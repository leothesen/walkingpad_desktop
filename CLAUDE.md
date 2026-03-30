# CLAUDE.md — WalkingPad Desktop

## Project Overview

Native macOS 26 menu-bar app for controlling WalkingPad treadmills over Bluetooth Low Energy. Syncs session data to Notion and posts daily summaries to Strava. Uses SwiftUI with Liquid Glass effects.

## Build & Run

- **IDE**: Xcode 16.3+ with macOS 26 SDK
- **Language**: Swift 5
- **Platform**: macOS 26+ (menu bar app, `LSUIElement = true`)
- **Dependencies**: Swift Package Manager (embedded in Xcode)
- **Build**: Cmd+B or `xcodebuild -scheme walkingpad-client`
- **Run**: Cmd+R (appears in menu bar, not Dock)
- **Release**: Product → Archive → Distribute App → Copy App → zip → upload to GitHub Releases

## Architecture

```
BLE Notify (FE01) → WalkingPadService → callback → Workout
                                                      ├── Session tracking (start/stop/idle detection)
                                                      ├── NotionService (push sessions)
                                                      ├── MqttService (Home Assistant)
                                                      └── Status bar update

Stats window → NotionService.fetchAllSessions() → StatsViewModel → Charts
Strava post  → NotionService.fetchTodaySessions() → StravaService → Strava API
```

- **Entry point**: `walkingpad_clientApp.swift` — `MenuBarPopoverApp` + `AppDelegate`
- **Services**: All business logic in `services/`
- **Views**: SwiftUI in `views/`, environment objects for Workout + WalkingPadService
- **Config storage**: JSON files in `~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information/`
- **Notion**: Source of truth for sessions and daily totals
- **Strava**: One-way push of daily Walk activities via OAuth2

## Key Files

| File | Purpose |
|------|---------|
| `walkingpad_clientApp.swift` | App entry, service wiring, sleep/wake, auto-post timer |
| `WalkingPadService.swift` | BLE notification parsing, debug log buffer |
| `WalkingPadCommand.swift` | BLE write commands with checksum |
| `BluetoothDiscoveryService.swift` | Device scanning, connection, reconnect |
| `Workout.swift` | Session detection (idle-based), step accumulation, 60-min notification |
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
- Session detection: idle-based (3 consecutive zero-step updates) since the WalkingPad doesn't reliably report speed=0

## Config Files (in Autosave Information directory)

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

## Known Gotchas

- `RepeatingTimer` ignores its `interval` parameter and hardcodes 4 seconds
- `EmptyView.swift` shadows SwiftUI's built-in `EmptyView`
- `exit(0)` in FooterView bypasses cleanup
- Date rollover check only compares day-of-month, not full date
- `NSApp.delegate as? AppDelegate` cast fails from SwiftUI views — use cached standalone service instances
- The WalkingPad doesn't report speed=0 when belt stops — session end uses idle detection instead
