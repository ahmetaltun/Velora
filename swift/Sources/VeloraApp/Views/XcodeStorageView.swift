import AppKit
import SwiftUI
import VeloraCore

extension XcodeItemRecord: Identifiable {
    public var id: String { path }
}

public struct XcodeStorageView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedCategory: String = "All"
    @State private var selectedItemIds = Set<String>()

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: XcodeSummaryRecord? {
        viewModel.xcodeSummary
    }

    private var filteredItems: [XcodeItemRecord] {
        guard let items = summary?.items else { return [] }
        if selectedCategory == "All" {
            return items
        }
        return items.filter { $0.categoryName.localizedCaseInsensitiveContains(selectedCategory) }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            BloomToolHeaderView(
                title: "Xcode Storage Inspector",
                subtitle: "DerivedData, build archives, device symbol caches, and simulator runtimes",
                systemImage: "wrench.and.screwdriver.fill",
                accentColor: VeloraTheme.accentEmerald
            ) {
                HStack(spacing: 10) {
                    // Prune Simulators Button
                    Button(action: {
                        viewModel.pruneUnavailableSimulators()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Prune Simulators")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Deletes unavailable CoreSimulator runtimes via xcrun simctl")

                    // Collect All DerivedData
                    if let ddBytes = summary?.derivedDataBytes, ddBytes > 0 {
                        Button(action: {
                            if let items = summary?.items {
                                for item in items where item.categoryName.contains("DerivedData") {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Collect DerivedData (\(formatBytes(ddBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: VeloraTheme.accentViolet.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        viewModel.loadXcodeSummary()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan Xcode storage")
                }
            }

            // Metric Cards Row
            if let s = summary {
                HStack(spacing: 12) {
                    ToolMetricCardView(title: "Total Xcode", value: formatBytes(s.totalBytes), accentColor: VeloraTheme.textPrimary)
                    ToolMetricCardView(title: "DerivedData", value: formatBytes(s.derivedDataBytes), accentColor: VeloraTheme.accentBlue)
                    ToolMetricCardView(title: "Archives", value: formatBytes(s.archivesBytes), accentColor: VeloraTheme.accentViolet)
                    ToolMetricCardView(title: "Device Support", value: formatBytes(s.deviceSupportBytes), accentColor: VeloraTheme.accentAmber)
                    ToolMetricCardView(title: "Simulators", value: formatBytes(s.simulatorBytes), accentColor: VeloraTheme.accentEmerald)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(VeloraTheme.obsidianElevated.opacity(0.4))
                .overlay(alignment: .bottom) {
                    Divider().overlay(VeloraTheme.cardBorder)
                }
            }

            // Prune status notification banner
            if let status = viewModel.pruneSimulatorsStatus {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(VeloraTheme.accentCyan)
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.pruneSimulatorsStatus = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(VeloraTheme.accentBlue.opacity(0.15))
                .overlay(alignment: .bottom) {
                    Divider().overlay(VeloraTheme.cardBorder)
                }
            }

            // Category Filter Bar
            HStack(spacing: 8) {
                ToolFilterChip(title: "All", isSelected: selectedCategory == "All", accentColor: VeloraTheme.accentEmerald) { selectedCategory = "All" }
                ToolFilterChip(title: "DerivedData", isSelected: selectedCategory == "DerivedData", accentColor: VeloraTheme.accentBlue) { selectedCategory = "DerivedData" }
                ToolFilterChip(title: "Archives", isSelected: selectedCategory == "Archives", accentColor: VeloraTheme.accentViolet) { selectedCategory = "Archives" }
                ToolFilterChip(title: "Device Support", isSelected: selectedCategory == "Device", accentColor: VeloraTheme.accentAmber) { selectedCategory = "Device" }
                ToolFilterChip(title: "Simulators", isSelected: selectedCategory == "Simulator", accentColor: VeloraTheme.accentEmerald) { selectedCategory = "Simulator" }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(VeloraTheme.obsidianElevated.opacity(0.6))
            .overlay(alignment: .bottom) {
                Divider().overlay(VeloraTheme.cardBorder)
            }

            // Content Table
            if viewModel.isLoadingXcode {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Analyzing Xcode storage directories...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else if filteredItems.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(VeloraTheme.accentEmerald.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "sparkles")
                            .font(.system(size: 32))
                            .foregroundColor(VeloraTheme.accentEmerald)
                    }
                    Text("No Items in This Category")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("Xcode developer directory has zero caches here.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                Table(filteredItems, selection: $selectedItemIds) {
                    TableColumn("Target / Project") { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)
                                Text(item.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(VeloraTheme.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .width(min: 220, ideal: 300)

                    TableColumn("Category") { item in
                        Text(item.categoryName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: item.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Size") { item in
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Action") { item in
                        Button(action: {
                            viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                        }) {
                            Text("Collect")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(VeloraTheme.obsidianElevated, in: Capsule())
                                .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .width(min: 70, ideal: 80)
                }
                .scrollContentBackground(.hidden)
                .background(VeloraTheme.obsidianBase)
                .onKeyPress(.space) {
                    if let firstId = selectedItemIds.first, let item = filteredItems.first(where: { $0.id == firstId }) {
                        QuickLookCoordinator.shared.togglePreview(for: item.path)
                        return .handled
                    }
                    return .ignored
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let firstId = ids.first, let item = filteredItems.first(where: { $0.id == firstId }) {
                        Button("Quick Look") {
                            QuickLookCoordinator.shared.togglePreview(for: item.path)
                        }
                        .keyboardShortcut(.space, modifiers: [])

                        Divider()

                        Button("Reveal in Finder") {
                            let url = URL(fileURLWithPath: item.path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }

                        Divider()

                        Button("Collect for Cleanup") {
                            viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                        }
                    }
                }
            }
        }
        .background(VeloraTheme.obsidianBase)
        .onAppear {
            if viewModel.xcodeSummary == nil {
                viewModel.loadXcodeSummary()
            }
        }
    }
}
