import SwiftUI

public struct SecurityPillarCardView: View {
    public let title: String
    public let subtitle: String
    public let description: String
    public let statusText: String
    public let systemImage: String
    public let accentColor: Color
    public var isAlert: Bool = false

    public init(
        title: String,
        subtitle: String,
        description: String,
        statusText: String,
        systemImage: String,
        accentColor: Color,
        isAlert: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.statusText = statusText
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.isAlert = isAlert
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 36, height: 36)

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()
            }

            Text(description)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isAlert ? VeloraTheme.accentPink : VeloraTheme.accentEmerald)

                Text(statusText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(isAlert ? VeloraTheme.accentPink : VeloraTheme.accentEmerald)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (isAlert ? VeloraTheme.accentPink : VeloraTheme.accentEmerald).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(
            VeloraTheme.cardTintGradient(accent: accentColor),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isAlert
                        ? VeloraTheme.accentPink.opacity(0.35)
                        : VeloraTheme.cardBorder,
                    lineWidth: 1
                )
        )
    }
}
