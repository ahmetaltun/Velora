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
            HStack(alignment: .center, spacing: 20) {
                identity
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                actions
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                identity
                ScrollView(.horizontal) {
                    actions.fixedSize()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VeloraTheme.cardBorder)
                .frame(height: 1)
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 38, height: 38)
                .background(accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(VeloraTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
