import SwiftUI

public struct MetricPillView: View {
    public var icon: String
    public var value: String
    public var unit: String
    public var tintColor: Color

    public init(
        icon: String,
        value: String,
        unit: String,
        tintColor: Color = VeloraTheme.mint
    ) {
        self.icon = icon
        self.value = value
        self.unit = unit
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tintColor)

            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.primary)

            Text(unit)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(tintColor.opacity(0.2), lineWidth: 0.8)
        )
    }
}
