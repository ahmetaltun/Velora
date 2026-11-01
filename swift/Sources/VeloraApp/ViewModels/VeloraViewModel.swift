import AppKit
import Foundation
import Observation
import VeloraCore

@Observable
public final class VeloraViewModel {
    public var engine: VeloraEngine
    public static let maxSearchResults: UInt32 = 1000
    public var searchQuery: String = ""
    public var isSearchCapped: Bool = false
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
    public var dockerSummary: DockerStorageSummaryRecord?
    public var isLoadingDocker: Bool = false
    public var isPruningDockerAction: Bool = false
    public var dockerActionStatusMessage: String?
    public var aiModelSummary: AiModelSummaryRecord?
    public var isLoadingAiModels: Bool = false
    public var pruneOllamaBlobsStatus: String?
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

    // Cryptographic Secure Shredder State
    public var shredQueue: [ShredQueueItem] = []
    public var selectedShredAlgorithm: ShredAlgorithm = .dod522022M
    public var isShredding: Bool = false
    public var shredCurrentIndex: Int = 0
    public var shredTotalCount: Int = 0
    public var shredBytesProcessed: UInt64 = 0
    public var shredTotalBytes: UInt64 = 0
    public var shredCurrentFileName: String = ""
    public var shredCurrentPass: Int = 1
    public var shredTotalPasses: Int = 3
    public var shredPassDescription: String = ""
    public var shredThroughputBytesPerSec: Double = 0.0
    public var shredEstimatedSecondsRemaining: Double? = nil
    public var shredErrorMessage: String? = nil
    public var shredSuccessMessage: String? = nil
    public var cancelShredRequested: Bool = false
    public var isShredConfirmationPresented: Bool = false

    public var shredProgress: Double {
        guard shredTotalBytes > 0 else { return 0.0 }
        return min(1.0, Double(shredBytesProcessed) / Double(shredTotalBytes))
    }

    public var shredQueueTotalSize: UInt64 {
        shredQueue.reduce(0) { $0 + $1.sizeBytes }
    }

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
    private var isSnapshotLoadingInProgress: Bool = false
    private var hasLoadedSnapshot: Bool = false

    /// Indicates whether global interaction (sidebar tools, search, navigation) is disabled
    /// because catalog.bin is loading into memory or a volume scan is active.
    public var isInteractionDisabled: Bool {
        isScanning || isLoadingSnapshot || isShredding
    }

    public init() {
        self.engine = VeloraEngine()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.currentPath = home
        self.pathStack = [home]
        let hasIndex = SnapshotManager.shared.hasAnyBinaryIndexFile
        self.isLoadingSnapshot = hasIndex
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
        isSearchCapped = false
        performSearch(query: "")
    }

    public func cancelScan() {
        cancelScanRequested = true
        engine.cancelScan()
        isScanning = false
        scanStatusMessage = "Scan cancelled"
    }

