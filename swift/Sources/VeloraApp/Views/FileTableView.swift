import AppKit
import SwiftUI
import VeloraCore

extension SearchResultItem: Identifiable {
    public var id: String { path }
}

public struct FileTableView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var selectedItem: SearchResultItem?

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Table(viewModel.searchResults) {
            TableColumn("Name") { item in
                HStack(spacing: 8) {
                    Image(systemName: item.isDir ? "folder.fill" : "doc.fill")
                        .foregroundColor(Color(hex: item.colorHex))
                    Text(item.name)
                        .font(.system(.body, design: .rounded))
                }
                .contextMenu {
                    Button("Open") {
                        openFile(path: item.path)
                    }
                    Button("Reveal in Finder") {
                        revealInFinder(path: item.path)
                    }
                    Button("Open in Terminal") {
                        openInTerminal(path: item.path, isDir: item.isDir)
                    }
                    Divider()
                    Button("Collect for Cleanup") {
                        viewModel.collect(path: item.path, size: item.sizeBytes, isDir: item.isDir)
                    }
                }
            }
            .width(min: 200, ideal: 300)

            TableColumn("Size") { item in
                Text(item.isDir ? "--" : formatBytes(item.sizeBytes))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Path") { item in
                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .tableStyle(.inset)
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
}
