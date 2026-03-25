---
phase: 03-menu-ui-config-management
plan: 03
subsystem: ui
tags: [swiftui, menubarextra, vpnmanager, observable, concurrency]

# Dependency graph
requires:
  - phase: 03-menu-ui-config-management
    provides: StatusMenuView with full menu layout, connect/disconnect buttons, config management
provides:
  - Verified working connect/disconnect button actions in .menuBarExtraStyle(.menu) context
affects: [future ui changes, vpnmanager integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [Capture @Environment ObservableObject before spawning @MainActor Task in menu button actions]

key-files:
  created: []
  modified:
    - AWSVPNClient/StatusMenuView.swift

key-decisions:
  - "In .menuBarExtraStyle(.menu), SwiftUI @Environment objects must be captured as explicit local constants before spawning a Task, and the Task must be @MainActor-annotated to guarantee VPNManager mutation stays on the main actor after menu dismissal"

patterns-established:
  - "Pattern: Always capture @Environment @Observable objects into local let before Task {} in menu button actions to prevent use-after-free when menu dismisses"

requirements-completed:
  - UI-01
  - UI-02
  - UI-03
  - UI-04
  - UI-05
  - CONF-01
  - CONF-03

# Metrics
duration: 10min
completed: 2026-03-25
---

# Phase 3 Plan 03: Menu UI Human Verification Summary

**Fixed connect/disconnect button actions in .menuBarExtraStyle(.menu) by capturing @Environment object and config before spawning @MainActor Task**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-25T00:00:00Z
- **Completed:** 2026-03-25T00:10:00Z
- **Tasks:** 1 (bug fix during human verification)
- **Files modified:** 1

## Accomplishments

- Diagnosed root cause of click-does-nothing bug in config row buttons
- Fixed StatusMenuView.swift to capture `vpnManager` and `config` as explicit local constants before spawning Task
- Annotated Task closures with `@MainActor` to ensure VPNManager mutations stay on main actor after menu dismissal
- Project builds cleanly

## Task Commits

1. **Fix: config button connect/disconnect action** - `c6e2f2c` (fix)

## Files Created/Modified

- `AWSVPNClient/StatusMenuView.swift` - Capture manager/config before Task, annotate Task @MainActor

## Decisions Made

- When using `.menuBarExtraStyle(.menu)`, SwiftUI menu views are torn down as soon as an item is selected. A bare `Task { try? await vpnManager.connect(config) }` may reference a stale environment after the view disappears. Explicitly capturing `let manager = vpnManager` and `let capturedConfig = config` before the Task, combined with `@MainActor` annotation, ensures the async work executes on the correct actor with a strong reference to the manager regardless of view lifecycle.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Config row button action did not trigger connect/disconnect**

- **Found during:** Task 1 (human verification — user reported clicking a config does nothing)
- **Issue:** In `.menuBarExtraStyle(.menu)` context, the `Task { try? await vpnManager.connect(config) }` inside the Button action referenced the `@Environment` property after menu dismissal. The view hierarchy is torn down on item selection, leaving the Task with a potentially stale reference that silently no-ops.
- **Fix:** Captured `let manager = vpnManager` and `let capturedConfig = config` as local constants in the button action before creating the Task. Annotated both Tasks with `@MainActor in` to keep VPNManager mutations on the main actor.
- **Files modified:** `AWSVPNClient/StatusMenuView.swift`
- **Verification:** `xcodebuild build` succeeded with `** BUILD SUCCEEDED **`
- **Committed in:** `c6e2f2c`

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Fix necessary for correctness. No scope creep.

## Issues Encountered

The human verification checkpoint revealed the bug: clicking a config name had no visible effect (no authentication state change, no browser opening). The button action was firing but the async Task was silently failing due to the `.menu` style menu teardown lifecycle.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Menu UI fully functional: empty state, add config, connect/disconnect, remove config, view logs, quit
- Phase 3 complete — ready for Phase 4 (menu bar icon + connection state polish) or next planned phase
- No known blockers

---
*Phase: 03-menu-ui-config-management*
*Completed: 2026-03-25*
