import AppKit
import SwiftUI
import VeloraCore

extension OrphanedResidueRecord: Identifiable {
    public var id: String { path }
}

public struct OrphanedLeftoversView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedFilter: String = "All"
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var filteredResidues: [OrphanedResidueRecord] {
        var result = viewModel.orphanedResidues

        if selectedFilter != "All" {
            result = result.filter { $0.categoryName == selectedFilter }
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.inferredBundleId.lowercased().contains(query) ||
                $0.path.lowercased().contains(query)
            }
        }

        return result
    }

    private var stagedPaths: Set<String> {
        Set(viewModel.collectorItems.map { $0.path })
    }

    private var allFilteredStaged: Bool {
        !filteredResidues.isEmpty && filteredResidues.allSatisfy { stagedPaths.contains($0.path) }
    }

    private var totalLeftoverBytes: UInt64 {
        filteredResidues.reduce(0) { $0 + $1.sizeBytes }
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

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Application Support":
            return VeloraTheme.teal
        case "Caches & Logs":
            return VeloraTheme.amber
        case "Sandboxed Container":
            return Color.purple
        case "Preferences":
            return VeloraTheme.mint
        default:
            return .secondary
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.circle")
                            .font(.system(size: 16))
                            .foregroundColor(Color.red.opacity(0.85))
                        Text("Leftovers & Residue Hunter")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }

                    Text("Detects residual caches, containers, and support files from previously uninstalled applications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if totalLeftoverBytes > 0 {
                    Button(action: {
                        if allFilteredStaged {
                            for item in filteredResidues {
                                viewModel.removeCollected(path: item.path)
                            }
                        } else {
                            for item in filteredResidues {
                                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                            }
                        }
                    }) {
                        Label(
                            allFilteredStaged ? "Unstage All Leftovers" : "Collect All Leftovers (\(formatBytes(totalLeftoverBytes)))",
                            systemImage: allFilteredStaged ? "checkmark.circle.fill" : "sparkles"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(allFilteredStaged ? VeloraTheme.teal : .red.opacity(0.85))
                    .controlSize(.regular)
                }

                Button(action: {
                    viewModel.loadOrphanedResidues()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Rescan orphaned leftovers")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Filter Chips Bar
            HStack(spacing: 8) {
                FilterChip(title: "All", count: viewModel.orphanedResidues.count, isSelected: selectedFilter == "All") {
                    selectedFilter = "All"
                }

                let appSupportCount = viewModel.orphanedResidues.filter { $0.categoryName == "Application Support" }.count
                if appSupportCount > 0 {
                    FilterChip(title: "App Support", count: appSupportCount, isSelected: selectedFilter == "Application Support") {
                        selectedFilter = "Application Support"
                    }
                }

                let cachesCount = viewModel.orphanedResidues.filter { $0.categoryName == "Caches & Logs" }.count
                if cachesCount > 0 {
                    FilterChip(title: "Caches & Logs", count: cachesCount, isSelected: selectedFilter == "Caches & Logs") {
                        selectedFilter = "Caches & Logs"
                    }
                }

                let containerCount = viewModel.orphanedResidues.filter { $0.categoryName == "Sandboxed Container" }.count
                if containerCount > 0 {
                    FilterChip(title: "Containers", count: containerCount, isSelected: selectedFilter == "Sandboxed Container") {
                        selectedFilter = "Sandboxed Container"
                    }
                }

                let prefCount = viewModel.orphanedResidues.filter { $0.categoryName == "Preferences" }.count
                if prefCount > 0 {
                    FilterChip(title: "Preferences", count: prefCount, isSelected: selectedFilter == "Preferences") {
                        selectedFilter = "Preferences"
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search leftovers...", text: $searchFilter)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.5))

            Divider()

            if viewModel.isLoadingOrphans {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning Library directories for abandoned footprints...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredResidues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 42))
                        .foregroundColor(VeloraTheme.mint)
                    Text("No Orphaned Leftovers Found")
                        .font(.title3.weight(.bold))
                    Text("Your ~/Library is free from residual traces of uninstalled applications.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredResidues) { item in
                        let isStaged = stagedPaths.contains(item.path)
                        OrphanCard(
                            item: item,
                            isStaged: isStaged,
                            categoryColor: categoryColor(item.categoryName),
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
                .listStyle(.plain)
            }
        }
        .onAppear {
            if viewModel.orphanedResidues.isEmpty {
                viewModel.loadOrphanedResidues()
            }
        }
    }
}

// MARK: - Orphan Card Component

private struct OrphanCard: View {
    let item: OrphanedResidueRecord
    let isStaged: Bool
    let categoryColor: Color
    let formatBytes: (UInt64) -> String
    let formatDate: (UInt64) -> String
    let onToggleCollect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(categoryColor)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(.body, design: .rounded, weight: .bold))

                    Text(item.categoryName)
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.12), in: Capsule())

                    if isStaged {
                        Text("STAGED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.teal.opacity(0.15), in: Capsule())
                    }

                    if !item.inferredBundleId.isEmpty && item.inferredBundleId != item.name {
                        Text("(\(item.inferredBundleId))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Text(item.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("• Modified \(formatDate(item.modifiedSecs))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(formatBytes(item.sizeBytes))
                .font(.system(.subheadline, design: .monospaced, weight: .bold))

            // Reveal in Finder
            Button(action: {
                let url = URL(fileURLWithPath: item.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Reveal in Finder")

            // QuickLook preview
            Button(action: {
                let url = URL(fileURLWithPath: item.path)
                QuickLookCoordinator.shared.togglePreview(for: url)
            }) {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("QuickLook preview")

            // Stage into Collector / Remove
            Button(action: onToggleCollect) {
                Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundColor(isStaged ? VeloraTheme.teal : .orange)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isStaged ? "Remove from Collector Tray" : "Stage into Collector Tray")
        }
        .padding(12)
        .background(
            isStaged
                ? VeloraTheme.teal.opacity(0.06)
                : Color(nsColor: .controlBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isStaged
                        ? VeloraTheme.teal.opacity(0.4)
                        : Color.primary.opacity(0.06),
                    lineWidth: isStaged ? 1.5 : 1
                )
        )
    }
}

// MARK: - Reusable Filter Chip

private struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .medium)
                Text("\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
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
