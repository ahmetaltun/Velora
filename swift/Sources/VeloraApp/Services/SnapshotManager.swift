import Foundation
import VeloraCore

/// Manages serialization and offline persistence of the `VolumeIndex` catalog.
/// Encapsulates storage locations in Application Support and file existence checks.
public final class SnapshotManager: @unchecked Sendable {
    public static let shared = SnapshotManager()

    public let directoryURL: URL
    public let snapshotURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directoryURL = appSupport.appendingPathComponent("Velora", isDirectory: true)
        self.snapshotURL = self.directoryURL.appendingPathComponent("catalog.bin")
    }

    /// Verifies if a valid serialized catalog exists at the designated snapshot location.
    public var snapshotExists: Bool {
        FileManager.default.fileExists(atPath: snapshotURL.path)
    }

    /// Verifies whether the default catalog snapshot or any binary index file (*.bin) exists in the storage directory.
    public var hasAnyBinaryIndexFile: Bool {
        if snapshotExists {
            return true
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return files.contains { $0.pathExtension.lowercased() == "bin" }
    }

    /// Formatted file size of the existing catalog.bin file if present on disk.
    public var snapshotFileSizeFormatted: String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: snapshotURL.path),
              let size = attrs[.size] as? UInt64, size > 0 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// Ensures the parent storage directory exists on disk.
    public func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw NSError(
                    domain: "com.velora.snapshot",
                    code: 1001,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to create Application Support directory at \(directoryURL.path): \(error.localizedDescription)"
                    ]
                )
            }
        }
    }

    /// Saves the current engine volume index to disk asynchronously.
    @discardableResult
    public func saveSnapshot(engine: VeloraEngine) -> Bool {
        do {
            try ensureDirectoryExists()
            let path = snapshotURL.path
            let success = engine.saveSnapshot(destPath: path)
            if success {
                print("[SnapshotManager] Catalog successfully persisted to \(path)")
            } else {
                print("[SnapshotManager] Error: Engine failed to serialize catalog snapshot to \(path)")
            }
            return success
        } catch {
            print("[SnapshotManager] Directory creation error: \(error.localizedDescription)")
            return false
        }
    }

    /// Loads the offline snapshot from disk into the engine memory.
    @discardableResult
    public func loadSnapshot(engine: VeloraEngine) -> Bool {
        guard snapshotExists else {
            print("[SnapshotManager] No snapshot found at \(snapshotURL.path)")
            return false
        }

        let path = snapshotURL.path
        let success = engine.loadOfflineSnapshot(srcPath: path)
        if success {
            print("[SnapshotManager] Successfully loaded offline snapshot from \(path)")
        } else {
            print("[SnapshotManager] Error: Corrupted or unreadable snapshot at \(path)")
        }
        return success
    }
}
