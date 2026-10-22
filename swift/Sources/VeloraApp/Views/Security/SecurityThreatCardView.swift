import AppKit
import SwiftUI
import VeloraCore

public struct SecurityThreatCardView: View {
    public let threat: SecurityThreatRecord
    public let isQuarantined: Bool
    public let onQuarantine: () -> Void
    public let onRestore: () -> Void

    @State private var copiedPath = false
    @State private var copiedHash = false

    public init(
        threat: SecurityThreatRecord,
        isQuarantined: Bool,
        onQuarantine: @escaping () -> Void,
        onRestore: @escaping () -> Void
    ) {
        self.threat = threat
        self.isQuarantined = isQuarantined
        self.onQuarantine = onQuarantine
        self.onRestore = onRestore
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(VeloraTheme.obsidianSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isQuarantined
                                ? VeloraTheme.accentEmerald.opacity(0.3)
                                : Color(hex: threat.severityColorHex).opacity(0.35),
                            lineWidth: 1
                        )
                )

            VStack(alignment: .leading, spacing: 12) {
                // Top Row: Title, Severity Pill, Category Pill, Action
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(threat.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(VeloraTheme.textPrimary)

                            // Severity Pill
                            Text(threat.severityName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(hex: threat.severityColorHex), in: Capsule())

                            // Category Pill
                            Text(threat.categoryName)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(VeloraTheme.obsidianElevated, in: Capsule())
                                .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))

                            if isQuarantined {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Quarantined")
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(VeloraTheme.accentEmerald)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(VeloraTheme.accentEmerald.opacity(0.15), in: Capsule())
                            }
                        }

                        Text(threat.description)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                    }

                    Spacer()

                    // Action Button
                    if isQuarantined {
                        Button(action: onRestore) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Restore")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: onQuarantine) {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.shield")
                                Text("Quarantine")
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [VeloraTheme.accentPink, Color(hex: "#DC2626")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .shadow(color: VeloraTheme.accentPink.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Middle Row: File Path & Quick Actions
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(VeloraTheme.textMuted)

                    Text(threat.targetPath)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // Copy Path Button
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(threat.targetPath, forType: .string)
                        copiedPath = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedPath = false
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: copiedPath ? "checkmark" : "doc.on.doc")
                            Text(copiedPath ? "Copied" : "Copy")
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(copiedPath ? VeloraTheme.accentEmerald : VeloraTheme.textMuted)
                    }
                    .buttonStyle(.plain)

                    // Reveal in Finder Button
                    Button(action: {
                        let url = URL(fileURLWithPath: threat.targetPath)
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.forward.square")
                            Text("Reveal")
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 6))

                Divider()
                    .overlay(VeloraTheme.cardBorder)

                // Bottom Row: Telemetry & Signature Badges
                HStack(spacing: 16) {
                    // Size
                    if threat.fileSize > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "scalemass")
                                .font(.system(size: 10))
                                .foregroundColor(VeloraTheme.textMuted)
                            Text(formatBytes(threat.fileSize))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                    }

                    // Signing Status
                    HStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.system(size: 10))
                            .foregroundColor(VeloraTheme.textMuted)
                        Text(threat.signingStatus)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                    }

                    // Detection Method
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10))
                            .foregroundColor(VeloraTheme.textMuted)
                        Text(threat.detectionMethod)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                    }

                    Spacer()

                    // SHA-256 Hash Copy
                    if !threat.sha256Hex.isEmpty {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(threat.sha256Hex, forType: .string)
                            copiedHash = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedHash = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: copiedHash ? "checkmark" : "number")
                                    .font(.system(size: 9))
                                Text(copiedHash ? "Hash Copied" : "SHA: \(String(threat.sha256Hex.prefix(8)))…")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(copiedHash ? VeloraTheme.accentEmerald : VeloraTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .help(threat.sha256Hex)
                    }
                }
            }
            .padding(14)
        }
    }
}
