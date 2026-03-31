---
phase: 04-ipc-cli
plan: 01
subsystem: ipc
tags: [unix-socket, network-framework, codable, nwlistener, ipc, json, swift6]

# Dependency graph
requires:
  - phase: 03-menu-ui-config-management
    provides: StatusMenuView, VPNManager with configs/connections, ConnectionState enum
  - phase: 02-connection-lifecycle
    provides: VPNManager.connect/disconnect, SAMLServer pattern (NWListener @unchecked Sendable)
  - phase: 01-scaffold
    provides: VPNCore framework, AWSVPNClientApp entry point

provides:
  - IPCRequest/IPCResponse/IPCConfigStatus — Codable Sendable types in VPNCore shared by app + CLI
  - formatStatusTable() — aligned two-column output, alphabetical, no header (D-07/D-08/D-10)
  - ConnectionState.ipcLabel — string representation for IPC status responses
  - IPCServer — NWListener Unix domain socket server at ~/Library/Application Support/AWSVPNClient/daemon.sock
  - App wires IPCServer on launch via @State + .task modifier
affects: [04-02-cli]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "IPCServer: final class @unchecked Sendable + DispatchQueue + Task { @MainActor } — mirrors SAMLServer pattern exactly"
    - "Unix socket NWParameters: NWParameters() + NWProtocolTCP.Options() + requiredLocalEndpoint (NOT NWParameters.tcp)"
    - "Stale socket cleanup: FileManager.removeItem before listener.start() (allowLocalEndpointReuse is broken on macOS rdar://FB8658821)"
    - "IPC Codable structs in VPNCore (not App target) — CLI imports VPNCore and can reuse them"

key-files:
  created:
    - VPNCore/IPCMessage.swift
    - AWSVPNClient/IPCServer.swift
    - VPNCoreTests/IPCMessageTests.swift
  modified:
    - VPNCore/ConnectionState.swift
    - VPNCoreTests/ConnectionStateTests.swift
    - AWSVPNClient/AWSVPNClientApp.swift
    - AWSVPNClient.xcodeproj/project.pbxproj

key-decisions:
  - "IPCMessage.swift placed in VPNCore (not App target) — CLI imports VPNCore and avoids struct duplication"
  - "IPCServer in App target (not VPNCore) — CLI never instantiates a server; keeps NWListener out of CLI's framework surface"
  - "Task { @MainActor [weak self] in } bridges GCD NWConnection callbacks to @MainActor VPNManager — mirrors spawnSudoOpenvpn pattern"
  - "try? IPCServer(vpnManager: vpnManager) in .task — server failure (permission issue) should not crash app"

patterns-established:
  - "IPCServer pattern: final class @unchecked Sendable, private DispatchQueue, weak var vpnManager, Task @MainActor dispatch"
  - "Unix socket NWParameters: NWParameters() + transportProtocol = NWProtocolTCP.Options() + requiredLocalEndpoint = .unix(path:)"

requirements-completed: [IPC-01, IPC-04]

# Metrics
duration: 25min
completed: 2026-03-31
---

# Phase 4 Plan 01: IPC Message Types + IPCServer Summary

**Codable IPC types (IPCRequest/IPCResponse/IPCConfigStatus) in VPNCore shared framework plus NWListener Unix socket server in App target that dispatches connect/disconnect/status to VPNManager on @MainActor**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-03-31T19:30:00Z
- **Completed:** 2026-03-31T19:55:09Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- IPC message types (IPCRequest, IPCConfigStatus, IPCResponse) as Codable Sendable structs in VPNCore
- formatStatusTable() producing aligned two-column output sorted alphabetically with no header row (D-07/D-08/D-10)
- ConnectionState.ipcLabel covering all 5 cases including `failed: <msg>` (D-09)
- IPCServer using NWListener on Unix domain socket at ~/Library/Application Support/AWSVPNClient/daemon.sock with stale socket cleanup (IPC-01)
- App wires IPCServer as @State property initialized in .task modifier
- 15 unit tests all passing (10 IPCMessageTests + 5 ipcLabel ConnectionStateTests)

## Task Commits

Each task was committed atomically:

1. **Task 1: IPC message types + ConnectionState.ipcLabel + Wave 0 tests** - `4e259f7` (feat)
2. **Task 2: IPCServer + app integration** - `1da1e66` (feat)

_Note: Task 1 used TDD (RED tests written first, then GREEN implementation)_

## Files Created/Modified

- `VPNCore/IPCMessage.swift` — IPCRequest, IPCConfigStatus, IPCResponse structs + formatStatusTable()
- `VPNCore/ConnectionState.swift` — Added public var ipcLabel: String computed property
- `AWSVPNClient/IPCServer.swift` — NWListener Unix socket server, GCD → @MainActor dispatch
- `AWSVPNClient/AWSVPNClientApp.swift` — Added @State ipcServer + server startup in .task
- `VPNCoreTests/IPCMessageTests.swift` — 10 unit tests for IPC encode/decode/formatting
- `VPNCoreTests/ConnectionStateTests.swift` — 5 ipcLabel test cases added
- `AWSVPNClient.xcodeproj/project.pbxproj` — Updated via XcodeGen to include new files

## Decisions Made

- IPCMessage.swift placed in VPNCore so the CLI target (which imports VPNCore) can use the same structs without duplication
- IPCServer placed in App target (not VPNCore) — the CLI never instantiates a server; VPNCore should not carry NWListener as CLI surface area
- Used `try? IPCServer(vpnManager: vpnManager)` in .task — server init failure (e.g., permissions) should not crash the menu bar app
- Followed SAMLServer @unchecked Sendable + GCD + Task @MainActor pattern exactly for concurrency bridging

## Deviations from Plan

None — plan executed exactly as written. XcodeGen regeneration was required after creating new source files (standard project workflow, not a deviation).

## Issues Encountered

- IPCMessageTests.swift initially showed 0 test cases after creation because XcodeGen must be re-run to include new files in the Xcode project. Ran `xcodegen generate` after both Task 1 and Task 2 to keep the project file current.
- SAMLServer "Address already in use" warnings appear in test output — pre-existing issue, not caused by this plan. Port 35001 conflicts in the test environment. All tests pass regardless.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- IPC server-side foundation complete; ready for Plan 02 (CLI implementation)
- CLI (aws-connect/main.swift) can import VPNCore and use IPCRequest/IPCResponse/IPCConfigStatus directly
- Socket path available as `IPCServer.socketPath` but CLI should use same computed path (FileManager applicationSupportDirectory + AWSVPNClient/daemon.sock)
- formatStatusTable() is importable from VPNCore for CLI status output

---
*Phase: 04-ipc-cli*
*Completed: 2026-03-31*
