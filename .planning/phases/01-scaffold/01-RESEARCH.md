# Phase 1: Scaffold - Research

**Researched:** 2026-03-18
**Domain:** Swift 6.1 / SwiftUI / Xcode multi-target project scaffold (macOS 14+)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**VPNCore Linking Strategy**
- Dynamic .framework — VPNCore compiled as an embedded framework inside the app bundle
- CLI binary lives at `AWSVPNClient.app/Contents/MacOS/aws-connect` alongside the app binary
- Both binaries load `VPNCore.framework` from `AWSVPNClient.app/Contents/Frameworks/`
- CLI rpath points to `@executable_path/../Frameworks/` — works because CLI is inside the bundle
- Phase 1 must include a spike task: build the three-target project and verify the CLI can successfully `import VPNCore` before writing any real logic. If rpath fails, pivot to local SPM before Phase 2 work begins.

**VPNManager Skeleton**
- Full typed skeleton — not an empty shell
- `@Observable @MainActor class VPNManager`
- Properties: `var configs: [VPNConfig] = []`, `var connections: [String: ConnectionState] = [:]`
- Computed: `var isAnyConnected: Bool` (drives menu bar icon)
- Stub methods: `func connect(_ config: VPNConfig) async throws` and `func disconnect(_ config: VPNConfig) async throws` — both `fatalError("Phase 2")`

**VPNConfig Model**
- Minimal — name and file URL only, no parsed fields
- `struct VPNConfig: Identifiable, Hashable { let id: UUID; let name: String; let fileURL: URL }`
- `name` derived from filename without `.conf` extension
- Phase 2 adds parsed fields (host, port, proto) when the connection logic needs them

**MenuBarExtra Style**
- `.menuBarExtraStyle(.menu)` — native macOS pull-down menu
- Each SwiftUI view inside becomes a native menu item
- Chosen for: native Mac feel, consistent with apps like Tailscale/1Password, matches the simple list UI
- The run-loop-blocks-while-open quirk is acceptable — state updates between opens, not during

**Menu Bar Icon**
- Wire lock.fill / lock.open immediately in Phase 1, not a throwaway placeholder
- `systemImage: vpnManager.isAnyConnected ? "lock.fill" : "lock.open"`
- Use `.imageScaleStyle(.template)` for dark/light mode compatibility (meets UI-01)
- Phase 3 adds no icon changes — this is the final icon logic

### Claude's Discretion
- Xcode project file layout details (groups, folder structure within the project navigator)
- Exact rpath build setting names and values
- How to handle the config directory creation (AppDelegate vs. VPNManager init)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCAF-01 | Xcode project exists with three targets: App (AWSVPNClient), VPNCore (framework), and CLI (aws-connect) | Multi-target Xcode setup, dynamic framework embedding, rpath wiring — all documented below |
| SCAF-02 | App runs as menu bar only — no Dock icon, no main window (LSUIElement = YES in Info.plist) | MenuBarExtra + LSUIElement pattern fully documented; Quit button requirement from Pitfall 10 |
</phase_requirements>

---

## Summary

Phase 1 creates the buildable project skeleton that all subsequent phases link against. The work is primarily Xcode project configuration rather than logic — three targets (App, VPNCore framework, CLI), correct rpath wiring, a SwiftUI MenuBarExtra with .menu style, and a typed VPNManager skeleton that compiles under Swift 6 strict concurrency.

The two highest-risk items are: (1) the `@Observable @MainActor` class pattern under Swift 6 strict concurrency in an App struct — there is a known compiler error when `@State` tries to initialize a `@MainActor`-isolated object from a nonisolated context; the resolution is to annotate the App struct itself with `@MainActor`, or provide a `nonisolated init()` on VPNManager; (2) the dynamic framework rpath for the CLI target — the CLI binary lives inside the app bundle so `@executable_path/../Frameworks/` resolves correctly, but this must be verified with a test build before Phase 2 begins (as the CONTEXT.md mandates).

The config directory creation is straightforward: `FileManager.default.createDirectory(at:withIntermediateDirectories:true)` at app launch, called with `withIntermediateDirectories: true` so it is safe to call every launch (no-op if the directory already exists).

