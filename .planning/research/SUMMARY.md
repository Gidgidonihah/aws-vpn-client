# Research Summary

**Project:** AWS VPN Client — Swift macOS Menu Bar App
**Synthesized:** 2026-03-17
**Research files:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md

---

## Executive Summary

This project is a personal macOS menu bar utility that wraps AWS Client VPN with SAML authentication — converting a Rust CLI tool into a native Swift app. The research is unusually well-scoped: the domain is small, the technology choices are constrained to Apple-first APIs, and the predecessor implementation in Rust provides a working reference for all core flows (SAML auth, openvpn subprocess, credential passing). The recommended approach is a three-target Xcode project (VPNCore framework, app target, CLI target) using Swift 6.1 strict concurrency, `@Observable` state management on macOS 14+, `MenuBarExtra` with `.menu` style, and `Network.framework` for both the Unix socket IPC server and the SAML HTTP callback server. No third-party dependencies are needed beyond `swift-argument-parser` for the CLI.

The core risks are not architectural — they are operational. Six critical pitfalls emerge repeatedly across research files: `sudo` openvpn processes that survive app termination as orphaned root processes; `NWListener` instances that cannot be safely restarted after cancellation; SAML HTTP body fragmentation across multiple TCP receive callbacks; credential temp files left on disk after crash or failure; off-main-thread `@Observable` mutations from `NWListener` callbacks causing silent SwiftUI corruption; and the 104-byte Unix socket path length limit inherited from BSD. Every one of these is a known, documented issue with established mitigations — none requires architectural rethinking, but each requires deliberate implementation care.

The right sequencing is: nail the app scaffold and `VPNCore` framework structure first (this is the foundation everything else links against), then drive the connection lifecycle to a working state before adding UI polish, CLI companion, or quality-of-life features. The SAML flow and openvpn subprocess management are the hardest problems; they should be implemented and hardened before any non-critical features are started.

---

## Key Findings

### From STACK.md

| Technology | Rationale |
|------------|-----------|
| Swift 6.1 (Xcode 16.3) | Strict concurrency catches data-race bugs at compile time — essential when UI, subprocess I/O, and IPC handlers share `VPNManager` state |
| SwiftUI `MenuBarExtra` | Only non-deprecated first-party menu bar API; `.menu` style is correct for a flat config list |
| `@Observable` (macOS 14+) | Fine-grained property tracking eliminates spurious menu redraws; requires macOS 14 minimum |
| `Network.framework` (`NWListener`) | Modern replacement for CFSocket; handles Unix socket IPC and TCP SAML server with no third-party dependency |
| `Foundation.Process` | Stable, battle-tested subprocess API; `swift-subprocess` is v0.1 (Sept 2025) with unstable API — avoid |
| `swift-argument-parser` 1.3+ | Apple-maintained CLI parsing; Swift 6 compatible; only external dependency |
| `os.Logger` (OSLog) | Structured logging observable in Console.app; `print()` is invisible post-launch |

**Critical version requirements:**
- macOS 14+ deployment target (for `@Observable`)
- Xcode 16.3 with Swift 6 language mode enabled
- `swift-argument-parser` 1.3+ (Swift 6 compatibility)

### From FEATURES.md

**Table stakes (MVP — must ship):**
- Menu bar icon showing aggregate lock state (connected/disconnected)
- Config list with inline per-connection state indicator
- Click to connect (full SAML flow + openvpn subprocess)
- Click to disconnect
- Add config via file picker (`NSOpenPanel`)
- Remove config with confirmation
- Persisted configs in `~/Library/Application Support/AWSVPNClient/configs/`
- Per-connection log files in `~/Library/Logs/AWSVPNClient/`
- Quit from menu (required for `LSUIElement` apps)

**Differentiators (second pass):**
- Launch at login via `SMAppService` (macOS 13+)
- System notifications on connection state change (`UNUserNotificationCenter`)
- Companion CLI (`aws-connect`) via Unix domain socket IPC
- Connection error surfaced in menu with retry affordance
- Open log from menu (one `NSWorkspace.open` call — trivially easy once logs exist)

