# Phase 4: IPC & CLI - Research

**Researched:** 2026-03-26
**Domain:** Network.framework (NWListener/NWConnection), Unix domain sockets, Swift 6 concurrency bridging, POSIX socket CLI
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Line-delimited JSON protocol — each message is one JSON object terminated by `\n`
- **D-02:** Request+response model — CLI sends a command, server replies before CLI exits
  - Request: `{"cmd":"connect","name":"corp-vpn"}\n`
  - Response: `{"ok":true}\n` or `{"ok":false,"error":"config not found"}\n`
  - Commands: `connect`, `disconnect`, `status`
- **D-03:** Status response embeds data inline: `{"ok":true,"configs":[{"name":"corp-vpn","state":"connected"},...]}\n`
- **D-04:** Silent on success — `aws-connect connect <name>` prints nothing and exits 0
- **D-05:** Errors go to stderr, exit non-zero — e.g. `error: config not found` or `Start the AWSVPNClient menu bar app first`
- **D-06:** Fire-and-forget semantics for connect/disconnect — send command, get ack, exit. Does NOT wait for VPN to fully connect.
- **D-07:** Status output: two plain aligned columns — `name` left-padded, `state` right
- **D-08:** No header row in status output — stays grep-friendly
- **D-09:** `failed` state shows error reason inline: `failed: <short message>` (≤30 char format from Phase 2)
- **D-10:** Configs listed alphabetically (matches menu sort order from Phase 3)
- **D-11:** Manual `CommandLine.arguments` — no new SPM dependencies
- **D-12:** Argument shape:
  - `aws-connect <name>` → connect
  - `aws-connect --disconnect <name>` → disconnect
  - `aws-connect status` → status
  - Any other input → print usage to stderr and exit 1

### Claude's Discretion

- **D-13:** Where `IPCServer` lives (VPNCore vs. App target) and how it hooks into VPNManager's `@MainActor` context
- **D-14:** Stale socket cleanup (IPC-01) approach — remove on launch if socket file exists but nothing is listening

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IPC-01 | App starts Unix domain socket server at `~/Library/Application Support/AWSVPNClient/daemon.sock` on launch; removes stale socket file on startup | NWListener + NWParameters.requiredLocalEndpoint; must `unlink()` / `FileManager.removeItem` before NWListener.start() — `allowLocalEndpointReuse` is broken on macOS |
| IPC-02 | `aws-connect <name>` sends connect command and exits | POSIX BSD socket (Darwin) in CLI: `socket()` → `connect()` → `write()` → `read()` → `close()` |
| IPC-03 | `aws-connect --disconnect <name>` sends disconnect command and exits | Same CLI pattern as IPC-02 |
| IPC-04 | `aws-connect status` prints table of all config names and their current state | Same CLI pattern; parses JSON response, formats two-column aligned table |
| IPC-05 | CLI prints clear error if socket not found | `connect()` returns -1 with ENOENT/ECONNREFUSED → print to stderr, exit 1 |
</phase_requirements>

---

## Summary

Phase 4 adds a Unix domain socket IPC layer between the running menu bar app and the `aws-connect` companion CLI. The app side uses Network.framework (NWListener + NWConnection) following the same pattern already used by SAMLServer — the only difference is replacing a TCP port with a Unix socket path via `NWParameters.requiredLocalEndpoint`. The CLI side is a synchronous command-line tool that uses raw POSIX BSD socket calls (Darwin module: `socket()`, `connect()`, `write()`, `read()`, `close()`) because Network.framework's NWConnection is not suitable for synchronous one-shot use in a CLI.

The hardest design question is where IPCServer lives and how it bridges NWConnection callbacks (which fire on a private DispatchQueue) to VPNManager (which is `@MainActor`). The established SAMLServer pattern — `final class @unchecked Sendable` + serialized DispatchQueue + `Task { @MainActor in ... }` dispatch — is the correct model and avoids introducing actors.

