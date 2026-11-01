import AppKit
import SwiftUI
import VeloraCore

extension DevArtifactRecord: Identifiable {
    public var id: String { path }
}

public struct DevArtifactsHunterView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedFilter: String = "All"
    @State private var searchFilter: String = ""

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private var filteredArtifacts: [DevArtifactRecord] {
        var result: [DevArtifactRecord]
        switch selectedFilter {
        case "Stale":
            result = viewModel.devArtifacts.filter { $0.inactivityLabel.contains("Stale") }
        case "Rust":
            result = viewModel.devArtifacts.filter { $0.kindName.contains("Rust") }
        case "Node":
            result = viewModel.devArtifacts.filter { $0.kindName.contains("Node") }
        case "Python":
            result = viewModel.devArtifacts.filter { $0.kindName.contains("Python") }
        case "Swift":
            result = viewModel.devArtifacts.filter { $0.kindName.contains("Swift") }
        default:
            result = viewModel.devArtifacts
        }

        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.parentProjectName.lowercased().contains(query) ||
                $0.name.lowercased().contains(query) ||
                $0.kindName.lowercased().contains(query) ||
                $0.path.lowercased().contains(query) ||
                $0.inactivityLabel.lowercased().contains(query)
            }
        }

        return result
    }

    private var stagedPaths: Set<String> {
        Set(viewModel.collectorItems.map { $0.path })
    }

    private var staleItems: [DevArtifactRecord] {
        viewModel.devArtifacts.filter { $0.inactivityLabel.contains("Stale") }
    }

    private var staleTotalBytes: UInt64 {
        staleItems.reduce(0) { $0 + $1.sizeBytes }
    }

    private var allStaleStaged: Bool {
        !staleItems.isEmpty && staleItems.allSatisfy { stagedPaths.contains($0.path) }
    }

    private var totalFoundBytes: UInt64 {
        viewModel.devArtifacts.reduce(0) { $0 + $1.sizeBytes }
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
                title: "Build Artifact Hunter",
                subtitle: "Verified workspace build directories (target/, node_modules, .venv, .build)",
                systemImage: "hammer.fill",
                accentColor: VeloraTheme.accentAmber
            ) {
                HStack(spacing: 10) {
                    if staleTotalBytes > 0 {
                        Button(action: {
                            if allStaleStaged {
                                for item in staleItems {
                                    viewModel.removeCollected(path: item.path)
                                }
                            } else {
                                for item in staleItems {
                                    viewModel.collect(path: item.path, size: item.sizeBytes, isDir: true)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: allStaleStaged ? "checkmark.circle.fill" : "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                                Text(allStaleStaged ? "Unstage Stale" : "Collect Stale (\(formatBytes(staleTotalBytes)))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: allStaleStaged
                                        ? [VeloraTheme.accentEmerald, VeloraTheme.accentCyan]
                                        : [VeloraTheme.accentViolet, VeloraTheme.accentPurple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                            .shadow(color: (allStaleStaged ? VeloraTheme.accentEmerald : VeloraTheme.accentViolet).opacity(0.35), radius: 6, x: 0, y: 2)
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
                ToolFilterChip(
                    title: "All (\(viewModel.devArtifacts.count))",
                    isSelected: selectedFilter == "All",
                    accentColor: VeloraTheme.accentAmber
                ) {
                    selectedFilter = "All"
                }

                let staleCount = viewModel.devArtifacts.filter { $0.inactivityLabel.contains("Stale") }.count
                if staleCount > 0 {
                    ToolFilterChip(
                        title: "Stale >60d (\(staleCount))",
                        isSelected: selectedFilter == "Stale",
                        accentColor: VeloraTheme.accentPink
                    ) {
                        selectedFilter = "Stale"
                    }
                }

                let rustCount = viewModel.devArtifacts.filter { $0.kindName.contains("Rust") }.count
                if rustCount > 0 {
                    ToolFilterChip(
                        title: "Rust target/ (\(rustCount))",
                        isSelected: selectedFilter == "Rust",
                        accentColor: VeloraTheme.accentAmber
                    ) {
                        selectedFilter = "Rust"
                    }
                }

                let nodeCount = viewModel.devArtifacts.filter { $0.kindName.contains("Node") }.count
                if nodeCount > 0 {
                    ToolFilterChip(
                        title: "node_modules (\(nodeCount))",
                        isSelected: selectedFilter == "Node",
                        accentColor: VeloraTheme.accentEmerald
                    ) {
                        selectedFilter = "Node"
                    }
                }

                let pythonCount = viewModel.devArtifacts.filter { $0.kindName.contains("Python") }.count
                if pythonCount > 0 {
                    ToolFilterChip(
                        title: "Python .venv (\(pythonCount))",
                        isSelected: selectedFilter == "Python",
                        accentColor: VeloraTheme.accentBlue
                    ) {
                        selectedFilter = "Python"
                    }
                }

                let swiftCount = viewModel.devArtifacts.filter { $0.kindName.contains("Swift") }.count
                if swiftCount > 0 {
                    ToolFilterChip(
                        title: "Swift .build (\(swiftCount))",
                        isSelected: selectedFilter == "Swift",
                        accentColor: VeloraTheme.accentViolet
                    ) {
                        selectedFilter = "Swift"
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(VeloraTheme.textSecondary)
                    TextField("Search build artifacts...", text: $searchFilter)
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

            // Content Area
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
            } else if filteredArtifacts.isEmpty {
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
                    Text("No Build Artifacts Found")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)
                    Text("Your indexed workspaces are clean, or no artifacts match the active filter.")
                        .font(.system(size: 12))
                        .foregroundColor(VeloraTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VeloraTheme.obsidianBase)
            } else {
                List {
                    ForEach(filteredArtifacts) { item in
                        let isStaged = stagedPaths.contains(item.path)
                        BuildArtifactCard(
                            item: item,
                            isStaged: isStaged,
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
            if viewModel.devArtifacts.isEmpty {
                viewModel.loadDevArtifacts()
            }
        }
    }
}

// MARK: - Build Artifact Card Component

private struct BuildArtifactCard: View {
    let item: DevArtifactRecord
    let isStaged: Bool
    let formatBytes: (UInt64) -> String
    let formatDate: (UInt64) -> String
    let onToggleCollect: () -> Void

    private var accentColor: Color {
        Color(hex: item.colorHex)
    }

    private var stalenessColor: Color {
        if item.inactivityLabel.contains("Stale") {
            return VeloraTheme.accentPink
        } else if item.inactivityLabel.contains("Idle") {
            return VeloraTheme.accentAmber
        } else {
            return VeloraTheme.accentEmerald
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 4, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.parentProjectName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(VeloraTheme.textPrimary)

                    Text(item.kindName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15), in: Capsule())

                    Text(item.inactivityLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(stalenessColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stalenessColor.opacity(0.15), in: Capsule())

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
            Button(action: onToggleCollect) {
                Image(systemName: isStaged ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundColor(isStaged ? VeloraTheme.accentCyan : VeloraTheme.accentAmber)
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

            Button("Open in Terminal") {
                let script = "tell application \"Terminal\" to do script \"cd '\(item.path)'\""
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }

            Divider()

            Button(isStaged ? "Remove from Collector" : "Stage for Cleanup") {
                onToggleCollect()
            }
        }
    }
}
