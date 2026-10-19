import AppKit
import Foundation
import Observation
import QuickLookUI

@Observable
public final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookCoordinator()

    public var currentPreviewURL: URL? {
        didSet {
            if let panel = QLPreviewPanel.shared(), panel.isVisible {
                panel.reloadData()
            }
        }
    }

    public var isPreviewOpen: Bool {
        QLPreviewPanel.shared()?.isVisible ?? false
    }

    public func togglePreview(for path: String) {
        let url = URL(fileURLWithPath: path)
        togglePreview(for: url)
    }

    public func togglePreview(for url: URL?) {
        guard let url = url else {
            closePreview()
            return
        }

        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible && currentPreviewURL == url {
            closePreview()
        } else {
            currentPreviewURL = url
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    public func updatePreviewIfVisible(path: String) {
        guard isPreviewOpen else { return }
        currentPreviewURL = URL(fileURLWithPath: path)
    }

    public func closePreview() {
        currentPreviewURL = nil
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentPreviewURL != nil ? 1 : 0
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = currentPreviewURL else {
            return nil
        }
        return url as NSURL
    }
}
