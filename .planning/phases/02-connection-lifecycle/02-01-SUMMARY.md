---
phase: 02-connection-lifecycle
plan: 01
subsystem: VPNCoreTests
tags: [xctest, test-infrastructure, vpnerror, wave-0]
dependency_graph:
  requires: []
  provides: [VPNCoreTests target, VPNError enum, test stub contracts for Wave 1+]
  affects: [02-02, 02-03, 02-04, 02-05]
tech_stack:
  added: [XCTest (VPNCoreTests target)]
  patterns: [stub-first TDD, XcodeGen scheme configuration, bundle.unit-test target]
key_files:
  created:
    - project.yml (VPNCoreTests target + AWSVPNClient scheme)
    - VPNCore/VPNError.swift
    - VPNCoreTests/Info.plist
    - VPNCoreTests/VPNConfigParsingTests.swift
    - VPNCoreTests/CRV1ParserTests.swift
    - VPNCoreTests/SAMLServerTests.swift
    - VPNCoreTests/ConnectionStateTests.swift
    - VPNCoreTests/AuthHelpersTests.swift
    - VPNCoreTests/VPNManagerTests.swift
    - AWSVPNClient.xcodeproj/xcshareddata/xcschemes/AWSVPNClient.xcscheme
  modified:
    - AWSVPNClient.xcodeproj/project.pbxproj
decisions:
  - "--writepid flag confirmed supported by installed openvpn binary at /opt/homebrew/sbin/openvpn — primary PID tracking strategy adopted, pgrep fallback not needed"
  - "Explicit schemes block required in project.yml — XcodeGen does not auto-associate unit test targets with the app scheme; test action would fail without it"
  - "xcodebuild test exits 65 (XCTest failures) not 0 — expected behavior for XCTFail stubs; test infrastructure is functional, not broken"
metrics:
  duration_seconds: 228
  completed_date: "2026-03-20"
  tasks_completed: 2
  files_created: 10
  files_modified: 1
---

# Phase 2 Plan 1: XCTest Infrastructure and VPNError Summary

XCTest target (VPNCoreTests) wired to AWSVPNClient scheme via explicit XcodeGen schemes block; VPNError enum created; 40 test stubs scaffold all Phase 2 requirements with 5 real passing ConnectionState tests.

## What Was Built

### VPNCoreTests Target (project.yml)
`VPNCoreTests` added as `bundle.unit-test` depending on `VPNCore`. An explicit `schemes:` block was required to associate the test target with the AWSVPNClient scheme — XcodeGen does not auto-attach unit tests without this.

### VPNError Enum (VPNCore/VPNError.swift)
Public `Error, Sendable, LocalizedError` enum with 7 cases covering all Phase 2 failure modes. Includes `shortDescription` computed property with 30-char truncation for menu display.

**Cases:** `configParseFailure(String)`, `authChallengeFailed(String)`, `samlResponseMissing`, `samlTimeout`, `connectionFailed(String)`, `alreadyAuthenticating`, `cancelled`

### Test Stub Files (VPNCoreTests/)

| File | Tests | Status |
|------|-------|--------|
| ConnectionStateTests.swift | 5 | All pass (real assertions) |
| VPNConfigParsingTests.swift | 9 | XCTFail stubs — Wave 1 |
| CRV1ParserTests.swift | 4 | XCTFail stubs — Wave 1 |
| SAMLServerTests.swift | 6 | XCTFail stubs — Wave 1 |
| AuthHelpersTests.swift | 8 | XCTFail stubs — Wave 1 |
| VPNManagerTests.swift | 8 | XCTFail stubs — Wave 2/3 |
| **Total** | **40** | **5 pass, 35 stubs** |

### --writepid Verification
`openvpn --help 2>&1 | grep -i writepid` returned: `--writepid file : Write main process ID to file.`

The installed binary at `/opt/homebrew/sbin/openvpn` supports `--writepid`. The primary PID tracking strategy from RESEARCH.md Pattern 5 is confirmed viable. Fallback to `pgrep -P` is not needed.

## Verification Results

```
xcodegen generate               -> Created project (SUCCESS)
xcodebuild build-for-testing    -> ** TEST BUILD SUCCEEDED **
grep "VPNCoreTests" project.yml -> VPNCoreTests: (target exists)
grep -r "XCTestCase" VPNCoreTests/ | wc -l -> 6
grep -r "import VPNCore" VPNCoreTests/ | wc -l -> 6
xcodebuild test (40 tests):
  - ConnectionStateTests: 5 passed
  - Other 5 files: 35 XCTFail stubs (expected)
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Added explicit schemes block to project.yml**
- **Found during:** Task 2 verification
- **Issue:** `xcodebuild test -scheme AWSVPNClient` returned "Scheme AWSVPNClient is not currently configured for the test action" — XcodeGen does not auto-associate `bundle.unit-test` targets with the app scheme
- **Fix:** Added `schemes:` block to project.yml with explicit `test.targets: [VPNCoreTests]` entry
- **Files modified:** project.yml, AWSVPNClient.xcodeproj/xcshareddata/xcschemes/AWSVPNClient.xcscheme
- **Commit:** cdf9fc5

## Self-Check: PASSED

All created files verified present:
- [x] VPNCore/VPNError.swift
- [x] VPNCoreTests/Info.plist
- [x] VPNCoreTests/ConnectionStateTests.swift
- [x] VPNCoreTests/VPNConfigParsingTests.swift
- [x] VPNCoreTests/CRV1ParserTests.swift
- [x] VPNCoreTests/SAMLServerTests.swift
- [x] VPNCoreTests/AuthHelpersTests.swift
- [x] VPNCoreTests/VPNManagerTests.swift
- [x] AWSVPNClient.xcodeproj/xcshareddata/xcschemes/AWSVPNClient.xcscheme

Commits verified:
- [x] 3d77d94: feat(02-01): add VPNCoreTests target, VPNError enum, and --writepid verification
- [x] cdf9fc5: feat(02-01): create Phase 2 test stub infrastructure in VPNCoreTests
