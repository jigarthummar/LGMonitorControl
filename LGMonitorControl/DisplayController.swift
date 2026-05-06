import Foundation
import AppKit
import Combine

@MainActor
final class DisplayController: ObservableObject, Identifiable {
    let id: String                  // display UUID
    let displayName: String
    let manufacturer: String

    @Published var brightness: Double = 50
    @Published var contrast: Double = 50
    @Published var volume: Double = 50
    @Published var muted: Bool = false

    @Published var brightnessSupported: Bool = true
    @Published var contrastSupported: Bool = true
    @Published var volumeSupported: Bool = true

    @Published var isReachable: Bool = false
    @Published var lastError: String? = nil

    private var brightnessTask: Task<Void, Never>? = nil
    private var contrastTask: Task<Void, Never>? = nil
    private var volumeTask: Task<Void, Never>? = nil
    private var suppressWrites = false

    init(display: Display) {
        self.id = display.uuid
        self.displayName = display.productName
        self.manufacturer = display.manufacturer
    }

    func refresh() async {
        guard DDC.isInstalled else {
            isReachable = false
            return
        }
        // Probe capabilities first (max returns 0 or errors when unsupported).
        let maxL = await DDC.maxInt(id, "luminance")
        let maxC = await DDC.maxInt(id, "contrast")
        let maxV = await DDC.maxInt(id, "volume")
        brightnessSupported = (maxL ?? 0) > 0
        contrastSupported = (maxC ?? 0) > 0
        volumeSupported = (maxV ?? 0) > 0

        var anySuccess = false
        var firstError: Error? = nil

        if brightnessSupported {
            do {
                let bv = try await DDC.getInt(id, "luminance")
                suppressWrites = true; brightness = Double(bv); suppressWrites = false
                anySuccess = true
            } catch { firstError = firstError ?? error }
        }
        if contrastSupported {
            do {
                let cv = try await DDC.getInt(id, "contrast")
                suppressWrites = true; contrast = Double(cv); suppressWrites = false
                anySuccess = true
            } catch { firstError = firstError ?? error }
        }
        if volumeSupported {
            do {
                let vv = try await DDC.getInt(id, "volume")
                suppressWrites = true
                volume = Double(vv)
                muted = (vv == 0)
                suppressWrites = false
                anySuccess = true
            } catch { firstError = firstError ?? error }
        }

        if anySuccess || (!brightnessSupported && !contrastSupported && !volumeSupported) {
            isReachable = true
            lastError = nil
        } else {
            isReachable = false
            lastError = (firstError as? LocalizedError)?.errorDescription ?? firstError.map { "\($0)" }
        }
    }

    func commitBrightness() {
        guard !suppressWrites, brightnessSupported else { return }
        brightnessTask?.cancel()
        let value = Int(brightness.rounded())
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            guard let self else { return }
            do { try await DDC.set(self.id, "luminance", value) }
            catch { self.report(error) }
        }
    }

    func commitContrast() {
        guard !suppressWrites, contrastSupported else { return }
        contrastTask?.cancel()
        let value = Int(contrast.rounded())
        contrastTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            guard let self else { return }
            do { try await DDC.set(self.id, "contrast", value) }
            catch { self.report(error) }
        }
    }

    func commitVolume() {
        guard !suppressWrites, volumeSupported else { return }
        volumeTask?.cancel()
        let value = Int(volume.rounded())
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            guard let self else { return }
            do {
                try await DDC.set(self.id, "volume", value)
                if value > 0, self.muted { self.muted = false }
            } catch { self.report(error) }
        }
    }

    func toggleMute() {
        guard volumeSupported else { return }
        let target = !muted
        muted = target
        Task { [weak self] in
            guard let self else { return }
            do { try await DDC.setMute(self.id, target) }
            catch { self.report(error) }
        }
    }

    private func report(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
