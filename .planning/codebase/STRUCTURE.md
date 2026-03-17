# Codebase Structure

## Overview

Cargo workspace with two crates: a library (`aws-vpn-core`) and a CLI binary (`aws-vpn-cli`). Legacy artifacts from the original Go/shell implementation remain.

## Directory Layout

```
aws-vpn-client/
├── Cargo.toml                    # Workspace root (members: aws-vpn-core, aws-vpn-cli)
├── Cargo.lock
├── aws-vpn-core/                 # Library crate — all business logic
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs                # Module declarations (config, server, vpn)
│       ├── config.rs             # OpenVPN config parsing + temp file filtering
│       ├── server.rs             # Axum-based SAML HTTP server
│       └── vpn.rs                # OpenVPN subprocess control, auth challenge
├── aws-vpn-cli/                  # Binary crate — CLI entry point
│   ├── Cargo.toml
│   └── src/
│       └── main.rs               # Arg parsing (clap), orchestrates the auth flow
├── configs/                      # OpenVPN .conf files (gitignored content likely)
│   ├── example.conf
│   ├── prod.conf
│   ├── stag.conf
│   ├── staging/
│   └── production/
├── Formula/
│   └── openvpn-aws.rb            # Homebrew formula for patched OpenVPN
├── openvpn-v2.5.1-aws.patch      # OpenVPN patch for AWS SAML auth
├── aws-connect.sh                # Legacy shell script (superseded by Rust CLI)
├── aws-saml-response-server.go   # Legacy Go SAML server (superseded by server.rs)
├── aws-saml-response-server      # Compiled Go binary (should be gitignored)
├── README.md
├── ChangeLog.md
├── LICENSE
└── .planning/                    # GSD planning artifacts
```

## Key Locations

| What | Where |
|------|-------|
| CLI entry point | `aws-vpn-cli/src/main.rs` |
| Auth flow orchestration | `aws-vpn-cli/src/main.rs:main()` |
| SAML HTTP server | `aws-vpn-core/src/server.rs` |
| OpenVPN subprocess calls | `aws-vpn-core/src/vpn.rs` |
| Config parsing | `aws-vpn-core/src/config.rs` |
| OpenVPN patch | `openvpn-v2.5.1-aws.patch` |
| Homebrew formula | `Formula/openvpn-aws.rb` |
| VPN configs | `configs/` |

## Naming Conventions

- **Crates**: `aws-vpn-{role}` (kebab-case)
- **Modules**: snake_case matching their domain (`config`, `server`, `vpn`)
- **Structs**: PascalCase (`VpnConfig`, `SamlServer`, `AuthChallenge`)
- **Functions**: snake_case (`load`, `get_auth_challenge`, `connect`)
- **Config files**: `<name>.conf` in `configs/`

## Notable Observations

- `aws-saml-response-server` (compiled Go binary) and `tmp.sh` should likely be in `.gitignore`
- `out.log` present at root — likely debug artifact, not version-controlled
- Legacy Go/shell files (`aws-connect.sh`, `aws-saml-response-server.go`) kept for reference but no longer part of the active implementation
- `plan.md` at root is a planning scratch file
