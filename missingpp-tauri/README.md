# Missing++ (Tauri rewrite)

焦虑型依恋人格的记录 + 自我安抚菜单栏 app。Tauri 2.x + React 19 重写版。

## 与旧 Swift app 的关系

旧 macOS native app 在 `../MissingPlusPlus/`（独立 Xcode project），完整保留作为 baseline。新 Tauri 版独立维护，两边 feature 对齐。

## 技术栈

- **Rust 1.77+** shell（5-10MB native binary）
- **Tauri 2.x** + plugins（notification / store / dialog / fs / global-shortcut / os）
- **React 19** + **TypeScript 5** + **Vite 5**
- **shadcn/ui** + **Tailwind 4** + **Zustand 5** + **@tanstack/react-query 5**
- **Cloudflare Pages** + **R2** for frontend hosting

## 架构

| Q | 答案 |
|---|---|
| 框架 | React + TS + shadcn/ui + Tailwind |
| 更新架构 | **C 本地默认 + 远端 fallback**（bundled + CDN 热更） |
| 持久化 | **A JSON file**（`~/Library/Application Support/MissingPlusPlus/records.json`） |
| State | React Query（持久）+ Zustand（瞬态）+ Tauri events |
| 部署 | Cloudflare Pages + R2 + manifest.json + SRI |

## 项目结构

```
missingpp-tauri/
├── src-tauri/          # Rust shell
│   ├── src/
│   │   ├── main.rs
│   │   ├── data/{model,persistence,store}.rs
│   │   ├── commands/records.rs
│   │   └── error.rs
│   └── tauri.conf.json
├── src/                # React frontend
│   ├── views/{MenuBarContent,PopoverContent,NewMissingForm,HistoryList,StatisticsView,SettingsView}.tsx
│   ├── sheets/{RealityCheckSheet,GroundingSheet,SelfCompassionView,CooldownSheet}.tsx
│   ├── domain/{model,phrases,cooldown,bucket}.ts
│   ├── ipc/{tauri,queries}.ts
│   └── stores/ui.ts
├── Dockerfile.dev       # Vite dev in container
├── docker-compose.dev.yml
└── .github/workflows/   # CI/CD
```

## Dev workflow

```bash
# 1. Start frontend dev server in container
docker compose -f docker-compose.dev.yml up -d

# 2. Start Tauri shell (connects to localhost:5173)
cd src-tauri && cargo tauri dev
```

Tauri 会自动 reload frontend when Vite hot-reloads.

## Build

```bash
cd src-tauri && cargo tauri build
# produces .app (macOS) / .msi (Windows) / .AppImage (Linux)
```

## 从旧 Swift app 迁移数据

```bash
# macOS
cp ~/Library/Application\ Support/MissingPlusPlus/missings.json \
   ~/Library/Application\ Support/com.tuzhipeng.MissingPlusPlus/records.json
```

Rust 端 `Missing::deserialize_with_fallback` 自动处理 forward-compat（未知 trigger rawValue 过滤 + 缺字段 fallback）。

## Frontend 热更

新版本 deploy 到 Cloudflare Pages + R2（`manifest.json` + tarball），用户下次启动 app 自动下载 + 验证 SRI + 落 cache，第三次启动使用新版。bundled 兜底保证离线可用。

## Documentation

- Spec: `docs/superpowers/specs/2026-06-26-tauri-rewrite-design.md`
- Plan: `docs/superpowers/plans/2026-06-26-tauri-rewrite.md`
- AGENTS.md (in progress)
