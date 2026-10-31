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
    public var pathStack: [String] = []
    public var sectorStack: [SunburstSectorItem] = []
    public var currentFolderTotalSize: UInt64 = 0
    public var collectorItems: [CollectedFile] = []
    public var collectorTotalSize: UInt64 = 0
    public var activeSidebarId: String = "volume_root"
    public var isScanning: Bool = false
    public var isSearching: Bool = false
    public var isLoadingSnapshot: Bool = false
    public var currentScanPath: String = ""
    public var scannedCount: UInt64 = 0
    public var scanThroughput: Double = 0
    public var cancelScanRequested: Bool = false
    public var scanStatusMessage: String = "Ready"
    public var storageReconciliation: StorageReconciliationItem?
    public var isReconcilingStorage: Bool = false
    public var devArtifacts: [DevArtifactRecord] = []
    public var isLoadingDevArtifacts: Bool = false
    public var xcodeSummary: XcodeSummaryRecord?
    public var isLoadingXcode: Bool = false
    public var pruneSimulatorsStatus: String?
    public var packageCacheSummary: PackageCacheSummaryRecord?
    public var isLoadingPackageCaches: Bool = false
    public var dockerPruneStatus: String?
    public var installedApps: [InstalledAppRecord] = []
    public var isLoadingApps: Bool = false
    public var orphanedResidues: [OrphanedResidueRecord] = []
    public var isLoadingOrphans: Bool = false
    public var largeOldMatrix: LargeOldMatrixSummaryRecord?
    public var isLoadingLargeOldMatrix: Bool = false
    public var duplicateSummary: DuplicateSummaryRecord?
    public var isLoadingDuplicates: Bool = false
    public var securitySummary: SecuritySummaryRecord?
    public var isLoadingSecurity: Bool = false
    public var quarantinedThreatIds: Set<String> = []
    public var isCleaning: Bool = false
    public var cleaningCurrentIndex: Int = 0
    public var cleaningTotalCount: Int = 0
    public var cleaningFreedBytes: UInt64 = 0
    public var cleaningTotalBytes: UInt64 = 0
    public var cleaningCurrentFileName: String = ""
    public var cleaningEstimatedSecondsRemaining: Double? = nil
    public var cleaningErrorMessage: String? = nil
    public var cancelCleaningRequested: Bool = false

    public var cleaningProgress: Double {
        guard cleaningTotalCount > 0 else { return 0.0 }
        return Double(cleaningCurrentIndex) / Double(cleaningTotalCount)
    }

    public var cleaningDisplayIndex: Int {
        guard cleaningTotalCount > 0 else { return 0 }
        return min(cleaningCurrentIndex + 1, cleaningTotalCount)
    }

    private var activeCleaningQueue: OperationQueue?

    public func cancelCleaning() {
        cancelCleaningRequested = true
        activeCleaningQueue?.cancelAllOperations()
    }
    private var pendingSearchWorkItem: DispatchWorkItem?
    private var lastExecutedQuery: String?

    public init() {
        self.engine = VeloraEngine()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.currentPath = home
        self.pathStack = [home]
        self.refreshStorageReconciliation()
    }

    /// Indicates whether a valid binary index snapshot file exists on disk.
    public var hasBinaryIndex: Bool {
        SnapshotManager.shared.hasAnyBinaryIndexFile
    }

    /// Formatted file size of the cached catalog.bin on disk if present.
    public var catalogFileSizeString: String? {
        SnapshotManager.shared.snapshotFileSizeFormatted
    }

    /// Indicates whether the engine currently holds indexed volume data in memory.
    public var hasIndexedData: Bool {
        scannedCount > 0 || currentSunburst != nil || engine.totalFiles() > 0
    }

    /// Determines if the initial scan hero UI should be presented when no binary index file exists.
    public var shouldShowScanUI: Bool {
        !hasBinaryIndex && !hasIndexedData
    }

    /// Indicates whether a global search query is currently entered and active.
    public var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Clears the active search query and resets search results.
    public func clearSearch() {
        searchQuery = ""
        performSearch(query: "")
    }

    public func cancelScan() {
        cancelScanRequested = true
        isScanning = false
        scanStatusMessage = "Scan cancelled"
    }

    /// Asynchronously deserializes and loads the offline snapshot on a background thread.
    /// This prevents blocking window presentation on app launch.
    public func loadCachedSnapshotIfAvailable() {
        guard SnapshotManager.shared.hasAnyBinaryIndexFile else {
            scanStatusMessage = "Ready for initial scan"
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
                    self.refreshStorageReconciliation()
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingSnapshot = false
                    self.scanStatusMessage = "Failed to load cached snapshot; please perform a clean scan"
                    self.refreshTableItems()
                    self.refreshStorageReconciliation()
                }
            }
        }
    }

    public func refreshStorageReconciliation() {
        isReconcilingStorage = true
        let mount = "/"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let item = self.engine.reconcileStorage(mountPoint: mount)
            DispatchQueue.main.async {
                self.storageReconciliation = item
                self.isReconcilingStorage = false
            }
        }
    }

    public func loadDevArtifacts() {
        isLoadingDevArtifacts = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let items = self.engine.findDevArtifacts(minSizeBytes: 1_000_000)
            DispatchQueue.main.async {
                self.devArtifacts = items
                self.isLoadingDevArtifacts = false
            }
        }
    }

    public func loadXcodeSummary() {
        isLoadingXcode = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.inspectXcode(homePath: home)
            DispatchQueue.main.async {
                self.xcodeSummary = summary
                self.isLoadingXcode = false
            }
        }
    }

    public func pruneUnavailableSimulators() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let success = self.engine.pruneUnavailableSimulators()
            DispatchQueue.main.async {
                self.pruneSimulatorsStatus = success ? "Cleaned unavailable simulators" : "None pruned"
                self.loadXcodeSummary()
            }
        }
    }

    public func loadPackageCaches() {
        isLoadingPackageCaches = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.inspectPackageCaches(homePath: home)
            DispatchQueue.main.async {
                self.packageCacheSummary = summary
                self.isLoadingPackageCaches = false
            }
        }
    }

    public func pruneDocker() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let success = self.engine.pruneDocker()
            DispatchQueue.main.async {
                self.dockerPruneStatus = success ? "Docker system pruned successfully" : "Docker daemon unavailable or error"
                self.loadPackageCaches()
            }
        }
    }

    public func loadInstalledApps() {
        isLoadingApps = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let apps = self.engine.listAppsWithFootprint(homePath: home)
            DispatchQueue.main.async {
                self.installedApps = apps
                self.isLoadingApps = false
            }
        }
    }

    public func loadOrphanedResidues() {
        isLoadingOrphans = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let orphans = self.engine.findOrphanedResidue(homePath: home)
            DispatchQueue.main.async {
                self.orphanedResidues = orphans
                self.isLoadingOrphans = false
            }
        }
    }

    public func loadLargeOldMatrix() {
        isLoadingLargeOldMatrix = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.computeLargeOldMatrix()
            DispatchQueue.main.async {
                self.largeOldMatrix = summary
                self.isLoadingLargeOldMatrix = false
            }
        }
    }

    public func loadDuplicates(minSizeBytes: UInt64 = 1_000_000) {
        isLoadingDuplicates = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.findDuplicates(minSizeBytes: minSizeBytes)
            DispatchQueue.main.async {
                self.duplicateSummary = summary
                self.isLoadingDuplicates = false
            }
        }
    }

    public func loadSecurityScan() {
        isLoadingSecurity = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.scanSecurity(homePath: home)
            DispatchQueue.main.async {
                self.securitySummary = summary
                self.isLoadingSecurity = false
            }
        }
    }

    public func quarantineThreat(_ threat: SecurityThreatRecord) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let success = self.engine.quarantineThreat(
            homePath: home,
            id: threat.id,
            targetPath: threat.targetPath,
            associatedPaths: threat.associatedPaths
        )
        if success {
            self.quarantinedThreatIds.insert(threat.id)
        }
    }

    public func restoreThreat(_ threat: SecurityThreatRecord) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let success = self.engine.restoreQuarantinedThreat(homePath: home, id: threat.id)
        if success {
            self.quarantinedThreatIds.remove(threat.id)
        }
    }

    /// Triggers parallel background calculation of all hygiene scanners once catalog.bin is in memory or after a scan completes.
    public func loadAllHygieneMetrics() {
        loadDevArtifacts()
        loadXcodeSummary()
        loadPackageCaches()
        loadInstalledApps()
        loadOrphanedResidues()
        loadLargeOldMatrix()
        loadDuplicates()
        loadSecurityScan()
        refreshStorageReconciliation()
    }

    public var devArtifactsBytes: UInt64? {
        if isLoadingDevArtifacts || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && devArtifacts.isEmpty { return nil }
        return devArtifacts.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    public var appLeftoversBytes: UInt64? {
        if isLoadingOrphans || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && orphanedResidues.isEmpty { return nil }
        return orphanedResidues.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    public var xcodeStorageBytes: UInt64? {
        if isLoadingXcode || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && xcodeSummary == nil { return nil }
        return xcodeSummary?.totalBytes
    }

    public var packageCachesBytes: UInt64? {
        if isLoadingPackageCaches || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && packageCacheSummary == nil { return nil }
        return packageCacheSummary?.totalBytes
    }

    public var duplicatesBytes: UInt64? {
        if isLoadingDuplicates || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && duplicateSummary == nil { return nil }
        return duplicateSummary?.totalWastedBytes
    }

    public var largeOldMatrixBytes: UInt64? {
        if isLoadingLargeOldMatrix || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && largeOldMatrix == nil { return nil }
        return largeOldMatrix?.totalBytes
    }

    public var securityThreatsCount: Int? {
        if isLoadingSecurity || isLoadingSnapshot || isScanning { return nil }
        guard let summary = securitySummary else { return nil }
        let active = summary.threats.filter { !quarantinedThreatIds.contains($0.id) }
        return active.count
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
                        self.refreshStorageReconciliation()
                    } else {
                        self.scanStatusMessage = "Scan failed or permission denied: Unable to access \(path)"
                    }
                }
            }
        }
    }

    public func performSearch(query: String, debounce: Bool = false) {
        pendingSearchWorkItem?.cancel()

        if self.searchQuery != query {
            self.searchQuery = query
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            self.lastExecutedQuery = ""
            self.searchResults = []
            self.isSearching = false
            self.refreshTableItems()
            return
        }

        if lastExecutedQuery == trimmed && !searchResults.isEmpty {
            return
        }

        self.isSearching = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let hits = self.engine.search(queryStr: trimmed, maxResults: 300)
            DispatchQueue.main.async {
                guard self.searchQuery.trimmingCharacters(in: .whitespaces) == trimmed else { return }
                self.lastExecutedQuery = trimmed
                self.searchResults = hits
                self.displayedItems = hits
                self.currentFolderTotalSize = hits.reduce(0) { $0 + $1.sizeBytes }
                self.isSearching = false
            }
        }

        self.pendingSearchWorkItem = workItem

        if debounce {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.15, execute: workItem)
        } else {
            DispatchQueue.global(qos: .userInteractive).async(execute: workItem)
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
            currentSunburst = nil
            sectorStack = []
        }
        refreshTableItems()
    }

    public func drillDownPath(_ path: String) {
        if let child = currentSunburst?.children.first(where: { $0.path == path }) {
            drillDown(sector: child)
        } else {
            pathStack.append(path)
            currentPath = path
            currentSunburst = nil
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
        } else {
            currentSunburst = nil
            sectorStack = []
        }
        currentPath = pathStack.last ?? FileManager.default.homeDirectoryForCurrentUser.path
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
                    modifiedSecs: 0,
                    isDir: child.isDir,
                    colorHex: child.colorHex
                )
            }
            self.displayedItems = items
            self.currentFolderTotalSize = max(currentSunburst.sizeBytes, items.reduce(0) { $0 + $1.sizeBytes })

            // Asynchronously resolve modification dates in background without blocking main thread
            let targetPath = self.currentPath
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                var updated = items
                var didChange = false
                for i in 0..<updated.count {
                    let m = self.lookupModificationDate(atPath: updated[i].path)
                    if m > 0 {
                        updated[i].modifiedSecs = m
                        didChange = true
                    }
                }
                if didChange {
                    DispatchQueue.main.async {
                        if self.currentPath == targetPath {
                            self.displayedItems = updated
                        }
                    }
                }
            }
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
        let targetPath = path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let url = URL(fileURLWithPath: targetPath)
            let fileManager = FileManager.default
            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                DispatchQueue.main.async {
                    if self.currentPath == targetPath {
                        self.displayedItems = []
                        self.currentFolderTotalSize = 0
                    }
                }
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
                let colorHex = self.colorHexForExtension(ext, isDir: isDir)

                items.append(SearchResultItem(
                    name: name,
                    path: fileURL.path,
                    sizeBytes: size,
                    modifiedSecs: UInt64(modDate),
                    isDir: isDir,
                    colorHex: colorHex
                ))
            }

            DispatchQueue.main.async {
                if self.currentPath == targetPath {
                    self.displayedItems = items
                    self.currentFolderTotalSize = items.reduce(0) { $0 + $1.sizeBytes }
                }
            }
        }
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
        guard !isCleaning, !collectorItems.isEmpty else { return }

        let itemsToClean = collectorItems
        let totalCount = itemsToClean.count
        let totalBytes = collectorTotalSize

        isCleaning = true
        cleaningCurrentIndex = 0
        cleaningTotalCount = totalCount
        cleaningFreedBytes = 0
        cleaningTotalBytes = totalBytes
        cleaningCurrentFileName = (itemsToClean.first?.path as NSString?)?.lastPathComponent ?? ""
        cleaningEstimatedSecondsRemaining = nil
        cleaningErrorMessage = nil
        cancelCleaningRequested = false

        let queue = OperationQueue()
        queue.name = "com.velora.concurrentTrashQueue"
        queue.maxConcurrentOperationCount = min(8, max(4, ProcessInfo.processInfo.activeProcessorCount * 2))
        queue.qualityOfService = .userInitiated
        self.activeCleaningQueue = queue

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var trashedPaths: [String] = []
            var trashedBytes: UInt64 = 0
            var errors: [String] = []
            let startTime = Date()
            var lastUiUpdate = Date()
            let lock = NSLock()
            var completedCount = 0

            for item in itemsToClean {
                queue.addOperation { [weak self] in
                    guard let self = self, !self.cancelCleaningRequested else { return }

                    let url = URL(fileURLWithPath: item.path)
                    let fileName = url.lastPathComponent
                    var trashedSuccess = false
                    var errorMsg: String? = nil

                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        trashedSuccess = true
                    } catch let nsErr as NSError {
                        // If file was already deleted (e.g. parent folder was trashed), treat as success
                        if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileNoSuchFileError {
                            trashedSuccess = true
                        } else {
                            errorMsg = "Failed to trash '\(fileName)': \(nsErr.localizedDescription)"
                        }
                    }

                    lock.lock()
                    completedCount += 1
                    let currentCompleted = completedCount
                    if trashedSuccess {
                        trashedPaths.append(item.path)
                        trashedBytes += item.sizeBytes
                    } else if let errorMsg = errorMsg {
                        errors.append(errorMsg)
                    }
                    let currentFreed = trashedBytes
                    let isCanceled = self.cancelCleaningRequested
                    let now = Date()
                    let shouldUpdate = currentCompleted == totalCount || isCanceled || now.timeIntervalSince(lastUiUpdate) >= 0.05
                    if shouldUpdate {
                        lastUiUpdate = now
                    }
                    lock.unlock()

                    if shouldUpdate {
                        let elapsed = max(0.01, now.timeIntervalSince(startTime))
                        let itemsPerSec = Double(currentCompleted) / elapsed
                        let remaining = totalCount - currentCompleted
                        let eta = itemsPerSec > 0.2 ? Double(remaining) / itemsPerSec : nil

                        DispatchQueue.main.async {
                            self.cleaningCurrentIndex = currentCompleted
                            self.cleaningFreedBytes = currentFreed
                            self.cleaningCurrentFileName = fileName
                            self.cleaningEstimatedSecondsRemaining = eta
                        }
                    }
                }
            }

            queue.waitUntilAllOperationsAreFinished()
            self.activeCleaningQueue = nil

            // Batch tombstone successfully trashed items in the Rust index with a single write lock
            let deletedPaths = Set(trashedPaths)
            if !trashedPaths.isEmpty {
                _ = self.engine.markDeletedBatch(paths: trashedPaths)
            }

            // Remove successfully trashed items from the Collector Tray in Rust and memory
            for path in trashedPaths {
                self.engine.removeCollected(path: path)
            }

            // Asynchronously persist the updated index with tombstoned files to catalog.bin
            SnapshotManager.shared.saveSnapshot(engine: self.engine)

            DispatchQueue.main.async {
                self.syncCollectorState()

                // Instant in-memory refresh without scanning physical disk
                self.scannedCount = self.engine.activeFiles()
                self.currentSunburst = self.engine.computeSunburst(maxDepth: 3, minAngleDeg: 1.5)
                if let root = self.currentSunburst {
                    self.sectorStack = [root]
                }
                self.refreshTableItems()
                self.refreshStorageReconciliation()

                // Also update apps and leftovers cache if loaded
                if !self.installedApps.isEmpty {
                    self.loadInstalledApps()
                }
                // Prune deleted leftovers in-memory without initiating a disk rescan
                if !self.orphanedResidues.isEmpty {
                    self.orphanedResidues.removeAll { deletedPaths.contains($0.path) }
                }

                // Optimistically update duplicateSummary and re-sync with engine
                if let currentSummary = self.duplicateSummary {
                    var updatedGroups: [DuplicateGroupRecord] = []
                    var newTotalFiles: UInt32 = 0
                    var newTotalWasted: UInt64 = 0

                    for group in currentSummary.groups {
                        var remaining = group.files.filter { !deletedPaths.contains($0.path) }
                        if remaining.count >= 2 {
                            // Ensure the oldest remaining file is marked as original if original was deleted
                            remaining.sort(by: { $0.modifiedSecs < $1.modifiedSecs })
                            for i in 0..<remaining.count {
                                remaining[i].isOriginal = (i == 0)
                            }

                            let groupWasted = group.sizeBytes * UInt64(remaining.count - 1)
                            let updatedGroup = DuplicateGroupRecord(
                                groupId: group.groupId,
                                hashHex: group.hashHex,
                                sizeBytes: group.sizeBytes,
                                totalWastedBytes: groupWasted,
                                fileCount: UInt32(remaining.count),
                                files: remaining
                            )
                            updatedGroups.append(updatedGroup)
                            newTotalFiles += UInt32(remaining.count)
                            newTotalWasted += groupWasted
                        }
                    }

                    self.duplicateSummary = DuplicateSummaryRecord(
                        totalDuplicateFiles: newTotalFiles,
                        totalDuplicateGroups: UInt32(updatedGroups.count),
                        totalWastedBytes: newTotalWasted,
                        groups: updatedGroups
                    )
                }

                // Refresh developer artifacts and large old matrix if loaded
                if !self.devArtifacts.isEmpty {
                    self.loadDevArtifacts()
                }
                if self.largeOldMatrix != nil {
                    self.loadLargeOldMatrix()
                }
                if self.packageCacheSummary != nil {
                    self.loadPackageCaches()
                }

                if !errors.isEmpty {
                    self.cleaningErrorMessage = "\(errors.count) items could not be moved to Trash. \(errors.first ?? "")"
                }

                self.isCleaning = false
            }
        }
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