    /// Asynchronously deserializes and loads the offline snapshot on a background thread.
    /// This prevents blocking window presentation on app launch.
    public func loadCachedSnapshotIfAvailable() {
        guard !hasLoadedSnapshot && !isSnapshotLoadingInProgress else { return }
        guard SnapshotManager.shared.hasAnyBinaryIndexFile else {
            isLoadingSnapshot = false
            scanStatusMessage = "Ready for initial scan"
            return
        }

        isSnapshotLoadingInProgress = true
        isLoadingSnapshot = true
        scanStatusMessage = "Loading indexed catalog in background..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let success = SnapshotManager.shared.loadSnapshot(engine: self.engine)
            if success {
                let total = self.engine.totalFiles()
                let sunburst = self.engine.computeSunburst(maxDepth: 3, minAngleDeg: 1.5)

                DispatchQueue.main.async {
                    self.hasLoadedSnapshot = true
                    self.isSnapshotLoadingInProgress = false
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
                    self.hasLoadedSnapshot = false
                    self.isSnapshotLoadingInProgress = false
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

    public func loadDockerSummary() {
        isLoadingDocker = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.inspectDocker(homePath: home)
            DispatchQueue.main.async {
                self.dockerSummary = summary
                self.isLoadingDocker = false
            }
        }
    }

    public func pruneDockerDanglingImages() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerDanglingImages(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func pruneDockerUnusedImages() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerUnusedImages(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func pruneDockerAnonymousVolumes() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerAnonymousVolumes(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func pruneDockerAllUnattachedVolumes() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerAllUnattachedVolumes(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func pruneDockerBuildCache() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerBuildCache(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func pruneDockerStoppedContainers() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerStoppedContainers(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func pruneDockerSystemAll() {
        isPruningDockerAction = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let res = self.engine.pruneDockerSystemAll(homePath: home)
            DispatchQueue.main.async {
                self.isPruningDockerAction = false
                self.dockerActionStatusMessage = res.message
                self.loadDockerSummary()
                self.loadPackageCaches()
            }
        }
    }

    public func loadAiModels() {
        isLoadingAiModels = true
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let summary = self.engine.inspectAiModels(homePath: home)
            DispatchQueue.main.async {
                self.aiModelSummary = summary
                self.isLoadingAiModels = false
            }
        }
    }

    public func pruneOllamaBlobs() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let freed = self.engine.pruneOllamaOrphanedBlobs(homePath: home)
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file)
            DispatchQueue.main.async {
                self.pruneOllamaBlobsStatus = freed > 0 ? "Pruned \(formatted) of orphaned blobs." : "No orphaned blobs found."
                self.loadAiModels()
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

            // Attempt zero-copy GPU compute acceleration via Metal
            var summary: LargeOldMatrixSummaryRecord? = nil
            if let gpuEngine = MetalComputeEngine.shared {
                summary = gpuEngine.computeLargeOldMatrix(engine: self.engine)
            }

            // Fallback to CPU algorithm if GPU compute is unavailable or returns nil
            if summary == nil {
                summary = self.engine.computeLargeOldMatrix()
            }

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
        loadAiModels()
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

    public var dockerStorageBytes: UInt64? {
        if isLoadingDocker || isLoadingSnapshot || isScanning { return nil }
        guard let summary = dockerSummary else { return nil }
        return summary.totalHostAllocatedBytes > 0 ? summary.totalHostAllocatedBytes : summary.totalGuestActiveBytes
    }

    public var aiModelsBytes: UInt64? {
        if isLoadingAiModels || isLoadingSnapshot || isScanning { return nil }
        if !hasBinaryIndex && !hasIndexedData && aiModelSummary == nil { return nil }
        return aiModelSummary?.totalBytes
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
        if isSearchActive {
            clearSearch()
        }
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
                        self.hasLoadedSnapshot = true
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
            self.isSearchCapped = false
            self.refreshTableItems()
            return
        }

        if lastExecutedQuery == trimmed && !searchResults.isEmpty {
            return
        }

        self.isSearching = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let hits = self.engine.search(queryStr: trimmed, maxResults: VeloraViewModel.maxSearchResults)
            DispatchQueue.main.async {
                guard self.searchQuery.trimmingCharacters(in: .whitespaces) == trimmed else { return }
                self.lastExecutedQuery = trimmed
                self.searchResults = hits
                self.displayedItems = hits
                self.isSearchCapped = hits.count >= Int(VeloraViewModel.maxSearchResults)
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
        } else if let subSunburst = engine.computeSunburstForPath(path: path, maxDepth: 3, minAngleDeg: 1.5) {
            pathStack.append(path)
            sectorStack.append(subSunburst)
            currentPath = path
            currentSunburst = subSunburst
            refreshTableItems()
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
            currentPath = sector.path

            // If the sector was at the outer depth limit and has no precomputed children,
            // recompute a fresh sub-tree sunburst rooted at this folder from the volume index.
            if sector.children.isEmpty,
               let subSunburst = engine.computeSunburstForPath(path: sector.path, maxDepth: 3, minAngleDeg: 1.5) {
                sectorStack.append(subSunburst)
                currentSunburst = subSunburst
            } else {
                sectorStack.append(sector)
                currentSunburst = sector
            }
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
        } else if let parentPath = pathStack.last {
            currentSunburst = engine.computeSunburstForPath(path: parentPath, maxDepth: 3, minAngleDeg: 1.5)
            if let root = currentSunburst {
                sectorStack = [root]
            } else {
                sectorStack = []
            }
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
                if self.aiModelSummary != nil {
                    self.loadAiModels()
                }

                if !errors.isEmpty {
                    self.cleaningErrorMessage = "\(errors.count) items could not be moved to Trash. \(errors.first ?? "")"
                }

                self.isCleaning = false
            }
        }
    }

    // MARK: - Cryptographic Secure Shredder Actions

    public func queueForShredding(paths: [String]) {
        guard !paths.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var newItems: [ShredQueueItem] = []

            for p in paths {
                let url = URL(fileURLWithPath: p)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: p, isDirectory: &isDirectory) else { continue }

                var size: UInt64 = 0
                if isDirectory.boolValue {
                    if let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
                    ) {
                        for case let fileURL as URL in enumerator {
                            if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                               res.isDirectory != true {
                                size += UInt64(res.fileSize ?? 0)
                            }
                        }
                    }
                } else {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: p) {
                        size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                    }
                }
                newItems.append(ShredQueueItem(path: p, sizeBytes: size, isDir: isDirectory.boolValue))
            }

            DispatchQueue.main.async {
                for item in newItems {
                    if !self.shredQueue.contains(where: { $0.path == item.path }) {
                        self.shredQueue.append(item)
                    }
                }
            }
        }
    }

