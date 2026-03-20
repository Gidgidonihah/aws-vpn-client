# Phase 2: Connection Lifecycle — Research

**Researched:** 2026-03-19
**Domain:** Foundation.Process subprocess management, Network.framework NWListener, Swift 6 strict concurrency, SAML auth flow port
**Confidence:** HIGH (core patterns verified via Swift Forums + Apple docs; pitfalls from PITFALLS.md confirmed by official sources)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Only one SAML auth flow at a time — port 35001 is shared; while any config is `.authenticating`, all other disconnected configs are blocked
- `.authenticating` configs ARE clickable — clicking cancels the in-progress auth, kills dummy openvpn Process, stops listener, deletes temp credentials, resets to `.disconnected` — no cooldown
- SAML timeout: **30 seconds** from browser open → `.failed("SAML auth timed out")`; compile-time constant `private let samlTimeoutSeconds: TimeInterval = 30`
- Connected detection: parse `"Initialization Sequence Completed"` from openvpn stdout
- Unexpected openvpn exit while `.connected` → `.failed("openvpn exited unexpectedly")`
- openvpn stdout + stderr piped to a single `FileHandle` writing to `~/Library/Logs/AWSVPNClient/<name>.log` — **file only**, no in-memory buffer
- `.failed` state: immediate click-to-retry, no explicit dismiss step
- Connection state is **ephemeral** — not persisted; all configs start `.disconnected`

### Claude's Discretion

- Exact log directory creation logic (lazy-created per connection or alongside configs dir setup)
- PID tracking strategy for the `sudo openvpn` process — `pgrep -P` vs. `--writepid` (see Pitfall 1 analysis below)
- Exact openvpn flags passed for the sudo connect call — match Rust reference
- Line-buffering strategy for stdout parsing (Pipe + FileHandle read loop)
- App termination cleanup sequencing (`applicationWillTerminate` / `applicationShouldTerminate` + `atexit` safety net)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONN-01 | User can initiate a VPN connection by clicking a config name in the menu | `connect(_ config:)` method in VPNManager — state transitions, guard for concurrent auth |
| CONN-02 | SAML authentication flow completes end-to-end: dummy openvpn → CRV1 parsed → browser opens → SAML POST received on :35001 → openvpn connected | NWListener server design, Rust auth flow port, credential format, connection sequence |
| CONN-03 | Each connection has a state machine: disconnected → authenticating → connected → disconnecting → failed | `ConnectionState` enum already defined; VPNManager.connections dict drives all transitions |
| CONN-04 | Connected openvpn process runs as background subprocess under `sudo openvpn` (NOPASSWD) until explicitly stopped | Foundation.Process + terminationHandler, PID tracking strategy |
| CONN-05 | App termination kills all openvpn subprocesses — no orphaned tunnels survive app quit | `applicationShouldTerminate` + `replyToApplicationShouldTerminate` + `atexit` |
| CONN-06 | Credential temp files (dummy creds, SAML creds) are deleted immediately after subprocess consumes them | `defer { try? FileManager.removeItem }` pattern, 0600 permissions |
| CONN-07 | User can disconnect a connected config by clicking it in the menu | `disconnect(_ config:)` — SIGTERM to real openvpn PID, state → .disconnecting → .disconnected |
| CONN-08 | Per-connection stdout+stderr streamed to `~/Library/Logs/AWSVPNClient/<name>.log` | Pipe + FileHandle.readabilityHandler + file write loop |
</phase_requirements>

---

## Summary

Phase 2 implements the complete VPN connection lifecycle in `VPNManager`. The Rust reference code (in `aws-vpn-core/` and `aws-vpn-cli/`) already proves the auth flow works; the task is a faithful Swift port, not invention. There are six distinct technical areas, each with well-understood patterns but significant pitfalls if the patterns are applied naively.

The most critical design decision is the NWListener strategy: **keep one long-running listener alive for the entire app session** rather than starting/stopping a listener per auth cycle. This directly avoids EADDRINUSE (PITFALLS.md Pitfall 2). All other NWListener guidance flows from this choice. The second most critical decision is PID tracking for `sudo openvpn`: **`--writepid` is the preferred strategy** because it gives the real openvpn PID reliably without a timing-sensitive `pgrep` race, and it works even after the sudo wrapper exits.

Swift 6 strict concurrency requires that all `VPNManager` state mutations reach the `@MainActor`. The `@MainActor` annotation on VPNManager already enforces this, but NWListener and Pipe/FileHandle callbacks fire on background queues — every mutation must be wrapped in `Task { @MainActor in ... }` or `await MainActor.run { ... }`.

