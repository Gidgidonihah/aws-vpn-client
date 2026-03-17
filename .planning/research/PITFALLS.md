# Domain Pitfalls

**Domain:** Swift macOS menu bar app with background subprocesses (sudo openvpn + Unix socket IPC + NWListener HTTP)
**Researched:** 2026-03-17

---

## Critical Pitfalls

Mistakes that cause rewrites, silent data loss, or security incidents.

---

### Pitfall 1: sudo openvpn Survives App Termination

**What goes wrong:** When the Swift app quits (crash, Force Quit, normal exit), `Process.terminate()` sends SIGTERM to the `sudo` wrapper — but the actual `openvpn` child process, running as root under a separate PID, keeps running. The tunnel stays up, credentials temp file may still be on disk, and the next app launch finds a conflict.

**Why it happens:** `sudo` spawns openvpn as a child of the `sudo` process. On macOS, `Process.terminate()` sends SIGTERM to the direct child only. SIGTERM is not automatically forwarded down to openvpn unless openvpn installs a signal handler for it (it does handle SIGTERM, but only if delivered directly). When `sudo` exits first, openvpn is reparented to launchd and keeps running as an orphan root process.

**Consequences:**
- Zombie or orphan openvpn processes accumulate between restarts
- Port/tunnel conflicts on reconnect
- Credentials temp file left on disk if cleanup was tied to process exit handler
- User cannot disconnect because the app-side PID tracking is lost

**Warning signs:**
- `ps aux | grep openvpn` shows processes from prior sessions after app relaunch
- Connection attempt to already-connected config "succeeds" but produces a second tunnel
- Log file shows duplicate openvpn initialization sequence

**Prevention:**
- Track the PID of the openvpn child (not the sudo wrapper). Read from `Process.processIdentifier` of the outer process, then use `pgrep -P <sudo_pid>` via a second Process call immediately after launch to get the real openvpn PID.
- On disconnect, send `kill -SIGTERM <openvpn_pid>` directly (requires another `sudo kill` invocation, or NOPASSWD for `kill` as well).
- Alternatively, pass `--writepid /tmp/aws-vpn-<name>.pid` to openvpn and read the PID file after startup.
- In `applicationWillTerminate`, iterate all tracked connections and call the disconnect path; block termination with `NSApplication.shared.reply(toApplicationShouldTerminate:)` until confirmed.
- Register an `atexit` handler as a last-resort safety net.

**Phase to address:** Phase implementing VPN connection lifecycle (subprocess spawn/teardown).

---

### Pitfall 2: NWListener Cannot Be Restarted After Cancellation