**Anti-features (do not build):**
- Preferences window (use inline menu toggle for launch at login)
- Auto-update mechanism (manual builds, git pull + rebuild)
- In-app log viewer (Console.app is purpose-built)
- System VPN / `NEVPNManager` integration (AWS Client VPN uses raw openvpn, not the macOS VPN stack)

**Key error states to design for:** Disconnected, Authenticating, Auth timeout, Connected, Unexpectedly disconnected, SAML port conflict, App not running (CLI only)

### From ARCHITECTURE.md

**Major components:**

| Component | Location | Responsibility |
|-----------|----------|---------------|
| `VPNManager` | VPNCore | `@Observable` source of truth; owns `[VPNConnection]`; must be `@MainActor` |
| `VPNConnection` | VPNCore | Per-connection state machine; owns `Process` + `SAMLServer`; state transitions dispatched to `@MainActor` |
| `SAMLServer` | VPNCore | `NWListener` TCP on `127.0.0.1:35001`; delivers SAML response via `CheckedContinuation` |
| `IPCServer` | VPNCore | `NWListener` Unix socket `daemon.sock`; parses CLI commands, calls `VPNManager` |
| `IPCClient` | VPNCore | `NWConnection` to `daemon.sock`; used by CLI `main.swift` |
| `StatusMenuView` | App | SwiftUI reads `VPNManager` via `@Environment`; no business logic |
| `aws-connect` CLI | CLI target | Arg parsing via `ArgumentParser`; delegates entirely to `IPCClient` |

**Key patterns:**
- `@State` (not `@StateObject`) to own `VPNManager` in the `App` struct
- `@Environment(VPNManager.self)` in child views (not `@EnvironmentObject`)
- All NW callbacks → `Task { @MainActor in }` before touching `VPNManager`
- `VPNConnection.run()` is an `async` `Task`; never block `@MainActor`
- Delete stale socket file before every `NWListener` bind

**Unresolved architectural question:** Whether `VPNCore` should be a dynamic framework (rpath embedding for unsigned CLI) or a static Swift Package target (avoids rpath entirely). Research flags this as MEDIUM confidence; a test build in Phase 1 should resolve it.

### From PITFALLS.md

**Top critical pitfalls:**

| Pitfall | Phase Risk | Prevention |
|---------|-----------|------------|
| sudo openvpn orphaned on app exit | VPN connection lifecycle | Track openvpn child PID via `--writepid` or `pgrep -P`; `SIGTERM` directly; disconnect all in `applicationWillTerminate` |
| NWListener cannot restart after cancel | SAML server + IPC socket | Keep SAML listener running for full session; delete stale socket file on startup |
| SAML HTTP body fragmented across TCP callbacks | SAML auth flow | Buffer `Data` accumulator until `Content-Length` bytes received; parse only complete body |
| @Observable mutated off main thread | VPN state + menu UI | Annotate `VPNManager` with `@MainActor`; all NW callbacks dispatch via `Task { @MainActor in }` |
| Credential temp file left on disk | VPN connection launch | Mode `0600`; `defer { try? FileManager.removeItem }` at openvpn launch; prefer `O_TMPFILE`/`mkstemp` unlink pattern |
| Unix socket path >104 bytes | IPC socket setup | Assert path length ≤ 103 bytes; fall back to `/tmp/aws-vpn-<hash>.sock` |

**Additional moderate pitfalls:**
- `MenuBarExtra .menu` style blocks run loop while open — do not attempt programmatic dismissal
- `MenuBarExtra .menu` does not re-render on open — rely on `@Observable` dependency tracking + consider 1–2 second polling
- Port 35001 conflict — surface clear error; do NOT fall back to random port (port is hardcoded in AWS SAML ACS URL)
- `LSUIElement` app has no default quit — Quit button with cleanup must be in initial scaffold

---

## Implications for Roadmap

### Suggested Phase Structure

**Phase 1: Foundation — App Scaffold + VPNCore Framework**

Rationale: Everything downstream links against VPNCore. Establishing the Xcode project structure, multi-target build, and the `@Observable VPNManager` wiring correctly removes all blocking dependencies for subsequent phases. The rpath vs. static library question (MEDIUM confidence) must be answered here before writing any code that depends on the choice.

