# Testing

## Current State

**No tests exist in this codebase.** There are no `#[test]` modules, no `tests/` directories, and no test dependencies in any `Cargo.toml`.

## Framework (Available, Not Used)

Rust's built-in test framework is available via `cargo test` but has not been employed.

## What Would Need to Be Tested

Given the codebase structure, meaningful tests would need to address:

### Unit Testable (Pure Logic)
- `aws-vpn-core/src/config.rs` — `field()` helper, `should_strip()` predicate, `load()` parsing logic
- `aws-vpn-core/src/vpn.rs` — `random_hex()` output format, `get_auth_challenge()` CRV1 parsing logic (SID extraction, URL extraction)
- `aws-vpn-cli/src/main.rs` — `resolve_config()` path resolution logic

### Integration / Subprocess Heavy (Hard to Test)
- `vpn::resolve()` — shells out to `dig`
- `vpn::get_auth_challenge()` — spawns actual `openvpn` process
- `vpn::connect()` — spawns `sudo openvpn` process
- `server::SamlServer::start()` — binds a real TCP port

### Suggested Mocking Strategy (If Tests Added)
- Extract subprocess calls behind a trait to allow injection in tests
- Or use `mockall` / test doubles for `Command`
- For `SamlServer`, integration tests could POST to `127.0.0.1:35001` directly

## CI / CD

No CI configuration found (no `.github/workflows/`, no `Makefile`, no `justfile`).

## Coverage

0% — no tests exist.
