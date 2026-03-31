# Phase 4: IPC & CLI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 04-ipc-cli
**Areas discussed:** IPC message protocol, CLI response behavior, Status table format, Arg parsing approach

---

## IPC Message Protocol

| Option | Description | Selected |
|--------|-------------|----------|
| Line-delimited JSON | One JSON object per line, easy to debug with nc, extensible | ✓ |
| Plain-text tokens | Space-separated tokens (`connect corp-vpn\n`), minimal parsing | |
| You decide | Claude picks based on codebase patterns | |

**User's choice:** Line-delimited JSON

**Follow-up — server response:**

| Option | Description | Selected |
|--------|-------------|----------|
| Request + response | Server replies `{"ok":true}` or `{"ok":false,"error":"..."}` before CLI exits | ✓ |
| Fire-and-forget | CLI sends command and exits without waiting for response | |

**User's choice:** Request + response

**Notes:** CLI sends `{"cmd":"connect","name":"corp-vpn"}`, server replies with ok/error. Status response embeds config list inline.

---

## CLI Response Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Silent on success | Prints nothing, exits 0. Errors to stderr, non-zero exit. Unix convention. | ✓ |
| Confirmation message | Prints `Connecting corp-vpn...` on success | |
| You decide | Claude picks output style | |

**User's choice:** Silent on success

**Notes:** `connect`/`disconnect` are fire-and-forget semantics — they ack that the command was received, not that the VPN is fully up.

---

## Status Table Format

| Option | Description | Selected |
|--------|-------------|----------|
| Two columns: name + state | Plain aligned columns, no header, grep-friendly | ✓ |
| Wider table with header | Includes NAME/STATE header row | |
| You decide | Claude picks format | |

**User's choice:** Two columns, no header

**Follow-up — failed state:**

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, inline | `corp-vpn    failed: timed out` | ✓ |
| No, just `failed` | Uniform output, details in log file | |

**User's choice:** Yes, inline error reason

**Notes:** Configs listed alphabetically, matches Phase 3 menu sort order.

---

## Arg Parsing Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Manual CommandLine.arguments | No new deps, switch statement handles 3 commands | ✓ |
| Swift Argument Parser (SPM) | Adds apple/swift-argument-parser dep, gets --help for free | |
| You decide | Claude picks based on complexity | |

**User's choice:** Manual CommandLine.arguments

**Notes:** CLI has 3 commands, 1 flag — doesn't warrant a full argument parser library.

---

## Claude's Discretion

- Where `IPCServer` class lives (VPNCore framework vs. App target)
- NWListener vs. POSIX socket implementation details
- Stale socket cleanup implementation at launch

## Deferred Ideas

None.
