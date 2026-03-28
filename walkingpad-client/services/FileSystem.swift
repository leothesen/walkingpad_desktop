import Foundation

/// Simple file persistence helper that reads/writes to the app's Autosave Information directory.
/// Path: ~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information/
///
/// Used for storing workout history (workouts.json) and MQTT config (.walkingpad-client-mqtt.json).
/// This directory is accessible within the app sandbox without additional entitlements.
class FileSystem {
    /// Returns the app's Autosave Information directory, creating it if necessary.
    private func getDirectory() -> URL {
        let paths = FileManager.default.urls(for: .autosavedInformationDirectory, in: .userDomainMask)
        let path = paths[0]
        try? FileManager.default.createDirectory(atPath: path.path, withIntermediateDirectories: true)
        return path
    }
    
    public func save(filename: String, data: Data) {
        let path = self.getDirectory().appendingPathComponent(filename)
        print("saving to \(path)")
        do {
            try data.write(to: path)
        } catch {
            print("Failed to write to \(path): \(error)")
        }
    }
    
    public func load(filename: String) -> Data? {
        let path = self.getDirectory().appendingPathComponent(filename)
        print("loading from \(path)")
        do {
            return try Data(contentsOf: path)
        } catch {
            print("Failed to load from \(path): \(error)")
            return nil
        }
    }
    
}
