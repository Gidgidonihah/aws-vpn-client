# External Integrations

**Analysis Date:** 2026-03-17

## APIs & External Services

**AWS VPN Endpoint:**
- AWS Client VPN - SAML-authenticated VPN service
  - Protocol: OpenVPN with SAML 2.0 support
  - Communication: Custom SAML authentication challenge/response flow
  - Config files: `./configs/staging` and `./configs/production`

**AWS SSO:**
- AWS Single Sign-On identity provider (optional)
  - Used for validating AWS credentials before VPN connection
  - Command: `aws sso login`

**SAML 2.0 Identity Provider:**
- Any SAML 2.0-compatible IdP configured for AWS VPN endpoint
- Accessed via browser for interactive authentication
  - Communication pattern: Client redirects to SAML URL in browser
  - Response: POST callback containing `SAMLResponse` parameter

## Data Storage

**Databases:**
- None - This is a stateless VPN client

**File Storage:**
- Local filesystem only
- Configuration files: `./configs/*.conf` (OpenVPN config format)
- Temporary credentials files: Created via `tempfile` crate, deleted after use
  - Contains OpenVPN credentials passed to authenticated connection
  - No persistent storage of sensitive data

**Caching:**
- None

## Authentication & Identity

**Auth Provider:**
- SAML 2.0 (AWS VPN endpoint integration)

**Implementation:**
- Custom SAML authentication flow:
  1. OpenVPN connection attempt with dummy credentials triggers `AUTH_FAILED,CRV1` response
  2. CRV1 response contains SAML redirect URL
  3. User authenticates in browser against configured SAML IdP
  4. IdP redirects to local SAML server callback (127.0.0.1:35001)
  5. Application extracts `SAMLResponse` from POST form data
  6. Extracted response is URL-encoded and passed back to OpenVPN
  7. OpenVPN completes authentication with SAML response

**SAML Server Details:**
- Port: 127.0.0.1:35001 (localhost only)
- Endpoint: POST `/` - Receives SAML response form data
- Implementation: `aws-vpn-core/src/server.rs` - Axum HTTP server with graceful shutdown
- Communication pattern: Tokio oneshot channels for request/response signaling

## Monitoring & Observability

**Error Tracking:**
- None

**Logs:**
- Stderr output using Rust `eprintln!` macro
- OpenVPN command output captured and parsed
- Example: Parsing `AUTH_FAILED,CRV1` line from OpenVPN output
- No structured logging framework deployed

## CI/CD & Deployment

**Hosting:**
- Homebrew tap distribution
  - Tap: `awsvpn/aws-vpn-client`
  - Formula: Includes patched OpenVPN build and Rust binary

**CI Pipeline:**
- None detected

## Environment Configuration

**Required env vars:**
- None enforced at runtime
- AWS SSO credentials accessed via AWS CLI (if `--aws-login` flag used)

**CLI Arguments:**
- `-x, --openvpn <OPENVPN>` - Path to patched OpenVPN executable (default: "openvpn")
- `-c, --config <CONFIG>` - Path to `.conf` file (overrides config directory lookup)
- `-a, --aws-login` - Verify AWS SSO session before connecting
- `<config_name>` - Config name to load from `./configs/<name>.conf`

**Secrets location:**
- No persistent secrets storage
- Temporary credentials files created with `tempfile` crate
- Sensitive data (SAML response, session ID) passed via temporary files to OpenVPN subprocess

## Webhooks & Callbacks

**Incoming:**
- POST `http://127.0.0.1:35001/` - SAML response callback
  - Form parameter: `SAMLResponse` (URL-encoded)
  - Initiated by SAML IdP redirect after user authentication

**Outgoing:**
- OpenVPN process spawned as subprocess with command-line arguments
  - Configuration file path
  - Remote VPN endpoint (host:port)
  - Protocol (UDP/TCP)
  - Temporary credentials file containing SAML response

## External Tools Invoked

**System Commands:**
- `dig` - DNS A record resolution for random hostname subdomain (e.g., `<random>.vpn.example.com`)
  - Purpose: Converts VPN FQDN to IP address
- `openvpn` - VPN client executable (patched version)
  - Invoked twice: once for auth challenge, once for connection
- `sudo` - Privilege elevation for VPN connection
  - First invocation: `sudo -v` to ask for password upfront
  - Second invocation: `sudo openvpn` for actual connection
- `aws` - AWS CLI
  - Optional: `aws sts get-caller-identity` to check SSO session status
  - Optional: `aws sso login` to establish new SSO session

## Process Communication

**Subprocess Communication:**
- OpenVPN stdout/stderr captured and parsed for authentication challenges
- Credentials passed via temporary files (OpenvPN `--auth-user-pass` flag)
- VPN tunnel blocks main process until connection closes

**Async I/O:**
- SAML server runs in spawned Tokio task
- Waits for POST callback from browser redirect (30 second timeout)
- Shutdown triggered by channel signal after SAML response received

---

*Integration audit: 2026-03-17*
