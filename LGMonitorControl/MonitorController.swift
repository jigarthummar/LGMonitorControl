import Foundation
import AppKit
import Combine

enum InputSource: Int, CaseIterable, Identifiable {
    case hdmi1 = 144
    case hdmi2 = 145
    case displayPort1 = 208
    case displayPort2 = 209
    case usbC = 210

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .usbC: return "USB-C"
        }
    }
}

@MainActor
final class MonitorController: ObservableObject {
    @Published var brightness: Double = 50
    @Published var contrast: Double = 50
    @Published var volume: Double = 50
    @Published var muted: Bool = false
    @Published var currentInput: InputSource? = nil
    @Published var isReachable: Bool = false
    @Published var isInstalled: Bool = DDC.isInstalled
    @Published var lastError: String? = nil

    private var brightnessTask: Task<Void, Never>? = nil
    private var contrastTask: Task<Void, Never>? = nil
    private var volumeTask: Task<Void, Never>? = nil
    private var suppressWrites = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await DDC.shared.invalidate()
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        isInstalled = DDC.isInstalled
        guard isInstalled else {
            isReachable = false
            return
        }
        do {
            async let b = DDC.getInt("luminance")
            async let c = DDC.getInt("contrast")
            async let v = DDC.getInt("volume")
            let (bv, cv, vv) = try await (b, c, v)
            suppressWrites = true
            brightness = Double(bv)
            contrast = Double(cv)
            volume = Double(vv)
            muted = (vv == 0)
            suppressWrites = false
            isReachable = true
            lastError = nil
        } catch {
            isReachable = false
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    func commitBrightness() {
        guard !suppressWrites else { return }
        brightnessTask?.cancel()
        let value = Int(brightness.rounded())
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            do { try await DDC.set("luminance", value) }
            catch { self?.report(error) }
        }
    }

    func commitContrast() {
        guard !suppressWrites else { return }
        contrastTask?.cancel()
        let value = Int(contrast.rounded())
        contrastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            do { try await DDC.set("contrast", value) }
            catch { self?.report(error) }
        }
    }

    func commitVolume() {
        guard !suppressWrites else { return }
        volumeTask?.cancel()
        let value = Int(volume.rounded())
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            do {
                try await DDC.set("volume", value)
                if value > 0, self?.muted == true {
                    self?.muted = false
                }
            } catch { self?.report(error) }
        }
    }

    func toggleMute() {
        let target = !muted
        muted = target
        Task { [weak self] in
            do { try await DDC.setMute(target) }
            catch { self?.report(error) }
        }
    }

    func setInput(_ input: InputSource) {
        currentInput = input
        Task { [weak self] in
            do { try await DDC.setInputAlt(input.rawValue) }
            catch { self?.report(error) }
        }
    }

    private func report(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