**Primary recommendation:** Build in this order — (1) create Xcode project with three targets, (2) wire VPNCore as embedded dynamic framework with correct rpath, (3) do the rpath spike (CLI `import VPNCore`), (4) add VPNManager skeleton + ConnectionState enum, (5) wire MenuBarExtra with LSUIElement, (6) create config directory on launch. Do not write logic until the rpath spike passes.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.1 (Xcode 16.3) | Primary language | Swift 6 strict concurrency enforced from day one; Xcode 16.3 ships Swift 6.1 |
| SwiftUI | macOS 14+ | Menu bar scene | `MenuBarExtra` is the only first-party, non-deprecated menu bar API |
| Observation framework (`@Observable`) | macOS 14+ | VPNManager reactive state | Fine-grained property tracking; requires macOS 14 Sonoma minimum |
| Foundation (`FileManager`) | macOS 10+ | Config directory creation | `createDirectory(at:withIntermediateDirectories:true)` is the standard pattern |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `swift-argument-parser` | 1.3+ | CLI argument parsing (Phase 4) | Added to CLI target only; not needed in Phase 1 scaffold but include as SPM dependency now to avoid future restructuring |
| `os.Logger` (OSLog) | macOS 11+ | Structured logging | Use throughout; visible in Console.app |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Dynamic .framework for VPNCore | Local SPM package (.target) | SPM avoids rpath complexity entirely; chosen only if rpath spike fails in Phase 1 |
| `@Observable` | `ObservableObject + @Published` | `@Observable` requires macOS 14; `ObservableObject` works on macOS 13 but project targets 14+ |

**Installation:**
```bash
# In Xcode: File > Add Package Dependencies
# swift-argument-parser (CLI target only)
# https://github.com/apple/swift-argument-parser.git  from: "1.3.0"

# All other dependencies are system frameworks — no installation needed.
```

---

## Architecture Patterns

### Recommended Project Structure

```
AWSVPNClient.xcodeproj/
│
├── VPNCore/                          # Framework target
│   ├── VPNConfig.swift               # struct VPNConfig: Identifiable, Hashable
│   ├── ConnectionState.swift         # enum ConnectionState (Phase 1 stub)
│   └── VPNManager.swift              # @Observable @MainActor class VPNManager
│
├── AWSVPNClient/                     # macOS App target
│   ├── AWSVPNClientApp.swift         # @main, MenuBarExtra scene
│   ├── StatusMenuView.swift          # Menu contents view
│   └── AWSVPNClient-Info.plist       # LSUIElement = YES
│
└── aws-connect/                      # Command Line Tool target
    └── main.swift                    # Minimal stub (Phase 4 fills in)
```

**File layout on disk after build:**
```
AWSVPNClient.app/
└── Contents/
    ├── MacOS/
    │   ├── AWSVPNClient              # App binary
    │   └── aws-connect               # CLI binary (lives here, not separate)
    └── Frameworks/
        └── VPNCore.framework/        # Shared by both binaries via rpath
```

### Pattern 1: Three-Target Xcode Project

**What:** One `.xcodeproj` with three targets — App (macOS App template), VPNCore (Framework template), CLI (Command Line Tool template).

**When to use:** All of Phase 1.

**Xcode target configuration:**
- VPNCore target: Framework, macOS 14.0 deployment target, Swift 6 language mode
- AWSVPNClient target: macOS App, links and embeds VPNCore.framework (Embed & Sign → "Embed Without Signing" for unsigned apps)
- aws-connect target: Command Line Tool, adds "Copy Files" build phase to copy VPNCore.framework into `$(BUILT_PRODUCTS_DIR)/aws-connect/Frameworks/` (not needed if CLI lives inside app bundle — see rpath note below)

**rpath build setting for CLI target:**
```
RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks
```
This works because the CLI binary lives at `AWSVPNClient.app/Contents/MacOS/aws-connect`, so `../Frameworks` resolves to `AWSVPNClient.app/Contents/Frameworks/` where VPNCore.framework lives.

**Spike verification command:**
```bash
# After building, from project root:
cd AWSVPNClient.app/Contents/MacOS
./aws-connect   # should not crash with dyld framework not found
# Or inspect:
otool -L aws-connect | grep VPNCore
```

