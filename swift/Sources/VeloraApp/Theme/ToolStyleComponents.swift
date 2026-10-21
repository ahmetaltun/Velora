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
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 38, height: 38)

                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            actions
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(VeloraTheme.obsidianElevated)
        .overlay(alignment: .bottom) {
            Divider().overlay(VeloraTheme.cardBorder)
        }
    }
}

public struct ToolMetricCardView: View {
    public let title: String
    public let value: String
    public var accentColor: Color

    public init(title: String, value: String, accentColor: Color = VeloraTheme.accentBlue) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
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
        accentColor: Color = VeloraTheme.accentBlue,
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
                .foregroundColor(isSelected ? .white : VeloraTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isSelected ? accentColor : VeloraTheme.obsidianElevated,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.white.opacity(0.18) : VeloraTheme.cardBorder, lineWidth: 1)
                )
                .shadow(color: isSelected ? accentColor.opacity(0.3) : Color.clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}
