import SwiftUI
import VeloraCore

public struct SmartScanHeroView: View {
    @Bindable public var viewModel: VeloraViewModel

    @State private var isHoveringCTA: Bool = false

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

            // Right Column: Seamless Ambient Fluid Mesh with Reactive Loop Animation
            AmbientFluidMeshView(
                isScanning: viewModel.isScanning,
                isLoading: viewModel.isLoadingSnapshot,
                size: 160
            )
            .frame(width: 200, height: 160)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}
