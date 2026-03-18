---
phase: 1
slug: scaffold
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | xcodebuild (Xcode build system) |
| **Config file** | AWSVPNClient.xcodeproj |
| **Quick run command** | `xcodebuild build -project AWSVPNClient.xcodeproj -scheme AWSVPNClient -configuration Debug 2>&1 | tail -5` |
| **Full suite command** | `xcodebuild build -project AWSVPNClient.xcodeproj -allTargets -configuration Debug 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -project AWSVPNClient.xcodeproj -scheme AWSVPNClient -configuration Debug 2>&1 | tail -5`
- **After every plan wave:** Run `xcodebuild build -project AWSVPNClient.xcodeproj -allTargets -configuration Debug 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 0 | SCAF-01 | build | `xcodebuild build -scheme AWSVPNClient -configuration Debug` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | SCAF-01 | build | `xcodebuild build -scheme VPNCore -configuration Debug` | ❌ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | SCAF-01 | build | `xcodebuild build -scheme aws-connect -configuration Debug` | ❌ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | SCAF-01 | manual | Launch app — verify no Dock icon, menu bar icon visible | N/A | ⬜ pending |
| 1-01-05 | 01 | 1 | SCAF-01 | manual | Click Quit in menu bar — verify clean termination | N/A | ⬜ pending |
| 1-02-01 | 02 | 2 | SCAF-02 | build | `xcodebuild build -allTargets` — VPNManager importable | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | SCAF-02 | manual | Launch app — verify ~/Library/Application Support/AWSVPNClient/configs/ created | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Xcode project created with all three targets (AWSVPNClient, VPNCore, aws-connect)
- [ ] Build settings configured for Swift 6, macOS 14+
- [ ] VPNCore embedded in AWSVPNClient (Embed Without Signing)
- [ ] rpath spike: CLI target `RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks/`

*Wave 0 establishes the project structure before any feature code.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No Dock icon on launch | SCAF-01 | UI behavior, no automated assertion | Launch app; verify Dock shows no AWSVPNClient entry |
| Menu bar icon visible | SCAF-01 | UI behavior, no automated assertion | Launch app; verify icon appears in macOS menu bar |
| Quit terminates cleanly | SCAF-01 | Process lifecycle, no automated assertion | Click Quit in menu; verify process exits (Activity Monitor) |
| configs/ dir created on first launch | SCAF-02 | Filesystem side-effect on first run | Delete ~/Library/Application Support/AWSVPNClient/; launch; verify directory exists |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
