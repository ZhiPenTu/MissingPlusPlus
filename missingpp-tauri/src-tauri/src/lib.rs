//! Missing++ library — Tauri 2.x + React 19 shell
//!
//! Rust shell that wraps the React frontend. Records persisted to JSON file
//! with forward-compat decode. Frontend updateable via CDN fallback (C arch).

mod commands;
mod data;
mod error;

use tauri::Manager;

use crate::data::{Persistence, Store};
use crate::error::AppResult;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_os::init())
        .setup(|app| {
            let base_dir = storage_base_dir(app)?;
            let persistence = Persistence::new(base_dir)?;
            let store = Store::new(persistence)?;
            app.manage(store);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_records,
            commands::add_missing,
            commands::mark_resolved,
            commands::attach_reality_check,
            commands::update_triggers,
            commands::delete_missing,
            commands::clear_all_records,
            commands::merge_records,
            commands::replace_records,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn storage_base_dir(_app: &tauri::App) -> AppResult<std::path::PathBuf> {
    use tauri::path::BaseDirectory;
    let app_data_dir = _app
        .path()
        .resolve("", BaseDirectory::AppData)
        .map_err(error::AppError::Tauri)?;
    Ok(app_data_dir)
}
