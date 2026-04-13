import Foundation

/// Notion API client for syncing walking sessions to a Notion database.
/// Handles Keychain-based config storage, pushing sessions, and fetching all sessions.
class NotionService: ObservableObject {
    static let shared = NotionService()

    @Published var isConfigured: Bool = false

    private let baseURL = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
    private let session = URLSession(configuration: .default)

    private let apiKeyKeychainKey = "notionApiKey"
    private let databaseIdKeychainKey = "notionDatabaseId"

    private var apiKey: String?
    private var databaseId: String?

    private static let saTimeZone = TimeZone(identifier: "Africa/Johannesburg")!

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = saTimeZone
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = saTimeZone
        return f
    }()

    private static let titleDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = saTimeZone
        return f
    }()

    private struct NotionConfig: Codable {
        var apiKey: String
        var databaseId: String
    }

    private let configFilename = ".walkingpad-client-notion.json"

    init() {
        loadConfig()
    }

    // MARK: - Config (JSON file)

    func saveConfig(apiKey: String, databaseId: String) {
        self.apiKey = apiKey
        self.databaseId = databaseId
        self.isConfigured = true
        let config = NotionConfig(apiKey: apiKey, databaseId: databaseId)
        if let data = try? JSONEncoder().encode(config) {
            FileSystem().save(filename: configFilename, data: data)
        }
    }

    func clearConfig() {
        self.apiKey = nil
        self.databaseId = nil
        self.isConfigured = false
        FileSystem().save(filename: configFilename, data: Data("{}".utf8))
    }

    func loadConfig() {
        guard let data = FileSystem().load(filename: configFilename),
              let config = try? JSONDecoder().decode(NotionConfig.self, from: data) else {
            self.isConfigured = false
            return
        }
        self.apiKey = config.apiKey
        self.databaseId = config.databaseId
        self.isConfigured = !config.apiKey.isEmpty && !config.databaseId.isEmpty
    }

    func currentDatabaseId() -> String? {
        return databaseId
    }

    // MARK: - Push Session

    /// Pushes a completed session to the Notion database.
    /// Queries existing sessions for the day to determine the correct session number.
    func pushSession(_ sessionData: SessionSaveData, sessionNumber: Int) async -> Bool {
        guard let apiKey = apiKey, let databaseId = databaseId else {
            print("Notion: not configured, skipping push")
            return false
        }

        // Query Notion for how many sessions already exist today to get correct numbering
        let existingCount = await fetchTodaySessions()?.count ?? 0
        let actualSessionNumber = existingCount + 1

        let duration = sessionData.endTime.timeIntervalSince(sessionData.startTime) / 60.0
        let dateStr = Self.dateFormatter.string(from: sessionData.startTime)
        let startStr = Self.timeFormatter.string(from: sessionData.startTime)
        let endStr = Self.timeFormatter.string(from: sessionData.endTime)
        let titleStr = "Session #\(actualSessionNumber) - \(Self.titleDateFormatter.string(from: sessionData.startTime))"

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
                    // Skip archived/trashed pages
                    let archived = page["archived"] as? Bool ?? false
                    let inTrash = page["in_trash"] as? Bool ?? false
                    if archived || inTrash {
                        let title = ((page["properties"] as? [String: Any])?["Session"] as? [String: Any])?["title"] as? [[String: Any]]
                        let name = (title?.first?["plain_text"] as? String) ?? "unknown"
                        print("Notion: skipping archived/trashed page: \(name)")
                        continue
                    }
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

    /// Fetches only today's sessions from Notion (filtered by date).
    func fetchTodaySessions() async -> [SessionSaveData]? {
        return await fetchSessions(for: Date())
    }

    /// Fetches sessions for a specific date from Notion.
    func fetchSessions(for date: Date) async -> [SessionSaveData]? {
        guard let apiKey = apiKey, let databaseId = databaseId else { return nil }

        let dateStr = Self.dateFormatter.string(from: date)
        let body: [String: Any] = [
            "page_size": 100,
            "filter": [
                "property": "Date",
                "date": ["equals": dateStr]
            ]
        ]

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/databases/\(databaseId)/query")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                return nil
            }

            let sessions = results.filter {
                !($0["archived"] as? Bool ?? false) && !($0["in_trash"] as? Bool ?? false)
            }.compactMap { parseSession(from: $0) }
            print("Notion: fetched \(sessions.count) sessions for \(dateStr)")
            return sessions
        } catch {
            print("Notion: fetchSessions error: \(error)")
            return nil
        }
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
        formatter.timeZone = TimeZone(identifier: "Africa/Johannesburg")
        return formatter.date(from: combined)
    }

    // MARK: - Day Totals

    private let dayTotalsDatabaseId = "333deabd-9164-80fb-b3e6-e6292f0a9826"

    /// Check if a Day Totals entry exists for a date and if Strava was posted.
    func fetchDayTotal(for date: Date) async -> (exists: Bool, stravaPosted: Bool, pageId: String?)? {
        guard let apiKey = apiKey else { return nil }

        let dateStr = Self.dateFormatter.string(from: date)
        let body: [String: Any] = [
            "page_size": 1,
            "filter": ["property": "Date", "date": ["equals": dateStr]]
        ]

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/databases/\(dayTotalsDatabaseId)/query")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return nil }

            if let page = results.first {
                let props = page["properties"] as? [String: Any] ?? [:]
                let stravaPostedAt = extractRichText(props["Strava Posted At"])
                let pageId = page["id"] as? String
                return (exists: true, stravaPosted: !stravaPostedAt.isEmpty, pageId: pageId)
            }
            return (exists: false, stravaPosted: false, pageId: nil)
        } catch {
            print("Notion: fetchDayTotal error: \(error)")
            return nil
        }
    }

    /// Create or update the Day Totals entry for today.
    func upsertDayTotal(date: Date, sessions: [SessionSaveData], stravaActivityId: String? = nil) async -> Bool {
        guard let apiKey = apiKey else { return false }

        let totalDistance = sessions.reduce(0) { $0 + $1.distance }
        let totalSteps = sessions.reduce(0) { $0 + $1.steps }
        let totalSeconds = sessions.reduce(0) { $0 + Int($1.endTime.timeIntervalSince($1.startTime)) }
        let durationMin = round(Double(totalSeconds) / 6.0) / 10.0
        let dateStr = Self.dateFormatter.string(from: date)
        let distKm = Double(totalDistance) / 1000.0

        var properties: [String: Any] = [
            "Day": ["title": [["text": ["content": "\(String(format: "%.1f", distKm))km — \(dateStr)"]]]],
            "Date": ["date": ["start": dateStr]],
            "Total Distance (m)": ["number": totalDistance],
            "Total Steps": ["number": totalSteps],
            "Total Duration (min)": ["number": durationMin],
            "Sessions": ["number": sessions.count]
        ]

        if let activityId = stravaActivityId {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            timeFormatter.timeZone = Self.saTimeZone
            properties["Strava Posted At"] = ["rich_text": [["text": ["content": timeFormatter.string(from: Date())]]]]
            properties["Strava Activity ID"] = ["rich_text": [["text": ["content": activityId]]]]
        }

        // Check if entry exists
        if let existing = await fetchDayTotal(for: date), existing.exists, let pageId = existing.pageId {
            // Update existing
            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/pages/\(pageId)")!)
                request.httpMethod = "PATCH"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["properties": properties])

                let (_, response) = try await session.data(for: request)
                let success = (response as? HTTPURLResponse)?.statusCode == 200
                print("Notion: day total updated: \(success)")
                return success
            } catch {
                print("Notion: day total update error: \(error)")
                return false
            }
        } else {
            // Create new
            let body: [String: Any] = [
                "parent": ["database_id": dayTotalsDatabaseId],
                "properties": properties
            ]
            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/pages")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await session.data(for: request)
                let success = (response as? HTTPURLResponse)?.statusCode == 200
                print("Notion: day total created: \(success)")
                return success
            } catch {
                print("Notion: day total create error: \(error)")
                return false
            }
        }
    }

    /// Check if Strava has been posted for a given date (via Day Totals).
    func isStravaPosted(for date: Date) async -> Bool {
        guard let result = await fetchDayTotal(for: date) else { return false }
        return result.stravaPosted
    }

    /// Fetches the most recent Strava sync date by checking recent Day Totals entries.
    func fetchLastStravaSync() async -> Date? {
        guard let apiKey = apiKey else { return nil }

        let body: [String: Any] = [
            "page_size": 10,
            "sorts": [["property": "Date", "direction": "descending"]]
        ]

        do {
            var request = URLRequest(url: URL(string: "\(baseURL)/databases/\(dayTotalsDatabaseId)/query")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return nil }

            for page in results {
                let props = page["properties"] as? [String: Any] ?? [:]
                let postedAt = extractRichText(props["Strava Posted At"])
                guard !postedAt.isEmpty else { continue }

                guard let dateProp = props["Date"] as? [String: Any],
                      let dateObj = dateProp["date"] as? [String: Any],
                      let dateStr = dateObj["start"] as? String,
                      let date = Self.dateFormatter.date(from: dateStr) else { continue }

                return combineDateTime(date: date, timeStr: postedAt) ?? date
            }
            return nil
        } catch {
            print("Notion: fetchLastStravaSync error: \(error)")
            return nil
        }
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
