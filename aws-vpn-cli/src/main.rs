use anyhow::{bail, Context, Result};
use aws_vpn_core::{config, server::SamlServer, vpn};
use clap::Parser;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

#[derive(Parser)]
#[command(
    name = "aws-connect",
    about = "Connect to an AWS Client VPN endpoint using SAML authentication"
)]
struct Args {
    /// Path to the patched OpenVPN executable (defaults to 'openvpn' on $PATH)
    #[arg(short = 'x', long, default_value = "openvpn")]
    openvpn: String,

    /// Path to the .conf file (overrides positional config name)
    #[arg(short = 'c', long)]
    config: Option<PathBuf>,

    /// Verify AWS SSO session before connecting, running 'aws sso login' if needed
    #[arg(short = 'a', long)]
    aws_login: bool,

    /// Config name — looks for <exe-dir>/configs/<name>.conf
    config_name: Option<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    let config_path = resolve_config(&args)?;

    println!("The VPN must be run with administrator privileges.");
    Command::new("sudo")
        .arg("-v")
        .status()
        .context("sudo -v failed")?;

    let vpn_cfg = config::load(&config_path)?;

    let saml = SamlServer::start().await?;

    let rand_prefix = vpn::random_hex(12);
    let fqdn = format!("{}.{}", rand_prefix, vpn_cfg.host);
    let server_ip = vpn::resolve(&fqdn)?;

    println!(
        "Getting SAML redirect URL from AUTH_FAILED response (host: {}:{})",
        server_ip, vpn_cfg.port
    );

    let challenge = vpn::get_auth_challenge(
        &args.openvpn,
        vpn_cfg.filtered_conf.path(),
        &vpn_cfg.protocol,
        &server_ip,
        &vpn_cfg.port,
    )?;

    println!("Opening browser for SAML authentication...");
    open::that(&challenge.url).context("Failed to open browser")?;

    println!("Waiting for SAML response (30s timeout)...");
    let saml_response = tokio::time::timeout(Duration::from_secs(30), saml.response_rx)
        .await
        .context("SAML authentication timed out")?
        .context("SAML server channel closed unexpectedly")?;

    let _ = saml.shutdown_tx.send(());

    if args.aws_login {
        ensure_aws_login()?;
    }

    println!("Connecting...");
    vpn::connect(
        &args.openvpn,
        vpn_cfg.filtered_conf.path(),
        &vpn_cfg.protocol,
        &server_ip,
        &vpn_cfg.port,
        &challenge.sid,
        &saml_response,
    )?;

    Ok(())
}

fn resolve_config(args: &Args) -> Result<PathBuf> {
    if let Some(ref p) = args.config {
        if !p.exists() {
            bail!("Config file not found: {}", p.display());
        }
        return Ok(p.clone());
    }

    let name = args
        .config_name
        .as_deref()
        .context("A config name is required (or use -c to supply a path)")?;

    let exe_dir = std::env::current_exe()?
        .parent()
        .context("Could not determine executable directory")?
        .to_path_buf();

    let path = exe_dir.join("configs").join(format!("{name}.conf"));
    if !path.exists() {
        bail!("Config file not found: {}", path.display());
    }
    Ok(path)
}

fn ensure_aws_login() -> Result<()> {
    let authenticated = Command::new("aws")
        .args(["sts", "get-caller-identity"])
        .output()
        .context("Failed to run aws sts get-caller-identity")?
        .status
        .success();

    if !authenticated {
        println!("Logging into AWS SSO...");
        Command::new("aws")
            .args(["sso", "login"])
            .status()
            .context("aws sso login failed")?;
    }

    Ok(())
}
