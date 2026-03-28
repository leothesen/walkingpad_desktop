# CLAUDE.md — WalkingPad Desktop

## Project Overview

Native macOS status-bar application for controlling and monitoring WalkingPad treadmills over Bluetooth Low Energy (BLE). Written in Swift, built with Xcode.

## Build & Run

- **IDE**: Xcode (16.3+)
- **Language**: Swift
- **Platform**: macOS (menu bar app, `LSUIElement = true`)
- **Dependencies**: Swift Package Manager (embedded in Xcode). `Package.resolved` locks all deps.
- **Open**: `walkingpad-client.xcodeproj` in Xcode
- **Build**: Cmd+B or `xcodebuild -scheme walkingpad-client`
- **Run**: Cmd+R (appears in menu bar, not Dock)
- **Note**: `project.pbxproj` is gitignored — you may need to recreate project settings on a fresh clone

## Architecture

```
BLE Notify (FE01) → WalkingPadService → callback → Workout (accumulate steps)
                                                  → MqttService (Home Assistant)
                                                  → StepsUploader → HCGateway API
                                                  → HttpApi (port 4934, Alfred)
```

- **Entry point**: `walkingpad_clientApp.swift` — `MenuBarPopoverApp` + `AppDelegate`
- **Services layer**: All business logic in `services/`
- **Views**: SwiftUI views in `views/`, injected via `@EnvironmentObject`
- **Models**: Pure data types in `models/`
- **Persistence**: `workouts.json` in `~/Library/Containers/klassm.walkingpad-client/Data/Library/Autosave Information/`

## Key Files

| File | Purpose |
|------|---------|
| `walkingpad_clientApp.swift` | App entry, service wiring, sleep/wake lifecycle |
| `WalkingPadService.swift` | BLE notification parsing, central state holder |
| `WalkingPadCommand.swift` | BLE write commands (speed, start, mode) with checksum |
| `BluetoothDiscoveryService.swift` | Device scanning, connection, reconnect |
| `BluetoothPeripheral.swift` | Service/characteristic discovery, WalkingPad identification |
| `Workout.swift` | Step accumulation, daily reset, persistence |
| `HttpApi.swift` | Local HTTP server on port 4934 (Embassy) |
| `MqttService.swift` | MQTT publishing via mqtt-nio |
| `HCGatewayService.swift` | Auth + token management for health sync |
| `HCGatewayFacade.swift` | REST client for hcgateway.shuchir.dev |
| `StepsUploader.swift` | Batches step changes, triggers upload on treadmill stop |

## BLE Protocol

- Service UUIDs: `0000180a-...`, `00010203-...`, `0000fe00-...`
- Notify characteristic: `FE01` (status updates)
- Command characteristic: `FE02` (write commands)
- Command format: `[0xF7, 0xA2, cmd, param, checksum, 0xFD]`
- Status format: 14+ bytes, parsed for speed (byte 3), mode (byte 4), time (5-7), distance (8-10), steps (11-13)

## Dependencies

| Package | Purpose |
|---------|---------|
| Embassy 4.1.6 | Embedded HTTP server (kqueue-based) |
| mqtt-nio 2.8.1 | MQTT 3.1.1 client for Home Assistant |
| swift-nio 2.84.0 | Network I/O (mqtt-nio dependency) |

## Conventions

- No test target exists — the project has zero automated tests
- Classes use `open` access (legacy, not intentional framework design)
- Callbacks are used instead of Combine publishers for inter-service communication
- `@Published` properties drive SwiftUI reactivity
- Error handling is minimal — most failures are `print()`-logged and silently recovered
- Semicolons appear inconsistently (some files use them, some don't)

## Known Gotchas

- `RepeatingTimer` ignores its `interval` parameter and hardcodes 4 seconds
- `EmptyView.swift` shadows SwiftUI's built-in `EmptyView`
- `exit(0)` in FooterView bypasses cleanup — should use `NSApplication.shared.terminate(nil)`
- The date-change check in `Workout.resetIfDateChanged()` only compares day-of-month, not full date
- Thread safety: BLE callbacks mutate `@Published` state from background threads
