import SwiftUI

extension Color {
    static let claudeCream     = Color(red: 0xFA/255, green: 0xF9/255, blue: 0xF5/255)
    static let claudeSurface   = Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE8/255)
    static let claudeAccent    = Color(red: 0xC9/255, green: 0x64/255, blue: 0x42/255)
    static let claudeText      = Color(red: 0x3D/255, green: 0x39/255, blue: 0x29/255)
    static let claudeSecondary = Color(red: 0x6B/255, green: 0x65/255, blue: 0x57/255)
    static let claudeBorder    = Color(red: 0xE6/255, green: 0xDF/255, blue: 0xD3/255)
}

struct ThemedSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let onCommit: () -> Void
    var range: ClosedRange<Double> = 0...100
    var iconAction: (() -> Void)? = nil

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Group {
                    if let iconAction {
                        Button(action: iconAction) {
                            Image(systemName: systemImage)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: systemImage)
                    }
                }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.claudeSecondary : Color.claudeBorder)
                    .frame(width: 16)
                Text(title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(isEnabled ? Color.claudeText : Color.claudeSecondary.opacity(0.5))
                Spacer()
                if isEnabled {
                    Text("\(Int(value.rounded()))")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.claudeSecondary)
                        .monospacedDigit()
                } else {
                    Text("not supported")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.claudeSecondary.opacity(0.6))
                }
            }
            Slider(value: $value, in: range, onEditingChanged: { editing in
                if !editing { onCommit() }
            })
            .tint(isEnabled ? Color.claudeAccent : Color.claudeBorder)
            .controlSize(.small)
            .onChange(of: value) { _, _ in onCommit() }
        }
    }
}
