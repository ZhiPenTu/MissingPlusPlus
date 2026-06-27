//! OS-specific platform code (menu bar tray, hotkey, etc.)

#[cfg(target_os = "macos")]
pub mod macos;
