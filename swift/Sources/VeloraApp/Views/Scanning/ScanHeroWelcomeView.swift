import SwiftUI
import VeloraCore

/// A futuristic, cyber-mint hero view displayed on first launch or when no volume index is loaded.
public struct ScanHeroWelcomeView: View {
    @Bindable public var viewModel: VeloraViewModel

    @State private var pulsePhase: CGFloat = 0.0
    @State private var isHoveringButton: Bool = false
    @State private var radarRotation: Double = 0.0

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            // Ambient Cybernetic Radial Background
            RadialGradient(
                gradient: Gradient(colors: [
                    VeloraTheme.mint.opacity(0.14),
                    VeloraTheme.teal.opacity(0.06),
                    Color.clear
                ]),
                center: .center,
                startRadius: 60,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                // Central Glowing Holographic Radar
                ZStack {
                    // Outer expanding pulse ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [VeloraTheme.mint.opacity(0.4), VeloraTheme.teal.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 170, height: 170)
                        .scaleEffect(1.0 + (pulsePhase * 0.12))
                        .opacity(1.0 - (Double(pulsePhase) * 0.6))

                    // Secondary orbital ring with dashed track
                    Circle()
                        .stroke(
                            VeloraTheme.glassBorder,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 6])
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(radarRotation))

                    // Inner frosted glass vessel
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 104, height: 104)
                        .overlay(
                            Circle()
                                .stroke(VeloraTheme.specularRim, lineWidth: 1.5)
                        )
                        .shadow(color: VeloraTheme.mint.opacity(0.35), radius: 18, x: 0, y: 0)

                    // Core pulsing orb
                    PulsingOrbView(isScanning: true, size: 28)
                }
                .padding(.top, 12)

                // Hero Titles
                VStack(spacing: 10) {
                    Text("Instant Space Intelligence")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, VeloraTheme.mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Velora indexes files with near-instant speed. Your catalog will be saved\nlocally in Application Support and refreshed on demand.")
                        .font(.system(size: 13, weight: .regular))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 460)
                }

                // Target Location Pill
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(VeloraTheme.mint)

                    Text("Ready to analyze:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(viewModel.currentPath)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(VeloraTheme.glassBorder, lineWidth: 1)
                )

                // Call to Action: Glowing "Scan Now" Button
                Button(action: {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        viewModel.scanCurrentPath()
                    }
                }) {
                    HStack(spacing: 10) {
                        if viewModel.isScanning {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning...")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 14, weight: .bold))

                            Text("Scan Now")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundColor(viewModel.isScanning ? .secondary : .black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: viewModel.isScanning
                                ? [VeloraTheme.mintDark.opacity(0.5), VeloraTheme.mint.opacity(0.5)]
                                : (isHoveringButton
                                    ? [VeloraTheme.mint, VeloraTheme.teal]
                                    : [VeloraTheme.mintDark, VeloraTheme.mint]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .shadow(
                        color: VeloraTheme.mint.opacity(isHoveringButton && !viewModel.isScanning ? 0.65 : 0.35),
                        radius: isHoveringButton && !viewModel.isScanning ? 16 : 8,
                        x: 0,
                        y: 0
                    )
                    .scaleEffect(isHoveringButton && !viewModel.isScanning ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        isHoveringButton = hovering
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(36)
            .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(VeloraTheme.specularRim, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 15)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulsePhase = 1.0
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                radarRotation = 360
            }
        }
    }
}