**Primary recommendation:** Implement a `SAMLServer` struct that wraps one long-lived NWListener, uses a per-auth `CheckedContinuation` to suspend until a single POST arrives, then resumes the caller — never cancels the listener between auth cycles.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation.Process | macOS 14 built-in | Spawn openvpn/sudo subprocesses | Only option per project constraints; swift-subprocess is out of scope |
| Network.framework NWListener | macOS 14 built-in | TCP listener on :35001 for SAML callback | Modern replacement for BSD sockets; project constraint |
| Network.framework NWConnection | macOS 14 built-in | Accept + read the single SAML POST per auth cycle | Paired with NWListener |
| Foundation.Pipe + FileHandle | macOS 14 built-in | Stream openvpn stdout/stderr to log file | Lightweight; readabilityHandler avoids blocking |
| Swift Concurrency (Task, CheckedContinuation) | Swift 6.1 | Bridge NWListener/Pipe callbacks to async/await | Required for @MainActor-safe state updates |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation.URLComponents | built-in | Parse SAMLResponse from URL-encoded POST body | Extract `SAMLResponse` field from `application/x-www-form-urlencoded` |
| Foundation.CharacterSet | built-in | URL-encode the SAML response for the final credential | `addingPercentEncoding(withAllowedCharacters:)` |
| Foundation.FileManager | built-in | Create Logs dir, write temp creds at 0600, delete temp files | Established pattern from Phase 1 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Long-running NWListener | New listener per auth cycle | New-per-cycle triggers EADDRINUSE (Pitfall 2) — never do this |
| `--writepid` for PID tracking | `pgrep -P <sudo_pid>` | pgrep has a timing race window; writepid is atomic and race-free |
| FileHandle.readabilityHandler | Pipe.fileHandleForReading.bytes (AsyncBytes) | AsyncBytes not available for Pipe on macOS until later versions; readabilityHandler is stable |

**Installation:** No new dependencies — all APIs are platform built-ins.

---

## Architecture Patterns

### Recommended Project Structure

```
VPNCore/
├── VPNManager.swift          # @Observable @MainActor — connect/disconnect/state
├── ConnectionState.swift     # enum (already done — use as-is)
├── VPNConfig.swift           # struct — Phase 2 adds host/port/proto parsed fields
├── SAMLServer.swift          # NEW — long-lived NWListener wrapper
├── ProcessRunner.swift       # NEW (optional) — thin Foundation.Process helpers
└── VPNConfig+Parsing.swift   # NEW — conf file parsing (strip/filter + field extraction)
```

Keeping `SAMLServer` in its own file reduces VPNManager.swift complexity and isolates the NWListener restart pitfall. `VPNConfig+Parsing.swift` keeps parsing logic separate from the data struct.

---

### Pattern 1: Long-Lived SAMLServer with per-auth CheckedContinuation

**What:** One `NWListener` is started at `VPNManager.init()` and never cancelled during the app's lifetime. Each auth cycle calls `SAMLServer.waitForSAMLResponse()`, which installs a `CheckedContinuation` that resumes with the `SAMLResponse` string when the single POST arrives and the connection sends back a 200 response.

**Why:** NWListener cannot restart on the same port after `.cancel()` in the same process run (PITFALLS.md Pitfall 2). `allowLocalEndpointReuse = true` helps for process-to-process restart but does NOT reliably fix intra-process restart timing. Keeping one listener avoids the problem entirely.

**When to use:** Always. This is the only approach that survives repeated cancel→retry sequences.

**Example:**
```swift
// SAMLServer.swift
// Source: pattern synthesized from Network.framework docs + Pitfall 2 in PITFALLS.md

final class SAMLServer {
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true          // Belt-and-suspenders
        listener = try NWListener(using: params, on: 35001)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        // Set BOTH handlers before start (Pitfall 12)
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                // Surface port conflict clearly
                print("SAMLServer failed: \(err)")
            }
        }
        listener.start(queue: .global(qos: .utility))
    }

    /// Suspends until exactly one SAMLResponse arrives.
    /// Throws if the caller cancels or timeout fires.
    func waitForSAMLResponse() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancelCurrentWait() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receiveHTTPBody(connection: connection, accumulated: Data())
    }

    private func receiveHTTPBody(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            // Check if we have a full HTTP request (headers + body)
            // Minimal strategy: look for \r\n\r\n separator
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let bodyStart = headerEnd.upperBound
                let body = buffer[bodyStart...]
                // Parse Content-Length from headers (Pitfall 5)
                let headerText = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                let contentLength = Self.parseContentLength(from: headerText)
                if body.count >= contentLength {
                    self.handlePOSTBody(Data(body), connection: connection)
                    return
                }
            }
            // Not complete yet — accumulate more
            if !isComplete {
                self.receiveHTTPBody(connection: connection, accumulated: buffer)
            }
        }
    }

    private static func parseContentLength(from headers: String) -> Int {
        // "Content-Length: 4096\r\n"
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func handlePOSTBody(_ body: Data, connection: NWConnection) {
        // Parse application/x-www-form-urlencoded
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        let saml = Self.extractSAMLResponse(from: bodyString)

        // Send HTTP 200 response before resuming continuation
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 52\r\n\r\nGot SAMLResponse; it is now safe to close this window"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        if let saml, !saml.isEmpty {
            continuation?.resume(returning: saml)
        } else {
            continuation?.resume(throwing: VPNError.samlResponseMissing)
        }
        continuation = nil
    }

    private static func extractSAMLResponse(from body: String) -> String? {
        // body: "SAMLResponse=PHNhbWxwOlJlc3BvbnNl...&RelayState=..."
        for pair in body.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count >= 2, kv[0] == "SAMLResponse" else { continue }
            // Re-join in case value itself contains '='
            let encoded = kv.dropFirst().joined(separator: "=")
            return encoded.removingPercentEncoding
        }
        return nil
    }
}
```

