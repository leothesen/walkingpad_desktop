# CLAUDE.md — WalkingPad Desktop

## Project Overview

Native macOS menu-bar app for controlling WalkingPad treadmills over Bluetooth Low Energy. Syncs session data to Notion and posts daily summaries to Strava. Auto-updates via Sparkle.

## Build & Run

- **IDE**: Xcode 26+ (macOS 26 SDK)
- **Language**: Swift 5
- **Platform**: macOS 26+ (menu bar app, `LSUIElement = true`), Liquid Glass UI
- **Dependencies**: Swift Package Manager (embedded in Xcode)
- **Build**: Cmd+B or `xcodebuild -scheme walkingpad-client`
- **Run**: Cmd+R (appears in menu bar, not Dock)
- **Session tracker checks**: `swiftc walkingpad-client/services/SessionTracker.swift Tests/SessionTrackerChecks/main.swift -o /tmp/checks && /tmp/checks` (also run in CI)
- **Release**: Push a git tag (`git tag v1.0.0 && git push origin v1.0.0`) — GitHub Actions builds, signs, creates release, updates appcast

## Architecture

```
BLE Notify (FE01) → WalkingPadService → callback → Workout
                                                      ├── SessionTracker (time-based start/pause/end)
                                                      ├── NotionService (push sessions)
                                                      ├── MqttService (Home Assistant)
                                                      └── Status bar update

Stats window → NotionService.fetchAllSessions() → StatsViewModel → Charts
Strava post  → NotionService.fetchTodaySessions() → StravaService → Strava API
```

- **Entry point**: `walkingpad_clientApp.swift` — `MenuBarPopoverApp` + `AppDelegate`
- **Services**: All business logic in `services/`
- **Views**: SwiftUI in `views/`, environment objects for Workout + WalkingPadService
- **Config storage**: JSON files in `~/Library/Application Support/walkingpad-client/` (legacy `Autosave Information` locations are migrated on first access)
- **Notion**: Source of truth for sessions and daily totals
- **Strava**: One-way push of daily Walk activities via OAuth2

## Key Files

| File | Purpose |
|------|---------|
| `walkingpad_clientApp.swift` | App entry, service wiring, sleep/wake |
| `WalkingPadService.swift` | BLE notification parsing, debug log buffer |
| `WalkingPadCommand.swift` | BLE write commands with checksum |
| `BluetoothDiscoveryService.swift` | Device scanning, connection, reconnect |
| `Workout.swift` | Step accumulation, session lifecycle via `SessionTracker`, 60-min notification |
| `SessionTracker.swift` | Pure, time-based session state machine (walking / paused / stopping); no UI deps |
| `GoalSettings.swift` | Daily goal (distance / steps / time) in UserDefaults |
| `StatusBarIcon.swift` | Menu bar goal ring glyph (template image) |
| `NotionService.swift` | Notion API — sessions, day totals, config via JSON file |
| `StravaService.swift` | OAuth2, token refresh, activity posting, config via JSON file |
| `StravaOAuthServer.swift` | Temporary Embassy server on port 8234 for OAuth redirect |
| `ActivityLog.swift` | Shared observable log for sync operations |
| `StatsViewModel.swift` | Computed stats, filtering, trend data |
| `HttpApi.swift` | Local HTTP server on port 4934 (Embassy) |
| `MqttService.swift` | MQTT publishing via mqtt-nio |

## BLE Protocol

- Service UUIDs: `0000180a-...`, `00010203-...`, `0000fe00-...`
- Notify: `FE01` (status updates), Command: `FE02` (write)
- Command format: `[0xF7, 0xA2, cmd, param, checksum, 0xFD]`
- Status: 14+ bytes — speed (byte 3), mode (4), time (5-7), distance (8-10), steps (11-13)
- Only `0xF8 0xA2` (current status) frames drive state; `0xF8 0xA7` (last session summary) frames are logged and ignored
- Session detection is time-based (`SessionTracker`): no steps for 10s or a speed-0 frame → paused; no steps for 60s → ended (end time = last step); after Stop, ends on speed 0 or 5s without steps

## Config Files (in `~/Library/Application Support/walkingpad-client/`)

| File | Purpose |
|------|---------|
| `.walkingpad-client-notion.json` | Notion API key + database ID |
| `.walkingpad-client-strava.json` | Strava client ID/secret + OAuth tokens |
| `.walkingpad-client-mqtt.json` | MQTT broker connection config |
| `workouts.json` | Local workout fallback (cleared on Notion push) |

## Dependencies

| Package | Purpose |
|---------|---------|
| Embassy 4.1.6 | Embedded HTTP server (kqueue-based) |
| mqtt-nio 2.8.1 | MQTT 3.1.1 client for Home Assistant |
| swift-nio 2.84.0 | Network I/O (mqtt-nio dependency) |
| Sparkle 2.x | Auto-update framework (EdDSA signed, appcast on main branch) |

## Known Gotchas

- `NSApp.delegate as? AppDelegate` cast fails from SwiftUI views — use the shared singletons (`NotionService.shared`, `StravaService.shared`) instead
- The WalkingPad doesn't report speed=0 when belt stops — session end uses idle detection instead
- `~/Library/Autosave Information` is behind macOS privacy protection (TCC) on recent macOS — non-sandboxed reads/writes fail with EPERM "Operation not permitted". App data lives in `~/Library/Application Support/walkingpad-client/`; `FileSystem` migrates from legacy locations best-effort
- `NSHostingView` in `NSWindow` crashes with infinite constraint loops if SwiftUI content changes size during animations — avoid `.transition()` and broad `.animation()` modifiers in the stats window; use `.frame(minHeight:)` to stabilize layout
- CI and release run on GitHub's `macos-26` runner with Xcode 26.6, so Liquid Glass APIs (`.glassEffect`, `.buttonStyle(.glass/.glassProminent)`) are available; deployment target is macOS 26
- Picker binding to `@Published` property causes "Publishing changes from within view updates" — use local `@State` for Picker, sync to view model via `DispatchQueue.main.async` in `.onChange`
- All logging uses `appLog()` (global function in ActivityLog.swift) which routes to both console and the debug panel's Log tab
- Never count BLE frames as a proxy for time: the treadmill replies to most commands with an extra status frame, so frame bursts arrive after speed changes. Session rules are wall-clock based (see `SessionTracker`)
- Use semantic colors (`.primary`, `.secondary`, system `.green`/`.orange`) and glass/materials so the UI follows the system light/dark appearance
- Strava API does not support a `steps` field on activity creation — steps only appear in the description text
- Sparkle EdDSA private key is in GitHub secret `SPARKLE_PRIVATE_KEY`; public key is in Info.plist `SUPublicEDKey`
