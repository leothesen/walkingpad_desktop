import Foundation
import AppKit

/// Strava integration: OAuth2 authentication, daily activity posting, sync state tracking.
class StravaService: ObservableObject {
    static let shared = StravaService()

    @Published var isConnected: Bool = false
    @Published var isSyncedToday: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastError: String? = nil
    @Published var lastStravaSync: Date? = nil
    /// Recent days with walks in Notion but no Strava post, newest first.
    @Published var unsyncedDays: [UnsyncedDay] = []
    /// Day keys with a post in flight.
    @Published var postingDays: Set<String> = []
    /// Why the last post of a day failed, by day key.
    @Published var dayPostErrors: [String: String] = [:]
    @Published var uploadResultMessage: String? = nil
    @Published var uploadResultIsError: Bool = false

    /// The date when isSyncedToday was last set to true, used for day-rollover reset.
    private var syncedDate: Date?

    /// A past day whose walks never reached Strava.
    struct UnsyncedDay: Identifiable, Equatable {
        /// Notion day key, "yyyy-MM-dd".
        let key: String
        let date: Date
        let sessionCount: Int
        /// Meters
        let distance: Int
        var id: String { key }
    }

    /// How many days back to look for walks that never reached Strava.
    static let lookbackDays = 7
    /// Popover opens re-check at most this often; a new day or a wake always re-checks.
    static let recheckInterval: TimeInterval = 10 * 60

    private var isCheckingUnsynced = false
    private var lastUnsyncedCheckAt: Date?
    private var lastUnsyncedCheckDay: String?

    private var clientId: String?
    private var clientSecret: String?

    private let baseURL = "https://www.strava.com"
    private let apiURL = "https://www.strava.com/api/v3"
    private let redirectURI = "http://localhost:8234/callback"

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var oauthServer: StravaOAuthServer?

    private let configFilename = ".walkingpad-client-strava.json"

    private struct StravaConfig: Codable {
        var clientId: String?
        var clientSecret: String?
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Double?  // timeIntervalSince1970
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Resets isSyncedToday to false if the day has changed since it was set.
    func resetIfDateChanged() {
        if let syncedDate = syncedDate, !Calendar.current.isDateInToday(syncedDate) {
            isSyncedToday = false
            self.syncedDate = nil
        }
    }

    var isClientConfigured: Bool {
        clientId != nil && clientSecret != nil && !(clientId?.isEmpty ?? true) && !(clientSecret?.isEmpty ?? true)
    }

    init() {
        loadAllConfig()
    }

    /// Save Strava API credentials (from debug panel).
    func saveClientConfig(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        saveAllConfig()
    }

    func clearClientConfig() {
        self.clientId = nil
        self.clientSecret = nil
        disconnect()
        saveAllConfig()
    }

    // MARK: - OAuth Flow

    /// Opens the system browser to authorize with Strava.
    func startOAuthFlow() {
        guard isClientConfigured, let clientId = clientId else {
            lastError = "Client ID/Secret not configured — set in debug panel"
            appLog("Strava: credentials not configured — use debug panel")
            return
        }

        // Start callback server
        oauthServer = StravaOAuthServer()
        oauthServer?.start { [weak self] code in
            Task {
                await self?.exchangeCodeForTokens(code: code)
            }
        }

        // Open browser
        let scope = "activity:write"
        let urlString = "\(baseURL)/oauth/authorize?client_id=\(clientId)&response_type=code&redirect_uri=\(redirectURI)&scope=\(scope)&approval_prompt=auto"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            appLog("Strava: opened browser for OAuth")
        }
    }

    /// Exchanges the authorization code for access and refresh tokens.
    private func exchangeCodeForTokens(code: String) async {
        guard let clientId = clientId, let clientSecret = clientSecret else { return }
        let body: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]

