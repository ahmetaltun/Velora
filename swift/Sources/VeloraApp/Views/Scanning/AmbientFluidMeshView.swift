import SwiftUI

/// An organic, borderless ambient fluid mesh with dynamic reactivity.
/// Transitions seamlessly between an idle jewel breathing state ("Your Mac looks great")
/// and a high-velocity cyber-mint scanning state when disk indexing is active.
public struct AmbientFluidMeshView: View {
    public var isScanning: Bool
    public var isLoading: Bool
    public var size: CGFloat

    @State private var meshRotation: Double = 0.0
    @State private var radarRotation: Double = 0.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var sparklePhase: CGFloat = 0.0

    public init(
        isScanning: Bool = false,
        isLoading: Bool = false,
        size: CGFloat = 160
    ) {
        self.isScanning = isScanning
        self.isLoading = isLoading
        self.size = size
    }

    private var isBusy: Bool {
        isScanning || isLoading
    }

    public var body: some View {
        ZStack {
            // LAYER 1: Ambient Fluid Blob Mesh (Living Gradient Cloud)
            ZStack {
                // Blob 1: Top-Left (Blue / Mint)
                Circle()
                    .fill(isBusy ? VeloraTheme.mint : VeloraTheme.accentBlue)
                    .frame(width: size * 0.65, height: size * 0.65)
                    .offset(x: -size * 0.20, y: -size * 0.20)

                // Blob 2: Top-Right (Cyan / Teal)
                Circle()
                    .fill(isBusy ? VeloraTheme.teal : VeloraTheme.accentCyan)
                    .frame(width: size * 0.60, height: size * 0.60)
                    .offset(x: size * 0.22, y: -size * 0.16)

                // Blob 3: Bottom-Right (Violet / Dark Mint)
                Circle()
                    .fill(isBusy ? VeloraTheme.mintDark : VeloraTheme.accentViolet)
                    .frame(width: size * 0.68, height: size * 0.68)
                    .offset(x: size * 0.18, y: size * 0.20)

                // Blob 4: Bottom-Left (Pink / Amber Accent)
                Circle()
                    .fill(isBusy ? VeloraTheme.accentBlue : VeloraTheme.accentPink)
                    .frame(width: size * 0.58, height: size * 0.58)
                    .offset(x: -size * 0.18, y: size * 0.18)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(meshRotation))
            .scaleEffect(pulseScale)
            .blur(radius: size * 0.18)
            // Crucial Anti-Clipping Mask: Guarantees zero hard rectangular box edges
            .mask(
                RadialGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black.opacity(0.85), location: 0.40),
                        .init(color: .clear, location: 0.82)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.48
                )
            )

            // LAYER 2: Scanning Telemetry Rings (Active when indexing or loading)
            if isBusy {
                // Outer Orbiting Dashed Track
                Circle()
                    .stroke(
                        VeloraTheme.mint.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 6])
                    )
                    .frame(width: size * 0.78, height: size * 0.78)
                    .rotationEffect(.degrees(radarRotation))

                // Inner Fast Scan Ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [VeloraTheme.mint, Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: size * 0.62, height: size * 0.62)
                    .rotationEffect(.degrees(-radarRotation * 1.5))
            }

            // LAYER 3: Floating Frosted Glass Insignia Vessel
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size * 0.46, height: size * 0.46)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: isBusy
                                        ? [VeloraTheme.mint.opacity(0.7), VeloraTheme.teal.opacity(0.2)]
                                        : [Color.white.opacity(0.4), VeloraTheme.accentCyan.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(
                        color: (isBusy ? VeloraTheme.mint : VeloraTheme.accentCyan).opacity(0.3),
                        radius: 12,
                        x: 0,
                        y: 4
                    )

                // Central Dynamic Symbol
                if isLoading {
                    VStack(spacing: 4) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: size * 0.16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [VeloraTheme.accentCyan, VeloraTheme.accentBlue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        ProgressView()
                            .controlSize(.mini)
                    }
                } else if isScanning {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.19, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, VeloraTheme.mint],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: VeloraTheme.mint.opacity(0.8), radius: 8)
                        .scaleEffect(pulseScale)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: size * 0.19, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#FF70A6"), Color(hex: "#70D6FF")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: "#FF70A6").opacity(0.5), radius: 8)
                }
            }

            // LAYER 4: Floating Micro-Sparkles (Perimeter Twinkle)
            Group {
                // Top-Right Sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isBusy ? VeloraTheme.mint : VeloraTheme.accentCyan)
                    .offset(x: size * 0.38, y: -size * 0.28 + (sparklePhase * -4))
                    .scaleEffect(0.85 + (sparklePhase * 0.25))
                    .shadow(color: (isBusy ? VeloraTheme.mint : VeloraTheme.accentCyan).opacity(0.6), radius: 5)

                // Bottom-Right Sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isBusy ? VeloraTheme.teal : VeloraTheme.accentPink)
                    .offset(x: size * 0.42, y: size * 0.22 + (sparklePhase * 3))
                    .scaleEffect(1.0 - (sparklePhase * 0.2))
                    .shadow(color: (isBusy ? VeloraTheme.teal : VeloraTheme.accentPink).opacity(0.5), radius: 4)

                // Left Sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isBusy ? VeloraTheme.mint : VeloraTheme.accentViolet)
                    .offset(x: -size * 0.38, y: -size * 0.08 + (sparklePhase * 4))
                    .scaleEffect(0.9 + (sparklePhase * 0.2))
                    .shadow(color: (isBusy ? VeloraTheme.mint : VeloraTheme.accentViolet).opacity(0.5), radius: 5)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            restartAnimations()
        }
        .onChange(of: isScanning) { _, _ in
            restartAnimations()
        }
        .onChange(of: isLoading) { _, _ in
            restartAnimations()
        }
    }

    private func restartAnimations() {
        // Reset and trigger continuous smooth rotation
        meshRotation = 0.0
        let rotDuration = isBusy ? 2.8 : 12.0
        withAnimation(.linear(duration: rotDuration).repeatForever(autoreverses: false)) {
            meshRotation = 360.0
        }

        // Radar rotation for scanning mode
        radarRotation = 0.0
        if isBusy {
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                radarRotation = 360.0
            }
        }

        // Rhythmic breathing scale
        pulseScale = 1.0
        let pulseDuration = isBusy ? 0.9 : 2.5
        let targetScale: CGFloat = isBusy ? 1.08 : 1.04
        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
            pulseScale = targetScale
        }

        // Sparkle float & scale harmonic
        sparklePhase = 0.0
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            sparklePhase = 1.0
        }
    }
}
