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

    // Coalescing dispatcher state. Each property keeps the latest target value
    // the user has dragged to, plus a flag indicating whether a write loop is
    // currently running. This lets us track the slider live without queueing
    // intermediate values behind the slow DDC bus.
    private var pendingBrightness: Double? = nil
    private var brightnessWriting = false
    private var pendingContrast: Double? = nil
    private var contrastWriting = false
    private var pendingVolume: Double? = nil
    private var volumeWriting = false
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
        pendingBrightness = brightness
        if brightnessWriting { return }
        brightnessWriting = true
        Task { [weak self] in
            guard let self else { return }
            while let v = self.pendingBrightness {
                self.pendingBrightness = nil
                do { try await DDC.set(self.id, "luminance", Int(v.rounded())) }
                catch { self.report(error); break }
            }
            self.brightnessWriting = false
        }
    }

    func commitContrast() {
        guard !suppressWrites, contrastSupported else { return }
        pendingContrast = contrast
        if contrastWriting { return }
        contrastWriting = true
        Task { [weak self] in
            guard let self else { return }
            while let v = self.pendingContrast {
                self.pendingContrast = nil
                do { try await DDC.set(self.id, "contrast", Int(v.rounded())) }
                catch { self.report(error); break }
            }
            self.contrastWriting = false
        }
    }

    func commitVolume() {
        guard !suppressWrites, volumeSupported else { return }
        pendingVolume = volume
        if volumeWriting { return }
        volumeWriting = true
        Task { [weak self] in
            guard let self else { return }
            while let v = self.pendingVolume {
                self.pendingVolume = nil
                let intValue = Int(v.rounded())
                do {
                    try await DDC.set(self.id, "volume", intValue)
                    if intValue > 0, self.muted { self.muted = false }
                } catch { self.report(error); break }
            }
            self.volumeWriting = false
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
