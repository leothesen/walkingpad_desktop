# Known Issues

## Active

### 1. RepeatingTimer ignores its interval parameter
**File:** `RepeatingTimer.swift:20`
Hardcodes 4 seconds instead of using `self.interval`. Timer is initialized with `interval: 5` in AppDelegate.

### 2. Custom EmptyView shadows SwiftUI's built-in
**File:** `views/EmptyView.swift`
Renders `Text("")` instead of nothing.

### 3. exit(0) on quit bypasses cleanup
**File:** `FooterView.swift`
Skips `deinit`, NIO event loop shutdown, pending file I/O. Should use `NSApplication.shared.terminate(nil)`.

### 4. Date-change check only compares day-of-month
**File:** `Workout.swift`
`now.get(.day) != self.lastUpdateTime.get(.day)` — walking on Jan 5 and opening Feb 5 would not trigger reset.

### 5. NSApp.delegate cast fails from SwiftUI views
FooterView and other views can't access `NSApp.delegate as? AppDelegate` — the SwiftUI `@NSApplicationDelegateAdaptor` wraps it differently. Workaround: cached standalone service instances.

### 6. Notion session count may not match stats
Sessions deleted in Notion UI may still be returned by the API until the trash is fully purged. The app filters `archived` and `in_trash` pages but Notion's eventual consistency can cause brief mismatches.

### 7. NSHostingView in NSMenu causes layout warnings
`"It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out"` — cosmetic AppKit warning from embedding SwiftUI in NSMenu. Harmless. Fix would require migrating to NSPopover.

## Resolved (kept for reference)

- **Steps over-counting on reconnect** — Fixed by skipping first BLE update (no oldState to diff against)
- **"Publishing changes from within view updates"** — Fixed by deferring @Published mutations via DispatchQueue.main.async
- **Keychain password prompts** — Fixed by migrating all config to JSON files
- **Session detection missing treadmill stop** — Fixed with idle detection (3 consecutive zero-step updates)
- **Stats showing stale Notion data** — Fixed by always fetching fresh on stats window open
