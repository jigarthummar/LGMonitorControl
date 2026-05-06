import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @EnvironmentObject var manager: MonitorManager
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            if !manager.isInstalled {
                installPrompt
            } else if manager.displays.isEmpty {
                emptyState
            } else {
                monitorPicker
                Divider().background(Color.claudeBorder)
                if let controller = manager.selectedController {
                    DisplayControlsView(controller: controller)
                        .id(controller.id)   // ensure subview re-evaluates per-display
                }
            }

            Divider().background(Color.claudeBorder)
            footer
        }
        .frame(width: 320)
        .background(Color.claudeCream)
        .task { await manager.discover() }
    }

    private var monitorPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "display")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.claudeAccent)
            Text("Monitor")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(Color.claudeText)
            Spacer()
            Menu {
                ForEach(manager.displays) { display in
                    Button {
                        manager.select(display.id)
                        if let c = manager.selectedController {
                            Task { await c.refresh() }
                        }
                    } label: {
                        if display.id == manager.selectedID {
                            Label(display.displayName, systemImage: "checkmark")
                        } else {
                            Text(display.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(manager.selectedController?.displayName ?? "—")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.claudeText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.claudeSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.claudeSurface)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.claudeBorder, lineWidth: 1))
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Circle()
                .fill((manager.selectedController?.isReachable ?? false)
                      ? Color.green
                      : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var installPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.claudeAccent)
            Text("m1ddc is not installed")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.claudeText)
            Text("Run in Terminal:")
                .font(.caption)
                .foregroundStyle(Color.claudeSecondary)
            Text("brew install m1ddc")
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.claudeSurface)
                .cornerRadius(4)
                .foregroundStyle(Color.claudeText)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "display.slash")
                .font(.system(size: 22))
                .foregroundStyle(Color.claudeSecondary)
            Text("No external displays detected")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.claudeText)
            Text("m1ddc cannot control built-in panels or the HDMI port on entry M1/M2 Macs.")
                .font(.caption2)
                .foregroundStyle(Color.claudeSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button("Rescan") {
                Task { await manager.discover() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.claudeAccent)
            .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack {
            Toggle(isOn: $launchAtLogin) {
                Text("Launch at login")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.claudeSecondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Color.claudeAccent)
            .onChange(of: launchAtLogin) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin.toggle()
                }
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.claudeSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct DisplayControlsView: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        Group {
            if controller.isReachable {
                controls
            } else {
                unreachable
            }
        }
        .task { await controller.refresh() }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            ThemedSlider(
                title: "Brightness",
                systemImage: "sun.max.fill",
                value: $controller.brightness,
                onCommit: { controller.commitBrightness() }
            )
            .disabled(!controller.brightnessSupported)

            ThemedSlider(
                title: "Contrast",
                systemImage: "circle.lefthalf.filled",
                value: $controller.contrast,
                onCommit: { controller.commitContrast() }
            )
            .disabled(!controller.contrastSupported)

            ThemedSlider(
                title: "Volume",
                systemImage: controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                value: $controller.volume,
                onCommit: { controller.commitVolume() },
                iconAction: { controller.toggleMute() }
            )
            .disabled(!controller.volumeSupported)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var unreachable: some View {
        VStack(spacing: 8) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(Color.claudeSecondary)
            Text("Display not reachable")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.claudeText)
            if let err = controller.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(Color.claudeSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Retry") {
                Task { await controller.refresh() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.claudeAccent)
            .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }
}
