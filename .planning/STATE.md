---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: verifying
stopped_at: Completed 04-ipc-cli-02 (Task 2 human-verify approved); Phase 04 complete
last_updated: "2026-04-02T22:52:29.409Z"
last_activity: 2026-04-02
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 13
  completed_plans: 13
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** VPN connections run silently in the background — connect once from the menu bar, walk away.
**Current focus:** Phase 04 — ipc-cli

## Current Position

Phase: 5
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-04-02

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01-scaffold P02 | 30 | 3 tasks | 7 files |
| Phase 01-scaffold P03 | 5 | 1 tasks | 2 files |
| Phase 02-connection-lifecycle P01 | 228 | 2 tasks | 10 files |
| Phase 02-connection-lifecycle P03 | 2 | 1 tasks | 2 files |
| Phase 02-connection-lifecycle P02 | 3 | 2 tasks | 5 files |
| Phase 02-connection-lifecycle P04 | 4 | 1 tasks | 4 files |
| Phase 02-connection-lifecycle P05 | 15 | 3 tasks | 5 files |
| Phase 02-connection-lifecycle P05 | 15 | 3 tasks | 5 files |
| Phase 03-menu-ui-config-management P01 | 4 | 2 tasks | 3 files |
| Phase 03-menu-ui-config-management P02 | 2 | 1 tasks | 1 files |
| Phase 03-menu-ui-config-management P03 | 10 | 1 tasks | 1 files |
| Phase 04-ipc-cli P01 | 25 | 2 tasks | 7 files |
| Phase 04-ipc-cli P02 | 8 | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-phase]: VPNCore as shared framework — resolve rpath vs. static library in Phase 1 spike before committing
- [Pre-phase]: Swift 6.1 strict concurrency + @Observable (macOS 14+) — no @StateObject, no global singletons
- [Pre-phase]: Foundation.Process for subprocess (not swift-subprocess v0.1)
- [Phase 01]: Dynamic framework rpath confirmed viable — spike passed, CLI loads VPNCore from @executable_path/../Frameworks, no pivot to SPM needed
- [Phase 01]: VPNCore-Info.plist required in XcodeGen project.yml info block — codesign rejects embedded framework without it
- [Phase 01-scaffold]: ConnectionState uses case failed(String) not Error for Swift 6 Sendable conformance
- [Phase 01-scaffold]: @MainActor on AWSVPNClientApp struct required to resolve Swift 6 @State + @MainActor class init error
- [Phase 01-scaffold]: Config directory creation inline in VPNManager.init() using try? — idempotent, no separate setup
- [Phase 01-scaffold]: XcodeGen embed+copy.destination:executables places aws-connect into AWSVPNClient.app/Contents/MacOS/ — primary approach worked, postBuildScript fallback not needed
- [Phase 02-connection-lifecycle]: --writepid flag confirmed supported by installed openvpn binary — primary PID tracking strategy adopted, pgrep fallback not needed
- [Phase 02-connection-lifecycle]: Explicit schemes block required in project.yml — XcodeGen does not auto-associate unit test targets with the app scheme
- [Phase 02-connection-lifecycle]: SAMLServer is final class @unchecked Sendable (not actor) — NWListener GCD callbacks + DispatchQueue-serialized continuation state
- [Phase 02-connection-lifecycle]: extractSAMLResponse/parseContentLength use internal visibility for @testable import unit test access
- [Phase 02-connection-lifecycle]: VPNConfigParser is a caseless enum namespace — no state, all static methods, prevents instantiation
- [Phase 02-connection-lifecycle]: urlEncodeSAML removes '+' from CharacterSet.urlQueryAllowed so it encodes as %2B, matching Rust urlencoding::encode
- [Phase 02-connection-lifecycle]: AuthHelpers uses components(separatedBy:) not split(separator:) for CRV1 colon-split to preserve empty subsequences and keep field indices stable
- [Phase 02-connection-lifecycle]: Filtered conf temp file deleted in terminationHandler (not defer in connect()) to avoid race where openvpn hasn't read the file yet
- [Phase 02-connection-lifecycle]: SAML timeout implemented as withThrowingTaskGroup race between SAMLServer.waitForSAMLResponse() and Task.sleep(30s)
- [Phase 02-connection-lifecycle]: openvpnPath resolved at init via static closure checking /usr/local/bin, /opt/homebrew/bin, /usr/bin before falling back to PATH
- [Phase 02-connection-lifecycle]: _updateAtexitPIDs defined in VPNCore not app target: VPNCore framework cannot call into embedding app
- [Phase 02-connection-lifecycle]: atexit PID set uses nonisolated(unsafe) global: data race acceptable on crash-path safety net
- [Phase 02-connection-lifecycle]: _updateAtexitPIDs defined in VPNCore (not AWSVPNClientApp) because VPNCore framework cannot call into the app target
- [Phase 03-menu-ui-config-management]: TDD RED stubs in Swift: compile stubs added to VPNManager so isActive test could run before real implementations existed
- [Phase 03-menu-ui-config-management]: loadConfigs() called in VPNManager.init() — configs array auto-populated on construction, no explicit caller burden
- [Phase 03-menu-ui-config-management]: removeConfig uses FileManager.trashItem not NSWorkspace.recycle — synchronous, no AppKit dependency in VPNCore framework
- [Phase 03-menu-ui-config-management]: StatusMenuView: NSApp.activate(ignoringOtherApps:true) must precede NSOpenPanel.runModal() for menu bar apps; Button actions use Task { try? await } for async VPNManager calls; View Logs creates log file before NSWorkspace.open
- [Phase 03-menu-ui-config-management]: In .menuBarExtraStyle(.menu), capture @Environment ObservableObject before Task to prevent use-after-free on menu dismissal; annotate Task @MainActor
- [Phase 04-ipc-cli]: IPCMessage.swift in VPNCore (not App target) — CLI imports VPNCore and avoids struct duplication
- [Phase 04-ipc-cli]: IPCServer in App target (not VPNCore) — CLI never instantiates a server; keeps NWListener out of CLI surface
- [Phase 04-ipc-cli]: Task { @MainActor [weak self] in } bridges GCD NWConnection callbacks to @MainActor VPNManager — mirrors spawnSudoOpenvpn pattern
- [Phase 04-ipc-cli]: Copied sun_path to local var before strncpy to satisfy Swift 6 exclusive access rule
- [Phase 04-ipc-cli]: End-to-end IPC verified: daemon.sock created on launch, CLI POSIX socket connection works, aws-connect status output confirmed, app-not-running error path confirmed

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 1]: VPNCore linking strategy (dynamic framework rpath vs. static Swift Package) is MEDIUM confidence — must resolve with a test build before writing dependent code
- [Phase 2]: openvpn PID tracking via --writepid vs. pgrep -P under sudo needs early verification

## Session Continuity

Last session: 2026-03-31T23:36:59.980Z
Stopped at: Completed 04-ipc-cli-02 (Task 2 human-verify approved); Phase 04 complete
Resume file: None
