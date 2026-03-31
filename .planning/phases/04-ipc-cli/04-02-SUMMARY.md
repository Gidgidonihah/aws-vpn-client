---
phase: 04-ipc-cli
plan: 02
subsystem: cli
tags: [unix-socket, posix, cli, darwin, swift6, ipc, json]

# Dependency graph
requires:
  - phase: 04-ipc-cli plan 01
    provides: IPCRequest, IPCResponse, IPCConfigStatus structs + formatStatusTable() in VPNCore; IPCServer socket at daemon.sock

provides:
  - aws-connect binary: connect/disconnect/status commands over Unix socket
  - POSIX socket client (no Network.framework) — synchronous, no RunLoop
  - Correct exit codes: 0 on success, 1 on error/bad args/app-not-running

affects: [end-users, scripting-workflows]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Darwin.socket(AF_UNIX, SOCK_STREAM, 0) + sockaddr_un copy via local var to avoid overlapping-access error"
    - "Synchronous POSIX CLI: no RunLoop, no dispatchMain, no Network.framework — read blocks until newline"
    - "sun_path copy: var sunPath = addr.sun_path + strncpy + addr.sun_path = sunPath (exclusive-access fix)"

key-files:
  created: []
  modified:
    - aws-connect/main.swift

key-decisions:
  - "Copied sun_path to local var before strncpy to satisfy Swift 6 exclusive access rule (overlapping inout error)"

# Metrics
duration: 8min
completed: 2026-03-31
---

# Phase 4 Plan 02: aws-connect CLI Implementation Summary

**Full POSIX Unix socket CLI replacing stub — sends JSON IPCRequest to daemon.sock, receives IPCResponse, prints status table or errors, exits with correct codes**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-31T20:08:48Z
- **Completed:** 2026-03-31T20:16:00Z
- **Tasks:** 1 of 2 completed (Task 2 is a human-verify checkpoint)
- **Files modified:** 1

## Accomplishments

- Replaced aws-connect stub with full 130-line implementation
- POSIX socket client: `Darwin.socket(AF_UNIX, SOCK_STREAM, 0)`, `sockaddr_un`, `Darwin.connect/read/write/close`
- Arg parsing switch: `aws-connect <name>` (connect), `--disconnect <name>`, `status`, usage-on-error
- JSON encode/decode: `JSONEncoder().encode(IPCRequest)` / `JSONDecoder().decode(IPCResponse.self)`
- `formatStatusTable()` called for status command (imported from VPNCore)
- IPC-05: "Start the AWSVPNClient menu bar app first" on socket connect failure
- D-04: silent exit 0 on connect/disconnect success
- D-05: all errors to stderr with exit 1
- Build: BUILD SUCCEEDED

## Task Commits

1. **Task 1: Implement aws-connect CLI** - `8bf57f8` (feat)
2. **Task 2: End-to-end IPC smoke test** - awaiting human verification

## Files Created/Modified

- `aws-connect/main.swift` — Full CLI implementation (was 6-line stub)

## Decisions Made

- Copied `addr.sun_path` to a local variable before `strncpy` to satisfy Swift 6 exclusive access rule. The original plan called for `withUnsafeMutablePointer(to: &addr.sun_path)` directly, but Swift 6 rejects that as overlapping access. Fixed inline.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 exclusive access on sun_path copy**
- **Found during:** Task 1 (first build attempt)
- **Issue:** `withUnsafeMutablePointer(to: &addr.sun_path)` + reading `addr.sun_path` for size in same expression — Swift 6 exclusive access error
- **Fix:** Copy `addr.sun_path` to `var sunPath` first, run `strncpy` on local, write back `addr.sun_path = sunPath`
- **Files modified:** `aws-connect/main.swift`
- **Commit:** `8bf57f8`

## Known Stubs

None — CLI is fully wired to the live Unix socket. No placeholder data.

## Next Steps (pending Task 2 human verification)

Human must:
1. Build and run the AWSVPNClient app
2. Verify socket exists: `ls -la ~/Library/Application\ Support/AWSVPNClient/daemon.sock`
3. Test raw socket with nc: `echo '{"cmd":"status"}' | nc -U ~/Library/Application\ Support/AWSVPNClient/daemon.sock`
4. Test CLI status, connect/disconnect, error-when-app-not-running, and bad args

---
*Phase: 04-ipc-cli*
*Completed: 2026-03-31*
