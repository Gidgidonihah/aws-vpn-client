# Technology Stack

**Analysis Date:** 2026-03-17

## Languages

**Primary:**
- Rust 1.86.0 - Core application logic, VPN client implementation, SAML server, CLI

**Secondary:**
- Bash - Legacy wrapper script (`aws-connect.sh`)
- Go - Legacy SAML response server (`aws-saml-response-server.go`)

## Runtime

**Environment:**
- Rust toolchain 1.86.0 (Homebrew)
- Cargo 1.86.0 (Rust package manager)

**Package Manager:**
- Cargo
- Lockfile: `Cargo.lock` (present, version 4)

## Frameworks

**Core:**
- Axum 0.7.9 - Web framework for SAML response server HTTP endpoints
- Tokio 1.x (with full features) - Async runtime and concurrent I/O operations

**CLI:**
- Clap 4.5.60 (with derive macros) - Command-line argument parsing

**Utilities:**
- Serde 1.x - Serialization/deserialization framework
- Tempfile 3.x - Temporary file handling

## Key Dependencies

**Critical:**
- `anyhow` 1.0.102 - Error handling (Result type, Context trait)
- `tokio` 1.x - Async runtime (full feature set for threading, networking, sync)
- `axum` 0.7.9 - HTTP server for SAML POST callbacks
- `clap` 4.5.60 - CLI argument parsing with derive macros

**Networking & HTTP:**
- `hyper` - HTTP client/server implementation
- `http` - HTTP types and status codes
- `tower` - Middleware and service abstractions

**Serialization:**
- `serde` - Serialization/deserialization
- `serde_json` - JSON support
- `serde_urlencoded` - Form URL encoding

**Utilities:**
- `rand` 0.8 - Random number generation (for hex string generation)
- `urlencoding` 2.x - URL encoding/decoding for SAML responses
- `tempfile` 3.x - Temporary file creation and cleanup
- `open` 5.x - Open URLs in default browser

**Async/Concurrency:**
- `async-trait` - Async trait support
- `futures-util` - Async utilities
- `pin-project-lite` - Pin projection helpers

**Error Handling & Logging:**
- `tracing` - Structured logging and diagnostics
- `anstream` - ANSI stream support for colored output

## Configuration

**Environment:**
- Runtime configuration via CLI arguments parsed by Clap
- VPN configuration files (`.conf`) stored in `./configs/` directory
- Example: `./configs/staging.conf`, `./configs/production`

**Build:**
- `Cargo.toml` - Workspace root configuration
- `aws-vpn-core/Cargo.toml` - Core library configuration
- `aws-vpn-cli/Cargo.toml` - CLI binary configuration
- Edition: Rust 2021
- Resolver: Workspace resolver v2

## Platform Requirements

**Development:**
- macOS (primary target)
- Rust 1.86.0+
- OpenVPN 2.6.19 (patched version via Homebrew formula at `Formula/openvpn-aws.rb`)
- GNU `dig` command-line tool
- AWS CLI (optional, for `aws sso login` and `aws sts get-caller-identity`)

**Runtime:**
- macOS required (target platform)
- Patched OpenVPN 2.6.19 executable
- GNU `dig` for DNS resolution
- Sudo access required for VPN connection
- AWS credentials/SSO session

**Production/Deployment:**
- Binary distribution via Homebrew tap
- Includes both Rust binary and patched OpenVPN formula

---

*Stack analysis: 2026-03-17*