### Pattern 2: MenuBarExtra + LSUIElement

**What:** App entry point uses `MenuBarExtra` scene; Info.plist sets `LSUIElement = YES` to suppress Dock icon.

**When to use:** The App struct and plist setup.

```swift
// AWSVPNClientApp.swift
// Source: Apple Developer Documentation — MenuBarExtra
@main
@MainActor  // Required: resolves the @State + @MainActor @Observable initialization conflict
struct AWSVPNClientApp: App {
    @State private var vpnManager = VPNManager()

    var body: some Scene {
        MenuBarExtra(vpnManager.isAnyConnected ? "VPN Connected" : "VPN",
                     systemImage: vpnManager.isAnyConnected ? "lock.fill" : "lock.open") {
            StatusMenuView()
                .environment(vpnManager)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Info.plist key:** `LSUIElement` → `YES` (or in Xcode's target Info tab: "Application is agent (UIElement)" = YES).

### Pattern 3: @Observable @MainActor VPNManager

**What:** The shared state object. `@Observable` for SwiftUI tracking; `@MainActor` for safe main-thread mutation.

**Swift 6 constraint:** Initializing a `@MainActor`-isolated object with `@State` in an App struct causes a compile error: "Call to main actor-isolated initializer 'init()' in a synchronous nonisolated context." The fix is to annotate the App struct itself with `@MainActor` (see Pattern 2 above).

```swift
// VPNManager.swift (in VPNCore target)
import Observation

@Observable
@MainActor
final class VPNManager {
    var configs: [VPNConfig] = []
    var connections: [String: ConnectionState] = [:]

    var isAnyConnected: Bool {
        connections.values.contains { $0 == .connected }
    }

    func connect(_ config: VPNConfig) async throws {
        fatalError("Phase 2")
    }

    func disconnect(_ config: VPNConfig) async throws {
        fatalError("Phase 2")
    }
}
```

```swift
// ConnectionState.swift (in VPNCore target)
public enum ConnectionState: Equatable {
    case disconnected
    case authenticating
    case connected
    case disconnecting
    case failed(Error)

    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.authenticating, .authenticating),
             (.connected, .connected),
             (.disconnecting, .disconnecting):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}
```

Note: `Error` is not `Equatable`, so the `Equatable` conformance requires a custom `==` that treats all `.failed` cases as equal (or drops `Equatable` and uses `isConnected` computed property instead). Simpler: drop `Equatable`, add `var isConnected: Bool { if case .connected = self { return true }; return false }`.

### Pattern 4: VPNConfig Model

```swift
// VPNConfig.swift (in VPNCore target)
import Foundation

public struct VPNConfig: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let fileURL: URL

    public init(fileURL: URL) {
        self.id = UUID()
        self.fileURL = fileURL
        self.name = fileURL.deletingPathExtension().lastPathComponent
    }
}
```

### Pattern 5: Config Directory Creation on Launch

**What:** Create `~/Library/Application Support/AWSVPNClient/configs/` on first launch.

**When:** App struct init or in a dedicated setup call from VPNManager init.

```swift
// In VPNManager.init() or AppDelegate.applicationDidFinishLaunching
// Source: Apple Developer Documentation — FileManager
static let configsDirectory: URL = {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AWSVPNClient/configs", isDirectory: true)
}()

func createConfigDirectoryIfNeeded() throws {
    try FileManager.default.createDirectory(
        at: VPNManager.configsDirectory,
        withIntermediateDirectories: true,
        attributes: nil
    )
}
```

`withIntermediateDirectories: true` makes this idempotent — safe to call every launch.

### Pattern 6: StatusMenuView with Quit Button

**What:** The menu contents, including the mandatory Quit button (Pitfall 10 — LSUIElement apps have no default quit mechanism).

```swift
// StatusMenuView.swift (in App target)
struct StatusMenuView: View {
    @Environment(VPNManager.self) private var vpnManager

