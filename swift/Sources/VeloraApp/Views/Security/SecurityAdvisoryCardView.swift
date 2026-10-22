import SwiftUI

public struct SecurityAdvisoryCardView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15))
                    .foregroundColor(VeloraTheme.accentAmber)

                Text("macOS Security & Hygiene Advisories")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Spacer()
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                tipTile(
                    title: "Gatekeeper & Notarization",
                    icon: "checkmark.seal.fill",
                    accent: VeloraTheme.accentEmerald,
                    description: "Avoid executing unsigned binaries outside the Mac App Store. Always check Developer ID verification."
                )

                tipTile(
                    title: "Background Items Hygiene",
                    icon: "gearshape.2.fill",
                    accent: VeloraTheme.accentCyan,
                    description: "Prune legacy helpers in macOS System Settings > Login Items to minimize attack surface and memory load."
                )

                tipTile(
                    title: "System Integrity Protection",
                    icon: "shield.lefthalf.filled",
                    accent: VeloraTheme.accentViolet,
                    description: "Keep SIP active to safeguard system namespaces (/System, /usr, /bin) against root-level persistent modifications."
                )
            }
        }
        .padding(16)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func tipTile(
        title: String,
        icon: String,
        accent: Color,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)
            }

            Text(description)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VeloraTheme.cardBorder, lineWidth: 1))
    }
}