---

### Pattern 2: Auth Flow Sequence (port of Rust main.rs)

**What:** The exact sequence from the Rust CLI, ported to Swift `async throws`.

```
1. Guard: is any config already .authenticating? → throw/return early
2. Set connections[config.name] = .authenticating
3. Write dummy creds file (N/A / ACS::35001) at 0600
4. Spawn dummy openvpn Process (non-sudo, .output() capture)
5. Parse CRV1 line from combined stdout+stderr
6. Extract URL ("https://..." split) and SID (colon field index 6)
7. Open browser with NSWorkspace.shared.open(url)
8. Start 30-second timeout Task
9. Await samlServer.waitForSAMLResponse()
   — either SAML arrives, OR timeout fires (cancelCurrentWait + throw)
10. Cancel timeout Task
11. Delete dummy creds file (defer already covers it)
12. URL-encode samlResponse with addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
13. Write real creds file (N/A / CRV1::{sid}::{encoded}) at 0600
14. Spawn sudo openvpn Process with terminationHandler
15. Read --writepid file to get real openvpn PID
16. Start stdout monitoring Task (readabilityHandler → scan for "Initialization Sequence Completed")
17. Wait for "Initialization Sequence Completed" → set .connected
18. Keep terminationHandler running: unexpected exit → .failed("openvpn exited unexpectedly")
```

**Critical invariants from Rust (must match exactly):**
- Dummy creds: line 1 = `"N/A"`, line 2 = `"ACS::35001"`
- Hostname: `random_hex(12) + "." + config.host` (Rust: 12 random bytes as lowercase hex = 24 hex chars)
- CRV1 SID: split on `":"`, take index 6 (zero-indexed, equivalent to awk `$7`)
- Real creds: line 1 = `"N/A"`, line 2 = `"CRV1::\(sid)::\(urlEncoded(samlResponse))"`
- URL encoding must match `url.QueryEscape` (Go) / `urlencoding::encode` (Rust) — use `.urlQueryAllowed` NOT `.urlHostAllowed` (space must become `+` or `%20`; AWS accepts `%20`)

**Note on URL encoding:** Swift's `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` does NOT encode `+`. The Rust `urlencoding::encode` encodes spaces as `%20`. Use a custom character set that also excludes `+` from allowed chars, or manually replace `"+"` with `"%2B"` after encoding.

---

### Pattern 3: openvpn Flags (match Rust exactly)

**Dummy call (non-sudo):**
```
openvpn
  --config <filtered_temp_conf>
  --verb 3
  --proto <protocol>
  --remote <resolved_ip> <port>
  --auth-user-pass <dummy_creds_path>
```
Run synchronously via `Process.run()` + `waitUntilExit()` — this call is expected to fail quickly with the CRV1 challenge; blocking is acceptable.

**Real connect call (sudo):**
```
sudo openvpn
  --config <filtered_temp_conf>
  --verb 3
  --auth-nocache
  --inactive 3600
  --proto <protocol>
  --remote <resolved_ip> <port>
  --script-security 2
  --auth-user-pass <real_creds_path>
  --writepid /tmp/aws-vpn-<configName>.pid
```
Run async via `Process` + `terminationHandler`.

---

### Pattern 4: openvpn Config Filtering (port of config.rs)

Strip these directives from the `.conf` before passing to openvpn — the patched AWS openvpn rejects them or conflicts with command-line args:

```swift
// VPNConfig+Parsing.swift
func shouldStripLine(_ line: String) -> Bool {
    let l = line.trimmingCharacters(in: .whitespaces)
    return l.hasPrefix("auth-user-pass")
        || l.hasPrefix("auth-federate")
        || (l.hasPrefix("auth-retry") && l.contains("interact"))
        || l.hasPrefix("remote")
}
```

Extract `host`, `port`, `proto`:
```swift
// field(content, directive: "remote", n: 1) → host (whitespace field at index 1)
// field(content, directive: "remote", n: 2) → port (whitespace field at index 2)
// field(content, directive: "proto",  n: 1) → protocol (whitespace field at index 1)
```

