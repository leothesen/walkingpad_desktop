# Architecture — WalkingPad Desktop

## Overview

WalkingPad Desktop is a native macOS menu-bar application that communicates with KingSmith WalkingPad treadmills over Bluetooth Low Energy. It provides real-time speed control, step tracking, MQTT publishing for home automation, and health data sync via the HCGateway bridge service.

## System Architecture

```
┌──────────────────────────────────────────────────┐
│                   SwiftUI Views                  │
│                                                  │
│  ContentView ─┬─ DeviceView ─┬─ RunningView     │
│               │              └─ StoppedOrPaused  │
│               └─ WaitingForTreadmillView         │
│  FooterView ── LoginLogoutButton                 │
│  WorkoutStateView                                │
└──────────────────┬───────────────────────────────┘
                   │ @EnvironmentObject
┌──────────────────▼───────────────────────────────┐
│           ObservableObject Services               │
│                                                   │
│  WalkingPadService    — BLE state + parsing       │
│  Workout              — step accumulation         │
│  HCGatewayService     — auth + upload orchestrate │
└──────┬───────────────────┬───────────────────────┘
       │                   │
┌──────▼──────┐  ┌─────────▼───────────────────────┐
│  BLE Stack  │  │     Side-Effect Services         │
│             │  │                                   │
│ Discovery   │  │  MqttService      (mqtt-nio)     │
│ Peripheral  │  │  StepsUploader    (batch+upload)  │
│ Command     │  │  HttpApi          (Embassy)       │
│ Service     │  │  HCGatewayFacade  (REST client)   │
└─────────────┘  └──────────┬───────────────────────┘
                            │
                   ┌────────▼────────┐
                   │   Persistence   │
                   │                 │
                   │  FileSystem     │
                   │  (workouts.json)│
                   │  macOS Keychain │
                   │  UserDefaults   │
                   └─────────────────┘
```

## Bluetooth Low Energy Protocol

### Discovery

The app scans for devices advertising any of three service UUIDs:

| UUID | Service |
|------|---------|
| `0000180a-0000-1000-8000-00805f9b34fb` | Device Information Service (standard) |
| `00010203-0405-0607-0809-0a0b0c0d1912` | WalkingPad proprietary service |
| `0000fe00-0000-1000-8000-00805f9b34fb` | WalkingPad FE service |

A device is confirmed as a WalkingPad when both the `FE01` (notify) and `FE02` (command) characteristics are discovered under the `FE00` service.

### Connection Lifecycle

```
App Start → CBCentralManager.scanForPeripherals()
         → didDiscover → BluetoothPeripheral wrapper → connect()
         → didConnect → discoverServices → discoverCharacteristics
         → FE01 + FE02 found? → WalkingPadService.onConnect()
                                 → setNotifyValue(true) on FE01
         → didDisconnect → WalkingPadService.onDisconnect()
                         → restart scanning
```

Non-WalkingPad devices are added to an in-memory blacklist for the session to avoid reconnection attempts.

### Command Protocol

Commands are written to the `FE02` characteristic (write without response):

```
[0xF7, 0xA2, <command>, <parameter>, <checksum>, 0xFD]
 start  type   cmd byte   param byte   sum       end
```

The checksum is the sum of all bytes between the start and checksum positions, with overflow wrapping (UInt8 addition).

| Command | Byte 2 | Byte 3 | Description |
|---------|--------|--------|-------------|
| Set Speed | `0x01` | speed (0-80) | Speed in tenths of km/h (e.g., 25 = 2.5 km/h) |
| Update Status | `0x00` | `0x00` | Request current status notification |
| Start | `0x04` | `0x01` | Start the treadmill belt |
| Set Mode | `0x02` | 0 or 1 | 0 = automatic, 1 = manual |

### Status Notification Format

Notifications arrive on `FE01` as a byte array (14+ bytes):

| Byte(s) | Field | Encoding |
|---------|-------|----------|
| 0-1 | Status type | `0xF8 0xA2` = current, `0xF8 0xA7` = last session |
| 2 | (reserved) | — |
| 3 | Speed | Raw integer, divide by 10 for km/h |
| 4 | Walking mode | 1 = manual, 0 = automatic |
| 5-7 | Walking time | Big-endian seconds |
| 8-10 | Distance | Big-endian, multiply by 10 |
| 11-13 | Steps | Big-endian step count |

Multi-byte integers are decoded as big-endian: `value = byte[0] * 256^2 + byte[1] * 256 + byte[2]`.

## Data Flow

### BLE → UI Update Path

```
CoreBluetooth notification (FE01)
  → WalkingPadService.peripheral(_:didUpdateValueFor:)
    → Parse binary → DeviceState struct
    → Fire callback(oldState, newState)
      ├── Workout.update(oldState, newState)
      │     → Accumulate steps/distance/time diffs
      │     → @Published properties update → SwiftUI re-renders
      │     → Fire onChangeCallback(Change)
      │           → StepsUploader.handleChange(change)
      │                 → If treadmill just stopped + steps >= 10:
      │                       → HCGatewayService.uploadSteps()
      └── MqttService.publish(oldState, newState, workoutState)
            → Rate-limited: only on speed change or every 30s
            → JSON → MQTT topic
```

### Polling Loop

A `RepeatingTimer` fires every ~4 seconds (hardcoded, see Known Issues):

1. `Workout.resetIfDateChanged()` — zeroes counters at midnight
2. `WalkingPadCommand.updateStatus()` — requests a fresh status notification from the treadmill

### Sleep/Wake Handling

| Event | Actions |
|-------|---------|
| `willSleepNotification` | Stop timer, stop MQTT, reset StepsUploader |
| `didWakeNotification` | Stop+restart timer, stop+restart MQTT, restart BLE scanning, reconnect to known peripheral after 2s delay, reset StepsUploader |

