import AppKit
import SwiftUI

public struct SecurityAsepInspectorView: View {
    public let totalInspected: UInt32

    public init(totalInspected: UInt32) {
        self.totalInspected = totalInspected
    }

    private var userLaunchAgentsPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .path
    }

    private let systemLaunchAgentsPath = "/Library/LaunchAgents"
    private let systemLaunchDaemonsPath = "/Library/LaunchDaemons"

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Explanation Card
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(VeloraTheme.accentCyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Start Execution Points (ASEP) Audit")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("Velora scans macOS persistence locations where background daemons register to execute automatically on boot or user session initiation.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()
            }
            .padding(14)
            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.cardBorder, lineWidth: 1))

            // 3 Scopes Grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                scopeCard(
                    title: "User LaunchAgents",
                    path: "~/Library/LaunchAgents",
                    fullPath: userLaunchAgentsPath,
                    role: "User Session Helpers",
                    description: "Per-user daemons loaded when you log into macOS.",
                    accent: VeloraTheme.accentCyan
                )

                scopeCard(
                    title: "System LaunchAgents",
                    path: "/Library/LaunchAgents",
                    fullPath: systemLaunchAgentsPath,
                    role: "Global User Daemons",
                    description: "Shared background daemons executed for all local users.",
                    accent: VeloraTheme.accentViolet
                )

                scopeCard(
                    title: "System LaunchDaemons",
                    path: "/Library/LaunchDaemons",
                    fullPath: systemLaunchDaemonsPath,
                    role: "Privileged Boot Daemons",
                    description: "Root-level background processes initiated during kernel boot.",
                    accent: VeloraTheme.accentAmber
                )
            }

            // Dual-Stage Verification Callout
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(VeloraTheme.accentEmerald.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(VeloraTheme.accentEmerald)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dual-Stage Integrity Verification")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("Every persistence plist is parsed to resolve target Mach-O binaries. Each binary is verified for cryptographic signature validity, Apple Developer ID notarization, and checked against the known malware IOC hash database.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()

                Text("\(totalInspected) Verified")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.accentEmerald)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(VeloraTheme.accentEmerald.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(VeloraTheme.accentEmerald.opacity(0.3), lineWidth: 1))
            }
            .padding(14)
            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.cardBorder, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func scopeCard(
        title: String,
        path: String,
        fullPath: String,
        role: String,
        description: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)
                Spacer()
                Text(role)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            Text(path)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(VeloraTheme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(description)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(VeloraTheme.accentEmerald)
                        .frame(width: 6, height: 6)
                    Text("Audited")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.accentEmerald)
                }

                Spacer()

                Button(action: {
                    let url = URL(fileURLWithPath: fullPath)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Reveal")
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(VeloraTheme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Open persistence folder in Finder")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
