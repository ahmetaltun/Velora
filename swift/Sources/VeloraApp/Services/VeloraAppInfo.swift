import Foundation
import AppKit

/// Centralized application metadata provider for Velora.
/// Single source of truth for runtime version, build number, and UI formatting.
public enum VeloraAppInfo {
    /// Canonical fallback matching Cargo.toml workspace version
    public static let fallbackVersion = "0.4.0"

    /// Marketing release version (e.g. "0.4.0")
    public static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    /// Build version number (e.g. "0.3.0" or "42")
    public static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? shortVersion
    }

    /// Clean version for sidebar footer: "Version 0.3.0" or "Version 0.3.0 (42)"
    public static var formattedSidebarVersion: String {
        let ver = shortVersion
        let build = buildVersion
        if !build.isEmpty && build != ver {
            return "Version \(ver) (\(build))"
        }
        return "Version \(ver)"
    }

    /// Clean version for settings pill badge: "v0.3.0" or "v0.3.0 (Build 42)"
    public static var formattedBadgeVersion: String {
        let ver = shortVersion
        let build = buildVersion
        if !build.isEmpty && build != ver {
            return "v\(ver) (Build \(build))"
        }
        return "v\(ver)"
    }
}
