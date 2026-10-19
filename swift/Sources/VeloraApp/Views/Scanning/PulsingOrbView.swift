import SwiftUI

public struct PulsingOrbView: View {
    public var isScanning: Bool
    public var size: CGFloat = 18

    @State private var waveScale: CGFloat = 1.0
    @State private var waveOpacity: Double = 0.7

    public init(isScanning: Bool = true, size: CGFloat = 18) {
        self.isScanning = isScanning
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Ambient Radial Bloom
            Circle()
                .fill(
                    RadialGradient(
                        colors: [VeloraTheme.mint.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 1.5
                    )
                )
                .frame(width: size * 3, height: size * 3)

            // Expanding Pulse Ripple Wave
            if isScanning {
                Circle()
                    .stroke(VeloraTheme.mint.opacity(waveOpacity), lineWidth: 1.5)
                    .frame(width: size * waveScale, height: size * waveScale)
            }

            // Core Luminous Orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.8), VeloraTheme.mint, VeloraTheme.mintDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                )
                .shadow(color: VeloraTheme.mint.opacity(0.5), radius: 4, x: 0, y: 0)
        }
        .frame(width: size * 2.2, height: size * 2.2)
        .onAppear {
            if isScanning {
                startAnimation()
            }
        }
        .onChange(of: isScanning) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                waveScale = 1.0
                waveOpacity = 0.0
            }
        }
    }

    private func startAnimation() {
        waveScale = 1.0
        waveOpacity = 0.7
        withAnimation(
            .easeOut(duration: 1.25)
            .repeatForever(autoreverses: false)
        ) {
            waveScale = 2.0
            waveOpacity = 0.0
        }
    }
}
