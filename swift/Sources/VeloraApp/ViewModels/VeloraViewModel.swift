import AppKit
import Foundation
import Observation
import VeloraCore

@Observable
public final class VeloraViewModel {
    public var engine: VeloraEngine
    public var searchQuery: String = ""
    public var searchResults: [SearchResultItem] = []
    public var currentPath: String = ""
    public var currentSunburst: SunburstSectorItem?
    public var selectedSector: SunburstSectorItem?
    public var hoveredSector: SunburstSectorItem?
    public var pathStack: [String] = []
    public var collectorItems: [CollectedFile] = []
    public var collectorTotalSize: UInt64 = 0
    public var selectedViewMode: ViewMode = .sunburst
    public var isScanning: Bool = false
    public var isSearching: Bool = false
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
            let sunburst = self.engine.computeSunburst(maxDepth: 3, minAngleDeg: 1.5)
            let total = self.engine.totalFiles()

            DispatchQueue.main.async {
                self.scannedCount = total
                self.scanThroughput = 0
                self.currentScanPath = "Completed: \((path as NSString).lastPathComponent)"

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self.isScanning = false
                    if success {
                        self.currentSunburst = sunburst
                        self.scanStatusMessage = "\(total) items indexed"
                    } else {
                        self.scanStatusMessage = "Scan failed or permission denied"
                    }
                }
            }
        }
    }

    public func performSearch(query: String) {
        self.searchQuery = query
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            self.searchResults = []
            self.isSearching = false
            return
        }

        self.isSearching = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let hits = self.engine.search(queryStr: query, maxResults: 200)
            DispatchQueue.main.async {
                self.searchResults = hits
                self.isSearching = false
            }
        }
    }

    public func drillDown(sector: SunburstSectorItem) {
        if sector.isDir && !sector.isGrouped {
            pathStack.append(sector.path)
            currentPath = sector.path
            currentSunburst = sector
        }
    }

    public func navigateUp() {
        if pathStack.count > 1 {
            pathStack.removeLast()
            if let parent = pathStack.last {
                currentPath = parent
                scanCurrentPath()
            }
        }
    }

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
