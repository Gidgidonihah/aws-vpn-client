# Technology Stack

**Project:** AWS VPN Client — Swift macOS Menu Bar App
**Researched:** 2026-03-17
**Overall confidence:** HIGH for core framework choices; MEDIUM for subprocess API (actively evolving)

---

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Swift | 6.1 (Xcode 16.3) | Primary language | Swift 6's strict concurrency model catches data-race bugs at compile time — critical when UI state, subprocess I/O, and IPC handlers all touch the same `VPNManager`. Use Swift 6.1 strict mode from day one; don't defer the migration pain. |
| SwiftUI | macOS 13+ | Menu bar UI | `MenuBarExtra` is the only first-party, non-deprecated API for menu bar apps as of macOS 13+. It integrates natively with the App lifecycle, requires no AppDelegate boilerplate, and is the direction Apple is investing in. |
| Xcode | 16.3 | Build toolchain | Ships Swift 6.1. The minimum version that reliably handles `@Observable` and Swift 6 strict concurrency without known compiler regressions. |

### Menu Bar Scene

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `MenuBarExtra` (SwiftUI scene) | macOS 13+ | Menu bar entry point | Use `.menuBarExtraStyle(.menu)` — the app's primary UI is a flat list of config names with status indicators and actions. A dropdown menu is the correct UX, not a floating window. `menuBarExtraStyle(.window)` is appropriate only if you need sliders, text fields, or custom layouts; a VPN connection list does not. |
| `LSUIElement = YES` (Info.plist) | — | Suppress Dock icon | The standard mechanism to mark an app as a background agent. Set `Application is agent (UIElement)` to `YES` in the target's Info tab. This suppresses both the Dock icon and the app from appearing in the Cmd-Tab switcher. |

### State Management

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `@Observable` (Observation framework) | Swift 5.9 / macOS 14+ | `VPNManager` reactive state | `@Observable` tracks fine-grained property access — a view watching `.connections` will NOT re-render when `.isAuthenticating` changes. With `ObservableObject`/`@Published` it would. For a menu that shows per-connection status, this granularity eliminates spurious redraws. Requires macOS 14 (Sonoma). |
| `@ObservableObject` + `@Published` | Fallback | Same | Use only if the deployment target must remain macOS 13. The `@Observable` performance advantage is meaningful here; prefer bumping the minimum to 14 if acceptable. |

**Decision:** Target macOS 14+ to use `@Observable`. macOS 13 support buys nothing for this tool's audience (personal use, developer machine) and costs the cleaner concurrency story.

### Networking / IPC

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `Network.framework` / `NWListener` | macOS 10.15+ | Unix domain socket IPC server | The modern replacement for `CFSocket`/`GCDAsyncSocket`. `NWListener` with `NWEndpoint.unix` creates the daemon socket at `~/Library/Application Support/AWSVPNClient/daemon.sock`. Handles connection lifecycle, framing, and cancellation cleanly with Swift concurrency. |
| `Network.framework` / `NWListener` (TCP) | macOS 10.15+ | SAML HTTP server on port 35001 | Same API, different endpoint type. `NWListener(using: .tcp, on: 35001)` receives the SAML POST from the browser. No third-party HTTP library needed — raw TCP + manual HTTP response parsing for a single endpoint is 30 lines. |
| `NWConnection` | macOS 10.15+ | CLI → App IPC client | The companion CLI uses `NWConnection` to connect to the Unix socket and send JSON commands. Same framework, symmetric API. |

### Subprocess Management

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `Foundation.Process` | macOS 10+ | `sudo openvpn` subprocess | Use `Foundation.Process` (not `swift-subprocess`). The official `swiftlang/swift-subprocess` package requires Swift 6.1 minimum but was released in September 2025 with an unstable v0.1 API. For a tool targeting production stability, `Process` + `Pipe` + `FileHandle.readabilityHandler` (or `DispatchIO`) is battle-tested and handles the specific requirements: write credentials to a temp file, set `standardInput` from that file, stream `stdout`/`stderr` to a log file, and observe `terminationHandler`. |

