use anyhow::{Context, Result};
use axum::{
    extract::{Form, State},
    routing::post,
    Router,
};
use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{Arc, Mutex},
};
use tokio::sync::oneshot;

type SharedSender = Arc<Mutex<Option<oneshot::Sender<String>>>>;

pub struct SamlServer {
    pub response_rx: oneshot::Receiver<String>,
    pub shutdown_tx: oneshot::Sender<()>,
}

impl SamlServer {
    pub async fn start() -> Result<Self> {
        let (response_tx, response_rx) = oneshot::channel::<String>();
        let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

        let shared: SharedSender = Arc::new(Mutex::new(Some(response_tx)));

        let app = Router::new()
            .route("/", post(handle_saml))
            .with_state(shared);

        let addr = SocketAddr::from(([127, 0, 0, 1], 35001));
        let listener = tokio::net::TcpListener::bind(addr)
            .await
            .context("Failed to bind SAML server on 127.0.0.1:35001")?;

        eprintln!("SAML server listening on 127.0.0.1:35001");

        tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(async {
                    let _ = shutdown_rx.await;
                })
                .await
                .ok();
        });

        Ok(Self { response_rx, shutdown_tx })
    }
}

async fn handle_saml(
    State(tx): State<SharedSender>,
    Form(form): Form<HashMap<String, String>>,
) -> &'static str {
    match form.get("SAMLResponse").filter(|s| !s.is_empty()) {
        Some(saml) => {
            if let Ok(mut guard) = tx.lock() {
                if let Some(sender) = guard.take() {
                    let _ = sender.send(saml.clone());
                }
            }
            eprintln!("Got SAMLResponse; it is now safe to close this window");
            "Got SAMLResponse field, it is now safe to close this window\n"
        }
        None => {
            eprintln!("SAMLResponse field is empty or not present");
            "Error: SAMLResponse field not found\n"
        }
    }
}
