import Foundation
import AppKit

/// Strava integration: OAuth2 authentication, daily activity posting, sync state tracking.
class StravaService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isSyncedToday: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastError: String? = nil

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
            print("Strava: credentials not configured — use debug panel")
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
            print("Strava: opened browser for OAuth")
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
                print("Strava: authenticated successfully")
            }
        } catch {
            await MainActor.run {
                self.lastError = "Auth failed: \(error.localizedDescription)"
                print("Strava: token exchange failed: \(error)")
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
                print("Strava: token refreshed")
            }
        } catch {
            await MainActor.run {
                self.lastError = "Token refresh failed"
                self.isConnected = false
                print("Strava: refresh failed: \(error)")
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
        print("Strava: disconnected")
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
            log.progress("Checking if already posted today…")
            if let dayTotal = await notion.fetchDayTotal(for: Date()), dayTotal.stravaPosted {
                log.info("Already posted to Strava today")
                await MainActor.run { isSyncedToday = true }
                return true
            }
        }

        await MainActor.run {
            isSyncing = true
            lastError = nil
        }

        log.progress("Refreshing Strava token…")
        await refreshTokenIfNeeded()
        guard let token = accessToken else {
            log.error("Not authenticated with Strava")
            await MainActor.run { isSyncing = false; lastError = "Not authenticated" }
            return false
        }

        let totalDistance = sessions.reduce(0) { $0 + $1.distance }
        let totalSteps = sessions.reduce(0) { $0 + $1.steps }
        let totalSeconds = sessions.reduce(0) { $0 + Int($1.endTime.timeIntervalSince($1.startTime)) }
        let firstStart = sessions.min(by: { $0.startTime < $1.startTime })!.startTime
        let distKm = Double(totalDistance) / 1000.0
        let avgSpeed = totalSeconds > 0 ? (distKm / (Double(totalSeconds) / 3600.0)) : 0

        log.progress("Posting \(String(format: "%.1f", distKm))km to Strava (\(sessions.count) sessions)…")

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]

        let body: [String: Any] = [
            "name": "Walking while working — \(String(format: "%.1f", distKm))km",
            "type": "Walk",
            "sport_type": "Walk",
            "start_date_local": iso8601.string(from: firstStart),
            "elapsed_time": totalSeconds,
            "distance": totalDistance,
            "steps": totalSteps,
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
                let activityId = (json?["id"] as? Int).map { String($0) } ?? "unknown"

                log.success("Posted to Strava! Activity ID: \(activityId)")

                // Update Notion Day Totals
                if let notion = notionService {
                    log.progress("Saving day totals to Notion…")
                    let updated = await notion.upsertDayTotal(date: Date(), sessions: sessions, stravaActivityId: activityId)
                    log.info("Day totals \(updated ? "saved to Notion" : "failed to save")")
                }

                await MainActor.run {
                    isSyncing = false
                    isSyncedToday = true
                }
                return true
            } else if [401, 403].contains(statusCode) {
                log.error("Strava auth error (\(statusCode)) — reconnect needed")
                await MainActor.run {
                    isSyncing = false
                    lastError = "Auth error — reconnect Strava"
                    isConnected = false
                    disconnect()
                }
                return false
            } else {
                log.error("Strava post failed (\(statusCode))")
                await MainActor.run {
                    isSyncing = false
                    lastError = "Post failed (\(statusCode))"
                }
                return false
            }
        } catch {
            log.error("Network error: \(error.localizedDescription)")
            await MainActor.run {
                isSyncing = false
                lastError = "Network error"
            }
            return false
        }
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