**Primary recommendation:** IPCServer lives in the App target (not VPNCore), is instantiated in `AWSVPNClientApp` after `VPNManager()`, and holds a `weak var vpnManager: VPNManager?`. The CLI uses POSIX Darwin socket calls — no Network.framework on the client side.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Network.framework | macOS 14+ (built-in) | NWListener / NWConnection for Unix socket server | Already used for SAMLServer; modern replacement for BSD sockets on Apple platforms |
| Foundation | macOS 14+ (built-in) | JSONEncoder/JSONDecoder, FileManager, Codable | Standard; zero dependencies |
| Darwin (module) | macOS 14+ (built-in) | POSIX socket calls in CLI: `socket()`, `connect()`, `write()`, `read()` | Required for synchronous blocking I/O in a non-async CLI tool |

### No New Dependencies
Per D-11, no new SPM dependencies are introduced. Everything needed is in Swift's standard library + Apple system frameworks.

### Installation
```bash
# No new packages — Network.framework and Darwin are always available
```

---

## Architecture Patterns

### Recommended File Layout
```
VPNCore/
├── (no changes — IPCServer does NOT go here)
AWSVPNClient/
├── AWSVPNClientApp.swift   # Instantiate IPCServer after VPNManager
├── IPCServer.swift         # NEW: NWListener-based IPC server
├── IPCMessage.swift        # NEW: Codable request/response structs
aws-connect/
└── main.swift              # REPLACE stub with full CLI implementation
```

### Pattern 1: IPCServer as App-Target Class (D-13 resolution)

**What:** `IPCServer` is a `final class @unchecked Sendable` in the **App target**, holding a `weak var vpnManager: VPNManager?`. It mirrors the `SAMLServer` pattern exactly: private `DispatchQueue` for all NWListener/NWConnection callbacks, `Task { @MainActor in ... }` dispatch for VPNManager calls.

**Why App target, not VPNCore:** VPNCore is a framework that the CLI also loads. The CLI does not run a server. Putting IPCServer in VPNCore would add NWListener to the CLI's framework surface unnecessarily. The established precedent (`_updateAtexitPIDs` is in VPNCore not app target) exists for the reverse direction — code that must be in the framework because the CLI calls it. IPCServer is never called by the CLI.

**Why not an actor:** SAMLServer is `@unchecked Sendable` + GCD queue (not an actor). Following the same pattern keeps the codebase consistent and avoids the actor reentrancy / suspension footguns when GCD callbacks call async methods.

```swift
// Source: established SAMLServer.swift pattern (VPNCore/SAMLServer.swift)
public final class IPCServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.local.IPCServer", qos: .utility)
    private weak var vpnManager: VPNManager?

    init(vpnManager: VPNManager, socketPath: String) throws {
        self.vpnManager = vpnManager
        // Remove stale socket file BEFORE starting listener (see Pitfall 1)
        try? FileManager.default.removeItem(atPath: socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        // NOTE: do NOT set allowLocalEndpointReuse — it is broken on macOS (see Pitfall 2)
        listener = try NWListener(using: params)

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("IPCServer failed: \(error)")
            }
        }
        listener.start(queue: queue)
    }
    // ...
}
```

**When to use:** Always — this is the only IPCServer architecture for this project.

### Pattern 2: Unix Socket Path

**What:** The socket path is derived from `VPNManager.configsDirectory` (which already computes the Application Support URL) minus the `configs/` component:

```swift
// Source: VPNManager.swift (existing pattern)
static let socketPath: String = {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AWSVPNClient/daemon.sock")
        .path
}()
```

**Important:** The path `~/Library/Application Support/AWSVPNClient/daemon.sock` resolves to an absolute path like `/Users/jason/Library/Application Support/AWSVPNClient/daemon.sock`. The `~` is shell expansion — code must use `FileManager` to resolve it, not a literal string.

### Pattern 3: NWListener Unix Socket Setup vs. TCP

**Key differences from SAMLServer (TCP on port 35001):**

| Aspect | SAMLServer (TCP) | IPCServer (Unix) |
|--------|-----------------|------------------|
| Port | `NWListener(using: params, on: 35001)` | No port — use `NWParameters.requiredLocalEndpoint` |
| Address | Implicit localhost | Explicit path via `NWEndpoint.unix(path:)` |
| Stale state | Port released on process exit | Socket FILE persists on disk after crash |
| Transport | `NWParameters.tcp` | `NWParameters()` + `NWProtocolTCP.Options()` in stack |
| Reuse | `params.allowLocalEndpointReuse = true` (works) | `allowLocalEndpointReuse` is BROKEN — must unlink manually |

