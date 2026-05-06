import Cocoa

/// Listens for the volume keys (F10 mute / F11 down / F12 up) and forwards
/// them to the currently-selected `DisplayController` as DDC volume changes.
///
/// Uses an `NSEvent` global monitor for system-defined events. We don't
/// *consume* the event — macOS still tries to act on it for the system audio
/// output, but for monitors connected over DP/HDMI/USB-C the OS volume slider
/// is typically frozen ("digital fixed output"), so the OS-side action is a
/// no-op and only the DDC write takes effect.
///
/// First-time use will prompt the user for "Input Monitoring" permission
/// (Settings → Privacy & Security → Input Monitoring). The popover keeps
/// working without it; only the keys won't fire.
@MainActor
final class MediaKeyMonitor {
    // System-defined NSEvent subtype that carries media key info.
    private static let systemDefinedMediaKeys: Int16 = 8

    // Apple's NX_KEYTYPE_* constants for the media keys we care about.
    private static let keyTypeSoundUp: Int = 0
    private static let keyTypeSoundDown: Int = 1
    private static let keyTypeMute: Int = 7

    /// One step is 1/16 of the 0–100 range, matching the granularity of the
    /// system volume HUD.
    private static let step: Double = 100.0 / 16.0

    weak var manager: MonitorManager?

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            // The closure runs off-main; hop to main before touching state.
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.subtype.rawValue == Self.systemDefinedMediaKeys else { return }

        // The packed media-key payload lives in `data1`:
        //   bits 16..31 → key code   (which media key)
        //   bits  8..15 → key flags  (high byte: state — 0xA on key down)
        let keyCode = (event.data1 & 0xFFFF0000) >> 16
        let keyState = (event.data1 & 0x0000FF00) >> 8
        guard keyState == 0xA else { return }   // act only on key-down

        guard let controller = manager?.selectedController,
              controller.volumeSupported else { return }

        switch Int(keyCode) {
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
