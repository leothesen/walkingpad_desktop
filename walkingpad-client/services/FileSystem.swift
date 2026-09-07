import Foundation

/// Simple file persistence helper that reads/writes to the app's data directory.
///
/// Used for storing workout history (workouts.json), Notion/Strava/MQTT config.
///
/// Storage location history:
/// 1. `~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information` (sandboxed era)
/// 2. `~/Library/Autosave Information` (after the sandbox was disabled)
/// 3. `~/Library/Application Support/walkingpad-client` (current)
///
/// Location 2 broke when macOS put `~/Library/Autosave Information` behind privacy
/// protection — all reads/writes fail with "Operation not permitted". Application
/// Support is the canonical home for this kind of data and is not protected.
/// On first access, files found in the legacy locations are migrated best-effort;
/// the OS may still deny reads from the old paths, which is logged so the user
/// knows to re-enter config in the debug panel.
class FileSystem {
    /// Current data directory: ~/Library/Application Support/walkingpad-client
    static let directory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("walkingpad-client", isDirectory: true)

    /// Old storage locations, newest first.
    private static let legacyDirectories: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Autosave Information"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information")
    ]

    private static var hasMigrated = false

    /// Returns the app's data directory, creating it and running legacy migration if necessary.
    private func getDirectory() -> URL {
        let path = FileSystem.directory
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        if !FileSystem.hasMigrated {
            FileSystem.hasMigrated = true
            migrateFromLegacyLocations(to: path)
        }

        return path
    }

    /// Copies files from old storage locations if they exist and aren't already in the new one.
    /// Reads can be denied by macOS privacy protection on the old paths — that is logged
    /// and skipped rather than treated as fatal.
    private func migrateFromLegacyLocations(to newDir: URL) {
        let configFiles = [
            ".walkingpad-client-notion.json",
            ".walkingpad-client-strava.json",
            ".walkingpad-client-mqtt.json",
            "workouts.json"
        ]

        for filename in configFiles {
            let dest = newDir.appendingPathComponent(filename)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }

            for legacyDir in FileSystem.legacyDirectories {
                let source = legacyDir.appendingPathComponent(filename)
                do {
                    let data = try Data(contentsOf: source)
                    try data.write(to: dest, options: .atomic)
                    appLog("Migrated \(filename) from \(legacyDir.path)")
                    break
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                    continue
                } catch {
                    appLog("Could not migrate \(filename) from \(legacyDir.path): \(error.localizedDescription). If macOS blocked the read, re-enter this config in the Stats → Debug panel.", type: .error)
                }
            }
        }
    }

    public func save(filename: String, data: Data) {
        let path = self.getDirectory().appendingPathComponent(filename)
        do {
            try data.write(to: path, options: .atomic)
        } catch {
            appLog("Failed to write to \(path): \(error)", type: .error)
        }
    }

    /// Deletes a file if it is there. A missing file is the success case, so callers
    /// can clear state unconditionally without first checking for it.
    public func remove(filename: String) {
        let path = self.getDirectory().appendingPathComponent(filename)
        do {
            try FileManager.default.removeItem(at: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            appLog("Failed to remove \(path): \(error)", type: .error)
        }
    }

    public func load(filename: String) -> Data? {
        let path = self.getDirectory().appendingPathComponent(filename)
        do {
            return try Data(contentsOf: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            appLog("Failed to load from \(path): \(error)", type: .error)
            return nil
        }
    }
}