### Project Structure

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Xcode workspace + 2 targets | Xcode 16.3 | `AWSVPNClient.app` + `aws-connect` CLI | A single `.xcworkspace` containing one `.xcodeproj` with two targets is the standard approach. A third `AWSVPNCore` framework target holds all shared logic (VPN manager, subprocess, IPC protocol types). Both the app and the CLI link this framework. No SPM package is needed — all code is internal to one repo. |
| `AWSVPNCore` static library target | — | Shared business logic | Subprocess management, config parsing, SAML flow, IPC message types, and `VPNManager` live here. The app target adds SwiftUI scenes; the CLI target adds `ArgumentParser` + socket client. This prevents duplication and keeps the core testable without a UI dependency. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `swift-argument-parser` | 1.x (Apple) | `aws-connect` CLI argument parsing | The canonical Apple-maintained CLI parsing library. Use it for the CLI target. Do NOT hand-roll `CommandLine.arguments` parsing — `ArgumentParser` provides help text, error messages, and subcommand dispatch for free. |
| `os.Logger` (OSLog) | macOS 11+ | Structured logging | Use `Logger(subsystem: "com.yourname.awsvpnclient", category: "vpnmanager")` throughout. Logs appear in Console.app (which users can open from the menu). `print()` is not observable post-launch; `os.Logger` is. |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Menu bar integration | `MenuBarExtra` | `NSStatusItem` (AppKit) | `NSStatusItem` is not deprecated but requires AppKit boilerplate and breaks the SwiftUI-only mental model. `MenuBarExtra` is the declared forward direction. Use `NSStatusItem` only if you hit a hard `MenuBarExtra` limitation (e.g., the known `SettingsLink` bug — not relevant here). |
| State management | `@Observable` | `ObservableObject`/`@Published` | `ObservableObject` causes whole-view re-renders on any published property change. `@Observable` tracks only properties read by each view body. Prefer it on macOS 14+. |
| HTTP / IPC server | `NWListener` (Network.framework) | Vapor, Hummingbird, GCDWebServer | Server frameworks are overkill for one HTTP endpoint and one Unix socket. Adding a dependency for 30 lines of networking introduces Swift version coupling, build time cost, and update maintenance. |
| Subprocess | `Foundation.Process` | `swiftlang/swift-subprocess` | `swift-subprocess` requires Swift 6.1 but is v0.1 (released Sept 2025) with an explicitly unstable API. `Process` is stable, well-documented, and sufficient for the requirements. Revisit after `swift-subprocess` reaches 1.0. |
| CLI parsing | `swift-argument-parser` | `CommandLine.arguments` | Hand-rolling argument parsing is error-prone and produces poor error messages. `ArgumentParser` is Apple-maintained and the community standard. |
| Concurrency | Swift Concurrency (`async`/`await`, `actor`) | GCD (`DispatchQueue`) | GCD bypasses Swift 6 data-race checking. Use `actor` for `VPNManager` (shared mutable state), `@MainActor` for all SwiftUI state mutations, and `async`/`await` throughout. Do not mix GCD and Swift Concurrency in new code. |

---

## Installation

```bash
# swift-argument-parser (via SPM, CLI target only)
# In Package.swift or Xcode: add package dependency
# https://github.com/apple/swift-argument-parser.git  from: "1.3.0"

# No other third-party dependencies. Everything else is system frameworks:
# - SwiftUI (Xcode built-in)
# - Network.framework (system)
# - Foundation (system)
# - OSLog (system)
```

**Build requirements:**
- macOS 14+ deployment target (for `@Observable`)
- Xcode 16.3 (ships Swift 6.1)
- Swift 6 language mode (`SWIFT_VERSION = 6` in build settings)

---

## Key API Quirks and Version Notes

### `MenuBarExtra` — `.menu` style limitations (HIGH confidence)
The `.menu` style enforces macOS menu rendering rules: `Button` styles are ignored (all buttons render as menu items), images in non-standard positions are dropped, and `Toggle`/`Slider` controls do not render. This is fine for a list of configs with connect/disconnect actions. If you need custom controls, switch to `.window` style, but be aware that `.window` style menus do not dismiss automatically when the user clicks outside — you must manage dismissal manually.