**What goes wrong:** Calling `listener.cancel()` and then creating a new `NWListener` on the same TCP port (35001) or Unix socket path immediately fails with "Address already in use." This is a known, longstanding bug in Network.framework (filed as SR-13918 / swift#56316).

**Why it happens:** `NWListener` does not release the OS socket binding synchronously when `.cancel()` is called. The underlying socket enters TIME_WAIT and the address/path is not freed until the system releases it — which can take seconds or never happen within the same process run. This affects both TCP port listeners and Unix domain socket listeners.

**Consequences:**
- SAML callback server on port 35001 cannot restart if a previous auth attempt was cancelled mid-flow
- Unix IPC socket cannot restart if the app crashed and left a stale socket file
- App must be killed and relaunched to recover

**Warning signs:**
- NWListener state goes to `.failed(POSIXError.EADDRINUSE)` immediately on second start
- Stale `.sock` file remains at `~/Library/Application Support/AWSVPNClient/daemon.sock` after a crash
- Auth retry after partial SAML flow hangs or errors immediately

**Prevention — TCP port 35001:**
- Set `allowLocalEndpointReuse = true` on the `NWParameters` before creating the listener.
- Do not reuse the same `NWListener` instance — create a fresh one each time, after the old one has fully reached `.cancelled` state (use the `stateUpdateHandler` to gate creation).
- Keep a single long-running listener for the SAML port (started at app launch, never cancelled mid-auth); discard and accept only the one connection needed per auth cycle.

**Prevention — Unix domain socket:**
- On app startup, delete the stale socket file before binding: `try? FileManager.default.removeItem(atPath: socketPath)`.
- Do the same in `applicationWillTerminate` so next launch is clean.
- Never reuse the `NWListener` instance itself; always allocate a new one.

**Phase to address:** Phase implementing SAML HTTP listener and Unix IPC socket.

---

### Pitfall 3: Unix Socket Path Length Exceeds 104-Byte Limit

**What goes wrong:** The `sockaddr_un.sun_path` field on macOS is limited to 104 bytes (including the null terminator), inherited from BSD. `NWEndpoint.unix(path:)` enforces this limit. If the full path to `daemon.sock` exceeds 103 printable characters, `NWListener` fails with an opaque error or silently refuses to bind.

**Why it happens:** macOS enforces the `sockaddr_un` structural limit. The path `~/Library/Application Support/AWSVPNClient/daemon.sock` expands to something like `/Users/<username>/Library/Application Support/AWSVPNClient/daemon.sock`. With a username of 20+ characters, this easily hits the limit (the base path without username is already 60 characters).

**Actual path length math:**
```
/Users/<username>/Library/Application Support/AWSVPNClient/daemon.sock
       ^^^^^^^^^^
       20 chars → total ~70 chars — safe
       30 chars → total ~80 chars — safe
       38 chars → total ~88 chars — marginal
       53+ chars → total 103+ chars — FAILS
```

**Consequences:**
- App fails to start IPC listener for usernames over ~35 characters with no helpful error message
- CLI companion cannot connect

**Warning signs:**
- NWListener state immediately `.failed` with no useful description
- Only reproducible on machines with long usernames

**Prevention:**
- Use `FileManager.default.temporaryDirectory` as a fallback if `Application Support` path is too long.
- Or use a path under `/tmp/aws-vpn-<hash>.sock` which is always short.
- Add a startup assertion: `assert(socketPath.utf8.count <= 103, "Unix socket path too long: \(socketPath)")`.
- Document in README that paths over 103 bytes are unsupported.

**Phase to address:** Phase implementing Unix IPC socket setup.

---

### Pitfall 4: @Observable VPNManager Updated from NWListener Queue — Silent SwiftUI Corruption

**What goes wrong:** NWListener and NWConnection deliver callbacks on their own internal dispatch queue (not the main thread). If `VPNManager` (annotated `@Observable`) has its properties mutated directly inside `stateUpdateHandler` or `receiveMessage` closures, SwiftUI either renders stale data, triggers undefined layout behavior, or (in stricter builds) emits a purple runtime warning about off-main-thread mutation.

**Why it happens:** Unlike `ObservableObject` + `@Published` (which had a clear "must be main thread" rule with a runtime warning), `@Observable` silently allows mutation from any thread. SwiftUI observes changes via the `withMutation` tracking mechanism, but the actual view update scheduling still must originate from the main actor. Background mutations can corrupt the dependency graph mid-render without crashing.

**Consequences:**
- Menu shows stale connection state (e.g., still "Connected" after disconnect event arrived)
- Race conditions where two NW callbacks both mutate state simultaneously
- Intermittent state desync that is hard to reproduce

**Warning signs:**
- Connection state in the menu lags real state by one event
- Purple runtime warning: "Publishing changes from background threads is not allowed"
- State inconsistency only seen under fast connect/disconnect cycling

**Prevention:**
- Annotate `VPNManager` with `@MainActor` — this is the single most important protection.
- All NW callbacks that mutate `VPNManager` must dispatch via `await MainActor.run { }` or `DispatchQueue.main.async { }`.
- Pattern:
  ```swift
  connection.stateUpdateHandler = { [weak self] state in
      Task { @MainActor in
          self?.connectionState = .map(from: state)
      }
  }
  ```
- Never call `DispatchQueue.main.sync` from an NW callback — deadlock risk if the callback is already on main.

**Phase to address:** Phase implementing VPN state observation and menu UI.

---

### Pitfall 5: NWListener as Raw HTTP Server — Body Not Fully Buffered Before Processing

**What goes wrong:** The SAML callback arrives as an HTTP POST with a URL-encoded body. NWListener delivers data in chunks via `receive(minimumIncompleteLength:maximumLength:completion:)`. If the HTTP parser processes each chunk as it arrives rather than waiting for the full body (determined by `Content-Length`), SAML response parsing fails on large IdP payloads because the body is split across multiple `receive` callbacks.

**Why it happens:** TCP is a stream protocol. A single logical HTTP message may arrive in multiple `Data` chunks. NWListener/NWConnection provide raw bytes — there is no built-in HTTP framing. SAML assertions from AWS/Okta/Azure AD can be 2–8 KB of base64, meaning the body routinely spans 2+ receive callbacks.

**Consequences:**
- SAML auth silently fails on real IdP payloads that work fine with short test strings
- Intermittent failures that look like network issues but are actually parse failures
- Base64-encoded SAML payload gets truncated, producing "invalid credential" errors from OpenVPN

**Warning signs:**
- Auth works in dev (short test SAML) but fails in production against real IdP
- `samlResponse` string contains a truncated base64 sequence (detectable: length not divisible by 4, or missing `=` padding)
- Issue only appears with Azure AD or Okta, not simple test IdPs

**Prevention:**
- Buffer all received data until `Content-Length` bytes have been received. Parse only after the full body is present.
- Keep a running `Data` accumulator; parse `Content-Length` from the first chunk; continue receiving until accumulator length >= declared content length.
- Alternatively: use swift-nio or Vapor's leaf HTTP parser as a library rather than writing raw HTTP parsing — but for a personal-use app the buffering approach is simpler and avoids a dependency.
- Set a maximum body size (e.g., 64 KB) to guard against malformed requests hanging the listener indefinitely.

**Phase to address:** Phase implementing SAML HTTP listener and credential extraction.

---

### Pitfall 6: Temp Credential File Left on Disk After Crash or Auth Failure

**What goes wrong:** The OpenVPN credential file (containing `N/A` / `CRV1::<sid>::<saml>`) is written to a temp path before openvpn launch and is supposed to be deleted after the tunnel comes up. If the app crashes, the process is killed, or openvpn fails to start, the file is never deleted and the SAML token remains readable by any process running as the same user.

**Why it happens:** `NSTemporaryDirectory()` is not automatically cleaned at logout or reboot — it persists until macOS cleans it (every ~3 days). The delete-on-success pattern leaves the file on disk during the entire openvpn startup window and permanently on any failure path.

**Consequences:**
- SAML token (which encodes session credentials for the AWS VPN session) readable from disk by other user-space processes
- On a shared or compromised machine this is a credential leak

**Warning signs:**
- Files named `aws-vpn-creds-*.txt` visible in `$TMPDIR` after a failed connection attempt
- Log shows openvpn exited before credentials cleanup line logged

**Prevention:**
- Write the credential file with mode `0600`: `FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])`.
- Use `defer { try? FileManager.default.removeItem(atPath: credPath) }` at the point of openvpn launch so cleanup runs even on thrown errors.
- Consider writing to a `FileHandle` opened with `O_TMPFILE` or using a `mkstemp`-equivalent via POSIX directly so the file is unlinked immediately after openvpn opens it (unlinked files remain accessible via the open file descriptor but disappear from the filesystem immediately). This is the most secure approach.
- For extra hardening, overwrite with zeros before deletion (though this is optional given the SAML token is time-limited).

**Phase to address:** Phase implementing VPN connection launch (credential passing).

---

## Moderate Pitfalls

---

### Pitfall 7: MenuBarExtra `.menu` Style Blocks the Run Loop

**What goes wrong:** `MenuBarExtra` with `.menuBarExtraStyle(.menu)` (the default pull-down menu) blocks the macOS run loop while open. Any SwiftUI binding that tries to dismiss the menu programmatically (e.g., setting `isPresented` to `false` from a button handler) has no effect. The app cannot update its displayed state while the menu is showing.

**Prevention:**
- Use `.menuBarExtraStyle(.window)` if you need to programmatically control presentation or show rich custom content (connection progress, log tails).
- For the simple connect/disconnect menu, `.menu` style is fine — just never try to drive state from outside the menu while it's open. All state changes should be queued and rendered on next open.
- Be aware that `.onAppear` is NOT called for `.menu` style views, so "refresh on open" patterns must use a different mechanism (e.g., monitor via `@Observable` that gets updated from a background poller).

**Phase to address:** Phase implementing menu bar UI.

---

### Pitfall 8: MenuBarExtra `.menu` Style Does Not Re-render on Open

**What goes wrong:** When the user opens the menu, SwiftUI does NOT re-evaluate the menu body. If connection state changed between the last render and the menu open event, the menu shows stale data until the next state-change-triggered redraw.

**Why it happens:** Filed as Apple Feedback FB13683957. `.menu` style does not have a "menu will open" lifecycle event analogous to `NSMenuDelegate.menuWillOpen`.

**Consequences:**
- User sees "Disconnected" in the menu even though the VPN connected a moment ago
- The icon in the menu bar updates (driven by `@Observable`) but the menu items don't until the menu is re-opened

**Prevention:**
- Drive all connection state from `@Observable` + `@MainActor` so SwiftUI's dependency tracking automatically invalidates the menu view when state changes — this usually makes the menu correct when it opens since the render happens at open time using current bindings.
- If using `.window` style this is a non-issue since the window always renders fresh.
- Consider periodic polling (1–2 second timer) on `VPNManager` to force state freshness rather than relying purely on subprocess output parsing.

**Phase to address:** Phase implementing menu bar UI.

---

### Pitfall 9: Hardcoded Port 35001 Conflict on Developer Machines

**What goes wrong:** The SAML callback server binds `127.0.0.1:35001`. On a developer machine running multiple VPN tools or AWS tooling, port 35001 may already be in use. The NWListener either fails to bind (and the auth hangs silently) or a second instance of the app tries to bind and fails.

**Prevention:**
- On bind failure, surface a clear error to the user: "Port 35001 is already in use. Check for another running instance."
- Use `lsof -i :35001` logic (via a `Process` call) to identify the conflicting process and include it in the error message.
- Do NOT attempt to fall back to a random port — the port is hardcoded into the AWS Client VPN dummy credential `ACS::35001` and is not configurable without changing the SAML flow.
- Prevent multiple instances via a lock file on the Unix IPC socket path (if binding fails because the socket file exists and responds to a ping, the second instance should exit with a helpful message).

**Phase to address:** Phase implementing SAML HTTP listener.

---

### Pitfall 10: LSUIElement App Has No Default Quit Mechanism

**What goes wrong:** With `LSUIElement = YES` (no Dock icon, no default app menu), users have no standard way to quit the app. If there is no "Quit" item in the menu bar menu, the app can only be killed via Activity Monitor or `kill` — and this kills it without running cleanup (openvpn teardown, socket removal, credential deletion).

**Prevention:**
- Always include a "Quit AWSVPNClient" `Button` in the `MenuBarExtra` view.
- The quit button's action must disconnect all active VPN connections before calling `NSApplication.shared.terminate(nil)`.
- Implement `applicationShouldTerminate` in `AppDelegate` to block termination until all tunnels are confirmed down (with a timeout, e.g., 5 seconds).

**Phase to address:** Phase implementing menu bar UI (must be in initial scaffold, not deferred).

---

## Minor Pitfalls

---

### Pitfall 11: macOS Sequoia (15+) Blocks Unsigned Apps Without Right-Click Open

**What goes wrong:** On macOS Sequoia 15+, the `Control + Right-click → Open` workaround for unsigned apps no longer works by default. Users must open System Settings → Privacy & Security and manually approve the app after the first blocked launch.

**Prevention:**
- Document in README: exact steps for macOS 15+ approval.
- The app itself cannot work around this — it's a Gatekeeper enforcement change.
- Not a code issue, purely a documentation/onboarding issue.

**Phase to address:** README / deployment phase.

---

### Pitfall 12: NWListener stateUpdateHandler Called Before newConnectionHandler Is Set

**What goes wrong:** If you set `stateUpdateHandler` and `newConnectionHandler` in separate steps and the listener reaches `.ready` state before `newConnectionHandler` is assigned, incoming connections are dropped silently during that window.

**Prevention:**
- Set both handlers before calling `listener.start(queue:)`. Never assign handlers after starting.

**Phase to address:** Phase implementing SAML HTTP listener and Unix IPC socket.

---

### Pitfall 13: Process.waitUntilExit() Blocks the Main Thread

**What goes wrong:** Calling `process.waitUntilExit()` on the main thread blocks SwiftUI rendering for the duration of the openvpn process (minutes to hours). The app becomes unresponsive.

**Prevention:**
- Never call `waitUntilExit()` on the main thread.
- Use `process.terminationHandler` (called on a background queue) to react to process exit.
- Or `await withCheckedContinuation { process.terminationHandler = { _ in continuation.resume() } }` in an async context.

**Phase to address:** Phase implementing VPN connection launch.

---

### Pitfall 14: Config Files Stored in Application Support Without Error If Directory Missing

**What goes wrong:** If `~/Library/Application Support/AWSVPNClient/configs/` does not exist (e.g., first launch), copying a config file there silently fails.

**Prevention:**
- Always call `FileManager.default.createDirectory(at:withIntermediateDirectories:true)` before any write, not just on first launch.

**Phase to address:** Phase implementing config management.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| App scaffold + MenuBarExtra | No quit mechanism (Pitfall 10) | Add Quit button in initial scaffold |
| SAML HTTP listener (NWListener TCP) | Cannot restart after cancel (Pitfall 2), body not buffered (Pitfall 5), port conflict (Pitfall 9) | Keep listener running for full session, buffer body |
| Unix IPC socket (NWListener Unix) | Cannot restart after cancel (Pitfall 2), path too long (Pitfall 3), stale socket file on crash (Pitfall 2) | Delete socket on startup, short path |
| VPN connection launch | Zombie processes (Pitfall 1), temp cred file on disk (Pitfall 6), blocking wait (Pitfall 13) | PID tracking, `defer` cleanup, async wait |
| VPN state observation + menu UI | @Observable off-main-thread (Pitfall 4), stale menu render (Pitfall 8) | @MainActor on VPNManager |
| Config management | Missing directory (Pitfall 14) | createDirectory on every write |
| App termination | openvpn orphans (Pitfall 1), stale socket (Pitfall 2) | Disconnect all in applicationWillTerminate |

---

## Sources

- Apple Developer Forums — NWListener stop/restart fails: https://developer.apple.com/forums/thread/129452
- Swift Forums — SR-13918 NWListener can't cancel and relisten: https://github.com/apple/swift/issues/56316
- Apple Developer Forums — NWListener with NWEndpoint.unix: https://developer.apple.com/forums/thread/719635
- dotnet/runtime issue #79503 — macOS 104 byte Unix socket path limit: https://github.com/dotnet/runtime/issues/79503
- Swift Forums — @Observable and main thread requirements: https://forums.swift.org/t/do-update-to-observable-properties-have-to-be-done-on-the-main-thread/74954
- Jesse Squires — @Observable is not a drop-in for ObservableObject: https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/
- Apple Feedback FB13683957 — MenuBarExtra .menu style does not rerender on open: https://github.com/feedback-assistant/reports/issues/477
- Apple Feedback FB13683950 — MenuBarExtra no event for when menu opens: https://github.com/feedback-assistant/reports/issues/475
- Cindori — Hands-on building a Menu Bar experience with SwiftUI: https://cindori.com/developer/hands-on-menu-bar
- NSHipster — Temporary Files: https://nshipster.com/temporary-files/
- Fluid Attacks — Insecure temporary files in Swift: https://docs.fluidattacks.com/criteria/fixes/swift/028/
- Swift Forums — Script (subprocess) behaves differently on macOS (SIGTERM not propagated): https://forums.swift.org/t/script-behaves-differently-on-rpi-than-on-macos/41728
- AlwaysRightInstitute — Intro to Network.framework Servers: http://www.alwaysrightinstitute.com/network-framework/
