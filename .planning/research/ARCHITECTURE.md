# Architecture Patterns

**Domain:** Swift macOS menu bar app with background subprocess management
**Researched:** 2026-03-17
**Confidence:** MEDIUM-HIGH (Core patterns from Apple docs + community sources; NWListener HTTP framing is LOW)

---

## Recommended Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│  AWSVPNClient.app (macOS App Bundle)                        │
│                                                             │
│  ┌─────────────────┐    ┌──────────────────────────────┐   │
│  │  SwiftUI Layer  │    │  VPNManager (@Observable)    │   │
│  │                 │◄───│                              │   │
│  │  MenuBarExtra   │    │  [VPNConnection] state       │   │
│  │  StatusMenu     │    │  connect(config:)            │   │
│  │  ConfigList     │    │  disconnect(name:)           │   │
│  └─────────────────┘    │  status(name:) → State       │   │
│                         └──────────────┬─────────────┘   │
│                                        │ owns              │
│            ┌───────────────────────────┼────────────────┐  │
│            │                           │                │  │
│     ┌──────▼──────┐   ┌───────────────▼──────┐         │  │
│     │ IPCServer   │   │  [VPNConnection]      │         │  │
│     │ NWListener  │   │  Process (openvpn)    │         │  │
│     │ Unix socket │   │  SAMLServer           │         │  │
│     │ daemon.sock │   │  NWListener :35001    │         │  │
│     └──────┬──────┘   └───────────────────────┘         │  │
│            │                                             │  │
└────────────┼─────────────────────────────────────────────┘  │
             │ reads/writes                                    │
             ▼
┌─────────────────────┐       ┌─────────────────────────────┐
│  aws-connect (CLI)  │       │  sudo openvpn (subprocess)  │
│  Command line tool  │       │  per-connection Process      │
│  Links VPNCore.fwk  │       │  stdout → log file + state  │
└─────────────────────┘       └─────────────────────────────┘
```

---

## Xcode Project Structure

### Multi-Target Layout

```
AWSVPNClient.xcodeproj
├── VPNCore/                    ← Framework target (shared library)
│   ├── VPNConfig.swift         # Config parsing (port from config.rs)
│   ├── VPNConnection.swift     # Per-connection state + Process lifecycle
│   ├── VPNManager.swift        # @Observable aggregate; owns all connections
│   ├── SAMLServer.swift        # NWListener on 127.0.0.1:35001
│   ├── IPCServer.swift         # NWListener on Unix socket
│   └── IPCClient.swift         # Used by CLI target to send commands
│
├── AWSVPNClient/               ← App target (macOS App)
│   ├── AWSVPNClientApp.swift   # @main, MenuBarExtra scene
│   ├── StatusMenuView.swift    # Menu contents, reads VPNManager
│   └── Assets.xcassets
│
└── aws-connect/                ← Command Line Tool target
    └── main.swift              # Arg parsing, IPCClient calls
```

**Build order:** VPNCore must be built first. App and CLI both link against VPNCore.framework.

### Why a Framework, Not a Swift Package

The CLI target needs to embed framework dylibs because Swift command line tools cannot use `@rpath`-relative frameworks without a bundle structure. The framework is embedded inside the `.app` bundle at `Contents/Frameworks/VPNCore.framework`, and the CLI tool copies it adjacent to the binary or uses an explicit `@rpath` runpath search pointing at `@executable_path/../Frameworks` (mirroring the app bundle layout).

Confidence: MEDIUM — the rpath embedding for unsigned CLI tools sharing a framework has known friction. This warrants a test build early in Phase 1.

---

## Component Boundaries

| Component | Target | Responsibility | Communicates With |
|-----------|--------|---------------|-------------------|
| `VPNManager` | VPNCore | Single @Observable source of truth; owns `[VPNConnection]` array | SwiftUI views (read), IPCServer (write) |
| `VPNConnection` | VPNCore | Per-connection state machine; owns `Process`, `SAMLServer` | `VPNManager` (reports state), log file |
| `SAMLServer` | VPNCore | NWListener on TCP 127.0.0.1:35001; delivers SAML response to `VPNConnection` via async continuation | `VPNConnection` |
| `IPCServer` | VPNCore | NWListener on Unix socket `daemon.sock`; parses CLI commands and calls `VPNManager` | `VPNManager` |
| `IPCClient` | VPNCore | NWConnection to `daemon.sock`; sends JSON command, reads response | CLI tool's `main.swift` |
| `StatusMenuView` | App | SwiftUI view; reads `VPNManager` via `@Environment`; no business logic | `VPNManager` (read only) |
| `aws-connect` CLI | CLI tool | Arg parsing; delegates entirely to `IPCClient` | `IPCServer` in running app |

---

## @Observable + MenuBarExtra Wiring

### Pattern (HIGH confidence — verified with Apple docs + community sources)

The `@Observable` macro (Swift 5.9 / macOS 14) replaces `ObservableObject + @Published`. The key difference: in an App struct, use `@State` (not `@StateObject`) to own the object's lifecycle.

```swift
// AWSVPNClientApp.swift
@main
struct AWSVPNClientApp: App {
    @State private var vpnManager = VPNManager()   // @State owns lifecycle

