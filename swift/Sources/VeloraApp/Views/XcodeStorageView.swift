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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                        Text("Xcode Storage Inspector")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }

                    Text("DerivedData, build archives, device symbol caches, and simulator runtimes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Prune Simulators Button
                Button(action: {
                    viewModel.pruneUnavailableSimulators()
                }) {
                    Label("Prune Simulators", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
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
                        Label("Collect DerivedData (\(formatBytes(ddBytes)))", systemImage: "shippingbox")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.85))
                    .controlSize(.regular)
                }

                Button(action: {
                    viewModel.loadXcodeSummary()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Rescan Xcode storage")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Metric Cards Row
            if let s = summary {
                HStack(spacing: 12) {
                    MetricCard(title: "Total Xcode", value: formatBytes(s.totalBytes), color: .primary)
                    MetricCard(title: "DerivedData", value: formatBytes(s.derivedDataBytes), color: .blue)
                    MetricCard(title: "Archives", value: formatBytes(s.archivesBytes), color: .purple)
                    MetricCard(title: "Device Support", value: formatBytes(s.deviceSupportBytes), color: .orange)
                    MetricCard(title: "Simulators", value: formatBytes(s.simulatorBytes), color: .green)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.02))

                Divider()
            }

            // Prune status notification banner
            if let status = viewModel.pruneSimulatorsStatus {
                HStack {
                    Image(systemName: "info.circle")
                    Text(status)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.pruneSimulatorsStatus = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
            }

            // Category Filter Bar
            HStack(spacing: 8) {
                FilterTab(title: "All", isSelected: selectedCategory == "All") { selectedCategory = "All" }
                FilterTab(title: "DerivedData", isSelected: selectedCategory == "DerivedData") { selectedCategory = "DerivedData" }
                FilterTab(title: "Archives", isSelected: selectedCategory == "Archives") { selectedCategory = "Archives" }
                FilterTab(title: "Device Support", isSelected: selectedCategory == "Device") { selectedCategory = "Device" }
                FilterTab(title: "Simulators", isSelected: selectedCategory == "Simulator") { selectedCategory = "Simulator" }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider()

            // Content Table
            if viewModel.isLoadingXcode {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Analyzing Xcode storage directories...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                    Text("No Items in This Category")
                        .font(.headline)
                    Text("Xcode developer directory has zero caches here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredItems, selection: $selectedItemIds) {
                    TableColumn("Target / Project") { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                Text(item.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .width(min: 220, ideal: 300)

                    TableColumn("Category") { item in
                        Text(item.categoryName)
                            .font(.system(.caption, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: item.colorHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Size") { item in
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(.body, design: .monospaced, weight: .medium))
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Action") { item in
                        Button("Collect") {
                            viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .width(min: 70, ideal: 80)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
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
        .onAppear {
            if viewModel.xcodeSummary == nil {
                viewModel.loadXcodeSummary()
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FilterTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.blue : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
