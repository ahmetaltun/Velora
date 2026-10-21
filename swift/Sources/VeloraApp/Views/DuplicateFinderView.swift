import AppKit
import SwiftUI
import VeloraCore

extension DuplicateGroupRecord: Identifiable {
    public var id: String { groupId }
}

extension DuplicateFileRecord: Identifiable {
    public var id: String { path }
}

public struct DuplicateFinderView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var minSizeFilter: UInt64 = 1_000_000 // Default: 1MB
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: DuplicateSummaryRecord? {
        viewModel.duplicateSummary
    }

    private var filteredGroups: [DuplicateGroupRecord] {
        guard let summary = summary else { return [] }
        var groups = summary.groups

        // Exclude any file that no longer exists on disk
        groups = groups.compactMap { group in
            let existingFiles = group.files.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard existingFiles.count >= 2 else { return nil }
            if existingFiles.count == group.files.count {
                return group
            }
            var updated = group
            updated.files = existingFiles
            updated.fileCount = UInt32(existingFiles.count)
            updated.totalWastedBytes = group.sizeBytes * UInt64(existingFiles.count - 1)
            return updated
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            groups = groups.filter { group in
                group.files.contains {
                    $0.name.lowercased().contains(query) ||
                    $0.path.lowercased().contains(query)
                }
            }
        }

        return groups
    }

    private var stagedPaths: Set<String> {
        Set(viewModel.collectorItems.map { $0.path })
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func parseColor(hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (100, 149, 237)
        }
        return Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 16))
                            .foregroundColor(VeloraTheme.teal)
                        Text("Duplicate Finder")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }
                    Text("3-Tier Progressive Pipeline: Exact Size → 4KB Prefix Probe → Cryptographic SHA-256 Stream")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let summary = summary, summary.totalWastedBytes > 0 {
                    Text("\(summary.totalDuplicateFiles) files (\(formatBytes(summary.totalWastedBytes)) wasted)")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())

                    Button(action: {
                        for group in summary.groups {
                            // Stage all duplicates (skipping original)
                            for file in group.files where !file.isOriginal {
                                viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                            }
                        }
                    }) {
                        Label("Collect All Duplicates (\(formatBytes(summary.totalWastedBytes)))", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.85))
                    .controlSize(.regular)
                }

                Button(action: {
                    viewModel.loadDuplicates(minSizeBytes: minSizeFilter)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Rescan duplicates")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Filter bar
            HStack(spacing: 12) {
                Text("Minimum Size:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("", selection: $minSizeFilter) {
                    Text("> 1 MB").tag(UInt64(1_000_000))
                    Text("> 10 MB").tag(UInt64(10_000_000))
                    Text("> 50 MB").tag(UInt64(50_000_000))
                    Text("> 100 MB").tag(UInt64(100_000_000))
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .onChange(of: minSizeFilter) { _, newValue in
                    viewModel.loadDuplicates(minSizeBytes: newValue)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter duplicates...", text: $searchFilter)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.5))

            Divider()

            if viewModel.isLoadingDuplicates {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Executing 3-Tier Progressive Pipeline...")
                        .font(.headline)
                    Text("1. In-memory exact size filter → 2. 4KB prefix probes → 3. Multi-threaded SHA-256 verification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGroups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 42))
                        .foregroundColor(VeloraTheme.mint)
                    Text("No Duplicates Detected")
                        .font(.title3.weight(.bold))
                    Text("No byte-identical duplicate files found above \(formatBytes(minSizeFilter)).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredGroups) { group in
                        DuplicateGroupCard(
                            group: group,
                            formatBytes: formatBytes,
                            parseColor: parseColor,
                            stagedPaths: stagedPaths,
                            onStageDuplicates: {
                                for file in group.files where !file.isOriginal {
                                    viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                                }
                            },
                            onToggleCollect: { file in
                                if stagedPaths.contains(file.path) {
                                    viewModel.removeCollected(path: file.path)
                                } else {
                                    viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            if viewModel.duplicateSummary == nil {
                viewModel.loadDuplicates(minSizeBytes: minSizeFilter)
            }
        }
    }
}

// MARK: - Duplicate Group Card Component

private struct DuplicateGroupCard: View {
    let group: DuplicateGroupRecord
    let formatBytes: (UInt64) -> String
    let parseColor: (String) -> Color
    let stagedPaths: Set<String>
    let onStageDuplicates: () -> Void
    let onToggleCollect: (DuplicateFileRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Group Header
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.fill.on.square.fill")
                        .foregroundColor(VeloraTheme.teal)
                    Text("\(group.fileCount) Identical Copies")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }

                Text("(\(formatBytes(group.sizeBytes)) each)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Waste: \(formatBytes(group.totalWastedBytes))")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12), in: Capsule())

                Button(action: onStageDuplicates) {
                    Label("Stage Duplicates", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Stage all copies except the oldest original into Collector Tray")
            }

            Divider()

            // File items in group
            VStack(spacing: 6) {
                ForEach(group.files) { file in
                    DuplicateFileRow(
                        file: file,
                        isStaged: stagedPaths.contains(file.path),
                        categoryColor: parseColor(file.colorHex),
                        formatBytes: formatBytes,
                        onToggleCollect: { onToggleCollect(file) }
                    )
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Duplicate File Row Component

private struct DuplicateFileRow: View {
    let file: DuplicateFileRecord
    let isStaged: Bool
    let categoryColor: Color
    let formatBytes: (UInt64) -> String
    let onToggleCollect: () -> Void

    private var parentDirectoryName: String {
        let parent = (file.path as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text(parentDirectoryName)
                            .font(.system(size: 10, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))

                    if file.isOriginal {
                        Text("ORIGINAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.mint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(VeloraTheme.mint.opacity(0.15), in: Capsule())
                    } else {
                        Text("DUPLICATE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())

                        if isStaged {
                            Text("STAGED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(VeloraTheme.teal)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(VeloraTheme.teal.opacity(0.15), in: Capsule())
                        }
                    }
                }

                Text(file.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
            }

            Spacer()

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

            // Stage to Collector (only enabled if duplicate)
            if !file.isOriginal {
                Button(action: onToggleCollect) {
                    Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle.fill")
                        .foregroundColor(isStaged ? VeloraTheme.teal : .orange)
                }
                .buttonStyle(.plain)
                .help(isStaged ? "Remove from Collector Tray" : "Stage into Collector Tray")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            file.isOriginal
                ? VeloraTheme.mint.opacity(0.04)
                : Color.primary.opacity(0.02),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
