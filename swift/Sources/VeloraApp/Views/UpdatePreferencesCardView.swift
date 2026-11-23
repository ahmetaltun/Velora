import SwiftUI

public struct UpdatePreferencesCardView: View {
    @ObservedObject private var updateManager = VeloraUpdateManager.shared

    public init() {}

    private var formattedLastCheck: String {
        updateManager.lastUpdateCheckDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Label("Software Updates", systemImage: "arrow.clockwise.circle")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                Button {
                    updateManager.checkForUpdates()
                } label: {
                    if updateManager.isChecking {
                        ProgressView("Checking…").controlSize(.small)
                    } else {
                        Text("Check Now")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!updateManager.canCheckForUpdates || updateManager.isChecking)
            }

            VStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { updateManager.automaticallyChecksForUpdates },
                    set: { updateManager.setAutomaticallyChecksForUpdates($0) }
                )) {
                    preferenceLabel("Check automatically", detail: "Check daily and notify me when an update is available.")
                }

                Divider().overlay(VeloraTheme.cardBorder)

                Toggle(isOn: Binding(
                    get: { updateManager.automaticallyDownloadsUpdates },
                    set: { updateManager.setAutomaticallyDownloadsUpdates($0) }
                )) {
                    preferenceLabel("Download automatically", detail: "Download available updates and ask before relaunching.")
                }
                .disabled(!updateManager.automaticallyChecksForUpdates)
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Text(updateManager.currentVersionString)
                Spacer()
                Text("Last checked: \(formattedLastCheck)")
            }
            .font(.caption)
            .foregroundStyle(VeloraTheme.textSecondary)
        }
        .padding(18)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(VeloraTheme.cardBorder))
    }

    private func preferenceLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(VeloraTheme.textSecondary)
        }
    }
}
