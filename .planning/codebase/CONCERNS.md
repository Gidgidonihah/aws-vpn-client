# Concerns & Technical Debt

## High Priority

### No Tests
- Zero test coverage across all Rust code
- Core logic (`config.rs`, `vpn.rs`, `server.rs`) is entirely untested
- Subprocess-heavy design makes testing non-trivial without refactoring

### Hardcoded Port
- SAML server hardcoded to `127.0.0.1:35001` in `aws-vpn-core/src/server.rs:33`
- Credential file also hardcodes `ACS::35001` in `vpn.rs:47`
- Port conflict will cause a cryptic bind failure with no user-friendly message

### sudo Blindly Trusted
- `sudo -v` called at startup to cache credentials (`main.rs:37-40`)
- `sudo openvpn` called at connect time
- No fallback or explanation if sudo fails beyond anyhow error propagation

### Temp File Credential Security
- SAML response written to a `NamedTempFile` in plaintext (`vpn.rs:106-109`)
- Temp file deleted on `drop(creds)` but window exists where it's readable by other processes
- On a multi-user system this is a potential credential leak

## Medium Priority

### Legacy Files in Repo
- `aws-saml-response-server.go` — original Go implementation, kept for reference but could confuse contributors
- `aws-connect.sh` — original shell script, superseded by Rust CLI
- `aws-saml-response-server` — compiled Go binary committed to repo (should be gitignored)
- `out.log`, `tmp.sh` — debug/scratch artifacts at root

### OpenVPN Patch Tied to 2.5.1 / 2.6.19
- `openvpn-v2.5.1-aws.patch` and `Formula/openvpn-aws.rb` pinned to specific versions
- README explicitly warns: "latest supported version is 2.6.19"
- Updating to newer OpenVPN requires manual patch creation

### README Still References Go Setup
- README instructions reference `go build` and Go dependencies
- Rust rewrite is not reflected in the README setup steps
- New users following README will get confused

### dig Dependency
- `vpn::resolve()` shells out to `dig` for DNS resolution (`vpn.rs:23`)
- Not available by default on all systems; no fallback to system resolver
- Could use `trust-dns-resolver` or `hickory-dns` crate instead

## Low Priority

### No Structured Logging
- `println!` / `eprintln!` used throughout
- No log levels — no way to suppress output or increase verbosity beyond what's hardcoded
- `--verb 3` passed to openvpn but no equivalent for the Rust code itself

### SAML Timeout Not Configurable
- 30-second timeout for SAML response hardcoded in `main.rs:67`
- Slow IdPs or slow typists may hit this

### Single SAML Response Only
- `SamlServer` uses a `oneshot` channel — handles exactly one SAML POST
- No retry path if user accidentally closes browser and needs to re-authenticate

### aws_login Flag Is Optional Afterthought
- `--aws-login` flag triggers AWS SSO check only after VPN auth challenge
- Logically, AWS SSO login should happen before the VPN auth flow

## Security Notes

- The codebase does not handle credentials beyond SAML responses (no AWS keys stored)
- SAML response is transmitted only to the local openvpn process via temp file
- The SAML HTTP server (`127.0.0.1:35001`) is localhost-only — not exposed externally
- Using URL encoding (`urlencoding::encode`) correctly before passing SAML response to openvpn
