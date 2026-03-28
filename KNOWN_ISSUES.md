# Known Issues

Prioritized list of bugs, risks, and improvement areas discovered during a comprehensive codebase audit.

## Critical

### 1. Array index out-of-bounds in BLE status parsing
**File:** `WalkingPadService.swift:83-91`

The guard checks `byteArray.count < 13` but then accesses `byteArray[11...13]` (index 13 = 14th element). If the treadmill sends exactly 13 bytes, this crashes. The guard should check `< 14`. Additionally, `statusTypeFrom(Array(byteArray[0...2]))` on line 80 is called *before* the length check — a payload shorter than 3 bytes crashes before reaching the guard.

### 2. UInt8 underflow crash on `/treadmill/slower`
**File:** `HttpApi.swift:71-78`

If treadmill speed is 0-4, `UInt8((speed ?? 0) - 5)` produces a negative integer. Casting a negative `Int` to `UInt8` in Swift is a fatal error. Similarly, `/treadmill/faster` at speed > 250 overflows `UInt8`. No bounds checking exists.

### 3. Infinite recursion in token refresh retry
**File:** `HCGatewayService.swift:149-182`

`performPushRequest` calls itself recursively on 401/403 after a token refresh. If the refreshed token is also rejected, this recurses until stack overflow. Needs a retry counter or circuit breaker.

### 4. Force-unwraps throughout the codebase
**Files:** `HttpApi.swift:19,84,90,92,152`, `HCGatewayFacade.swift:33,190`

`try! SelectorEventLoop(...)`, `try! server.start()`, `try! NSRegularExpression(...)`, `Range(...)!`, `UInt8(...)!`, `.url!`, `.data(using:)!` — any of these can crash the app on edge cases (port in use, malformed data, etc.).

### 5. Thread safety violations
**Files:** `Workout.swift`, `WalkingPadService.swift`, `StepsUploader.swift`

`@Published` properties in `Workout` are mutated from BLE callback threads (not main thread). `StepsUploader.accumulatedSteps` and `startTime` are accessed from multiple queues without synchronization. These are data races.

### 6. No authentication on HTTP API
**File:** `HttpApi.swift`

The HTTP server on port 4934 has no auth, open CORS (`*`), and no localhost binding enforcement. Any process (or network peer if the firewall allows) can start/stop/change the treadmill speed. This is a physical safety issue.

## Important

### 7. RepeatingTimer ignores its interval parameter
**File:** `RepeatingTimer.swift:20`

`Timer.scheduledTimer(withTimeInterval: 4, ...)` hardcodes 4 seconds instead of using `self.interval`. The timer is initialized with `interval: 5` in AppDelegate.

### 8. `exit(0)` bypasses all cleanup
**File:** `FooterView.swift:17-20`

`exit(0)` skips `deinit`, NIO event loop shutdown, pending file I/O, and Bluetooth disconnect. Should use `NSApplication.shared.terminate(nil)`.

### 9. Date-change check only compares day-of-month
**File:** `Workout.swift:32`

`now.get(.day) != self.lastUpdateTime.get(.day)` compares only the day component. Walking on Jan 5 and opening the app on Feb 5 would not trigger the reset. Should use `Calendar.current.isDateInToday()`.

### 10. MQTT double-subscribe and self-subscription
**File:** `MqttService.swift:48-62`

The `flatMap` closure and `whenComplete` both call `subscribeToTopics` and assign `self.client`. Also, subscribing to its own publish topic is wasteful (received messages are silently dropped).

### 11. Keychain entries lack `kSecAttrService`
**File:** `HCGatewayService.swift:186-194`

Without `kSecAttrService`, keychain queries may collide with other apps that store items under the same `kSecAttrAccount` key (e.g., `"accessToken"`).

### 12. `.wait()` may deadlock on main thread
**File:** `MqttService.swift:74`

`client?.disconnect().wait()` is called from `stop()`, which can be invoked on the main thread via `receiveSleepNotification`. Calling `.wait()` on a NIO future from the main thread risks deadlock.

## Moderate

### 13. Custom `EmptyView` shadows SwiftUI's built-in
**File:** `views/EmptyView.swift`

The custom `EmptyView` renders `Text("")` instead of nothing. The `Settings { EmptyView() }` in the app entry point hits this custom type.

### 14. Typo in UI copy
**File:** `LoginWindowView.swift:28`

`"HCGatewy in Github"` — should be `"HCGateway on GitHub"`.

### 15. Distance display threshold too high
**File:** `WorkoutStateView.swift:4-8`

Switches from meters to km at 10,000m instead of 1,000m. Walking 5km shows as "5000 m".

### 16. Workout history silently truncated to 500 entries
**File:** `Workout.swift:109`

`workoutData.workouts.suffix(500)` drops older entries on every save with no warning. ~1.4 years of daily use before data loss.

### 17. Excessive disk I/O on speed changes
**File:** `Workout.swift:49-51`

Every speed change triggers a full JSON re-serialization + file write. With status polling every 4 seconds, any speed jitter causes hundreds of writes per session.

### 18. Peripheral blacklist has no eviction
**File:** `BluetoothDiscoveryService.swift:71`

Non-WalkingPad devices (and WalkingPads that fail discovery due to transient BLE errors) are permanently blacklisted for the session with no recovery mechanism.

### 19. Zero test coverage
The project has no test target, no unit tests, no integration tests. The BLE byte parsing, workout accumulation, and upload trigger logic are entirely untested.

### 20. `project.pbxproj` is gitignored
**File:** `.gitignore`

The Xcode project file is not version-controlled, making it impossible to clone and build from the repo alone without manually recreating project settings.
