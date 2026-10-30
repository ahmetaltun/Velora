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
            return VeloraTheme.accentBlue
        case "Caches & Logs":
            return VeloraTheme.accentAmber
        case "Sandboxed Container":
            return VeloraTheme.accentViolet
        case "Preferences":
            return VeloraTheme.accentEmerald
        default:
            return VeloraTheme.accentPink
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            BloomToolHeaderView(
                title: "Leftovers & Residue Hunter",
                subtitle: "Detects residual caches, containers, and support files from previously uninstalled applications",
                systemImage: "trash.circle.fill",
                accentColor: VeloraTheme.accentPink
            ) {
                HStack(spacing: 10) {
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
                            HStack(spacing: 6) {
                                Image(systemName: allFilteredStaged ? "checkmark.circle.fill" : "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                Text(allFilteredStaged ? "Unstage All Leftovers" : "Collect All Leftovers (\(formatBytes(totalLeftoverBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: allFilteredStaged
                                        ? [VeloraTheme.accentEmerald, VeloraTheme.accentCyan]
                                        : [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: (allFilteredStaged ? VeloraTheme.accentEmerald : VeloraTheme.accentViolet).opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        viewModel.loadOrphanedResidues()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan orphaned leftovers")
                }
            }

            // Filter Chips Bar
            HStack(spacing: 8) {
                ToolFilterChip(
                    title: "All (\(viewModel.orphanedResidues.count))",
                    isSelected: selectedFilter == "All",
                    accentColor: VeloraTheme.accentPink
                ) {
                    selectedFilter = "All"
                }

                let appSupportCount = viewModel.orphanedResidues.filter { $0.categoryName == "Application Support" }.count
                if appSupportCount > 0 {
                    ToolFilterChip(
                        title: "App Support (\(appSupportCount))",
                        isSelected: selectedFilter == "Application Support",
                        accentColor: VeloraTheme.accentBlue
                    ) {
                        selectedFilter = "Application Support"
                    }
                }

                let cachesCount = viewModel.orphanedResidues.filter { $0.categoryName == "Caches & Logs" }.count
                if cachesCount > 0 {
                    ToolFilterChip(
                        title: "Caches & Logs (\(cachesCount))",
                        isSelected: selectedFilter == "Caches & Logs",
                        accentColor: VeloraTheme.accentAmber
                    ) {
                        selectedFilter = "Caches & Logs"
                    }
                }

                let containerCount = viewModel.orphanedResidues.filter { $0.categoryName == "Sandboxed Container" }.count
                if containerCount > 0 {
                    ToolFilterChip(
                        title: "Containers (\(containerCount))",
                        isSelected: selectedFilter == "Sandboxed Container",
                        accentColor: VeloraTheme.accentViolet
                    ) {
                        selectedFilter = "Sandboxed Container"
                    }
                }

                let prefCount = viewModel.orphanedResidues.filter { $0.categoryName == "Preferences" }.count
                if prefCount > 0 {
                    ToolFilterChip(
                        title: "Preferences (\(prefCount))",
                        isSelected: selectedFilter == "Preferences",
                        accentColor: VeloraTheme.accentEmerald
                    ) {
                        selectedFilter = "Preferences"
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Search leftovers...", text: $searchFilter)
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

            if viewModel.isLoadingOrphans {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning Library directories for abandoned footprints...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else if filteredResidues.isEmpty {
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
                    Text("No Orphaned Leftovers Found")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("Your ~/Library is free from residual traces of uninstalled applications.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
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
                .scrollContentBackground(.hidden)
                .background(VeloraTheme.obsidianBase)
                .listStyle(.plain)
            }
        }
        .background(VeloraTheme.obsidianBase)
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
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(item.categoryName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.15), in: Capsule())

                    if isStaged {
                        Text("STAGED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(VeloraTheme.accentCyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VeloraTheme.accentCyan.opacity(0.18), in: Capsule())
                    }

                    if !item.inferredBundleId.isEmpty && item.inferredBundleId != item.name {
                        Text("(\(item.inferredBundleId))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(VeloraTheme.textMuted)
                    }
                }

                HStack(spacing: 10) {
                    Text(item.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(VeloraTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("• Modified \(formatDate(item.modifiedSecs))")
                        .font(.system(size: 10))
                        .foregroundColor(VeloraTheme.textSecondary)
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
                    .foregroundColor(isStaged ? VeloraTheme.accentCyan : VeloraTheme.accentPink)
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
    }
}
