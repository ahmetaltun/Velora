import AppKit
import Combine
import Sparkle
import SwiftUI

/// Central update coordinator for Velora, wrapping Sparkle 2's `SPUStandardUpdaterController`.
/// Provides observable state for SwiftUI views and menu bar commands.
@MainActor
public final class VeloraUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = VeloraUpdateManager()

    @Published public private(set) var canCheckForUpdates: Bool = false
    @Published public var automaticallyChecksForUpdates: Bool = true
    @Published public var automaticallyDownloadsUpdates: Bool = false
    @Published public private(set) var lastUpdateCheckDate: Date? = nil
    @Published public private(set) var isChecking: Bool = false

    private var updaterController: SPUStandardUpdaterController?

    public var updater: SPUUpdater? {
        updaterController?.updater
    }

    public var currentVersionString: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "v\(shortVersion) (Build \(buildVersion))"
    }

    public var feedURLString: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "https://github.com/ahmetaltun/Velora/releases/latest/download/appcast.xml"
    }

    private override init() {
        super.init()
        setupUpdater()
    }

    private func setupUpdater() {
        // Initialize Sparkle standard updater controller
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updaterController = controller

        // Bind Sparkle dynamic KVO properties to Combine publishers
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyChecksForUpdates)

        controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$automaticallyDownloadsUpdates)

        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastUpdateCheckDate)
    }

    /// User-initiated update check with modal UI presentation
    public func checkForUpdates() {
        guard let updater = updater, canCheckForUpdates else {
            #if DEBUG
            print("⚠️ [Sparkle] Cannot check for updates right now (canCheckForUpdates=false).")
            #endif
            return
        }
        isChecking = true
        updater.checkForUpdates()
    }

    /// Background update check without dialogs unless a valid update is found
    public func checkForUpdatesInBackground() {
        guard let updater = updater else { return }
        updater.checkForUpdatesInBackground()
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    public func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
        automaticallyDownloadsUpdates = enabled
    }

    // MARK: - SPUUpdaterDelegate

    public func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        isChecking = false
        #if DEBUG
        print("✅ [Sparkle] Successfully loaded appcast feed (\(appcast.items.count) item(s)).")
        #endif
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        isChecking = false
        #if DEBUG
        print("🚀 [Sparkle] Found valid update: \(item.displayVersionString) (\(item.versionString))")
        #endif
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        isChecking = false
        #if DEBUG
        print("ℹ️ [Sparkle] Update check finished with error: \(error.localizedDescription)")
        #endif
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        isChecking = false
        #if DEBUG
        print("ℹ️ [Sparkle] App is up to date (no newer version found).")
        #endif
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        isChecking = false
        #if DEBUG
        print("⚠️ [Sparkle] Update aborted: \(error.localizedDescription)")
        #endif
    }
}

/// SwiftUI menu button component for "Check for Updates…"
public struct CheckForUpdatesMenuItem: View {
    @ObservedObject private var updateManager = VeloraUpdateManager.shared

    public init() {}

    public var body: some View {
        Button("Check for Updates…") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}
