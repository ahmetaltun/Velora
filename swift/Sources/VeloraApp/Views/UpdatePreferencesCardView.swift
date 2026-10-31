import SwiftUI

public struct UpdatePreferencesCardView: View {
    @ObservedObject private var updateManager = VeloraUpdateManager.shared

    public init() {}

    private var formattedLastCheck: String {
        guard let date = updateManager.lastUpdateCheckDate else {
            return "Never"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VeloraTheme.accentViolet.opacity(0.18))
                        .frame(width: 36, height: 36)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(VeloraTheme.accentViolet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Software Updates")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)

                        Text(updateManager.currentVersionString)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(VeloraTheme.accentCyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(VeloraTheme.accentCyan.opacity(0.16))
                            )
                    }

                    Text("Secure in-place updates signed with Ed25519 and notarized by Apple.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()

                Button {
                    updateManager.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        if updateManager.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                        }

                        Text("Check Now")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(VeloraTheme.ctaGradient, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!updateManager.canCheckForUpdates || updateManager.isChecking)
            }

            Divider()
                .overlay(VeloraTheme.cardBorder)

            // Configuration Toggles & Status
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically check for updates")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)

                        Text("Checks daily in the background and notifies you when new releases are available.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(VeloraTheme.textMuted)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { updateManager.automaticallyChecksForUpdates },
                        set: { updateManager.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(VeloraTheme.accentViolet)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically download updates")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)

                        Text("Silently pre-downloads updates and prompts for a seamless relaunch when ready.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(VeloraTheme.textMuted)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { updateManager.automaticallyDownloadsUpdates },
                        set: { updateManager.setAutomaticallyDownloadsUpdates($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(VeloraTheme.accentViolet)
                    .disabled(!updateManager.automaticallyChecksForUpdates)
                }

                HStack {
                    Text("Last checked:")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textMuted)

                    Text(formattedLastCheck)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)

                    Spacer()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VeloraTheme.obsidianElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
        )
    }
}
