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
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(minWidth: 130, maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 12))
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

struct ToolPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .background(VeloraTheme.obsidianBase)
    }
}

struct ToolMetrics<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                content
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                content
            }
        }
    }
}

struct ToolSearchField: View {
    let prompt: String
    @Binding var query: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VeloraTheme.textSecondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel(prompt)

            if !query.isEmpty {
                Button("Clear Filter", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(VeloraTheme.textSecondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(VeloraTheme.cardBorder))
    }
}

struct ToolFilterOption<Selection: Hashable> {
    let title: String
    let value: Selection

    init(_ title: String, _ value: Selection) {
        self.title = title
        self.value = value
    }
}

struct ToolFilterBar<Selection: Hashable>: View {
    var title = "Category"
    let prompt: String
    @Binding var selection: Selection
    @Binding var query: String
    var summary: String? = nil
    let options: [ToolFilterOption<Selection>]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                picker
                search.frame(minWidth: 120, idealWidth: 200, maxWidth: .infinity)
                if let summary {
                    summaryLabel(summary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    picker
                    Spacer(minLength: 0)
                    if let summary {
                        summaryLabel(summary)
                    }
                }
                search
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(VeloraTheme.obsidianElevated.opacity(0.5))
        .overlay(alignment: .bottom) { Divider().overlay(VeloraTheme.cardBorder) }
    }

    private var picker: some View {
        let selectedTitle = options.first { $0.value == selection }?.title ?? title

        return ToolDropdown(
            title: selectedTitle,
            accessibilityTitle: title,
            items: options.map { option in
                .command(option.title, selected: option.value == selection) { selection = option.value }
            }
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private var search: some View {
        ToolSearchField(prompt: prompt, query: $query)
    }

    private func summaryLabel(_ summary: String) -> some View {
        Text(summary)
            .font(.caption.monospacedDigit())
            .foregroundStyle(VeloraTheme.textSecondary)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct ToolStatusView: View {
    let title: String
    var message: String? = nil
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(VeloraTheme.accentViolet)
                    .frame(width: 34, height: 34)
                    .background(VeloraTheme.accentViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            } else {
                ProgressView().controlSize(.small)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(VeloraTheme.textPrimary)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(VeloraTheme.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VeloraTheme.cardBorder))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }
}
