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
                    if viewModel.shouldShowScanUI && viewModel.searchQuery.isEmpty {
                        ScanHeroWelcomeView(viewModel: viewModel)
                            .padding(24)
                    } else if !viewModel.searchQuery.isEmpty || viewModel.selectedViewMode == .table {
                        FileTableView(viewModel: viewModel)
                    } else {
                        SunburstCanvasView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                            .foregroundColor(.secondary)
                        Text((viewModel.currentPath as NSString).lastPathComponent.isEmpty ? "Macintosh HD" : (viewModel.currentPath as NSString).lastPathComponent)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    if viewModel.isLoadingSnapshot {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Indexing...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    }
                }

                // Instant Search Bar
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search anything (e.g. ext:rs size:>10MB !target)...", text: $viewModel.searchQuery)
                            .textFieldStyle(.plain)
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
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(minWidth: 280, idealWidth: 380, maxWidth: 500)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
    }
}
