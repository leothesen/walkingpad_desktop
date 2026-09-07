# Known Issues

## Active

### 1. NSApp.delegate cast fails from SwiftUI views
FooterView and other views can't access `NSApp.delegate as? AppDelegate` — the SwiftUI `@NSApplicationDelegateAdaptor` wraps it differently. Workaround: cached standalone service instances.

### 2. Notion session count may not match stats
Sessions deleted in Notion UI may still be returned by the API until the trash is fully purged. The app filters `archived` and `in_trash` pages but Notion's eventual consistency can cause brief mismatches.

### 3. NSHostingView in NSMenu causes layout warnings
`"It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out"` — cosmetic AppKit warning from embedding SwiftUI in NSMenu. Harmless. Fix would require migrating to NSPopover.

### 4. Notion push wipes workouts.json
`AppDelegate.onSessionComplete` writes an empty `WorkoutsSaveData` over `workouts.json` after a successful Notion push. In-memory state means the next `save()` puts it back, so it is usually invisible — but an app death in that window leaves the local file empty. Only the local mirror is at risk; Notion holds the sessions.

## Resolved

- **Crash on a short BLE frame, losing the in-flight session** — `WalkingPadService` sliced `byteArray[0...2]` before checking the payload length, and its later check tested `count < 13` while `byteArray[11...13]` needs 14. Payloads of 0, 1, 2 or 13 bytes trapped. On 2026-09-07 the treadmill's shutdown frame killed the app mid-session and took 2.62 km with it, because `todaySessions` — the only thing Notion and Strava read — is written when a session *ends*. Fixed by checking the length before any indexed read, and by `SessionCheckpoint`, which mirrors the running session to disk every update and recovers it at launch.
- **RepeatingTimer ignoring interval** — Fixed: now uses `self.interval` instead of hardcoded 4 seconds
- **EmptyView shadowing SwiftUI** — Fixed: deleted custom `EmptyView.swift`, uses SwiftUI's built-in
- **exit(0) bypassing cleanup** — Fixed: replaced with `NSApplication.shared.terminate(nil)`
- **Date check only comparing day-of-month** — Fixed: uses `Calendar.current.isDateInToday()` for full date comparison
- **Steps over-counting on reconnect** — Fixed by skipping first BLE update (no oldState to diff against)
- **"Publishing changes from within view updates"** — Fixed by deferring @Published mutations via DispatchQueue.main.async
- **Keychain password prompts** — Fixed by migrating all config to JSON files
- **Session detection missing treadmill stop** — Fixed with idle detection (3 consecutive zero-step updates)
- **Stats showing stale Notion data** — Fixed by always fetching fresh on stats window open
