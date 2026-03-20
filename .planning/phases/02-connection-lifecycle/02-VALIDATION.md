---
phase: 2
slug: connection-lifecycle
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-20
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in) — no external framework needed |
| **Config file** | `project.yml` — Wave 0 adds `VPNCoreTests` target |
| **Quick run command** | `xcodebuild test -scheme AWSVPNClient -only-testing:VPNCoreTests -destination 'platform=macOS' 2>&1 \| grep -E 'PASS\|FAIL\|error:'` |
| **Full suite command** | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' 2>&1 \| tail -20` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite green + manual integration checks for CONN-04, CONN-05, CONN-08
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| Wave 0 setup | 02-01 | 0 | CONN-01..08 | infra | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS'` | ❌ Wave 0 | ⬜ pending |
| CRV1 parsing | 02-01 | 1 | CONN-02 | unit | `xcodebuild test -only-testing:VPNCoreTests/CRV1ParserTests` | ❌ Wave 0 | ⬜ pending |
| SAML extraction | 02-01 | 1 | CONN-02 | unit | `xcodebuild test -only-testing:VPNCoreTests/SAMLServerTests/testExtractSAMLResponse` | ❌ Wave 0 | ⬜ pending |
| randomHex length | 02-01 | 1 | CONN-02 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testRandomHexLength` | ❌ Wave 0 | ⬜ pending |
| URL encoding + | 02-01 | 1 | CONN-02 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testURLEncodingPlusChar` | ❌ Wave 0 | ⬜ pending |
| State transitions | 02-01 | 1 | CONN-03 | unit | `xcodebuild test -only-testing:VPNCoreTests/ConnectionStateTests` | ❌ Wave 0 | ⬜ pending |
| Connect blocks while auth | 02-01 | 1 | CONN-01 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testConnectBlockedWhileAuthenticating` | ❌ Wave 0 | ⬜ pending |
| Dummy creds deleted | 02-01 | 1 | CONN-06 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testDummyCredsFileDeletedOnExit` | ❌ Wave 0 | ⬜ pending |
| Real creds deleted | 02-01 | 1 | CONN-06 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testRealCredsFileDeleted` | ❌ Wave 0 | ⬜ pending |
| Log file created | 02-01 | 1 | CONN-08 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testLogFileCreated` | ❌ Wave 0 | ⬜ pending |
| Disconnect signal | 02-01 | 1 | CONN-07 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testDisconnectSendsSignal` | ❌ Wave 0 | ⬜ pending |
| openvpn running | 02-02 | 2 | CONN-04 | manual | `ps aux \| grep openvpn` | manual-only | ⬜ pending |
| App quit kills openvpn | 02-02 | 2 | CONN-05 | manual | `ps aux \| grep openvpn` after quit | manual-only | ⬜ pending |
| Log file receives output | 02-02 | 2 | CONN-08 | manual | `cat ~/Library/Logs/AWSVPNClient/<name>.log` | manual-only | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `VPNCore/Tests/VPNCoreTests/VPNManagerTests.swift` — stubs for CONN-01, CONN-02 (randomHex, URL encoding), CONN-06, CONN-07, CONN-08
- [ ] `VPNCore/Tests/VPNCoreTests/CRV1ParserTests.swift` — stubs for CONN-02 (CRV1 parsing, SID extraction)
- [ ] `VPNCore/Tests/VPNCoreTests/SAMLServerTests.swift` — stubs for CONN-02 (SAMLResponse body extraction, chunked accumulation)
- [ ] `VPNCore/Tests/VPNCoreTests/ConnectionStateTests.swift` — stubs for CONN-03 (all state transitions)
- [ ] `VPNCore/Tests/VPNCoreTests/VPNConfigParsingTests.swift` — stubs for config filtering (host, port, proto extraction, auth directive removal)
- [ ] `VPNCoreTests` target added to `project.yml` (`type: bundle.unit-test`, `platform: macOS`, `dependencies: [VPNCore]`); `xcodebuild generate && xcodebuild test` exits 0

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| sudo openvpn runs as background process after connect | CONN-04 | Requires real SAML flow and patched openvpn binary | `ps aux \| grep openvpn` — confirm PID present after connecting a real config |
| All openvpn PIDs killed on app quit | CONN-05 | Requires live processes; app termination lifecycle can't be unit tested | `ps aux \| grep openvpn` before and after quitting app — confirm no survivors |
| openvpn stdout written to log file | CONN-08 | Requires real openvpn subprocess | `cat ~/Library/Logs/AWSVPNClient/<name>.log` — confirm openvpn output present after connecting |
| SAML browser opens to correct URL | CONN-02 | Requires live network call to AWS Client VPN endpoint | Open app, click config, confirm browser opens to AWS IdP page |
| State transitions to .connected after IdP login | CONN-02 | Requires real SAML flow completion | Confirm menu item shows "● Connected" after completing browser login |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
