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

    private func formatThreatBadge(_ count: Int?, isLoading: Bool) -> String? {
        if isLoading {
            return "..."
        }
        guard let count = count, count > 0 else {
            return nil
        }
        return "\(count) alert\(count == 1 ? "" : "s")"
    }

    private var isBusy: Bool {
        viewModel.isScanning || viewModel.isLoadingSnapshot
    }

    public var body: some View {
        VStack(spacing: 0) {
            // App Identity Header
            Button {
                AppAssetLoader.openAboutPanel()
            } label: {
                HStack(spacing: 11) {
                    VeloraLogoView(size: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Velora")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)

                        Text("Space to breathe")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textSecondary)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help("About Velora")
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Primary Overview / Action Center Action
            SidebarRowItem(
                title: "Overview",
                systemImage: "gauge.with.dots.needle.bottom.50percent",
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
                        badge: formatBadge(viewModel.devArtifactsBytes, isLoading: viewModel.isLoadingDevArtifacts),
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
                        badge: formatBadge(viewModel.appLeftoversBytes, isLoading: viewModel.isLoadingOrphans),
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
                        badge: formatBadge(viewModel.xcodeStorageBytes, isLoading: viewModel.isLoadingXcode),
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
                        badge: formatBadge(viewModel.packageCachesBytes, isLoading: viewModel.isLoadingPackageCaches),
                        isSelected: viewModel.activeSidebarId == "tool_package_caches"
                    ) {
                        viewModel.activeSidebarId = "tool_package_caches"
                        if viewModel.packageCacheSummary == nil {
                            viewModel.loadPackageCaches()
                        }
                    }
                }

                Section("Protection") {
                    SidebarRowItem(
                        title: "Malware & Threats",
                        systemImage: "shield.lefthalf.filled",
                        accentColor: (viewModel.securityThreatsCount ?? 0) > 0 ? VeloraTheme.accentPink : VeloraTheme.accentEmerald,
                        badge: formatThreatBadge(viewModel.securityThreatsCount, isLoading: viewModel.isLoadingSecurity),
                        isSelected: viewModel.activeSidebarId == "tool_security"
                    ) {
                        viewModel.activeSidebarId = "tool_security"
                        if viewModel.securitySummary == nil {
                            viewModel.loadSecurityScan()
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
                        badge: formatBadge(viewModel.largeOldMatrixBytes, isLoading: viewModel.isLoadingLargeOldMatrix),
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
                        badge: formatBadge(viewModel.duplicatesBytes, isLoading: viewModel.isLoadingDuplicates),
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
            .scrollContentBackground(.hidden)
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
                    .foregroundColor(isSelected ? VeloraTheme.accentViolet : accentColor)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Spacer(minLength: 4)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(isSelected ? VeloraTheme.accentViolet : VeloraTheme.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? VeloraTheme.accentViolet.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? VeloraTheme.accentViolet.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
