use anyhow::{bail, Context, Result};
use rand::Rng;
use std::io::Write;
use std::path::Path;
use std::process::Command;
use tempfile::NamedTempFile;

pub struct AuthChallenge {
    pub url: String,
    /// Session ID extracted from the CRV1 line (field 7, split on ':').
    pub sid: String,
}

/// Generates `n` random bytes as a lowercase hex string.
/// Equivalent to `openssl rand -hex n`.
pub fn random_hex(n: usize) -> String {
    let mut rng = rand::thread_rng();
    (0..n).map(|_| format!("{:02x}", rng.gen::<u8>())).collect()
}

/// Resolves the first A record for `hostname` using `dig`.
pub fn resolve(hostname: &str) -> Result<String> {
    let out = Command::new("dig")
        .args(["a", "+short", hostname])
        .output()
        .context("Failed to run dig")?;

    let stdout = String::from_utf8_lossy(&out.stdout);
    stdout
        .lines()
        .find(|l| !l.is_empty())
        .map(str::to_string)
        .with_context(|| format!("dig returned no results for {hostname}"))
}

/// Runs openvpn with a dummy credential to provoke an AUTH_FAILED,CRV1 response,
/// then extracts the SAML redirect URL and session ID from that line.
pub fn get_auth_challenge(
    openvpn: &str,
    conf: &Path,
    protocol: &str,
    server: &str,
    port: &str,
) -> Result<AuthChallenge> {
    let mut creds = NamedTempFile::new()?;
    writeln!(creds, "N/A")?;
    writeln!(creds, "ACS::35001")?;
    creds.flush()?;

    let out = Command::new(openvpn)
        .args(["--config", conf.to_str().unwrap()])
        .args(["--verb", "3"])
        .args(["--proto", protocol])
        .args(["--remote", server, port])
        .arg("--auth-user-pass")
        .arg(creds.path())
        .output()
        .context("Failed to run openvpn")?;

    let combined = format!(
        "{}\n{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );

    let crv1 = combined
        .lines()
        .find(|l| l.contains("AUTH_FAILED,CRV1"))
        .with_context(|| {
            format!(
                "No AUTH_FAILED,CRV1 line in openvpn output.\nFull output:\n{combined}"
            )
        })?;

    let url = crv1
        .split("https://")
        .nth(1)
        .map(|s| format!("https://{}", s.trim()))
        .context("Could not extract SAML URL from CRV1 line")?;

    // Replicates: awk -F : '{print $7}'  (1-indexed field 7 = 0-indexed index 6)
    let parts: Vec<&str> = crv1.split(':').collect();
    let sid = parts
        .get(6)
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .context("Could not extract SID from CRV1 line")?;

    Ok(AuthChallenge { url, sid })
}

/// Runs openvpn under sudo with the SAML credentials to establish the VPN tunnel.
/// Blocks until the VPN session ends.
pub fn connect(
    openvpn: &str,
    conf: &Path,
    protocol: &str,
    server: &str,
    port: &str,
    sid: &str,
    saml_response: &str,
) -> Result<()> {
    // openvpn expects the SAML response URL-encoded, matching Go's url.QueryEscape.
    let encoded = urlencoding::encode(saml_response);

    let mut creds = NamedTempFile::new()?;
    writeln!(creds, "N/A")?;
    writeln!(creds, "CRV1::{sid}::{encoded}")?;
    creds.flush()?;

    let status = Command::new("sudo")
        .arg(openvpn)
        .args(["--config", conf.to_str().unwrap()])
        .args(["--verb", "3", "--auth-nocache", "--inactive", "3600"])
        .args(["--proto", protocol])
        .args(["--remote", server, port])
        .args(["--script-security", "2"])
        .arg("--auth-user-pass")
        .arg(creds.path())
        .status()
        .context("Failed to run sudo openvpn")?;

    // creds drops here, deleting the temp file after openvpn exits.
    drop(creds);

    if !status.success() {
        bail!("openvpn exited with {status}");
    }

    Ok(())
}
