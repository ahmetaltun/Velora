import SwiftUI

public enum VeloraTheme {
    // MARK: - Window & Layout Dimensions
    public static let minWindowWidth: CGFloat = 1000
    public static let minWindowHeight: CGFloat = 600

    // MARK: - Velora Bloom Soft Charcoal-Violet Palette
    public static let obsidianBase = Color(hex: "#202031")
    public static let obsidianSidebar = Color(hex: "#252438")
    public static let obsidianElevated = Color(hex: "#2A293E")
    public static let obsidianSurface = Color(hex: "#302F47")
    public static let obsidianSubsurface = Color(hex: "#37344D")

    // MARK: - Velora Bloom Accent Palette (Soft Violet, Periwinkle, Mint, Coral & Warm Ivory)
    public static let accentBlue = Color(hex: "#93C3FA")      // Periwinkle / Soft Blue
    public static let accentCyan = Color(hex: "#84BFEC")      // Soft Sky
    public static let accentViolet = Color(hex: "#A695FF")    // Brand Lavender / Soft Violet
    public static let accentPink = Color(hex: "#F68DAB")      // Coral Rose
    public static let accentEmerald = Color(hex: "#70D3BD")   // Mint
    public static let accentAmber = Color(hex: "#FEC787")     // Apricot / Warm Ivory
    public static let accentPurple = Color(hex: "#B7A0FF")    // Iris / Soft Violet

    // MARK: - Typography & Semantic Foreground Tokens
    public static let textPrimary = Color(hex: "#F6F2FF")     // Warm Ivory Primary Ink
    public static let textSecondary = Color(hex: "#A8A3BF")   // Muted Ink
    public static let textMuted = Color(hex: "#817D9B")       // Quiet Ink

    // MARK: - Glass & Border Tokens
    public static let cardBorder = Color(hex: "#4A455F").opacity(0.70)
    public static let cardBorderHover = accentViolet.opacity(0.45)
    public static let glassBorder = Color(hex: "#59516F").opacity(0.70)

    // MARK: - Legacy / High-Tech Palette Support
    public static let mint = Color(hex: "#70D3BD")
    public static let mintDark = Color(hex: "#58C7AC")
    public static let teal = Color(hex: "#84BFEC")
    public static let amber = Color(hex: "#FEC787")
    public static let glow = Color(hex: "#70D3BD").opacity(0.25)

    // MARK: - Gradients
    public static var ctaGradient: LinearGradient {
        LinearGradient(
            colors: [accentViolet, Color(hex: "#C69DFC")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static var ctaHoverGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#B7A7FF"), Color(hex: "#E4B9F9")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    public static var heroArtworkGlow: RadialGradient {
        RadialGradient(
            gradient: Gradient(colors: [
                accentViolet.opacity(0.35),
                Color(hex: "#93C3FA").opacity(0.20),
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
                accentViolet.opacity(0.22),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Storage Gauge Gradient (Soft Violet to Coral)
    public static var storageGauge: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#9381F3"), Color(hex: "#F2A2BC")],
            startPoint: .leading,
            endPoint: .trailing
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

// MARK: - Byte Formatting Utility
public func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useAll]
    return formatter.string(fromByteCount: Int64(bytes))
}

// MARK: - Color Hex Initializer
extension Color {
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