    var body: some Scene {
        MenuBarExtra("VPN", systemImage: vpnManager.menuBarIcon) {
            StatusMenuView()
                .environment(vpnManager)            // inject by type
        }
    }
}

// StatusMenuView.swift
struct StatusMenuView: View {
    @Environment(VPNManager.self) private var vpnManager  // read by type

    var body: some View {
        ForEach(vpnManager.connections) { conn in
            ConnectionRowView(connection: conn)
        }
    }
}

// VPNManager.swift (in VPNCore)
@Observable
final class VPNManager {
    var connections: [VPNConnection] = []

    var menuBarIcon: String {
        connections.contains(where: { $0.state == .connected })
            ? "lock.fill" : "lock.open"
    }
}
```

**Note on macOS 13 (Ventura) compatibility:** `@Observable` requires macOS 14+. If macOS 13 support is needed, use `ObservableObject + @Published` and `@StateObject` / `@EnvironmentObject`. Given the project targets macOS 13+ for `MenuBarExtra`, this is a real constraint. Options:
1. Raise minimum to macOS 14 — simplest, loses Ventura support.
2. Use `ObservableObject` throughout — compatible with macOS 13, slightly more boilerplate.
3. `#available` branching — high complexity, not recommended.

**Recommendation:** Raise minimum to macOS 14 (Sonoma). Ventura was released October 2022; Sonoma October 2023. By the time this app is used, nearly all users will be on 14+. This unblocks `@Observable` and avoids the compatibility fork. Confidence: MEDIUM.

---

## Data Flow

```
User clicks config in menu
        │
        ▼
StatusMenuView.connect(config)
        │  calls
        ▼
VPNManager.connect(config:)           ← @MainActor
        │  creates
        ▼
VPNConnection(config:)                 ← stored in connections[]
        │  Task { await self.run() }
        ▼
VPNConnection.run()                    ← async, background Task
  1. getAuthChallenge()                  (blocking Process call, run on detached task)
  2. SAMLServer.start()                  (NWListener bind)
  3. NSWorkspace.open(challengeURL)      (browser opens)
  4. await SAMLServer.samlResponse       (async continuation, waits for POST)
  5. SAMLServer.stop()
  6. spawnOpenVPN(sid:saml:)             (Process, streams stdout to log)
  7. state = .connected
  8. await process termination           (continuations on Process.terminationHandler)
  9. state = .disconnected
```

State changes in `VPNConnection` must dispatch to `@MainActor` to update `@Observable` properties safely:

```swift
await MainActor.run { self.state = .connected }
```

---

## Process Lifecycle Management

### Spawning OpenVPN (MEDIUM confidence)

```swift
// Conceptual — not final code
final class VPNConnection {
    private var process: Process?

    func spawnOpenVPN(...) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = [openvpnPath, "--config", configPath, ...]

        // Pipe stdout to log file AND state detection
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        // Async stdout monitoring via FileHandle + AsyncStream
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            // Write to log file
            // Check for "Initialization Sequence Completed" → state = .connected
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.state = .disconnected
                self?.process = nil
            }
        }

        try p.run()
        self.process = p
    }

    func stop() {
        process?.terminate()    // SIGTERM to openvpn (sudo-owned process)
        process = nil
    }
}
```

**Sudo process termination caveat:** `process.terminate()` sends SIGTERM to the `sudo` wrapper, not to the `openvpn` child process. This is a known macOS pitfall. The correct approach is to use `killpg` (kill the process group) or configure openvpn with `--management` for clean shutdown. The Rust implementation used `Command::new("sudo").status()` which blocks — the Swift version must be non-blocking. Confidence: MEDIUM (known issue, mitigation patterns exist but need validation).

