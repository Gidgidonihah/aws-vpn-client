# AWS VPN Client — Swift Menu Bar App

## What This Is

A native macOS menu bar utility that manages AWS Client VPN connections as a background daemon, replacing the existing Rust CLI tool. It ships with a companion `aws-connect` CLI for scripting and terminal control. Users never need a terminal window open to stay connected.

## Core Value

VPN connections run silently in the background — connect once from the menu bar, walk away.

## Requirements

### Validated

<!-- Capabilities already working in the Rust implementation -->

- ✓ AWS Client VPN SAML authentication flow (dummy creds → CRV1 challenge → browser → response) — existing
- ✓ OpenVPN config file parsing (extract remote host/port/protocol, filter auth directives) — existing
- ✓ SAML response collection via local HTTP server on 127.0.0.1:35001 — existing
- ✓ OpenVPN subprocess management (spawn, capture output, pass credentials via temp file) — existing
- ✓ CLI interface (`aws-connect <config>`) — existing

### Active

<!-- New work: the Swift rewrite -->

- [ ] macOS menu bar app (SwiftUI MenuBarExtra, `LSUIElement = YES`, no Dock icon)
- [ ] Menu shows all configs with live connection state (disconnected / authenticating / connected)
- [ ] Click a config to connect; click a connected config to disconnect
- [ ] Multiple simultaneous VPN connections supported
- [ ] SAML authentication opens browser automatically, completes without user intervention beyond IdP login
- [ ] Connection runs as background subprocess under `sudo openvpn` (NOPASSWD sudoers entry)
- [ ] Config management: add via NSOpenPanel, remove via menu, stored in `~/Library/Application Support/AWSVPNClient/configs/`
- [ ] Per-connection log files in `~/Library/Logs/AWSVPNClient/<name>.log`, viewable from menu (opens Console.app)
- [ ] Menu bar icon reflects overall state: `lock.fill` (any connected) / `lock.open` (all disconnected)
- [ ] Companion `aws-connect` CLI: `connect`, `disconnect`, `status` commands via Unix domain socket IPC
- [ ] CLI prints helpful error if app is not running

### Out of Scope

- Signing / notarization — not needed for personal use
- Preferences window — no settings UI, config is file-based
- Auto-update mechanism — manual builds only
- Non-macOS platforms — macOS 13+ (Ventura) only, required for MenuBarExtra
- Keeping Rust workspace long-term — legacy code deleted after Swift version verified

## Context

The existing Rust CLI (`aws-connect`) works but requires a terminal session to remain open for the duration of the VPN connection. The SAML auth flow and OpenVPN subprocess logic are well-understood and will be ported to Swift. The Rust workspace (`aws-vpn-core/`, `aws-vpn-cli/`, etc.) becomes legacy after the Swift implementation is verified and will be deleted.

Existing authentication logic to preserve exactly:
- Randomized hex prefix on hostname for DNS resolve
- Dummy credential format: `N/A` / `ACS::35001`
- CRV1 line parsing: URL from `https://` split, SID from field 7 (colon-split)
- Final credential format: `N/A` / `CRV1::{sid}::{urlEncoded(saml)}`

## Constraints

- **Tech stack**: Swift + SwiftUI + Network.framework — full rewrite, no Rust dependency
- **Min macOS**: 13.0 (Ventura) — required for `MenuBarExtra` scene
- **Privileges**: `sudo openvpn` requires NOPASSWD sudoers entry — documented in README, must be set up by user
- **IPC**: Unix domain socket at `~/Library/Application Support/AWSVPNClient/daemon.sock`
- **No code signing**: Personal-use tool, unsigned builds only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift full rewrite (no Rust) | Native macOS APIs, no terminal required, proper background process lifecycle | — Pending |
| SwiftUI MenuBarExtra | Native menu bar integration, macOS 13+ only | — Pending |
| Unix domain socket for IPC | Simple, reliable, no network stack needed for local CLI→app communication | — Pending |
| NWListener for SAML server | Network.framework is the modern macOS API; replaces axum/tokio | — Pending |
| @Observable VPNManager | SwiftUI-native state management pattern (Swift 5.9+) | — Pending |
| Core framework target | Shared by App + CLI — no code duplication between targets | — Pending |
| NOPASSWD sudoers | Avoids password prompts mid-connection; trade-off is documented security risk | — Pending |
| Legacy Rust left in place initially | Delete after Swift version verified working | — Pending |

---
*Last updated: 2026-03-17 after initialization*
