import SwiftUI

public enum VeloraTheme {
    // MARK: - Deep Midnight Obsidian Palette
    public static let obsidianBase = Color(hex: "#16192E")
    public static let obsidianSidebar = Color(hex: "#131627")
    public static let obsidianElevated = Color(hex: "#1D2140")
    public static let obsidianSurface = Color(hex: "#22274B")
    public static let obsidianSubsurface = Color(hex: "#282E56")

    // MARK: - Jewel Accent Palette (MacCleaner / Modern Utility Style)
    public static let accentBlue = Color(hex: "#0A84FF")
    public static let accentCyan = Color(hex: "#00C7FF")
    public static let accentViolet = Color(hex: "#9065FE")
    public static let accentPink = Color(hex: "#F43F5E")
    public static let accentEmerald = Color(hex: "#10B981")
    public static let accentAmber = Color(hex: "#F59E0B")
    public static let accentPurple = Color(hex: "#A855F7")

    // MARK: - Typography & Semantic Foreground Tokens
    public static let textPrimary = Color.white
    public static let textSecondary = Color(hex: "#9BA1C7")
    public static let textMuted = Color(hex: "#6D7297")

    // MARK: - Glass & Border Tokens
    public static let cardBorder = Color.white.opacity(0.08)
    public static let cardBorderHover = Color.white.opacity(0.20)
    public static let glassBorder = Color.white.opacity(0.12)

    // MARK: - Legacy / High-Tech Palette Support
    public static let mint = Color(hex: "#00FFA3")
    public static let mintDark = Color(hex: "#05D59E")
    public static let teal = Color(hex: "#00E5FF")
    public static let amber = Color(hex: "#FBBF24")
    public static let glow = Color(hex: "#00FFA3").opacity(0.25)

    // MARK: - Gradients
    public static var ctaGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#007AFF"), Color(hex: "#00C7FF")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static var ctaHoverGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#1A8CFF"), Color(hex: "#33D4FF")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static var heroArtworkGlow: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [
                accentViolet.opacity(0.35),
                accentBlue.opacity(0.20),
                Color.clear
            ]),
            center: .center,
            startRadius: 20,
            endRadius: 240
        )
    }

    public static func cardTintGradient(accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.12),
                obsidianSurface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Specular Rim Gradient for Floating Island
    public static var specularRim: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.28),
                mint.opacity(0.35),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Laser Track Shimmer Beam
    public static func laserBeam(phase: CGFloat) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, phase - 0.25)),
                .init(color: teal.opacity(0.6), location: max(0, phase - 0.1)),
                .init(color: mint, location: phase),
                .init(color: teal.opacity(0.6), location: min(1, phase + 0.1)),
                .init(color: .clear, location: min(1, phase + 0.25))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