    var body: some View {
        // Config list (Phase 2+ populates this)
        if vpnManager.configs.isEmpty {
            Text("No configs — add .conf files")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Quit AWSVPNClient") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

### Anti-Patterns to Avoid

- **Omitting the Quit button:** LSUIElement apps have no Cmd-Q or Dock menu. Without an explicit Quit button the app can only be killed via Activity Monitor. Include it in the initial scaffold.
- **Using @StateObject with @Observable:** `@StateObject` is for `ObservableObject`. Using it with `@Observable` compiles but breaks SwiftUI's dependency tracking. Use `@State` + `@Environment`.
- **Calling `fatalError` stubs in tests:** The Phase 2 stub methods use `fatalError("Phase 2")` — ensure no test code calls `connect()` or `disconnect()` in Phase 1.
- **Forgetting `public` on VPNCore types:** All types and members imported by the App and CLI targets must be `public`. Forgetting `public` causes "cannot find type" errors that look like linking problems.
- **Embedding VPNCore.framework with signing on unsigned builds:** The Embed & Sign build phase on an unsigned app will fail. Use "Embed Without Signing" in the framework embedding phase.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CLI argument parsing | Custom `CommandLine.arguments` parser | `swift-argument-parser` | Help text, subcommand dispatch, error messages — free |
| Structured logging | `print()` | `os.Logger` | `print()` is invisible after app launch; logs need to appear in Console.app |
| Config directory creation | Manual existence check + mkdir | `FileManager.createDirectory(withIntermediateDirectories:true)` | Idempotent — no pre-check needed |

**Key insight:** Phase 1 is configuration-heavy, not logic-heavy. The only "code" is type declarations and wiring. Everything complex (subprocess, IPC, SAML) is deferred.

---

## Common Pitfalls

### Pitfall A: @Observable @MainActor + @State Init Error (Swift 6)

**What goes wrong:** Compiler error "Call to main actor-isolated initializer 'init()' in a synchronous nonisolated context" when `@State private var vpnManager = VPNManager()` is in the App struct, and `VPNManager` is `@MainActor @Observable`.

**Why it happens:** `@State` initialization runs in a nonisolated context. A `@MainActor`-isolated `init()` cannot be called from nonisolated code.

**How to avoid:** Annotate the App struct with `@MainActor`. As of WWDC 2024, SwiftUI's `View` protocol is `@MainActor`, but `App` does not automatically inherit this. Explicitly annotating the App struct resolves the error.
```swift
@main
@MainActor
struct AWSVPNClientApp: App { ... }
```

**Warning signs:** Compiler error at `@State private var vpnManager = VPNManager()` line.

### Pitfall B: rpath Failure — CLI Cannot Load VPNCore.framework

**What goes wrong:** At runtime, `aws-connect` fails with `dyld: Library not loaded: @rpath/VPNCore.framework/Versions/A/VPNCore`.

**Why it happens:** Either (a) the `RUNPATH_SEARCH_PATHS` build setting for the CLI target is wrong, (b) VPNCore.framework is not present at the expected path relative to the CLI binary, or (c) the CLI binary is not in the app bundle at build time.

**How to avoid:** The spike task in this phase exists to catch this. After the first successful build, run `otool -L AWSVPNClient.app/Contents/MacOS/aws-connect` and verify the VPNCore entry uses `@rpath`. If the spike fails: pivot to SPM local package before writing any dependent code.

**Warning signs:** `dyld` error on CLI launch; `otool -L` shows absolute path instead of `@rpath/...`.

### Pitfall C: Missing `public` on VPNCore Exported Types

**What goes wrong:** `import VPNCore` compiles, but `VPNManager`, `VPNConfig`, `ConnectionState` are not visible in the App or CLI targets.

**Why it happens:** Swift framework members default to `internal`. Only `public` (or `open`) declarations are visible across module boundaries.

**How to avoid:** Mark all types and members imported by other targets as `public`. In Phase 1: `VPNManager`, `VPNConfig`, `ConnectionState`, and all their `init` methods must be `public`.

**Warning signs:** "Cannot find type 'VPNManager' in scope" despite successful build of VPNCore target.

### Pitfall D: LSUIElement App Has No Default Quit Mechanism (Pitfall 10 from PITFALLS.md)

**What goes wrong:** App launches with no Dock icon and no Cmd-Q shortcut. The only way to quit is Activity Monitor or `kill`. Any cleanup (openvpn teardown in later phases) never runs.

**How to avoid:** Include `Button("Quit AWSVPNClient") { NSApplication.shared.terminate(nil) }` in the initial `StatusMenuView`. Non-negotiable from Phase 1.

### Pitfall E: Embedding With Signing Fails on Unsigned Builds

**What goes wrong:** Xcode's default framework embedding uses "Embed & Sign". On an unsigned app (no provisioning profile, no developer certificate), the signing step may fail or produce a broken build.

**How to avoid:** In the App target's "Frameworks, Libraries, and Embedded Content" section, set VPNCore.framework to "Embed Without Signing".

---

## Code Examples

### MenuBarExtra scene wiring (verified pattern)

```swift
// Source: Apple Developer Documentation — MenuBarExtra + @Observable pattern
// https://developer.apple.com/documentation/SwiftUI/MenuBarExtra

@main
@MainActor
struct AWSVPNClientApp: App {
    @State private var vpnManager = VPNManager()

    var body: some Scene {
        MenuBarExtra(
            vpnManager.isAnyConnected ? "VPN Connected" : "VPN",
            systemImage: vpnManager.isAnyConnected ? "lock.fill" : "lock.open"
        ) {
            StatusMenuView()
                .environment(vpnManager)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

### Reading @Observable via @Environment in child view

```swift
// Source: Apple Developer Documentation — @Observable + @Environment
struct StatusMenuView: View {
    @Environment(VPNManager.self) private var vpnManager

    var body: some View {
        Button("Quit AWSVPNClient") {
            NSApplication.shared.terminate(nil)
        }
    }
}
```

### Config directory creation (idempotent, safe every launch)

```swift
// Source: Apple Developer Documentation — FileManager
// https://developer.apple.com/documentation/foundation/filemanager/1407884-createdirectory

let configsDir = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("AWSVPNClient/configs", isDirectory: true)

try FileManager.default.createDirectory(
    at: configsDir,
    withIntermediateDirectories: true,
    attributes: nil
)
```

### Verifying rpath after build

```bash
# Run from project directory after building
otool -L "$(find . -name aws-connect -not -path '*/DerivedData*' | head -1)"
# Expected: @rpath/VPNCore.framework/... in output
# If absolute path: rpath is not set correctly

# Also verify the framework resolves at runtime:
DYLD_PRINT_LIBRARIES=1 AWSVPNClient.app/Contents/MacOS/aws-connect 2>&1 | grep VPNCore
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSStatusItem` (AppKit) | `MenuBarExtra` (SwiftUI) | macOS 13 / 2022 | SwiftUI-native menu bar; no AppDelegate needed for basic setup |
| `@ObservableObject + @Published + @StateObject` | `@Observable + @State + @Environment` | Swift 5.9 / macOS 14 / 2023 | Fine-grained view updates; cleaner dependency injection |
| `@StateObject` to hold observable | `@State` to hold `@Observable` | Swift 5.9 | `@StateObject` is for `ObservableObject` only; mixing patterns breaks tracking |

**Deprecated/outdated:**
- `@StateObject` with `@Observable`: Do not use. `@StateObject` is specifically for `ObservableObject`. Using it with `@Observable` compiles but does not trigger view updates correctly.
- `LSUIElement` via AppDelegate + `NSApp.setActivationPolicy(.accessory)`: Still works but unnecessary when using `MenuBarExtra` — setting LSUIElement in Info.plist is the correct, declarative approach.

---

## Open Questions

1. **rpath spike outcome**
   - What we know: The planned layout (CLI inside app bundle, `@executable_path/../Frameworks/`) is architecturally correct
   - What's unclear: Whether Xcode 16.3 auto-configures the CLI target's runpath when you set the "Copy Files" destination, or whether manual `RUNPATH_SEARCH_PATHS` setting is required
   - Recommendation: The spike task is mandatory per CONTEXT.md. If it fails (dyld error), pivot to a local SPM package for VPNCore before writing any Phase 2 code.

2. **Config directory creation placement: AppDelegate vs. VPNManager init**
   - What we know: Both work; CONTEXT.md marks this as Claude's Discretion
   - What's unclear: `@Observable @MainActor` class init runs on the main actor; FileManager directory creation is fast and synchronous — no issues calling it from `VPNManager.init()`
   - Recommendation: Call `createConfigDirectoryIfNeeded()` from `VPNManager.init()`. This keeps config-related logic inside VPNCore and avoids an AppDelegate. Wrap in `try?` — a missing Application Support directory is recoverable (will just have no configs).

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | None detected — this is a greenfield Xcode project |
| Config file | None — Wave 0 gap |
| Quick run command | `xcodebuild test -project AWSVPNClient.xcodeproj -scheme AWSVPNClient -destination 'platform=macOS'` (once test target exists) |
| Full suite command | Same — no distinction at this scale |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCAF-01 | All three targets build without errors | Build verification | `xcodebuild build -project AWSVPNClient.xcodeproj -scheme AWSVPNClient` | ❌ Wave 0 — project doesn't exist yet |
| SCAF-01 | CLI can import VPNCore (rpath spike) | Manual smoke test | `otool -L .../aws-connect \| grep VPNCore` | ❌ Wave 0 |
| SCAF-02 | App shows no Dock icon on launch | Manual observation | Launch app, observe Dock | ❌ Wave 0 |
| SCAF-02 | Quit button terminates app cleanly | Manual test | Click Quit, verify process exits | ❌ Wave 0 |

Note: SCAF-01 and SCAF-02 are infrastructure/UI requirements best verified manually during the phase. No unit test framework is justified for scaffold-only work. The build command acts as the automated gate.

### Sampling Rate
- **Per task commit:** `xcodebuild build -project AWSVPNClient.xcodeproj -scheme AWSVPNClient 2>&1 | tail -5` (clean build)
- **Per wave merge:** Same build command + manual smoke test (launch app, verify no Dock icon, click Quit)
- **Phase gate:** Build green + manual smoke tests pass before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Xcode project does not yet exist — creation is Wave 1 work
- [ ] No test target — acceptable for Phase 1 (scaffold only); test infrastructure introduced in Phase 2 or 3 when there is testable logic in VPNCore

*(No existing test infrastructure to extend — project is greenfield)*

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — MenuBarExtra: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- Apple Developer Documentation — MenuBarExtraStyle: https://developer.apple.com/documentation/swiftui/menubarextrastyle
- Apple Developer Documentation — FileManager.createDirectory: https://developer.apple.com/documentation/foundation/filemanager/1407884-createdirectory
- Apple Developer Documentation — Observation (@Observable): https://developer.apple.com/documentation/Observation
- `.planning/research/STACK.md` — full stack decisions for this project
- `.planning/research/ARCHITECTURE.md` — target layout and wiring patterns
- `.planning/research/PITFALLS.md` — Pitfalls 7, 8, 10, 13 (all Phase 1 relevant)

### Secondary (MEDIUM confidence)
- Livefront: How to add a dynamic Swift framework to a Command Line Tool — rpath wiring guide
- Apple Developer Forums thread 731822 — @Observable + @MainActor interaction under Swift 6
- Nil Coalescing: Build a macOS menu bar utility in SwiftUI — LSUIElement + MenuBarExtra walkthrough
- Swift Forums: @Observable macro conflicting with @MainActor — resolution: annotate App struct with @MainActor

### Tertiary (LOW confidence — needs validation in spike)
- Dynamic framework rpath resolves at runtime for unsigned CLI inside app bundle (`@executable_path/../Frameworks/`) — architecturally sound but must be confirmed by build spike

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Swift 6.1 / SwiftUI / @Observable are all verified Apple APIs; versions confirmed against STACK.md
- Architecture: HIGH for target structure and MenuBarExtra wiring; MEDIUM for rpath resolution (requires spike)
- Pitfalls: HIGH — drawn from project-specific PITFALLS.md backed by Apple Developer Forums and community sources
- @MainActor + @Observable conflict: MEDIUM — resolution identified (annotate App struct) but Swift 6 behavior is compiler-version sensitive

**Research date:** 2026-03-18
**Valid until:** 2026-06-18 (stable APIs; 90 days reasonable for Swift 6.1 / macOS 14 ecosystem)
