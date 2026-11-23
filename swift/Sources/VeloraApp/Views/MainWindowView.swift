import SwiftUI
import VeloraCore

public struct MainWindowView: View {
    @Bindable public var viewModel: VeloraViewModel
    @ObservedObject private var permissionManager = PermissionManager.shared
    @AppStorage("isCleanupInspectorVisible") private var showBloomInspector: Bool = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canSearch: Bool {
        viewModel.hasIndexedData && !viewModel.isInteractionDisabled
    }

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 245, ideal: 265, max: 310)
        } detail: {
            GeometryReader { viewport in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Full Disk Access Security Banner
                        if !permissionManager.hasFullDiskAccess && !permissionManager.isBannerDismissed {
                            FullDiskAccessBannerView()
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .scale(scale: 0.96).combined(with: .opacity)
                                    )
                                )
                        }

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

                        if let notice = viewModel.catalogNotice {
                            HStack(alignment: .top) {
                                Label(notice, systemImage: "info.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Dismiss", systemImage: "xmark") {
                                    viewModel.catalogNotice = nil
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                            }
                            .font(.callout)
                            .padding(12)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
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
                            } else if viewModel.activeSidebarId == "tool_docker" {
                                DockerStorageView(viewModel: viewModel)
                            } else if viewModel.activeSidebarId == "tool_ai_models" {
                                ModelWeightHunterView(viewModel: viewModel)
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
                            } else if viewModel.activeSidebarId == "tool_shredder" {
                                SecureShredderView(viewModel: viewModel)
                            } else {
                                FileTableView(viewModel: viewModel)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(VeloraTheme.obsidianBase)

                        // Bottom DaisyDisk-style Collector Drawer
                        if !showBloomInspector || viewModel.isCleaning {
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
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: showBloomInspector)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: viewModel.collectorItems.isEmpty)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78), value: viewModel.isScanning)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: permissionManager.hasFullDiskAccess)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: permissionManager.isBannerDismissed)
            .toolbar {
                // Navigation controls
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: {
                        viewModel.navigateToRoot()
                    }) {
                        Label("Browse Catalog", systemImage: "internaldrive").labelStyle(.iconOnly)
                    }
                    .disabled(viewModel.isInteractionDisabled)
                    .opacity(viewModel.isInteractionDisabled ? 0.45 : 1.0)
                    .help("Browse the catalog root")

                    Button(action: {
                        viewModel.navigateUp()
                    }) {
                        Label("Enclosing Folder", systemImage: "chevron.up").labelStyle(.iconOnly)
                    }
                    .disabled(viewModel.activeSidebarId != "tool_files" || viewModel.pathStack.count <= 1 || viewModel.isInteractionDisabled || viewModel.isSearchActive)
                    .opacity((viewModel.pathStack.count <= 1 || viewModel.isInteractionDisabled) ? 0.45 : 1.0)
                    .help("Navigate up one folder level")

                    // Current Path Pill
                    if viewModel.activeSidebarId == "tool_files" && !viewModel.isSearchActive {
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
                        .help(viewModel.currentPath)
                    }
                    if viewModel.isLoadingSnapshot {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Loading catalog…")
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
                            .foregroundColor(viewModel.isInteractionDisabled ? VeloraTheme.textMuted : (isSearchFocused ? VeloraTheme.accentCyan : VeloraTheme.textSecondary))

                        TextField(
                            viewModel.hasIndexedData ? "Search files" : "Scan to search files",
                            text: Binding(
                                get: { viewModel.searchQuery },
                                set: { viewModel.performSearch(query: $0, debounce: true) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .disabled(!canSearch)
                        .accessibilityLabel("Search indexed files")
                        .foregroundColor(canSearch ? VeloraTheme.textPrimary : VeloraTheme.textMuted)
                        .onKeyPress(.escape) {
                            viewModel.clearSearch()
                            isSearchFocused = false
                            return .handled
                        }

                        if viewModel.isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if !viewModel.searchQuery.isEmpty && canSearch {
                            Button(action: {
                                viewModel.clearSearch()
                                isSearchFocused = false
                            }) {
                                Label("Clear Search", systemImage: "xmark.circle.fill").labelStyle(.iconOnly)
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
                            .stroke(isSearchFocused && !viewModel.isInteractionDisabled ? VeloraTheme.accentCyan.opacity(0.65) : VeloraTheme.cardBorder, lineWidth: 1)
                    )
                    .opacity(viewModel.isInteractionDisabled ? 0.55 : 1.0)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        if canSearch {
                            isSearchFocused = true
                        }
                    }
                }

                // Actions
                ToolbarItemGroup(placement: .primaryAction) {
                    if viewModel.activeSidebarId == "tool_files" && !viewModel.isSearchActive {
                        Button("Scan This Folder", systemImage: "arrow.clockwise") {
                            viewModel.scanCurrentPath()
                        }
                        .labelStyle(.iconOnly)
                        .help("Scan this folder")
                        .disabled(viewModel.isInteractionDisabled)
                    }
                    Button(action: {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                            showBloomInspector.toggle()
                        }
                    }) {
                        Label("Cleanup Inspector", systemImage: "sidebar.right").labelStyle(.iconOnly)
                            .foregroundStyle(showBloomInspector ? VeloraTheme.accentViolet : VeloraTheme.textSecondary)
                    }
                    .help("Toggle cleanup inspector")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(VeloraTheme.accentViolet)
        .onChange(of: viewModel.isInteractionDisabled) { _, isDisabled in
            if isDisabled {
                isSearchFocused = false
            }
        }
        .onAppear {
            viewModel.loadCachedSnapshotIfAvailable()
        }
        .background(VeloraTheme.obsidianBase)
        .background {
            Button(action: {
                if canSearch {
                    isSearchFocused = true
                }
            }) {
                EmptyView()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .veloraTriggerRescan)) { _ in
            if !viewModel.isInteractionDisabled && !viewModel.isScanning {
                if viewModel.activeSidebarId == "tool_files" && !viewModel.isSearchActive {
                    viewModel.scanCurrentPath()
                } else {
                    viewModel.scanCatalog()
                }
            }
        }
    }
}
