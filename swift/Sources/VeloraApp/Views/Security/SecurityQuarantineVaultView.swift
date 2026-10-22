import AppKit
import SwiftUI
import VeloraCore

public struct SecurityQuarantineVaultView: View {
    public let quarantinedThreats: [SecurityThreatRecord]
    public let onRestore: (SecurityThreatRecord) -> Void

    public init(
        quarantinedThreats: [SecurityThreatRecord],
        onRestore: @escaping (SecurityThreatRecord) -> Void
    ) {
        self.quarantinedThreats = quarantinedThreats
        self.onRestore = onRestore
    }

    private var vaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Velora/Quarantine")
            .path
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Quarantine Sandbox Banner
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(VeloraTheme.accentAmber.opacity(0.18))
                        .frame(width: 40, height: 40)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundColor(VeloraTheme.accentAmber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Secure Quarantine Sandbox")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("Quarantined files are moved out of execution directories, stripped of execution permissions (chmod 000), and their launchctl daemons unloaded.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()

                Button(action: {
                    let url = URL(fileURLWithPath: vaultPath)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text("Reveal Vault")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Open Quarantine directory in Finder")
            }
            .padding(14)
            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.cardBorder, lineWidth: 1))

            // Quarantined Items List or Clean State
            if quarantinedThreats.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 20)

                    ZStack {
                        Circle()
                            .fill(VeloraTheme.accentEmerald.opacity(0.12))
                            .frame(width: 50, height: 50)

                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 22))
                            .foregroundColor(VeloraTheme.accentEmerald)
                    }

                    Text("Quarantine Vault is Empty")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("No suspicious executables or auto-start agents are currently isolated. When you quarantine an anomaly, it will be safely contained here.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(VeloraTheme.obsidianSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.cardBorder, lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(quarantinedThreats) { threat in
                        quarantinedRow(threat: threat)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quarantinedRow(threat: SecurityThreatRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(VeloraTheme.accentAmber.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(VeloraTheme.accentAmber)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(threat.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(threat.categoryName)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())

                    Text("Mode: 000 (Non-Executable)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(VeloraTheme.accentEmerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VeloraTheme.accentEmerald.opacity(0.12), in: Capsule())
                }

                Text(threat.targetPath)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(VeloraTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: {
                onRestore(threat)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Restore")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Restore binary and original permissions")
        }
        .padding(12)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