### App Quit — Terminating All Connections

```swift
// In App target — use NSApplicationDelegate via @NSApplicationDelegateAdaptor
class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationWillTerminate(_ notification: Notification) {
        // Synchronous teardown — no async here (app exits immediately after)
        VPNManager.shared.terminateAll()    // calls process.terminate() on each
    }
}
```

Note: `applicationWillTerminate` is reliable for macOS apps (unlike iOS). Do NOT use Swift async Task inside this method — the runtime is shutting down and tasks may not execute. Confidence: MEDIUM.

---

## NWListener: Unix Socket IPC Server

The app listens on `~/Library/Application Support/AWSVPNClient/daemon.sock` for JSON commands from the CLI tool.

### Setup Pattern (MEDIUM confidence — Apple Forums + community)

```swift
// IPCServer.swift (conceptual)
import Network

final class IPCServer {
    private var listener: NWListener?

    func start(socketPath: String) throws {
        let params = NWParameters()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { state in
            // handle ready / failed
        }
        listener.newConnectionHandler = { connection in
            self.handleConnection(connection)
        }
        listener.start(queue: .global())
        self.listener = listener
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
            guard let data, let command = try? JSONDecoder().decode(IPCCommand.self, from: data) else { return }
            // dispatch to VPNManager, send response
        }
    }
}
```

**Socket file cleanup:** The `.sock` file persists on disk after app exit. On next launch, `NWListener` will fail to bind if the stale file exists. The app must delete the socket file before binding: `try? FileManager.default.removeItem(atPath: socketPath)`. Confidence: HIGH (documented NWListener behavior).

**Sandboxing:** This project is unsigned and unsandboxed (personal-use tool). Unix domain socket IPC works without entitlements in this context. If the app were ever sandboxed, `com.apple.security.network.server` and specific socket path entitlements would be required. Confidence: HIGH.

---

## NWListener: SAML HTTP Server (127.0.0.1:35001)

The SAML server receives a single HTTP POST from the browser's redirect after IdP authentication.

### Approach

Network.framework does not ship a built-in HTTP framer. Two options:

**Option A: Raw TCP + manual HTTP parsing (LOW confidence — complex)**
Use `NWListener` with `.tcp` parameters, read raw bytes, parse the HTTP request manually (headers + body). This is what NWHTTPProtocol and ko9.org's simple web server do. The approach works but HTTP parsing is tedious and error-prone.

**Option B: Embed a minimal HTTP library**
Use `swift-nio` or a lightweight library inside VPNCore. This adds a dependency but is more robust.

**Recommended: Option A with a narrow scope.** The SAML server only needs to:
- Accept one TCP connection
- Read until `\r\n\r\n` (end of headers)
- Read `Content-Length` bytes of body
- Extract `SAMLResponse=...` from URL-encoded body
- Return a 200 plaintext response
- Stop listening

This is ~60 lines of deterministic byte parsing. The Rust version used axum for this same narrow purpose — replacing with NWListener raw TCP is justified to avoid adding a server framework dependency. Confidence: MEDIUM (pattern is known, implementation needs careful testing).

The `SAMLServer` should deliver the SAML response via `CheckedContinuation`:

