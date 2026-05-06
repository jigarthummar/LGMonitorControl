import Foundation
import AppKit
import Combine

@MainActor
final class MonitorManager: ObservableObject {
    @Published private(set) var displays: [DisplayController] = []
    @Published var selectedID: String?
    @Published var isInstalled: Bool = DDC.isInstalled
    @Published var lastDiscoveryError: String? = nil

    private static let selectedKey = "selectedDisplayID"

    init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await DDC.shared.invalidate()
                await self?.discover()
            }
        }
    }

    var selectedController: DisplayController? {
        guard let selectedID else { return displays.first }
        return displays.first(where: { $0.id == selectedID }) ?? displays.first
    }

    func select(_ id: String) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: Self.selectedKey)
    }

    func discover() async {
        isInstalled = DDC.isInstalled
        guard isInstalled else {
            displays = []
            return
        }
        let detected: [Display]
        do {
            detected = try await DDC.shared.listDisplays()
            lastDiscoveryError = nil
        } catch {
            lastDiscoveryError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            detected = []
        }

        // Reuse existing controllers when their UUID still appears, so slider
        // state and tasks survive a re-discover (e.g. on hot-plug of a *different*
        // monitor).
        var byID: [String: DisplayController] = [:]
        for c in displays { byID[c.id] = c }

        let rebuilt = detected.map { d -> DisplayController in
            byID[d.uuid] ?? DisplayController(display: d)
        }
        displays = rebuilt

        // Make sure the selection is still valid.
        if let sel = selectedID, !rebuilt.contains(where: { $0.id == sel }) {
            selectedID = rebuilt.first?.id
            if let sel = selectedID {
                UserDefaults.standard.set(sel, forKey: Self.selectedKey)
            }
        } else if selectedID == nil, let first = rebuilt.first?.id {
            selectedID = first
        }

        // Refresh state for displays that haven't been read yet (or are stale).
        for controller in rebuilt where !controller.isReachable {
            await controller.refresh()
        }
    }

    /// Refresh just the currently-selected display (called when the popover opens).
    func refreshSelected() async {
        await selectedController?.refresh()
    }
}
