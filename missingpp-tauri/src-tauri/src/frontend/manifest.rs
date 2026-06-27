//! Frontend manifest schema + parser (C architecture)

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Manifest {
    pub version: String,
    pub min_native_version: String,
    pub url: String,
    pub sri: String,
    #[serde(default)]
    pub released_at: String,
    #[serde(default)]
    pub changelog_url: Option<String>,
}

pub fn parse(json: &str) -> Result<Manifest> {
    serde_json::from_str(json).context("parse manifest")
}
