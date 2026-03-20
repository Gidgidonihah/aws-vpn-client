---
phase: 02-connection-lifecycle
plan: "02"
subsystem: VPNCore
tags: [tdd, config-parsing, auth-helpers, crv1, openvpn]
dependency_graph:
  requires: ["02-01"]
  provides: ["VPNConfigParser", "AuthHelpers", "CRV1Challenge"]
  affects: ["02-04"]
tech_stack:
  added: ["Security (SecRandomCopyBytes)"]
  patterns: ["pure-functions", "enum-namespace", "TDD red-green-refactor"]
key_files:
  created:
    - VPNCore/VPNConfigParser.swift
    - VPNCore/AuthHelpers.swift
  modified:
    - VPNCoreTests/VPNConfigParsingTests.swift
    - VPNCoreTests/AuthHelpersTests.swift
    - VPNCoreTests/CRV1ParserTests.swift
decisions:
  - "VPNConfigParser is a caseless enum (namespace) not a struct — no state needed, all static methods"
  - "urlEncodeSAML removes '+' from .urlQueryAllowed CharacterSet to match Rust urlencoding::encode behavior"
  - "parseCRV1Line uses components(separatedBy:) not split(separator:) for colon fields to preserve empty subsequences"
  - "AuthHelpers are top-level public functions, not wrapped in a type — matches Rust module-level function style"
metrics:
  duration_minutes: 3
  completed_date: "2026-03-20"
  tasks_completed: 2
  files_changed: 5
---

# Phase 02 Plan 02: Config Parsing and Auth Helpers Summary

Config parsing (VPNConfigParser) and all pure auth helper functions (randomHex, urlEncodeSAML, credential formatting, CRV1 parsing) implemented via TDD, porting Rust reference exactly — 21 tests pass covering all behaviors.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | VPNConfigParser — config file parsing and filtering (TDD) | eda4d01 | VPNCore/VPNConfigParser.swift, VPNCoreTests/VPNConfigParsingTests.swift |
| 2 | AuthHelpers — randomHex, URL encoding, credentials, CRV1 parsing (TDD) | a0fb65a | VPNCore/AuthHelpers.swift, VPNCoreTests/AuthHelpersTests.swift, VPNCoreTests/CRV1ParserTests.swift |

## What Was Built

**VPNConfigParser** (`VPNCore/VPNConfigParser.swift`):
- `parse(content: String) throws -> ParsedConfig` — extracts host, port, proto from "remote"/"proto" directives
- `parse(fileURL: URL) throws -> ParsedConfig` — thin file I/O wrapper
- `shouldStripLine(_:)` — strips auth-user-pass, auth-federate, auth-retry interact, and remote directives
- `field(lines:directive:index:)` — whitespace-split field extraction matching Rust's `field()` function
- `ParsedConfig` struct with `host`, `port`, `proto`, `filteredContent` — all `Sendable`

**AuthHelpers** (`VPNCore/AuthHelpers.swift`):
- `randomHex(byteCount:)` — SecRandomCopyBytes → lowercase hex, byteCount 12 produces 24 chars
- `urlEncodeSAML(_:)` — percent-encodes SAML response; removes '+' from allowed set so it encodes as %2B
- `dummyCredentials()` — returns `"N/A\nACS::35001\n"` for initial openvpn auth challenge
- `realCredentials(sid:urlEncodedSAML:)` — returns `"N/A\nCRV1::<sid>::<encoded>\n"` for sudo openvpn
- `parseCRV1Line(_:)` — finds AUTH_FAILED,CRV1, extracts URL via "https://" split and SID at colon-split field 6
- `findCRV1Line(in:)` — scans multiline openvpn output for first CRV1 line
- `CRV1Challenge` struct with `url` and `sid` — `Sendable`

## Test Results

```
VPNConfigParsingTests:  9 tests,  0 failures
AuthHelpersTests:       8 tests,  0 failures
CRV1ParserTests:        4 tests,  0 failures
Total:                 21 tests,  0 failures
```

## Decisions Made

1. **VPNConfigParser as caseless enum** — No state needed; all methods are static. Enum prevents instantiation and serves as a clean namespace, matching Swift conventions for utility containers.

2. **urlEncodeSAML removes '+' from CharacterSet** — `.urlQueryAllowed` leaves '+' unencoded (it's legal in query strings). The Rust `urlencoding::encode` crate always encodes '+' as `%2B`. Removing '+' from the allowed set achieves exact parity.

3. **components(separatedBy:) for CRV1 colon-split** — Swift's `split(separator:)` omits empty subsequences by default, which would shift field indices. `components(separatedBy:)` preserves empties, matching Rust's `split(':').collect()` behavior exactly.

4. **Top-level public functions for AuthHelpers** — The Rust reference uses module-level functions. Swift top-level functions in a module are equivalent. Wrapping in a type would add ceremony with no benefit.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written. Task 1 RED and GREEN were committed together (VPNConfigParser.swift didn't exist to separate compilation phases), but both phases were completed correctly.

## Self-Check: PASSED

All required files exist on disk. All commits verified in git log. All 21 tests pass with 0 failures.
