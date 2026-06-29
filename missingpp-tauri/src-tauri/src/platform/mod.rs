//! Apple-specific platform code (menu bar tray, hotkey, etc.)
//!
//! Scope: **macOS + iOS** (Tauri 2.x Apple). Windows / Linux / Android 已删除。
//!
//! 当前只实现 macOS（menu bar status item + ⌥M global hotkey）。
//! iOS 没有 menu bar 概念，全局快捷键在 iOS 上也不适用，所以 v1 iOS
//! 端是普通单窗口 app，没有 platform-specific 初始化代码。

#[cfg(target_os = "macos")]
pub mod macos;