## HTTP API (Port 4934)

An Embassy-based HTTP server runs on a background thread. It provides local control for Alfred workflows and the external stats web app.

| Method | Path | Response |
|--------|------|----------|
| GET | `/treadmill` | `{"steps": N, "distance": N, "walkingSeconds": N, "speed": N.N}` |
| GET | `/treadmill/workouts` | Array of `{"steps": N, "distance": N, "walkingSeconds": N, "date": "YYYY-MM-DD"}` |
| POST | `/treadmill/start` | Starts the treadmill |
| POST | `/treadmill/stop` | Sets speed to 0 |
| POST | `/treadmill/faster` | Increments speed by 0.5 km/h |
| POST | `/treadmill/slower` | Decrements speed by 0.5 km/h |
| POST | `/treadmill/speed/{10-80}` | Sets speed (multiples of 10 only, e.g., `/speed/30` = 3.0 km/h) |

GET endpoints include `access-control-allow-origin: *` for browser access. Returns 428 if treadmill is not connected, 404 for unknown paths.

## MQTT Integration

Configured via `~/.../Autosave Information/.walkingpad-client-mqtt.json`:

```json
{
  "username": "...",
  "password": "...",
  "host": "192.168.0.73",
  "port": 1883,
  "topic": "homeassistant/sensor/walkingpad"
}
```

Publishes JSON messages to the configured topic:

```json
{
  "stepsWalkingpad": 510,
  "stepsTotal": 19202,
  "distanceTotal": 4690,
  "speedKmh": 1.5
}
```

**Rate limiting**: Messages are sent only when the speed changes or when 30+ seconds have elapsed since the last message.

## HCGateway Health Sync

A two-layer integration for syncing steps to Google Fit via the [HCGateway](https://github.com/ShuchirJ/HCGateway) bridge:

### API Client (`HCGatewayFacade.swift`)

- Base URL: `https://api.hcgateway.shuchir.dev`
- `POST /api/v2/login` — authenticate, returns `{token, refresh, expiry}`
- `POST /api/v2/refresh` — refresh expired access token
- `PUT /api/v2/push/steps` — upload step records with ISO8601 timestamps

### Token Management (`HCGatewayService.swift`)

- Access token and refresh token stored in macOS Keychain
- Expiry date stored in UserDefaults
- Automatic token refresh on 401/403 responses
- Login UI via floating `NSWindow` with username/password form

### Upload Trigger (`StepsUploader.swift`)

Steps are batched and uploaded when ALL of these conditions are met:
1. A speed change occurred
2. Accumulated steps >= 10
3. Previous speed was non-zero (was walking)
4. New speed is zero (just stopped/paused)

## Persistence

| Data | Location | Format |
|------|----------|--------|
| Workout history | `~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information/workouts.json` | JSON array, max 500 entries |
| MQTT config | Same directory, `.walkingpad-client-mqtt.json` | JSON |
| Access token | macOS Keychain (`kSecClassGenericPassword`, account: `accessToken`) | String |
| Refresh token | macOS Keychain (`kSecClassGenericPassword`, account: `refreshToken`) | String |
| Token expiry | UserDefaults (key: `expiryDate`) | Date |

## Threading Model

| Component | Thread | Notes |
|-----------|--------|-------|
| CoreBluetooth callbacks | Main thread | `CBCentralManager(delegate:, queue: nil)` defaults to main |
| `WalkingPadService.callback` | Main thread (from BLE) | Directly mutates `@Published` Workout properties |
| `onChangeCallback` (StepsUploader) | `DispatchQueue.global(.userInitiated)` | Dispatched explicitly in AppDelegate |
| HTTP server | `DispatchQueue.global(.userInitiated)` | `loop.runForever()` blocks the thread permanently |
| MQTT (NIO event loop) | Dedicated NIO thread | `MultiThreadedEventLoopGroup(numberOfThreads: 1)` |
| Timer callbacks | Main RunLoop | `Timer.scheduledTimer` added to `RunLoop.main` |
| HCGateway API calls | Swift async/await | `MainActor.run` for state mutations |

## View Hierarchy

```
MenuBarPopoverApp (SwiftUI App)
  └── Settings { EmptyView() }  ← custom EmptyView, not SwiftUI's

AppDelegate (NSApplicationDelegate)
  └── NSStatusItem → NSMenu → NSMenuItem
        └── NSHostingView
              └── ContentView
                    ├── DeviceView (when connected)
                    │     ├── RunningView (speed > 0)
                    │     │     ├── WorkoutStateView
                    │     │     ├── Speed button grid (4x4, manual mode)
                    │     │     ├── Walking mode toggle
                    │     │     └── Stop button
                    │     └── StoppedOrPausedView (speed == 0)
                    │           ├── WorkoutStateView
                    │           └── Start button
                    ├── WaitingForTreadmillView (when disconnected)
                    └── FooterView
                          ├── Stats link (external web app)
                          ├── LoginLogoutButton → LoginWindowView
                          └── Quit button
```

## External Dependencies

| System | URL | Purpose |
|--------|-----|---------|
| HCGateway API | `https://api.hcgateway.shuchir.dev` | Health data sync bridge |
| HCGateway App | [github.com/ShuchirJ/HCGateway](https://github.com/ShuchirJ/HCGateway) | Bridge app (iOS/Android) |
| Stats Web App | `https://walkingpad-stats.netlify.app` | External statistics dashboard |
| ph4-walkingpad | [github.com/ph4r05/ph4-walkingpad](https://github.com/ph4r05/ph4-walkingpad) | Protocol reference (Python) |
