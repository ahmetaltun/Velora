import AppKit
import SwiftUI
import VeloraCore

extension PackageCacheRecord: Identifiable {
    public var id: String { path }
}

public struct PackageCachesView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedEcosystem: String = "All"
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: PackageCacheSummaryRecord? {
        viewModel.packageCacheSummary
    }

    private var filteredItems: [PackageCacheRecord] {
        guard let items = summary?.items else { return [] }
        var result = items
        if selectedEcosystem != "All" {
            result = result.filter { $0.ecosystemName.localizedCaseInsensitiveContains(selectedEcosystem) }
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.ecosystemName.lowercased().contains(query) ||
                $0.path.lowercased().contains(query)
            }
        }

        return result
    }

    private var stagedPaths: Set<String> {
        Set(viewModel.collectorItems.map { $0.path })
    }

    private var collectableItems: [PackageCacheRecord] {
        guard let items = summary?.items else { return [] }
        return items.filter { $0.canCollect }
    }

    private var allCollectableStaged: Bool {
        !collectableItems.isEmpty && collectableItems.allSatisfy { stagedPaths.contains($0.path) }
    }

    private var totalBytes: UInt64 {
        summary?.totalBytes ?? 0
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
                title: "Package & Container Caches",
                subtitle: "Homebrew bottles, Cargo registry, npm/yarn, pip/uv wheels, Gradle, and Docker VM",
                systemImage: "shippingbox.circle.fill",
                accentColor: VeloraTheme.accentAmber
            ) {
                HStack(spacing: 10) {
                    // Docker Deep Inspection Jump Button
                    Button(action: {
                        viewModel.activeSidebarId = "tool_docker"
                        if viewModel.dockerSummary == nil {
                            viewModel.loadDockerSummary()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cylinder.split.1x2")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Deep Inspect Docker")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.accentBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.accentBlue.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.accentBlue.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Opens Docker Deep Inspection to audit dangling layers, unused volumes, and VM disk compaction")

                    // Prune Docker Button
                    Button(action: {
                        viewModel.pruneDocker()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Prune Docker")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(VeloraTheme.obsidianElevated, in: Capsule())
                        .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Prunes dangling Docker images and build cache via docker system prune")

                    // Collect All Collectable Caches
                    if totalBytes > 0 {
                        Button(action: {
                            if allCollectableStaged {
                                for item in collectableItems {
                                    viewModel.removeCollected(path: item.path)
                                }
                            } else {
                                for item in collectableItems {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: allCollectableStaged ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(allCollectableStaged ? "Unstage All" : "Collect All (\(formatBytes(totalBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: allCollectableStaged
                                        ? [VeloraTheme.accentEmerald, VeloraTheme.accentCyan]
                                        : [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: (allCollectableStaged ? VeloraTheme.accentEmerald : VeloraTheme.accentViolet).opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        viewModel.loadPackageCaches()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan package caches")
                }
            }

            // Docker Prune Status banner
            if let status = viewModel.dockerPruneStatus {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(VeloraTheme.accentCyan)
                    Text(status)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.dockerPruneStatus = nil
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

            // Ecosystem Filter Chips
            HStack(spacing: 8) {
                ToolFilterChip(title: "All", isSelected: selectedEcosystem == "All", accentColor: VeloraTheme.accentAmber) { selectedEcosystem = "All" }
                ToolFilterChip(title: "Homebrew", isSelected: selectedEcosystem == "Homebrew", accentColor: VeloraTheme.accentAmber) { selectedEcosystem = "Homebrew" }
                ToolFilterChip(title: "Cargo (Rust)", isSelected: selectedEcosystem == "Cargo", accentColor: Color(hex: "#DEA584")) { selectedEcosystem = "Cargo" }
                ToolFilterChip(title: "NPM / Yarn", isSelected: selectedEcosystem == "Node", accentColor: VeloraTheme.accentEmerald) { selectedEcosystem = "Node" }
                ToolFilterChip(title: "Python (pip/uv)", isSelected: selectedEcosystem == "Python", accentColor: VeloraTheme.accentBlue) { selectedEcosystem = "Python" }
                ToolFilterChip(title: "JVM (Gradle)", isSelected: selectedEcosystem == "JVM", accentColor: VeloraTheme.accentViolet) { selectedEcosystem = "JVM" }
                ToolFilterChip(title: "Docker", isSelected: selectedEcosystem == "Docker", accentColor: VeloraTheme.accentCyan) { selectedEcosystem = "Docker" }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Search package caches...", text: $searchFilter)
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

                Text("Total: \(formatBytes(totalBytes))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(VeloraTheme.textMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(VeloraTheme.obsidianElevated.opacity(0.6))
            .overlay(alignment: .bottom) {
                Divider().overlay(VeloraTheme.cardBorder)
            }

            // Content Area
            if viewModel.isLoadingPackageCaches {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Scanning package manager and container caches...")
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
                            .fill(VeloraTheme.accentAmber.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 32))
                            .foregroundColor(VeloraTheme.accentAmber)
                    }
                    Text("No Caches Detected")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("Your global package manager directories are clean, or no caches match the active filter.")
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
                        PackageCacheCard(
                            item: item,
                            isStaged: isStaged,
                            formatBytes: formatBytes,
                            formatDate: formatRelativeDate,
                            onToggleCollect: {
                                guard item.canCollect else { return }
                                if isStaged {
                                    viewModel.removeCollected(path: item.path)
                                } else {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            },
                            onInspectDocker: {
                                viewModel.activeSidebarId = "tool_docker"
                                if viewModel.dockerSummary == nil {
                                    viewModel.loadDockerSummary()
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
            if viewModel.packageCacheSummary == nil {
                viewModel.loadPackageCaches()
            }
        }
    }
}

// MARK: - Package Cache Card Component

private struct PackageCacheCard: View {
    let item: PackageCacheRecord
    let isStaged: Bool
    let formatBytes: (UInt64) -> String
    let formatDate: (UInt64) -> String
    let onToggleCollect: () -> Void
    let onInspectDocker: () -> Void

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

                    Text(item.ecosystemName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15), in: Capsule())

                    if !item.canCollect {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                            Text("Locked")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(VeloraTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .help("Direct deletion disabled — use dedicated CLI prune (e.g. Prune Docker)")
                    }

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
            if item.canCollect {
                Button(action: onToggleCollect) {
                    Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle.fill")
                        .foregroundColor(isStaged ? VeloraTheme.accentCyan : VeloraTheme.accentAmber)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(isStaged ? "Remove from Collector Tray" : "Stage into Collector Tray")
            } else if item.ecosystemName.localizedCaseInsensitiveContains("Docker") {
                Button(action: onInspectDocker) {
                    HStack(spacing: 4) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Deep Inspect")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(VeloraTheme.accentBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VeloraTheme.accentBlue.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Launch Docker Deep Inspection to analyze dangling layers, unused volumes, and BuildKit cache")
            } else {
                Image(systemName: "lock")
                    .foregroundColor(VeloraTheme.textMuted.opacity(0.5))
                    .font(.system(size: 14))
                    .help("Direct deletion disabled — use Prune Docker")
            }
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

            if item.canCollect {
                Divider()

                Button(isStaged ? "Remove from Collector" : "Stage for Cleanup") {
                    onToggleCollect()
                }
            }
        }
    }
}
