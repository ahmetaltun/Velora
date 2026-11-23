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
    public var displayedItems: [SearchResultItem] = []
    public var currentPath: String = ""
    private var indexedRoot: String?
    public var isLoadingFolder = false
    public var folderErrorMessage: String?
    public var pathStack: [String] = []
    public var searchResultBytes: UInt64 = 0
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
    public var catalogNotice: String?
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
    public var quarantinedItems: [QuarantinedItemRecord] = []
    public var isUpdatingQuarantine = false
    public var quarantineNotice: String?

    public var quarantinedPaths: Set<String> {
        Set(quarantinedItems.map(\.originalPath))
    }
    public var isCleaning: Bool = false
    public var cleaningCurrentIndex: Int = 0
    public var cleaningTotalCount: Int = 0
    public var cleaningMovedBytes: UInt64 = 0
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

    private var cleaningTask: Task<Void, Never>?

    public func cancelCleaning() {
        cancelCleaningRequested = true
        cleaningTask?.cancel()
    }
    private var pendingSearchWorkItem: DispatchWorkItem?
    private var searchRequest = UUID()
    private var folderRequest = UUID()
    private var isSnapshotLoadingInProgress: Bool = false
    private var hasLoadedSnapshot: Bool = false

    /// Indicates whether global interaction (sidebar tools, search, navigation) is disabled
    /// while the catalog loads, a scan runs, or a file operation is active.
    public var isInteractionDisabled: Bool {
        isScanning || isLoadingSnapshot || isShredding || isCleaning || isUpdatingQuarantine
    }

    public init() {
        self.engine = VeloraEngine()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.currentPath = home
        self.pathStack = [home]
        self.isLoadingSnapshot = SnapshotManager.shared.snapshotExists
        self.refreshStorageReconciliation()
    }

    /// Formatted file size of the cached catalog.bin on disk if present.
    public var catalogFileSizeString: String? {
        SnapshotManager.shared.snapshotFileSizeFormatted
    }

    /// Indicates whether the engine currently holds indexed volume data in memory.
    public var hasIndexedData: Bool {
        indexedRoot != nil
    }

    /// Indicates whether a global search query is currently entered and active.
    public var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Clears the active search query and resets search results.
    public func clearSearch() {
        performSearch(query: "")
    }

    public func cancelScan() {
        guard isScanning, !cancelScanRequested else { return }
        cancelScanRequested = true
        engine.cancelScan()
    }

    /// Asynchronously deserializes and loads the offline snapshot on a background thread.
    /// This prevents blocking window presentation on app launch.
    public func loadCachedSnapshotIfAvailable() {
        guard !hasLoadedSnapshot, !isSnapshotLoadingInProgress, !isScanning, !isCleaning, !isShredding else { return }
        guard SnapshotManager.shared.snapshotExists else {
            isLoadingSnapshot = false
            return
        }

        isSnapshotLoadingInProgress = true
        isLoadingSnapshot = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let success = SnapshotManager.shared.loadSnapshot(engine: self.engine)
            if success, let root = self.engine.indexedRoot() {
                let total = self.engine.activeFiles()

                DispatchQueue.main.async {
                    self.hasLoadedSnapshot = true
                    self.isSnapshotLoadingInProgress = false
                    self.scannedCount = total
                    self.indexedRoot = root
                    self.currentPath = root
                    self.pathStack = [root]
                    self.isLoadingSnapshot = false
                    self.refreshTableItems()
                    self.refreshStorageReconciliation()
                }
            } else {
                DispatchQueue.main.async {
                    self.hasLoadedSnapshot = false
                    self.isSnapshotLoadingInProgress = false
                    self.isLoadingSnapshot = false
                    self.catalogNotice = "The saved catalog could not be opened. Scan a folder to rebuild it."
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
        guard !isUpdatingQuarantine, !isLoadingSecurity else { return }
        isLoadingSecurity = true
        quarantineNotice = nil
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let vault = Result { try self.engine.quarantinedItems(homePath: home) }
            let summary = self.engine.scanSecurity(homePath: home)
            DispatchQueue.main.async {
                self.applyVaultInventory(vault)
                self.securitySummary = summary
                self.isLoadingSecurity = false
            }
        }
    }

    public func quarantineThreat(_ threat: SecurityThreatRecord) {
        quarantineThreats([threat])
    }

    public func quarantineThreats(_ threats: [SecurityThreatRecord]) {
        let existing = quarantinedPaths
        var targets = Set<String>()
        let candidates = threats.filter {
            $0.canQuarantine && !existing.contains($0.targetPath) && targets.insert($0.targetPath).inserted
        }
        guard !candidates.isEmpty else { return }
        updateQuarantine { engine, home in
            var failures: [String] = []
            for threat in candidates {
                do {
                    try engine.quarantineThreat(
                        homePath: home, id: threat.id, targetPath: threat.targetPath,
                        associatedPaths: threat.associatedPaths
                    )
                } catch {
                    failures.append("\(threat.name). \(Self.quarantineErrorText(error))")
                }
            }
            if let first = failures.first {
                return "\(failures.count) quarantine operations reported an error. \(first)"
            }
            return nil
        }
    }

    public func restoreThreat(_ threat: SecurityThreatRecord) {
        guard let item = quarantinedItems.first(where: { $0.originalPath == threat.targetPath }) else { return }
        restoreQuarantinedItem(item)
    }

    public func restoreQuarantinedItem(_ item: QuarantinedItemRecord) {
        updateQuarantine { engine, home in
            do {
                try engine.restoreQuarantinedThreat(homePath: home, id: item.id)
                return nil
            } catch {
                return "Could not restore item. \(Self.quarantineErrorText(error))"
            }
        }
    }

    private func updateQuarantine(_ operation: @escaping (VeloraEngine, String) -> String?) {
        guard !isInteractionDisabled, !isLoadingSecurity else { return }
        isUpdatingQuarantine = true
        quarantineNotice = nil
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let message = operation(self.engine, home)
            let vault = Result { try self.engine.quarantinedItems(homePath: home) }
            DispatchQueue.main.async {
                self.quarantineNotice = message
                self.applyVaultInventory(vault)
                self.isUpdatingQuarantine = false
            }
        }
    }

    private func applyVaultInventory(_ inventory: Result<[QuarantinedItemRecord], Error>) {
        switch inventory {
        case .success(let items):
            quarantinedItems = items
        case .failure(let error):
            quarantineNotice = "Could not read the quarantine vault. \(Self.quarantineErrorText(error))"
        }
    }

    private static func quarantineErrorText(_ error: Error) -> String {
        if case QuarantineError.OperationFailed(let reason) = error {
            return reason
        }
        return error.localizedDescription
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
        if !hasIndexedData && devArtifacts.isEmpty { return nil }
        return devArtifacts.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    public var appLeftoversBytes: UInt64? {
        if isLoadingOrphans || isLoadingSnapshot || isScanning { return nil }
        if !hasIndexedData && orphanedResidues.isEmpty { return nil }
        return orphanedResidues.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    public var xcodeStorageBytes: UInt64? {
        if isLoadingXcode || isLoadingSnapshot || isScanning { return nil }
        if !hasIndexedData && xcodeSummary == nil { return nil }
        return xcodeSummary?.totalBytes
    }

    public var packageCachesBytes: UInt64? {
        if isLoadingPackageCaches || isLoadingSnapshot || isScanning { return nil }
        if !hasIndexedData && packageCacheSummary == nil { return nil }
        return packageCacheSummary?.totalBytes
    }

    public var dockerStorageBytes: UInt64? {
        if isLoadingDocker || isLoadingSnapshot || isScanning { return nil }
        guard let summary = dockerSummary else { return nil }
        return summary.totalHostAllocatedBytes > 0 ? summary.totalHostAllocatedBytes : summary.totalGuestActiveBytes
    }

    public var aiModelsBytes: UInt64? {
        if isLoadingAiModels || isLoadingSnapshot || isScanning { return nil }
        if !hasIndexedData && aiModelSummary == nil { return nil }
        return aiModelSummary?.totalBytes
    }

    public var duplicatesBytes: UInt64? {
        if isLoadingDuplicates || isLoadingSnapshot || isScanning { return nil }
        if !hasIndexedData && duplicateSummary == nil { return nil }
        return duplicateSummary?.totalWastedBytes
    }

    public var largeOldMatrixBytes: UInt64? {
        if isLoadingLargeOldMatrix || isLoadingSnapshot || isScanning { return nil }
        if !hasIndexedData && largeOldMatrix == nil { return nil }
        return largeOldMatrix?.totalBytes
    }

    public var securityThreatsCount: Int? {
        if isLoadingSecurity || isLoadingSnapshot || isScanning { return nil }
        guard let summary = securitySummary else { return nil }
        let paths = quarantinedPaths
        let active = summary.threats.filter { !paths.contains($0.targetPath) }
        return active.count
    }

    public func scanCatalog() {
        scanCurrentPath(at: indexedRoot ?? FileManager.default.homeDirectoryForCurrentUser.path)
    }

    public func scanCurrentPath(at requestedPath: String? = nil) {
        guard !isInteractionDisabled else { return }
        if isSearchActive {
            clearSearch()
        }
        let path = requestedPath ?? currentPath
        catalogNotice = nil
        let volumeName = path == "/" ? "Macintosh HD" : (path as NSString).lastPathComponent
        engine.resetScanCancellation()
        isScanning = true
        cancelScanRequested = false
        scannedCount = 0
        scanThroughput = 0
        currentScanPath = path

        let progressBridge = ScanProgressBridge(viewModel: self)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let success = self.engine.scanVolume(mountPoint: path, volumeName: volumeName, callback: progressBridge)
            let total = self.engine.activeFiles()
            let saved = success && SnapshotManager.shared.saveSnapshot(engine: self.engine)

            DispatchQueue.main.async {
                self.scannedCount = total
                self.scanThroughput = 0
                self.isScanning = false
                if success {
                    self.hasLoadedSnapshot = true
                    self.indexedRoot = path
                    self.currentPath = path
                    self.pathStack = [path]
                    self.catalogNotice = saved ? nil : "The scan finished. The catalog could not be saved."
                    self.refreshTableItems()
                    self.refreshStorageReconciliation()
                    self.refreshLoadedTools()
                } else if self.cancelScanRequested {
                    self.catalogNotice = "Scan cancelled"
                } else {
                    self.catalogNotice = "Could not scan \(path). Check that the folder exists and Velora has access."
                }
            }
        }
    }

    public func performSearch(query: String, debounce: Bool = false) {
        pendingSearchWorkItem?.cancel()
        let request = UUID()
        searchRequest = request
        if searchQuery != query {
            searchQuery = query
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchCapped = false
        guard !trimmed.isEmpty else {
            isSearching = false
            refreshTableItems()
            return
        }
        displayedItems = []
        searchResultBytes = 0
        guard !isInteractionDisabled else {
            isSearching = false
            return
        }
        isSearching = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let hits = self.engine.search(queryStr: trimmed, maxResults: Self.maxSearchResults + 1)
            let shown = Array(hits.prefix(Int(Self.maxSearchResults)))
            let bytes = shown.reduce(0) { $0 + $1.sizeBytes }
            DispatchQueue.main.async {
                guard self.searchRequest == request,
                      self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                self.displayedItems = shown
                self.isSearchCapped = hits.count > Int(Self.maxSearchResults)
                self.searchResultBytes = bytes
                self.isSearching = false
            }
        }

        pendingSearchWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + (debounce ? 0.15 : 0), execute: workItem
        )
    }

    // MARK: - Navigation

    public func navigateToRoot() {
        guard !isInteractionDisabled else { return }
        activeSidebarId = "tool_files"
        currentPath = indexedRoot ?? FileManager.default.homeDirectoryForCurrentUser.path
        pathStack = [currentPath]
        clearSearch()
    }

    public func drillDownPath(_ path: String) {
        guard !isInteractionDisabled else { return }
        if isSearchActive {
            let root = indexedRoot ?? FileManager.default.homeDirectoryForCurrentUser.path
            var ancestors = [path]
            while let last = ancestors.last, last != root, last != "/" {
                ancestors.append((last as NSString).deletingLastPathComponent)
            }
            pathStack = Array(ancestors.reversed())
        } else if path != currentPath {
            pathStack.append(path)
        }
        activeSidebarId = "tool_files"
        currentPath = path
        clearSearch()
    }

    public func navigateUp() {
        guard !isInteractionDisabled, pathStack.count > 1 else { return }
        pathStack.removeLast()
        currentPath = pathStack[pathStack.count - 1]
        activeSidebarId = "tool_files"
        clearSearch()
    }

    public func refreshTableItems() {
        guard !isSearchActive else { return }
        let request = UUID()
        folderRequest = request
        let path = currentPath
        isLoadingFolder = true
        folderErrorMessage = nil
        displayedItems = []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = Result { try self.engine.indexedChildren(path: path) ?? self.readDirectory(at: path) }
            DispatchQueue.main.async {
                guard self.folderRequest == request, self.currentPath == path else { return }
                self.isLoadingFolder = false
                guard !self.isSearchActive else { return }
                switch result {
                case .success(let items):
                    self.displayedItems = items
                case .failure(let error):
                    self.folderErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func readDirectory(at path: String) throws -> [SearchResultItem] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: Array(keys)
        )
        return contents.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            let isDir = values?.isDirectory ?? false
            let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return SearchResultItem(
                name: url.lastPathComponent,
                path: url.path,
                sizeBytes: isDir ? 0 : UInt64(max(0, values?.fileSize ?? 0)),
                modifiedSecs: UInt64(max(0, modified)),
                isDir: isDir,
                colorHex: colorHexForExtension(isDir ? url.lastPathComponent.lowercased() : url.pathExtension.lowercased(), isDir: isDir)
            )
        }
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
        guard !isInteractionDisabled else { return }
        engine.collectItem(path: path, sizeBytes: size, isDir: isDir)
        syncCollectorState()
    }

    public func removeCollected(path: String) {
        guard !isInteractionDisabled else { return }
        engine.removeCollected(path: path)
        syncCollectorState()
    }

    public func clearCollector() {
        guard !isInteractionDisabled else { return }
        engine.clearCollector()
        syncCollectorState()
    }

    public func syncCollectorState() {
        collectorItems = engine.collectorItems()
        collectorTotalSize = engine.collectorTotalSize()
    }

    public func cleanStagedItems() {
        guard !isInteractionDisabled, !collectorItems.isEmpty else { return }

        let items = collectorItems
        let total = items.count
        isCleaning = true
        cleaningCurrentIndex = 0
        cleaningTotalCount = total
        cleaningMovedBytes = 0
        cleaningTotalBytes = collectorTotalSize
        cleaningCurrentFileName = (items[0].path as NSString).lastPathComponent
        cleaningEstimatedSecondsRemaining = nil
        cleaningErrorMessage = nil
        cancelCleaningRequested = false

        cleaningTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var completedPaths: [String] = []
            var movedBytes: UInt64 = 0
            var errors: [String] = []
            let startTime = Date()
            var lastUpdate = startTime

            for (index, item) in items.enumerated() {
                guard !Task.isCancelled else { break }
                let url = URL(fileURLWithPath: item.path)
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    completedPaths.append(item.path)
                    movedBytes += item.sizeBytes
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain,
                       [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code),
                       !FileManager.default.fileExists(atPath: item.path) {
                        completedPaths.append(item.path)
                    } else {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                let now = Date()
                let completed = index + 1
                if completed == total || now.timeIntervalSince(lastUpdate) >= 0.05 {
                    lastUpdate = now
                    let bytes = movedBytes
                    let nextName = completed < total ? (items[completed].path as NSString).lastPathComponent : ""
                    let eta = now.timeIntervalSince(startTime) / Double(completed) * Double(total - completed)
                    await MainActor.run {
                        self.cleaningCurrentIndex = completed
                        self.cleaningMovedBytes = bytes
                        self.cleaningCurrentFileName = nextName
                        self.cleaningEstimatedSecondsRemaining = eta
                    }
                }
            }

            let changed = !completedPaths.isEmpty
            var saved = true
            if changed {
                _ = self.engine.markDeletedBatch(paths: completedPaths)
                for path in completedPaths {
                    self.engine.removeCollected(path: path)
                }
                if self.engine.indexedRoot() != nil {
                    saved = SnapshotManager.shared.saveSnapshot(engine: self.engine)
                }
            }

            let activeCount = self.engine.activeFiles()
            var notices: [String] = []
            if let firstError = errors.first {
                notices.append("\(errors.count) items could not be moved to Trash. \(firstError)")
            }
            if Task.isCancelled {
                notices.append("Cleanup stopped. Unprocessed items are still staged.")
            }
            if !saved {
                notices.append("The updated catalog could not be saved.")
            }
            let message = notices.isEmpty ? nil : notices.joined(separator: "\n")
            await MainActor.run {
                self.cleaningTask = nil
                self.isCleaning = false
                self.cleaningErrorMessage = message
                self.syncCollectorState()
                if changed {
                    self.scannedCount = activeCount
                    if self.isSearchActive {
                        self.performSearch(query: self.searchQuery)
                    } else {
                        self.refreshTableItems()
                    }
                    self.refreshStorageReconciliation()
                    self.refreshLoadedTools()
                }
            }
        }
    }

    private func refreshLoadedTools() {
        if !devArtifacts.isEmpty { loadDevArtifacts() }
        if xcodeSummary != nil { loadXcodeSummary() }
        if packageCacheSummary != nil { loadPackageCaches() }
        if aiModelSummary != nil { loadAiModels() }
        if !installedApps.isEmpty { loadInstalledApps() }
        if !orphanedResidues.isEmpty { loadOrphanedResidues() }
        if largeOldMatrix != nil { loadLargeOldMatrix() }
        if duplicateSummary != nil { loadDuplicates() }
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
        guard !isInteractionDisabled, !shredQueue.isEmpty else { return }

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

            let activeCount = self.engine.activeFiles()
            let successfulPaths = Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
            if self.engine.indexedRoot() != nil {
                SnapshotManager.shared.saveSnapshot(engine: self.engine)
            }

            DispatchQueue.main.async {
                self.isShredding = false
                if result.success || result.filesShredded > 0 {
                    self.shredQueue.removeAll { successfulPaths.contains($0.path) }
                    let itemWord = result.filesShredded == 1 ? "item" : "items"
                    self.shredSuccessMessage = "Overwrote and deleted \(result.filesShredded) \(itemWord)."
                }

                if !result.errors.isEmpty {
                    self.shredErrorMessage = result.errors.joined(separator: "\n")
                }

                self.syncCollectorState()
                self.scannedCount = activeCount
                self.refreshTableItems()
                self.refreshStorageReconciliation()

                if !self.installedApps.isEmpty {
                    self.loadInstalledApps()
                }
                if !self.orphanedResidues.isEmpty {
                    self.loadOrphanedResidues()
                }
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
            return "Seven overwrite passes using alternating bit patterns and random data."
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
            guard let viewModel = self?.viewModel, viewModel.isScanning, !viewModel.cancelScanRequested else { return }
            viewModel.scannedCount = scannedCount
            viewModel.scanThroughput = throughput
            viewModel.currentScanPath = currentPath
        }
    }
}
