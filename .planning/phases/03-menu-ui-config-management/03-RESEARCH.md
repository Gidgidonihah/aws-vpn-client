# Phase 3: Menu UI + Config Management - Research

**Researched:** 2026-03-20
**Domain:** SwiftUI MenuBarExtra, NSOpenPanel, FileManager, NSWorkspace
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Authenticating State — Click Behavior**
- Config rows in `.authenticating` state ARE clickable — clicking cancels the in-progress auth flow
- This overrides REQUIREMENTS.md UI-03 ("non-clickable") — Phase 2 decision stands
- VPNManager.connect() already implements cancel-on-click via cancelAuth(); no additional code needed there
- Label while authenticating: `"⏳ authenticating"` (replaces UI-02's `"[authenticating…]"` spec)

**Authenticating State — Other Configs**
- While any config is `.authenticating`, all other disconnected configs are **disabled** (grayed out, unclickable) in the menu
- Communicates the single-auth-at-a-time constraint visually — user knows why they can't connect a second config
- VPNManager already throws `.alreadyAuthenticating`; the UI simply reflects this with `.disabled()`

**Connected State Display**
- Label: `"● Connected"` — green dot prefix matching UI-02 spec
- Row layout: config name left-aligned, state indicator right-aligned (using `Spacer()` in SwiftUI HStack)
- Failed state label format locked from Phase 2: `"⚠ <short error>"` right-aligned (≤ 30 chars)
- Disconnected configs: no state indicator — name only

**Config Loading**
- Load once at app launch: `VPNManager.loadConfigs()` scans `configsDirectory` and populates `configs` array
- Sorted alphabetically by `config.name` (filename without `.conf` extension)
- Add/remove operations update `configs` in-memory directly — no rescan needed

**Add Config Flow**
- "Add Config…" triggers NSOpenPanel filtered to `.conf` files
- Selected file is **copied** into `~/Library/Application Support/AWSVPNClient/configs/`
- If a file with the same name already exists: silently overwrite
- After copy: create new `VPNConfig` and append to `vpnManager.configs` array (in-memory, no disk rescan)
- Re-sort after append to maintain alphabetical order

**Remove Config Behavior**
- "Remove Config ▶" submenu lists all configs
- Active configs (`.connected`, `.authenticating`, `.disconnecting`) are **disabled** in the submenu — user must disconnect first
- Removal: move file to Trash via `NSWorkspace.shared.recycle()` (recoverable; not permanent delete)
- After removal: remove from `vpnManager.configs` array and clear `vpnManager.connections[config.name]`

**Menu Layout & Structure**
Exact arrangement (top to bottom):
1. Config list — one row per config, name left / state right
2. Empty state placeholder (when no configs): `"No configs — use Add Config…"` as disabled, grayed text
3. `Divider()`
4. `"Add Config…"` — triggers NSOpenPanel
5. `"Remove Config"` — submenu (`▶`) listing all configs (active ones disabled)
6. `"View Logs"` — submenu (`▶`) listing each config; selecting opens `~/Library/Logs/AWSVPNClient/<name>.log` in Console.app
7. `Divider()`
8. `"Quit AWSVPNClient"` — `NSApplication.shared.terminate(nil)`

### Claude's Discretion
- NSOpenPanel activation details (NSApp.activate() call, window ordering for menu bar apps)
- Exact SwiftUI modifiers for disabled state styling
- Whether loadConfigs() lives in VPNManager.init() or is called from the App struct
- View Logs submenu: how Console.app is opened (NSWorkspace.open or shell command)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONF-01 | User can add a `.conf` file via NSOpenPanel ("Add Config…" in menu) | NSOpenPanel API pattern; menu bar app activation; FileManager.copyItem |
| CONF-02 | Config files stored in `~/Library/Application Support/AWSVPNClient/configs/` | configsDirectory already defined as static let on VPNManager; directory creation already in init() |
| CONF-03 | User can remove a config via "Remove Config ▶" submenu | NSWorkspace.recycle() for Trash move; in-memory array mutation; connection cleanup |
| CONF-04 | All configs in the directory are listed in the menu at launch and reflect changes after add/remove | loadConfigs() scan at launch; in-memory updates after add/remove keep list live |
| UI-01 | Menu bar icon lock.fill / lock.open (template rendering) | Already wired in AWSVPNClientApp.swift via isAnyConnected; this is done |
| UI-02 | Per-config state labels (Connected, authenticating, blank) | SwiftUI HStack with Spacer(); state-derived label strings; .foregroundStyle(.green) |
| UI-03 | OVERRIDDEN: authenticating configs ARE clickable (cancel flow); disconnected configs grayed during auth | .disabled() modifier; ConnectionState helpers; VPNManager.connect() already handles cancel-on-click |
| UI-04 | "View Logs ▶" submenu — opens log file in Console.app | NSWorkspace.shared.open(URL) with Console.app bundle ID or direct file URL |
| UI-05 | "Quit" menu item terminates app | NSApplication.shared.terminate(nil) already in StatusMenuView; keep as-is |
</phase_requirements>

---

## Summary

Phase 3 replaces the stub `StatusMenuView` with a fully functional menu and adds config lifecycle methods to `VPNManager`. The work divides cleanly into two halves: (1) adding `loadConfigs()`, `addConfig(from:)`, and `removeConfig(_:)` to VPNManager, and (2) rewriting StatusMenuView to render the full menu layout from CONTEXT.md.

All the supporting infrastructure already exists from Phases 1–2. `VPNManager` has `configs`, `connections`, `configsDirectory`, `logsDirectory`, `connect()`, `disconnect()`, and all `ConnectionState` helpers. The menu is already mounted in `AWSVPNClientApp` with `@MainActor` and `@Observable` wiring in place. Phase 3 is purely additive — no existing methods change.

The only technically nuanced parts are the NSOpenPanel activation pattern for menu bar apps (the panel needs `NSApp.activate(ignoringOtherApps: true)` before `runModal()` or it appears behind the menu) and the move-to-Trash API (`NSWorkspace.shared.recycle(_:completionHandler:)` is async; the UI must handle this on MainActor).

**Primary recommendation:** Add three methods to VPNManager (loadConfigs, addConfig, removeConfig), then rewrite StatusMenuView to match the CONTEXT.md layout exactly. Two files change; no new dependencies.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14+ built-in | Menu layout, Button, Divider, HStack, Spacer, Text | The established pattern for this project |
| AppKit NSOpenPanel | macOS 14+ built-in | File picker for "Add Config…" | Only AppKit API for open panels |
| Foundation FileManager | macOS 14+ built-in | copyItem, contentsOfDirectory, createDirectory | Already used throughout; established pattern |
| AppKit NSWorkspace | macOS 14+ built-in | recycle() for Trash move, open() for Console.app | Standard macOS file/app operations |

### No New Dependencies

This phase requires zero new Swift packages or frameworks. Everything needed is in AppKit + Foundation + SwiftUI, all already imported by the project.

**Installation:** None needed.

---

## Architecture Patterns

### Recommended File Structure Changes

```
AWSVPNClient/
└── StatusMenuView.swift          # Full replacement (was stub)

VPNCore/
└── VPNManager.swift              # Add loadConfigs(), addConfig(from:), removeConfig(_:)
```

Only two files change in this phase. No new files needed.

### Pattern 1: loadConfigs() — Scan at Launch

**What:** Scan `configsDirectory` for `.conf` files, create `VPNConfig` instances, sort alphabetically, assign to `configs`.

**When to use:** Called once at startup. Either from `VPNManager.init()` (synchronous file I/O is fine — it's fast directory listing) or from `AWSVPNClientApp` body via `.task { vpnManager.loadConfigs() }`. The CONTEXT.md marks this as Claude's discretion; placing it in `VPNManager.init()` is the cleaner choice since it keeps the manager self-contained.

**Example:**
```swift
// In VPNManager — called from init() or exposed as public func for App to call
public func loadConfigs() {
    let urls = (try? FileManager.default.contentsOfDirectory(
        at: Self.configsDirectory,
        includingPropertiesForKeys: nil,
        options: .skipsHiddenFiles
    )) ?? []
    configs = urls
        .filter { $0.pathExtension == "conf" }
        .map { VPNConfig(fileURL: $0) }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}
```

**Note:** `contentsOfDirectory(at:includingPropertiesForKeys:options:)` does not guarantee ordering — always sort after collecting.

### Pattern 2: addConfig(from:) — Copy and Append

**What:** Copy the user-selected `.conf` file into `configsDirectory`, create a `VPNConfig`, append to `configs`, re-sort.

**When to use:** After NSOpenPanel returns a URL.

**Example:**
```swift
public func addConfig(from sourceURL: URL) throws {
    let destURL = Self.configsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
    // Silently overwrite if exists (CONTEXT.md decision)
    try? FileManager.default.removeItem(at: destURL)
    try FileManager.default.copyItem(at: sourceURL, to: destURL)
    let config = VPNConfig(fileURL: destURL)
    configs.append(config)
    configs.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
}
```

**Critical:** Always call `createDirectory` before `copyItem` (Pitfall 14 — directory may not exist). VPNManager.init() already does this, so it is safe here, but the pattern is worth documenting.

### Pattern 3: removeConfig(_:) — Trash and Clean Up

**What:** Move the config file to Trash, remove from `configs` array, clear `connections` entry.

**When to use:** User selects a config from "Remove Config ▶" submenu. CONTEXT.md mandates the config must already be in `.disconnected` state at this point (active configs are disabled in the submenu).

**Example:**
```swift
public func removeConfig(_ config: VPNConfig) {
    NSWorkspace.shared.recycle([config.fileURL]) { _, _ in
        // Completion fires on an arbitrary queue — dispatch to MainActor
        Task { @MainActor [weak self] in
            self?.configs.removeAll { $0.id == config.id }
            self?.connections.removeValue(forKey: config.name)
        }
    }
}
```

**Alternative (simpler, synchronous):** Use `FileManager.default.trashItem(at:resultingItemURL:)` — this is synchronous, throws on failure, and is `@MainActor`-safe. The result URL (in Trash) is not needed. This is simpler than `NSWorkspace.recycle()` and avoids the callback-to-MainActor complexity.

```swift
public func removeConfig(_ config: VPNConfig) {
    try? FileManager.default.trashItem(at: config.fileURL, resultingItemURL: nil)
    configs.removeAll { $0.id == config.id }
    connections.removeValue(forKey: config.name)
}
```

**Recommendation:** Use `FileManager.trashItem` (synchronous). `NSWorkspace.recycle()` is the AppKit-level API intended for Finder-like file management; `FileManager.trashItem` is the Swift-idiomatic equivalent and keeps everything on MainActor with no callback dispatch needed.

### Pattern 4: NSOpenPanel in a Menu Bar App

**What:** `NSOpenPanel.runModal()` blocks the thread until the user picks a file or cancels. In a menu bar app, the panel appears behind the menu by default unless the app is explicitly activated.

**Critical activation sequence for menu bar apps:**
```swift
Button("Add Config…") {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.init(filenameExtension: "conf")!]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.title = "Select OpenVPN Config File"

    // REQUIRED for menu bar apps: bring app to foreground so panel appears in front
    NSApp.activate(ignoringOtherApps: true)

    if panel.runModal() == .OK, let url = panel.url {
        try? vpnManager.addConfig(from: url)
    }
}
```

**Why `NSApp.activate` is required:** `LSUIElement = YES` apps do not automatically become the frontmost app when showing panels. Without activation, the open panel appears behind other windows and is invisible to the user. This is a well-known menu bar app gotcha documented in multiple Apple Developer Forums threads.

**UTType for `.conf` files:** `.conf` files have no registered UTI in macOS. Use `UTType(filenameExtension: "conf")` — this returns an optional since it is a dynamic (unregistered) type. Unwrap safely. Alternatively, use the older `panel.allowedFileTypes = ["conf"]` (deprecated but still works on macOS 14).

### Pattern 5: StatusMenuView Layout

**What:** The complete SwiftUI view body matching CONTEXT.md's menu structure.

**Key modifiers and techniques:**

```swift
// Config row with state right-aligned
Button(action: { Task { try? await vpnManager.connect(config) } }) {
    HStack {
        Text(config.name)
        Spacer()
        Text(stateLabel(for: config))
            .foregroundStyle(stateColor(for: config))
    }
}
.disabled(isConfigDisabled(config))

// Disabled disconnected configs during auth (grayed automatically by .disabled())
private func isConfigDisabled(_ config: VPNConfig) -> Bool {
    let isAnyAuthenticating = vpnManager.connections.values.contains { $0.isAuthenticating }
    let state = vpnManager.connections[config.name] ?? .disconnected
    // Disconnected configs are disabled while any auth is in progress
    if isAnyAuthenticating, case .disconnected = state { return true }
    // Failed configs: not disabled (immediate retry on click)
    // Authenticating configs: not disabled (cancel on click)
    return false
}

// Submenu using Menu { } label style
Menu("Remove Config") {
    ForEach(vpnManager.configs) { config in
        Button(config.name) {
            vpnManager.removeConfig(config)
        }
        .disabled(isActiveConfig(config))
    }
}
```

**Empty state:** When `vpnManager.configs.isEmpty`, show a single disabled Text item instead of the ForEach.

### Pattern 6: Opening Console.app for Logs

**What:** Open the log file for a config in Console.app.

**Claude's discretion resolution:** Use `NSWorkspace.shared.open(_:withApplicationAt:configuration:completionHandler:)` with Console.app's bundle ID, OR simply `NSWorkspace.shared.open(logFileURL)` — macOS associates `.log` files with Console.app by default, so the simpler form works without hardcoding an app path.

```swift
// Simple form — relies on .log file association
NSWorkspace.shared.open(
    VPNManager.logsDirectory.appendingPathComponent("\(config.name).log")
)
```

If the log file does not exist yet (config never connected), create an empty file first, then open it.

### loadConfigs() Placement — Claude's Discretion Resolution

**Recommendation:** Place `loadConfigs()` in `VPNManager.init()` directly. The directory listing is fast (< 1ms for a handful of `.conf` files), synchronous I/O on the main thread during init is acceptable, and it keeps the manager self-contained. The alternative (calling from `AWSVPNClientApp` via `.task {}`) adds complexity for no benefit.

### Anti-Patterns to Avoid

- **Rescanning disk after every add/remove:** CONTEXT.md explicitly prohibits this. Update `configs` array in-memory only.
- **Using `NSWorkspace.recycle()` when `FileManager.trashItem` suffices:** The async callback form of `recycle()` adds unnecessary MainActor dispatch complexity.
- **Calling `NSOpenPanel.runModal()` without `NSApp.activate()`:** Panel will appear behind other windows in a menu bar app.
- **Using `panel.allowedFileTypes = ["conf"]` deprecated API for anything other than fallback:** Prefer `allowedContentTypes` with `UTType(filenameExtension:)`.
- **ForEach over `[String]` (config names) instead of `[VPNConfig]`:** Use `ForEach(vpnManager.configs)` since `VPNConfig` is `Identifiable`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Move file to Trash | Custom "rm to ~/.Trash" logic | `FileManager.trashItem(at:resultingItemURL:)` | Handles locked files, name conflicts, user's actual Trash (which may be on a different volume) |
| File picker UI | Custom NSWindow file browser | `NSOpenPanel` | Standard macOS open panel, sandboxing-compatible, zero implementation effort |
| Sort config list | Custom sort | `.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }` | `localizedCompare` handles locale-aware sorting (accented chars, numeric order) correctly |
| Open log in viewer | Custom log display window | `NSWorkspace.shared.open(url)` | Console.app already handles `.log` files |

---

## Common Pitfalls

### Pitfall A: NSOpenPanel Appears Behind Other Windows

**What goes wrong:** In an `LSUIElement = YES` menu bar app, `NSOpenPanel.runModal()` shows the panel but it's hidden behind the user's current foreground app.

**Why it happens:** The app has no Dock presence and never becomes the active app automatically. macOS window ordering places the panel behind the frontmost application.

**How to avoid:** Always call `NSApp.activate(ignoringOtherApps: true)` immediately before `panel.runModal()`.

**Warning signs:** Users report the app "hangs" or "doesn't respond" after clicking "Add Config…" — the panel opened but is invisible.

### Pitfall B: Missing createDirectory Before copyItem (Pitfall 14 from PITFALLS.md)

**What goes wrong:** `FileManager.copyItem(at:to:)` throws if the destination directory doesn't exist.

**Why it happens:** `configsDirectory` is created in `VPNManager.init()`, but if the app was updated and init() wasn't rerun, or the user manually deleted the folder, copyItem fails silently (if wrapped in `try?`).

**How to avoid:** Call `try? FileManager.default.createDirectory(at: Self.configsDirectory, withIntermediateDirectories: true)` at the top of `addConfig(from:)`. This is idempotent.

**Warning signs:** "Add Config…" dialog closes, nothing appears in the config list, no error shown.

### Pitfall C: Button Rows in MenuBarExtra .menu Style and HStack Layout

**What goes wrong:** SwiftUI `Button` in `.menu` style `MenuBarExtra` uses the button label's view for the menu item content. `HStack { Text ... Spacer() Text ... }` inside a Button works for visual layout, but `Spacer()` in a menu item does not expand to full menu width on all macOS versions — it may collapse.

**Why it happens:** Menu items have a fixed width based on the longest item; `Spacer()` inside a Button label in a menu context does not behave identically to a window context.

**How to avoid:** Test the HStack layout in the actual running app, not just in SwiftUI Previews. If Spacer() collapses, use a fixed-width approach or right-align state text via a separate Label format string. The CONTEXT.md design (name left / state right via HStack+Spacer) is the standard pattern used by apps like Tailscale and should work; validate early.

**Warning signs:** State indicator appears immediately after config name instead of right-aligned.

### Pitfall D: @Observable Mutations Must Stay on MainActor

**What goes wrong:** `NSWorkspace.recycle()` (if used) calls its completion handler on an arbitrary queue. Directly mutating `vpnManager.configs` inside the handler causes Swift 6 strict concurrency errors or runtime issues.

**Why it happens:** VPNManager is `@MainActor`. Any mutation from a non-main-actor context is a data race.

**How to avoid:** Use `FileManager.trashItem` (synchronous, already on MainActor) instead of `NSWorkspace.recycle()`. If `recycle` is used for any reason, wrap mutations in `Task { @MainActor in ... }`.

### Pitfall E: UTType for .conf Files

**What goes wrong:** `UTType(filenameExtension: "conf")` returns `nil` on some systems because `.conf` is not a registered file type in macOS's UTI database.

**Why it happens:** Only well-known types (jpg, png, pdf, txt, etc.) have registered UTIs. Custom extensions like `.conf` return a "dynamic" UTI or nil depending on macOS version.

**How to avoid:** Nil-check the result:
```swift
let allowedTypes: [UTType] = [UTType(filenameExtension: "conf")].compactMap { $0 }
panel.allowedContentTypes = allowedTypes.isEmpty ? [] : allowedTypes
if allowedTypes.isEmpty {
    panel.allowedFileTypes = ["conf"]  // deprecated fallback
}
```
Or use the simpler deprecated API `panel.allowedFileTypes = ["conf"]` which is still functional on macOS 14+.

---

## Code Examples

### State Label Helper

```swift
private func stateLabel(for config: VPNConfig) -> String {
    switch vpnManager.connections[config.name] ?? .disconnected {
    case .connected:           return "● Connected"
    case .authenticating:      return "⏳ authenticating"
    case .disconnecting:       return "disconnecting…"
    case .failed(let msg):     return "⚠ \(msg.prefix(30))"
    case .disconnected:        return ""
    }
}

private func stateColor(for config: VPNConfig) -> Color {
    switch vpnManager.connections[config.name] ?? .disconnected {
    case .connected:      return .green
    case .authenticating: return .secondary
    case .disconnecting:  return .secondary
    case .failed:         return .red
    case .disconnected:   return .primary
    }
}
```

### isActiveConfig Helper (for Remove Submenu)

```swift
private func isActiveConfig(_ config: VPNConfig) -> Bool {
    let state = vpnManager.connections[config.name] ?? .disconnected
    return state.isConnected || state.isAuthenticating || state.isDisconnecting
}
```

### ConnectionState Extension for isActive

Rather than repeating the three-case check throughout the view, consider adding a computed property to `ConnectionState`:

```swift
// In ConnectionState.swift
public var isActive: Bool {
    isConnected || isAuthenticating || isDisconnecting
}
```

This is directly useful in both the Remove Config submenu and the Quit cleanup in AppDelegate.

### loadConfigs() in VPNManager.init()

```swift
public init() {
    try? FileManager.default.createDirectory(
        at: Self.configsDirectory, withIntermediateDirectories: true, attributes: nil)
    try? FileManager.default.createDirectory(
        at: Self.logsDirectory, withIntermediateDirectories: true, attributes: nil)
    self.samlServer = try? SAMLServer()
    loadConfigs()  // Add this line
}

public func loadConfigs() {
    let urls = (try? FileManager.default.contentsOfDirectory(
        at: Self.configsDirectory,
        includingPropertiesForKeys: nil,
        options: .skipsHiddenFiles
    )) ?? []
    configs = urls
        .filter { $0.pathExtension == "conf" }
        .map { VPNConfig(fileURL: $0) }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@StateObject` + `ObservableObject` | `@Observable` macro + `@State` | Swift 5.9 / macOS 14 | Already in use in this project; no change needed |
| `panel.allowedFileTypes = ["conf"]` | `panel.allowedContentTypes = [UTType(filenameExtension: "conf")]` | macOS 12+ | Both work on macOS 14; allowedContentTypes preferred but requires nil-check |
| `NSWorkspace.recycle(_:completionHandler:)` | `FileManager.trashItem(at:resultingItemURL:)` | macOS 8+ (trashItem is older) | trashItem is simpler for this use case |

**Deprecated/outdated:**
- `panel.allowedFileTypes`: Works but deprecated in macOS 12. Use `allowedContentTypes` with nil-check fallback.
- `@StateObject` / `ObservableObject`: Superseded by `@Observable` in this project — do not introduce.

---

## Open Questions

1. **`isActive` property on ConnectionState**
   - What we know: Three separate `isConnected || isAuthenticating || isDisconnecting` checks appear in both StatusMenuView (Remove Config submenu) and AppDelegate (termination cleanup).
   - What's unclear: Whether the planner should add `isActive` as a new computed var to `ConnectionState`, or inline the three checks at each call site.
   - Recommendation: Add `isActive` to `ConnectionState.swift` in Wave 1. It costs two lines and removes duplication. AppDelegate already uses the same three-way check — this would be a cleanup win.

2. **Log file missing when "View Logs ▶" is selected for a never-connected config**
   - What we know: `logsDirectory/<name>.log` is created in `spawnSudoOpenvpn()` only when a connection actually starts, not at config add time.
   - What's unclear: Should "View Logs" be disabled for configs with no log file, or create an empty file on first view?
   - Recommendation: Create an empty log file on demand in the View Logs action before calling `NSWorkspace.open()`. This is one line and avoids a "file not found" error from Console.app. Guard with `FileManager.fileExists` first.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (existing VPNCoreTests target) |
| Config file | AWSVPNClient.xcodeproj (inline scheme configuration) |
| Quick run command | `xcodebuild test -scheme AWSVPNClient -testPlan VPNCoreTests -destination 'platform=macOS' 2>&1 | grep -E 'Test (Passed|Failed|Case)'` |
| Full suite command | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' 2>&1 | tail -20` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONF-01 | NSOpenPanel copy path (post-panel logic) | unit | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests/VPNManagerTests/testAddConfigCopiesFile` | ❌ Wave 0 |
| CONF-02 | Configs directory exists and file lands in it | unit | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests/VPNManagerTests/testConfigsDirectory` | ❌ Wave 0 |
| CONF-03 | removeConfig removes from array and clears connections | unit | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests/VPNManagerTests/testRemoveConfigUpdatesArray` | ❌ Wave 0 |
| CONF-04 | loadConfigs reads .conf files, sorts alphabetically | unit | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests/VPNManagerTests/testLoadConfigsSorted` | ❌ Wave 0 |
| UI-01 | lock.fill / lock.open based on isAnyConnected | unit | existing isAnyConnected logic — covered indirectly | ✅ |
| UI-02 | stateLabel returns correct strings per state | unit | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests/VPNManagerTests/testStateLabelStrings` | ❌ Wave 0 |
| UI-03 | isConfigDisabled disables disconnected configs during auth | unit | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests/VPNManagerTests/testDisabledDuringAuth` | ❌ Wave 0 |
| UI-04 | View Logs action — manual (requires Console.app) | manual-only | n/a — integration with Console.app not unit-testable | — |
| UI-05 | Quit item present and calls terminate | manual-only | n/a — AppKit app termination not unit-testable | — |

**Note:** UI-02 and UI-03 test logic (stateLabel helper, isConfigDisabled helper) is best tested as pure functions extracted from the view or tested via VPNManager state. If they remain as private view helpers, they are manual-only. Recommendation: extract state label and disabled logic as internal/public functions on VPNManager or a separate helper type so they can be unit tested.

### Sampling Rate
- **Per task commit:** Run CONF-01 through CONF-04 tests targeting VPNManagerTests
- **Per wave merge:** Full `xcodebuild test` suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `VPNCoreTests/VPNManagerTests.swift` — add test methods for CONF-01, CONF-02, CONF-03, CONF-04, UI-02, UI-03 (file exists, needs new test cases)
- [ ] Consider extracting stateLabel / isConfigDisabled logic to `VPNManager` or a `MenuItemState` helper for testability

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation — NSOpenPanel: https://developer.apple.com/documentation/appkit/nsopenpanel
- Apple Developer Documentation — FileManager.trashItem: https://developer.apple.com/documentation/foundation/filemanager/1413590-trashitem
- Apple Developer Documentation — NSWorkspace.recycle: https://developer.apple.com/documentation/appkit/nsworkspace/1524994-recycle
- Apple Developer Documentation — UTType(filenameExtension:): https://developer.apple.com/documentation/uniformtypeidentifiers/uttype/init(filenameextension:)
- Existing codebase — VPNManager.swift, ConnectionState.swift, VPNConfig.swift (direct inspection)
- Existing codebase — AWSVPNClientApp.swift, AppDelegate.swift, StatusMenuView.swift (direct inspection)

### Secondary (MEDIUM confidence)

- .planning/research/PITFALLS.md — Pitfall 7 (MenuBarExtra .menu blocks run loop), Pitfall 8 (no re-render on open), Pitfall 10 (LSUIElement quit mechanism), Pitfall 14 (missing directory before copy)
- Apple Developer Forums — NSApp.activate(ignoringOtherApps:) required for panels in LSUIElement apps: documented pattern, consistent across multiple community sources
- .planning/phases/03-menu-ui-config-management/03-CONTEXT.md — Locked decisions from user discussion

### Tertiary (LOW confidence)

- HStack+Spacer layout behavior in MenuBarExtra .menu style: based on knowledge of SwiftUI menu item rendering; behavior with Spacer in menu buttons should be validated in the running app early.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are built-in AppKit/Foundation/SwiftUI; no external dependencies; existing codebase confirmed the exact versions
- Architecture: HIGH — VPNManager extension methods are straightforward; StatusMenuView rewrite has well-defined spec in CONTEXT.md; NSOpenPanel activation pattern is well-documented
- Pitfalls: HIGH — NSOpenPanel/LSUIElement pitfall is well-documented; FileManager vs NSWorkspace trade-off verified against official docs; HStack+Spacer in menu context is MEDIUM (needs runtime validation)

**Research date:** 2026-03-20
**Valid until:** 2026-06-20 (stable APIs; no fast-moving dependencies)
