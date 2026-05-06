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

    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.claudeSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.claudeText)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.claudeSecondary)
                    .monospacedDigit()
            }
            CustomSlider(value: $value, range: range, isDragging: $isDragging)
                .frame(height: 18)
                .onChange(of: value) { _, _ in
                    onCommit()
                }
                .onChange(of: isDragging) { _, dragging in
                    if !dragging { onCommit() }
                }
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Binding var isDragging: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let pct = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let fill = max(0, min(width, width * pct))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.claudeBorder)
                    .frame(height: 6)
                Capsule()
                    .fill(Color.claudeAccent)
                    .frame(width: fill, height: 6)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.claudeAccent, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.08), radius: 1, y: 1)
                    .offset(x: fill - 8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        isDragging = true
                        let raw = max(0, min(width, g.location.x)) / width
                        value = range.lowerBound + Double(raw) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}