    public func removeFromShredQueue(id: String) {
        shredQueue.removeAll { $0.id == id }
    }

    public func clearShredQueue() {
        shredQueue.removeAll()
    }

    public func cancelShredding() {
        cancelShredRequested = true
        engine.cancelShred()
    }

    public func startShredding() {
        guard !isShredding, !shredQueue.isEmpty else { return }

        let itemsToShred = shredQueue
        let totalItems = itemsToShred.count
        let totalRawBytes = shredQueueTotalSize
        let paths = itemsToShred.map(\.path)
        let algo = selectedShredAlgorithm
        let passes = UInt64(algo.totalPassesCount)

        isShredding = true
        cancelShredRequested = false
        shredCurrentIndex = 0
        shredTotalCount = totalItems
        shredBytesProcessed = 0
        shredTotalBytes = totalRawBytes * passes
        shredCurrentFileName = itemsToShred.first?.name ?? ""
        shredCurrentPass = 1
        shredTotalPasses = Int(passes)
        shredPassDescription = "Initializing overwrite pipeline..."
        shredThroughputBytesPerSec = 0
        shredEstimatedSecondsRemaining = nil
        shredErrorMessage = nil
        shredSuccessMessage = nil

        let startTime = Date()
        var lastUiUpdate = Date()
        let lock = NSLock()

        let bridge = SwiftShredCallbackBridge { [weak self] currentPath, fileIndex, totalFiles, currentPass, totalPasses, passName, bytesWrittenFile, fileSizeBytes, totalBytesWritten, totalBytesAllFiles in
            guard let self = self else { return }
            let now = Date()
            lock.lock()
            let shouldUpdate = now.timeIntervalSince(lastUiUpdate) >= 0.05 || totalBytesWritten >= totalBytesAllFiles
            if shouldUpdate {
                lastUiUpdate = now
            }
            lock.unlock()

            if shouldUpdate {
                let elapsed = max(0.01, now.timeIntervalSince(startTime))
                let speed = Double(totalBytesWritten) / elapsed
                let remainingBytes = totalBytesAllFiles > totalBytesWritten ? totalBytesAllFiles - totalBytesWritten : 0
                let eta = (speed > 1024 && remainingBytes > 0) ? Double(remainingBytes) / speed : nil
                let fileName = (currentPath as NSString).lastPathComponent

                DispatchQueue.main.async {
                    self.shredCurrentIndex = Int(fileIndex)
                    self.shredTotalCount = Int(totalFiles)
                    self.shredCurrentFileName = fileName
                    self.shredCurrentPass = Int(currentPass)
                    self.shredTotalPasses = Int(totalPasses)
                    self.shredPassDescription = passName
                    self.shredBytesProcessed = totalBytesWritten
                    self.shredTotalBytes = totalBytesAllFiles
                    self.shredThroughputBytesPerSec = speed
                    self.shredEstimatedSecondsRemaining = eta
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = self.engine.shredPaths(paths: paths, algorithm: algo, callback: bridge)

            // Pre-calculate active files count and sunburst on background thread (never stall Main Thread)
            let activeCount = self.engine.activeFiles()
            let sunburst = self.engine.computeSunburst(maxDepth: 3, minAngleDeg: 1.5)

            DispatchQueue.main.async {
                self.isShredding = false
                if result.success || result.filesShredded > 0 {
                    let successfulPaths = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
                    self.shredQueue.removeAll { successfulPaths.contains($0.path) }
                    let itemWord = result.filesShredded == 1 ? "item" : "items"
                    self.shredSuccessMessage = "Successfully sanitized and shredded \(result.filesShredded) \(itemWord)."
                }

                if !result.errors.isEmpty {
                    self.shredErrorMessage = result.errors.joined(separator: "\n")
                }

                self.syncCollectorState()
                self.scannedCount = activeCount
                self.currentSunburst = sunburst
                if let root = sunburst {
                    self.sectorStack = [root]
                }
                self.refreshTableItems()
                self.refreshStorageReconciliation()

                if !self.installedApps.isEmpty {
                    self.loadInstalledApps()
                }
                if !self.orphanedResidues.isEmpty {
                    self.loadOrphanedResidues()
                }
            }

            // Persist the updated index with tombstoned files to catalog.bin asynchronously
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                SnapshotManager.shared.saveSnapshot(engine: self.engine)
            }
        }
    }
}

// MARK: - Shredder Models & Bridge

public struct ShredQueueItem: Identifiable, Equatable {
    public let id: String
    public let path: String
    public let name: String
    public let sizeBytes: UInt64
    public let isDir: Bool

