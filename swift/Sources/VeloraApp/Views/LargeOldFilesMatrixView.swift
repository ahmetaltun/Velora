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
            return VeloraTheme.accentAmber
        case "Media":
            return VeloraTheme.accentBlue
        case "Documents":
            return VeloraTheme.accentEmerald
        case "Archives":
            return VeloraTheme.accentViolet
        case "System Purgeable":
            return VeloraTheme.accentPink
        default:
            return VeloraTheme.accentCyan
        }
    }

    public var body: some View {
        ToolPage {
            // Header Bar
            BloomToolHeaderView(
                title: "Large & Old Files",
                subtitle: "Explore indexed files by size and age.",
                systemImage: "calendar.badge.clock",
                accentColor: VeloraTheme.accentPink
            ) {
                HStack(spacing: 12) {
                    if let summary = summary, summary.totalFiles > 0 {
                        Text("\(summary.totalFiles) files (\(formatBytes(summary.totalBytes)))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(VeloraTheme.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(VeloraTheme.obsidianElevated, in: Capsule())
                            .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))

                        if ancientTotalBytes > 0 {
                            Button(action: {
                                let ancientFiles = summary.files.filter { $0.ageIdx == 3 }
                                for file in ancientFiles {
                                    viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Collect Ancient (\(formatBytes(ancientTotalBytes)))")
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
                    }

                    Button(action: {
                        viewModel.loadLargeOldMatrix()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Recompute matrix")
                }
            }

            if viewModel.isLoadingLargeOldMatrix {
                ToolStatusView(title: "Analyzing file sizes and ages…")
            } else if let summary = summary, summary.totalFiles > 0 {
                MatrixHeatmapGrid(
                    cells: summary.cells,
                    selectedCellId: $selectedCellId,
                    formatBytes: formatBytes
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                ToolFilterBar(prompt: "Search files", selection: $selectedCategory, query: $searchFilter) {
                    Text("All categories").tag("All")
                    Text("Media").tag("Media")
                    Text("Archives").tag("Archives")
                    Text("Documents").tag("Documents")
                    Text("Developer").tag("Developer")
                }

                if selectedCellId != nil {
                    Button("Reset Cell Filter", systemImage: "xmark.circle") {
                        selectedCellId = nil
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                if filteredFiles.isEmpty {
                    ToolStatusView(title: "No matching files", message: "Try another cell or review your filters.", icon: "magnifyingglass")
                } else {
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
            } else {
                ToolStatusView(title: "No large or old files found", message: "Scan your catalog to see files by size and age.", icon: "calendar")
            }
        }
        .background(VeloraTheme.obsidianBase)
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
                Text("")
                    .frame(width: 65)

                ForEach(sizeHeaders, id: \.self) { header in
                    Text(header)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Matrix Rows (Age)
            ForEach(0..<4, id: \.self) { ageIdx in
                HStack(spacing: 4) {
                    Text(ageHeaders[ageIdx])
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
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
        .padding(10)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
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
                    .foregroundColor(cell.fileCount > 0 ? VeloraTheme.textPrimary : VeloraTheme.textMuted)

                Text(cell.totalBytes > 0 ? formatBytes(cell.totalBytes) : "0 B")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(cell.totalBytes > 0 ? VeloraTheme.textSecondary : VeloraTheme.textMuted.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? VeloraTheme.accentCyan.opacity(0.35)
                            : (cell.totalBytes > 0
                                ? (cell.ageIdx == 3
                                    ? VeloraTheme.accentPink.opacity(0.15 + 0.35 * intensity)
                                    : VeloraTheme.accentAmber.opacity(0.12 + 0.28 * intensity))
                                : Color.white.opacity(0.02))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? VeloraTheme.accentCyan : VeloraTheme.cardBorder,
                        lineWidth: isSelected ? 1.5 : 0.8
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
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                        .lineLimit(1)

                    Text(file.categoryName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.15), in: Capsule())

                    Text(file.ageLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(file.ageIdx == 3 ? VeloraTheme.accentPink : VeloraTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((file.ageIdx == 3 ? VeloraTheme.accentPink : Color.white.opacity(0.08)).opacity(0.15), in: Capsule())
                }

                Text(file.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VeloraTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(file.sizeBytes))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(VeloraTheme.textPrimary)

            // Reveal in Finder
            Button(action: {
                let url = URL(fileURLWithPath: file.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(VeloraTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")

            // QuickLook preview
            Button(action: {
                let url = URL(fileURLWithPath: file.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }) {
                Image(systemName: "eye")
                    .foregroundColor(VeloraTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("QuickLook preview")

            // Stage into Collector
            Button(action: onCollect) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(VeloraTheme.accentCyan)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Stage into Collector Tray")
        }
        .padding(12)
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
        )
    }
}