The correct NWParameters setup for a Unix domain socket:
```swift
// Source: Apple Developer Forums thread/719635 (verified pattern)
let params = NWParameters()
params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
// Do NOT set allowLocalEndpointReuse — broken on macOS
```

### Pattern 4: Line-Delimited JSON Receive Loop (Server Side)

The same `receive(minimumIncompleteLength:maximumLength:)` pattern from SAMLServer works for line-delimited JSON. The server accumulates data until it finds `\n`, then decodes the JSON:

```swift
// Source: established pattern (SAMLServer.swift + timweiss.net/blog/2024-01-24-...)
private func receiveRequest(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        [weak self] data, _, isComplete, error in
        guard let self else { return }
        var buf = buffer
        if let data { buf.append(data) }

        if let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buf[..<nl]
            self.handleRequest(lineData, on: connection)
            return
        }
        if !isComplete && error == nil {
            self.receiveRequest(connection, buffer: buf)
        }
    }
}
```

### Pattern 5: MainActor Dispatch from NWConnection Callback

VPNManager is `@Observable @MainActor`. NWConnection callbacks fire on IPCServer's private DispatchQueue. The bridge is identical to what `spawnSudoOpenvpn` already uses:

```swift
// Source: VPNManager.swift spawnSudoOpenvpn terminationHandler (established pattern)
private func handleRequest(_ data: Data, on connection: NWConnection) {
    // This runs on self.queue (IPCServer's DispatchQueue)
    guard let request = try? JSONDecoder().decode(IPCRequest.self, from: data) else {
        sendResponse(IPCResponse(ok: false, error: "invalid request"), on: connection)
        return
    }

    Task { @MainActor [weak self] in
        guard let vpnManager = self?.vpnManager else {
            self?.sendResponse(IPCResponse(ok: false, error: "app shutting down"), on: connection)
            return
        }
        // Now safely on @MainActor — can read vpnManager.configs / vpnManager.connections
        switch request.cmd {
        case "connect":
            // find config, call vpnManager.connect() — fire-and-forget (D-06)
        case "disconnect":
            // find config, call vpnManager.disconnect()
        case "status":
            // read vpnManager.configs and vpnManager.connections, build response
        }
    }
}
```

### Pattern 6: CLI — POSIX Darwin Socket (Synchronous)

The CLI is a command-line tool with no async runtime. Network.framework's NWConnection is callback/async-based and requires a RunLoop. POSIX BSD socket calls are synchronous and are the correct tool for a CLI that connects, writes one line, reads one line, and exits.

```swift
// Source: Darwin module (POSIX) — standard Unix socket client pattern
import Foundation
import Darwin

func connectToSocket(path: String) -> Int32? {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        path.withCString { src in
            _ = Darwin.strncpy(
                UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                src,
                MemoryLayout.size(ofValue: addr.sun_path) - 1
            )
        }
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        Darwin.close(fd)
        return nil
    }
    return fd
}
```

Reading the response line (synchronous):
```swift
func readLine(fd: Int32) -> String? {
    var result = Data()
    var byte = UInt8(0)
    while Darwin.read(fd, &byte, 1) == 1 {
        if byte == UInt8(ascii: "\n") { break }
        result.append(byte)
    }
    return result.isEmpty ? nil : String(data: result, encoding: .utf8)
}
```

**Why not NWConnection in the CLI:** NWConnection requires either a RunLoop (`dispatchMain()`) or a structured concurrency runtime (`@main async`). A single-shot CLI tool that blocks until response is simplest with POSIX calls. Using `@main async` would work but adds complexity for no benefit and contradicts the "no new SPM dependencies" decision.

### Pattern 7: Codable Message Structs

```swift
// IPCMessage.swift (new file in App target — or VPNCore if shared)
struct IPCRequest: Codable {
    let cmd: String      // "connect" | "disconnect" | "status"
    let name: String?    // present for connect/disconnect
}

struct IPCConfigStatus: Codable {
    let name: String
    let state: String    // "connected" | "disconnected" | "authenticating" | "disconnecting" | "failed: <msg>"
}

struct IPCResponse: Codable {
    let ok: Bool
    let error: String?
    let configs: [IPCConfigStatus]?   // present for status response only
}
```

**Note on placement:** These structs are needed by both the CLI (to decode responses) and the App (to encode responses). Options:
1. Put in VPNCore — clean, avoids duplication, CLI already imports VPNCore
2. Put in App target — CLI cannot use them directly, must redefine

