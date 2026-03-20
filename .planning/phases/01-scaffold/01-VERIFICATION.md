---
phase: 01-scaffold
verified: 2026-03-19T18:40:00Z
status: human_needed
score: 10/10 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 8/10
  gaps_closed:
    - "CLI binary can load VPNCore.framework at runtime (rpath resolves) — aws-connect is now automatically placed inside AWSVPNClient.app/Contents/MacOS/ by the build system via XcodeGen copy phase"
    - "VPNCore.framework is embedded in app bundle at Contents/Frameworks/ — now confirmed self-contained without manual placement"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Launch AWSVPNClient.app and verify menu bar behavior"
    expected: "lock.open icon appears in menu bar, no Dock icon, click shows 'No configs — add .conf files' and 'Quit AWSVPNClient', Quit terminates the app"
    why_human: "Visual menu bar presence and LSUIElement (no Dock icon) behavior cannot be verified programmatically"
  - test: "Verify config directory created on first launch"
    expected: "~/Library/Application Support/AWSVPNClient/configs/ exists after running the app"
    why_human: "Directory exists (confirmed automatically), but creation-on-launch vs pre-existing needs human to verify with a fresh user account"
---

# Phase 1: Scaffold Verification Report

**Phase Goal:** A running Xcode project with three linked targets, a menu bar app that stays out of the Dock, and config persistence — the foundation everything else links against
**Verified:** 2026-03-19T18:40:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (Plan 01-03)

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Xcode project exists with three targets: AWSVPNClient (App), VPNCore (Framework), aws-connect (CLI) | VERIFIED | pbxproj contains all three PBXNativeTarget definitions |
| 2 | All three targets build without errors using xcodebuild | VERIFIED | `xcodebuild build -scheme AWSVPNClient` → BUILD SUCCEEDED |
| 3 | CLI binary can load VPNCore.framework at runtime (rpath resolves) | VERIFIED | Bundled binary at `Contents/MacOS/aws-connect` executes: "aws-connect — stub (Phase 4) / VPNCore types available: VPNConfig, ConnectionState, VPNManager" — no dyld errors. `otool -L` shows `@rpath/VPNCore.framework/...` resolving correctly inside the bundle. |
| 4 | VPNCore.framework is embedded in app bundle at Contents/Frameworks/ | VERIFIED | `AWSVPNClient.app/Contents/Frameworks/VPNCore.framework` confirmed in DerivedData after clean build |
| 5 | App launches showing a menu bar icon (lock.open) with no Dock icon and no main window | HUMAN NEEDED | LSUIElement=true in Info.plist verified; MenuBarExtra with lock.open in source; visual behavior requires human |
| 6 | Quit menu item terminates the app cleanly | HUMAN NEEDED | `NSApplication.shared.terminate(nil)` present in StatusMenuView.swift line 16; runtime behavior requires human |
| 7 | VPNManager (@Observable @MainActor) skeleton is importable from both app and CLI targets | VERIFIED | `VPNCore/VPNManager.swift` is `@Observable @MainActor public final class VPNManager`; both targets import VPNCore |
| 8 | Config directory at ~/Library/Application Support/AWSVPNClient/configs/ is created on first launch | VERIFIED | `VPNManager.init()` calls `createDirectory(withIntermediateDirectories: true)` — idempotent |
| 9 | Menu bar icon switches between lock.fill and lock.open based on isAnyConnected | VERIFIED | `AWSVPNClientApp.swift` line 12: `vpnManager.isAnyConnected ? "lock.fill" : "lock.open"` wired to VPNManager |
| 10 | All VPNCore public types (VPNConfig, ConnectionState) exported correctly | VERIFIED | All types, properties, inits explicitly `public`; five ConnectionState cases present; Sendable conformance correct |

