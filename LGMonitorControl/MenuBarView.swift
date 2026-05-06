import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @EnvironmentObject var controller: MonitorController
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.claudeBorder)

            if !controller.isInstalled {
                installPrompt
            } else if !controller.isReachable {
                unreachable
            } else {
                controls
            }

            Divider().background(Color.claudeBorder)
            footer
        }
        .frame(width: 300)
        .background(Color.claudeCream)
        .task { await controller.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "display")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.claudeAccent)
            Text("LG 27UP850-W")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.claudeText)
            Spacer()
            Circle()
                .fill(controller.isReachable ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            ThemedSlider(
                title: "Brightness",
                systemImage: "sun.max.fill",
                value: $controller.brightness,
                onCommit: { controller.commitBrightness() }
            )
            ThemedSlider(
                title: "Contrast",
                systemImage: "circle.lefthalf.filled",
                value: $controller.contrast,
                onCommit: { controller.commitContrast() }
            )
            HStack(spacing: 8) {
                Button {
                    controller.toggleMute()
                } label: {
                    Image(systemName: controller.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(controller.muted ? Color.claudeAccent : Color.claudeSecondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(controller.muted ? "Unmute" : "Mute")
                ThemedSlider(
                    title: "Volume",
                    systemImage: "speaker.wave.2.fill",
                    value: $controller.volume,
                    onCommit: { controller.commitVolume() }
                )
            }

            HStack {
                Text("Input")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.claudeText)
                Spacer()
                Picker("", selection: Binding(
                    get: { controller.currentInput ?? .usbC },
                    set: { controller.setInput($0) }
                )) {
                    ForEach(InputSource.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Color.claudeAccent)
                .frame(width: 140)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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

    private var unreachable: some View {
        VStack(spacing: 8) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 22))
                .foregroundStyle(Color.claudeSecondary)
            Text("Monitor not reachable")
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
