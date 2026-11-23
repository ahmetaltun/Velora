import SwiftUI

public struct SmartScanHeroView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var detail: String {
        if viewModel.isLoadingSnapshot {
            return "Restoring your file catalog…"
        }
        if viewModel.isScanning {
            return "Finding files in your home folder…"
        }
        if viewModel.hasIndexedData {
            let count = viewModel.scannedCount
            return count == 1 ? "1 item indexed" : "\(count.formatted()) items indexed"
        }
        return "Scan your home folder to browse and search files."
    }

    private var isCatalogReady: Bool {
        viewModel.hasIndexedData && !viewModel.isLoadingSnapshot && !viewModel.isScanning
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                content
                    .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)
                CatalogFolderArtwork(isScanning: viewModel.isScanning)
                    .frame(width: 210, height: 170)
            }
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [Color(hex: "#35304F"), VeloraTheme.obsidianElevated],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [VeloraTheme.accentViolet.opacity(0.18), .clear],
                    center: .trailing, startRadius: 0, endRadius: 340
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [VeloraTheme.accentPurple.opacity(0.42), VeloraTheme.cardBorder.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label("FILE CATALOG", systemImage: "square.grid.2x2")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(VeloraTheme.accentPurple)
                    .accessibilityLabel("File Catalog")
                    .accessibilityAddTraits(.isHeader)

                Text("Everything, within reach.")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(VeloraTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Image(systemName: isCatalogReady ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(VeloraTheme.accentEmerald)
                        .accessibilityHidden(true)
                    Text(detail)
                        .foregroundStyle(VeloraTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12, weight: .medium))
            }
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        if viewModel.isLoadingSnapshot {
            ToolActionProgress(title: "Loading Catalog…")
        } else if viewModel.isScanning {
            ToolActionProgress(title: "Indexing Files…")
        } else if viewModel.hasIndexedData {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    catalogActions
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    catalogActions
                }
            }
            .disabled(viewModel.isInteractionDisabled)
        } else {
            Button("Scan Home Folder", systemImage: "magnifyingglass", action: viewModel.scanCatalog)
                .buttonStyle(CatalogBannerButtonStyle(prominent: true))
                .disabled(viewModel.isInteractionDisabled)
        }
    }

    @ViewBuilder
    private var catalogActions: some View {
        Button("Browse Files", systemImage: "folder", action: viewModel.navigateToRoot)
            .buttonStyle(CatalogBannerButtonStyle(prominent: true))

        Button("Rescan Catalog", systemImage: "arrow.clockwise", action: viewModel.scanCatalog)
            .buttonStyle(CatalogBannerButtonStyle())
    }
}

private struct CatalogBannerButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = isHovered && isEnabled
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? VeloraTheme.obsidianBase : VeloraTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: prominent
                                ? [Color(hex: "#C3B3FF"), VeloraTheme.accentViolet]
                                : [Color.white.opacity(highlighted ? 0.10 : 0.06), Color.white.opacity(0.03)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(highlighted ? 0.26 : 0.12))
            }
            .shadow(color: prominent ? VeloraTheme.accentViolet.opacity(highlighted ? 0.25 : 0.10) : .clear,
                    radius: 12, y: 4)
            .offset(y: reduceMotion || !highlighted || configuration.isPressed ? 0 : -1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: highlighted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Native vector artwork stays crisp at every display scale.
private struct CatalogFolderArtwork: View {
    let isScanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var animatesScan: Bool {
        isScanning && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(VeloraTheme.accentViolet.opacity(0.08))
                .frame(width: 158, height: 158)
            Circle()
                .strokeBorder(VeloraTheme.accentPurple.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(-15))

            folder
                .phaseAnimator(reduceMotion || scenePhase != .active ? [false] : [false, true]) { content, lifted in
                    content
                        .offset(y: lifted ? (isScanning ? -7 : -4) : 3)
                        .rotationEffect(.degrees(lifted ? (isScanning ? -5 : -3) : 1))
                } animation: { _ in
                    .easeInOut(duration: isScanning ? 1.6 : 3.4)
                }
                .id(isScanning)

            Image(systemName: "sparkle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(VeloraTheme.accentAmber)
                .offset(x: 78, y: -53)
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(VeloraTheme.accentPurple.opacity(0.7))
                .rotationEffect(.degrees(15))
                .offset(x: -82, y: 22)
            Circle()
                .fill(VeloraTheme.accentEmerald)
                .frame(width: 5, height: 5)
                .offset(x: 64, y: 62)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var folder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#7563B9"))
                .frame(width: 126, height: 88)
                .offset(y: 14)
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: "#7563B9"))
                .frame(width: 54, height: 22)
                .offset(x: -36, y: -30)

            paper(symbol: "photo", color: VeloraTheme.accentPink)
                .rotationEffect(.degrees(-16))
                .offset(x: -24, y: -22)
            paper(symbol: "doc.text", color: VeloraTheme.accentBlue)
                .rotationEffect(.degrees(12))
                .offset(x: 23, y: -25)

            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [Color(hex: "#C7B5FF"), Color(hex: "#9680E6")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 138, height: 82)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
                .overlay {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(Color(hex: "#554286"))
                        .symbolEffect(.pulse, options: .repeating, isActive: animatesScan)
                }
                .rotationEffect(.degrees(-3))
                .offset(y: 27)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
        }
    }

    private func paper(symbol: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [Color(hex: "#F2EBFF"), Color(hex: "#D2C7ED")],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 57, height: 76)
            .overlay(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(color.opacity(0.9))
                    .padding(.top, 12)
            }
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
