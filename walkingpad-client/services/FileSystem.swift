import Foundation

/// Simple file persistence helper that reads/writes to the app's Autosave Information directory.
///
/// Used for storing workout history (workouts.json), Notion/Strava/MQTT config.
/// On first access, migrates any existing files from the old sandboxed container path.
class FileSystem {
    /// Old sandboxed container path where config files lived before sandbox was disabled.
    private static let legacyContainerDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information")

    private static var hasMigrated = false

    /// Returns the app's Autosave Information directory, creating it if necessary.
    private func getDirectory() -> URL {
        let paths = FileManager.default.urls(for: .autosavedInformationDirectory, in: .userDomainMask)
        let path = paths[0]
        try? FileManager.default.createDirectory(atPath: path.path, withIntermediateDirectories: true)

        // Migrate legacy config files from the old sandboxed container
        if !FileSystem.hasMigrated {
            FileSystem.hasMigrated = true
            migrateFromLegacyContainer(to: path)
        }

        return path
    }

    /// Copies config files from the old sandbox container if they exist and aren't already in the new location.
    private func migrateFromLegacyContainer(to newDir: URL) {
        let legacyDir = FileSystem.legacyContainerDir
        guard FileManager.default.fileExists(atPath: legacyDir.path) else { return }

        let configFiles = [
            ".walkingpad-client-notion.json",
            ".walkingpad-client-strava.json",
            ".walkingpad-client-mqtt.json",
            "workouts.json"
        ]

        for filename in configFiles {
            let source = legacyDir.appendingPathComponent(filename)
            let dest = newDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: source.path) &&
               !FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try FileManager.default.copyItem(at: source, to: dest)
                    appLog("Migrated \(filename) from legacy container")
                } catch {
                    appLog("Failed to migrate \(filename): \(error)")
                }
            }
        }
    }

    public func save(filename: String, data: Data) {
        let path = self.getDirectory().appendingPathComponent(filename)
        appLog("saving to \(path)")
        do {
            try data.write(to: path)
        } catch {
            appLog("Failed to write to \(path): \(error)")
        }
    }

    public func load(filename: String) -> Data? {
        let path = self.getDirectory().appendingPathComponent(filename)
        appLog("loading from \(path)")
        do {
            return try Data(contentsOf: path)
        } catch {
            appLog("Failed to load from \(path): \(error)")
            return nil
        }
    }
}