### `MenuBarExtra` — `SettingsLink` breakage (MEDIUM confidence, 2025 report)
As of early 2025, `SettingsLink` does not open a settings window reliably from within a `MenuBarExtra`. This project has no settings window, so this bug is not a blocker. If a preferences panel is added later, use `NSApp.sendAction` + activation policy juggling, not `SettingsLink`.

### `NWListener` Unix socket — non-sandboxed only (HIGH confidence)
Unix domain socket listeners at arbitrary filesystem paths (`~/Library/Application Support/...`) work correctly in non-sandboxed macOS apps. This project explicitly does not sign or sandbox the app, so this is not a concern. If the app is ever sandboxed, the socket path must move to the app's container directory.

### `@Observable` — macOS 14 minimum (HIGH confidence)
`@Observable` (the `Observation` framework macro) requires macOS 14 (Sonoma). If the deployment target stays at macOS 13 (Ventura), fall back to `ObservableObject`. Given this is a personal-use tool, bumping to macOS 14 is the pragmatic choice.

### `Foundation.Process` — pipe buffer deadlock (HIGH confidence)
Do NOT call `pipe.fileHandleForReading.readDataToEndOfFile()` synchronously for a long-running process like `openvpn`. The pipe buffer (typically 64KB on macOS) fills before the process exits, causing a deadlock. Use `FileHandle.readabilityHandler` on a background `DispatchQueue` to drain continuously, OR use `DispatchIO`. Set `process.standardOutput = pipe` and stream to a log file via the readability handler.

### Swift 6 strict concurrency + `NWListener` (MEDIUM confidence)
`NWListener` callbacks fire on its internal queue, not on the main actor. All state mutations in `newConnectionHandler` and `stateUpdateHandler` must be explicitly dispatched to `@MainActor` or handled inside an `actor`. Failing to do this will produce Swift 6 sendability errors at compile time — which is the desired behavior catching real bugs.

### `swift-argument-parser` + Swift 6 (HIGH confidence)
`swift-argument-parser` 1.3+ is fully Swift 6 compatible. Use `1.3.0` or later.

---

## Sources

- [SwiftUI MenuBarExtra — Apple Developer Docs](https://developer.apple.com/documentation/swiftui/menubarextra) — macOS 13+ availability
- [MenuBarExtraStyle — Apple Developer Docs](https://developer.apple.com/documentation/swiftui/menubarextrastyle) — .menu vs .window styles
- [Showing Settings from macOS Menu Bar Items (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — SettingsLink bug report
- [Migrating from ObservableObject to @Observable — Apple Developer Docs](https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro) — migration guidance
- [@Observable Macro performance increase over ObservableObject — Antoine van der Lee](https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/) — fine-grained re-render explanation
- [NWListener — Apple Developer Docs](https://developer.apple.com/documentation/network/nwlistener) — Network.framework API
- [Unix Domain Socket, NWListener — Apple Developer Forums](https://developer.apple.com/forums/thread/756756) — Unix socket IPC in Network.framework
- [Building a server-client application using Network Framework — RDerik](https://rderik.com/blog/building-a-server-client-application-using-apple-s-network-framework/) — NWListener TCP example
- [swiftlang/swift-subprocess — GitHub](https://github.com/swiftlang/swift-subprocess) — v0.1, Swift 6.1 required, Sept 2025 release
- [Running a Child Process with Standard Input and Output — Apple Developer Forums](https://developer.apple.com/forums/thread/690310) — Process + Pipe stdin pattern
- [Swift 6.1 Released — Swift.org](https://www.swift.org/blog/swift-6.1-released/) — Swift 6.1 in Xcode 16.3
- [Xcode 16.3 / Swift 6.1 — Apple Developer Weekly #224](https://www.ethanhuang13.com/p/224-en) — release confirmation
- [Build a macOS menu bar utility in SwiftUI — Nil Coalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — LSUIElement + MenuBarExtra walkthrough
- [swift-argument-parser — GitHub](https://github.com/apple/swift-argument-parser) — Apple-maintained CLI parsing
