import AppKit
import SwiftUI
import VeloraCore

extension XcodeItemRecord: Identifiable {
    public var id: String { path }
}

public struct XcodeStorageView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedCategory: String = "All"
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: XcodeSummaryRecord? {
        viewModel.xcodeSummary
    }

    private var filteredItems: [XcodeItemRecord] {
        guard let items = summary?.items else { return [] }
        var result = items
        if selectedCategory != "All" {
            result = result.filter { $0.categoryName.localizedCaseInsensitiveContains(selectedCategory) }
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.categoryName.lowercased().contains(query) ||
                $0.path.lowercased().contains(query)
            }
        }

        return result
    }

    private var stagedPaths: Set<String> {
        Set(viewModel.collectorItems.map { $0.path })
    }

    private var derivedDataItems: [XcodeItemRecord] {
        guard let items = summary?.items else { return [] }
        return items.filter { $0.categoryName.contains("DerivedData") }
    }

    private var allDerivedDataStaged: Bool {
        !derivedDataItems.isEmpty && derivedDataItems.allSatisfy { stagedPaths.contains($0.path) }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatRelativeDate(secs: UInt64) -> String {
        guard secs > 0 else { return "Unknown" }
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
                            if allDerivedDataStaged {
                                for item in derivedDataItems {
                                    viewModel.removeCollected(path: item.path)
                                }
                            } else {
                                for item in derivedDataItems {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: allDerivedDataStaged ? "checkmark.circle.fill" : "shippingbox.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(allDerivedDataStaged ? "Unstage DerivedData" : "Collect DerivedData (\(formatBytes(ddBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: allDerivedDataStaged
                                        ? [VeloraTheme.accentEmerald, VeloraTheme.accentCyan]
                                        : [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: (allDerivedDataStaged ? VeloraTheme.accentEmerald : VeloraTheme.accentViolet).opacity(0.35), radius: 6, x: 0, y: 2)
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

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Search Xcode items...", text: $searchFilter)
                        .textFieldStyle(.plain)
                        .foregroundColor(VeloraTheme.textPrimary)
                        .frame(width: 140)
                    if !searchFilter.isEmpty {
                        Button(action: { searchFilter = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(VeloraTheme.obsidianElevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(VeloraTheme.cardBorder, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(VeloraTheme.obsidianElevated.opacity(0.6))
            .overlay(alignment: .bottom) {
                Divider().overlay(VeloraTheme.cardBorder)
            }

            // Content Area
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
                    Text("Xcode developer directory has zero caches here, or no items match the search query.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        let isStaged = stagedPaths.contains(item.path)
                        XcodeItemCard(
                            item: item,
                            isStaged: isStaged,
                            formatBytes: formatBytes,
                            formatDate: formatRelativeDate,
                            onToggleCollect: {
                                if isStaged {
                                    viewModel.removeCollected(path: item.path)
                                } else {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(VeloraTheme.obsidianBase)
                .listStyle(.plain)
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

// MARK: - Xcode Item Card Component

private struct XcodeItemCard: View {
    let item: XcodeItemRecord
    let isStaged: Bool
    let formatBytes: (UInt64) -> String
    let formatDate: (UInt64) -> String
    let onToggleCollect: () -> Void

    private var accentColor: Color {
        Color(hex: item.colorHex)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(item.categoryName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15), in: Capsule())

                    if isStaged {
                        Text("STAGED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.accentCyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentCyan.opacity(0.18), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Text(item.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(VeloraTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if item.modifiedSecs > 0 {
                        Text("• Modified \(formatDate(item.modifiedSecs))")
                            .font(.system(size: 10))
                            .foregroundColor(VeloraTheme.textSecondary)
                    }
                }
            }

            Spacer()

            Text(formatBytes(item.sizeBytes))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(VeloraTheme.textPrimary)

            // Reveal in Finder
            Button(action: {
                let url = URL(fileURLWithPath: item.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(VeloraTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            // QuickLook preview
            Button(action: {
                let url = URL(fileURLWithPath: item.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }) {
                Image(systemName: "eye")
                    .foregroundColor(VeloraTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("QuickLook preview")

            // Stage into Collector / Remove
            Button(action: onToggleCollect) {
                Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundColor(isStaged ? VeloraTheme.accentCyan : VeloraTheme.accentEmerald)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isStaged ? "Remove from Collector Tray" : "Stage into Collector Tray")
        }
        .padding(12)
        .background(
            isStaged
                ? VeloraTheme.accentCyan.opacity(0.08)
                : VeloraTheme.obsidianSurface,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isStaged
                        ? VeloraTheme.accentCyan.opacity(0.4)
                        : VeloraTheme.cardBorder,
                    lineWidth: 1
                )
        )
        .contextMenu {
            Button("Quick Look") {
                let url = URL(fileURLWithPath: item.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Reveal in Finder") {
                let url = URL(fileURLWithPath: item.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            Divider()

            Button(isStaged ? "Remove from Collector" : "Stage for Cleanup") {
                onToggleCollect()
            }
        }
    }
}
