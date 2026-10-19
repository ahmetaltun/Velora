import AppKit
import Foundation
import Observation
import VeloraCore

@Observable
public final class VeloraViewModel {
    public var engine: VeloraEngine
    public var searchQuery: String = ""
    public var searchResults: [SearchResultItem] = []
    public var displayedItems: [SearchResultItem] = []
    public var currentPath: String = ""
    public var currentSunburst: SunburstSectorItem?
    public var selectedSector: SunburstSectorItem?
    public var hoveredSector: SunburstSectorItem?
    public var pathStack: [String] = []
    public var sectorStack: [SunburstSectorItem] = []
    public var currentFolderTotalSize: UInt64 = 0
    public var collectorItems: [CollectedFile] = []
    public var collectorTotalSize: UInt64 = 0
    public var selectedViewMode: ViewMode = .table
    public var activeSidebarId: String = "volume_root"
    public var isScanning: Bool = false
    public var isSearching: Bool = false
    public var isLoadingSnapshot: Bool = false
    public var currentScanPath: String = ""
    public var scannedCount: UInt64 = 0
    public var scanThroughput: Double = 0
    public var cancelScanRequested: Bool = false
    public var scanStatusMessage: String = "Ready"

    public init() {
        self.engine = VeloraEngine()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.currentPath = home
        self.pathStack = [home]
    }

    public func cancelScan() {
        cancelScanRequested = true
        isScanning = false
        scanStatusMessage = "Scan cancelled"
    }

