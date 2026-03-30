# Architecture — WalkingPad Desktop

## Overview

WalkingPad Desktop is a native macOS 26 menu-bar app that communicates with KingSmith WalkingPad treadmills over Bluetooth Low Energy. It provides speed control, session tracking, Notion sync, Strava integration, and a stats dashboard with Liquid Glass UI.

## System Architecture

```
┌──────────────────────────────────────────────────┐
│                   SwiftUI Views                  │
│                                                  │
│  ContentView → DeviceView → RunningView          │
│                            → StoppedOrPausedView │
│  FooterView (Stats, Strava, Quit)                │
│  StatsWindowView (floating window)               │
│  DebugView (Log, Raw Data, BLE, Notion, Strava)  │
└──────────────────┬───────────────────────────────┘
                   │ @EnvironmentObject
┌──────────────────▼───────────────────────────────┐
│           ObservableObject Services               │
│                                                   │
│  WalkingPadService  — BLE state + parsing         │
│  Workout            — session tracking            │
│  NotionService      — Notion API client           │
│  StravaService      — Strava OAuth + posting      │
│  ActivityLog        — shared sync log             │
└──────┬───────────────────┬───────────────────────┘
       │                   │
┌──────▼──────┐  ┌─────────▼───────────────────────┐
│  BLE Stack  │  │     External Services             │
│             │  │                                   │
│ Discovery   │  │  Notion API (sessions + totals)   │
│ Peripheral  │  │  Strava API (Walk activities)     │
│ Command     │  │  MQTT broker (Home Assistant)     │
│ Service     │  │  HTTP API port 4934 (Alfred)      │
└─────────────┘  └───────────────────────────────────┘
```

## Data Flow

### BLE → Session → Notion

```
BLE Notify (FE01, every ~4s)
  → WalkingPadService.peripheral(didUpdateValueFor:)
    → Parse binary → DeviceState
    → Fire callback(oldState, newState)
      → Workout.update()
        → Accumulate steps/distance diffs
        → Session detection:
            Speed 0→>0 = session start
            3 consecutive zero-step updates = session end (idle detection)
        → On session end:
            → Save SessionSaveData locally
            → NotionService.pushSession() → POST /v1/pages
            → Clear local workouts.json
            → Fetch today's total for status bar
```

### Stats Window

```
Click Stats → FooterView.openStatsWindow()
  → NotionService.fetchAllSessions() (paginated)
  → Group by date → [WorkoutSaveData]
  → StatsViewModel (computed stats, filtering, chart data)
  → StatsWindowView renders
```

### Strava Post

```
Click "Stop & Finish Day" or upload icon
  → NotionService.fetchTodaySessions()
  → Check Day Totals for existing Strava post
  → StravaService.postTodayActivity()
    → Refresh token if expired
    → POST /api/v3/activities (Walk)
    → NotionService.upsertDayTotal() with Strava activity ID
```

## Session Detection

The WalkingPad doesn't reliably report `speed=0` when the belt stops. Session boundaries are detected by:

1. **Start**: `oldState.speed == 0 && newState.speed > 0`, OR steps flowing with no active session
2. **End**: 3 consecutive BLE updates (~12 seconds) with zero step diffs while a session is active

## Notion Databases

### Sessions
Each walking session is a row: title, date, start/end times, duration, steps, distance.

### Day Totals
One row per day: aggregated distance/steps/duration/sessions, plus Strava sync status (posted timestamp + activity ID).

## Strava OAuth Flow

1. Open system browser → `strava.com/oauth/authorize`
2. Temporary Embassy server on port 8234 catches redirect callback
3. Exchange auth code for access + refresh tokens
4. Tokens stored in `.walkingpad-client-strava.json`
5. Auto-refresh on expiry before API calls

## Status Bar

- **Walking**: `0.45 km · 3:24` (current session distance + elapsed time, no icon)
- **Idle with activity**: treadmill icon + `0.45 km` (today's total from Notion)
- **No activity**: treadmill icon only

## Threading Model

| Component | Thread |
|-----------|--------|
| CoreBluetooth callbacks | Main (queue: nil) |
| @Published mutations | Deferred via DispatchQueue.main.async |
| HTTP server (Embassy) | Dedicated background thread |
| MQTT (NIO event loop) | Dedicated NIO thread |
| Notion/Strava API calls | Swift async/await |
| Timer callbacks | Main RunLoop |

## Config Persistence

All config stored as JSON files in `~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information/` — no Keychain access, no password prompts.