Delivers:
- Xcode project with VPNCore, app target, CLI target
- `MenuBarExtra` + `LSUIElement` + Quit button (Pitfall 10 requires Quit in initial scaffold)
- `VPNManager @Observable @MainActor` skeleton
- Config loading/saving from `~/Library/Application Support/AWSVPNClient/configs/`
- Stale socket file cleanup on launch

Pitfalls to address: Pitfall 10 (no quit mechanism), Pitfall 14 (missing config directory), Anti-Pattern 2 (@StateObject with @Observable), Anti-Pattern 3 (global singleton).

Research flag: STANDARD PATTERNS — `MenuBarExtra` + `@Observable` wiring is well-documented; no additional research needed.

---

**Phase 2: VPN Connection Lifecycle — SAML + openvpn**

Rationale: This is the hardest and highest-risk phase. All critical pitfalls cluster here. The Rust predecessor provides a working reference implementation but the Swift translation requires careful async design. This phase must be stable before any dependent features (CLI, notifications, error display) are added.

Delivers:
- `SAMLServer` (`NWListener` TCP 35001) with proper body buffering
- `VPNConnection.run()` async flow: auth challenge → browser open → SAML response → openvpn spawn
- openvpn PID tracking + `SIGTERM` to child process (not sudo wrapper)
- Credential temp file with mode `0600` + `defer` cleanup
- Per-connection log files streaming from `stdout`
- `applicationWillTerminate` disconnects all tunnels
- `atexit` handler as safety net for crashes

Pitfalls to address: Pitfall 1 (orphaned openvpn), Pitfall 2 (NWListener restart), Pitfall 5 (SAML body fragmentation), Pitfall 6 (credential temp file), Pitfall 9 (port 35001 conflict), Pitfall 13 (blocking Process wait).

Research flag: NEEDS RESEARCH — openvpn PID tracking via `--writepid` vs. `pgrep -P` approach, and the `O_TMPFILE`/`mkstemp` unlink pattern in Swift, warrant a focused research pass before implementation.

---

**Phase 3: Menu UI — State Display + Config Management**

Rationale: With the connection lifecycle stable, the menu can be wired to real state. Config add/remove, inline state display, and error surfacing are all straightforward once `VPNManager` has reliable state. Pitfalls 4, 7, and 8 are addressed here.

Delivers:
- Config list with per-connection state indicator (Disconnected / Authenticating / Connected)
- Connection error surfaced in menu with retry affordance
- Add config via `NSOpenPanel`
- Remove config with confirmation
- Menu bar icon switching between `lock.fill` / `lock.open`

Pitfalls to address: Pitfall 4 (@Observable off-main-thread), Pitfall 7 (menu blocks run loop), Pitfall 8 (stale menu render).

Research flag: STANDARD PATTERNS — `@Observable` + `MenuBarExtra` rendering is documented; no research needed.

---

**Phase 4: Quality of Life — CLI, Notifications, Launch at Login**

Rationale: These features have no hard dependencies on each other and low implementation risk. They add meaningful value (CLI for scripting, notifications for background auth, launch at login for daily use) without touching the high-risk connection lifecycle.

Delivers:
- `IPCServer` (Unix socket) + `IPCClient` wiring
- `aws-connect` CLI with `connect`, `disconnect`, `status` subcommands
- System notifications on connect / disconnect / auth failure (`UNUserNotificationCenter`)
- Launch at login toggle via `SMAppService`
- "Open Log" menu item via `NSWorkspace.open`
- README: macOS 15+ Gatekeeper approval steps, NOPASSWD sudoers setup

Pitfalls to address: Pitfall 2 (stale socket on crash), Pitfall 3 (socket path length), Pitfall 11 (macOS Sequoia unsigned app).

Research flag: STANDARD PATTERNS — `SMAppService`, `UNUserNotificationCenter`, and `swift-argument-parser` patterns are well-documented.

---

### Feature-to-Phase Mapping

