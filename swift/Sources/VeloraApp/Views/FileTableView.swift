import AppKit
import SwiftUI
import VeloraCore

extension SearchResultItem: Identifiable {
    public var id: String { path }
}

public struct FileTableView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var sortOrder = [KeyPathComparator(\SearchResultItem.sizeBytes, order: .reverse)]
    @State private var selectedItemIds = Set<String>()
    @State private var sortedItems: [SearchResultItem] = []

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private func updateSortedItems() {
        sortedItems = viewModel.displayedItems.sorted(using: sortOrder)
    }

    public var body: some View {
        ZStack {
            Table(sortedItems, selection: $selectedItemIds, sortOrder: $sortOrder) {
                // MARK: Name Column
                TableColumn("Name", value: \.name) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.isDir ? "folder.fill" : fileIconName(for: item.name))
                            .foregroundColor(Color(hex: item.colorHex))
                            .frame(width: 16)

                        Text(item.name)
                            .font(.system(.body, design: .rounded, weight: item.isDir ? .medium : .regular))
                            .lineLimit(1)
                    }
                }
                .width(min: 180, ideal: 260)

                // MARK: Size & Proportion Column
                TableColumn("Size", value: \.sizeBytes) { item in
                    HStack(spacing: 8) {
                        Text(formatBytes(item.sizeBytes))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(VeloraTheme.textPrimary)
                            .frame(minWidth: 72, alignment: .trailing)

                        if viewModel.currentFolderTotalSize > 0 {
                            let ratio = min(1.0, max(0.02, Double(item.sizeBytes) / Double(viewModel.currentFolderTotalSize)))
                            let barWidth: CGFloat = 50

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(VeloraTheme.textSecondary.opacity(0.16))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: item.colorHex), Color(hex: item.colorHex).opacity(0.65)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(4, barWidth * ratio))
                            }
                            .frame(width: barWidth, height: 5)

                            Text(String(format: "%4.1f%%", (Double(item.sizeBytes) / Double(viewModel.currentFolderTotalSize)) * 100))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(VeloraTheme.textSecondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .width(min: 170, ideal: 200)

                // MARK: Kind Column
                TableColumn("Kind", value: \.colorHex) { item in
                    Text(kindDescription(for: item))
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(VeloraTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(VeloraTheme.textSecondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
                .width(min: 80, ideal: 100)

                // MARK: Modified Date Column
                TableColumn("Modified", value: \.modifiedSecs) { item in
                    Text(formatTimestamp(item.modifiedSecs))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(VeloraTheme.textSecondary)
                }
                .width(min: 110, ideal: 140)

                // MARK: Path Column
                TableColumn("Path", value: \.path) { item in
                    Text(item.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(VeloraTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 150, ideal: 260)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(VeloraTheme.obsidianBase)
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if let firstId = selectedIds.first, let item = sortedItems.first(where: { $0.id == firstId }) {
                    itemContextMenu(for: item, selectedIds: selectedIds)
                }
            } primaryAction: { selectedIds in
                if let firstId = selectedIds.first, let item = sortedItems.first(where: { $0.id == firstId }) {
                    handleItemDoubleClick(item)
                }
            }
            .onChange(of: selectedItemIds) { _, newIds in
                if let firstId = newIds.first, let item = sortedItems.first(where: { $0.id == firstId }) {
                    QuickLookCoordinator.shared.updatePreviewIfVisible(path: item.path)
                }
            }
            .onKeyPress(.space) {
                if let firstId = selectedItemIds.first, let item = sortedItems.first(where: { $0.id == firstId }) {
                    QuickLookCoordinator.shared.togglePreview(for: item.path)
                    return .handled
                }
                return .ignored
            }
            .onChange(of: sortOrder) { _, _ in
                updateSortedItems()
            }
            .onChange(of: viewModel.displayedItems) { _, _ in
                updateSortedItems()
            }
            .onAppear {
                updateSortedItems()
            }

            // MARK: Overlay States
            if viewModel.isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Searching index...")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            } else if viewModel.isLoadingSnapshot {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Restoring catalog index...")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            } else if sortedItems.isEmpty {
                if !viewModel.searchQuery.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches Found", systemImage: "magnifyingglass")
                    } description: {
                        Text("No files matched \"\(viewModel.searchQuery)\".")
                    } actions: {
                        Text("Tip: Use filters like ext:rs • size:>50MB • dm:today • !target")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Folder Empty or Not Indexed", systemImage: "folder")
                    } description: {
                        Text("No files found in \(viewModel.currentPath)")
                    } actions: {
                        Button("Scan This Folder") {
                            viewModel.scanCurrentPath()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    // MARK: - Actions & Helpers

    private func handleItemDoubleClick(_ item: SearchResultItem) {
        if item.isDir {
            viewModel.drillDownPath(item.path)
        } else {
            openFile(path: item.path)
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: SearchResultItem, selectedIds: Set<String>) -> some View {
        if selectedIds.count <= 1 {
            Button("Quick Look") {
                QuickLookCoordinator.shared.togglePreview(for: item.path)
            }
            .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Open") {
                openFile(path: item.path)
            }
            Button("Reveal in Finder") {
                revealInFinder(path: item.path)
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
            Button("Open in Terminal") {
                openInTerminal(path: item.path, isDir: item.isDir)
            }
            Divider()
            Button("Collect for Cleanup") {
                viewModel.collect(path: item.path, size: item.sizeBytes, isDir: item.isDir)
            }
        } else {
            Button("Collect \(selectedIds.count) Items for Cleanup") {
                for id in selectedIds {
                    if let found = sortedItems.first(where: { $0.id == id }) {
                        viewModel.collect(path: found.path, size: found.sizeBytes, isDir: found.isDir)
                    }
                }
            }
            Divider()
            Button("Copy \(selectedIds.count) Paths") {
                let paths = selectedIds.compactMap { id in sortedItems.first(where: { $0.id == id })?.path }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
            }
        }
    }

    private func openFile(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openInTerminal(path: String, isDir: Bool) {
        let folder = isDir ? path : (path as NSString).deletingLastPathComponent
        let script = "tell application \"Terminal\" to do script \"cd '\(folder)'\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    private func formatTimestamp(_ secs: UInt64) -> String {
        guard secs > 0 else { return "--" }
        let date = Date(timeIntervalSince1970: TimeInterval(secs))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func kindDescription(for item: SearchResultItem) -> String {
        if item.isDir {
            switch item.colorHex.uppercased() {
            case "#F59E0B": return "Dev Cache"
            case "#EF4444": return "System Cache"
            default: return "Folder"
            }
        }
        switch item.colorHex.uppercased() {
        case "#3B82F6": return "Media"
        case "#10B981": return "Document"
        case "#8B5CF6": return "Archive"
        case "#F59E0B": return "Source Code"
        case "#EF4444": return "System Cache"
        default:
            let ext = (item.name as NSString).pathExtension.uppercased()
            return ext.isEmpty ? "File" : ext
        }
    }

    private func fileIconName(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "rs", "swift", "ts", "js", "py", "c", "cpp", "h", "go":
            return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "heic", "webp", "gif", "svg":
            return "photo.fill"
        case "mp4", "mov", "mkv", "avi":
            return "film.fill"
        case "mp3", "flac", "wav":
            return "music.note"
        case "zip", "tar", "gz", "7z", "dmg", "iso", "pkg":
            return "archivebox.fill"
        case "pdf":
            return "doc.richtext.fill"
        default:
            return "doc.fill"
        }
    }
}