**Recommendation (D-13 discretion):** Put `IPCMessage.swift` in **VPNCore** (the shared framework). The CLI already imports VPNCore and the structs are pure data with no AppKit/SwiftUI dependencies. The `IPCServer` class itself stays in the App target.

### Pattern 8: Status Table Formatting

```swift
// D-07/D-08/D-09/D-10: two-column table, no header, alphabetical, failed shows reason
func formatStatusTable(_ configs: [IPCConfigStatus]) -> String {
    let maxNameLen = configs.map(\.name.count).max() ?? 0
    return configs
        .sorted { $0.name < $1.name }
        .map { c in
            let pad = String(repeating: " ", count: maxNameLen - c.name.count + 4)
            return "\(c.name)\(pad)\(c.state)"
        }
        .joined(separator: "\n")
}
```

### Pattern 9: ConnectionState → String for IPC

`ConnectionState` (in VPNCore) needs a string representation for IPC. The correct place is a computed property on `ConnectionState`:

```swift
// Add to VPNCore/ConnectionState.swift
public var ipcLabel: String {
    switch self {
    case .disconnected:   return "disconnected"
    case .authenticating: return "authenticating"
    case .connected:      return "connected"
    case .disconnecting:  return "disconnecting"
    case .failed(let msg): return "failed: \(msg)"
    }
}
```

### Anti-Patterns to Avoid

