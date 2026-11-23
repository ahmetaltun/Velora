import SwiftUI

struct ToolDropdown: View {
    enum Item {
        case command(String, selected: Bool = false, destructive: Bool = false, action: () -> Void)
        case separator
    }

    let title: String
    var icon: String? = nil
    var accessibilityTitle: String? = nil
    let items: [Item]
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(VeloraTheme.textSecondary)
                }
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(VeloraTheme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VeloraTheme.accentViolet)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(maxWidth: 230, minHeight: 30, alignment: .leading)
            .modifier(ToolControlSurface(accent: VeloraTheme.accentViolet))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityValue(accessibilityTitle == nil ? "" : title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ToolDropdownOptions(items: items) { isPresented = false }
                .presentationBackground(VeloraTheme.obsidianElevated)
        }
    }
}

private struct ToolDropdownOptions: View {
    let items: [ToolDropdown.Item]
    let dismiss: () -> Void
    @State private var highlighted: Int?
    @State private var contentHeight: CGFloat = 420
    @State private var contentWidth: CGFloat = 1
    @FocusState private var hasKeyboardFocus: Bool

    private var commandIndices: [Int] {
        items.indices.filter { if case .command = items[$0] { return true }; return false }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(items.indices, id: \.self) { index in
                        switch items[index] {
                        case let .command(title, selected, destructive, _):
                            Button { choose(index) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(VeloraTheme.accentViolet)
                                        .opacity(selected ? 1 : 0)
                                        .frame(width: 14)
                                    Text(title)
                                        .font(.system(.callout, design: .rounded, weight: selected ? .semibold : .medium))
                                        .foregroundStyle(destructive ? VeloraTheme.accentPink : VeloraTheme.textPrimary)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(highlighted == index ? VeloraTheme.accentViolet.opacity(0.20) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .onHover { hovering in
                                if hovering { highlighted = index }
                            }
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .id(index)
                        case .separator:
                            Divider().overlay(VeloraTheme.cardBorder).padding(.vertical, 4)
                        }
                    }
                }
                .padding(6)
                .fixedSize(horizontal: true, vertical: true)
                .onGeometryChange(for: CGSize.self) { geometry in
                    geometry.size
                } action: { size in
                    contentWidth = size.width.rounded(.up)
                    contentHeight = size.height.rounded(.up)
                }
            }
            .frame(width: contentWidth, height: min(420, contentHeight))
            .background(VeloraTheme.obsidianElevated)
            .focusable(interactions: [.activate, .edit])
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onAppear {
                highlighted = commandIndices.first { index in
                    if case let .command(_, selected, _, _) = items[index] { return selected }
                    return false
                } ?? commandIndices.first
                hasKeyboardFocus = true
            }
            .onChange(of: highlighted) { _, index in
                if let index { proxy.scrollTo(index) }
            }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.return) {
                if let highlighted { choose(highlighted) }
                return .handled
            }
            .onKeyPress(.space) {
                if let highlighted { choose(highlighted) }
                return .handled
            }
            .onExitCommand(perform: dismiss)
        }
    }

    private func move(_ offset: Int) {
        let indices = commandIndices
        guard !indices.isEmpty else { return }
        let current = highlighted.flatMap { indices.firstIndex(of: $0) } ?? 0
        highlighted = indices[(current + offset + indices.count) % indices.count]
    }

    private func choose(_ index: Int) {
        guard case let .command(_, _, _, action) = items[index] else { return }
        dismiss()
        action()
    }
}

struct ToolActionButtonStyle: ButtonStyle {
    var accent = VeloraTheme.accentViolet
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .foregroundStyle(prominent ? VeloraTheme.obsidianBase : VeloraTheme.textPrimary)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .modifier(ToolControlSurface(accent: accent, prominent: prominent, isPressed: configuration.isPressed))
    }
}

private struct ToolControlSurface: ViewModifier {
    let accent: Color
    var prominent = false
    var isPressed = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        let highlighted = isEnabled && (isHovered || isPressed)

        content
            .background(prominent ? accent.opacity(isPressed ? 0.82 : 1) : VeloraTheme.obsidianSurface, in: shape)
            .overlay {
                shape.fill(highlighted ? (prominent ? Color.white.opacity(0.10) : accent.opacity(0.09)) : .clear)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(highlighted ? accent.opacity(0.75) : VeloraTheme.cardBorder)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .opacity(isEnabled ? 1 : 0.55)
    }
}

struct ToolActionProgress: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .foregroundStyle(VeloraTheme.textSecondary)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 34)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(VeloraTheme.cardBorder)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fills each row and gives its cards the same height.
struct ToolCardRows: Layout {
    var spacing: CGFloat = 12
    var minimumCardWidth: CGFloat = 180

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = widthForColumns(max(1, subviews.count))
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let rows = measureRows(width: width, subviews: subviews)
        let height = rows.heights.reduce(0, +) + CGFloat(max(0, rows.heights.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = measureRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY

        for (row, height) in rows.heights.enumerated() {
            let first = row * rows.columns
            for index in first..<min(first + rows.columns, subviews.count) {
                let x = bounds.minX + CGFloat(index - first) * (rows.cardWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: rows.cardWidth, height: height)
                )
            }
            y += height + spacing
        }
    }

    private func widthForColumns(_ columns: Int) -> CGFloat {
        CGFloat(columns) * minimumCardWidth + CGFloat(columns - 1) * spacing
    }

    private func measureRows(width: CGFloat, subviews: Subviews) -> (columns: Int, cardWidth: CGFloat, heights: [CGFloat]) {
        let columns = [subviews.count, 2].first { count in
            count > 1 && subviews.count.isMultiple(of: count) && width >= widthForColumns(count)
        } ?? 1
        let cardWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let proposal = ProposedViewSize(width: cardWidth, height: nil)
        let heights = stride(from: 0, to: subviews.count, by: columns).map { first in
            subviews[first..<min(first + columns, subviews.count)]
                .map { $0.sizeThatFits(proposal).height }
                .max() ?? 0
        }
        return (columns, cardWidth, heights)
    }
}
