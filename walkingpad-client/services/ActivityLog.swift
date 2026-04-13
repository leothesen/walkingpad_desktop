import Foundation

/// A single entry in the activity log shown in the stats window.
struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let message: String
    let type: LogType

    enum LogType {
        case info, success, error, progress
    }
}

/// Shared observable log for the app's sync operations.
/// Used by StravaService, NotionService, and displayed in the stats debug panel.
class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    @Published var entries: [ActivityLogEntry] = []
    private let maxEntries = 100

    func log(_ message: String, type: ActivityLogEntry.LogType = .info) {
        let entry = ActivityLogEntry(time: Date(), message: message, type: type)
        print("ActivityLog: \(message)")
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func info(_ message: String) { log(message, type: .info) }
    func success(_ message: String) { log(message, type: .success) }
    func error(_ message: String) { log(message, type: .error) }
    func progress(_ message: String) { log(message, type: .progress) }
}

/// Global shorthand — routes all app logging through ActivityLog so it appears in the debug panel.
func appLog(_ message: String, type: ActivityLogEntry.LogType = .info) {
    ActivityLog.shared.log(message, type: type)
}