```swift
func waitForSAMLResponse() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        self.pendingContinuation = continuation
        // NWConnection receive loop sets continuation.resume(returning: saml)
    }
}
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Blocking the Main Thread with Process
**What goes wrong:** `Process.waitUntilExit()` blocks. Calling it on `@MainActor` freezes the menu bar and the entire app.
**Instead:** Run the `connect()` flow in a `Task { }` (Swift concurrency). Use `Process.terminationHandler` (callback-based) or a `CheckedContinuation` wrapper to await process exit without blocking.

### Anti-Pattern 2: @StateObject with @Observable
**What goes wrong:** Using `@StateObject` with an `@Observable` (not `ObservableObject`) object compiles but does not trigger view updates correctly. SwiftUI's tracking infrastructure only hooks into `@Observable` when the view accesses properties through `@State` or `@Environment`.
**Instead:** `@State private var vpnManager = VPNManager()` in the App struct; `@Environment(VPNManager.self)` in child views.

### Anti-Pattern 3: Sharing State via Global Singleton
**What goes wrong:** A `VPNManager.shared` global is easy to reach from anywhere but breaks testability and makes the data flow implicit. The IPCServer needs to call VPNManager — if it holds a reference injected at init, the dependency is explicit and testable.
**Instead:** Inject `VPNManager` into `IPCServer` at construction time. In the App struct, create one instance and pass it everywhere.

### Anti-Pattern 4: Stale Socket File on Restart
**What goes wrong:** App crashes or force-quits without cleaning up `daemon.sock`. Next launch: `NWListener` fails to bind, IPC is broken, CLI exits with "app not running" even when it is.
**Instead:** Delete the socket path before binding on every app launch. Wrap in `try?` — it's fine if the file doesn't exist.

### Anti-Pattern 5: Killing sudo-wrapped Processes with SIGTERM
**What goes wrong:** `process.terminate()` on the `sudo openvpn` Process sends SIGTERM to `sudo`, which may not propagate to the openvpn child. VPN tunnel stays up after the app thinks it disconnected.
**Instead:** Either (a) use `--management` socket for openvpn shutdown, or (b) after sending SIGTERM, give openvpn 2 seconds then `SIGKILL` the process group via `kill(-pgid, SIGKILL)`. Option (b) is simpler and sufficient for a personal tool. Confidence: MEDIUM.

---

## Build Order Implications

1. **VPNCore.framework** — built first; no UI dependencies; pure Swift + Foundation + Network.framework
2. **AWSVPNClient.app** — built second; links VPNCore; adds SwiftUI layer only
3. **aws-connect CLI** — built third; links VPNCore; no UI; uses only `IPCClient` from the framework

The CLI tool must copy `VPNCore.framework` into a `Frameworks/` directory adjacent to its binary, and set `Runpath Search Paths` to `@executable_path/Frameworks`. This requires a custom "Copy Files" build phase in Xcode. Without it, the CLI binary fails to load the framework dylib at runtime with a `dyld` error.

If this rpath wiring proves too painful for an unsigned personal tool, a simpler alternative is to statically link VPNCore by using a Swift Package with `.target` instead of a framework. SPM static libraries avoid the rpath problem entirely. Trade-off: Xcode project structure becomes SPM-driven rather than target-driven. This is worth evaluating in Phase 1.

---

## Scalability Considerations

This is a single-user personal tool. Scalability is not a concern. The multi-connection model (supporting simultaneous VPN connections to different configs) is the relevant "scale" dimension:

| Concern | Approach |
|---------|---------|
| Multiple simultaneous VPNs | `[VPNConnection]` array in VPNManager; each has its own `Process` and `SAMLServer` instance |
| SAML port conflict | Each `VPNConnection` must bind port 35001 in sequence, not simultaneously. Only one SAML auth flow should be in-flight at a time; the `VPNManager` should serialize auth. |
| Log files | One file per connection: `~/Library/Logs/AWSVPNClient/<config-name>.log`. FileHandle append only. |

---

## Sources

- [Apple Developer Documentation: MenuBarExtra](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) — HIGH confidence
- [Apple Developer Documentation: NWListener](https://developer.apple.com/documentation/network/nwlistener) — HIGH confidence
- [nilcoalescing.com: Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — MEDIUM confidence
- [Apple Developer Forums: NWListener with NWEndpoint.unix](https://developer.apple.com/forums/thread/719635) — MEDIUM confidence
- [Livefront: How to add a dynamic Swift framework to a Command Line Tool](https://livefront.com/writing/how-to-add-a-dynamic-swift-framework-to-a-command-line-tool/) — MEDIUM confidence
- [Jesse Squires: SwiftUI app lifecycle issues with ScenePhase](https://www.jessesquires.com/blog/2024/06/29/swiftui-scene-phase/) — MEDIUM confidence
- [Jesse Squires: Swift @Observable macro is not a drop-in replacement](https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/) — MEDIUM confidence
- [arturgruchala.com: Asynchronous process handling in Swift](https://arturgruchala.com/asynchronous-process-handling/) — MEDIUM confidence
- [helje5/NWHTTPProtocol — NWHTTPServer.swift](https://github.com/helje5/NWHTTPProtocol/blob/develop/Sources/NWHTTPServer/HTTPServer.swift) — MEDIUM confidence (HTTP parsing pattern)
- [Swift Forums: NWListener Unix socket — Apple Developer Forums thread 756756](https://developer.apple.com/forums/thread/756756) — MEDIUM confidence
