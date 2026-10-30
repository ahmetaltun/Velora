import SwiftUI

/// Shared Bloom header for Velora's cleanup, security and utility screens.
/// Drop-in replacement for ToolHeaderView; the existing action closures are kept.
public struct BloomToolHeaderView<Actions: View>: View {
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let accentColor: Color
    private let actions: Actions

    public init(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.actions = actions()
    }

    public init(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color
    ) where Actions == EmptyView {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, accentColor: accentColor) {
            EmptyView()
        }
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 15) {
                identity
                Spacer(minLength: 16)
                actions
            }
            VStack(alignment: .leading, spacing: 14) {
                identity
                actions
            }
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [VeloraTheme.obsidianElevated, VeloraTheme.obsidianSurface.opacity(0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VeloraTheme.cardBorder)
                .frame(height: 1)
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 45, height: 45)
                .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.20), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .tracking(-0.55)
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VeloraTheme.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}
