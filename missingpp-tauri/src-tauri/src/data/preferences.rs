//! App preferences (mirrors Swift AppPreferences)
//!
//! v1.x: stored in Tauri Store plugin (UserDefaults on macOS, equivalent elsewhere).
//! For now, in-memory only — React side syncs via Tauri commands.

#[derive(Debug, Clone)]
pub struct AppPreferences {
    pub auto_prompt_reality_check: bool,
    pub auto_prompt_resolve_last: bool,
    pub notification_include_triggers: bool,
}

impl Default for AppPreferences {
    fn default() -> Self {
        Self {
            auto_prompt_reality_check: true,
            auto_prompt_resolve_last: true,
            notification_include_triggers: true,
        }
    }
}
