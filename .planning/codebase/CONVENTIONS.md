# Code Conventions

## Language & Style

- **Language**: Rust (2021 edition)
- **Formatting**: Standard `rustfmt` conventions assumed (no custom config found)
- **Error handling**: `anyhow` throughout — `Result<T>` return types, `.context()` / `.with_context()` for error decoration

## Error Handling Pattern

All fallible functions return `anyhow::Result<T>`. Errors are enriched with context at the call site:

```rust
// aws-vpn-core/src/vpn.rs
Command::new("dig")
    .args(["a", "+short", hostname])
    .output()
    .context("Failed to run dig")?;
```

`bail!` macro used for early returns with custom messages:

```rust
// aws-vpn-cli/src/main.rs
bail!("Config file not found: {}", p.display());
```

## Async Pattern

- `tokio` runtime via `#[tokio::main]` on `main()` in the CLI crate
- `axum` server spawned with `tokio::spawn` in `server.rs`
- Oneshot channels (`tokio::sync::oneshot`) used for single-value async communication between server and main flow

## Subprocess Execution

External processes called via `std::process::Command` (not async):

```rust
// aws-vpn-core/src/vpn.rs
let out = Command::new(openvpn)
    .args([...])
    .output()
    .context("Failed to run openvpn")?;
```

`sudo` invoked explicitly as a subprocess rather than via privilege escalation libraries.

## Temporary Files

`tempfile::NamedTempFile` used for ephemeral credential and config files:

```rust
let mut creds = NamedTempFile::new()?;
writeln!(creds, "N/A")?;
writeln!(creds, "ACS::35001")?;
creds.flush()?;
// ... passed to subprocess, dropped (deleted) after
drop(creds);
```

## Struct Design

Simple structs with public fields — no builder pattern or getter/setter methods:

```rust
pub struct VpnConfig {
    pub host: String,
    pub port: String,
    pub protocol: String,
    pub filtered_conf: NamedTempFile,
}
```

## Logging / Output

- `println!` for user-facing status messages
- `eprintln!` for server-side / diagnostic output (notably in `server.rs`)
- No structured logging framework (`tracing`, `log`, etc.) used

## Module Organization

- Core library exposes 3 modules via `aws-vpn-core/src/lib.rs`: `config`, `server`, `vpn`
- CLI crate depends on core, uses `clap::Parser` derive macro for args
- No internal re-exports; consumers use full module paths (`aws_vpn_core::config`, etc.)

## Naming

| Construct | Convention | Example |
|-----------|-----------|---------|
| Crates | kebab-case | `aws-vpn-core` |
| Modules | snake_case | `config`, `server`, `vpn` |
| Structs | PascalCase | `SamlServer`, `AuthChallenge` |
| Functions | snake_case | `get_auth_challenge`, `random_hex` |
| Types/aliases | PascalCase | `SharedSender` |
| CLI args | kebab-case (clap) | `--openvpn`, `--aws-login` |
