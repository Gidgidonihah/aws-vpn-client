# Phase 1: Scaffold - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a buildable Xcode project with three linked targets (AWSVPNClient app, VPNCore framework, aws-connect CLI), a menu bar shell with no Dock icon, a typed VPNManager skeleton importable from both app and CLI, and config directory creation on first launch. No VPN logic — Phase 2 fills in the implementations.

</domain>

<decisions>
## Implementation Decisions

### VPNCore Linking Strategy
- Dynamic .framework — VPNCore compiled as an embedded framework inside the app bundle
- CLI binary lives at `AWSVPNClient.app/Contents/MacOS/aws-connect` alongside the app binary
- Both binaries load `VPNCore.framework` from `AWSVPNClient.app/Contents/Frameworks/`
- CLI rpath points to `@executable_path/../Frameworks/` — works because CLI is inside the bundle
- **Phase 1 must include a spike task:** build the three-target project and verify the CLI can successfully `import VPNCore` before writing any real logic. If rpath fails, pivot to local SPM before Phase 2 work begins.

### VPNManager Skeleton
- Full typed skeleton — not an empty shell
- `@Observable @MainActor class VPNManager`
- Properties: `var configs: [VPNConfig] = []`, `var connections: [String: ConnectionState] = [:]`
- Computed: `var isAnyConnected: Bool` (drives menu bar icon)
- Stub methods: `func connect(_ config: VPNConfig) async throws` and `func disconnect(_ config: VPNConfig) async throws` — both `fatalError("Phase 2")`
- `ConnectionState` enum in VPNCore: `.disconnected`, `.authenticating`, `.connected`, `.disconnecting`, `.failed(Error)`

### VPNConfig Model
- Minimal — name and file URL only, no parsed fields
- `struct VPNConfig: Identifiable, Hashable { let id: UUID; let name: String; let fileURL: URL }`
- `name` derived from filename without `.conf` extension
- Phase 2 adds parsed fields (host, port, proto) when the connection logic needs them

### MenuBarExtra Style
- `.menuBarExtraStyle(.menu)` — native macOS pull-down menu
- Each SwiftUI view inside becomes a native menu item
- Chosen for: native Mac feel, consistent with apps like Tailscale/1Password, matches the simple list UI
- The run-loop-blocks-while-open quirk is acceptable — state updates between opens, not during

### Menu Bar Icon
- Wire lock.fill / lock.open immediately in Phase 1, not a throwaway placeholder
- `systemImage: vpnManager.isAnyConnected ? "lock.fill" : "lock.open"`
- Use `.imageScaleStyle(.template)` for dark/light mode compatibility (meets UI-01)
- Phase 3 adds no icon changes — this is the final icon logic

### Claude's Discretion
- Xcode project file layout details (groups, folder structure within the project navigator)
- Exact rpath build setting names and values
- How to handle the config directory creation (AppDelegate vs. VPNManager init)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Scaffold — SCAF-01 (three targets), SCAF-02 (LSUIElement = YES)
- `.planning/REQUIREMENTS.md` §Menu Bar UI — UI-01 (lock icon template rendering)

### Known pitfalls
- `.planning/research/PITFALLS.md` Pitfall 7 — MenuBarExtra .menu style blocks run loop
- `.planning/research/PITFALLS.md` Pitfall 8 — MenuBarExtra .menu style does not re-render on open
- `.planning/research/PITFALLS.md` Pitfall 10 — LSUIElement app has no default quit mechanism (Quit button required in scaffold)
- `.planning/research/PITFALLS.md` Pitfall 13 — Process.waitUntilExit() blocks main thread (awareness for Phase 2 stub design)

### Project constraints
- `.planning/PROJECT.md` §Constraints — macOS 14.0 minimum, Swift 6.1 strict concurrency, @Observable (no @StateObject)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `aws-vpn-core/src/config.rs` — Rust config parser: extracts `remote` (host + port) and `proto` directives, filters auth directives. Swift port needed in Phase 2; not needed in Phase 1 skeleton.
- `aws-vpn-core/src/vpn.rs` — Auth flow reference: dummy creds format, CRV1 line parsing, final credential format. Phase 2 reference.

### Established Patterns
- No existing Swift code — greenfield. All patterns defined here become the project conventions.
- Rust uses RAII (tempfile) for credential cleanup — Swift equivalent is `defer { try? FileManager... }` — establish this pattern in Phase 2.

### Integration Points
- `VPNManager` is the single shared state object — instantiated in `App.swift`, passed into menu views, imported by CLI target
- Config directory: `~/Library/Application Support/AWSVPNClient/configs/` — created on first launch (Phase 1), read by VPNManager (Phase 2+)

</code_context>

<specifics>
## Specific Ideas

- No specific UI references given — open to standard macOS menu bar conventions
- User is new to Swift/macOS — planner should prefer explicit, conventional code over clever patterns

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-scaffold*
*Context gathered: 2026-03-17*