Write filtered content to a temp file at `NSTemporaryDirectory()` with mode 0600. Use `defer { try? FileManager.default.removeItem(at: filteredConfURL) }` at the call site.

---

### Pattern 5: PID Tracking for sudo openvpn

**Recommended approach: `--writepid`**

Pass `--writepid /tmp/aws-vpn-<configName>.pid` to the openvpn invocation. After the Process is launched (and a brief readiness pause — either poll the PID file or wait for the "Initialization Sequence Completed" log line), read the PID file:

```swift
let pidPath = "/tmp/aws-vpn-\(config.name).pid"
// After "Initialization Sequence Completed" is seen in stdout:
if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8),
   let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
    // store pid in connections metadata
}
```

**Why `--writepid` over `pgrep -P`:**
- `pgrep -P <sudo_pid>` has a timing race: if called before openvpn fully execs under sudo, it may return the sudo process or nothing
- `--writepid` is written by openvpn itself after it daemonizes, so the file only appears when the real PID is valid
- `pgrep` requires knowing the sudo wrapper's PID is still live; on macOS sudo may or may not exec-replace itself

**Disconnect via direct kill:**
```swift
// NOPASSWD sudoers must also cover: /bin/kill -TERM <pid>
// Or use: sudo kill -TERM <openvpnPID>
let killProcess = Process()
killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
killProcess.arguments = ["kill", "-TERM", String(openvpnPID)]
try killProcess.run()
```

**Fallback cleanup on launch:** At app startup, check for stale PID files in `/tmp/aws-vpn-*.pid` and send SIGTERM to any live openvpn processes to clean up prior sessions.

---

### Pattern 6: stdout Streaming + "Initialization Sequence Completed" Detection (CONN-08)

**Architecture:** One `Pipe` for both stdout and stderr. Set `Process.standardOutput` and `Process.standardError` to the same Pipe write end. Read from the Pipe's read end via `FileHandle.readabilityHandler`.

```swift
// Source: Foundation docs + Swift Forums thread 59834 pattern
let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

let logFileHandle = try FileHandle(forWritingTo: logFileURL)
var lineBuffer = Data()

pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else {
        handle.readabilityHandler = nil     // EOF — process exited
        try? logFileHandle.close()
        return
    }
    // Write raw bytes to log file
    try? logFileHandle.write(contentsOf: data)
    // Scan for trigger line (only until .connected is reached)
    lineBuffer.append(data)
    // Split on newlines
    while let nl = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
        let lineData = lineBuffer[lineBuffer.startIndex...nl]
        if let line = String(data: lineData, encoding: .utf8),
           line.contains("Initialization Sequence Completed") {
            Task { @MainActor [weak self] in
                self?.connections[config.name] = .connected
            }
            // Stop scanning — no longer need to parse lines
            lineBuffer = Data()
            break
        }
        lineBuffer = Data(lineBuffer[lineBuffer.index(after: nl)...])
    }
}
```

**Swift 6 concurrency note:** `readabilityHandler` fires on GCD's background queue. Mutations to `VPNManager.connections` (a `@MainActor` property) must go through `Task { @MainActor in ... }`. The `logFileHandle` write is non-actor-isolated I/O and safe on a background queue. The `lineBuffer` is local to the closure (captured `var`) — in Swift 6, wrap it in a `class` or use `actor` if the compiler complains about mutation in a `@Sendable` closure.

**Correct pattern for Swift 6 `readabilityHandler`** (avoids "mutation of captured var" error):
```swift
// Use a class (reference type) to hold mutable state captured in @Sendable closure
final class LineScanner: @unchecked Sendable {
    var buffer = Data()
    var triggered = false
}
let scanner = LineScanner()
pipe.fileHandleForReading.readabilityHandler = { handle in
    // scanner is a reference type — mutating it is safe in @Sendable
    ...
}
```

---

### Pattern 7: App Termination Cleanup (CONN-05)

**Reliable approach:** `applicationShouldTerminate` + `NSApplication.shared.reply(toApplicationShouldTerminate:)`.

`applicationWillTerminate` is NOT reliable for async cleanup — scheduled Tasks do not execute when the app is already terminating. `applicationShouldTerminate` lets you defer the termination decision.

```swift
// AppDelegate (add to AWSVPNClientApp or create AppDelegate)
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let activeConnections = vpnManager.connections.filter {
        if case .connected = $0.value { return true }
        if case .disconnecting = $0.value { return true }
        return false
    }
    guard !activeConnections.isEmpty else { return .terminateNow }

    // Disconnect all active connections on a background task
    Task {
        for config in vpnManager.configs {
            try? await vpnManager.disconnect(config)
        }
        // Allow up to 5 seconds then force-quit
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    // Set a 5-second hard timeout
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    return .terminateLater
}
```

