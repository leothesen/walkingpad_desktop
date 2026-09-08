import Foundation
import os

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

/// Crash-safe logging that outlives the process.
///
/// `ActivityLog` and the BLE debug console are both bounded in-memory buffers, so
/// when the app dies everything that would explain the death dies with it: the only
/// other output was `print()`, and a menu-bar app's stdout goes nowhere anybody can
/// read back. This writes the same events to a daily file *and* to the unified log,
/// so `log show --predicate 'subsystem == "klassm.walkingpad-client"'` works too.
///
/// Three properties make it worth trusting after a crash:
/// - **Written synchronously.** Nothing waits in a userspace buffer, so a trap
///   cannot take the lines that explain it with it. At roughly one line per second
///   the cost is a `write(2)` per line, which is not worth optimising away.
/// - **It never throws and never traps.** A logger that can take the app down is
///   worse than no logger, so every failure path degrades to writing less.
/// - **It is bounded.** One file per day, pruned after `retentionDays`. Past
///   `maxBytesPerDay` the high-volume `.trace` frames are dropped and everything
///   else still gets through.
final class PersistentLog {
    static let shared = PersistentLog()

    enum Level: String {
        case trace = "TRACE"
        case info  = "INFO "
        case warn  = "WARN "
        case error = "ERROR"
    }

    /// Log directory: ~/Library/Application Support/walkingpad-client/logs
    static var directory: URL {
        FileSystem.directory.appendingPathComponent("logs", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "klassm.walkingpad-client.persistent-log")
    private let osLog = Logger(subsystem: "klassm.walkingpad-client", category: "app")

    private let retentionDays = 14
    private let maxBytesPerDay = 16 * 1024 * 1024

    private var handle: FileHandle?
    private var openDayKey = ""
    private var bytesWritten = 0

    /// Exists only while the app is running. Still present at the next launch means
    /// the previous run never reached `finishSession` — it crashed or was killed.
    private var runMarker: URL {
        PersistentLog.directory.appendingPathComponent("running.marker")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Writing

    func write(_ message: String, level: Level = .info) {
        switch level {
        case .error: osLog.error("\(message, privacy: .public)")
        case .warn:  osLog.warning("\(message, privacy: .public)")
        case .info:  osLog.info("\(message, privacy: .public)")
        case .trace: osLog.debug("\(message, privacy: .public)")
        }
        queue.sync { append(format(level, message), level: level) }
    }

    /// Records the app starting, and reports whether the previous run ended without
    /// a clean shutdown so the caller can say so somewhere the user will see it.
    @discardableResult
    func startSession(version: String, pid: Int32) -> Bool {
        var wasUnclean = false
        queue.sync {
            rollIfNeeded()
            if FileManager.default.fileExists(atPath: runMarker.path) {
                wasUnclean = true
                let previous = (try? String(contentsOf: runMarker, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
                append(format(.error, "PREVIOUS RUN ENDED UNCLEANLY (\(previous)) — the lines above it are what it was doing"),
                       level: .error)
            }
            append(format(.info, "=== start v\(version) pid \(pid) ==="), level: .info)
            try? "started \(PersistentLog.stamp.string(from: Date()))"
                .write(to: runMarker, atomically: true, encoding: .utf8)
        }
        return wasUnclean
    }

    /// Records a clean shutdown so the next launch does not report a crash.
    func finishSession(reason: String) {
        queue.sync {
            rollIfNeeded()
            append(format(.info, "=== exit (\(reason)) ==="), level: .info)
            try? FileManager.default.removeItem(at: runMarker)
        }
    }

    /// Today's log file, for the "reveal in Finder" affordance in the debug panel.
    var currentFile: URL {
        PersistentLog.directory
            .appendingPathComponent("walkingpad-\(PersistentLog.day.string(from: Date())).log")
    }

    /// Last `maxBytes` of today's log, for the debug panel's copy button.
    func tail(maxBytes: Int = 256 * 1024) -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: currentFile) else { return "" }
            let slice = data.count > maxBytes ? Data(data.suffix(maxBytes)) : data
            return String(data: slice, encoding: .utf8) ?? ""
        }
    }

    // MARK: - Internals (all called on `queue`)

    private func format(_ level: Level, _ message: String) -> String {
        "\(PersistentLog.stamp.string(from: Date())) \(level.rawValue) \(message)\n"
    }

    private func append(_ line: String, level: Level) {
        rollIfNeeded()
        guard let handle else { return }
        // Shedding trace keeps a pathological BLE stream from filling the disk
        // without also losing the errors that would explain it.
        if level == .trace && bytesWritten >= maxBytesPerDay { return }
        guard let data = line.data(using: .utf8) else { return }
        do {
            try handle.write(contentsOf: data)
            bytesWritten += data.count
        } catch {
            // Disk full, file removed underneath us, a sandbox denial: drop the line
            // and force a reopen on the next write rather than taking the app down.
            try? handle.close()
            self.handle = nil
            openDayKey = ""
        }
    }

    private func rollIfNeeded() {
        let key = PersistentLog.day.string(from: Date())
        guard key != openDayKey || handle == nil else { return }

        try? handle?.close()
        handle = nil

        let fm = FileManager.default
        let dir = PersistentLog.directory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("walkingpad-\(key).log")
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        bytesWritten = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        openDayKey = key
        prune()
    }

    private func prune() {
        let fm = FileManager.default
        let dir = PersistentLog.directory
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }

        for name in names where name.hasPrefix("walkingpad-") && name.hasSuffix(".log") {
            let key = String(name.dropFirst("walkingpad-".count).dropLast(".log".count))
            guard let date = PersistentLog.day.date(from: key), date < cutoff else { continue }
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
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
        PersistentLog.shared.write(message, level: type.persistentLevel)
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

extension ActivityLogEntry.LogType {
    var persistentLevel: PersistentLog.Level {
        switch self {
        case .error: return .error
        case .info, .success, .progress: return .info
        }
    }
}

/// Global shorthand — routes all app logging through ActivityLog so it appears in the
/// debug panel and, via `PersistentLog`, in a file that survives a crash.
func appLog(_ message: String, type: ActivityLogEntry.LogType = .info) {
    ActivityLog.shared.log(message, type: type)
}
