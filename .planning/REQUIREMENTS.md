# Requirements: AWS VPN Client — Swift Menu Bar App

**Defined:** 2026-03-17
**Core Value:** VPN connections run silently in the background — connect once from the menu bar, walk away.

## v1 Requirements

### Scaffold

- [x] **SCAF-01**: Xcode project exists with three targets — App (AWSVPNClient), VPNCore (framework), and CLI (aws-connect)
- [x] **SCAF-02**: App runs as menu bar only — no Dock icon, no main window (LSUIElement = YES in Info.plist)

### Connection Lifecycle

- [x] **CONN-01**: User can initiate a VPN connection by clicking a config name in the menu
- [x] **CONN-02**: SAML authentication flow completes end-to-end: dummy openvpn call → CRV1 line parsed → browser opens → SAML POST received on :35001 → openvpn connected
- [x] **CONN-03**: Each connection has a state machine: disconnected → authenticating → connected → disconnecting → failed
- [x] **CONN-04**: Connected openvpn process runs as background subprocess under `sudo openvpn` (NOPASSWD) until explicitly stopped
- [x] **CONN-05**: App termination kills all openvpn subprocesses — no orphaned tunnels survive app quit
- [x] **CONN-06**: Credential temp files (dummy creds, SAML creds) are deleted immediately after the subprocess consumes them
- [x] **CONN-07**: User can disconnect a connected config by clicking it in the menu
- [x] **CONN-08**: Per-connection stdout+stderr streamed to `~/Library/Logs/AWSVPNClient/<name>.log`

### Config Management

- [x] **CONF-01**: User can add a `.conf` file via NSOpenPanel ("Add Config…" in menu)
- [x] **CONF-02**: Config files stored in `~/Library/Application Support/AWSVPNClient/configs/`
- [x] **CONF-03**: User can remove a config via "Remove Config ▶" submenu
- [x] **CONF-04**: All configs in the directory are listed in the menu at launch and reflect changes after add/remove

### Menu Bar UI

- [x] **UI-01**: Menu bar icon is `lock.fill` when any connection is active, `lock.open` otherwise (template rendering for dark/light mode)
- [x] **UI-02**: Menu lists each config with per-config state — "● Connected" indicator for connected, "[authenticating…]" for in-progress, blank for disconnected
- [x] **UI-03**: Configs in authenticating state are non-clickable (disabled) during the SAML flow
- [x] **UI-04**: "View Logs ▶" submenu lists each config and opens its log file in Console.app
- [x] **UI-05**: "Quit" menu item terminates the app and all openvpn subprocesses

### IPC & CLI

- [ ] **IPC-01**: App starts a Unix domain socket server at `~/Library/Application Support/AWSVPNClient/daemon.sock` on launch; removes stale socket file on startup
- [ ] **IPC-02**: `aws-connect <name>` sends connect command and exits
- [ ] **IPC-03**: `aws-connect --disconnect <name>` sends disconnect command and exits
- [ ] **IPC-04**: `aws-connect status` prints a table of all config names and their current state
- [ ] **IPC-05**: CLI prints a clear error ("Start the AWSVPNClient menu bar app first") if socket is not found

### Cleanup & Docs

- [ ] **CLEN-01**: Rust workspace (`aws-vpn-core/`, `aws-vpn-cli/`, `Cargo.toml`, legacy shell/Go files) deleted after Swift implementation verified working
- [ ] **CLEN-02**: README updated with Swift setup instructions: sudoers entry, building the app, installing the CLI binary, adding configs

## v2 Requirements

### Quality of Life

- **QOL-01**: App launches at login (SMAppService — macOS 13+)
- **QOL-02**: System notification on successful connect and disconnect (UNUserNotificationCenter)
- **QOL-03**: Connection duration timer displayed in menu next to connected config name
- **QOL-04**: App checks openvpn is installed and accessible on first launch; shows actionable error if not

## Out of Scope

| Feature | Reason |
|---------|--------|
| Code signing / notarization | Personal-use tool; unnecessary complexity |
| Preferences window | Config is file-based; no settings needed |
| Kill switch (block traffic on disconnect) | Disproportionate complexity for personal tool |
| In-app log viewer | Console.app is sufficient |
| Linux / Windows | macOS 14+ only; MenuBarExtra and NWListener are Apple-only APIs |
| Auto-update | Manual builds; no audience to update |
| Multiple SAML servers simultaneously | Port 35001 is hardcoded; one auth flow at a time (connect sequentially) |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SCAF-01 | Phase 1 | Complete |
| SCAF-02 | Phase 1 | Complete |
| CONN-01 | Phase 2 | Complete |
| CONN-02 | Phase 2 | Complete |
| CONN-03 | Phase 2 | Complete |
| CONN-04 | Phase 2 | Complete |
| CONN-05 | Phase 2 | Complete |
| CONN-06 | Phase 2 | Complete |
| CONN-07 | Phase 2 | Complete |
| CONN-08 | Phase 2 | Complete |
| CONF-01 | Phase 3 | Complete |
| CONF-02 | Phase 3 | Complete |
| CONF-03 | Phase 3 | Complete |
| CONF-04 | Phase 3 | Complete |
| UI-01 | Phase 3 | Complete |
| UI-02 | Phase 3 | Complete |
| UI-03 | Phase 3 | Complete |
| UI-04 | Phase 3 | Complete |
| UI-05 | Phase 3 | Complete |
| IPC-01 | Phase 4 | Pending |
| IPC-02 | Phase 4 | Pending |
| IPC-03 | Phase 4 | Pending |
| IPC-04 | Phase 4 | Pending |
| IPC-05 | Phase 4 | Pending |
| CLEN-01 | Phase 5 | Pending |
| CLEN-02 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 26
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after roadmap creation (traceability complete)*
