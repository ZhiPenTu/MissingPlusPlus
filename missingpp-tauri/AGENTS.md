# Missing++ Tauri Rewrite — 项目级 Codex 准则

> 旧 macOS native app 准则在 `../AGENTS.md`（§1-§23），不重复。下面只追加 Tauri / Rust / React 特定规则。

## 1. 项目形态

- 全新项目 `missingpp-tauri/`：Tauri 2.x + React 19 + TypeScript + Rust 1.77+
- **Apple 平台 only**：macOS（主目标）+ iOS（v1 fallback 简化单页）
- Bundle ID: `com.tuzhipeng.MissingPlusPlus`（沿用旧 app）
- 存储（macOS）：`~/Library/Application Support/com.tuzhipeng.MissingPlusPlus/`
- 存储（iOS）：app sandbox container
- JSON file persistence（500 records 内无感），不引入 SQLite（v1）
- frontend C 架构（bundled + CDN 热更），用 Cloudflare Pages + R2 部署

**不要做**：不要给 Windows / Linux / Android 做平台支持 —— 这条已 lock 死。

## 2. 目录与职责

```
missingpp-tauri/
├── src-tauri/                       # Rust shell
│   ├── src/main.rs                  # 入口
│   ├── src/data/{model,persistence,store}.rs
│   ├── src/commands/                # Tauri commands
│   ├── src/frontend/                # C 架构 frontend updater (bundled + cache + CDN)
│   ├── src/platform/macos.rs        # menu bar / hotkey / dock
│   └── tauri.conf.json              # bundle / window / allowlist / frontendDist
├── src/                             # React frontend
│   ├── App.tsx, main.tsx, index.css
│   ├── views/                       # 3 tabs (main) + 2 tabs (popover) + settings
│   ├── sheets/                      # 4 modal sheets (RealityCheck / Grounding / SelfCompassion / Cooldown)
│   ├── ipc/{tauri,queries}.ts       # Tauri invoke + React Query
│   ├── stores/ui.ts                 # Zustand
│   └── domain/{model,phrases,cooldown,bucket}.ts
├── Dockerfile.dev + docker-compose.dev.yml  # 本地容器 dev
├── .github/workflows/deploy-frontend.yml     # push to main → CF Pages + R2
└── wrangler.toml
```

新增 / 修改文件按这个分层；持久化逻辑不要写到 `src/views/`。

## 3. 关键不变量

- **forward-compat decode**：`Missing` 已有 `decode_with_fallback` 自定义反序列化（沿用旧 Swift §22 设计）
  - `trigger_tags` 缺字段 → `[]`
  - `trigger_tags` 未知 rawValue → 过滤
  - `resolved_at` / `reality_check` 缺字段 → `None`
- **atomic write**：`Persistence::save_records` 用 temp + rename，崩溃时不会半写
- **SRI 校验**：frontend download 必须 SRI 校验，失败保留旧 cache
- **bundled fallback**：离线 / CDN 挂了用 bundled 兜底
- **JSON IPC**：所有 Tauri command 用 `Result<T, String>` 返回，前端 React Query error state 处理
- **3 层 state 分清楚**：
  - 持久（records）→ Rust store 单一真相
  - 瞬态（form / sheet / tab）→ Zustand（不沾 Rust）
  - Rust 主动 push → `tauri::Manager::emit('store:changed')` → React Query `invalidateQueries`
- **macOS 平台边界**：
  - `BaseDirectory::Resource` 找 bundle resources（runtime 拿图标必须用，CARGO_MANIFEST_DIR compile 时才有）
  - `tauri-plugin-global-shortcut` 在 Builder 注册一次，setup 里只 `on_shortcut` + `register`（重复 register 会 panic "register ⌥M"）
  - `MenuItemBuilder::with_id(...).build(&app_handle)` builder 模式（避开 `MenuItem::new` 静态 vs builder 歧义）
  - iOS 端 `target_os = "ios"` 走简化单页（没有 platform::macos），所有 macOS 路径都 `#[cfg(target_os = "macos")]` 包裹

## 4. Tauri command 命名约定

- `load_records`, `add_missing`, `mark_resolved`, `attach_reality_check`, `update_triggers`
- `delete_missing`, `clear_all_records`, `merge_records`, `replace_records`
- `get_prefs`, `set_pref`
- `check_frontend_update`, `apply_frontend_update`, `get_pending_frontend_update`
- `show_main_window`, `hide_main_window`, `show_popover`, `hide_popover`
- `post_record_notification`

全部用 snake_case，对应 Swift camelCase API 的 1:1 翻译。

## 5. 验证清单（改动后必跑）

- [ ] `cd src-tauri && cargo check` 通过
- [ ] `cargo tauri dev` 启起来，菜单栏 icon 显示
- [ ] 录一条 missing → IPC round-trip + JSON 写盘 + re-fetch
- [ ] 老 `missings.json` 直接 copy 能读
- [ ] `npm run build` 生成 `dist/`
- [ ] SRI 校验失败不会破坏 app
- [ ] macOS `cargo tauri build` 产出 `.app` + `.dmg`

## 6. 不要做（这一轮的）

- 不要把 records 存到 SQLite（v1 选 A：JSON file）
- 不要把 frontend bundle hash 存到 manifest（要 SRI hash of file，不是 version hash）
- 不要在 production 关掉 SRI 校验（防 CDN 攻破）
- 不要让前端直接读 records.json（必须走 IPC + Rust store 单一真相）
- 不要在 Rust commands 里同步阻塞超过 100ms（重 IO 用 `tokio::task::spawn_blocking`）
- 不要把 frontend cache 暴露给文件系统（用户不该手动改）
- 不要做 trigger 标签用户自定义（沿用 v1 预定义 8 个）
- 不要在 React Query cache 里存 records 超过 5 分钟（mutation 频繁，cache 容易 stale）
- 不要用 `cargo tauri dev` 启动时跑 `npm run dev`（Dockerfile.dev 跑容器，避免端口冲突）
- **不要加 Windows / Linux / Android 平台支持** —— 终极决策 Apple-only
- **不要给 iOS 端做 native UI**（v1 iOS fallback 简化单页，v2 再做 iOS-native）
- **不要给 iOS 加全局快捷键**（iOS 没有 menu bar / global hotkey 概念）
- 不要在 setup hook 里再 `app.handle().plugin(...)` 注册 plugin（plugin 必须在 Builder 注册）
