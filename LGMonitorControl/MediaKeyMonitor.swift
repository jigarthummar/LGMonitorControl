import Cocoa
import ApplicationServices

// IOKit's NX_SYSDEFINED event type — not exposed as a case on Swift's
// CGEventType enum, but valid as a raw value for tap registration.
private let systemDefinedEventType: UInt32 = 14

// CGEventTap callbacks must be plain C functions, so this lives at file scope
// and recovers `self` from the userInfo pointer the tap carries for us.
private func mediaKeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    cgEvent: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let unretained = Unmanaged<CGEvent>.passUnretained(cgEvent)

    // macOS disables the tap if our callback runs too long, or in some other
    // edge cases — we re-enable it and pass the event through unchanged.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in monitor.reEnable() }
        }
        return unretained
    }

    guard type.rawValue == systemDefinedEventType,
          let userInfo,
          let nsEvent = NSEvent(cgEvent: cgEvent),
          nsEvent.subtype.rawValue == 8     // NSSystemDefined media-keys subtype
    else { return unretained }

    let keyCode = (nsEvent.data1 & 0xFFFF0000) >> 16
    let keyState = (nsEvent.data1 & 0x0000FF00) >> 8
    guard keyState == 0xA else { return unretained }   // act only on key-down

    let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let consumed = monitor.handleKeyDown(keyCode: Int(keyCode))
    return consumed ? nil : unretained
}

/// Captures the volume keys (F10 mute / F11 down / F12 up) at the session
/// level and dispatches them to the currently-selected `DisplayController`
/// as DDC volume changes — even when another app is frontmost.
///
/// Implemented with a `CGEventTap` rather than `NSEvent.addGlobalMonitor…`
/// because the latter sits *after* macOS's media-key routing layer and only
/// fires when our app is frontmost. The session-level tap intercepts events
/// before any app-level routing decision, at the cost of requiring
/// **Accessibility** permission (Privacy & Security → Accessibility).
@MainActor
final class MediaKeyMonitor {
    private static let keyTypeSoundUp: Int = 0
    private static let keyTypeSoundDown: Int = 1
    private static let keyTypeMute: Int = 7

    /// One step is 1/16 of the 0–100 range, matching the granularity of the
    /// system volume HUD.
    private static let step: Double = 100.0 / 16.0

    weak var manager: MonitorManager?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryObserver: NSObjectProtocol?

    /// Whether the tap is currently installed. Read by the popover so it can
    /// surface a "Grant Accessibility" hint when this is false.
    var isActive: Bool { eventTap != nil }

    func start() {
        guard eventTap == nil else { return }

        // Triggers the macOS Accessibility prompt on first launch.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        installTap()

        if eventTap == nil {
            // Permission likely missing; retry whenever the user activates
            // any app — that's a cheap signal they may have just toggled
            // Accessibility in System Settings.
            retryObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.retryInstall() }
            }
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        if let retryObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(retryObserver)
        }
        retryObserver = nil
    }

    // MARK: - Tap lifecycle

    private func installTap() {
        let mask = UInt64(1) << UInt64(systemDefinedEventType)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: mediaKeyEventCallback,
            userInfo: userInfo
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    private func retryInstall() {
        guard eventTap == nil else { return }
        installTap()
        if eventTap != nil, let retryObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(retryObserver)
            self.retryObserver = nil
        }
    }

    fileprivate func reEnable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    // MARK: - Key dispatch

    /// Returns `true` when the key was a recognized media key and should be
    /// consumed (so the OS doesn't *also* forward it to whatever app would
    /// normally have received it).
    fileprivate nonisolated func handleKeyDown(keyCode: Int) -> Bool {
        switch keyCode {
        case Self.keyTypeSoundUp, Self.keyTypeSoundDown, Self.keyTypeMute:
            Task { @MainActor in self.dispatch(keyCode: keyCode) }
            return true
        default:
            return false
        }
    }

    private func dispatch(keyCode: Int) {
        guard let controller = manager?.selectedController,
              controller.volumeSupported else { return }
        switch keyCode {
        case Self.keyTypeSoundUp:
            controller.volume = min(100, controller.volume + Self.step)
            controller.commitVolume()
        case Self.keyTypeSoundDown:
            controller.volume = max(0, controller.volume - Self.step)
            controller.commitVolume()
        case Self.keyTypeMute:
            controller.toggleMute()
        default:
            break
        }
    }
}
