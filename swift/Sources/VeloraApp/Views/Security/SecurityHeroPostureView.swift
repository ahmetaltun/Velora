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

    private var isClean: Bool {
        activeThreatCount == 0
    }

    private var statusColor: Color {
        isClean ? VeloraTheme.accentEmerald : VeloraTheme.accentPink
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(VeloraTheme.obsidianElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            isClean
                                ? VeloraTheme.accentEmerald.opacity(0.35)
                                : VeloraTheme.accentPink.opacity(0.4),
                            lineWidth: 1
                        )
                )

            // Ambient background glow
            RadialGradient(
                colors: [
                    statusColor.opacity(0.16),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 260
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 16) {
                // Top row: Shield + Posture Grade + Actions
                HStack(alignment: .center, spacing: 18) {
                    // Shield Badge with Glow
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.16))
                            .frame(width: 58, height: 58)

                        Circle()
                            .stroke(statusColor.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 66, height: 66)

                        Image(systemName: isClean ? "shield.checkered" : "exclamationmark.shield.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(statusColor)
                    }

                    // Status Copy & Grade Badge
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(isClean ? "System Fortified & Secure" : "\(activeThreatCount) Security Anomaly Detected")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)

                            // Grade Pill
                            HStack(spacing: 4) {
                                Image(systemName: isClean ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text(isClean ? "GRADE A+ SECURE" : "ACTION REQUIRED")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor.opacity(0.15), in: Capsule())
                            .overlay(Capsule().stroke(statusColor.opacity(0.35), lineWidth: 1))
                        }

                        Text(isClean
                            ? "All \(summary.totalAsepInspected) boot persistence agents verified. Zero malicious IOC hashes or unauthorized daemons found."
                            : "Suspicious boot persistence items or unsigned binaries detected. Review and quarantine threats below.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 10) {
                        if !isClean, let onQuarantineAll = onQuarantineAll {
                            Button(action: onQuarantineAll) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Quarantine All (\(activeThreatCount))")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [VeloraTheme.accentPink, Color(hex: "#DC2626")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: Capsule()
                                )
                                .shadow(color: VeloraTheme.accentPink.opacity(0.4), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: onRescan) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Rescan")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(VeloraTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(VeloraTheme.obsidianSurface, in: Capsule())
                            .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                    .overlay(VeloraTheme.cardBorder)

                // Bottom row: Real-time Telemetry Metrics
                HStack(spacing: 12) {
                    telemetryCard(
                        title: "Persistence Audited",
                        value: "\(summary.totalAsepInspected)",
                        caption: "LaunchAgents & Daemons",
                        color: VeloraTheme.accentCyan
                    )

                    telemetryCard(
                        title: "In-Memory Candidates",
                        value: "\(summary.totalCandidatesTriaged)",
                        caption: "Catalog Triaged",
                        color: VeloraTheme.accentViolet
                    )

                    telemetryCard(
                        title: "Audit Latency",
                        value: "\(summary.scanDurationMs) ms",
                        caption: "Sub-10ms Target",
                        color: VeloraTheme.accentEmerald
                    )

                    telemetryCard(
                        title: "Storage Engine",
                        value: "Zero-Disk-I/O",
                        caption: "In-RAM Traversal",
                        color: VeloraTheme.accentAmber
                    )
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func telemetryCard(title: String, value: String, caption: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(color)

            Text(caption)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundColor(VeloraTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