        do {
            let result = try await postTokenRequest(body: body)
            await MainActor.run {
                self.accessToken = result.accessToken
                self.refreshToken = result.refreshToken
                self.expiresAt = result.expiresAt
                self.isConnected = true
                self.lastError = nil
                self.saveTokens()
                appLog("Strava: authenticated successfully")
                self.checkUnsyncedDays(notionService: NotionService.shared, force: true)
            }
        } catch {
            await MainActor.run {
                self.lastError = "Auth failed: \(error.localizedDescription)"
                appLog("Strava: token exchange failed: \(error)")
            }
        }
    }

    /// Refreshes the access token if expired.
    func refreshTokenIfNeeded() async {
        guard let expiresAt = expiresAt, let refreshToken = refreshToken else { return }
        guard expiresAt < Date() else { return }
        guard let clientId = clientId, let clientSecret = clientSecret else { return }

        let body: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        do {
            let result = try await postTokenRequest(body: body)
            await MainActor.run {
                self.accessToken = result.accessToken
                self.refreshToken = result.refreshToken
                self.expiresAt = result.expiresAt
                self.saveTokens()
                appLog("Strava: token refreshed")
            }
        } catch {
            await MainActor.run {
                self.lastError = "Token refresh failed"
                self.isConnected = false
                appLog("Strava: refresh failed: \(error)")
            }
        }
    }

    /// Disconnect from Strava — clear tokens and save.
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        isConnected = false
        isSyncedToday = false
        saveAllConfig()
        appLog("Strava: disconnected")
    }

    // MARK: - Post Activity

    private let log = ActivityLog.shared

    /// Posts today's combined walking activity to Strava and records in Notion Day Totals.
    func postTodayActivity(sessions: [SessionSaveData], notionService: NotionService? = nil) async -> Bool {
        guard !sessions.isEmpty else {
            log.info("Strava: no sessions to post")
            return false
        }

        // Check Notion Day Totals for existing post
        if let notion = notionService {
            log.progress("Checking if already posted today")
            if let dayTotal = await notion.fetchDayTotal(for: Date()), dayTotal.stravaPosted {
                log.info("Already posted to Strava today")
                await MainActor.run { isSyncedToday = true; syncedDate = Date() }
                return true
            }
        }

        await MainActor.run {
            isSyncing = true
            lastError = nil
        }

        let distKm = Double(sessions.reduce(0) { $0 + $1.distance }) / 1000.0
        log.progress("Posting \(String(format: "%.1f", distKm))km to Strava (\(sessions.count) sessions)")

        switch await sendWalkActivity(sessions: sessions) {
        case .posted(let activityId):
            log.success("Posted to Strava! Activity ID: \(activityId)")

            // Update Notion Day Totals
            if let notion = notionService {
                log.progress("Saving day totals to Notion")
                let updated = await notion.upsertDayTotal(date: Date(), sessions: sessions, stravaActivityId: activityId)
                log.info("Day totals \(updated ? "saved to Notion" : "failed to save")")
            }

            await MainActor.run {
                isSyncing = false
                isSyncedToday = true
                syncedDate = Date()
                lastStravaSync = Date()
                uploadResultMessage = "Uploaded \(String(format: "%.1f", distKm))km to Strava"
                uploadResultIsError = false
            }
            return true
        case .authError:
            await MainActor.run {
                isSyncing = false
                handleAuthError()
            }
            return false
        case .failed(let reason):
            await MainActor.run {
                isSyncing = false
                lastError = reason
                uploadResultMessage = reason
                uploadResultIsError = true
            }
            return false
        }
    }

    private enum PostOutcome {
        case posted(activityId: String)
        case authError
        case failed(String)
    }

    /// Creates one Strava Walk activity covering the given sessions.
    private func sendWalkActivity(sessions: [SessionSaveData]) async -> PostOutcome {
        log.progress("Refreshing Strava token")
        await refreshTokenIfNeeded()
        guard let token = accessToken else {
            log.error("Not authenticated with Strava")
            return .failed("Not authenticated")
        }

        let totalDistance = sessions.reduce(0) { $0 + $1.distance }
        let totalSteps = sessions.reduce(0) { $0 + $1.steps }
        let totalSeconds = sessions.reduce(0) { $0 + Int($1.endTime.timeIntervalSince($1.startTime)) }
        guard let firstStart = sessions.min(by: { $0.startTime < $1.startTime })?.startTime else {
            log.error("Strava: could not determine session start time")
            return .failed("No valid sessions")
        }
        let distKm = Double(totalDistance) / 1000.0
        let avgSpeed = totalSeconds > 0 ? (distKm / (Double(totalSeconds) / 3600.0)) : 0

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        iso8601.timeZone = TimeZone(identifier: "Africa/Johannesburg")

        let body: [String: Any] = [
            "name": "Walking while working — \(String(format: "%.1f", distKm))km",
            "type": "Walk",
            "sport_type": "Walk",
            "start_date_local": iso8601.string(from: firstStart),
            "elapsed_time": totalSeconds,
            "distance": totalDistance,
            "description": "Walking treadmill: \(sessions.count) walking session(s) · \(totalSteps) steps · avg \(String(format: "%.1f", avgSpeed)) km/h"
        ]

        do {
            var request = URLRequest(url: URL(string: "\(apiURL)/activities")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if statusCode == 201 {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                return .posted(activityId: (json?["id"] as? Int).map { String($0) } ?? "unknown")
            } else if [401, 403].contains(statusCode) {
                log.error("Strava auth error (\(statusCode)) — reconnect needed")
                return .authError
            } else {
                log.error("Strava post failed (\(statusCode))")
                return .failed("Post failed (\(statusCode))")
            }
        } catch {
            log.error("Network error: \(error.localizedDescription)")
            return .failed("Network error")
        }
    }

    /// Strava rejected the token: drop it so the UI offers to reconnect.
    @MainActor
    private func handleAuthError() {
        lastError = "Auth error — reconnect Strava"
        isConnected = false
        uploadResultMessage = "Strava auth error — reconnect needed"
        uploadResultIsError = true
        disconnect()
    }

    /// Re-checks Notion for recent days that never reached Strava. Without `force`
    /// it skips when the last check was today and under `recheckInterval` ago, so it is
    /// cheap to call on every popover open. Call on the main thread.
    func checkUnsyncedDays(notionService: NotionService, force: Bool = false) {
        guard isConnected, notionService.isConfigured, !isCheckingUnsynced else { return }
        let today = NotionService.dayKey(for: Date())
        if !force, lastUnsyncedCheckDay == today,
           let last = lastUnsyncedCheckAt, Date().timeIntervalSince(last) < Self.recheckInterval {
            return
        }

        // Stamped up front so a failing Notion isn't retried on every timer tick.
        isCheckingUnsynced = true
        lastUnsyncedCheckAt = Date()
        lastUnsyncedCheckDay = today
        Task {
            await runUnsyncedCheck(notionService: notionService)
            await MainActor.run { isCheckingUnsynced = false }
        }
    }

    /// Re-checks once the day rolls over, so "yesterday" never means the day before.
    /// Called from the polling timer, on the main thread.
    func checkUnsyncedDaysIfDayChanged(notionService: NotionService) {
        guard let last = lastUnsyncedCheckDay, last != NotionService.dayKey(for: Date()) else { return }
        checkUnsyncedDays(notionService: notionService, force: true)
    }

    private func runUnsyncedCheck(notionService: NotionService) async {
        let now = Date()
        let calendar = NotionService.dayCalendar
        guard let start = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return }

        // Two range queries cover the whole lookback; posted days include today.
        async let sessionsQuery = notionService.fetchSessionsByDay(from: start, to: yesterday)
        async let postedQuery = notionService.fetchStravaPostedDays(from: start, to: now)
        async let lastSyncQuery = notionService.fetchLastStravaSync()
        guard let byDay = await sessionsQuery, let posted = await postedQuery else {
            appLog("Strava: couldn't check Notion for missed days")
            return
        }
        let lastSync = await lastSyncQuery

        let todayKey = NotionService.dayKey(for: now)
        let missed = byDay.compactMap { key, sessions -> UnsyncedDay? in
            let distance = sessions.reduce(0) { $0 + $1.distance }
            guard key != todayKey, !posted.contains(key), distance > 0,
                  let date = NotionService.date(forDayKey: key) else { return nil }
            return UnsyncedDay(key: key, date: date, sessionCount: sessions.count, distance: distance)
        }.sorted { $0.key > $1.key }

        await MainActor.run {
            if let lastSync = lastSync { lastStravaSync = lastSync }
            if posted.contains(todayKey) {
                isSyncedToday = true
                syncedDate = now
            }
            unsyncedDays = missed
            let keys = Set(missed.map(\.key))
            dayPostErrors = dayPostErrors.filter { keys.contains($0.key) }
        }
        if !missed.isEmpty {
            appLog("Strava: \(missed.count) recent day(s) not on Strava: \(missed.map(\.key).joined(separator: ", "))")
        }
    }

    /// Posts one past day's walks to Strava as a single activity and records it in
    /// Notion Day Totals.
    func postDay(_ day: UnsyncedDay, notionService: NotionService) async -> Bool {
        let claimed = await MainActor.run { () -> Bool in
            guard !postingDays.contains(day.key) else { return false }
            postingDays.insert(day.key)
            dayPostErrors[day.key] = nil
            return true
        }
        guard claimed else { return false }

        // Re-read the day: the check may be minutes old.
        guard let sessions = await notionService.fetchSessions(for: day.date), !sessions.isEmpty else {
            log.error("No sessions found for \(day.key)")
            await finishPostingDay(day.key, error: "No walks found")
            return false
        }
        if let dayTotal = await notionService.fetchDayTotal(for: day.date), dayTotal.stravaPosted {
            log.info("\(day.key) already posted to Strava")
            await finishPostingDay(day.key, posted: true)
            return true
        }

        let distKm = Double(sessions.reduce(0) { $0 + $1.distance }) / 1000.0
        log.progress("Posting \(day.key)'s \(String(format: "%.1f", distKm))km to Strava (\(sessions.count) sessions)")

        switch await sendWalkActivity(sessions: sessions) {
        case .posted(let activityId):
            log.success("Posted \(day.key) to Strava! Activity ID: \(activityId)")
            log.progress("Saving day totals to Notion")
            let updated = await notionService.upsertDayTotal(date: day.date, sessions: sessions, stravaActivityId: activityId)
            log.info("Day totals \(updated ? "saved to Notion" : "failed to save")")
            await MainActor.run {
                lastStravaSync = Date()
                uploadResultMessage = "Uploaded \(day.key)'s \(String(format: "%.1f", distKm))km to Strava"
                uploadResultIsError = false
            }
            await finishPostingDay(day.key, posted: true)
            return true
        case .authError:
            await MainActor.run { handleAuthError() }
            await finishPostingDay(day.key, error: "Reconnect Strava")
            return false
        case .failed(let reason):
            await MainActor.run {
                uploadResultMessage = reason
                uploadResultIsError = true
            }
            await finishPostingDay(day.key, error: reason)
            return false
        }
    }

    @MainActor
    private func finishPostingDay(_ key: String, posted: Bool = false, error: String? = nil) {
        postingDays.remove(key)
        if posted { unsyncedDays.removeAll { $0.key == key } }
        dayPostErrors[key] = error
    }

    /// Clears the upload result message.
    func clearUploadResult() {
        uploadResultMessage = nil
    }

    // MARK: - Token Request Helper

    private struct TokenResult {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    private func postTokenRequest(body: [String: String]) async throws -> TokenResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "Strava", code: statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresAtEpoch = json["expires_at"] as? Int else {
            throw NSError(domain: "Strava", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        return TokenResult(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: Double(expiresAtEpoch))
        )
    }

    // MARK: - Config Persistence (JSON file — no Keychain prompts)

    private func saveAllConfig() {
        let config = StravaConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt?.timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(config) {
            FileSystem().save(filename: configFilename, data: data)
        }
    }

    private func loadAllConfig() {
        guard let data = FileSystem().load(filename: configFilename),
              let config = try? JSONDecoder().decode(StravaConfig.self, from: data) else {
            return
        }
        clientId = config.clientId
        clientSecret = config.clientSecret
        accessToken = config.accessToken
        refreshToken = config.refreshToken
        if let exp = config.expiresAt {
            expiresAt = Date(timeIntervalSince1970: exp)
        }
        isConnected = accessToken != nil && refreshToken != nil
    }

    private func saveTokens() {
        saveAllConfig()
    }
}
