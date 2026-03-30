import Foundation
import AppKit
import Security

/// Strava integration: OAuth2 authentication, daily activity posting, sync state tracking.
class StravaService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isSyncedToday: Bool = false
    @Published var isSyncing: Bool = false
    @Published var lastError: String? = nil

    // Loaded from Keychain — configured via debug panel
    private var clientId: String?
    private var clientSecret: String?

    private let baseURL = "https://www.strava.com"
    private let apiURL = "https://www.strava.com/api/v3"
    private let redirectURI = "http://localhost:8234/callback"
    private let keychainService = "com.walkingpad.strava"
    private let syncedDatesKey = "stravaSyncedDates"

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var oauthServer: StravaOAuthServer?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var isClientConfigured: Bool {
        clientId != nil && clientSecret != nil && !(clientId?.isEmpty ?? true) && !(clientSecret?.isEmpty ?? true)
    }

    init() {
        clientId = loadKeychain(key: "clientId")
        clientSecret = loadKeychain(key: "clientSecret")
        loadTokens()
        isSyncedToday = isDaySynced(Date())
    }

    /// Save Strava API credentials (from debug panel).
    func saveClientConfig(clientId: String, clientSecret: String) {
        saveKeychain(key: "clientId", value: clientId)
        saveKeychain(key: "clientSecret", value: clientSecret)
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    func clearClientConfig() {
        deleteKeychain(key: "clientId")
        deleteKeychain(key: "clientSecret")
        self.clientId = nil
        self.clientSecret = nil
        disconnect()
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

    /// Disconnect from Strava — clear all tokens.
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        isConnected = false
        isSyncedToday = false
        deleteKeychain(key: "accessToken")
        deleteKeychain(key: "refreshToken")
        deleteKeychain(key: "expiresAt")
        print("Strava: disconnected")
    }

    // MARK: - Post Activity

    /// Posts today's combined walking activity to Strava.
    func postTodayActivity(sessions: [SessionSaveData]) async -> Bool {
        guard !sessions.isEmpty else {
            print("Strava: no sessions to post")
            return false
        }
        guard !isDaySynced(Date()) else {
            print("Strava: already synced today")
            await MainActor.run { isSyncedToday = true }
            return true
        }

        await MainActor.run {
            isSyncing = true
            lastError = nil
        }

        await refreshTokenIfNeeded()
        guard let token = accessToken else {
            await MainActor.run {
                isSyncing = false
                lastError = "Not authenticated"
            }
            return false
        }

        let totalDistance = sessions.reduce(0) { $0 + $1.distance }
        let totalSteps = sessions.reduce(0) { $0 + $1.steps }
        let totalSeconds = sessions.reduce(0) { $0 + Int($1.endTime.timeIntervalSince($1.startTime)) }
        let firstStart = sessions.min(by: { $0.startTime < $1.startTime })!.startTime
        let distKm = Double(totalDistance) / 1000.0
        let avgSpeed = totalSeconds > 0 ? (distKm / (Double(totalSeconds) / 3600.0)) : 0

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]

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
                print("Strava: activity posted successfully")
                markDaySynced(Date())
                await MainActor.run {
                    isSyncing = false
                    isSyncedToday = true
                }
                return true
            } else if [401, 403].contains(statusCode) {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                print("Strava: auth error \(statusCode): \(responseBody)")
                await MainActor.run {
                    isSyncing = false
                    lastError = "Auth error — reconnect Strava"
                    isConnected = false
                    disconnect()
                }
                return false
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                print("Strava: post failed \(statusCode): \(responseBody)")
                await MainActor.run {
                    isSyncing = false
                    lastError = "Post failed (\(statusCode))"
                }
                return false
            }
        } catch {
            print("Strava: post error: \(error)")
            await MainActor.run {
                isSyncing = false
                lastError = "Network error"
            }
            return false
        }
    }

    // MARK: - Sync Tracking

    func isDaySynced(_ date: Date) -> Bool {
        let dateStr = Self.dateFormatter.string(from: date)
        let synced = UserDefaults.standard.stringArray(forKey: syncedDatesKey) ?? []
        return synced.contains(dateStr)
    }

    func markDaySynced(_ date: Date) {
        let dateStr = Self.dateFormatter.string(from: date)
        var synced = UserDefaults.standard.stringArray(forKey: syncedDatesKey) ?? []
        if !synced.contains(dateStr) {
            synced.append(dateStr)
            // Keep last 90 days only
            if synced.count > 90 { synced = Array(synced.suffix(90)) }
            UserDefaults.standard.set(synced, forKey: syncedDatesKey)
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

    // MARK: - Keychain

    private func saveTokens() {
        if let t = accessToken { saveKeychain(key: "accessToken", value: t) }
        if let t = refreshToken { saveKeychain(key: "refreshToken", value: t) }
        if let e = expiresAt {
            saveKeychain(key: "expiresAt", value: String(e.timeIntervalSince1970))
        }
    }

    private func loadTokens() {
        accessToken = loadKeychain(key: "accessToken")
        refreshToken = loadKeychain(key: "refreshToken")
        if let expiresStr = loadKeychain(key: "expiresAt"), let interval = Double(expiresStr) {
            expiresAt = Date(timeIntervalSince1970: interval)
        }
        isConnected = accessToken != nil && refreshToken != nil
    }

    private func saveKeychain(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
