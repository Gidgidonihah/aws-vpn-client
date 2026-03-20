---
phase: 02-connection-lifecycle
plan: 03
subsystem: auth
tags: [nwlistener, network-framework, saml, checkedcontinuation, tdd, swift6]

# Dependency graph
requires:
  - phase: 02-connection-lifecycle
    provides: VPNError enum with samlResponseMissing case (from plan 01)
provides:
  - SAMLServer: long-lived NWListener on port 35001 wrapping CheckedContinuation per auth cycle
  - extractSAMLResponse: URL-encoded body parser handling base64 = padding
  - parseContentLength: case-insensitive HTTP Content-Length header parser
  - HTTP body accumulation loop (Pitfall 5 mitigation)
affects: [02-connection-lifecycle, VPNManager connect flow, SAML auth]

# Tech tracking
tech-stack:
  added: [Network.framework NWListener, Network.framework NWConnection]
  patterns:
    - "@unchecked Sendable final class with DispatchQueue-serialized mutable state"
    - "Long-lived NWListener (never cancelled) with per-auth CheckedContinuation"
    - "HTTP body accumulation: receive loop until Content-Length bytes buffered"

key-files:
  created:
    - VPNCore/SAMLServer.swift
  modified:
    - VPNCoreTests/SAMLServerTests.swift

key-decisions:
  - "SAMLServer is a final class (not actor) — NWListener callbacks fire on GCD queue, CheckedContinuation is not Sendable; @unchecked Sendable with private DispatchQueue serializes all state"
  - "Both newConnectionHandler and stateUpdateHandler set before listener.start() (Pitfall 12)"
  - "extractSAMLResponse uses dropFirst().joined(separator: =) to preserve base64 = padding in SAMLResponse values"
  - "parseContentLength and extractSAMLResponse use internal (not private) visibility for @testable import access in unit tests"

patterns-established:
  - "Pattern: Long-lived NWListener with per-auth CheckedContinuation — one SAMLServer instance started at app init, waitForSAMLResponse() installs a fresh continuation each auth cycle"
  - "Pattern: TDD for static helper methods — extractSAMLResponse and parseContentLength tested directly via @testable import without needing TCP integration test"

requirements-completed: [CONN-02]

# Metrics
duration: 2min
completed: 2026-03-20
---

# Phase 2 Plan 3: SAMLServer Summary

**Long-lived NWListener on port 35001 wrapping per-auth CheckedContinuation with body accumulation and URL-encoded SAMLResponse extraction**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-20T18:39:59Z
- **Completed:** 2026-03-20T18:41:09Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments

- SAMLServer.swift: long-lived NWListener started at init, never cancelled, mitigating EADDRINUSE on auth retry (Pitfall 2)
- waitForSAMLResponse() installs a fresh CheckedContinuation per auth cycle — suspends caller until SAML POST arrives or cancelCurrentWait() is called
- HTTP body accumulation loop continues until Content-Length bytes buffered, handling large IdP payloads (Pitfall 5)
- extractSAMLResponse handles base64 `=` padding by rejoining split parts with `=`
- HTTP 200 "safe to close this window" response sent before continuation is resumed
- All 6 SAMLServerTests pass: extraction, padding, nil cases, content-length parsing, case-insensitivity

## Task Commits

Each TDD phase committed atomically:

1. **RED — Failing SAMLServerTests** - `4b232e6` (test)
2. **GREEN — SAMLServer implementation** - `46886d1` (feat)

## Files Created/Modified

- `VPNCore/SAMLServer.swift` - Long-lived NWListener wrapper with CheckedContinuation signaling, body accumulation, HTTP response, and URL-encoded SAML extraction (126 lines)
- `VPNCoreTests/SAMLServerTests.swift` - 6 unit tests for static helpers: extractSAMLResponse and parseContentLength

## Decisions Made

- `SAMLServer` is `final class: @unchecked Sendable` — not an `actor`, because NWListener callbacks fire on a GCD queue and `CheckedContinuation` is not `Sendable`. A private `DispatchQueue` serializes all access to `continuation`.
- `extractSAMLResponse` and `parseContentLength` have `internal` (not `private`) visibility so tests can call them directly via `@testable import VPNCore` without needing a live TCP server.
- `extractSAMLResponse` uses `kv.dropFirst().joined(separator: "=")` to handle base64 `=` padding in SAML values that would otherwise be split by `components(separatedBy: "=")`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SAMLServer is ready to be instantiated in VPNManager.init() and used in the connect() flow (plan 02-04/05)
- waitForSAMLResponse() integrates with the 30-second timeout Task from Pattern 2
- cancelCurrentWait() provides the cancellation path for auth timeout and user-initiated cancel

## Self-Check: PASSED

All files found, all commits verified.

---
*Phase: 02-connection-lifecycle*
*Completed: 2026-03-20*
