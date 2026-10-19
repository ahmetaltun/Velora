import SwiftUI

public struct LaserTrackView: View {
    public var isScanning: Bool
    public var height: CGFloat = 3

    @State private var phase: CGFloat = -0.2

    public init(isScanning: Bool = true, height: CGFloat = 3) {
        self.isScanning = isScanning
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: height)

                // High-Velocity Laser Shimmer Beam
                if isScanning {
                    Capsule()
                        .fill(VeloraTheme.laserBeam(phase: phase))
                        .frame(height: height)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            if isScanning {
                startLaser()
            }
        }
        .onChange(of: isScanning) { _, newValue in
            if newValue {
                startLaser()
            }
        }
    }

    private func startLaser() {
        phase = -0.2
        withAnimation(
            .linear(duration: 1.4)
            .repeatForever(autoreverses: false)
        ) {
            phase = 1.2
        }
    }
}
