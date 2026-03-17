# Feature Landscape

**Domain:** macOS menu bar VPN client utility (personal tool, AWS Client VPN + SAML)
**Researched:** 2026-03-17
**Overall confidence:** HIGH (requirements well-defined in PROJECT.md, supplemented by ecosystem research)

---

## Table Stakes

Features users expect from a macOS menu bar utility. Missing = product feels broken or incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Menu bar icon with connection state | macOS menu bar utility convention — icon must communicate state at a glance | Low | `lock.fill` (any connected) / `lock.open` (all disconnected); must be SF Symbol template image for light/dark mode compatibility |
| List all configs in menu | Core interaction model — users pick which VPN to connect | Low | Show each config name with inline state indicator (disconnected / authenticating / connected) |
| Click config to connect | Primary action must be one click from the menu | Low | Initiates SAML auth flow + openvpn subprocess |
| Click connected config to disconnect | Toggle-style disconnect must be obvious and accessible | Low | Terminate openvpn subprocess, clean up state |
| Multiple simultaneous connections | AWS VPN configs are environment-specific (staging, production, etc.) — users run several at once | Medium | Each connection is independent subprocess; state tracked per config |
| SAML browser auth flow | AWS Client VPN requires SAML; auto-opening browser is the expected pattern | Medium | Opens browser automatically; user only touches IdP login; SAML response collected via local HTTP server |
| Add config via file picker | Users need to load new `.ovpn`/`.conf` files without a terminal | Low | NSOpenPanel; copy to `~/Library/Application Support/AWSVPNClient/configs/` |
| Remove config from menu | Configs become stale; removal must be available without touching the filesystem manually | Low | Submenu or right-click; requires confirmation to avoid accidental removal |
| Persisted configs across launches | Configs stored on disk — not in-memory only | Low | Already defined: `~/Library/Application Support/AWSVPNClient/configs/` |
| Quit from menu | macOS menu bar app convention — always provide Quit at bottom with Cmd+Q | Low | Standard `NSApplication.terminate` |
| App runs without Dock icon | Menu bar-only apps must suppress Dock presence (`LSUIElement = YES`) | Low | Already in requirements; affects activation policy |
| No terminal window required | Core value proposition — daemon manages subprocess lifecycle | Medium | Background process management via `@Observable VPNManager` |

---

## Differentiators

Features that distinguish this tool from generic VPN clients or the predecessor Rust CLI. Not table stakes, but add meaningful value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Per-connection log files | Debugging VPN issues is painful without logs; Console.app integration makes them accessible | Low | Write to `~/Library/Logs/AWSVPNClient/<name>.log`; "Open Log" menu item opens Console.app with filter |
| Companion CLI (`aws-connect`) | Terminal-friendly users and scripts can control the running app without a second terminal session | Medium | Unix domain socket IPC; `connect`, `disconnect`, `status` subcommands; helpful error if app not running |
| Descriptive connection state in menu | "Authenticating…" vs "Connected (2m)" vs "Disconnected" communicates progress without opening a log | Medium | Live status string under each config name in menu; timer for connected duration optional |
| Launch at login | VPN tool should survive reboots without user remembering to start it | Low | `SMAppService` (macOS 13+); off by default; toggle in menu; no separate preferences window needed |
| Connection error surfaced in menu | Failed connection reason visible in menu without opening Console.app | Medium | Show last error string under config name; e.g. "SAML timeout — click to retry" |
| System notification on state change | User may be away from screen during auth; notification tells them when connected or when auth fails | Low | `UNUserNotificationCenter`; fire on: connected, disconnected unexpectedly, auth failure |
| Open log from menu | One-click access to per-connection openvpn log in Console.app | Low | `NSWorkspace.open` with log file path; low effort, high utility |

---

## Anti-Features

Features to explicitly NOT build for this personal tool.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Preferences window | Adds UI surface area, state sync complexity, and AppKit/SwiftUI lifecycle headaches — all for 1-2 toggles | Single-item "Launch at Login" toggle directly in the menu; nothing else needs a preferences window |
| Auto-update mechanism | Personal tool with manual builds; adds Sparkle dependency, signing requirements, and network requests | User pulls from git and rebuilds; document in README |
| Kill switch / split tunneling | Out of scope for AWS Client VPN use case; openvpn routing handles this at the server level | Not applicable — AWS VPN config controls routing |
| Connection profiles / profiles UI | Not an enterprise VPN manager; configs are already files | File-based config management is sufficient |
| Bandwidth / traffic graphs | Adds non-trivial persistence and display complexity; does not help the core use case | Per-connection logs already capture this if needed |
| Re-authentication prompts mid-session | SAML session is 24h by default; building re-auth UX in-app adds complexity | When openvpn exits, mark config as disconnected; user clicks to reconnect and re-authenticates |
| System VPN / NEVPNManager integration | AWS Client VPN with SAML does not use the macOS system VPN stack — it's raw openvpn under sudo | Continue with direct openvpn subprocess approach |
| Dock presence | Defeats the purpose of a menu bar utility | `LSUIElement = YES` enforced |
| Multiple identity provider configs | Tool is for a single AWS org; SAML flow is fixed | Hardcode the SAML flow; config files carry the endpoint differences |
| In-app log viewer | Console.app is purpose-built for this | Open log file in Console.app via `NSWorkspace` |

