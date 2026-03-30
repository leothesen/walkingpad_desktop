import Foundation
import Security

/// Notion API client for syncing walking sessions to a Notion database.
/// Handles Keychain-based config storage, pushing sessions, and fetching all sessions.
class NotionService: ObservableObject {
    @Published var isConfigured: Bool = false

    private let baseURL = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
    private let session = URLSession(configuration: .default)

    private let apiKeyKeychainKey = "notionApiKey"
    private let databaseIdKeychainKey = "notionDatabaseId"

    private var apiKey: String?
    private var databaseId: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let titleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    init() {
        loadConfig()
    }

    // MARK: - Config (Keychain)

    func saveConfig(apiKey: String, databaseId: String) {
        saveKeychain(key: apiKeyKeychainKey, value: apiKey)
        saveKeychain(key: databaseIdKeychainKey, value: databaseId)
        self.apiKey = apiKey
        self.databaseId = databaseId
        self.isConfigured = true
    }

    func clearConfig() {
        deleteKeychain(key: apiKeyKeychainKey)
        deleteKeychain(key: databaseIdKeychainKey)
        self.apiKey = nil
        self.databaseId = nil
        self.isConfigured = false
    }

    func loadConfig() {
        self.apiKey = loadKeychain(key: apiKeyKeychainKey)
        self.databaseId = loadKeychain(key: databaseIdKeychainKey)
        self.isConfigured = apiKey != nil && databaseId != nil
    }

    func currentDatabaseId() -> String? {
        return databaseId
    }

    // MARK: - Push Session

    /// Pushes a completed session to the Notion database.
    func pushSession(_ sessionData: SessionSaveData, sessionNumber: Int) async -> Bool {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            print("Notion: not configured, skipping push")
            return false
        }

        let duration = sessionData.endTime.timeIntervalSince(sessionData.startTime) / 60.0
        let dateStr = Self.dateFormatter.string(from: sessionData.startTime)
        let startStr = Self.timeFormatter.string(from: sessionData.startTime)
        let endStr = Self.timeFormatter.string(from: sessionData.endTime)
        let titleStr = "Session #\(sessionNumber) - \(Self.titleDateFormatter.string(from: sessionData.startTime))"

        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": [
                "Session": ["title": [["text": ["content": titleStr]]]],
                "Date": ["date": ["start": dateStr]],
                "Start Time": ["rich_text": [["text": ["content": startStr]]]],
                "End Time": ["rich_text": [["text": ["content": endStr]]]],
                "Duration (min)": ["number": round(duration * 10) / 10],
                "Steps": ["number": sessionData.steps],
                "Distance (m)": ["number": sessionData.distance]
            ]
        ]

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/pages")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Notion: session pushed successfully")
                return true
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                print("Notion: push failed with status \(statusCode): \(responseBody)")
                return false
            }
        } catch {
            print("Notion: push error: \(error)")
            return false
        }
    }

    // MARK: - Fetch Sessions

    /// Fetches all sessions from the Notion database, paginating through results.
    func fetchAllSessions() async -> [SessionSaveData]? {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            return nil
        }

        var allSessions: [SessionSaveData] = []
        var hasMore = true
        var nextCursor: String? = nil

        while hasMore {
            var body: [String: Any] = [
                "page_size": 100,
                "sorts": [["property": "Date", "direction": "descending"]]
            ]
            if let cursor = nextCursor {
                body["start_cursor"] = cursor
            }

            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/databases/\(databaseId)/query")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("Notion: fetch failed with status \(statusCode)")
                    return nil
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    print("Notion: failed to parse response")
                    return nil
                }

                for page in results {
                    if let session = parseSession(from: page) {
                        allSessions.append(session)
                    }
                }

                hasMore = json["has_more"] as? Bool ?? false
                nextCursor = json["next_cursor"] as? String
            } catch {
                print("Notion: fetch error: \(error)")
                return nil
            }
        }

        print("Notion: fetched \(allSessions.count) sessions")
        for (i, s) in allSessions.enumerated() {
            print("  Notion session \(i): start=\(s.startTime) end=\(s.endTime) steps=\(s.steps) dist=\(s.distance)")
        }
        return allSessions
    }

    /// Tests the connection by fetching 1 row.
    func testConnection() async -> Bool {
        guard let apiKey = apiKey, let databaseId = databaseId else { return false }

        let body: [String: Any] = ["page_size": 1]

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/databases/\(databaseId)/query")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Parse Notion → SessionSaveData

    private func parseSession(from page: [String: Any]) -> SessionSaveData? {
        guard let properties = page["properties"] as? [String: Any] else { return nil }

        // Parse Date
        guard let dateProp = properties["Date"] as? [String: Any],
              let dateObj = dateProp["date"] as? [String: Any],
              let dateStr = dateObj["start"] as? String,
              let date = Self.dateFormatter.date(from: dateStr) else { return nil }

        // Parse Start Time
        let startTimeStr = extractRichText(properties["Start Time"])
        // Parse End Time
        let endTimeStr = extractRichText(properties["End Time"])

        // Parse start/end times by combining date + time string
        let startTime = combineDateTime(date: date, timeStr: startTimeStr) ?? date
        let endTime = combineDateTime(date: date, timeStr: endTimeStr) ?? date

        // Parse numbers
        let steps = extractNumber(properties["Steps"])
        let distance = extractNumber(properties["Distance (m)"])

        return SessionSaveData(
            startTime: startTime,
            endTime: endTime,
            steps: steps,
            distance: distance
        )
    }

    private func extractRichText(_ prop: Any?) -> String {
        guard let dict = prop as? [String: Any],
              let richText = dict["rich_text"] as? [[String: Any]],
              let first = richText.first,
              let text = first["plain_text"] as? String else { return "" }
        return text
    }

    private func extractNumber(_ prop: Any?) -> Int {
        guard let dict = prop as? [String: Any],
              let number = dict["number"] as? Double else { return 0 }
        return Int(number)
    }

    private func combineDateTime(date: Date, timeStr: String) -> Date? {
        guard !timeStr.isEmpty else { return nil }
        let combined = Self.dateFormatter.string(from: date) + " " + timeStr
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: combined)
    }

    // MARK: - Keychain Helpers

    private func saveKeychain(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.walkingpad.notion",
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.walkingpad.notion",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        if status == errSecSuccess, let data = ref as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.walkingpad.notion",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Grouping Sessions by Date

extension NotionService {
    /// Groups flat sessions into WorkoutSaveData entries (one per day) for StatsViewModel.
    static func groupSessionsByDate(_ sessions: [SessionSaveData]) -> [WorkoutSaveData] {
        let calendar = Calendar.current
        var grouped: [DateComponents: [SessionSaveData]] = [:]

        for session in sessions {
            let components = calendar.dateComponents([.year, .month, .day], from: session.startTime)
            grouped[components, default: []].append(session)
        }

        print("Notion: grouping \(sessions.count) sessions into \(grouped.count) days")
        return grouped.compactMap { (components, daySessions) -> WorkoutSaveData? in
            guard let date = calendar.date(from: components) else { return nil }
            let totalSteps = daySessions.reduce(0) { $0 + $1.steps }
            let totalDistance = daySessions.reduce(0) { $0 + $1.distance }
            let totalSeconds = daySessions.reduce(0) { $0 + Int($1.endTime.timeIntervalSince($1.startTime)) }

            return WorkoutSaveData(
                steps: totalSteps,
                distance: totalDistance,
                walkingSeconds: totalSeconds,
                date: date,
                sessions: daySessions
            )
        }.sorted { $0.date < $1.date }
    }
}
