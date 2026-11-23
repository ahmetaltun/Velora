import SwiftUI
import VeloraCore

public struct SecurityHeroPostureView: View {
    public let summary: SecuritySummaryRecord
    public let activeThreatCount: Int
    public let onRescan: () -> Void
    public let onQuarantineAll: (() -> Void)?

    public init(
        summary: SecuritySummaryRecord,
        activeThreatCount: Int,
        onRescan: @escaping () -> Void,
        onQuarantineAll: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.activeThreatCount = activeThreatCount
        self.onRescan = onRescan
        self.onQuarantineAll = onQuarantineAll
    }

    public var body: some View {
        let isClean = activeThreatCount == 0
        let accent = isClean ? VeloraTheme.accentEmerald : VeloraTheme.accentPink

        VStack(alignment: .leading, spacing: 13) {
            Label(
                isClean ? "No threats flagged" : "\(activeThreatCount.formatted()) flagged",
                systemImage: isClean ? "checkmark.shield" : "exclamationmark.shield"
            )
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .foregroundStyle(accent)
            .accessibilityAddTraits(.isHeader)

            ToolMetrics {
                ToolMetricCardView(title: "Startup items inspected", value: summary.totalAsepInspected.formatted(),
                                   accentColor: VeloraTheme.accentCyan)
                ToolMetricCardView(title: "Catalog candidates", value: summary.totalCandidatesTriaged.formatted())
                ToolMetricCardView(title: "Scan duration", value: "\(summary.scanDurationMs.formatted()) ms",
                                   accentColor: VeloraTheme.textPrimary)
            }

            HStack(spacing: 8) {
                Button("Rescan", systemImage: "arrow.clockwise", action: onRescan)
                    .buttonStyle(.bordered)
                if !isClean, let onQuarantineAll {
                    Button("Quarantine Flagged Items…", systemImage: "lock.shield", action: onQuarantineAll)
                        .buttonStyle(.bordered)
                        .tint(VeloraTheme.accentPink)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(VeloraTheme.cardBorder))
    }
}
