import SwiftUI
import VeloraCore

public struct SidebarView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private func formatBadge(_ bytes: UInt64?, isLoading: Bool) -> String? {
        if isLoading {
            return "..."
        }
        guard let bytes = bytes, bytes > 0 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var isBusy: Bool {
        viewModel.isScanning || viewModel.isLoadingSnapshot
    }

    public var body: some View {
        VStack(spacing: 0) {
            // App Identity Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [VeloraTheme.accentBlue, VeloraTheme.accentCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)

                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Velora")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text("Disk Intelligence")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Primary Smart Scan Action
            SidebarRowItem(
                title: "Smart Scan",
                systemImage: "sparkles",
                accentColor: VeloraTheme.accentCyan,
                badge: nil,
                isSelected: viewModel.activeSidebarId == "tool_smart_scan" || viewModel.activeSidebarId == "volume_root"
            ) {
                viewModel.activeSidebarId = "tool_smart_scan"
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()
                .overlay(VeloraTheme.cardBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            // Sectioned List
            List {
                Section("Cleanup") {
                    SidebarRowItem(
                        title: "Build Junk",
                        systemImage: "gearshape.2.fill",
                        accentColor: VeloraTheme.accentViolet,
                        badge: formatBadge(viewModel.devArtifactsBytes, isLoading: isBusy || viewModel.isLoadingDevArtifacts),
                        isSelected: viewModel.activeSidebarId == "tool_dev_artifacts"
                    ) {
                        viewModel.activeSidebarId = "tool_dev_artifacts"
                        if viewModel.devArtifacts.isEmpty {
                            viewModel.loadDevArtifacts()
                        }
                    }

                    SidebarRowItem(
                        title: "App Leftovers",
                        systemImage: "trash.circle.fill",
                        accentColor: VeloraTheme.accentPink,
                        badge: formatBadge(viewModel.appLeftoversBytes, isLoading: isBusy || viewModel.isLoadingOrphans),
                        isSelected: viewModel.activeSidebarId == "tool_orphans"
                    ) {
                        viewModel.activeSidebarId = "tool_orphans"
                        if viewModel.orphanedResidues.isEmpty {
                            viewModel.loadOrphanedResidues()
                        }
                    }

                    SidebarRowItem(
                        title: "Xcode Storage",
                        systemImage: "hammer.circle.fill",
                        accentColor: VeloraTheme.accentEmerald,
                        badge: formatBadge(viewModel.xcodeStorageBytes, isLoading: isBusy || viewModel.isLoadingXcode),
                        isSelected: viewModel.activeSidebarId == "tool_xcode"
                    ) {
                        viewModel.activeSidebarId = "tool_xcode"
                        if viewModel.xcodeSummary == nil {
                            viewModel.loadXcodeSummary()
                        }
                    }

                    SidebarRowItem(
                        title: "Package Caches",
                        systemImage: "shippingbox.circle.fill",
                        accentColor: VeloraTheme.accentAmber,
                        badge: formatBadge(viewModel.packageCachesBytes, isLoading: isBusy || viewModel.isLoadingPackageCaches),
                        isSelected: viewModel.activeSidebarId == "tool_package_caches"
                    ) {
                        viewModel.activeSidebarId = "tool_package_caches"
                        if viewModel.packageCacheSummary == nil {
                            viewModel.loadPackageCaches()
                        }
                    }
                }

                Section("Utilities") {
                    SidebarRowItem(
                        title: "App Uninstaller",
                        systemImage: "app.badge.checkmark",
                        accentColor: VeloraTheme.accentBlue,
                        badge: nil,
                        isSelected: viewModel.activeSidebarId == "tool_apps"
                    ) {
                        viewModel.activeSidebarId = "tool_apps"
                        if viewModel.installedApps.isEmpty {
                            viewModel.loadInstalledApps()
                        }
                    }

                    SidebarRowItem(
                        title: "Large & Old Matrix",
                        systemImage: "calendar.badge.clock",
                        accentColor: VeloraTheme.accentPink,
                        badge: formatBadge(viewModel.largeOldMatrixBytes, isLoading: isBusy || viewModel.isLoadingLargeOldMatrix),
                        isSelected: viewModel.activeSidebarId == "tool_large_old_matrix"
                    ) {
                        viewModel.activeSidebarId = "tool_large_old_matrix"
                        if viewModel.largeOldMatrix == nil {
                            viewModel.loadLargeOldMatrix()
                        }
                    }

                    SidebarRowItem(
                        title: "Duplicate Finder",
                        systemImage: "doc.on.doc.fill",
                        accentColor: VeloraTheme.accentCyan,
                        badge: formatBadge(viewModel.duplicatesBytes, isLoading: isBusy || viewModel.isLoadingDuplicates),
                        isSelected: viewModel.activeSidebarId == "tool_duplicates"
                    ) {
                        viewModel.activeSidebarId = "tool_duplicates"
                        if viewModel.duplicateSummary == nil {
                            viewModel.loadDuplicates()
                        }
                    }
                }

                Section("Storage & Explorer") {
                    SidebarRowItem(
                        title: "Macintosh HD",
                        systemImage: "internaldrive.fill",
                        accentColor: VeloraTheme.accentBlue,
                        badge: nil,
                        isSelected: viewModel.activeSidebarId == "storage_volumes"
                    ) {
                        viewModel.activeSidebarId = "storage_volumes"
                    }

                    SidebarRowItem(
                        title: "Home",
                        systemImage: "house.fill",
                        accentColor: .secondary,
                        badge: nil,
                        isSelected: viewModel.activeSidebarId == "fav_home"
                    ) {
                        viewModel.navigateToFavorite(
                            id: "fav_home",
                            path: FileManager.default.homeDirectoryForCurrentUser.path
                        )
                    }

                    SidebarRowItem(
                        title: "Developer",
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        accentColor: .secondary,
                        badge: nil,
                        isSelected: viewModel.activeSidebarId == "fav_dev"
                    ) {
                        let devPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Rust")
                        viewModel.navigateToFavorite(
                            id: "fav_dev",
                            path: devPath
                        )
                    }

                    SidebarRowItem(
                        title: "Downloads",
                        systemImage: "arrow.down.circle.fill",
                        accentColor: .secondary,
                        badge: nil,
                        isSelected: viewModel.activeSidebarId == "fav_downloads"
                    ) {
                        let dlPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
                        viewModel.navigateToFavorite(
                            id: "fav_downloads",
                            path: dlPath
                        )
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(VeloraTheme.obsidianSidebar)
    }
}

private struct SidebarRowItem: View {
    let title: String
    let systemImage: String
    var accentColor: Color = VeloraTheme.accentBlue
    var badge: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : accentColor)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(isSelected ? .white : VeloraTheme.textPrimary)

                Spacer(minLength: 4)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : VeloraTheme.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? VeloraTheme.obsidianElevated : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? VeloraTheme.cardBorderHover : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
