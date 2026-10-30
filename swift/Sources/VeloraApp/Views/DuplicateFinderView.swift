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

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            groups = groups.filter { group in
                group.files.contains {
                    $0.name.localizedCaseInsensitiveContains(query) ||
                    $0.path.localizedCaseInsensitiveContains(query)
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
            BloomToolHeaderView(
                title: "Duplicate Finder",
                subtitle: "3-Tier Progressive Pipeline: Exact Size → 4KB Prefix Probe → Cryptographic SHA-256 Stream",
                systemImage: "doc.on.doc.fill",
                accentColor: VeloraTheme.accentCyan
            ) {
                HStack(spacing: 12) {
                    if let summary = summary, summary.totalWastedBytes > 0 {
                        Text("\(summary.totalDuplicateFiles) files (\(formatBytes(summary.totalWastedBytes)) wasted)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(VeloraTheme.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(VeloraTheme.obsidianElevated, in: Capsule())
                            .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))

                        Button(action: {
                            for group in summary.groups {
                                for file in group.files where !file.isOriginal {
                                    viewModel.collect(path: file.path, size: file.sizeBytes, isDir: false)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Collect All Duplicates (\(formatBytes(summary.totalWastedBytes)))")
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
                        viewModel.loadDuplicates(minSizeBytes: minSizeFilter)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan duplicates")
                }
            }

            // Filter bar
            HStack(spacing: 12) {
                Text("Minimum Size:")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(VeloraTheme.textSecondary)

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
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Filter duplicates...", text: $searchFilter)
                        .textFieldStyle(.plain)
                        .foregroundColor(VeloraTheme.textPrimary)
                        .frame(width: 160)
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

            if viewModel.isLoadingDuplicates {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Executing 3-Tier Progressive Pipeline...")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("1. In-memory exact size filter → 2. 4KB prefix probes → 3. Multi-threaded SHA-256 verification")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else if filteredGroups.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(VeloraTheme.accentCyan.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 32))
                            .foregroundColor(VeloraTheme.accentCyan)
                    }
                    Text("No Duplicates Detected")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("No byte-identical duplicate files found above \(formatBytes(minSizeFilter)).")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                List {
                    ForEach(filteredGroups) { group in
                        let groupFilePaths = Set(group.files.map { $0.path })
                        let groupStagedPaths = stagedPaths.intersection(groupFilePaths)
                        DuplicateGroupCard(
                            group: group,
                            formatBytes: formatBytes,
                            parseColor: parseColor,
                            stagedPaths: groupStagedPaths,
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
                        .equatable()
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
            if viewModel.duplicateSummary == nil {
                viewModel.loadDuplicates(minSizeBytes: minSizeFilter)
            }
        }
    }
}

// MARK: - Duplicate Group Card Component

private struct DuplicateGroupCard: View, Equatable {
    let group: DuplicateGroupRecord
    let formatBytes: (UInt64) -> String
    let parseColor: (String) -> Color
    let stagedPaths: Set<String>
    let onStageDuplicates: () -> Void
    let onToggleCollect: (DuplicateFileRecord) -> Void

    static func == (lhs: DuplicateGroupCard, rhs: DuplicateGroupCard) -> Bool {
        lhs.group == rhs.group && lhs.stagedPaths == rhs.stagedPaths
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Group Header
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "square.fill.on.square.fill")
                        .foregroundColor(VeloraTheme.accentCyan)
                    Text("\(group.fileCount) Identical Copies")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                }

                Text("(\(formatBytes(group.sizeBytes)) each)")
                    .font(.system(size: 11))
                    .foregroundColor(VeloraTheme.textSecondary)

                Spacer()

                Text("Waste: \(formatBytes(group.totalWastedBytes))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(VeloraTheme.accentAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(VeloraTheme.accentAmber.opacity(0.15), in: Capsule())

                Button(action: onStageDuplicates) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Stage Duplicates")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(VeloraTheme.accentCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(VeloraTheme.accentCyan.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Stage all copies except the oldest original into Collector Tray")
            }

            Divider().overlay(VeloraTheme.cardBorder)

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
        .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(VeloraTheme.cardBorder, lineWidth: 1)
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
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(file.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    if file.isOriginal {
                        Text("ORIGINAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.accentEmerald)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(VeloraTheme.accentEmerald.opacity(0.15), in: Capsule())
                    }

                    if isStaged {
                        Text("STAGED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.accentCyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(VeloraTheme.accentCyan.opacity(0.18), in: Capsule())
                    }
                }

                Text(file.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VeloraTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(formatBytes(file.sizeBytes))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(VeloraTheme.textSecondary)

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

            // Stage into Collector / Remove
            Button(action: onToggleCollect) {
                Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundColor(isStaged ? VeloraTheme.accentCyan : (file.isOriginal ? VeloraTheme.textMuted : VeloraTheme.accentAmber))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isStaged ? "Remove from Collector Tray" : "Stage into Collector Tray")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isStaged
                ? VeloraTheme.accentCyan.opacity(0.08)
                : VeloraTheme.obsidianElevated.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