    public init(path: String, sizeBytes: UInt64, isDir: Bool) {
        self.id = path
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.sizeBytes = sizeBytes
        self.isDir = isDir
    }
}

final class SwiftShredCallbackBridge: ShredProgressCallback {
    private let onProgressClosure: (String, UInt32, UInt32, UInt32, UInt32, String, UInt64, UInt64, UInt64, UInt64) -> Void

    init(onProgress: @escaping (String, UInt32, UInt32, UInt32, UInt32, String, UInt64, UInt64, UInt64, UInt64) -> Void) {
        self.onProgressClosure = onProgress
    }

    func onProgress(
        currentPath: String,
        fileIndex: UInt32,
        totalFiles: UInt32,
        currentPass: UInt32,
        totalPasses: UInt32,
        passName: String,
        bytesWrittenFile: UInt64,
        fileSizeBytes: UInt64,
        totalBytesWritten: UInt64,
        totalBytesAllFiles: UInt64
    ) {
        onProgressClosure(
            currentPath,
            fileIndex,
            totalFiles,
            currentPass,
            totalPasses,
            passName,
            bytesWrittenFile,
            fileSizeBytes,
            totalBytesWritten,
            totalBytesAllFiles
        )
    }
}

extension ShredAlgorithm: Identifiable {
    public var id: String {
        switch self {
        case .zero: return "zero"
        case .randomNist80088: return "nist"
        case .dod522022M: return "dod"
        case .dod522022MEce: return "dod_ece"
        }
    }

    public var title: String {
        switch self {
        case .zero: return "Quick Zero (1-Pass)"
        case .randomNist80088: return "NIST SP 800-88 (1-Pass CSPRNG)"
        case .dod522022M: return "DoD 5220.22-M (3-Pass)"
        case .dod522022MEce: return "DoD 5220.22-M ECE (7-Pass)"
        }
    }

    public var totalPassesCount: Int {
        switch self {
        case .zero, .randomNist80088: return 1
        case .dod522022M: return 3
        case .dod522022MEce: return 7
        }
    }

    public var description: String {
        switch self {
        case .zero:
            return "Overwrites all bytes with 0x00 zeros. Fast and minimizes SSD write cycle wear."
        case .randomNist80088:
            return "Single-pass overwrite using hardware-accelerated cryptographically secure pseudo-random numbers."
        case .dod522022M:
            return "U.S. DoD 3-pass standard: 0x00 zeros, 0xFF complement, followed by CSPRNG random bytes."
        case .dod522022MEce:
            return "High-security 7-pass military sanitization with alternating bit patterns and cryptographic random passes."
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
