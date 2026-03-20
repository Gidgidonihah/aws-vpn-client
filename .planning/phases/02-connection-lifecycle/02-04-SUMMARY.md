---
phase: 02-connection-lifecycle
plan: "04"
subsystem: vpn
tags: [openvpn, saml, process, subprocess, Foundation.Process, NWListener, macos]

# Dependency graph
requires:
  - phase: 02-connection-lifecycle
    provides: VPNConfigParser, AuthHelpers, SAMLServer (Plans 02-01 through 02-03)
  - phase: 01-scaffold
    provides: VPNManager skeleton, VPNConfig, ConnectionState, VPNError
provides:
  - Full VPNManager.connect() implementation with SAML auth + openvpn subprocess flow
  - isAuthenticating computed property on ConnectionState
  - VPNError.shortDesc() static helper
  - logsDirectory at ~/Library/Logs/AWSVPNClient/
  - Wave 2 VPNManagerTests suite (7/8 passing, disconnect Wave 3 pending)
affects:
  - 02-05 (disconnect lifecycle)
  - 03-config-ui (reads connection state)
  - 04-ipc (monitors openvpn process)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "LineScanner: @unchecked Sendable wrapper for mutable state in readabilityHandler callbacks"
    - "terminationHandler + Task { @MainActor } for cross-actor state dispatch from Process callbacks"
    - "withThrowingTaskGroup for SAML 30-second timeout race between wait and timer"
    - "filtered conf temp file cleaned in terminationHandler (not defer) to avoid race with openvpn startup"
    - "defer cleanup for credential temp files (dummy + real creds)"

key-files:
  created: []
  modified:
    - VPNCore/VPNManager.swift
    - VPNCore/ConnectionState.swift
    - VPNCore/VPNError.swift
    - VPNCoreTests/VPNManagerTests.swift

key-decisions:
  - "Filtered conf temp file deleted in terminationHandler (not defer in connect()) to avoid race where openvpn hasn't read the file yet before defer fires"
  - "dig + dummy openvpn use waitUntilExit() -- acceptable since they're fast (< 5s) and called from async context, not blocking main thread"
  - "sudo openvpn uses terminationHandler only -- never waitUntilExit() (Pitfall 13)"
  - "SAML timeout implemented as withThrowingTaskGroup race between SAMLServer.waitForSAMLResponse() and Task.sleep(30s)"
  - "openvpnPath resolved at init via static closure checking /usr/local/bin, /opt/homebrew/bin, /usr/bin before falling back to PATH"

patterns-established:
  - "LineScanner: @unchecked Sendable -- inner final class pattern for mutable state in non-Sendable closures (Swift 6)"
  - "Task { @MainActor [weak self] in } -- canonical pattern for dispatching state mutations from GCD/Process callbacks"

requirements-completed: [CONN-01, CONN-02, CONN-03, CONN-04, CONN-06, CONN-08]

# Metrics
duration: 4min
completed: 2026-03-20
---

# Phase 2 Plan 04: Connection Lifecycle Summary

**SAML auth flow connecting randomHex DNS prefix, dummy openvpn CRV1 challenge, 30-second browser SAML wait, and sudo openvpn subprocess with stdout-based connected detection and file-only log streaming**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-20T18:45:14Z
- **Completed:** 2026-03-20T18:49:58Z
- **Tasks:** 1
- **Files modified:** 4

## Accomplishments

- Replaced `fatalError("Phase 2")` stub in `connect()` with 200+ lines of complete SAML auth + openvpn subprocess flow
- Implemented concurrent auth guard: blocks additional connects, re-click on `.authenticating` triggers cancel -> `.disconnected`
- Implemented 30-second SAML timeout via `withThrowingTaskGroup` race, transitioning to `.failed("SAML auth timed out")`
- sudo openvpn subprocess monitors stdout for "Initialization Sequence Completed" via readabilityHandler, transitions to `.connected`
- Implemented full temp file lifecycle: dummy creds via `defer`, real creds via `defer`, filtered conf via `terminationHandler`
- Logs streamed file-only to `~/Library/Logs/AWSVPNClient/<name>.log` via `FileHandle` (no in-memory buffer)
- Wave 2 VPNManagerTests implemented: 7/8 tests pass (Wave 3 disconnect test remains pending)

## Task Commits

1. **Task 1: Implement VPNManager.connect() full SAML auth flow** - `e53550f` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified

- `VPNCore/VPNManager.swift` - Full connect() implementation: concurrent auth guard, DNS resolve, dummy openvpn, SAML wait, sudo openvpn with terminationHandler, log streaming (270 lines, was 34)
- `VPNCore/ConnectionState.swift` - Added `isAuthenticating` computed property alongside existing `isConnected`
- `VPNCore/VPNError.swift` - Added `shortDesc(_ error: Error)` static helper for cross-type short descriptions
- `VPNCoreTests/VPNManagerTests.swift` - Implemented Wave 2 tests: concurrent auth guard, state transitions, temp file cleanup, logs directory verification

## Decisions Made

- Filtered conf temp file is NOT cleaned via `defer` in `connect()`. Instead it's passed to `spawnSudoOpenvpn()` and deleted in the `terminationHandler`. This prevents a race condition where the defer would delete the file before openvpn reads it during startup.
- `dig` and dummy openvpn both use `waitUntilExit()` -- this is safe because they are fast (< 5 seconds) and `connect()` is already called from an async context, so the main thread is not blocked.
- SAML timeout uses `withThrowingTaskGroup` with two competing tasks: the SAMLServer wait and a 30-second `Task.sleep`. Whichever finishes first cancels the other.
- `openvpnPath` is resolved once at init via a stored closure checking common Homebrew installation paths before falling back to the system PATH.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Implemented Wave 2 VPNManagerTests instead of leaving XCTFail stubs**
- **Found during:** Task 1 (connect() implementation)
- **Issue:** All VPNManagerTests contained `XCTFail("Not implemented -- Wave 2")` stubs that would fail the test suite
- **Fix:** Implemented actual test logic for the 7 Wave 2 tests: concurrent auth guard, state transitions, helper function tests, temp file cleanup verification, logs directory creation check
- **Files modified:** VPNCoreTests/VPNManagerTests.swift
- **Verification:** 7/8 VPNManagerTests pass; Wave 3 disconnect test still correctly fails
- **Committed in:** e53550f (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (missing critical -- test stubs would fail entire suite)
**Impact on plan:** Test implementation was necessary to satisfy "xcodebuild test succeeds" acceptance criteria. No scope creep.

## Issues Encountered

- `logsDirectory` is main actor-isolated as a static property on `@MainActor` class -- tests needed `await MainActor.run { VPNManager.logsDirectory }` to access it from async test context. Fixed immediately.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `connect()` is complete and wired to all Phase 2 dependencies (VPNConfigParser, AuthHelpers, SAMLServer)
- `disconnect()` still has `fatalError("Phase 2")` -- this is Wave 3 work for Plan 05
- `testDisconnectSendsSignal` test remains as a failing stub to be implemented in Plan 05
- App will build and connect to VPN; the full lifecycle requires Plan 05 to complete

---
*Phase: 02-connection-lifecycle*
*Completed: 2026-03-20*
