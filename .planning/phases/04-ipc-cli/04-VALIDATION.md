---
phase: 4
slug: ipc-cli
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode built-in) |
| **Config file** | VPNCoreTests/Info.plist (scheme-based) |
| **Quick run command** | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' -only-testing:VPNCoreTests 2>&1 \| grep -E "passed\|failed\|error:"` |
| **Full suite command** | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' 2>&1 \| tail -20` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite green + manual IPC smoke test
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | IPC-01/02/03/04 | Unit | `xcodebuild test ... -only-testing:VPNCoreTests/IPCMessageTests` | ❌ Wave 0 | ⬜ pending |
| 4-01-02 | 01 | 1 | IPC-01 | Unit | `xcodebuild test ... -only-testing:VPNCoreTests/IPCServerTests` | ❌ Wave 0 | ⬜ pending |
| 4-01-03 | 01 | 2 | IPC-01/02/03/04 | Integration (manual) | `echo '{"cmd":"status"}' \| nc -U ~/Library/Application\ Support/AWSVPNClient/daemon.sock` | N/A (manual) | ⬜ pending |
| 4-02-01 | 02 | 1 | IPC-02/03/04/05 | Unit | `xcodebuild test ... -only-testing:VPNCoreTests/IPCMessageTests` | ❌ Wave 0 | ⬜ pending |
| 4-02-02 | 02 | 2 | IPC-02/03/04/05 | Manual smoke | Run `aws-connect status` against running app | N/A (manual) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `VPNCoreTests/IPCMessageTests.swift` — unit tests for `IPCRequest`/`IPCResponse` Codable encode/decode, `ConnectionState.ipcLabel` all 5 cases, status table column alignment, arg parsing logic
- [ ] `VPNCoreTests/ConnectionStateTests.swift` — add `ipcLabel` test cases (file exists — needs additions for new property)

*Existing infrastructure covers XCTest setup — no new framework install needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Socket created on app launch | IPC-01 | Requires running app process | Launch app, check `ls ~/Library/Application\ Support/AWSVPNClient/daemon.sock` exists |
| Stale socket removed on relaunch | IPC-01 | Requires simulated crash + relaunch | Kill app with `kill -9`, relaunch, verify socket recreated |
| `aws-connect <name>` triggers connect | IPC-02 | Requires running app + VPN config | Run `aws-connect corp-vpn`, observe menu bar state change |
| `aws-connect --disconnect <name>` disconnects | IPC-03 | Requires active connection | Connect first, then run disconnect command |
| Full IPC smoke test | IPC-01–04 | App must be running | `echo '{"cmd":"status"}' \| nc -U ~/Library/Application\ Support/AWSVPNClient/daemon.sock` |
| Error when app not running | IPC-05 | Requires app to be stopped | Kill app, run any `aws-connect` command, verify error message |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
