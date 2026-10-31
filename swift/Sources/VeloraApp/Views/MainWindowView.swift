import SwiftUI
import VeloraCore

public struct MainWindowView: View {
    @State public var viewModel = VeloraViewModel()
    @AppStorage("isCleanupInspectorVisible") private var showBloomInspector: Bool = false
    @FocusState private var isSearchFocused: Bool

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 245, ideal: 265, max: 310)
        } detail: {
            HStack(spacing: 0) {
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
                        if viewModel.isSearchActive {
                            FileTableView(viewModel: viewModel)
                        } else if viewModel.activeSidebarId == "tool_smart_scan" || viewModel.activeSidebarId == "volume_root" {
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
                        } else if viewModel.activeSidebarId == "tool_security" {
                            MalwareScannerView(viewModel: viewModel)
                        } else if viewModel.shouldShowScanUI {
                            SmartScanDashboardView(viewModel: viewModel)
                        } else {
                            FileTableView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(VeloraTheme.obsidianBase)

                    // Bottom DaisyDisk-style Collector Drawer
                    if !showBloomInspector {
                        CollectorTrayView(viewModel: viewModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showBloomInspector {
                    Divider()
                        .overlay(VeloraTheme.cardBorder)
                    BloomInspectorView(viewModel: viewModel)
                        .frame(width: 278)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showBloomInspector)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.collectorItems.isEmpty)
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
                            .foregroundColor(isSearchFocused ? VeloraTheme.accentCyan : VeloraTheme.textSecondary)

                        TextField("Search anything (e.g. ext:rs size:>10MB !target)...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .foregroundColor(VeloraTheme.textPrimary)
                            .onChange(of: viewModel.searchQuery) { _, newValue in
                                viewModel.performSearch(query: newValue, debounce: true)
                            }
                            .onKeyPress(.escape) {
                                viewModel.clearSearch()
                                isSearchFocused = false
                                return .handled
                            }

                        if viewModel.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        } else if !viewModel.searchQuery.isEmpty {
                            Button(action: {
                                viewModel.clearSearch()
                                isSearchFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(VeloraTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear search (Esc)")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: 220, idealWidth: 330, maxWidth: 440)
                    .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSearchFocused ? VeloraTheme.accentCyan.opacity(0.65) : VeloraTheme.cardBorder, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        isSearchFocused = true
                    }
                }

                // Actions
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showBloomInspector.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(showBloomInspector ? VeloraTheme.accentViolet : VeloraTheme.textSecondary)
                    }
                    .help("Toggle cleanup inspector")
                }
            }
        }
        .tint(VeloraTheme.accentViolet)
        .onAppear {
            viewModel.loadCachedSnapshotIfAvailable()
        }
        .background(
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = NSColor(red: 32/255.0, green: 32/255.0, blue: 49/255.0, alpha: 1.0)
                window.minSize = NSSize(width: VeloraTheme.minWindowWidth, height: VeloraTheme.minWindowHeight)
            }
        )
        .background(VeloraTheme.obsidianBase)
        .background {
            Button(action: {
                isSearchFocused = true
            }) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }
}
