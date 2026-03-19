---
phase: 01-scaffold
plan: 02
subsystem: ui
tags: [swift, swiftui, menubarextra, observable, vpncore, macos]

requires:
  - phase: 01-scaffold/01-01
    provides: Three-target Xcode project with VPNCore framework embedding and rpath linking

provides:
  - VPNConfig model (Identifiable, Hashable, Sendable) in VPNCore
  - ConnectionState enum (5 cases, isConnected computed property) in VPNCore
  - VPNManager (@Observable @MainActor) skeleton in VPNCore — importable by app and CLI
  - Config directory creation at ~/Library/Application Support/AWSVPNClient/configs/ on first launch
  - MenuBarExtra with live lock.fill/lock.open icon switching based on isAnyConnected
  - StatusMenuView with "No configs" placeholder and Quit button
  - Functional menu bar agent shell — Phase 2 fills with real VPN logic

affects: [02-menubar, 03-config-io, 04-vpn-engine]

tech-stack:
  added: [Observation framework (@Observable), NSApplication.shared.terminate]
  patterns:
    - "@Observable @MainActor class — NOT ObservableObject, avoids @StateObject in App struct"
    - "@State private var vpnManager = VPNManager() — requires @MainActor on App struct (Swift 6)"
    - "@Environment(VPNManager.self) — Observation-framework injection (NOT @EnvironmentObject)"
    - "fatalError(Phase N) stubs — marks unimplemented async throws methods for future phases"
    - "static let configsDirectory with createDirectory in init() — idempotent, safe on every launch"

key-files:
  created:
    - VPNCore/VPNConfig.swift
    - VPNCore/ConnectionState.swift
    - VPNCore/VPNManager.swift
    - AWSVPNClient/StatusMenuView.swift
  modified:
    - AWSVPNClient/AWSVPNClientApp.swift
    - aws-connect/main.swift
    - AWSVPNClient.xcodeproj/project.pbxproj

key-decisions:
  - "ConnectionState uses case failed(String) (not Error) for clean Sendable conformance under Swift 6 strict concurrency"
  - "ConnectionState does NOT conform to Equatable — isConnected computed property is sufficient for Phase 1"
  - "VPNManager.init() creates config directory inline (try?) — idempotent, no separate setup step needed"
  - "@MainActor on AWSVPNClientApp struct required to resolve Swift 6 error when @State initializes @MainActor-isolated class"

patterns-established:
  - "Pattern: All VPNCore public API uses explicit public modifier — required for cross-module access from app and CLI"
  - "Pattern: lock.fill (connected) / lock.open (disconnected) — menu bar icon convention for this app"
  - "Pattern: Quit button mandatory in LSUIElement apps — no Cmd-Q, no Dock context menu"

requirements-completed: [SCAF-01, SCAF-02]

duration: ~30min
completed: 2026-03-19
---

# Phase 1 Plan 02: VPNCore Types and MenuBarExtra Shell Summary

**@Observable @MainActor VPNManager with VPNConfig/ConnectionState types, MenuBarExtra lock icon switching, and config directory creation — functional menu bar agent shell ready for Phase 2**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-03-19T~14:45:00Z
- **Completed:** 2026-03-19T~21:30:00Z
- **Tasks:** 3 (2 auto + 1 human-verify)
- **Files modified:** 7

## Accomplishments

- VPNCore exports three public types: VPNConfig (Identifiable, Hashable, Sendable), ConnectionState (5-case enum, Swift 6 Sendable), and VPNManager (@Observable @MainActor skeleton)
- MenuBarExtra wired with live icon switching — lock.fill when any config connected, lock.open otherwise
- Config directory ~/Library/Application Support/AWSVPNClient/configs/ created idempotently on every launch
- App runs as LSUIElement (no Dock icon), shows "No configs" placeholder, Quit button terminates cleanly
- Human verification passed: lock.open icon visible in menu bar, no Dock icon, Quit button works

## Task Commits

Each task was committed atomically:

1. **Task 1: Create VPNCore types and VPNManager skeleton** — `363e7b6` (feat)
2. **Task 2: Wire MenuBarExtra with VPNManager and StatusMenuView** — included in scaffold (files confirmed correct on disk, no net diff)
3. **Task 3: Verify menu bar app launches correctly** — human verification approved (no code changes)

**Plan metadata:** (docs commit — see final commit)

## Files Created/Modified

- `VPNCore/VPNConfig.swift` — Identifiable, Hashable, Sendable struct with UUID id, name derived from filename, fileURL
- `VPNCore/ConnectionState.swift` — 5-case enum (disconnected, authenticating, connected, disconnecting, failed(String)), isConnected computed property
- `VPNCore/VPNManager.swift` — @Observable @MainActor class; configs/connections/isAnyConnected; configsDirectory static; createDirectory in init(); connect/disconnect stubs with fatalError
- `AWSVPNClient/AWSVPNClientApp.swift` — @MainActor App struct, @State VPNManager, MenuBarExtra with lock icon switching, .menuBarExtraStyle(.menu)
- `AWSVPNClient/StatusMenuView.swift` — @Environment(VPNManager.self), "No configs" placeholder, Quit button with NSApplication.shared.terminate(nil)
- `aws-connect/main.swift` — Updated to remove vpnCoreVersion reference (Placeholder.swift deleted)
- `AWSVPNClient.xcodeproj/project.pbxproj` — Regenerated to remove Placeholder.swift reference

## Decisions Made

- `ConnectionState` uses `case failed(String)` instead of `case failed(Error)` for clean `Sendable` conformance under Swift 6 strict concurrency — Error is not Sendable
- `ConnectionState` does not conform to `Equatable` — the `isConnected` computed property is all Phase 1 needs; pattern-matching `if case .connected` handles the rest
- `@MainActor` placed on `AWSVPNClientApp` struct (not just VPNManager) to resolve Swift 6 compile error where `@State` initializes a `@MainActor`-isolated class from non-isolated context
- Config directory creation is inline in `VPNManager.init()` using `try?` — no separate "first launch" setup required; createDirectory with withIntermediateDirectories is idempotent

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria met.

## Issues Encountered

None — build succeeded, human verification passed on first run.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VPNCore framework is the typed foundation all subsequent phases import — VPNConfig, ConnectionState, VPNManager are all public and available
- Phase 2 (VPN engine) can implement `connect()` and `disconnect()` by replacing the `fatalError("Phase 2")` stubs
- Phase 3 (config I/O) can use `VPNManager.configsDirectory` as the canonical path and populate `configs: [VPNConfig]`
- Phase 4 (CLI) can import VPNCore and use all public types — aws-connect/main.swift already imports VPNCore

---
*Phase: 01-scaffold*
*Completed: 2026-03-19*
