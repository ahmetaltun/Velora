import AppKit
import SwiftUI
import VeloraCore

extension LargeOldFileRecord: Identifiable {
    public var id: String { path }
}

extension MatrixCellRecord: Identifiable {
    public var id: String { "\(ageIdx)_\(sizeIdx)" }
}

public struct LargeOldFilesMatrixView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedCellId: String? = nil
    @State private var selectedCategory: String = "All"
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: LargeOldMatrixSummaryRecord? {
        viewModel.largeOldMatrix
    }

    private var filteredFiles: [LargeOldFileRecord] {
        guard let summary = summary else { return [] }
        var files = summary.files

        // Filter by selected cell if any
        if let cellId = selectedCellId {
            let parts = cellId.split(separator: "_").compactMap { UInt32($0) }
            if parts.count == 2 {
                let ageIdx = parts[0]
                let sizeIdx = parts[1]
                files = files.filter { $0.ageIdx == ageIdx && $0.sizeIdx == sizeIdx }
            }
        }

        // Filter by category
        if selectedCategory != "All" {
            files = files.filter { $0.categoryName == selectedCategory }
        }

        // Search query
        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            files = files.filter {
                $0.name.lowercased().contains(query) ||
                $0.path.lowercased().contains(query)
            }
        }

        return files
    }

    private var ancientTotalBytes: UInt64 {
        guard let summary = summary else { return 0 }
        return summary.files
            .filter { $0.ageIdx == 3 } // Ancient (>1 yr)
            .reduce(0) { $0 + $1.sizeBytes }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func categoryColor(for category: String) -> Color {
        switch category {
        case "Developer", "DevCaches":
            return VeloraTheme.amber
        case "Media":
            return Color.blue
        case "Documents":
            return VeloraTheme.mint
        case "Archives":
            return Color.purple
        case "System Purgeable":
            return Color.red
        default:
            return VeloraTheme.teal
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16))
                            .foregroundColor(VeloraTheme.amber)
                        Text("Large & Old Files Matrix")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }
                    Text("Instant 2D Temporal × Size matrix computed in RAM from the indexed catalog")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let summary = summary, summary.totalFiles > 0 {
                    Text("\(summary.totalFiles) files (\(formatBytes(summary.totalBytes)))")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())

                    if ancientTotalBytes > 0 {
                        Button(action: {
                            let ancientFiles = summary.files.filter { $0.ageIdx == 3 }
                            for file in ancientFiles {
                                viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                            }
                        }) {
                            Label("Collect Ancient (\(formatBytes(ancientTotalBytes)))", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.85))
                        .controlSize(.regular)
                    }
                }

                Button(action: {
                    viewModel.loadLargeOldMatrix()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Recompute matrix")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            if viewModel.isLoadingLargeOldMatrix {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Analyzing catalog records for large and dormant files...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary = summary, summary.totalFiles > 0 {
                // PINNED CONTROLS AREA (4x4 Grid & Filter Bar)
                VStack(spacing: 8) {
                    // 4x4 Heatmap Matrix Grid Card
                    MatrixHeatmapGrid(
                        cells: summary.cells,
                        selectedCellId: $selectedCellId,
                        formatBytes: formatBytes
                    )

                    // Filter Chips Bar
                    HStack(spacing: 8) {
                        CategoryChip(title: "All", isSelected: selectedCategory == "All") {
                            selectedCategory = "All"
                        }
                        CategoryChip(title: "Media", isSelected: selectedCategory == "Media") {
                            selectedCategory = "Media"
                        }
                        CategoryChip(title: "Archives", isSelected: selectedCategory == "Archives") {
                            selectedCategory = "Archives"
                        }
                        CategoryChip(title: "Documents", isSelected: selectedCategory == "Documents") {
                            selectedCategory = "Documents"
                        }
                        CategoryChip(title: "Developer", isSelected: selectedCategory == "Developer") {
                            selectedCategory = "Developer"
                        }

                        if selectedCellId != nil {
                            Button("Reset Cell Filter") {
                                selectedCellId = nil
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundColor(VeloraTheme.teal)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Filter files...", text: $searchFilter)
                                .textFieldStyle(.plain)
                                .frame(width: 140)
                            if !searchFilter.isEmpty {
                                Button(action: { searchFilter = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)

                Divider()

                // DEDICATED SCROLLABLE VIRTUALIZED FILE LIST
                if filteredFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No Files Match Selected Filter")
                            .font(.headline)
                        Text("Try selecting a different quadrant in the matrix or clearing the category filter.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredFiles) { file in
                                LargeFileCard(
                                    file: file,
                                    categoryColor: categoryColor(for: file.categoryName),
                                    formatBytes: formatBytes,
                                    onCollect: {
                                        viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox.circle")
                        .font(.system(size: 42))
                        .foregroundColor(VeloraTheme.mint)
                    Text("No Large Files (> 50MB) Detected")
                        .font(.title3.weight(.bold))
                    Text("Your indexed storage has no files exceeding the 50MB threshold.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel.largeOldMatrix == nil {
                viewModel.loadLargeOldMatrix()
            }
        }
    }
}

// MARK: - 4x4 Heatmap Matrix Component

private struct MatrixHeatmapGrid: View {
    let cells: [MatrixCellRecord]
    @Binding var selectedCellId: String?
    let formatBytes: (UInt64) -> String

    private let ageHeaders = ["< 1 mo", "1 – 6 mo", "6 – 12 mo", "> 1 yr"]
    private let sizeHeaders = ["> 1 GB", "0.5 – 1 GB", "100 – 500 MB", "50 – 100 MB"]

    private var maxBytes: UInt64 {
        cells.map(\.totalBytes).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Size Column Headers
            HStack(spacing: 4) {
                Text("") // Top-left blank corner
                    .frame(width: 65)

                ForEach(sizeHeaders, id: \.self) { header in
                    Text(header)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Matrix Rows (Age)
            ForEach(0..<4, id: \.self) { ageIdx in
                HStack(spacing: 4) {
                    Text(ageHeaders[ageIdx])
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 65, alignment: .leading)

                    ForEach(0..<4, id: \.self) { sizeIdx in
                        let cellIdx = ageIdx * 4 + sizeIdx
                        if cellIdx < cells.count {
                            let cell = cells[cellIdx]
                            let isSelected = selectedCellId == cell.id

                            HeatmapCell(
                                cell: cell,
                                maxBytes: maxBytes,
                                isSelected: isSelected,
                                formatBytes: formatBytes
                            ) {
                                if isSelected {
                                    selectedCellId = nil
                                } else {
                                    selectedCellId = cell.id
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Individual Heatmap Cell

private struct HeatmapCell: View {
    let cell: MatrixCellRecord
    let maxBytes: UInt64
    let isSelected: Bool
    let formatBytes: (UInt64) -> String
    let onTap: () -> Void

    private var intensity: Double {
        guard maxBytes > 0 else { return 0 }
        return Double(cell.totalBytes) / Double(maxBytes)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                Text(cell.fileCount > 0 ? "\(cell.fileCount)" : "—")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(cell.fileCount > 0 ? .primary : .secondary.opacity(0.4))

                Text(cell.totalBytes > 0 ? formatBytes(cell.totalBytes) : "0 B")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? VeloraTheme.teal.opacity(0.35)
                            : (cell.totalBytes > 0
                                ? (cell.ageIdx == 3
                                    ? Color.red.opacity(0.12 + 0.3 * intensity)
                                    : VeloraTheme.amber.opacity(0.10 + 0.25 * intensity))
                                : Color.primary.opacity(0.03))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? VeloraTheme.teal : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Large File Card Component

private struct LargeFileCard: View {
    let file: LargeOldFileRecord
    let categoryColor: Color
    let formatBytes: (UInt64) -> String
    let onCollect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(file.name)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .lineLimit(1)

                    Text(file.categoryName)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.12), in: Capsule())

                    Text(file.ageLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(file.ageIdx == 3 ? .red : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((file.ageIdx == 3 ? Color.red : Color.secondary).opacity(0.1), in: Capsule())
                }

                Text(file.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(file.sizeBytes))
                .font(.system(.subheadline, design: .monospaced, weight: .bold))

            // Reveal in Finder
            Button(action: {
                let url = URL(fileURLWithPath: file.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Reveal in Finder")

            // QuickLook preview
            Button(action: {
                let url = URL(fileURLWithPath: file.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }) {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("QuickLook preview")

            // Stage into Collector
            Button(action: onCollect) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Stage into Collector Tray")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Category Chip

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? VeloraTheme.teal : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
