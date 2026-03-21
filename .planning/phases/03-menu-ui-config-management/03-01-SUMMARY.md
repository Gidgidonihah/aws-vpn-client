---
phase: 03-menu-ui-config-management
plan: 01
subsystem: api
tags: [swift, vpn, filemanager, xcode, unit-tests, tdd]

requires:
  - phase: 02-connection-lifecycle
    provides: VPNManager, VPNConfig, ConnectionState types with connect/disconnect lifecycle

provides:
  - ConnectionState.isActive computed property (true for connected/authenticating/disconnecting)
  - VPNManager.loadConfigs() — scans configsDirectory for .conf files, populates sorted array
  - VPNManager.addConfig(from:) — copies file into configsDirectory, updates array, handles overwrite
  - VPNManager.removeConfig(_:) — trashes file, cleans configs array, clears connections entry
  - Unit tests for all four new APIs (VPNManagerTests Phase 3 section)

affects:
  - 03-02 (StatusMenuView will call these methods)
  - Any future plan that lists or manages .conf files

tech-stack:
  added: []
  patterns:
    - "TDD RED/GREEN in Swift: compile stubs added to achieve RED compile state, replaced with real impl for GREEN"
    - "localizedCompare for alphabetical sort of config names"
    - "FileManager.trashItem for safe non-destructive config removal"
    - "zzz-test- prefix convention for test files that write into real app directories"

key-files:
  created:
    - VPNCoreTests/VPNManagerTests.swift (Phase 3 section added)
  modified:
    - VPNCore/ConnectionState.swift
    - VPNCore/VPNManager.swift

key-decisions:
  - "TDD in Swift requires compile stubs for RED phase — added no-op stubs so isActive test could run before real implementations"
  - "loadConfigs() called at end of init() so configs array is populated on startup without explicit caller burden"
  - "addConfig uses try? FileManager.default.removeItem before copyItem for silent overwrite (plan decision)"
  - "addConfig includes createDirectory guard to handle directory deletion edge case (Pitfall 14)"
  - "removeConfig uses trashItem not NSWorkspace.recycle — simpler, synchronous, no AppKit dependency in VPNCore"

patterns-established:
  - "Config tests use zzz-test- prefix to coexist with real configs in configsDirectory without collision"
  - "cleanupTestConfigs() wraps FileManager cleanup in Task { @MainActor } to respect actor isolation"

requirements-completed: [CONF-01, CONF-02, CONF-03, CONF-04]

duration: 4min
completed: 2026-03-20
---

# Phase 3 Plan 01: Config Lifecycle Methods Summary

**VPNManager config CRUD with TDD: loadConfigs/addConfig/removeConfig plus ConnectionState.isActive, 12/12 tests passing**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-20T18:23:05Z
- **Completed:** 2026-03-20T18:27:11Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added `isActive` computed property to `ConnectionState` — returns true for connected/authenticating/disconnecting states
- Implemented `loadConfigs()`, `addConfig(from:)`, `removeConfig(_:)` on `VPNManager` with full TDD cycle
- `loadConfigs()` now called automatically in `init()` so the configs array is populated at startup
- 5 new unit tests added, all 12 VPNManagerTests pass with 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Add isActive + failing config management tests (RED)** - `da2da31` (test)
2. **Task 2: Implement loadConfigs, addConfig, removeConfig (GREEN)** - `3209339` (feat)

## Files Created/Modified

- `VPNCore/ConnectionState.swift` - Added `isActive` computed property
- `VPNCore/VPNManager.swift` - Added loadConfigs/addConfig/removeConfig + init call
- `VPNCoreTests/VPNManagerTests.swift` - Added Phase 3 section with 5 new tests + cleanupTestConfigs()

## Decisions Made

- Added compile stubs in Task 1 to achieve proper RED state in Swift (file must compile for any tests to run)
- `addConfig` removes existing file before `copyItem` to silently overwrite (CONTEXT.md decision)
- `removeConfig` uses `FileManager.trashItem` (not `NSWorkspace.recycle`) — synchronous, no AppKit dependency in VPNCore
- `loadConfigs()` called at end of `init()` so callers never need to call it explicitly after construction

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added compile stubs to VPNManager for RED phase**
- **Found during:** Task 1 (RED phase test writing)
- **Issue:** Swift requires compilation to succeed before any test can run; methods that don't exist cause compile errors not runtime failures, preventing even `testIsActiveProperty` from running
- **Fix:** Added no-op/throw stub implementations for `loadConfigs`, `addConfig`, `removeConfig` so the test file compiled; stubs cause runtime failures in config tests (true RED) while `testIsActiveProperty` passes
- **Files modified:** `VPNCore/VPNManager.swift`
- **Verification:** `testIsActiveProperty` passed; `testLoadConfigsSorted` failed at assertion level
- **Committed in:** `da2da31` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — Swift compilation requirement for TDD RED phase)
**Impact on plan:** Necessary to achieve proper RED state in compiled language. No scope creep. Stubs replaced completely in Task 2.

## Issues Encountered

None beyond the Swift compilation requirement described above.

## Next Phase Readiness

- All config lifecycle methods available for Plan 02 (StatusMenuView) to call
- `VPNManager.loadConfigs()` / `addConfig(from:)` / `removeConfig(_:)` are `public` and `@MainActor`-safe
- `ConnectionState.isActive` available for menu item state indicators

---
*Phase: 03-menu-ui-config-management*
*Completed: 2026-03-20*

## Self-Check: PASSED

- VPNCore/ConnectionState.swift: FOUND
- VPNCore/VPNManager.swift: FOUND
- VPNCoreTests/VPNManagerTests.swift: FOUND
- .planning/phases/03-menu-ui-config-management/03-01-SUMMARY.md: FOUND
- Commit da2da31 (RED): FOUND
- Commit 3209339 (GREEN): FOUND
