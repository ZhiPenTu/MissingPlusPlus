//! Tauri commands: frontend updater (C architecture)

use anyhow::Context;
use serde::Serialize;
use tauri::AppHandle;

use crate::frontend::{installer, manifest};

#[derive(Debug, Clone, Serialize)]
pub struct UpdateInfo {
    pub version: String,
    pub min_native_version: String,
    pub url: String,
    pub sri: String,
}

const MANIFEST_URL: &str = "https://app.missingpp.com/frontend/manifest.json";

/// Check if a newer frontend version is available.
#[tauri::command]
pub async fn check_frontend_update() -> Result<Option<UpdateInfo>, String> {
    let resp = reqwest::get(MANIFEST_URL)
        .await
        .map_err(|e| e.to_string())?;
    let text = resp.text().await.map_err(|e| e.to_string())?;
    let m = manifest::parse(&text).map_err(|e| e.to_string())?;

    // For v1, just return the manifest (no version compare)
    // In a real impl, compare with locally-cached version
    Ok(Some(UpdateInfo {
        version: m.version,
        min_native_version: m.min_native_version,
        url: m.url,
        sri: m.sri,
    }))
}

/// Download + install the new frontend version. Returns the install path.
#[tauri::command]
pub async fn apply_frontend_update(app: AppHandle) -> Result<String, String> {
    let resp = reqwest::get(MANIFEST_URL)
        .await
        .map_err(|e| e.to_string())?;
    let text = resp.text().await.map_err(|e| e.to_string())?;
    let m = manifest::parse(&text).map_err(|e| e.to_string())?;

    let installed = installer::download_and_install(&app, &m)
        .await
        .context("install frontend")
        .map_err(|e| e.to_string())?;

    Ok(installed.to_string_lossy().to_string())
}

/// Get the current pending update (if download completed but app hasn't restarted).
#[tauri::command]
pub fn get_pending_frontend_update() -> Option<String> {
    // v1 stub - in real impl, check cache dir
    None
}
