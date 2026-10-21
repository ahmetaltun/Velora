import SwiftUI
import VeloraCore

public struct SmartScanHeroView: View {
    @Bindable public var viewModel: VeloraViewModel

    @State private var isHoveringCTA: Bool = false
    @State private var sparkleFloat: CGFloat = 0.0

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var heroTitle: String {
        if viewModel.isScanning {
            return "Indexing your Mac..."
        } else if viewModel.isLoadingSnapshot {
            return "Loading Disk Catalog..."
        } else if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            return "Your Mac looks great!"
        } else {
            return "Ready to analyze your Mac"
        }
    }

    private var heroSubtitle: String {
        if viewModel.isScanning {
            return "Indexing files into catalog.bin with near-instant speed. You can cancel at any time."
        } else if viewModel.isLoadingSnapshot {
            if let size = viewModel.catalogFileSizeString {
                return "Found cached catalog.bin (\(size)) on disk. Deserializing indexed volume into memory for instant search..."
            } else {
                return "Found cached catalog.bin on disk. Deserializing indexed volume into memory..."
            }
        } else if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            return "Your disk catalog is active. We found items you can clean to free up space and keep your Mac running smoothly."
        } else {
            return "No catalog index found yet. Scan all files to build catalog.bin and enable instant sub-millisecond search."
        }
    }

    private var buttonTitle: String {
        if viewModel.isScanning {
            return "Scanning..."
        } else if viewModel.isLoadingSnapshot {
            return "Loading Catalog..."
        } else if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            return "Rescan All Files"
        } else {
            return "Scan All Files"
        }
    }

    private var buttonIcon: String {
        if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            return "arrow.clockwise"
        } else {
            return "bolt.fill"
        }
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 24) {
            // Left Column: Text & CTA
            VStack(alignment: .leading, spacing: 14) {
                Text(heroTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)
                    .lineLimit(1)

                Text(heroSubtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440, alignment: .leading)

                HStack(spacing: 12) {
                    // Primary Glowing Action Button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            viewModel.scanCurrentPath()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isScanning || viewModel.isLoadingSnapshot {
                                ProgressView()
                                    .controlSize(.small)
                                Text(buttonTitle)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            } else {
                                Text(buttonTitle)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(
                            isHoveringCTA ? VeloraTheme.ctaHoverGradient : VeloraTheme.ctaGradient,
                            in: Capsule()
                        )
                        .shadow(
                            color: VeloraTheme.accentBlue.opacity(isHoveringCTA ? 0.6 : 0.35),
                            radius: isHoveringCTA ? 14 : 8,
                            x: 0,
                            y: isHoveringCTA ? 4 : 2
                        )
                        .scaleEffect(isHoveringCTA && !viewModel.isScanning && !viewModel.isLoadingSnapshot ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isScanning || viewModel.isLoadingSnapshot)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            isHoveringCTA = hovering
                        }
                    }

                    if viewModel.isScanning {
                        Button(action: {
                            viewModel.cancelScan()
                        }) {
                            Text("Cancel")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right Column: Luminous Laptop Illustration
            LuminousLaptopCompositionView(sparkleFloat: sparkleFloat, isLoading: viewModel.isLoadingSnapshot)
                .frame(width: 250, height: 160)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                sparkleFloat = 1.0
            }
        }
    }
}

/// A pure SwiftUI vector composition of a floating 3D-angled glass laptop with glowing brush and sparkles
private struct LuminousLaptopCompositionView: View {
    let sparkleFloat: CGFloat
    var isLoading: Bool = false

    var body: some View {
        ZStack {
            // Ambient Aura
            VeloraTheme.heroArtworkGlow
                .frame(width: 260, height: 180)

            // Laptop Display (Angled)
            ZStack {
                // Outer Display Shell
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1E2240"))
                    .frame(width: 190, height: 122)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 8)

                // Screen Bezel Inner
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#2A1856"),
                                Color(hex: "#122046")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 176, height: 108)

                // Screen Glow Center
                RadialGradient(
                    colors: [
                        Color(hex: "#FF5E99").opacity(0.35),
                        Color(hex: "#00C7FF").opacity(0.2),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 5,
                    endRadius: 70
                )
                .frame(width: 176, height: 108)

                // Center Icon: Luminous Cleaning Broom or Loading Disk Indicator
                ZStack {
                    if isLoading {
                        VStack(spacing: 6) {
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [VeloraTheme.accentCyan, VeloraTheme.accentBlue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: VeloraTheme.accentCyan.opacity(0.8), radius: 12, x: 0, y: 0)

                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#FF70A6"), Color(hex: "#70D6FF")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color(hex: "#FF70A6").opacity(0.6), radius: 10, x: 0, y: 0)
                    }
                }
            }
            .rotation3DEffect(.degrees(8), axis: (x: 0, y: -1, z: 0))
            .offset(y: -12)

            // Laptop Keyboard Base (Perspective)
            ZStack {
                // Wedge Base
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 130))
                    path.addLine(to: CGPoint(x: 215, y: 130))
                    path.addLine(to: CGPoint(x: 200, y: 142))
                    path.addLine(to: CGPoint(x: 25, y: 142))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#343A64"), Color(hex: "#212543")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 10, y: 130))
                        path.addLine(to: CGPoint(x: 215, y: 130))
                    }
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

                // Trackpad
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 6)
                    .offset(x: -5, y: 66)
            }
            .offset(y: -4)

            // Floating Sparkle Stars
            Image(systemName: "sparkle")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(VeloraTheme.accentCyan)
                .offset(x: 108, y: -45 + (sparkleFloat * -6))
                .shadow(color: VeloraTheme.accentCyan, radius: 6)

            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(VeloraTheme.accentPink)
                .offset(x: 122, y: -25 + (sparkleFloat * 4))
                .shadow(color: VeloraTheme.accentPink, radius: 4)

            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(VeloraTheme.accentViolet)
                .offset(x: -95, y: -10 + (sparkleFloat * -4))
                .shadow(color: VeloraTheme.accentViolet, radius: 5)
        }
    }
}
