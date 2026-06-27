//! Missing++ - 焦虑型依恋人格的记录 + 自我安抚菜单栏 app
//!
//! Entry point. See `lib.rs` for actual implementation.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    missingpp_lib::run();
}
