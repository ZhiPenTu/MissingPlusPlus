//! JSON file persistence (AGENTS.md §22 forward-compat)

use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;

use super::model::{Missing, MissingCompat};
use serde::de::DeserializeOwned;

const RECORDS_FILE: &str = "records.json";

/// Storage for records (and other app data) on disk.
///
/// `base_dir`:
/// - macOS: `~/Library/Application Support/com.tuzhipeng.MissingPlusPlus/`
/// - iOS: app sandbox container
pub struct Persistence {
    base_dir: PathBuf,
}

impl Persistence {
    pub fn new(base_dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(&base_dir).context("create base_dir")?;
        Ok(Self { base_dir })
    }

    pub fn base_dir(&self) -> &PathBuf {
        &self.base_dir
    }

    fn path(&self, name: &str) -> PathBuf {
        self.base_dir.join(name)
    }

    pub fn default_path() -> String { "~/Library/Application Support/MissingPlusPlus/records.json".to_string() }

    pub fn records_path(&self) -> PathBuf {
        self.path(RECORDS_FILE)
    }

    /// Load records with forward-compat decode.
    /// Old JSON missing fields → defaults. Unknown trigger rawValue → filtered.
    pub fn load_records(&self) -> Result<Vec<Missing>> {
        let path = self.records_path();
        if !path.exists() {
            return Ok(vec![]);
        }
        let json = fs::read_to_string(&path).context("read records.json")?;

        // Try forward-compat decode (filter unknown trigger rawValues)
        match serde_json::from_str::<Vec<MissingCompat>>(&json) {
            Ok(items) => Ok(items.into_iter().map(Missing::from).collect()),
            Err(_) => {
                // Fallback: try direct decode (newer format)
                match serde_json::from_str::<Vec<Missing>>(&json) {
                    Ok(items) => Ok(items),
                    Err(e) => {
                        // Backup corrupt file + start fresh
                        let backup_path = path.with_extension(format!(
                            "json.corrupt.{}",
                            chrono::Utc::now().timestamp()
                        ));
                        let _ = fs::rename(&path, &backup_path);
                        eprintln!(
                            "records.json corrupt ({}), backed up to {}",
                            e, backup_path.display()
                        );
                        Ok(vec![])
                    }
                }
            }
        }
    }

    /// Atomic save: temp file + rename.
    /// Prevents half-written files on crash.
    pub fn save_records(&self, items: &[Missing]) -> Result<()> {
        let path = self.records_path();
        let json = serde_json::to_string_pretty(items).context("serialize records")?;
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, json).context("write tmp records.json")?;
        fs::rename(&tmp, &path).context("atomic rename records.json")?;
        Ok(())
    }

    /// Generic JSON read with forward-compat fallback.
    pub fn read_json<T: DeserializeOwned>(&self, name: &str, default: T) -> Result<T> {
        let path = self.path(name);
        if !path.exists() {
            return Ok(default);
        }
        let json = fs::read_to_string(&path).context(format!("read {}", name))?;
        match serde_json::from_str(&json) {
            Ok(v) => Ok(v),
            Err(_) => Ok(default),
        }
    }

    /// Generic atomic JSON write.
    pub fn write_json<T: serde::Serialize>(&self, name: &str, value: &T) -> Result<()> {
        let path = self.path(name);
        let json = serde_json::to_string_pretty(value).context(format!("serialize {}", name))?;
        let tmp = path.with_extension("tmp");
        fs::write(&tmp, json).context(format!("write tmp {}", name))?;
        fs::rename(&tmp, &path).context(format!("atomic rename {}", name))?;
        Ok(())
    }
}