**Score:** 10/10 truths verified (2 require human confirmation for runtime/visual behavior)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `project.yml` | XcodeGen spec as source of truth with three targets | VERIFIED | AWSVPNClient target includes `aws-connect` dependency with `embed: true`, `codeSign: false`, `copy.destination: executables` |
| `AWSVPNClient.xcodeproj/project.pbxproj` | Generated project with Copy Files build phase for aws-connect | VERIFIED | PBXCopyFilesBuildPhase with `dstSubfolderSpec = 6` (MacOS) and aws-connect in Embed Dependencies confirmed |
| `AWSVPNClient/AWSVPNClientApp.swift` | App struct with MenuBarExtra wired to VPNManager | VERIFIED | `@main @MainActor`, `@State private var vpnManager = VPNManager()`, lock.fill/lock.open icon switching, `.menuBarExtraStyle(.menu)` |
| `AWSVPNClient/StatusMenuView.swift` | Menu view with Quit button | VERIFIED | `@Environment(VPNManager.self)`, "No configs" placeholder, "Quit AWSVPNClient" button with `NSApplication.shared.terminate(nil)` |
| `VPNCore/VPNConfig.swift` | VPNConfig model — Identifiable, Hashable, Sendable | VERIFIED | `public struct VPNConfig: Identifiable, Hashable, Sendable` with UUID id, name, fileURL — all public |
| `VPNCore/ConnectionState.swift` | ConnectionState enum with five cases | VERIFIED | `public enum ConnectionState: Sendable` with disconnected, authenticating, connected, disconnecting, `failed(String)` |
| `VPNCore/VPNManager.swift` | @Observable @MainActor VPNManager with typed skeleton | VERIFIED | `@Observable @MainActor public final class VPNManager`; fatalError Phase 2 stubs intentional |
| `aws-connect/main.swift` | CLI entry point that imports VPNCore | VERIFIED | `import VPNCore`, prints stub messages |
| `AWSVPNClient/AWSVPNClient-Info.plist` | LSUIElement = YES | VERIFIED | `<key>LSUIElement</key><true/>` confirmed at line 21 |
| `VPNCore/VPNCore.h` | Framework umbrella header | VERIFIED | Standard umbrella header with Foundation import |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `aws-connect/main.swift` | VPNCore.framework | `import VPNCore` + `@executable_path/../Frameworks` rpath | VERIFIED | Binary executes inside bundle with all VPNCore types loading correctly — no dyld errors |
| `project.yml` aws-connect dependency | `AWSVPNClient.xcodeproj/project.pbxproj` | `xcodegen generate` | VERIFIED | `dstSubfolderSpec = 6` copy phase present; clean build places binary at Contents/MacOS/aws-connect |
| `AWSVPNClient/AWSVPNClientApp.swift` | VPNCore.framework | `import VPNCore` | VERIFIED | VPNCore embedded in app bundle at Contents/Frameworks/ |
| `AWSVPNClient/AWSVPNClientApp.swift` | `VPNCore/VPNManager.swift` | `@State private var vpnManager = VPNManager()` | VERIFIED | Pattern confirmed present |
| `AWSVPNClient/StatusMenuView.swift` | `VPNCore/VPNManager.swift` | `@Environment(VPNManager.self)` | VERIFIED | Pattern confirmed present |
| `AWSVPNClient/AWSVPNClientApp.swift` | `VPNCore/VPNManager.swift` | `vpnManager.isAnyConnected` drives `lock.fill` icon | VERIFIED | Line 12: `vpnManager.isAnyConnected ? "lock.fill" : "lock.open"` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SCAF-01 | 01-01, 01-02, 01-03 | Xcode project with three targets: App, VPNCore framework, aws-connect CLI | SATISFIED | All three PBXNativeTarget blocks in pbxproj; all three targets build; aws-connect automatically placed inside app bundle via copy phase |
| SCAF-02 | 01-02 | App runs as menu bar only — no Dock icon, no main window (LSUIElement = YES) | SATISFIED | `<key>LSUIElement</key><true/>` in AWSVPNClient-Info.plist; no NSWindow or WindowGroup in App struct; MenuBarExtra only |

No orphaned requirements. Both SCAF-01 and SCAF-02 are the only Phase 1 requirements in REQUIREMENTS.md and both are accounted for in plan frontmatter.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `VPNCore/VPNManager.swift` | ~28, ~32 | `fatalError("Phase 2")` in connect/disconnect | INFO | Intentional — Phase 2 stubs as specified in PLAN. Does not block Phase 1 goal. |

No TODO/FIXME/placeholder comments. No empty return stubs. No unintended anti-patterns found.

### Human Verification Required

#### 1. Menu Bar Icon and LSUIElement Behavior

**Test:** Build and open `AWSVPNClient.app` from DerivedData: `open ~/Library/Developer/Xcode/DerivedData/AWSVPNClient-*/Build/Products/Debug/AWSVPNClient.app`
**Expected:** A lock.open icon appears in the macOS menu bar. No AWSVPNClient icon in the Dock. No main window opens.
**Why human:** Visual menu bar presence and LSUIElement enforcement are OS-level behaviors that cannot be verified without running the app.

#### 2. Menu Content and Quit Button

**Test:** Click the lock.open menu bar icon.
**Expected:** Menu shows "No configs — add .conf files" (greyed out) followed by a divider and "Quit AWSVPNClient" button. Clicking Quit makes the icon disappear from the menu bar.
**Why human:** Menu content rendering and app termination via NSApplication.shared.terminate require a running process to verify.

### Gap Closure Summary

Both structural gaps from the previous verification are fully closed:

**Gap 1 — No copy phase for CLI into app bundle: CLOSED.** `project.yml` now includes `embed: true` + `copy.destination: executables` for aws-connect under the AWSVPNClient target. XcodeGen generated a PBXCopyFilesBuildPhase with `dstSubfolderSpec = 6` targeting the MacOS folder. A clean build of the AWSVPNClient scheme now automatically places aws-connect at `Contents/MacOS/aws-connect`.

**Gap 2 — Rpath unresolvable for standalone product: CLOSED.** Running the bundled aws-connect binary confirms VPNCore types load via `@executable_path/../Frameworks` without dyld errors and without any manual file placement. The rpath architecture is now fully automated and repeatable from a clean build.

No regressions detected on previously-passing items (LSUIElement, icon switching, terminate handler, VPNCore types, all source artifacts).

---

_Verified: 2026-03-19T18:40:00Z_
_Verifier: Claude (gsd-verifier)_
