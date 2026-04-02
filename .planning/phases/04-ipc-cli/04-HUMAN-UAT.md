---
status: partial
phase: 04-ipc-cli
source: [04-VERIFICATION.md]
started: 2026-03-31T21:00:00Z
updated: 2026-03-31T21:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Socket lifecycle on app launch
expected: daemon.sock exists at ~/Library/Application Support/AWSVPNClient/daemon.sock after launch; relaunching the app does not fail (stale socket cleaned up)
result: [pending]

### 2. aws-connect status prints config table
expected: Aligned two-column table printed to stdout with config names and states; exits 0. Empty output (not an error) if no configs loaded
result: [pending]

### 3. aws-connect <name> connects the named VPN config
expected: Exits 0 silently; menu bar shows SAML authentication flow initiating
result: [pending]

### 4. aws-connect --disconnect <name> disconnects it
expected: Exits 0 silently; connection state returns to disconnected
result: [pending]

### 5. App not running error path
expected: Prints exactly "Start the AWSVPNClient menu bar app first" to stderr; exits 1
result: approved — confirmed by human in Plan 02 Task 2 checkpoint (2026-03-31)

## Summary

total: 5
passed: 1
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
