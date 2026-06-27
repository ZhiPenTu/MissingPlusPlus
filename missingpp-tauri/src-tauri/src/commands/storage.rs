//! Tauri commands: storage path management (Tauri dialog plugin)

use tauri::AppHandle;
use tauri_plugin_dialog::{DialogExt, FilePath};

/// Show a folder picker dialog. Returns the selected path (or None if cancelled).
#[tauri::command]
pub async fn pick_storage_path(app: AppHandle) -> Result<Option<String>, String> {
    let (tx, rx) = std::sync::mpsc::channel();
    app.dialog()
        .file()
        .set_title("选择新的存储位置")
        .pick_folder(move |path| {
            let _ = tx.send(path);
        });
    let path = rx.recv().map_err(|e| e.to_string())?;
    Ok(path.and_then(|p| match p {
        FilePath::Path(p) => Some(p.to_string_lossy().to_string()),
        FilePath::Url(u) => Some(u.to_string()),
    }))
}

/// Reset storage to default location (delete custom config).
#[tauri::command]
pub fn reset_storage_path() -> String {
    // For v1, default is just the platform's app data dir
    // Tauri Store plugin handles the actual reset
    "~/.config/MissingPlusPlus/records.json (or platform equivalent)".to_string()
}

/// Get current storage path.
#[tauri::command]
pub fn get_storage_path() -> String {
    crate::data::Persistence::default_path()
}