| Feature | Phase |
|---------|-------|
| MenuBarExtra scaffold + LSUIElement | 1 |
| VPNManager @Observable skeleton | 1 |
| Config persistence | 1 |
| Quit button with cleanup | 1 |
| SAML auth flow | 2 |
| openvpn subprocess + PID tracking | 2 |
| Per-connection log files | 2 |
| App termination cleanup | 2 |
| Config list with state indicators | 3 |
| Connection error in menu | 3 |
| Add / Remove config | 3 |
| Menu bar icon state | 3 |
| Companion CLI | 4 |
| System notifications | 4 |
| Launch at login | 4 |
| Open log from menu | 4 |
| README / deployment docs | 4 |

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Core framework choices (Swift 6.1, MenuBarExtra, @Observable, Network.framework) are well-documented with official sources. Only subprocess API (`swift-subprocess` vs `Foundation.Process`) has uncertainty — resolved in favor of `Process`. |
| Features | HIGH | Requirements are well-defined in the project brief; feature research confirms all table stakes with real-world VPN app references. Feature scope is narrow and appropriate for a personal tool. |
| Architecture | MEDIUM-HIGH | `@Observable` + `MenuBarExtra` wiring is HIGH confidence. VPNCore framework rpath/static-library choice is MEDIUM — needs early validation. NWListener raw HTTP parsing is MEDIUM — known pattern but requires careful testing. |
| Pitfalls | HIGH | All 6 critical pitfalls are grounded in filed bugs (SR-13918, FB13683957), official forum threads, and POSIX/BSD specifications. Mitigations are established. No speculation. |

**Overall confidence: HIGH**

**Gaps requiring attention:**

1. **VPNCore linking strategy** — dynamic framework with rpath vs. static Swift Package library. Research says MEDIUM confidence on the rpath approach for unsigned CLI tools. A Phase 1 spike is mandatory before committing to the project structure.

2. **openvpn PID tracking** — the `--writepid` flag approach is documented but behavior with `sudo` wrapping needs verification. The `pgrep -P` alternative works but adds process overhead. Phase 2 research spike recommended.

3. **SAML body parsing** — the Content-Length buffering approach is correct but 60-line raw HTTP parsing is error-prone. Consider a minimal test against a real AWS IdP (Okta/Azure AD) early in Phase 2 rather than after the full phase is built.

4. **macOS 15 Gatekeeper** — the workaround change (right-click Open no longer works) is documented but exact System Settings flow should be verified on a Sequoia machine before documenting in README.

---

## Sources (Aggregated)

**Apple Documentation:**
- SwiftUI MenuBarExtra — https://developer.apple.com/documentation/swiftui/menubarextra
- MenuBarExtraStyle — https://developer.apple.com/documentation/swiftui/menubarextrastyle
- NWListener — https://developer.apple.com/documentation/network/nwlistener
- Migrating from ObservableObject to @Observable — https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro

**Community / Blog:**
- @Observable performance over ObservableObject — https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/
- @Observable is not a drop-in for ObservableObject — https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/
- SettingsLink bug from MenuBarExtra — https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
- Build a macOS menu bar utility in SwiftUI — https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/
- NWListener Unix socket + CLI framework embedding — https://livefront.com/writing/how-to-add-a-dynamic-swift-framework-to-a-command-line-tool/

**Bugs / Issues:**
- NWListener cannot restart SR-13918 — https://github.com/apple/swift/issues/56316
- MenuBarExtra .menu no re-render on open FB13683957 — https://github.com/feedback-assistant/reports/issues/477
- macOS 104-byte Unix socket path limit — https://github.com/dotnet/runtime/issues/79503

**AWS Documentation:**
- AWS Client VPN SAML port 35001 — https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/federated-authentication.html
- AWS Client VPN SAML session duration — https://repost.aws/questions/QUy5fUEzd_T7-z8I-ngouLAQ/aws-client-vpn-maximum-vpn-session-duration

**Swift / Tooling:**
- swift-argument-parser — https://github.com/apple/swift-argument-parser
- swiftlang/swift-subprocess — https://github.com/swiftlang/swift-subprocess
- Swift 6.1 release — https://www.swift.org/blog/swift-6.1-released/
