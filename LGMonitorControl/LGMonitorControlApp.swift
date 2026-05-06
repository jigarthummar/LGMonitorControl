import SwiftUI

@main
struct LGMonitorControlApp: App {
    @StateObject private var controller = MonitorController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(controller)
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}