- **Do not use `allowLocalEndpointReuse = true` for Unix sockets:** It is a known broken API on macOS (rdar://FB8658821 — never fixed). Always delete the socket file manually before calling `listener.start()`.
- **Do not use NWConnection in the CLI:** It requires async dispatch or RunLoop. Use POSIX Darwin calls for the synchronous CLI use case.
- **Do not put IPCServer in VPNCore:** The CLI loads VPNCore but should not instantiate a server. IPCServer belongs to the App target.
- **Do not call `vpnManager.connect()` without `try`:** It is `throws`. The IPCServer must catch and serialize the error into `{"ok":false,"error":"..."}`.
- **Do not use `RunLoop.main.run()` in main.swift:** The CLI should exit after receiving the response. Using RunLoop is a trap that turns the CLI into a daemon.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Line framing | Custom byte accumulator | `receive(minimumIncompleteLength:1, maximumLength:65536)` with `\n` scan | Already proven in SAMLServer; two-phase receive loop is ~10 lines |
| JSON encode/decode | String templates | `Codable` structs + `JSONEncoder`/`JSONDecoder` | Type-safe, handles escaping, maintains Swift 6 Sendable |
| Unix socket path creation | Manual string building | `FileManager.default.urls(for: .applicationSupportDirectory...)` | Platform-aware, handles sandbox path differences |
| Error propagation | Multiple error types | Single `IPCResponse(ok: false, error: String)` | Matches D-02 protocol; CLI only cares about the string |

**Key insight:** The POSIX socket layer for the CLI is 30-40 lines. Don't add SwiftNIO or async-http-client for a one-shot CLI request.

---

## Common Pitfalls

### Pitfall 1: `allowLocalEndpointReuse` Doesn't Work on macOS for Unix Sockets
**What goes wrong:** Setting `params.allowLocalEndpointReuse = true` does nothing. If the socket file exists from a previous crash, `listener.start()` fires `.failed` with "Address already in use."
**Why it happens:** Confirmed Apple bug (rdar://FB8658821). The property is ignored for Unix domain sockets on macOS.
**How to avoid:** Call `try? FileManager.default.removeItem(atPath: socketPath)` immediately before calling `listener.start(queue:)`. This is the standard POSIX `unlink()`-before-bind pattern.
**Warning signs:** `NWListener` transitions to `.failed(.posix(.EADDRINUSE))` immediately on start.

### Pitfall 2: NWListener Cannot Be Restarted After `.cancel()`
**What goes wrong:** Calling `listener.cancel()` and then `listener.start()` on the same instance causes undefined behavior. There is a known Swift bug (SR-13918).
**Why it happens:** NWListener state machine does not support restart.
**How to avoid:** Only start the listener once for the app's lifetime. No restart logic needed for this use case.
**Warning signs:** Listener reaches `.cancelled` state then refuses to restart.

### Pitfall 3: NWListener `newConnectionHandler` Must Be Set Before `start()`
**What goes wrong:** Connections arrive immediately after `start()`. If `newConnectionHandler` is set after `start()`, connections are dropped silently.
**Why it happens:** Same as SAMLServer Pitfall 12 — NWListener is documented to require both handlers set before `start()`.
**How to avoid:** Set `newConnectionHandler` and `stateUpdateHandler` before calling `listener.start(queue:)`. This is already the pattern in SAMLServer.
**Warning signs:** CLI connects but server never handles the request (silent drop).

### Pitfall 4: NWConnection Callbacks on Wrong Isolation Context
**What goes wrong:** NWConnection callbacks fire on the DispatchQueue passed to `connection.start(queue:)`, not on @MainActor. Calling `vpnManager.connect()` directly from the callback will produce Swift 6 concurrency errors ("sending non-Sendable type across isolation boundaries").
**Why it happens:** Swift 6 strict concurrency enforces that `@MainActor` methods can only be called from the main actor context.
**How to avoid:** Use `Task { @MainActor [weak self] in ... }` to hop to the main actor before accessing VPNManager. This is the same pattern used in `spawnSudoOpenvpn`'s `terminationHandler`.
**Warning signs:** Build errors: "Expression is 'async' but is not marked with 'await'" or "actor-isolated instance method 'connect' can not be referenced from a non-isolated context."

### Pitfall 5: CLI `connect()` Fails with ENOENT (App Not Running)
**What goes wrong:** `Darwin.connect()` returns -1 with `errno == ENOENT` or `ECONNREFUSED` when the socket file doesn't exist or the app isn't listening.
**Why it happens:** The socket file doesn't exist if the app was never started.
**How to avoid:** Check `connect()` return value. If < 0, print "Start the AWSVPNClient menu bar app first" to stderr and exit 1. This satisfies IPC-05.
**Warning signs:** `errno` is `ENOENT` (2) or `ECONNREFUSED` (61) on macOS.

### Pitfall 6: `sockaddr_un.sun_path` Buffer Length
**What goes wrong:** `sun_path` is a C fixed-length char array (104 bytes on macOS). If the socket path is too long, `strncpy` silently truncates, producing a corrupted path.
**Why it happens:** POSIX limitation; macOS uses 104 bytes for `sun_path`.
**How to avoid:** The path `~/Library/Application Support/AWSVPNClient/daemon.sock` resolves to approximately 60-70 characters for a typical username, well within the 103-character limit (null-terminated). Verify at runtime and fail with a clear error if path length > 103.
**Warning signs:** `connect()` returns -1 with `ENOENT` even though the file exists.

### Pitfall 7: Weak Reference to VPNManager During App Shutdown
**What goes wrong:** IPCServer holds `weak var vpnManager`. During app shutdown, `vpnManager` is deallocated before IPCServer. A CLI request arriving during shutdown would get a nil `vpnManager`.
**Why it happens:** Reference counting — App releases VPNManager before IPCServer's listener is cancelled.
**How to avoid:** In the `Task { @MainActor in ... }` block, guard `vpnManager` with a nil check and respond with `{"ok":false,"error":"app shutting down"}`. The CLI will print the error and exit.
**Warning signs:** IPC response never arrives; CLI hangs waiting for read.

### Pitfall 8: `find config by name` Must Handle Missing Config
**What goes wrong:** `aws-connect corp-vpn` where `corp-vpn` doesn't exist in `vpnManager.configs`. Without a nil check, `connect()` is called with a dangling config.
**Why it happens:** configs are loaded from disk; CLI arg is user-typed.
**How to avoid:** `vpnManager.configs.first(where: { $0.name == request.name })` — if nil, respond `{"ok":false,"error":"config not found"}`. This maps to D-05 behavior.
**Warning signs:** nil force-unwrap crash or sending wrong config to VPN.

---

## Code Examples

### Server: NWParameters for Unix Socket
```swift
// Verified pattern — Apple Developer Forums thread/719635 + VPNCore/SAMLServer.swift
let params = NWParameters()
params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
// Do NOT set allowLocalEndpointReuse — broken on macOS (rdar://FB8658821)
let listener = try NWListener(using: params)
```

### Server: Stale Socket Cleanup
```swift
// Remove before start — standard POSIX unlink-before-bind pattern
try? FileManager.default.removeItem(atPath: socketPath)
listener.start(queue: queue)
```

### Server: Send JSON Response
```swift
private func sendResponse(_ response: IPCResponse, on connection: NWConnection) {
    guard let data = try? JSONEncoder().encode(response) else { return }
    var line = data
    line.append(UInt8(ascii: "\n"))
    connection.send(content: line, completion: .contentProcessed { _ in
        connection.cancel()
    })
}
```

### CLI: Connect to Socket (POSIX)
```swift
// Darwin POSIX calls — synchronous, no async runtime needed
import Darwin

func openSocket(path: String) -> Int32? {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        path.withCString { cStr in
            _ = Darwin.strncpy(
                UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self),
                cStr, MemoryLayout.size(ofValue: addr.sun_path) - 1
            )
        }
    }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if ok != 0 { Darwin.close(fd); return nil }
    return fd
}
```

### CLI: Read Response Line (Synchronous)
```swift
func readLine(fd: Int32) -> Data? {
    var result = Data()
    var byte = UInt8(0)
    while Darwin.read(fd, &byte, 1) == 1 {
        if byte == UInt8(ascii: "\n") { return result }
        result.append(byte)
    }
    return result.isEmpty ? nil : result
}
```

### CLI: Argument Parsing (D-11/D-12)
```swift
// CommandLine.arguments[0] is the tool name
let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.count) {
case ("status", 1):
    // status command
case ("--disconnect", 2):
    let name = args[1]
    // disconnect command
case (let name?, 1) where !name.hasPrefix("-"):
    // connect command
default:
    fputs("Usage: aws-connect <name> | --disconnect <name> | status\n", stderr)
    exit(1)
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| BSD sockets / CFSocket for IPC | NWListener + NWConnection (Network.framework) | macOS 10.14 (2018) | NWListener is the modern API for the server; but CLI still best served by POSIX for synchronous use |
| Global actors for NW callbacks | `@unchecked Sendable` + GCD queue + `Task { @MainActor in }` | Swift 6 (2024) | Avoids actor reentrancy; consistent with existing codebase patterns |
| NWFramer for message framing | Simple `\n` delimiter with manual accumulation | — | NWFramer is overkill for a one-request-one-response protocol; manual framing is <10 lines |

**Deprecated/outdated:**
- CFSocket: Not deprecated but discouraged; Network.framework is preferred for the server side
- `allowLocalEndpointReuse` for Unix sockets: Functionally broken on macOS — do not rely on it

---

## Open Questions

1. **`IPCMessage.swift` in VPNCore vs. App target**
   - What we know: CLI imports VPNCore; duplicating Codable structs in both targets is fragile
   - What's unclear: Whether adding IPC-specific types to VPNCore is architecturally acceptable
   - Recommendation: Put in VPNCore — zero AppKit/SwiftUI dependencies, DRY. If the planner disagrees, redefine in aws-connect target only (structs are trivial).

2. **`connect()` error handling — app running but config busy**
   - What we know: D-06 says fire-and-forget; VPNManager.connect() can throw `.alreadyAuthenticating`
   - What's unclear: Should IPC propagate this as `{"ok":false,"error":"another VPN is authenticating"}` or swallow it?
   - Recommendation: Propagate — the CLI error output (D-05) should reflect the actual reason.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Network.framework | IPCServer (app) | ✓ | macOS 14 built-in | — |
| Darwin (POSIX) | CLI socket calls | ✓ | macOS 14 built-in | — |
| Swift 6.2 | Strict concurrency | ✓ | 6.2.4 | — |
| Xcode 26.3 | Build toolchain | ✓ | 26.3 (17C529) | — |

No missing dependencies. Phase 4 is code-only with no external tools.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode built-in) |
| Config file | VPNCoreTests/Info.plist (scheme-based) |
| Quick run command | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' -only-testing:VPNCoreTests 2>&1 \| grep -E "Test Suite|error:|PASS|FAIL"` |
| Full suite command | `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' 2>&1 \| tail -20` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IPC-01 | Socket file created, stale file removed on launch | Integration (requires running app) | Manual only — socket lifecycle tied to app launch | ❌ Wave 0 stub |
| IPC-01 | IPCServer init removes existing file | Unit (FileManager mock or temp dir) | `xcodebuild test ... -only-testing:VPNCoreTests/IPCServerTests` | ❌ Wave 0 |
| IPC-02 | `connect` command sends `{"cmd":"connect","name":"..."}` | Unit (mock socket) | `xcodebuild test ... -only-testing:VPNCoreTests/IPCMessageTests` | ❌ Wave 0 |
| IPC-03 | `disconnect` command sends correct JSON | Unit | Same as IPC-02 | ❌ Wave 0 |
| IPC-04 | `status` response parsed to aligned table | Unit | `xcodebuild test ... -only-testing:VPNCoreTests/IPCMessageTests` | ❌ Wave 0 |
| IPC-04 | `failed` state shows `failed: <msg>` in table | Unit | Same | ❌ Wave 0 |
| IPC-05 | CLI prints correct error when socket absent | Unit (test arg parsing + exit) | Manual smoke test or subprocess spawn | ❌ Wave 0 |
| IPC-05 | `ConnectionState.ipcLabel` correct for all cases | Unit | `xcodebuild test ... -only-testing:VPNCoreTests/ConnectionStateTests` | ✅ existing |

**Note on integration testing:** IPC-01 full lifecycle (socket created, CLI sends, app responds) requires the app to be running, which is not automatable in XCTest. Integration smoke tests should be documented in the verification plan as manual steps using:
```bash
echo '{"cmd":"status"}' | nc -U ~/Library/Application\ Support/AWSVPNClient/daemon.sock
```

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme AWSVPNClient -destination 'platform=macOS' -only-testing:VPNCoreTests 2>&1 | grep -E "passed|failed|error:"`
- **Per wave merge:** Full suite command above
- **Phase gate:** All unit tests green + manual IPC smoke test before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `VPNCoreTests/IPCMessageTests.swift` — unit tests for `IPCRequest`/`IPCResponse` encode/decode, `ConnectionState.ipcLabel`, status table formatting, arg parsing
- [ ] `VPNCoreTests/ConnectionStateTests.swift` — add `ipcLabel` test cases (file exists, needs additions)

*(No new test framework needed — XCTest is already configured.)*

---

## Sources

### Primary (HIGH confidence)
- `VPNCore/SAMLServer.swift` — NWListener pattern used directly as template; `@unchecked Sendable` + GCD queue established pattern
- `VPNCore/VPNManager.swift` — `Task { @MainActor [weak self] in }` dispatch pattern for NWConnection callbacks
- Apple Developer Forums — NWListener with NWEndpoint.unix thread/719635 — Unix socket NWParameters setup
- rdar://FB8658821 (referenced in search results) — `allowLocalEndpointReuse` broken on macOS, needs manual `unlink()`/removeItem
- GitHub apple/swift-nio issue #1619 — confirms stale socket cleanup must be done at app level

### Secondary (MEDIUM confidence)
- [timweiss.net — Working with line-based sockets in Swift with Network.framework (2024-01-24)](https://timweiss.net/blog/2024-01-24-working-with-line-based-sockets-in-swift-with-network-framework/) — line-based receive loop with buffer accumulation
- [Apple Developer Forums thread/756756 — Unix Domain Socket, Network Framework](https://developer.apple.com/forums/thread/756756) — confirms unsandboxed apps use `~/Library/Application Support` path correctly
- [Medium — Using Unix Sockets for iOS Extensions and Main App](https://medium.com/@JustRouzbeh/using-unix-sockets-for-communication-between-ios-extensions-and-main-app-27159bfc1144) — POSIX Darwin client pattern (`socket`, `connect`, `read`)

### Tertiary (LOW confidence)
- [rderik.com — Using BSD Sockets in Swift](https://rderik.com/blog/using-bsd-sockets-in-swift/) — POSIX socket calls in Swift reference (2020, patterns still valid)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Network.framework and Darwin are built-in, no version uncertainty
- Architecture: HIGH — directly follows SAMLServer established pattern; D-13 has clear rationale
- Pitfalls: HIGH — allowLocalEndpointReuse bug is documented (rdar://FB8658821); others derived from existing codebase patterns
- CLI POSIX approach: MEDIUM-HIGH — well-established pattern but limited Swift-6-specific verification found

**Research date:** 2026-03-26
**Valid until:** 2026-06-26 (stable APIs; Network.framework and POSIX do not change frequently)