**`atexit` safety net:** Register at app start as last-resort for crash/Force Quit paths:
```swift
// At app startup — captures the vpnManager reference via a global
atexit {
    // Send SIGTERM to all known openvpn PIDs synchronously
    // Must be synchronous — atexit handlers cannot use async
    for pid in knownOpenvpnPIDs {
        kill(pid, SIGTERM)
    }
}
```

Note: `atexit` cannot call async code. Maintain a global `Set<Int32>` of live openvpn PIDs updated from `@MainActor` — reading from `atexit` is a data race but acceptable as a safety net (worst case: some PIDs not killed, but this is the crash path anyway).

---

### Pattern 8: Credential Temp File Lifecycle (CONN-06, Pitfall 6)

```swift
// Write with 0600 permissions
let credPath = NSTemporaryDirectory() + "aws-vpn-creds-\(config.name)-\(UUID().uuidString).txt"
let credContent = "N/A\nACS::35001\n"
FileManager.default.createFile(
    atPath: credPath,
    contents: credContent.data(using: .utf8),
    attributes: [.posixPermissions: 0o600]
)
defer {
    try? FileManager.default.removeItem(atPath: credPath)
}
// ... spawn Process using credPath ...
// defer fires when the enclosing function/scope exits, covering throw paths
```

Use a unique UUID suffix so concurrent cleanup tasks cannot collide.

---

### Anti-Patterns to Avoid

- **Cancelling and recreating NWListener per auth cycle:** Causes EADDRINUSE on retry (Pitfall 2). Use one long-lived instance.
- **Calling `Process.waitUntilExit()` on the main thread:** Blocks SwiftUI (Pitfall 13). Use `terminationHandler` exclusively for the real connect process.
- **Mutating `@Observable` `VPNManager` directly in NWListener/Pipe callbacks:** Silent SwiftUI corruption in Swift 6 (Pitfall 4). Always dispatch via `Task { @MainActor in ... }`.
- **Sending SIGTERM only to the `sudo` wrapper PID:** The real openvpn process survives (Pitfall 1). Always target the openvpn PID from the PID file.
- **Deleting temp credentials only on success:** File survives crashes (Pitfall 6). Use `defer` at the launch site so it runs on every exit path.
- **Parsing only one `receive()` chunk for the SAML POST body:** Truncates large IdP payloads (Pitfall 5). Accumulate until `Content-Length` bytes received.
- **Reusing the same `NWListener` instance after cancellation:** Framework does not support this — always allocate a new instance (moot with the long-lived approach).
- **Using `Swift.Data` in-memory log buffer:** CONTEXT.md specifies file-only logging. Keep no in-memory buffer beyond the line-scan accumulator.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| URL percent-encoding for SAML token | Custom encoder | `String.addingPercentEncoding(withAllowedCharacters:)` | Handles all edge cases; just pick correct character set |
| HTTP body framing | Full HTTP parser | Minimal header scan (look for `\r\n\r\n`, read `Content-Length`) | SAML server receives exactly one known request type; no generality needed |
| Process lifecycle tracking | Custom PID table | `--writepid` + file read | openvpn writes its own PID atomically; no polling needed |
| Log file rotation | Custom rotation | Single append-only `FileHandle` | Per-connection file, overwritten each session; rotation out of scope |
| Async process output reading | Custom dispatch queue | `FileHandle.readabilityHandler` | GCD already handles the background queue; no extra threading needed |

**Key insight:** The SAML HTTP server only ever handles one known request shape (a POST with `SAMLResponse` in a URL-encoded body). A minimal hand-rolled parser that scans for `\r\n\r\n` and reads `Content-Length` is the right scope — adding a full HTTP library dependency would be over-engineering for a personal tool.

---

## Common Pitfalls

### Pitfall A: NWListener EADDRINUSE on Auth Retry (Pitfall 2)

**What goes wrong:** Creating a new `NWListener` on port 35001 after calling `.cancel()` on the previous one fails immediately with EADDRINUSE.

**Why it happens:** NWListener does not release the OS socket binding synchronously. The socket enters TIME_WAIT and may never be freed within the same process run. `allowLocalEndpointReuse = true` helps but is not a complete fix for intra-process restart.

**How to avoid:** Keep one `SAMLServer` instance alive for the entire app lifetime. Each auth cycle calls `waitForSAMLResponse()`, which installs a new continuation — the listener itself never stops.

**Warning signs:** `NWListener` state goes to `.failed(POSIXError.EADDRINUSE)` immediately on second auth attempt.

---

### Pitfall B: Orphaned openvpn Root Process (Pitfall 1)

**What goes wrong:** `Process.terminate()` sends SIGTERM to the `sudo` wrapper, not to the `openvpn` child. openvpn is reparented to launchd and keeps running as a root orphan.

