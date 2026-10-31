import AppKit
import Combine
import Foundation

/// Central permission coordinator managing macOS Full Disk Access (FDA) detection,
/// settings deep linking, and notification dismissal state.
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    private let dismissedKey = "velora_fda_banner_dismissed"

    @Published public private(set) var hasFullDiskAccess: Bool = false
    @Published public var isBannerDismissed: Bool {
        didSet {
            UserDefaults.standard.set(isBannerDismissed, forKey: dismissedKey)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.isBannerDismissed = UserDefaults.standard.bool(forKey: dismissedKey)
        checkFullDiskAccess()

        // Automatically re-evaluate FDA status when the user switches back from System Settings
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkFullDiskAccess()
            }
            .store(in: &cancellables)
    }

    /// Verifies Full Disk Access by attempting to inspect the protected TCC database directory.
    public func checkFullDiskAccess() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let tccDir = homeDir.appendingPathComponent("Library/Application Support/com.apple.TCC").path

        if let dir = opendir(tccDir) {
            closedir(dir)
            hasFullDiskAccess = true
        } else {
            hasFullDiskAccess = false
        }
    }

    /// Direct deep link to macOS Privacy & Security > Full Disk Access in System Settings.
    public func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Dismisses the UI banner for the current user.
    public func dismissBanner() {
        isBannerDismissed = true
    }

    /// Resets dismissal state (e.g. for user settings or troubleshooting).
    public func resetBannerDismissal() {
        isBannerDismissed = false
    }
}