    /// Asynchronously deserializes and loads the offline snapshot on a background thread.
    /// This prevents blocking window presentation on app launch.
    public func loadCachedSnapshotIfAvailable() {
        guard SnapshotManager.shared.snapshotExists else {
            scanStatusMessage = "Ready for initial scan"
            refreshTableItems()
            return
        }

        isLoadingSnapshot = true
        scanStatusMessage = "Loading indexed catalog in background..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let success = SnapshotManager.shared.loadSnapshot(engine: self.engine)
            if success {
                let total = self.engine.totalFiles()
                let sunburst = self.engine.computeSunburst(maxDepth: 3, minAngleDeg: 1.5)

                DispatchQueue.main.async {
                    self.scannedCount = total
                    self.currentSunburst = sunburst
                    if let root = sunburst {
                        self.sectorStack = [root]
                    }
                    self.isLoadingSnapshot = false
                    self.scanStatusMessage = "Loaded \(total) indexed items from cache"
                    self.refreshTableItems()
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingSnapshot = false
                    self.scanStatusMessage = "Failed to load cached snapshot; please perform a clean scan"
                    self.refreshTableItems()
                }
            }
        }
    }

    public func scanCurrentPath() {
        let path = currentPath
        isScanning = true
        cancelScanRequested = false
        scannedCount = 0
        scanThroughput = 0
        currentScanPath = path
        scanStatusMessage = "Scanning \(path)..."

        let progressBridge = ScanProgressBridge(viewModel: self)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let success = self.engine.scanVolume(
                mountPoint: path,
                volumeName: (path as NSString).lastPathComponent,
                callback: progressBridge
            )

            if self.cancelScanRequested {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.scanStatusMessage = "Scan cancelled"
                }
                return
            }

            let sunburst = self.engine.computeSunburst(maxDepth: 3, minAngleDeg: 1.5)
            let total = self.engine.totalFiles()

            if success {
                SnapshotManager.shared.saveSnapshot(engine: self.engine)
            }

            DispatchQueue.main.async {
                self.scannedCount = total
                self.scanThroughput = 0
                self.currentScanPath = "Completed: \((path as NSString).lastPathComponent)"

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.isScanning = false
                    if success {
                        self.currentSunburst = sunburst
                        if let root = sunburst {
                            self.sectorStack = [root]
                        }
                        self.scanStatusMessage = "\(total) items indexed"
                        self.refreshTableItems()
                    } else {
                        self.scanStatusMessage = "Scan failed or permission denied: Unable to access \(path)"
                    }
                }
            }
        }
    }

    public func performSearch(query: String) {
        self.searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self.searchResults = []
            self.isSearching = false
            self.refreshTableItems()
            return
        }

        self.isSearching = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let hits = self.engine.search(queryStr: query, maxResults: 300)
            DispatchQueue.main.async {
                self.searchResults = hits
                self.displayedItems = hits
                self.currentFolderTotalSize = hits.reduce(0) { $0 + $1.sizeBytes }
                self.isSearching = false
            }
        }
    }

    // MARK: - Navigation

    public func navigateToRoot() {
        searchQuery = ""
        activeSidebarId = "volume_root"
        if let root = sectorStack.first {
            currentSunburst = root
            sectorStack = [root]
            currentPath = root.path
            pathStack = [root.path]
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            currentPath = home
            pathStack = [home]
        }
        refreshTableItems()
    }

    public func navigateToFavorite(id: String, path: String) {
        searchQuery = ""
        activeSidebarId = id
        currentPath = path
        pathStack = [path]

        if let root = sectorStack.first ?? currentSunburst,
           let sector = findSector(byPath: path, in: root) {
            currentSunburst = sector
            sectorStack = [sector]
        }
        refreshTableItems()
    }

    public func drillDownPath(_ path: String) {
        if let child = currentSunburst?.children.first(where: { $0.path == path }) {
            drillDown(sector: child)
        } else {
            pathStack.append(path)
            currentPath = path
            refreshTableItems()
        }
    }

    public func drillDown(sector: SunburstSectorItem) {
        if sector.isDir && !sector.isGrouped {
            pathStack.append(sector.path)
            sectorStack.append(sector)
            currentPath = sector.path
            currentSunburst = sector
            refreshTableItems()
        }
    }

    public func navigateUp() {
        if pathStack.count > 1 {
            pathStack.removeLast()
        }
        if sectorStack.count > 1 {
            sectorStack.removeLast()
            currentSunburst = sectorStack.last
        }
        currentPath = pathStack.last ?? currentSunburst?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        refreshTableItems()
    }

    public func refreshTableItems() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            self.displayedItems = self.searchResults
            self.currentFolderTotalSize = self.searchResults.reduce(0) { $0 + $1.sizeBytes }
            return
        }

        if let currentSunburst = currentSunburst, !currentSunburst.children.isEmpty {
            let items: [SearchResultItem] = currentSunburst.children.map { child in
                SearchResultItem(
                    name: child.name,
                    path: child.path,
                    sizeBytes: child.sizeBytes,
                    modifiedSecs: self.lookupModificationDate(atPath: child.path),
                    isDir: child.isDir,
                    colorHex: child.colorHex
                )
            }
            self.displayedItems = items
            self.currentFolderTotalSize = max(currentSunburst.sizeBytes, items.reduce(0) { $0 + $1.sizeBytes })
        } else {
            loadDirectoryItems(for: currentPath)
        }
    }

    private func findSector(byPath targetPath: String, in root: SunburstSectorItem) -> SunburstSectorItem? {
        if root.path == targetPath { return root }
        for child in root.children {
            if child.path == targetPath { return child }
            if targetPath.hasPrefix(child.path) {
                if let found = findSector(byPath: targetPath, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private func loadDirectoryItems(for path: String) {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            self.displayedItems = []
            self.currentFolderTotalSize = 0
            return
        }

        var items: [SearchResultItem] = []
        for fileURL in contents {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey])
            let isDir = resourceValues?.isDirectory ?? false
            let size = UInt64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0

            let name = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            let colorHex = colorHexForExtension(ext, isDir: isDir)

            items.append(SearchResultItem(
                name: name,
                path: fileURL.path,
                sizeBytes: size,
                modifiedSecs: UInt64(modDate),
                isDir: isDir,
                colorHex: colorHex
            ))
        }

        self.displayedItems = items
        self.currentFolderTotalSize = items.reduce(0) { $0 + $1.sizeBytes }
    }

    private func lookupModificationDate(atPath path: String) -> UInt64 {
        let attr = try? FileManager.default.attributesOfItem(atPath: path)
        if let date = attr?[.modificationDate] as? Date {
            return UInt64(date.timeIntervalSince1970)
        }
        return 0
    }

    private func colorHexForExtension(_ ext: String, isDir: Bool) -> String {
        if isDir {
            if ["node_modules", "target", ".build", "deriveddata", "venv", ".venv", "__pycache__"].contains(ext) {
                return "#F59E0B" // Dev Caches
            }
            return "#6B7280"
        }
        switch ext {
        case "mp4", "mkv", "mov", "avi", "mp3", "flac", "wav", "png", "jpg", "jpeg", "heic", "webp", "gif", "svg":
            return "#3B82F6" // Media
        case "pdf", "docx", "doc", "xlsx", "pptx", "txt", "md", "json", "csv":
            return "#10B981" // Documents
        case "zip", "tar", "gz", "bz2", "xz", "7z", "dmg", "iso", "pkg":
            return "#8B5CF6" // Archives
        case "rs", "swift", "ts", "js", "py", "go", "c", "cpp", "h":
            return "#F59E0B" // Code / Dev
        default:
            return "#6B7280" // Other
        }
    }

    // MARK: - Collector

    public func collect(path: String, size: UInt64, isDir: Bool) {
        engine.collectItem(path: path, sizeBytes: size, isDir: isDir)
        syncCollectorState()
    }

    public func removeCollected(path: String) {
        engine.removeCollected(path: path)
        syncCollectorState()
    }

    public func clearCollector() {
        engine.clearCollector()
        syncCollectorState()
    }

    public func syncCollectorState() {
        collectorItems = engine.collectorItems()
        collectorTotalSize = engine.collectorTotalSize()
    }

    public func cleanStagedItems() {
        for item in collectorItems {
            let url = URL(fileURLWithPath: item.path)
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        clearCollector()
        scanCurrentPath()
    }
}

final class ScanProgressBridge: ScanProgressCallback {
    private weak var viewModel: VeloraViewModel?
    private var startTime: Date = Date()

    init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
        self.startTime = Date()
    }

    func onProgress(currentPath: String, scannedCount: UInt64, bytesScanned: UInt64) {
        let now = Date()
        let elapsed = max(0.02, now.timeIntervalSince(startTime))
        let throughput = Double(scannedCount) / elapsed

        DispatchQueue.main.async { [weak self] in
            guard let viewModel = self?.viewModel, viewModel.isScanning else { return }
            viewModel.scannedCount = scannedCount
            viewModel.scanThroughput = throughput
            viewModel.currentScanPath = currentPath
        }
    }
}
