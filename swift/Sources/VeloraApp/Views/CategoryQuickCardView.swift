import SwiftUI

public struct QuickCardData: Identifiable {
    public let id: String
    public let title: String
    public let sizeText: String
    public let systemImage: String
    public let accentColor: Color
    public let destinationId: String

    public init(
        id: String,
        title: String,
        sizeText: String,
        systemImage: String,
        accentColor: Color,
        destinationId: String
    ) {
        self.id = id
        self.title = title
        self.sizeText = sizeText
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.destinationId = destinationId
    }
}

public struct CategoryQuickCardView: View {
    public let data: QuickCardData
    public let action: () -> Void

    @State private var isHovering: Bool = false

    public init(data: QuickCardData, action: @escaping () -> Void) {
        self.data = data
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(data.accentColor.opacity(0.18))
                        .frame(width: 30, height: 30)

                    Image(systemName: data.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(data.accentColor)
                }

                // Category Title
                Text(data.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .lineLimit(1)

                // Metric + Disclosure Row
                HStack(alignment: .firstTextBaseline) {
                    Text(data.sizeText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isHovering ? data.accentColor : data.accentColor.opacity(0.6))
                        .offset(x: isHovering ? 2 : 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                VeloraTheme.cardTintGradient(accent: data.accentColor),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovering ? VeloraTheme.cardBorderHover : VeloraTheme.cardBorder, lineWidth: 1)
            )
            .shadow(
                color: isHovering ? data.accentColor.opacity(0.15) : Color.black.opacity(0.12),
                radius: isHovering ? 10 : 4,
                x: 0,
                y: isHovering ? 3 : 2
            )
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
    }
}
