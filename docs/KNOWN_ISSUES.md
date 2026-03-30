# Known Issues

## Active

### 1. NSApp.delegate cast fails from SwiftUI views
FooterView and other views can't access `NSApp.delegate as? AppDelegate` — the SwiftUI `@NSApplicationDelegateAdaptor` wraps it differently. Workaround: cached standalone service instances.

### 2. Notion session count may not match stats
Sessions deleted in Notion UI may still be returned by the API until the trash is fully purged. The app filters `archived` and `in_trash` pages but Notion's eventual consistency can cause brief mismatches.

### 3. NSHostingView in NSMenu causes layout warnings
`"It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out"` — cosmetic AppKit warning from embedding SwiftUI in NSMenu. Harmless. Fix would require migrating to NSPopover.

## Resolved

- **RepeatingTimer ignoring interval** — Fixed: now uses `self.interval` instead of hardcoded 4 seconds
- **EmptyView shadowing SwiftUI** — Fixed: deleted custom `EmptyView.swift`, uses SwiftUI's built-in
- **exit(0) bypassing cleanup** — Fixed: replaced with `NSApplication.shared.terminate(nil)`
- **Date check only comparing day-of-month** — Fixed: uses `Calendar.current.isDateInToday()` for full date comparison
- **Steps over-counting on reconnect** — Fixed by skipping first BLE update (no oldState to diff against)
- **"Publishing changes from within view updates"** — Fixed by deferring @Published mutations via DispatchQueue.main.async
- **Keychain password prompts** — Fixed by migrating all config to JSON files
- **Session detection missing treadmill stop** — Fixed with idle detection (3 consecutive zero-step updates)
- **Stats showing stale Notion data** — Fixed by always fetching fresh on stats window open
