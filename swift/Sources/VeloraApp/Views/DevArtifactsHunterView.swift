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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 16))
                            .foregroundColor(VeloraTheme.amber)
                        Text("Build Artifact Hunter")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }

                    Text("Verified workspace build directories (`target/`, `node_modules`, `.venv`, `.build`)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Stale Reclaim Button
                if staleTotalBytes > 0 {
                    Button(action: {
                        let staleItems = viewModel.devArtifacts.filter { $0.inactivityLabel.contains("Stale") }
                        for item in staleItems {
                            viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                        }
                    }) {
                        Label("Collect Stale (\(formatBytes(staleTotalBytes)))", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.85))
                    .controlSize(.regular)
                }

                Button(action: {
                    viewModel.loadDevArtifacts()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Rescan build artifacts")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Filter Chips Bar
            HStack(spacing: 8) {
                FilterChip(title: "All (\(viewModel.devArtifacts.count))", isSelected: selectedFilter == "All") {
                    selectedFilter = "All"
                }
                FilterChip(title: "Stale >60d", isSelected: selectedFilter == "Stale") {
                    selectedFilter = "Stale"
                }
                FilterChip(title: "Rust target/", isSelected: selectedFilter == "Rust") {
                    selectedFilter = "Rust"
                }
                FilterChip(title: "node_modules", isSelected: selectedFilter == "Node") {
                    selectedFilter = "Node"
                }
                FilterChip(title: "Python .venv", isSelected: selectedFilter == "Python") {
                    selectedFilter = "Python"
                }
                FilterChip(title: "Swift .build", isSelected: selectedFilter == "Swift") {
                    selectedFilter = "Swift"
                }

                Spacer()

                Text("Total: \(formatBytes(totalFoundBytes))")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Divider()

            // Content Table
            if viewModel.isLoadingDevArtifacts {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Hunting build artifacts across indexed volume...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if viewModel.devArtifacts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("No Large Build Artifacts Found")
                        .font(.headline)
                    Text("Your indexed workspaces are clean, or a volume scan has not yet been executed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                Table(filteredArtifacts, selection: $selectedItemIds) {
                    TableColumn("Project / Folder") { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.colorHex))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.parentProjectName)
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                Text(item.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .width(min: 220, ideal: 320)

                    TableColumn("Kind") { item in
                        Text(item.kindName)
                            .font(.system(.caption, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: item.colorHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("Size") { item in
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(.body, design: .monospaced, weight: .medium))
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Staleness") { item in
                        Text(item.inactivityLabel)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundColor(item.inactivityLabel.contains("Stale") ? .red : (item.inactivityLabel.contains("Idle") ? .orange : .green))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (item.inactivityLabel.contains("Stale") ? Color.red : (item.inactivityLabel.contains("Idle") ? Color.orange : Color.green)).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }
                    .width(min: 110, ideal: 130)

                    TableColumn("Action") { item in
                        Button("Collect") {
                            viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .width(min: 70, ideal: 80)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
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
        .onAppear {
            if viewModel.devArtifacts.isEmpty {
                viewModel.loadDevArtifacts()
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
