import SwiftUI
import VeloraCore

public struct SmartScanDashboardView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private func formatMetric(_ bytes: UInt64?, isLoading: Bool) -> String {
        if isLoading {
            return "..."
        }
        guard let bytes = bytes else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var isBusy: Bool {
        viewModel.isScanning || viewModel.isLoadingSnapshot
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Tier 1: Hero Banner
                SmartScanHeroView(viewModel: viewModel)
                    .background(
                        VeloraTheme.obsidianElevated,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(VeloraTheme.cardBorder, lineWidth: 1)
                    )

                // Loading Snapshot Notice Banner
                if viewModel.isLoadingSnapshot {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Loading Cached Catalog")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)

                                if let size = viewModel.catalogFileSizeString {
                                    Text("(\(size))")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(VeloraTheme.accentCyan)
                                }
                            }

                            Text("Reading catalog.bin from disk. Deep storage breakdown and hygiene metrics will update automatically.")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [
                                VeloraTheme.accentBlue.opacity(0.18),
                                VeloraTheme.obsidianElevated
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(VeloraTheme.accentCyan.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: VeloraTheme.accentBlue.opacity(0.15), radius: 8, x: 0, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Tier 2: Category Quick-Cards Row (5 Cards)
                HStack(spacing: 12) {
                    CategoryQuickCardView(
                        data: QuickCardData(
                            id: "system_junk",
                            title: "Build Junk",
                            sizeText: formatMetric(viewModel.devArtifactsBytes, isLoading: isBusy || viewModel.isLoadingDevArtifacts),
                            systemImage: "gearshape.2.fill",
                            accentColor: VeloraTheme.accentViolet,
                            destinationId: "tool_dev_artifacts"
                        )
                    ) {
                        viewModel.activeSidebarId = "tool_dev_artifacts"
                        if viewModel.devArtifacts.isEmpty {
                            viewModel.loadDevArtifacts()
                        }
                    }

                    CategoryQuickCardView(
                        data: QuickCardData(
                            id: "app_leftovers",
                            title: "App Leftovers",
                            sizeText: formatMetric(viewModel.appLeftoversBytes, isLoading: isBusy || viewModel.isLoadingOrphans),
                            systemImage: "trash.circle.fill",
                            accentColor: VeloraTheme.accentPink,
                            destinationId: "tool_orphans"
                        )
                    ) {
                        viewModel.activeSidebarId = "tool_orphans"
                        if viewModel.orphanedResidues.isEmpty {
                            viewModel.loadOrphanedResidues()
                        }
                    }

                    CategoryQuickCardView(
                        data: QuickCardData(
                            id: "xcode_storage",
                            title: "Xcode Storage",
                            sizeText: formatMetric(viewModel.xcodeStorageBytes, isLoading: isBusy || viewModel.isLoadingXcode),
                            systemImage: "hammer.circle.fill",
                            accentColor: VeloraTheme.accentEmerald,
                            destinationId: "tool_xcode"
                        )
                    ) {
                        viewModel.activeSidebarId = "tool_xcode"
                        if viewModel.xcodeSummary == nil {
                            viewModel.loadXcodeSummary()
                        }
                    }

                    CategoryQuickCardView(
                        data: QuickCardData(
                            id: "package_caches",
                            title: "Package Caches",
                            sizeText: formatMetric(viewModel.packageCachesBytes, isLoading: isBusy || viewModel.isLoadingPackageCaches),
                            systemImage: "shippingbox.circle.fill",
                            accentColor: VeloraTheme.accentAmber,
                            destinationId: "tool_package_caches"
                        )
                    ) {
                        viewModel.activeSidebarId = "tool_package_caches"
                        if viewModel.packageCacheSummary == nil {
                            viewModel.loadPackageCaches()
                        }
                    }

                    CategoryQuickCardView(
                        data: QuickCardData(
                            id: "duplicates",
                            title: "Duplicates",
                            sizeText: formatMetric(viewModel.duplicatesBytes, isLoading: isBusy || viewModel.isLoadingDuplicates),
                            systemImage: "doc.on.doc.fill",
                            accentColor: VeloraTheme.accentBlue,
                            destinationId: "tool_duplicates"
                        )
                    ) {
                        viewModel.activeSidebarId = "tool_duplicates"
                        if viewModel.duplicateSummary == nil {
                            viewModel.loadDuplicates()
                        }
                    }
                }

                // Tier 3: Bottom Analytics Grid (Disk Space & Storage Usage)
                HStack(spacing: 16) {
                    LinearStorageGaugeCardView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)

                    StorageDonutChartView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(VeloraTheme.obsidianBase)
    }
}
