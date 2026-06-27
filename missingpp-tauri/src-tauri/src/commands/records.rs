//! Tauri commands for records (replaces Swift MissingStore methods)

use crate::data::{Intensity, Missing, Mood, RealityCheck, Store, TriggerTag};
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub fn load_records(store: State<'_, Store>) -> Vec<Missing> {
    store.snapshot()
}

#[tauri::command]
pub fn add_missing(
    app: tauri::AppHandle,
    store: State<'_, Store>,
    prefs: State<'_, crate::data::AppPreferences>,
    who: String,
    mood: Mood,
    intensity: Intensity,
    trigger_tags: Vec<TriggerTag>,
) -> Result<Missing, String> {
    let item = Missing::new(who, mood, intensity, trigger_tags);
    store.add(item.clone()).map_err(|e| e.to_string())?;

    // Post notification (per AppPreferences)
    if prefs.notification_include_triggers || !item.trigger_tags.is_empty() {
        let _ = crate::commands::post_record_notification(
            app,
            store.clone(),
            item.id,
            prefs.notification_include_triggers,
        );
    }

    Ok(item)
}

#[tauri::command]
pub fn mark_resolved(store: State<'_, Store>, id: Uuid) -> Result<(), String> {
    store.mark_resolved(id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn attach_reality_check(
    store: State<'_, Store>,
    id: Uuid,
    check: RealityCheck,
) -> Result<(), String> {
    store
        .attach_reality_check(id, check)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn update_triggers(
    store: State<'_, Store>,
    id: Uuid,
    tags: Vec<TriggerTag>,
) -> Result<(), String> {
    store.update_triggers(id, tags).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn delete_missing(store: State<'_, Store>, id: Uuid) -> Result<(), String> {
    store.delete(id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn clear_all_records(store: State<'_, Store>) -> Result<(), String> {
    store.clear_all().map_err(|e| e.to_string())
}

#[tauri::command]
pub fn merge_records(
    store: State<'_, Store>,
    items: Vec<Missing>,
) -> Result<usize, String> {
    store.merge(items).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn replace_records(
    store: State<'_, Store>,
    items: Vec<Missing>,
) -> Result<(), String> {
    store.replace_all(items).map_err(|e| e.to_string())
}
