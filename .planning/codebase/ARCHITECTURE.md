# Architecture

**Analysis Date:** 2026-03-17

## Pattern Overview

**Overall:** Layered CLI application with a dedicated authentication layer

**Key Characteristics:**
- Monolithic workspace with two distinct crates (core library + CLI)
- Async-first design using tokio runtime
- Separation of concerns: config parsing, SAML server, VPN operations
- Process-based integration with external tools (openvpn, aws, dig)
- Temporary file management for sensitive credential handling

## Layers

**CLI Layer (aws-vpn-cli):**
- Purpose: User interface and orchestration - entry point for the application
- Location: `aws-vpn-cli/src/main.rs`
- Contains: Command-line argument parsing, application flow control, user I/O
- Depends on: `aws-vpn-core` library, `clap`, `tokio`, `open`, `anyhow`
- Used by: Direct execution as compiled binary

**Core Library (aws-vpn-core):**
- Purpose: Shared business logic and utilities
- Location: `aws-vpn-core/src/` with modules: `config`, `server`, `vpn`
- Contains: Configuration loading, SAML server implementation, VPN authentication and connection logic
- Depends on: `axum`, `tokio`, `serde`, `tempfile`, `rand`, `anyhow`
- Used by: CLI layer and potentially other consumers

**Configuration Module:**
- Purpose: Parse and validate OpenVPN config files
- Location: `aws-vpn-core/src/config.rs`
- Contains: `VpnConfig` struct, config file parsing, filtering logic
- Key responsibility: Extract `remote`, `proto` directives and filter authentication-related directives

**SAML Server Module:**
- Purpose: Lightweight HTTP server to receive SAML responses from IdP redirect
- Location: `aws-vpn-core/src/server.rs`
- Contains: `SamlServer` struct, axum routing, POST handler for `/`
- Key responsibility: Listen on `127.0.0.1:35001` for SAML response, signal completion via oneshot channel

**VPN Operations Module:**
- Purpose: Wrapper around openvpn executable with authentication challenge/response flow
- Location: `aws-vpn-core/src/vpn.rs`
- Contains: `AuthChallenge` struct, DNS resolution, auth challenge retrieval, connection establishment
- Key responsibility: Orchestrate openvpn subprocess calls with proper credential handling

## Data Flow

**Main Authentication Flow:**

1. **Config Resolution** (CLI) - Determine VPN config file path from args or default location
2. **Permission Setup** - Request sudo credentials upfront with `sudo -v`
3. **Config Parsing** - Load config, extract remote host/port/protocol, filter authentication directives
4. **Server Startup** - Start SAML HTTP server listening on `127.0.0.1:35001`
5. **DNS Resolution** - Resolve VPN endpoint with randomized hostname using `dig`
6. **Auth Challenge** - Run openvpn with dummy credentials to extract SAML redirect URL and session ID
7. **Browser Launch** - Open browser to SAML authentication URL
8. **SAML Receipt** - Wait for HTTP POST to SAML server with SAML response (30s timeout)
9. **AWS Login** - Optionally verify AWS SSO session with `aws sts get-caller-identity`
10. **VPN Connection** - Run openvpn under sudo with SAML credentials to establish tunnel

**State Management:**
- Config state: `VpnConfig` struct holds loaded configuration and temporary filtered config file
- SAML state: `SamlServer` holds oneshot channels for response and shutdown signaling
- Credentials: Temporary files created on-demand, auto-deleted when dropped (RAII pattern)

## Key Abstractions

**VpnConfig:**
- Purpose: Represents parsed and normalized OpenVPN configuration
- Examples: `aws-vpn-core/src/config.rs` line 6
- Pattern: Value object with filtered config file as owned temporary resource

**SamlServer:**
- Purpose: Encapsulates lifecycle of SAML response handler
- Examples: `aws-vpn-core/src/server.rs` line 16
- Pattern: Builder-like async construction, channel-based signaling for coordination

**AuthChallenge:**
- Purpose: Represents SAML authentication requirements extracted from openvpn output
- Examples: `aws-vpn-core/src/vpn.rs` line 8
- Pattern: Immutable data structure carrying extracted values

**Command Execution:**
- Purpose: Encapsulate subprocess interactions (openvpn, dig, aws, sudo)
- Pattern: Direct `std::process::Command` without wrapper - leverages Rust's error propagation

## Entry Points

**CLI Binary:**
- Location: `aws-vpn-cli/src/main.rs` line 30 (`#[tokio::main]`)
- Triggers: Execution of `aws-connect` binary with CLI arguments
- Responsibilities: Parse arguments, validate file paths, orchestrate the complete flow from config to connection

**SAML Server Handler:**
- Location: `aws-vpn-core/src/server.rs` line 52 (`handle_saml` function)
- Triggers: POST request to `127.0.0.1:35001` from browser redirect
- Responsibilities: Extract SAML response from form data, signal completion

## Error Handling

**Strategy:** Bubble errors up with context using `anyhow`

**Patterns:**
- `.context()` for adding human-readable context at each step
- `.with_context(|| ...)` for lazy context generation with state information
- `bail!()` for unrecoverable errors with formatted messages
- `.ok()` for non-critical errors that should be silently ignored (e.g., server shutdown)
- Early returns with `?` operator for clean error propagation

**Example from main.rs:**
```rust
let saml_response = tokio::time::timeout(Duration::from_secs(30), saml.response_rx)
    .await
    .context("SAML authentication timed out")?
    .context("SAML server channel closed unexpectedly")?;
```

## Cross-Cutting Concerns

**Logging:** Minimal explicit logging - relies on `eprintln!` macros in `server.rs` and user-facing `println!` in CLI. No structured logging framework.

**Validation:** Inline validation at each step:
- Config file existence checks before loading
- Non-empty field extraction from config
- HTTP form field presence validation
- AWS CLI availability checks

**Authentication:** Multi-step SAML-based flow:
1. Extract challenge from openvpn
2. User authenticates via browser redirect
3. SAML response received via local HTTP server
4. Session ID and response passed to openvpn for tunnel establishment

**Temporary Resource Management:** RAII pattern with `tempfile::NamedTempFile` - automatic cleanup on drop:
- Filtered config file in `VpnConfig::filtered_conf`
- Credential files created in `get_auth_challenge` and `connect` functions

---

*Architecture analysis: 2026-03-17*
