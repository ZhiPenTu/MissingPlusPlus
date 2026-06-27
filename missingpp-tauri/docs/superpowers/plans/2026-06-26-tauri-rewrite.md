# Tauri Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans.

**Goal:** 用 Tauri 2.x + React + Rust 完整重写 Missing++，保留所有现有功能，新增跨平台 + 前端热更能力。

**Architecture:** Rust shell (5-10MB) + React 19 frontend (Vite + TS + shadcn/ui + Tailwind + Zustand + React Query). Frontend C 架构 (bundled + CDN fallback). JSON file persistence with forward-compat decode.

**Tech Stack:** Rust 1.96 + Tauri 2.x + serde + chrono + uuid + tokio + reqwest + sha2 + tar + flate2. React 19 + TS 5 + Vite 5 + shadcn/ui + Tailwind 4 + Zustand 5 + @tanstack/react-query 5 + @tauri-apps/api 2.

**Spec:** `docs/superpowers/specs/2026-06-26-tauri-rewrite-design.md`

---

## Task 1: Rust 工具链 + Tauri CLI 装好
## Task 2: 项目结构 scaffold (package.json, Cargo.toml, tauri.conf.json, main.rs)
## Task 3: Rust 数据模型 (model.rs - Mood/Intensity/TriggerTag/RealityCheck/Missing)
## Task 4: Rust persistence (JSON file, atomic write)
## Task 5: Rust memory store + Tauri state
## Task 6: Tauri commands (records 全部)
## Task 7: Tauri commands (preferences + notifications + window)
## Task 8: Tauri commands (frontend updater)
## Task 9: System tray + global hotkey
## Task 10: React app scaffold (Vite + shadcn + Zustand + React Query)
## Task 11: Domain types + UI store
## Task 12: NewMissingForm view
## Task 13: HistoryList view (date group + 20 cap + load more)
## Task 14: StatisticsView (3 insight cards)
## Task 15: SettingsView (5 section)
## Task 16: 4 sub-sheets (RealityCheck / Grounding / SelfCompassion / Cooldown)
## Task 17: PopoverContent + MenuBarContent
## Task 18: Dev workflow (Dockerfile.dev + docker-compose.dev.yml)
## Task 19: Build & deploy pipeline (GitHub Actions + wrangler)
## Task 20: 迁移老 Swift records.json (文档化)
## Task 21: AGENTS.md + 最终验证

(详细 task 内容见 git history / 各 task commit message)
