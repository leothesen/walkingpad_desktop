# WalkingPad Desktop

A native macOS menu-bar app for controlling and monitoring [WalkingPad](https://www.walkingpad.com/) treadmills over Bluetooth. Forked from [klassm/walkingpad_macos_client](https://github.com/klassm/walkingpad_macos_client) and significantly extended with Notion sync, Strava integration, a redesigned stats dashboard, and macOS 26 Liquid Glass UI.

## What's Changed from the Original

The original app provided basic BLE treadmill control and step tracking. This fork adds:

- **Notion as source of truth** — all session data synced to a Notion database, replacing local-only storage
- **Strava integration** — post daily walking summaries to Strava via OAuth2
- **Redesigned stats dashboard** — SwiftUI Charts with distance trends, activity heatmap, and session breakdowns
- **Session-level tracking** — individual sessions with start/end times, not just daily totals
- **macOS 26 Liquid Glass UI** — frosted glass effects throughout the menu bar popover. See [Design System](docs/DESIGN_SYSTEM.md).
- **Interactive Prototype** — explore the UI design in [prototype/index.html](prototype/index.html).
- **Live status bar** — shows current session distance + time while walking, today's total when idle
- **Speed slider** — replaced the 4x4 button grid with a slider + fine-tune +/- buttons
- **60-minute notification** — macOS notification + auto speed reduction after 1 hour of continuous walking
- **Stop & Finish Day** — one-tap button to stop the treadmill and post to Strava with confirmation
- **Debug panel** — BLE console, raw data viewer, Notion/Strava config, activity log
- **Removed legacy integrations** — Google Fit/HCGateway, Netlify stats app, OAuth2 framework dependency

## 🚀 Key User Stories
We focus on an unobtrusive, high-performance experience for power users.
- **US02: Stats Overlay** — Semi-transparent, floating metrics window for focus.
- **US11: Bypass Novice Guide** — Skip mandatory device tutorials for immediate full-speed access.
See [User Stories](docs/USER_STORIES.md) for the full roadmap.

## Features

- **Bluetooth connection** — automatically discovers and connects to your WalkingPad
- **Speed control** — slider with +/- fine-tune buttons (0.1 km/h increments), manual/auto mode toggle
- **Session tracking** — per-session distance, steps, duration, synced to Notion
- **Notion sync** — sessions and daily totals stored in Notion databases
- **Strava posting** — daily combined Walk activity with distance, steps, duration, avg speed
- **Stats dashboard** — distance trend chart, session count, consistency streak, interactive hover
- **MQTT publishing** — treadmill state for Home Assistant
- **Local HTTP API** — REST endpoints on port 4934 for Alfred workflows
- **60-min alert** — notification + speed reduction after 1 hour of walking

## Screenshots

![Tray App](docs/tray_app.png)
![Stats](docs/stats.png)

## Requirements

- **macOS 26** (Tahoe) or later — required for Liquid Glass SwiftUI APIs
- **Xcode 16.3+** with macOS 26 SDK
- A WalkingPad treadmill with Bluetooth

## Installation

### From Releases

Download the latest `.zip` from the [releases section](https://github.com/leothesen/walkingpad_desktop/releases), unzip, and drag to Applications.

On first launch: **System Settings → Privacy & Security → "Open Anyway"** (the app is not notarized).

Grant Bluetooth permissions when prompted.

### Building from Source

1. Clone the repo
2. Open `walkingpad-client.xcodeproj` in Xcode
3. Dependencies resolve automatically via Swift Package Manager
4. **Cmd+R** to build and run (appears in menu bar, not Dock)

## Setup Guide

### 1. Basic Usage (no setup needed)

The app connects to your WalkingPad automatically via Bluetooth. Use the menu bar dropdown to control speed and view session stats.

### 2. Notion Integration (recommended)

Notion stores all session data and daily totals. Without it, stats are local-only.

1. Create a [Notion internal integration](https://www.notion.so/my-integrations) with read/write permissions
2. Create a Notion page (e.g., "WalkingPad") and share it with your integration
3. Create two inline databases on that page:
   - **Sessions** — columns: Session (title), Date (date), Start Time (text), End Time (text), Duration (min) (number), Steps (number), Distance (m) (number)
   - **Day totals** — columns: Day (title), Date (date), Total Distance (m) (number), Total Steps (number), Total Duration (min) (number), Sessions (number), Strava Posted At (text), Strava Activity ID (text)
4. Add formula columns if desired: Distance (km), Avg Speed (km/h), Day of Week
5. In the app: click **Stats → ladybug icon → Notion tab** → paste your API key and database ID → Save

> **Tip**: If you have [Claude Code](https://claude.ai/claude-code) with the Notion MCP server configured, you can ask Claude to set up the databases and columns for you automatically.

### 3. Strava Integration (optional)

Post daily walking summaries to Strava as Walk activities.

1. Register an API application at [strava.com/settings/api](https://www.strava.com/settings/api)
2. Set the redirect URI to `http://localhost:8234/callback`
3. In the app: click **Stats → ladybug icon → Strava tab** → paste Client ID and Client Secret → Save
4. Click **Connect to Strava** → authorize in browser → done
5. Use the upload icon in the footer (or "Stop & Finish Day") to post

### 4. MQTT (optional)

For Home Assistant integration, create a config file at:
```
~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information/.walkingpad-client-mqtt.json
```

```json
{
  "username": "myusername",
  "password": "mypassword",
  "host": "192.168.0.73",
  "port": 1883,
  "topic": "homeassistant/sensor/walkingpad"
}
```

## HTTP API (Port 4934)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/treadmill` | Current state: steps, distance, walkingSeconds, speed |
| GET | `/treadmill/workouts` | Historical workout data |
| POST | `/treadmill/start` | Start the treadmill |
| POST | `/treadmill/stop` | Stop (speed to 0) |
| POST | `/treadmill/faster` | +0.5 km/h |
| POST | `/treadmill/slower` | -0.5 km/h |
| POST | `/treadmill/speed/{10-80}` | Set speed (multiples of 10) |

## Creating a Release

### Build the app bundle

From the project root, run:

```bash
# Build in Release mode with ad-hoc signing
xcodebuild -scheme walkingpad-client \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-"

# Zip the .app bundle
cd build/Build/Products/Release
zip -r ../../../../WalkingPad-Client.zip "Walkingpad Client.app"
cd ../../../..
```

This produces `WalkingPad-Client.zip` in the project root containing the standalone `.app` bundle.

> **Important**: Zip the `.app`, not the `.xcarchive`. The `.app` is a double-clickable application. An `.xcarchive` will open in Xcode instead.

### Publish to GitHub

1. Go to your repo → **Releases** → **Create a new release**
2. Create a new tag (e.g., `v0.1.0`)
3. Write release notes (or use "Generate release notes")
4. Drag `WalkingPad-Client.zip` into the assets area
5. Publish

### Installing from a release

1. Download `WalkingPad-Client.zip` from the release
2. Unzip — you'll get `Walkingpad Client.app`
3. Drag to `/Applications` (optional, can run from anywhere)
4. Double-click to open
5. On first launch: **System Settings → Privacy & Security → "Open Anyway"** (the app is ad-hoc signed, not notarized)

## Project Structure

```
walkingpad-client/
├── walkingpad_clientApp.swift       # App entry point + AppDelegate
├── models/                          # Data types
│   ├── DeviceState.swift            # BLE state snapshot
│   └── WorkoutsSaveData.swift       # Persistence models + SessionSaveData
├── services/
│   ├── walkingPad/
│   │   ├── WalkingPadService.swift  # BLE state + notification parsing
│   │   └── WalkingPadCommand.swift  # BLE write commands
│   ├── BluetoothDiscoveryService.swift
│   ├── BluetoothPeripheral.swift
│   ├── Workout.swift                # Session tracking + daily accumulation
│   ├── NotionService.swift          # Notion API client + Day Totals
│   ├── StravaService.swift          # Strava OAuth + activity posting
│   ├── StravaOAuthServer.swift      # Temporary OAuth callback server
│   ├── ActivityLog.swift            # Shared log for sync operations
│   ├── HttpApi.swift                # Local HTTP server (port 4934)
│   ├── MqttService.swift            # MQTT publishing
│   ├── FileSystem.swift             # JSON file persistence
│   └── RepeatingTimer.swift         # Polling timer
├── viewmodels/
│   └── StatsViewModel.swift         # Stats computation + filtering
├── views/
│   ├── ContentView.swift            # Root popover view
│   ├── DeviceView.swift             # Connected device routing
│   ├── RunningView.swift            # Speed slider + controls
│   ├── StoppedOrPauseView.swift     # Start button
│   ├── WorkoutStateView.swift       # Session distance/steps/time
│   ├── FooterView.swift             # Stats, Strava, Quit buttons
│   ├── WaitingForTreadmillView.swift
│   ├── EmptyView.swift
│   └── stats/
│       ├── StatsWindowView.swift    # Stats dashboard layout
│       ├── DailyDistanceChart.swift # Bar chart
│       ├── ActivityHeatmap.swift    # Consistency streak
│       ├── DebugView.swift          # Debug panel tabs
│       └── ActivityLogTabView.swift # Live activity log
└── utils/
    └── DateExtension.swift
```

## Credits

This project is a fork of [klassm/walkingpad_macos_client](https://github.com/klassm/walkingpad_macos_client) by Matthias Klass, which provided the original BLE protocol implementation and app structure. The BLE protocol is based on [ph4r05/ph4-walkingpad](https://github.com/ph4r05/ph4-walkingpad).

## License

[Apache License 2.0](LICENSE)
