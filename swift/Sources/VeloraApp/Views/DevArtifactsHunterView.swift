import AppKit
import SwiftUI
import VeloraCore

extension DevArtifactRecord: Identifiable {
    public var id: String { path }
}

public struct DevArtifactsHunterView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedFilter: String = "All"
    @State private var selectedItemIds = Set<String>()

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var filteredArtifacts: [DevArtifactRecord] {
        switch selectedFilter {
        case "Stale":
            return viewModel.devArtifacts.filter { $0.inactivityLabel.contains("Stale") }
        case "Rust":
            return viewModel.devArtifacts.filter { $0.kindName.contains("Rust") }
        case "Node":
            return viewModel.devArtifacts.filter { $0.kindName.contains("Node") }
        case "Python":
            return viewModel.devArtifacts.filter { $0.kindName.contains("Python") }
        case "Swift":
            return viewModel.devArtifacts.filter { $0.kindName.contains("Swift") }
        default:
            return viewModel.devArtifacts
        }
    }

    private var staleTotalBytes: UInt64 {
        viewModel.devArtifacts
            .filter { $0.inactivityLabel.contains("Stale") }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalFoundBytes: UInt64 {
        viewModel.devArtifacts.reduce(0) { $0 + $1.sizeBytes }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            ToolHeaderView(
                title: "Build Artifact Hunter",
                subtitle: "Verified workspace build directories (target/, node_modules, .venv, .build)",
                systemImage: "hammer.fill",
                accentColor: VeloraTheme.accentAmber
            ) {
                HStack(spacing: 10) {
                    if staleTotalBytes > 0 {
                        Button(action: {
                            let staleItems = viewModel.devArtifacts.filter { $0.inactivityLabel.contains("Stale") }
                            for item in staleItems {
                                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Collect Stale (\(formatBytes(staleTotalBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [VeloraTheme.accentPink, VeloraTheme.accentViolet],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: VeloraTheme.accentPink.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: {
                        viewModel.loadDevArtifacts()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(VeloraTheme.textSecondary)
                            .padding(8)
                            .background(VeloraTheme.obsidianElevated, in: Circle())
                            .overlay(Circle().stroke(VeloraTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Rescan build artifacts")
                }
            }

            // Filter Chips Bar
            HStack(spacing: 8) {
                ToolFilterChip(title: "All (\(viewModel.devArtifacts.count))", isSelected: selectedFilter == "All", accentColor: VeloraTheme.accentAmber) {
                    selectedFilter = "All"
                }
                ToolFilterChip(title: "Stale >60d", isSelected: selectedFilter == "Stale", accentColor: VeloraTheme.accentPink) {
                    selectedFilter = "Stale"
                }
                ToolFilterChip(title: "Rust target/", isSelected: selectedFilter == "Rust", accentColor: VeloraTheme.accentAmber) {
                    selectedFilter = "Rust"
                }
                ToolFilterChip(title: "node_modules", isSelected: selectedFilter == "Node", accentColor: VeloraTheme.accentEmerald) {
                    selectedFilter = "Node"
                }
                ToolFilterChip(title: "Python .venv", isSelected: selectedFilter == "Python", accentColor: VeloraTheme.accentBlue) {
                    selectedFilter = "Python"
                }
                ToolFilterChip(title: "Swift .build", isSelected: selectedFilter == "Swift", accentColor: VeloraTheme.accentViolet) {
                    selectedFilter = "Swift"
                }

                Spacer()

                Text("Total: \(formatBytes(totalFoundBytes))")
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
            if viewModel.isLoadingDevArtifacts {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Hunting build artifacts across indexed volume...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else if viewModel.devArtifacts.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(VeloraTheme.accentEmerald.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 32))
                            .foregroundColor(VeloraTheme.accentEmerald)
                    }
                    Text("No Large Build Artifacts Found")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("Your indexed workspaces are clean, or a volume scan has not yet been executed.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                Table(filteredArtifacts, selection: $selectedItemIds) {
                    TableColumn("Project / Folder") { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.parentProjectName)
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
                    .width(min: 220, ideal: 320)

                    TableColumn("Kind") { item in
                        Text(item.kindName)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: item.colorHex).opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("Size") { item in
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(VeloraTheme.textPrimary)
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Staleness") { item in
                        let color: Color = item.inactivityLabel.contains("Stale") ? VeloraTheme.accentPink : (item.inactivityLabel.contains("Idle") ? VeloraTheme.accentAmber : VeloraTheme.accentEmerald)
                        Text(item.inactivityLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .width(min: 110, ideal: 130)

                    TableColumn("Action") { item in
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
                    }
                    .width(min: 70, ideal: 80)
                }
                .scrollContentBackground(.hidden)
                .background(VeloraTheme.obsidianBase)
                .onKeyPress(.space) {
                    if let firstId = selectedItemIds.first, let item = filteredArtifacts.first(where: { $0.id == firstId }) {
                        QuickLookCoordinator.shared.togglePreview(for: item.path)
                        return .handled
                    }
                    return .ignored
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let firstId = ids.first, let item = filteredArtifacts.first(where: { $0.id == firstId }) {
                        Button("Quick Look") {
                            QuickLookCoordinator.shared.togglePreview(for: item.path)
                        }
                        .keyboardShortcut(.space, modifiers: [])

                        Divider()

                        Button("Reveal in Finder") {
                            let url = URL(fileURLWithPath: item.path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }

                        Button("Open in Terminal") {
                            let script = "tell application \"Terminal\" to do script \"cd '\(item.path)'\""
                            if let appleScript = NSAppleScript(source: script) {
                                var error: NSDictionary?
                                appleScript.executeAndReturnError(&error)
                            }
                        }

                        Divider()

                        Button("Collect for Cleanup") {
                            viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                        }
                    }
                }
            }
        }
        .background(VeloraTheme.obsidianBase)
        .onAppear {
            if viewModel.devArtifacts.isEmpty {
                viewModel.loadDevArtifacts()
            }
        }
    }
}
