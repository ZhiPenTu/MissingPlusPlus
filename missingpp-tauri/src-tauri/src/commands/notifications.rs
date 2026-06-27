//! Tauri commands: post record notification (with trigger info)

use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

use crate::data::{Missing, Store};

/// Post a notification when a new record is added.
/// Body: "想念 <who>　心情：<mood>　程度：<intensity>　触发：<triggers>"
/// (only includes triggers section if the user opted in via notificationIncludeTriggers)
#[tauri::command]
pub fn post_record_notification(
    app: AppHandle,
    store: tauri::State<'_, Store>,
    id: uuid::Uuid,
    include_triggers: bool,
) -> Result<(), String> {
    // Find the record
    let items = store.snapshot();
    let item = items
        .iter()
        .find(|i| i.id == id)
        .ok_or_else(|| format!("record not found: {}", id))?;

    let body = build_notification_body(item, include_triggers);

    app.notification()
        .builder()
        .title(format!("想念 {}", display_who(&item.who)))
        .body(body)
        .show()
        .map_err(|e| e.to_string())?;

    Ok(())
}

fn build_notification_body(item: &Missing, include_triggers: bool) -> String {
    let base = format!(
        "心情：{}　程度：{}",
        item.mood.label(),
        item.intensity.label()
    );
    if include_triggers && !item.trigger_tags.is_empty() {
        let strs: Vec<String> = item.trigger_tags.iter().map(|t| t.display_string()).collect();
        format!("{}　触发：{}", base, strs.join(" "))
    } else {
        base
    }
}

fn display_who(who: &str) -> String {
    if who.is_empty() { "TA".to_string() } else { who.to_string() }
}
