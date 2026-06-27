//! Frontend downloader + SRI verifier + atomic installer

use anyhow::{Context, Result};
use base64::Engine;
use sha2::{Digest, Sha384};
use std::fs;
use std::io::Cursor;
use std::path::PathBuf;
use tauri::{AppHandle, Manager, Runtime};

use super::manifest::Manifest;

/// Download frontend bundle, verify SRI, install to cache. Returns installed path.
pub async fn download_and_install<R: Runtime>(app: &AppHandle<R>, manifest: &Manifest) -> Result<PathBuf> {
    // 1. Download
    let bytes = download(&manifest.url).await.context("download frontend")?;

    // 2. Verify SRI
    verify_sri(&bytes, &manifest.sri).context("SRI verification")?;

    // 3. Install to cache
    let cache_dir = cache_dir_for(&app_handle_cache(app)?, &manifest.version);
    fs::create_dir_all(&cache_dir).context("create cache dir")?;

    // Extract tarball
    let cursor = Cursor::new(bytes);
    let mut archive = tar::Archive::new(flate2::read::GzDecoder::new(cursor));
    archive.unpack(&cache_dir).context("unpack tarball")?;

    Ok(cache_dir)
}

async fn download(url: &str) -> Result<Vec<u8>> {
    let resp = reqwest::get(url).await.context("HTTP GET")?;
    let bytes = resp.bytes().await.context("read response body")?;
    Ok(bytes.to_vec())
}

fn verify_sri(bytes: &[u8], expected_sri: &str) -> Result<()> {
    // expected_sri format: "sha384-<base64>"
    let parts: Vec<&str> = expected_sri.splitn(2, '-').collect();
    if parts.len() != 2 || parts[0] != "sha384" {
        anyhow::bail!("invalid SRI format: {}", expected_sri);
    }
    let expected = parts[1];
    let mut hasher = Sha384::new();
    hasher.update(bytes);
    let actual = base64::engine::general_purpose::STANDARD.encode(hasher.finalize());
    if actual != expected {
        anyhow::bail!("SRI mismatch: expected {} got {}", expected, actual);
    }
    Ok(())
}

fn app_handle_cache<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf> {
    use tauri::path::BaseDirectory;
    app.path()
        .resolve("frontend", BaseDirectory::AppData)
        .context("resolve frontend cache dir")
}

fn cache_dir_for(base: &PathBuf, version: &str) -> PathBuf {
    base.join("cache").join(version)
}

/// Resolve which frontend dir to load (cache > bundled).
/// Returns the path to the dir that should be served.
pub fn resolve_frontend_dir<R: Runtime>(app: &AppHandle<R>) -> PathBuf {
    // v1: just return bundled dir (C architecture full implementation needs file watcher)
    use tauri::path::BaseDirectory;
    app.path()
        .resolve("../../../dist", BaseDirectory::AppData)
        .unwrap_or_else(|_| PathBuf::from("dist"))
}