**How to avoid:** Use `--writepid` to get the real openvpn PID; send `sudo kill -TERM <pid>` to that PID directly.

**Warning signs:** `ps aux | grep openvpn` shows processes from prior sessions after app relaunch.

---

### Pitfall C: SAML Body Truncation on Large IdP Payloads (Pitfall 5)

**What goes wrong:** Parsing `SAMLResponse` from the first `receive()` chunk works in dev with small test payloads but fails against real Okta/Azure AD assertions (2–8 KB base64).

**How to avoid:** Parse `Content-Length` from headers; accumulate `Data` until buffer size ≥ `Content-Length` before processing the body.

**Warning signs:** Auth works locally against a test IdP but fails with real AWS credentials; `SAMLResponse` string is truncated (non-multiple-of-4 length base64).

---

### Pitfall D: Swift 6 @Sendable Mutation in readabilityHandler

**What goes wrong:** `pipe.fileHandleForReading.readabilityHandler = { ... }` is a `@Sendable` closure. Mutating a captured `var` (e.g., `lineBuffer`) inside it is a Swift 6 error.

**How to avoid:** Wrap mutable state in a reference type (`final class ... : @unchecked Sendable`) and capture the instance. Alternatively, use an `actor` with `await`. For `VPNManager` state mutations, always use `Task { @MainActor in ... }` inside the handler.

---

### Pitfall E: Tasks Not Executing in applicationWillTerminate

**What goes wrong:** Cleanup Tasks scheduled in `applicationWillTerminate` do not run because the app is already committed to termination.

**How to avoid:** Use `applicationShouldTerminate` returning `.terminateLater`, perform cleanup, then call `NSApplication.shared.reply(toApplicationShouldTerminate: true)` when done or after a 5-second hard timeout.

---

### Pitfall F: URL-Encoding Mismatch for SAML Token

**What goes wrong:** Swift's `.urlQueryAllowed` character set does NOT percent-encode `+`. The Rust reference (`urlencoding::encode`) encodes space as `%20`. If the SAML assertion contains a `+` character and Swift passes it through unencoded, openvpn receives a malformed credential.

**How to avoid:**
```swift
var customSet = CharacterSet.urlQueryAllowed
customSet.remove("+")
let encoded = samlResponse.addingPercentEncoding(withAllowedCharacters: customSet) ?? samlResponse
```

---

### Pitfall G: random_hex(12) Byte Count vs Hex Length

**What goes wrong:** The Rust `random_hex(12)` generates 12 **random bytes** formatted as 24 lowercase hex characters. If implemented as "12 random hex chars" instead of "12 random bytes → 24 hex chars", the prefix is half the intended length.

**How to avoid:**
```swift
func randomHex(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}
// randomHex(byteCount: 12) → 24-character hex string
```

---

## Code Examples

### VPNConfig + Parsing Fields

```swift
// VPNConfig+Parsing.swift
extension VPNConfig {
    struct ParsedConf {
        let host: String
        let port: String
        let proto: String
        let filteredContent: String
    }

    func parseConf() throws -> ParsedConf {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        func field(_ directive: String, index: Int) -> String? {
            lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(directive + " ") }
                .flatMap { $0.split(separator: " ").dropFirst().map(String.init)[safe: index] }
        }

        guard let host = field("remote", index: 0),
              let port = field("remote", index: 1),
              let proto = field("proto", index: 0)
        else { throw VPNError.configParseFailure }

        let filtered = lines
            .filter { !shouldStripLine($0) }
            .joined(separator: "\n")

        return ParsedConf(host: host, port: port, proto: proto, filteredContent: filtered)
    }

    private func shouldStripLine(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespaces)
        return l.hasPrefix("auth-user-pass")
            || l.hasPrefix("auth-federate")
            || (l.hasPrefix("auth-retry") && l.contains("interact"))
            || l.hasPrefix("remote")
    }
}
```

### Process Spawn (non-blocking, with terminationHandler)

```swift
// Source: Foundation.Process docs + Pitfall 13 (never use waitUntilExit on main thread)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
process.arguments = ["openvpn", "--config", filteredConfPath, /* ... */]
process.standardOutput = outputPipe
process.standardError = outputPipe

process.terminationHandler = { proc in
    Task { @MainActor [weak self] in
        guard let self else { return }
        if self.connections[config.name] == .connected {
            self.connections[config.name] = .failed("openvpn exited unexpectedly")
        }
    }
}

try process.run()    // non-blocking
```

### NWListener Parameters Setup (with allowLocalEndpointReuse)

