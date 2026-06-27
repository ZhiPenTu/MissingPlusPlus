//! macOS-specific: menu bar status item + global hotkey

use anyhow::{Context, Result};
use std::path::PathBuf;
use tauri::image::Image;
use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{App, AppHandle, Emitter, Manager, Runtime};

use crate::data::{Mood, Store};

/// Build the menu bar tray icon and attach it to the app.
pub fn setup_tray<R: Runtime>(app: &App<R>) -> Result<()> {
    let store = app.state::<Store>();
    let initial_mood = current_mood(&store);
    let icon = load_mood_icon(initial_mood)?;
    let app_handle: AppHandle<R> = app.handle().clone();

    // Build context menu items using MenuItemBuilder (avoids static vs builder ambiguity)
    let show = MenuItemBuilder::with_id("show", "打开 Missing++").enabled(true).build(&app_handle)?;
    let new = MenuItemBuilder::with_id("new", "新建").enabled(true).build(&app_handle)?;
    let stats = MenuItemBuilder::with_id("stats", "统计").enabled(true).build(&app_handle)?;
    let history = MenuItemBuilder::with_id("history", "历史").enabled(true).build(&app_handle)?;
    let quit = MenuItemBuilder::with_id("quit", "退出 Missing++").enabled(true).build(&app_handle)?;
    let sep1 = PredefinedMenuItem::separator(&app_handle)?;
    let sep2 = PredefinedMenuItem::separator(&app_handle)?;

    let menu = MenuBuilder::new(&app_handle)
        .item(&show)
        .item(&sep1)
        .item(&new)
        .item(&stats)
        .item(&history)
        .item(&sep2)
        .item(&quit)
        .build()?;

    let _tray = TrayIconBuilder::with_id("main")
        .icon(icon)
        .icon_as_template(false)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_main_window(tray.app_handle().clone());
            }
        })
        .on_menu_event(|app, event| {
            match event.id.as_ref() {
                "show" => toggle_main_window(app.clone()),
                "new" => switch_to_tab(app.clone(), "new"),
                "stats" => switch_to_tab(app.clone(), "stats"),
                "history" => switch_to_tab(app.clone(), "history"),
                "quit" => app.exit(0),
                _ => {}
            }
        })
        .build(app)
        .context("build tray icon")?;

    Ok(())
}

fn current_mood(store: &Store) -> Mood {
    store.snapshot().first().map(|m| m.mood).unwrap_or(Mood::Longing)
}

fn load_mood_icon(mood: Mood) -> Result<Image<'static>> {
    let name = match mood {
        Mood::Happy => "MenuBarIcon-happy",
        Mood::Joyful => "MenuBarIcon-joyful",
        Mood::Delighted => "MenuBarIcon-delighted",
        Mood::Sad => "MenuBarIcon-sad",
        Mood::Longing => "MenuBarIcon-longing",
    };
    let path = icon_path(name);
    Image::from_path(&path).with_context(|| format!("load icon from {:?}", path))
}

fn icon_path(name: &str) -> PathBuf {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .unwrap_or_else(|_| ".".to_string());
    PathBuf::from(manifest_dir).join("icons").join(format!("{}.png", name))
}

fn toggle_main_window<R: Runtime>(app: AppHandle<R>) {
    if let Some(window) = app.get_webview_window("main") {
        let visible = window.is_visible().unwrap_or(false);
        if visible {
            let _ = window.hide();
        } else {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}

fn switch_to_tab<R: Runtime>(app: AppHandle<R>, tab: &str) {
    toggle_main_window(app.clone());
    let _ = app.emit("tray:switch-tab", tab);
}

pub fn update_tray_icon<R: Runtime>(app: &AppHandle<R>) {
    if let Some(tray) = app.tray_by_id("main") {
        let store = app.state::<Store>();
        let mood = current_mood(&store);
        if let Ok(icon) = load_mood_icon(mood) {
            let _ = tray.set_icon(Some(icon));
            let _ = tray.set_tooltip(Some(format!("Missing++ · {}", mood.label())));
        }
    }
}

pub fn setup_global_hotkey<R: Runtime>(app: &App<R>) -> Result<()> {
    use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

    let shortcut = Shortcut::new(Some(Modifiers::ALT), Code::KeyM);

    app.handle()
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(move |app, _shortcut, event| {
                    if event.state == ShortcutState::Pressed {
                        toggle_main_window(app.clone());
                    }
                })
                .build(),
        )
        .context("register global shortcut plugin")?;

    app.global_shortcut()
        .register(shortcut)
        .context("register ⌥M")?;

    Ok(())
}

pub fn hook_window_close_to_hide<R: Runtime>(app: &App<R>) {
    use tauri::WindowEvent;
    if let Some(window) = app.get_webview_window("main") {
        let window_clone = window.clone();
        window.on_window_event(move |event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                let _ = window_clone.hide();
                api.prevent_close();
            }
        });
    }
}
