import SwiftUI

public enum VeloraTheme {
    // Hyper-Mint & Cyber Teal Palette
    public static let mint = Color(hex: "#00FFA3")
    public static let mintDark = Color(hex: "#05D59E")
    public static let teal = Color(hex: "#00E5FF")
    public static let amber = Color(hex: "#FBBF24")
    public static let glow = Color(hex: "#00FFA3").opacity(0.25)
    public static let glassBorder = Color.white.opacity(0.12)

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
