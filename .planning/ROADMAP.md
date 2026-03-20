# Roadmap: AWS VPN Client — Swift Menu Bar App

## Overview

Starting from a working Rust CLI, we build a native Swift macOS menu bar app that manages AWS Client VPN connections silently in the background. The work flows from scaffold (Xcode project structure and core framework) through the hardest problem (SAML auth + openvpn subprocess lifecycle), then wires real state into a full menu UI with config management, adds the companion CLI via Unix socket IPC, and finishes with legacy cleanup and documentation. The Rust code stays untouched until Phase 5 confirms the Swift version works end-to-end.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Scaffold** - Xcode multi-target project with VPNCore framework, menu bar shell, and config persistence (completed 2026-03-19)
- [x] **Phase 2: Connection Lifecycle** - SAML auth flow + openvpn subprocess management with all critical pitfall mitigations (completed 2026-03-20)
- [ ] **Phase 3: Menu UI + Config Management** - Full menu UI wired to live state, config add/remove, log viewer
- [ ] **Phase 4: IPC & CLI** - Unix socket server in app, companion aws-connect CLI with connect/disconnect/status
- [ ] **Phase 5: Cleanup & Docs** - Delete Rust legacy, update README with Swift setup instructions

## Phase Details

### Phase 1: Scaffold
**Goal**: A running Xcode project with three linked targets, a menu bar app that stays out of the Dock, and config persistence — the foundation everything else links against
**Depends on**: Nothing (first phase)
**Requirements**: SCAF-01, SCAF-02
**Success Criteria** (what must be TRUE):
  1. Xcode project builds all three targets (AWSVPNClient app, VPNCore framework, aws-connect CLI) without errors
  2. App launches showing a menu bar icon with no Dock icon and no main window
  3. A "Quit" menu item terminates the app cleanly
  4. VPNManager (@Observable @MainActor) skeleton is importable from both app and CLI targets
  5. Config directory at ~/Library/Application Support/AWSVPNClient/configs/ is created on first launch
**Plans**: 3 plans
Plans:
- [x] 01-01-PLAN.md — Xcode project creation with three targets, framework embedding, and rpath spike
- [x] 01-02-PLAN.md — VPNCore types (VPNConfig, ConnectionState, VPNManager) and MenuBarExtra shell wiring
- [x] 01-03-PLAN.md — Gap closure: copy aws-connect binary into app bundle via build phase

### Phase 2: Connection Lifecycle
**Goal**: A VPN connection can be initiated and terminated end-to-end — SAML auth completes, openvpn runs as a background subprocess, and no orphaned processes or credential files survive
**Depends on**: Phase 1
**Requirements**: CONN-01, CONN-02, CONN-03, CONN-04, CONN-05, CONN-06, CONN-07, CONN-08
**Success Criteria** (what must be TRUE):
  1. Clicking a config name triggers the SAML flow: browser opens to the AWS IdP login page automatically
  2. After IdP login, openvpn connects and the connection state transitions to "connected"
  3. Clicking a connected config disconnects it and the openvpn process exits
  4. Quitting the app terminates all running openvpn subprocesses — none survive app exit
  5. Per-connection log file appears at ~/Library/Logs/AWSVPNClient/<name>.log and receives openvpn output
**Plans**: 5 plans
Plans:
- [ ] 02-01-PLAN.md — Wave 0: XCTest target, VPNError type, --writepid verification, test stubs
- [ ] 02-02-PLAN.md — Config parsing + auth helpers (VPNConfigParser, randomHex, CRV1, credentials) via TDD
- [ ] 02-03-PLAN.md — SAMLServer: long-lived NWListener with CheckedContinuation via TDD
- [ ] 02-04-PLAN.md — VPNManager.connect(): full SAML auth flow + openvpn subprocess + stdout monitoring
- [ ] 02-05-PLAN.md — VPNManager.disconnect() + AppDelegate termination cleanup + human verification

### Phase 3: Menu UI + Config Management
**Goal**: The menu accurately reflects live connection state for all configs, and users can add and remove configs without touching the file system manually
**Depends on**: Phase 2
**Requirements**: CONF-01, CONF-02, CONF-03, CONF-04, UI-01, UI-02, UI-03, UI-04, UI-05
**Success Criteria** (what must be TRUE):
  1. Menu bar icon shows lock.fill when any connection is active and lock.open when all are disconnected
  2. Each config listed in the menu shows its current state (connected indicator, authenticating label, or blank)
  3. A config in the authenticating state is non-clickable until the SAML flow completes or fails
  4. User can add a .conf file via "Add Config..." and it appears in the menu immediately
  5. User can remove a config via the "Remove Config" submenu and it disappears from the menu
**Plans**: TBD

### Phase 4: IPC & CLI
**Goal**: The companion aws-connect CLI can control the running app and query connection status over a Unix socket, enabling scripting and terminal workflows
**Depends on**: Phase 3
**Requirements**: IPC-01, IPC-02, IPC-03, IPC-04, IPC-05
**Success Criteria** (what must be TRUE):
  1. App creates daemon.sock on launch and removes any stale socket file from a previous crash
  2. Running `aws-connect <name>` from a terminal connects the named VPN config
  3. Running `aws-connect --disconnect <name>` disconnects it
  4. Running `aws-connect status` prints a table of all config names and their current states
  5. Running any aws-connect command when the app is not running prints "Start the AWSVPNClient menu bar app first"
**Plans**: TBD

### Phase 5: Cleanup & Docs
**Goal**: Legacy Rust code is gone, the README reflects the Swift implementation, and the project is self-contained and documented for future use
**Depends on**: Phase 4
**Requirements**: CLEN-01, CLEN-02
**Success Criteria** (what must be TRUE):
  1. Rust workspace directories (aws-vpn-core/, aws-vpn-cli/, Cargo.toml) and legacy shell/Go files no longer exist in the repo
  2. README covers the complete setup: sudoers NOPASSWD entry, building the app, installing the aws-connect CLI binary, and adding configs
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Scaffold | 3/3 | Complete   | 2026-03-20 |
| 2. Connection Lifecycle | 5/5 | Complete   | 2026-03-20 |
| 3. Menu UI + Config Management | 0/TBD | Not started | - |
| 4. IPC & CLI | 0/TBD | Not started | - |
| 5. Cleanup & Docs | 0/TBD | Not started | - |
