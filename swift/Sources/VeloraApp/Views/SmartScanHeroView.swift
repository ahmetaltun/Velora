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
            return "Loading File Catalog..."
        } else if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            return "File Catalog Active"
        } else {
            return "Ready to Index Your Mac"
        }
    }

    private var heroSubtitle: String {
        if viewModel.isScanning {
            return "Indexing files into catalog.bin with high throughput. Sub-millisecond search and memory traversal will be available."
        } else if viewModel.isLoadingSnapshot {
            if let size = viewModel.catalogFileSizeString {
                return "Loading cached catalog.bin (\(size)) into RAM for instant search..."
            } else {
                return "Loading cached catalog.bin into RAM for instant search..."
            }
        } else if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            if viewModel.scannedCount > 0 {
                return "\(viewModel.scannedCount.formatted()) files indexed in memory. Sub-millisecond search is active. Explore tools below or rescan to refresh catalog.bin."
            } else {
                return "Your disk catalog is loaded in memory. Explore tools below or rescan to refresh catalog.bin."
            }
        } else {
            return "No catalog index found. Scan your disk to create catalog.bin and enable instant search and disk analytics."
        }
    }

    private var buttonTitle: String {
        if viewModel.isScanning {
            return "Indexing..."
        } else if viewModel.isLoadingSnapshot {
            return "Loading Catalog..."
        } else if viewModel.hasBinaryIndex || viewModel.hasIndexedData {
            return "Rescan All Files"
        } else {
            return "Index All Files"
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
                                Image(systemName: buttonIcon)
                                    .font(.system(size: 13, weight: .bold))
                                Text(buttonTitle)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
                            color: VeloraTheme.accentViolet.opacity(isHoveringCTA ? 0.6 : 0.35),
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
