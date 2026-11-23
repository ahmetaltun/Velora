import SwiftUI

struct LinearStorageGaugeCardView: View {
    let totalBytes: UInt64
    let freeBytes: UInt64

    private var usedBytes: UInt64 { totalBytes - freeBytes }
    private var usedRatio: Double { Double(usedBytes) / Double(totalBytes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Startup Disk", systemImage: "internaldrive")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(VeloraTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 3) {
                Text(formatBytes(freeBytes))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("Available · \(formatBytes(totalBytes)) total")
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.textSecondary)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.white.opacity(0.10))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(VeloraTheme.storageGauge)
                                .frame(width: geometry.size.width * usedRatio)
                        }
                }
                .frame(height: 8)
                .accessibilityHidden(true)

                HStack(spacing: 12) {
                    Text("\(formatBytes(usedBytes)) used")
                    Spacer(minLength: 0)
                    Text(usedRatio.formatted(.percent.precision(.fractionLength(0))))
                        .accessibilityLabel("Storage used")
                        .accessibilityValue(usedRatio.formatted(.percent.precision(.fractionLength(0))))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(VeloraTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