```swift
// Source: Network.framework docs + PITFALLS.md Pitfall 2
let params = NWParameters.tcp
params.allowLocalEndpointReuse = true
let listener = try NWListener(using: params, on: 35001)
// Set BOTH handlers before calling start (Pitfall 12)
listener.newConnectionHandler = { ... }
listener.stateUpdateHandler = { ... }
listener.start(queue: .global(qos: .utility))
```

### Dispatching NWListener Callback State to MainActor

```swift
// Source: PITFALLS.md Pitfall 4 + Swift 6 concurrency pattern
connection.stateUpdateHandler = { [weak self] state in
    Task { @MainActor in
        self?.connections[config.name] = .map(from: state)
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ObservableObject` + `@Published` | `@Observable` macro | macOS 14 / Swift 5.9 | Must be on `@MainActor`; background mutations no longer produce runtime warnings (silent corruption risk) |
| `NSTask` | `Foundation.Process` | macOS 10.13 rename | Same API, different name |
| BSD sockets / CFSocket | `NWListener` / `NWConnection` | macOS 10.14 | Modern API; no raw socket management |
| `swift-subprocess` | Foundation.Process (only option) | Project constraint | swift-subprocess is out of scope per PROJECT.md |

**Deprecated/outdated in this context:**
- `Process.waitUntilExit()` on main thread — always use `terminationHandler`
- Re-creating NWListener per auth cycle — use long-lived instance
- `@StateObject` / `@Published` — project uses `@Observable`

---

## Open Questions

1. **`--writepid` with patched AWS openvpn build**
   - What we know: Standard openvpn 2.5+ supports `--writepid`; the AWS patched build (v2.5.1 per the patch file) is based on 2.5.1
   - What's unclear: Does the AWS patch remove or conflict with `--writepid`? The patch file (`openvpn-v2.5.1-aws.patch`) should be audited for any `writepid` removal
   - Recommendation: In Phase 2 Wave 0, test `openvpn --writepid /tmp/test.pid --help` against the installed binary to confirm the flag is accepted before committing to this strategy; if rejected, fall back to `pgrep -P`

2. **`applicationShouldTerminate` availability in SwiftUI App lifecycle**
   - What we know: SwiftUI `@main` does not expose `applicationShouldTerminate` directly; requires `AppDelegate` adapter via `NSApplicationDelegateAdaptor`
   - What's unclear: Whether `@main AWSVPNClientApp` currently has an AppDelegate adaptor
   - Recommendation: Add `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate` to `AWSVPNClientApp`; implement `AppDelegate: NSObject, NSApplicationDelegate`

3. **openvpn stdout line endings**
   - What we know: openvpn uses `\n` on Unix
   - What's unclear: Whether the AWS patched build adds `\r\n` in any output mode
   - Recommendation: Split on `\n` and strip `\r` — handles both

---

## Validation Architecture

`workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected — no XCTest targets in project |
| Config file | None — Wave 0 must create |
| Quick run command | `xcodebuild test -scheme AWSVPNClientTests -destination 'platform=macOS' 2>&1 | tail -20` |
| Full suite command | Same (single test target for now) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONN-01 | `connect()` sets state to `.authenticating` when no other auth in progress | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testConnectSetsAuthenticatingState` | ❌ Wave 0 |
| CONN-01 | `connect()` returns early when another config is `.authenticating` | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testConnectBlockedWhileAuthenticating` | ❌ Wave 0 |
| CONN-02 | CRV1 line parsing: URL extraction + SID field-7 split | unit | `xcodebuild test -only-testing:VPNCoreTests/CRV1ParserTests` | ❌ Wave 0 |
| CONN-02 | `SAMLResponse` extraction from URL-encoded POST body | unit | `xcodebuild test -only-testing:VPNCoreTests/SAMLServerTests/testExtractSAMLResponse` | ❌ Wave 0 |
| CONN-02 | `randomHex(byteCount:)` produces 24-char string for input 12 | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testRandomHexLength` | ❌ Wave 0 |
| CONN-02 | URL-encoding: `+` in SAML response encoded as `%2B` | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testURLEncodingPlusChar` | ❌ Wave 0 |
| CONN-03 | State transitions: disconnected → authenticating → connected → disconnecting → disconnected | unit | `xcodebuild test -only-testing:VPNCoreTests/ConnectionStateTests` | ❌ Wave 0 |
| CONN-04 | openvpn Process not nil after `connect()` completes | integration (manual) | `ps aux \| grep openvpn` | manual-only |
| CONN-05 | All openvpn PIDs killed on app termination | integration (manual) | `ps aux \| grep openvpn` (check after quit) | manual-only |
| CONN-06 | Dummy creds file deleted after dummy openvpn exits | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testDummyCredsFileDeletedOnExit` | ❌ Wave 0 |
| CONN-06 | Real creds file deleted after sudo openvpn starts | unit | same test suite, separate case | ❌ Wave 0 |
| CONN-07 | `disconnect()` sends SIGTERM to openvpn PID | unit (mock Process) | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testDisconnectSendsSignal` | ❌ Wave 0 |
| CONN-08 | Log file created at correct path on connect | unit | `xcodebuild test -only-testing:VPNCoreTests/VPNManagerTests/testLogFileCreated` | ❌ Wave 0 |
| CONN-08 | openvpn stdout written to log file (not memory) | integration (manual) | `cat ~/Library/Logs/AWSVPNClient/<name>.log` | manual-only |

### Sampling Rate

- **Per task commit:** `xcodebuild test -only-testing:VPNCoreTests -destination 'platform=macOS' 2>&1 | grep -E 'PASS|FAIL|error:'`
- **Per wave merge:** Full `xcodebuild test` suite
- **Phase gate:** Full suite green before `/gsd:verify-work`; manual integration checks for CONN-04, CONN-05, CONN-08

### Wave 0 Gaps

- [ ] `VPNCore/Tests/VPNCoreTests/VPNManagerTests.swift` — covers CONN-01, CONN-02 (randomHex, URL encoding), CONN-06, CONN-07, CONN-08
- [ ] `VPNCore/Tests/VPNCoreTests/CRV1ParserTests.swift` — covers CONN-02 (CRV1 parsing)
- [ ] `VPNCore/Tests/VPNCoreTests/SAMLServerTests.swift` — covers CONN-02 (SAMLResponse extraction, body accumulation)
- [ ] `VPNCore/Tests/VPNCoreTests/ConnectionStateTests.swift` — covers CONN-03
- [ ] `VPNCore/Tests/VPNCoreTests/VPNConfigParsingTests.swift` — covers config filtering
- [ ] XCTest target `VPNCoreTests` in `project.yml` — add under `targets:` with `type: bundle.unit-test`, `platform: macOS`, `dependencies: [VPNCore]`
- [ ] Framework install: already present (XCTest is built-in; `xcodebuild test` only needs target added to `project.yml`)

---

## Sources

### Primary (HIGH confidence)
- PITFALLS.md (`/Users/jason/Sites/termly/sandbox/aws-vpn-client/.planning/research/PITFALLS.md`) — Pitfalls 1, 2, 4, 5, 6, 13 directly address Phase 2; verified against referenced Apple developer forums threads
- `aws-vpn-core/src/vpn.rs` + `aws-vpn-cli/src/main.rs` — canonical Rust reference for auth flow; porting exactly
- `aws-vpn-core/src/config.rs` — canonical conf filtering reference
- Apple Developer Documentation — `applicationShouldTerminate(_:)`: https://developer.apple.com/documentation/appkit/nsapplicationdelegate/1428642-applicationshouldterminate
- Apple Developer Documentation — `reply(toApplicationShouldTerminate:)`: https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:)
- Apple Developer Documentation — `FileHandle.readabilityHandler`: https://developer.apple.com/documentation/foundation/filehandle/1412413-readabilityhandler

### Secondary (MEDIUM confidence)
- Swift Forums — "Swift 6 Concurrency + NSPipe Readability Handlers": https://forums.swift.org/t/swift-6-concurrency-nspipe-readability-handlers/59834 — confirmed actor-wrapper pattern for Swift 6 readabilityHandler mutations
- Swift Forums — "How to deal with application termination/teardown/deinit with Swift Concurrency": https://forums.swift.org/t/how-to-deal-with-application-termination-teardown-deinit-with-swift-concurrency/53490 — confirmed `applicationShouldTerminate` over `applicationWillTerminate` for async cleanup
- Apple Developer Forums — "Stop and restart of NWListener fails": https://developer.apple.com/forums/thread/129452 — confirms EADDRINUSE bug; long-lived listener is documented workaround
- openvpn.net — "Controlling a Running OpenVPN Process": https://openvpn.net/community-docs/controlling-a-running-openvpn-process.html — confirms SIGTERM accepted by openvpn directly; `--writepid` behavior

### Tertiary (LOW confidence — flag for validation)
- openvpn `--writepid` support in the AWS patched 2.5.1 build: **unverified against the actual binary** — must be tested in Wave 0 before committing to this strategy

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are macOS built-ins; project constraints exclude alternatives
- Auth flow (Rust port): HIGH — exact code reference available; no ambiguity
- NWListener design: HIGH — Pitfall 2 is well-documented; long-lived listener is the correct mitigation
- PID tracking via `--writepid`: MEDIUM — standard openvpn flag; AWS patched build compatibility unverified
- App termination via `applicationShouldTerminate`: HIGH — Apple docs confirm the API and semantics
- Swift 6 readabilityHandler pattern: MEDIUM — Swift Forums thread confirms the approach; no official Apple doc

**Research date:** 2026-03-19
**Valid until:** 2026-06-19 (stable APIs; NWListener bugs are longstanding — unlikely to change)
