# Phase 3: Menu UI + Config Management - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the full menu UI to live connection state for all configs: per-config state indicators, clickable connect/disconnect rows, and the empty-state placeholder. Add config management: "Add Config…" via NSOpenPanel (copies file to configs dir), "Remove Config ▶" submenu (moves to Trash), "View Logs ▶" submenu (opens Console.app). Implement config loading from disk at launch. No IPC socket (Phase 4), no CLI (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Authenticating State — Click Behavior
- Config rows in `.authenticating` state ARE clickable — clicking cancels the in-progress auth flow
- This overrides REQUIREMENTS.md UI-03 ("non-clickable") — Phase 2 decision stands
- VPNManager.connect() already implements cancel-on-click via cancelAuth(); no additional code needed there
- Label while authenticating: `"⏳ authenticating"` (replaces UI-02's `"[authenticating…]"` spec)

### Authenticating State — Other Configs
- While any config is `.authenticating`, all other disconnected configs are **disabled** (grayed out, unclickable) in the menu
- Communicates the single-auth-at-a-time constraint visually — user knows why they can't connect a second config
- VPNManager already throws `.alreadyAuthenticating`; the UI simply reflects this with `.disabled()`

### Connected State Display
- Label: `"● Connected"` — green dot prefix matching UI-02 spec
- Row layout: config name left-aligned, state indicator right-aligned (using `Spacer()` in SwiftUI HStack)
- Failed state label format locked from Phase 2: `"⚠ <short error>"` right-aligned (≤ 30 chars)
- Disconnected configs: no state indicator — name only

### Config Loading
- Load once at app launch: `VPNManager.loadConfigs()` scans `configsDirectory` and populates `configs` array
- Sorted alphabetically by `config.name` (filename without `.conf` extension)
- Add/remove operations update `configs` in-memory directly — no rescan needed

### Add Config Flow
- "Add Config…" triggers NSOpenPanel filtered to `.conf` files
- Selected file is **copied** into `~/Library/Application Support/AWSVPNClient/configs/`
- If a file with the same name already exists: silently overwrite
- After copy: create new `VPNConfig` and append to `vpnManager.configs` array (in-memory, no disk rescan)
- Re-sort after append to maintain alphabetical order

### Remove Config Behavior
- "Remove Config ▶" submenu lists all configs
- Active configs (`.connected`, `.authenticating`, `.disconnecting`) are **disabled** in the submenu — user must disconnect first
- Removal: move file to Trash via `NSWorkspace.shared.recycle()` (recoverable; not permanent delete)
- After removal: remove from `vpnManager.configs` array and clear `vpnManager.connections[config.name]`

### Menu Layout & Structure
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Config Management — CONF-01 (NSOpenPanel add), CONF-02 (configs directory), CONF-03 (remove submenu), CONF-04 (listed at launch, live updates)
- `.planning/REQUIREMENTS.md` §Menu Bar UI — UI-01 (lock icon — already done Phase 1), UI-02 (state labels), UI-03 (overridden by Phase 2 context — see below), UI-04 (View Logs submenu), UI-05 (Quit item)

### Phase 2 decisions that affect Phase 3 UI
- `.planning/phases/02-connection-lifecycle/02-CONTEXT.md` — Auth cancel-on-click, .failed label format, single-auth-at-a-time constraint, failed-state immediate retry

### Known pitfalls
- `.planning/research/PITFALLS.md` — Review for any NSOpenPanel or menu bar activation pitfalls

### Project constraints
- `.planning/PROJECT.md` §Constraints — macOS 14.0+, Swift 6.1 strict concurrency, @Observable (no @StateObject)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AWSVPNClient/StatusMenuView.swift` — Stub to replace entirely; already has `@Environment(VPNManager.self)` wiring and Quit button as starting point
- `VPNCore/VPNManager.swift` — `configs: [VPNConfig]`, `connections: [String: ConnectionState]`, `connect()`, `disconnect()`, `configsDirectory`, `logsDirectory` all ready to use
- `VPNCore/ConnectionState.swift` — `isConnected`, `isAuthenticating`, `isDisconnecting` helper vars available for menu item disable logic
- `VPNCore/VPNConfig.swift` — `name` and `fileURL` are all that's needed for menu display and file operations

### Established Patterns
- `@Observable @MainActor VPNManager` — all mutations must be on MainActor; consistent with Phase 2 patterns
- `try? FileManager.default.createDirectory(...)` — established idiomatic pattern for directory ops in this codebase
- `NSApplication.shared.terminate(nil)` — already in StatusMenuView, keep as-is

### Integration Points
- `AWSVPNClientApp.swift`: `@State private var vpnManager = VPNManager()` — loadConfigs() should be called here or in VPNManager.init()
- `VPNManager.configs` — the source of truth for the menu config list; add/remove must update this array on `@MainActor`
- `VPNManager.connections` — drives all per-config state display; already wired to `isAnyConnected` for the lock icon

</code_context>

<specifics>
## Specific Ideas

- Menu layout confirmed against preview mockup: configs on top, management group in middle, Quit at bottom — matches Tailscale/1Password menu bar conventions
- Move to Trash (not permanent delete) for removed configs — user can recover an accidentally removed config
- "⏳ authenticating" instead of "[authenticating…]" — user's preference for the emoji label

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-menu-ui-config-management*
*Context gathered: 2026-03-20*
