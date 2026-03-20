# Phase 2: Connection Lifecycle - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Full VPN connection lifecycle: SAML authentication end-to-end (dummy openvpn call → CRV1 parse → browser open → NWListener callback on :35001 → sudo openvpn connect), state machine transitions (disconnected → authenticating → connected → disconnecting → failed), subprocess management, and cleanup. No config management UI (Phase 3) and no IPC socket (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Concurrent Auth Attempts
- Only one SAML auth flow can run at a time (port 35001 is shared)
- While any config is `.authenticating`, all other disconnected configs are blocked — they cannot start a new auth
- `.authenticating` configs ARE clickable, but clicking them **cancels** the in-progress auth
- Cancel action: stop the NWListener, kill the dummy openvpn Process, delete the temp credentials file, reset state to `.disconnected`
- After cancel, config is immediately clickable again — no cooldown, no `.failed` state

### SAML Auth Timeout
- Timeout: **30 seconds** from browser open until auto-cancel (if browser login not completed)
- Stored as a compile-time constant in `VPNManager`: `private let samlTimeoutSeconds: TimeInterval = 30`
- Timeout triggers transition to `.failed("SAML auth timed out")`
- Same cancel path as manual cancel: stop listener, kill process, delete temp file

### "Connected" Detection Trigger
- Parse openvpn stdout line-by-line; transition to `.connected` when `"Initialization Sequence Completed"` appears
- Monitor `Process.terminationHandler` for unexpected exits while `.connected` → transition to `.failed("openvpn exited unexpectedly")`
- openvpn stdout + stderr piped to a single `FileHandle` writing to `~/Library/Logs/AWSVPNClient/<name>.log` — **file only**, no in-memory buffer
- Logs directory created alongside the configs directory if it doesn't exist

### Failed State Recovery
- Clicking a `.failed` config **immediately starts a fresh connect flow** — no explicit dismiss step
- Consistent with cancel recovery: always one click to retry
- Menu label format: `"config-name   ⚠ <short error>"` — e.g., `"my-vpn   ⚠ timed out"`
- Error snippet should be short (≤ 30 chars) — truncate verbose openvpn messages
- Connection state is **ephemeral** — not persisted to disk; app always starts with all configs `.disconnected`

### Claude's Discretion
- Exact log directory creation logic (alongside configs dir setup, or lazy-created per connection)
- PID tracking strategy for the `sudo openvpn` process (PITFALLS.md Pitfall 1 — `pgrep -P` vs `--writepid`)
- Exact openvpn flags passed for the sudo connect call (match Rust reference: `--verb 3 --auth-nocache --inactive 3600 --script-security 2`)
- Line-buffering strategy for stdout parsing (Pipe + FileHandle read loop)
- App termination cleanup sequencing (applicationWillTerminate + atexit safety net)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Auth flow logic (port exactly from Rust)
- `aws-vpn-core/src/vpn.rs` — Complete auth flow: dummy creds format (`N/A`/`ACS::35001`), CRV1 line parsing, `random_hex(12)` prefix, `dig` DNS resolve, final creds format (`N/A`/`CRV1::{sid}::{urlEncoded(saml)}`), openvpn flags
- `aws-vpn-cli/src/main.rs` — CLI orchestration: full sequence from config load → SAML server start → challenge → browser open → SAML receive → sudo connect
- `aws-vpn-core/src/server.rs` — Rust SAML HTTP server reference (Swift uses NWListener replacement)

### Config parsing
- `aws-vpn-core/src/config.rs` — `remote` host/port/proto extraction, auth directive filtering for the patched openvpn conf

### Requirements
- `.planning/REQUIREMENTS.md` §Connection Lifecycle — CONN-01 through CONN-08 (all 8 requirements this phase covers)
- `.planning/PROJECT.md` §Requirements §Validated — Auth flow invariants that MUST be preserved exactly

### Known pitfalls (read before implementing)
- `.planning/research/PITFALLS.md` Pitfall 1 — sudo openvpn orphan processes; PID tracking via `pgrep -P` or `--writepid`
- `.planning/research/PITFALLS.md` Pitfall 2 — NWListener cannot restart after cancellation; use `allowLocalEndpointReuse`; never reuse the same instance
- `.planning/research/PITFALLS.md` Pitfall 4 — @Observable mutations from NWListener queue must be dispatched to MainActor
- `.planning/research/PITFALLS.md` Pitfall 13 — `Process.waitUntilExit()` blocks main thread; use `terminationHandler` instead

### Project constraints
- `.planning/PROJECT.md` §Constraints — Swift 6.1 strict concurrency, @Observable (no @StateObject), macOS 14.0 minimum, Foundation.Process (not swift-subprocess), NOPASSWD sudoers required

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `VPNCore/VPNManager.swift` — Skeleton with `connect(_ config:)` and `disconnect(_ config:)` stubs marked `fatalError("Phase 2")` — these are the exact methods Phase 2 implements
- `VPNCore/ConnectionState.swift` — `public enum ConnectionState` with `.disconnected`, `.authenticating`, `.connected`, `.disconnecting`, `.failed(String)` already defined — use as-is
- `VPNCore/VPNConfig.swift` — `struct VPNConfig: Identifiable, Hashable` with `name: String` and `fileURL: URL` — Phase 2 adds `host`, `port`, `proto` parsed fields from the conf file

### Established Patterns
- `@Observable @MainActor` on VPNManager — all property mutations must happen on the main actor; background NWListener/Process callbacks must `await MainActor.run { ... }`
- `defer { try? FileManager.default.removeItem(at: tempFile) }` — Rust used RAII drop for temp creds; Swift uses `defer` for the same guarantee
- `try? FileManager.default.createDirectory(...)` — established in VPNManager.init(); same pattern for Logs directory

### Integration Points
- `VPNManager.connections: [String: ConnectionState]` — keyed by `config.name`; Phase 2 writes these state transitions
- `VPNManager.isAnyConnected` — drives the menu bar lock icon (Phase 1 already wired); Phase 2 makes this reactive by updating `connections`
- `AWSVPNClient/StatusMenuView.swift` — reads `vpnManager.connections[config.name]` to show per-config state; Phase 3 refines the UI; Phase 2 just needs the state to be correct

</code_context>

<specifics>
## Specific Ideas

- Auth logic from Rust must be ported **exactly** — the randomized hex prefix, dummy credential format, CRV1 field-7 SID extraction, and URL-encoded final credential are all protocol-specific and non-obvious. Any deviation breaks the AWS Client VPN SAML handshake.
- `samlTimeoutSeconds = 30` — user specified 30 seconds. Note: this may be short for slow IdP pages; the constant is easy to adjust after first real-world test.
- Error messages in `.failed` state should be short (≤ 30 chars) and human-readable — e.g., `"timed out"`, `"exited unexpectedly"`, `"CRV1 parse failed"` — not raw openvpn log lines.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-connection-lifecycle*
*Context gathered: 2026-03-20*
