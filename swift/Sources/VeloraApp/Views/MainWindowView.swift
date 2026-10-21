import SwiftUI
import VeloraCore

public struct MainWindowView: View {
    @State public var viewModel = VeloraViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // CleanMyMac-style Floating Scan Banner
                if viewModel.isScanning {
                    CleanScanBannerView(viewModel: viewModel)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.96).combined(with: .opacity)
                            )
                        )
                }

                // Main Workspace Canvas
                Group {
                    if viewModel.activeSidebarId == "tool_smart_scan" || viewModel.activeSidebarId == "volume_root" {
                        SmartScanDashboardView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_dev_artifacts" {
                        DevArtifactsHunterView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_xcode" {
                        XcodeStorageView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_package_caches" {
                        PackageCachesView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_apps" {
                        AppUninstallerDashboardView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_orphans" {
                        OrphanedLeftoversView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_large_old_matrix" {
                        LargeOldFilesMatrixView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "tool_duplicates" {
                        DuplicateFinderView(viewModel: viewModel)
                    } else if viewModel.activeSidebarId == "storage_volumes" {
                        ApfsStorageCardView(viewModel: viewModel)
                            .padding(24)
                    } else if viewModel.shouldShowScanUI && viewModel.searchQuery.isEmpty {
                        SmartScanDashboardView(viewModel: viewModel)
                    } else if !viewModel.searchQuery.isEmpty || viewModel.selectedViewMode == .table {
                        FileTableView(viewModel: viewModel)
                    } else {
                        SunburstCanvasView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)

                // Bottom DaisyDisk-style Collector Drawer
                CollectorTrayView(viewModel: viewModel)
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.isScanning)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: viewModel.shouldShowScanUI)
            .toolbar {
                // Navigation controls
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: {
                        viewModel.navigateToRoot()
                    }) {
                        Image(systemName: "internaldrive")
                    }
                    .help("Return to main volume view")

                    Button(action: {
                        viewModel.navigateUp()
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.pathStack.count <= 1)
                    .help("Navigate up one folder level")

                    // Current Path Pill
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundColor(VeloraTheme.textSecondary)
                        Text((viewModel.currentPath as NSString).lastPathComponent.isEmpty ? "Macintosh HD" : (viewModel.currentPath as NSString).lastPathComponent)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundColor(VeloraTheme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(VeloraTheme.cardBorder, lineWidth: 1)
                    )

                    if viewModel.isLoadingSnapshot {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Loading catalog.bin...")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.accentCyan)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(VeloraTheme.accentCyan.opacity(0.35), lineWidth: 1)
                        )
                    }
                }

                // Instant Search Bar
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(VeloraTheme.textSecondary)

                        TextField("Search anything (e.g. ext:rs size:>10MB !target)...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .foregroundColor(VeloraTheme.textPrimary)
                            .onChange(of: viewModel.searchQuery) { _, newValue in
                                viewModel.performSearch(query: newValue, debounce: true)
                            }

                        if viewModel.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else if !viewModel.searchQuery.isEmpty {
                            Button(action: {
                                viewModel.searchQuery = ""
                                viewModel.performSearch(query: "")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(VeloraTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: 280, idealWidth: 380, maxWidth: 500)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(VeloraTheme.cardBorder, lineWidth: 1)
                    )
                }

                // View Mode & Actions
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("View", selection: $viewModel.selectedViewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button(action: {
                        viewModel.scanCurrentPath()
                    }) {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .help("Rescan current folder")
                }
            }
        }
        .onAppear {
            viewModel.loadCachedSnapshotIfAvailable()
        }
        .background(
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = NSColor(red: 22/255.0, green: 25/255.0, blue: 46/255.0, alpha: 1.0)
                window.toolbar?.showsBaselineSeparator = false
            }
        )
        .background(VeloraTheme.obsidianBase)
    }
}
