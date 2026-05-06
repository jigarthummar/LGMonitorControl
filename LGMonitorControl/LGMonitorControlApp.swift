import SwiftUI

@main
struct LGMonitorControlApp: App {
    @StateObject private var manager = MonitorManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(manager)
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}
