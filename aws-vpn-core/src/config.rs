use anyhow::{Context, Result};
use std::io::Write;
use std::path::Path;
use tempfile::NamedTempFile;

pub struct VpnConfig {
    pub host: String,
    pub port: String,
    pub protocol: String,
    /// Filtered copy of the .conf file; deleted when dropped.
    pub filtered_conf: NamedTempFile,
}

/// Lines whose directives we strip before passing the conf to openvpn.
/// Mirrors the grep -Ev patterns in aws-connect.sh.
fn should_strip(line: &str) -> bool {
    let l = line.trim_start();
    l.starts_with("auth-user-pass")
        || l.starts_with("auth-federate")
        || (l.starts_with("auth-retry") && l.contains("interact"))
        || l.starts_with("remote")
}

pub fn load(path: &Path) -> Result<VpnConfig> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read config: {}", path.display()))?;

    let host = field(&content, "remote", 1).context("No 'remote' directive in config")?;
    let port = field(&content, "remote", 2).context("No port in 'remote' directive")?;
    let protocol = field(&content, "proto", 1).context("No 'proto' directive in config")?;

    let filtered: String = content
        .lines()
        .filter(|l| !should_strip(l))
        .flat_map(|l| [l, "\n"])
        .collect();

    let mut tmp = NamedTempFile::new().context("Failed to create temp config file")?;
    tmp.write_all(filtered.as_bytes())?;
    tmp.flush()?;

    Ok(VpnConfig { host, port, protocol, filtered_conf: tmp })
}

fn field(content: &str, directive: &str, n: usize) -> Option<String> {
    let prefix = format!("{} ", directive);
    content
        .lines()
        .find(|l| l.trim_start().starts_with(&prefix))?
        .split_whitespace()
        .nth(n)
        .map(str::to_string)
}
