import SwiftUI

public struct ToolHeaderView<Actions: View>: View {
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let accentColor: Color
    public let actions: Actions

    public init(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.actions = actions()
    }

    public var body: some View {
        BloomToolHeaderView(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accentColor: accentColor
        ) {
            actions
        }
    }
}

public struct ToolMetricCardView: View {
    public let title: String
    public let value: String
    public var accentColor: Color

    public init(title: String, value: String, accentColor: Color = VeloraTheme.accentViolet) {
        self.title = title
        self.value = value
        self.accentColor = accentColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
        )
    }
}

public struct ToolFilterChip: View {
    public let title: String
    public let isSelected: Bool
    public var accentColor: Color
    public let action: () -> Void

    public init(
        title: String,
        isSelected: Bool,
        accentColor: Color = VeloraTheme.accentViolet,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.accentColor = accentColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? VeloraTheme.textPrimary : VeloraTheme.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(
                    isSelected ? accentColor.opacity(0.22) : VeloraTheme.obsidianElevated,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isSelected ? accentColor.opacity(0.48) : VeloraTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: isSelected ? accentColor.opacity(0.25) : Color.clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}
