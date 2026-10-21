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
            ToolHeaderView(
                title: "Package & Container Caches",
                subtitle: "Homebrew bottles, Cargo registry, npm/yarn, pip/uv wheels, Gradle, and Docker VM",
                systemImage: "shippingbox.circle.fill",
                accentColor: VeloraTheme.accentAmber
            ) {
                HStack(spacing: 10) {
                    // Prune Docker Button
                    Button(action: {
                        viewModel.pruneDocker()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "cylinder.split.1x2")
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
                            if let items = summary?.items {
                                for item in items where item.canCollect {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Collect All (\(formatBytes(totalBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [VeloraTheme.accentAmber, Color(hex: "#FF8C00")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: VeloraTheme.accentAmber.opacity(0.35), radius: 6, x: 0, y: 2)
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

            // Content Table
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
                    Text("Your global package manager directories are clean.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                Table(filteredItems, selection: $selectedItemIds) {
                    TableColumn("Cache Target") { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(VeloraTheme.textPrimary)
                                Text(item.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(VeloraTheme.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .width(min: 240, ideal: 320)

                    TableColumn("Ecosystem") { item in
                        Text(item.ecosystemName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: item.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Size") { item in
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Action") { item in
                        if item.canCollect {
                            Button(action: {
                                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                            }) {
                                Text("Collect")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(VeloraTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(VeloraTheme.obsidianElevated, in: Capsule())
                                    .overlay(Capsule().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Locked")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(VeloraTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.04), in: Capsule())
                        }
                    }
                    .width(min: 70, ideal: 80)
                }
                .scrollContentBackground(.hidden)
                .background(VeloraTheme.obsidianBase)
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
        .background(VeloraTheme.obsidianBase)
        .onAppear {
            if viewModel.packageCacheSummary == nil {
                viewModel.loadPackageCaches()
            }
        }
    }
}