---

## Feature Dependencies

```
Add Config via File Picker
  → Config List in Menu (requires at least one config)

Click Config to Connect
  → SAML Auth Flow
    → Local HTTP Server (port 35001)
    → Browser auto-launch
    → SAML response receipt
  → sudo openvpn subprocess
    → NOPASSWD sudoers entry (user setup, documented in README)

Click Config to Disconnect
  → Terminate openvpn subprocess
  → Update connection state
  → Fire state-change notification (if notifications granted)

Connection Error in Menu
  → openvpn subprocess exit code / log parsing
  → Connection state tracking per config

Open Log from Menu
  → Per-connection log file (created on connect)

Companion CLI
  → App running (IPC socket only available when app is running)
  → Unix domain socket IPC
  → VPNManager state observable

Launch at Login
  → SMAppService (no other dependencies; no preferences window needed)

System Notifications
  → UNUserNotificationCenter authorization (one-time user grant)
  → Connection state transitions
```

---

## MVP Recommendation

Prioritize these features for the initial working version:

1. **Menu bar icon with lock state** — visual feedback before anything else works
2. **Config list with inline state** — must see what you have before you can connect
3. **Add / Remove config** — useless without at least one config
4. **Click to connect (full SAML flow)** — core value
5. **Click to disconnect** — must be able to get out
6. **Per-connection log files** — essential for debugging during development and daily use
7. **Quit** — standard convention

Defer to a second pass:
- **Launch at login** — quality of life, not blocking daily use; `SMAppService` is low complexity so worth adding once core flow is stable
- **System notifications** — UNUserNotificationCenter setup is straightforward; add after core connection flow is reliable
- **Companion CLI** — useful but not blocking the GUI app; add after IPC socket layer is stabilized
- **Connection error in menu** — surface openvpn exit reason after subprocess management is solid
- **Open log from menu** — trivially easy once log files exist; add in the same pass as log files

---

## Error States to Design For

These are distinct UI states, not just log messages. Each needs a visible representation in the menu.

| State | Trigger | Menu Representation | User Action |
|-------|---------|---------------------|-------------|
| Disconnected | Initial / after disconnect | Dim indicator, config name only | Click to connect |
| Authenticating | SAML flow in progress | Spinner or "Authenticating…" label | (waiting) |
| Auth timeout | SAML server waited 30s with no response | "Auth timed out" + click to retry | Click config to retry |
| Connected | openvpn running and tunnel established | Filled indicator, optional duration | Click to disconnect |
| Unexpectedly disconnected | openvpn process exited without user action | "Disconnected (unexpectedly)" | Click to reconnect |
| SAML server port conflict | Port 35001 already in use | Error in menu, cannot connect | User must free port |
| App not running (CLI only) | `aws-connect` invoked with no socket | CLI prints explicit message | Start the app |

---

## Platform Notes

- **macOS 13+ required** — `MenuBarExtra` scene not available before Ventura; `SMAppService` requires macOS 13+
- **NOPASSWD sudoers** — prerequisite for connection; app cannot set this up itself; must be documented
- **UNUserNotificationCenter** — requires one-time user authorization prompt; request on first connect attempt, not on launch
- **Template images** — menu bar icon must use SF Symbols or a monochrome template image; colored icons look wrong in menu bar context
- **AWS Client VPN session duration** — 24h max by default; reconnect after expiry requires full SAML re-auth (expected behavior, not a bug)

---

## Sources

- PROJECT.md — primary requirements source (HIGH confidence)
- [Apple: Use the VPN status menu in the menu bar on Mac](https://support.apple.com/guide/mac-help/vpn-status-menu-bar-mac-mchl7f06ab80/mac) — connection state patterns (MEDIUM confidence)
- [Vipinator: macOS VPN menu bar app](https://github.com/vpukhanov/vipinator) — real-world menu bar VPN app reference (MEDIUM confidence)
- [SMAppService launch at login](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) — implementation pattern (MEDIUM confidence)
- [Tailscale windowed macOS UI beta](https://tailscale.com/blog/windowed-macos-ui-beta) — rationale for menu-only vs windowed trade-offs (MEDIUM confidence)
- [AWS Client VPN SAML session duration](https://repost.aws/questions/QUy5fUEzd_T7-z8I-ngouLAQ/aws-client-vpn-maximum-vpn-session-duration) — 24h session limit (HIGH confidence, AWS docs)
- [AWS VPN SAML port 35001](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/federated-authentication.html) — reserved port for SAML response (HIGH confidence, AWS official)
- [What I Learned Building a Native macOS Menu Bar App (Jan 2026)](https://medium.com/@p_anhphong/what-i-learned-building-a-native-macos-menu-bar-app-eacbc16c2e14) — platform conventions and pitfalls (MEDIUM confidence)
