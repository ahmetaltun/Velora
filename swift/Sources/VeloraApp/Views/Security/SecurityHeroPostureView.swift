import SwiftUI
import VeloraCore

public struct SecurityHeroPostureView: View {
    public let summary: SecuritySummaryRecord
    public let activeThreatCount: Int

    public init(
        summary: SecuritySummaryRecord,
        activeThreatCount: Int
    ) {
        self.summary = summary
        self.activeThreatCount = activeThreatCount
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(VeloraTheme.cardBorder))
    }
}
