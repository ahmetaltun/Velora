import AppKit
import SwiftUI
import VeloraCore

extension PackageCacheRecord: Identifiable {
    public var id: String { path }
}

public struct PackageCachesView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedEcosystem: String = "All"
    @State private var selectedItemIds = Set<String>()

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var summary: PackageCacheSummaryRecord? {
        viewModel.packageCacheSummary
    }

    private var filteredItems: [PackageCacheRecord] {
        guard let items = summary?.items else { return [] }
        if selectedEcosystem == "All" {
            return items
        }
        return items.filter { $0.ecosystemName.localizedCaseInsensitiveContains(selectedEcosystem) }
    }

    private var totalBytes: UInt64 {
        summary?.totalBytes ?? 0
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
                        Image(systemName: "shippingbox.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(VeloraTheme.teal)
                        Text("Package & Container Caches")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }

                    Text("Homebrew bottles, Cargo registry, npm/yarn, pip/uv wheels, Gradle, and Docker VM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Prune Docker Button
                Button(action: {
                    viewModel.pruneDocker()
                }) {
                    Label("Prune Docker", systemImage: "cylinder.split.1x2")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Prunes dangling Docker images and build cache via docker system prune")

                // Collect All Collectable Caches
                if totalBytes > 0 {
                    Button(action: {
                        if let items = summary?.items {
                            for item in items where item.canCollect {
                                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                            }
                        }
                    }) {
                        Label("Collect All (\(formatBytes(totalBytes)))", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VeloraTheme.teal)
                    .controlSize(.regular)
                }

                Button(action: {
                    viewModel.loadPackageCaches()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Rescan package caches")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Docker Prune Status banner
            if let status = viewModel.dockerPruneStatus {
                HStack {
                    Image(systemName: "info.circle")
                    Text(status)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.dockerPruneStatus = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
            }

            // Ecosystem Filter Chips
            HStack(spacing: 8) {
                CacheFilterChip(title: "All", isSelected: selectedEcosystem == "All") { selectedEcosystem = "All" }
                CacheFilterChip(title: "Homebrew", isSelected: selectedEcosystem == "Homebrew") { selectedEcosystem = "Homebrew" }
                CacheFilterChip(title: "Cargo (Rust)", isSelected: selectedEcosystem == "Cargo") { selectedEcosystem = "Cargo" }
                CacheFilterChip(title: "NPM / Yarn", isSelected: selectedEcosystem == "Node") { selectedEcosystem = "Node" }
                CacheFilterChip(title: "Python (pip/uv)", isSelected: selectedEcosystem == "Python") { selectedEcosystem = "Python" }
                CacheFilterChip(title: "JVM (Gradle)", isSelected: selectedEcosystem == "JVM") { selectedEcosystem = "JVM" }
                CacheFilterChip(title: "Docker", isSelected: selectedEcosystem == "Docker") { selectedEcosystem = "Docker" }

                Spacer()

                Text("Total: \(formatBytes(totalBytes))")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Divider()

            // Content Table
            if viewModel.isLoadingPackageCaches {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Scanning package manager and container caches...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 36))
                        .foregroundColor(VeloraTheme.teal)
                    Text("No Caches Detected")
                        .font(.headline)
                    Text("Your global package manager directories are clean.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredItems, selection: $selectedItemIds) {
                    TableColumn("Cache Target") { item in
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
                    .width(min: 240, ideal: 320)

                    TableColumn("Ecosystem") { item in
                        Text(item.ecosystemName)
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
                        if item.canCollect {
                            Button("Collect") {
                                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        } else {
                            Text("Protected")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
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

                        if item.canCollect {
                            Divider()
                            Button("Collect for Cleanup") {
                                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel.packageCacheSummary == nil {
                viewModel.loadPackageCaches()
            }
        }
    }
}

private struct CacheFilterChip: View {
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
                    isSelected ? VeloraTheme.teal : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
