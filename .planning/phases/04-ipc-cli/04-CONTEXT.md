# Phase 4: IPC & CLI - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Add a Unix domain socket IPC server to the running app and implement the `aws-connect` companion CLI that speaks to it. The CLI target stub already exists at `aws-connect/main.swift`. No GUI changes — this phase is entirely about the IPC layer and CLI logic.

</domain>

<decisions>
## Implementation Decisions

### IPC Message Protocol
- **D-01:** Line-delimited JSON — each message is one JSON object terminated by `\n`
- **D-02:** Request+response model — CLI sends a command, server replies before CLI exits
  - Request: `{"cmd":"connect","name":"corp-vpn"}\n`
  - Response: `{"ok":true}\n` or `{"ok":false,"error":"config not found"}\n`
  - Commands: `connect`, `disconnect`, `status`
- **D-03:** Status response embeds the data inline: `{"ok":true,"configs":[{"name":"corp-vpn","state":"connected"},...]}\n`

### CLI Response Behavior
- **D-04:** Silent on success — `aws-connect connect <name>` prints nothing and exits 0
- **D-05:** Errors go to stderr, exit non-zero — e.g. `error: config not found` or `Start the AWSVPNClient menu bar app first`
- **D-06:** Fire-and-forget semantics — `connect`/`disconnect` send the command, get an ok/error ack, and exit. They do NOT wait for the VPN to fully connect.

### Status Table Format
- **D-07:** Two plain aligned columns — `name` left-padded, `state` right
  ```
  corp-vpn    connected
  dev-vpn     disconnected
  staging     failed: timed out
  ```
- **D-08:** No header row — stays grep-friendly
- **D-09:** `failed` state shows error reason inline: `failed: <short message>` (matches the ≤30 char format established in Phase 2)
- **D-10:** Configs listed alphabetically (matches menu sort order from Phase 3)

### Arg Parsing
- **D-11:** Manual `CommandLine.arguments` — no new SPM dependencies
- **D-12:** Argument shape:
  - `aws-connect <name>` → connect
  - `aws-connect --disconnect <name>` → disconnect
  - `aws-connect status` → status
  - Any other input → print usage to stderr and exit 1

### IPC Server Lifecycle
- **D-13:** Claude's discretion — where `IPCServer` lives (VPNCore vs. App target) and how it hooks into VPNManager's `@MainActor` context
- **D-14:** Stale socket cleanup (IPC-01) is Claude's discretion — remove on launch if socket file exists but nothing is listening

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §IPC & CLI — IPC-01 through IPC-05 (all phase requirements)

### Project constraints
- `.planning/PROJECT.md` §Constraints — Swift 6.1 strict concurrency, macOS 14+, Unix socket path: `~/Library/Application Support/AWSVPNClient/daemon.sock`
- `.planning/PROJECT.md` §Key Decisions — VPNCore shared framework, NWListener for SAML server (pattern to follow)

### Prior phase patterns
- `.planning/phases/02-connection-lifecycle/02-CONTEXT.md` — failed state label format (≤30 chars), Swift 6 concurrency patterns
- `.planning/phases/03-menu-ui-config-management/03-CONTEXT.md` — config sort order (alphabetical), connection state labels

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `VPNCore/VPNManager.swift` — `configs: [VPNConfig]`, `connections: [String: ConnectionState]`, `connect()`, `disconnect()` — all the state the IPC server needs to expose
- `VPNCore/ConnectionState.swift` — `isConnected`, `isAuthenticating`, `isDisconnecting`, `isActive` helpers; `failed(String)` carries the error message for status output
- `VPNCore/SAMLServer.swift` — existing NWListener usage; pattern for how to set up a socket server with Network.framework
- `aws-connect/main.swift` — stub target, already imports VPNCore; replace entirely in this phase

### Established Patterns
- `@Observable @MainActor VPNManager` — IPC server must dispatch to `@MainActor` when calling `connect()`/`disconnect()` or reading `configs`/`connections`
- `nonisolated` + `DispatchQueue` bridge — established pattern in SAMLServer for GCD callbacks into async context
- `ConnectionState.failed(String)` — already carries a short error string; use directly for status output

### Integration Points
- `AWSVPNClientApp.swift` — app entry point; IPCServer should be started here (or in AppDelegate) after VPNManager is initialized
- `VPNManager.configs` + `VPNManager.connections` — the two dictionaries that feed the `status` response

</code_context>

<specifics>
## Specific Ideas

- JSON protocol debuggable with `echo '{"cmd":"status"}' | nc -U ~/Library/Application\ Support/AWSVPNClient/daemon.sock`
- Status output format matches `corp-vpn    connected` style (spaces, no header) — grep-friendly
- `failed` reason reuses the same ≤30 char format already locked in Phase 2/3

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-ipc-cli*
*Context gathered: 2026-03-31*
