# Missing++ Tauri Rewrite — 设计

> 日期：2026-06-26
> 状态：待 review
> 涉及范围：全新项目 `missingpp-tauri/`（Rust shell + React frontend）
> 旧 macOS native app（`MissingPlusPlus/`）保留不动，作为可对照的 baseline

## 1. 背景

当前 `Missing++` 是 macOS native app（Swift / SwiftUI / AppKit），22+ commits 累计了 3 块能力：
- **Shell**：menu bar / popover / 主窗口 / ⌥M 热键 / Dock / 通知 / 沙盒
- **Record bundle**（§22）：trigger / resolved / reality check + 3 insight 卡片 + 13 commits
- **Self-soothing bundle**（§23）：3 sub-sheet + 9 commits

架构**锁死 macOS**（SwiftUI + AppKit），无法覆盖 iOS / Windows / Linux / Android，且**每次更新都要重打包 DMG**。

这一轮用 **Tauri 2.x** 重写，5 个选型已锁死：

| Q | 答案 |
|---|---|
| Q1 前端框架 | React + TypeScript + shadcn/ui + Zustand + Tailwind |
| Q2 架构 | **C 本地默认 + 远端 fallback**（bundled + CDN 热更） |
| Q3 持久化 | **A JSON file**（沿用，500 records 内无感） |
| Q4 State | React Query（持久）+ Zustand（瞬态）+ Tauri events |
| Q5 部署 | Cloudflare Pages + R2 + manifest.json + SRI |

## 2. 目标

**所有现有功能 1:1 保留**（包括 record bundle + self-soothing bundle + 日期分组 + 20 cap + load more + 4 个 sub-button + 17 句 self-compassion + 6 条 cooldown 等所有细节），且：

- 跨 macOS / Windows / Linux / iOS / Android（Tauri 2.x 多平台）
- 前端可热更（部署新 HTML/JS 到 CDN，用户下次启动拿到新版本）
- 数据可迁移（直接复制旧 Swift app 的 `missings.json` 到 Tauri app 的 storage path）
- 离线可用（C 架构的 bundled fallback）

## 3. 非目标

- 不重做 iOS 特定 UI（iOS 端 UI 第一版先 fallback 到简化单页，后续 v2 再做 iOS-native）
- 不动旧 macOS Swift app（`MissingPlusPlus/` 完整保留，作为 baseline）
- 不引入新的 3rd-party SaaS（除 Cloudflare Pages + R2 + GitHub 之外）
- 不在 v1 做实时多设备 sync
- 不做 i18n（v1 中文 only）
- 不做 a11y 完整审计（v1 做到基本能用）
- 不重做图标 / menu bar 染色（沿用当前 PNG / SF Symbol 渲染逻辑的 Rust 等价物）

## 4. 架构

### 4.1 项目结构

```
missingpp-tauri/
├── src-tauri/                    # Rust shell
│   ├── Cargo.toml
│   ├── tauri.conf.json           # bundle / window / allowlist / frontendDist
│   ├── build.rs
│   ├── icons/                    # 现有 PNG 复制
│   └── src/
│       ├── main.rs               # 入口，setup system tray + global hotkey
│       ├── commands/             # Tauri commands (#[tauri::command])
│       │   ├── mod.rs
│       │   ├── records.rs        # load/add/mark_resolved/...
│       │   ├── preferences.rs    # app preferences
│       │   ├── notifications.rs  # post record notification
│       │   └── updater.rs        # check_frontend_update / apply_frontend_update
│       ├── data/                 # 业务逻辑 + 持久化
│       │   ├── mod.rs
│       │   ├── model.rs          # Missing / TriggerTag / RealityCheck / Mood / Intensity
│       │   ├── store.rs          # 内存 records store（替代 Swift MissingStore）
│       │   └── persistence.rs    # JSON file read/write + forward-compat
│       ├── frontend/             # frontend updater (C 架构)
│       │   ├── mod.rs
│       │   ├── manifest.rs       # Manifest schema + parser
│       │   ├── downloader.rs     # HTTPS 下载 + SRI 校验
│       │   └── installer.rs      # atomic swap bundled/cache
│       ├── platform/             # OS-specific
│       │   ├── mod.rs
│       │   ├── macos.rs          # NSStatusItem, menu bar, hotkey, dock
│       │   ├── windows.rs        # system tray
│       │   └── linux.rs          # AppIndicator
│       └── error.rs
├── src/                          # React frontend
│   ├── App.tsx
│   ├── main.tsx
│   ├── index.css
│   ├── ipc/                      # Tauri bridge
│   │   ├── tauri.ts              # invoke wrapper + listen
│   │   └── queries.ts            # React Query setup
│   ├── stores/                   # Zustand
│   │   ├── ui.ts                 # form draft / sheet / tab
│   │   └── prefs.ts              # app preferences (synced via invoke)
│   ├── views/                    # Pages
│   │   ├── PopoverContent.tsx    # 2 tab (stat / history)
│   │   ├── MenuBarContent.tsx    # 3 tab (new / stat / history)
│   │   ├── NewMissingForm.tsx
│   │   ├── HistoryList.tsx
│   │   ├── StatisticsView.tsx
│   │   └── SettingsView.tsx
│   ├── sheets/                   # Modal sheets
│   │   ├── RealityCheckSheet.tsx
│   │   ├── GroundingSheet.tsx
│   │   ├── SelfCompassionView.tsx
│   │   └── CooldownSheet.tsx
│   ├── components/               # shadcn/ui + 自定义
│   │   ├── chips/
│   │   ├── forms/
│   │   └── layout/
│   ├── domain/                   # 业务逻辑
│   │   ├── model.ts              # Missing / TriggerTag / Mood / Intensity type
│   │   ├── phrases.ts            # SelfCompassionPhrases 17 句
│   │   ├── cooldown.ts           # CooldownActivities 6 defaults
│   │   └── bucket.ts             # date grouping helpers
│   └── lib/
│       ├── utils.ts
│       └── format.ts              # relativeTime 等
├── public/
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.js
├── postcss.config.js
├── index.html
├── Dockerfile.dev                 # 本地容器跑 Vite dev server
├── docker-compose.dev.yml
├── .github/workflows/
│   └── deploy-frontend.yml        # push to main → build + upload to CF Pages/R2
├── docs/
│   └── superpowers/
│       ├── specs/2026-06-26-tauri-rewrite-design.md  (this file)
│       └── plans/2026-06-26-tauri-rewrite.md
└── README.md
```

### 4.2 Rust 数据模型（mirror Swift `Missing`）

`src-tauri/src/data/model.rs`：

```rust
use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Mood {
    Happy, Joyful, Delighted, Sad, Longing,
}

impl Mood {
    pub fn emoji(&self) -> &'static str { /* ... */ }
    pub fn label(&self) -> &'static str { /* ... */ }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum Intensity {
    None, Mild, Strong,
}

impl Intensity {
    pub fn label(&self) -> &'static str { /* ... */ }
    pub fn is_strong(&self) -> bool { matches!(self, Self::Strong) }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum TriggerTag {
    NoReply, Silent, Fight, Alone,
    SawSomething, PastMemory, Separation, Comparison,
}

impl TriggerTag {
    pub fn emoji(&self) -> &'static str { /* ... */ }
    pub fn label(&self) -> &'static str { /* ... */ }
    pub fn display_string(&self) -> String { format!("{} {}", self.emoji(), self.label()) }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct RealityCheck {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub evidence_for: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub evidence_against: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_action: Option<String>,
    pub checked_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Missing {
    pub id: Uuid,
    pub who: String,
    pub mood: Mood,
    pub intensity: Intensity,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub trigger_tags: Vec<TriggerTag>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reality_check: Option<RealityCheck>,
}
```

**forward-compat 关键点**（沿用 Swift §22 设计）：
- `trigger_tags` 缺字段 → `[]`
- `trigger_tags` 里有未知 rawValue（未来加新 case 后老数据里的旧值）→ 过滤掉
- `resolved_at` 缺字段 → `null`
- `reality_check` 缺字段 → `null`

### 4.3 Rust persistence

`src-tauri/src/data/persistence.rs`：

```rust
use std::path::PathBuf;
use std::fs;
use anyhow::{Result, Context};

const RECORDS_FILE: &str = "records.json";

pub struct Persistence {
    /// `~/Library/Application Support/MissingPlusPlus/records.json` on macOS
    /// `%APPDATA%/MissingPlusPlus/records.json` on Windows
    /// `~/.config/MissingPlusPlus/records.json` on Linux
    /// iOS: app sandbox container
    base_dir: PathBuf,
}

impl Persistence {
    pub fn new(base_dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(&base_dir).context("create base dir")?;
        Ok(Self { base_dir })
    }

    pub fn records_path(&self) -> PathBuf {
        self.base_dir.join(RECORDS_FILE)
    }

    pub fn load_records(&self) -> Result<Vec<Missing>> {
        let path = self.records_path();
        if !path.exists() {
            return Ok(vec![]);
        }
        let json = fs::read_to_string(&path).context("read records.json")?;
        let items: Vec<Missing> = serde_json::from_str(&json)
            .context("parse records.json (may be incompatible)")?;
        Ok(items)
    }

    pub fn save_records(&self, items: &[Missing]) -> Result<()> {
        let path = self.records_path();
        let json = serde_json::to_string_pretty(items).context("serialize")?;
        // atomic write: temp file + rename
        let tmp = path.with_extension("json.tmp");
        fs::write(&tmp, json).context("write tmp")?;
        fs::rename(&tmp, &path).context("atomic rename")?;
        Ok(())
    }
}
```

**关键**：用 temp + rename 实现 atomic write（避免崩溃时半写文件）。

### 4.4 Rust memory store

`src-tauri/src/data/store.rs`：

```rust
use std::sync::RwLock;
use crate::data::model::Missing;
use crate::data::persistence::Persistence;

pub struct Store {
    items: RwLock<Vec<Missing>>,
    persistence: Persistence,
}

impl Store {
    pub fn new(persistence: Persistence) -> Result<Self> {
        let items = persistence.load_records().unwrap_or_default();
        Ok(Self {
            items: RwLock::new(items),
            persistence,
        })
    }

    pub fn snapshot(&self) -> Vec<Missing> {
        let mut items = self.items.read().unwrap().clone();
        items.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        items
    }

    pub fn add(&self, item: Missing) -> Result<()> {
        { let mut items = self.items.write().unwrap(); items.push(item); }
        self.persist_and_emit()
    }

    pub fn mark_resolved(&self, id: Uuid) -> Result<()> {
        { 
            let mut items = self.items.write().unwrap();
            if let Some(item) = items.iter_mut().find(|i| i.id == id) {
                item.resolved_at = Some(Utc::now());
            }
        }
        self.persist_and_emit()
    }

    // attach_reality_check / update_triggers 类似

    fn persist_and_emit(&self) -> Result<()> {
        self.persistence.save_records(&self.items.read().unwrap())?;
        crate::emit_store_changed();
        Ok(())
    }
}
```

**Tauri State**：用 `app.manage(Store::new(...))` 注册全局，commands 通过 `State<'_, Store>` 拿到。

### 4.5 Tauri commands

`src-tauri/src/commands/records.rs`：

```rust
use tauri::State;
use crate::data::{Store, model::Missing};

#[tauri::command]
pub fn load_records(store: State<Store>) -> Vec<Missing> {
    store.snapshot()
}

#[tauri::command]
pub fn add_missing(
    store: State<Store>,
    who: String,
    mood: Mood,
    intensity: Intensity,
    trigger_tags: Vec<TriggerTag>,
) -> Result<Missing, String> {
    let item = Missing::new(who, mood, intensity, trigger_tags);
    store.add(item.clone()).map_err(|e| e.to_string())?;
    Ok(item)
}

#[tauri::command]
pub fn mark_resolved(store: State<Store>, id: Uuid) -> Result<(), String> {
    store.mark_resolved(id).map_err(|e| e.to_string())
}

// attach_reality_check / update_triggers / delete_missing / clear_all / merge / replace 类似
```

完整 command 列表（替代 Swift MissingStore + StorageService + AppPreferences）：

| Rust command | 替代 Swift |
|---|---|
| `load_records()` | `MissingStore.items` |
| `add_missing(...)` | `MissingStore.add()` |
| `mark_resolved(id)` | `MissingStore.markResolved()` |
| `attach_reality_check(id, check)` | `MissingStore.attachRealityCheck()` |
| `update_triggers(id, tags)` | `MissingStore.updateTriggers()` |
| `delete_missing(id)` | `MissingStore.delete()` |
| `clear_all_records()` | `MissingStore.clearAll()` |
| `merge_records(items)` | `MissingStore.merge()` |
| `replace_records(items)` | `MissingStore.replaceAll()` |
| `export_records()` (returns String) | `StorageService.export` |
| `import_records(json, mode)` | `StorageService.import` |
| `get_storage_path()` | `StorageService.currentURL` |
| `pick_storage_path()` | NSSavePanel |
| `reset_storage_path()` | `StorageService.resetToDefault` |
| `get_prefs()` | `AppPreferences.shared` |
| `set_pref(key, value)` | `AppPreferences.set` |
| `post_record_notification(id)` | `AppDelegate.postRecordNotification` |
| `check_frontend_update()` | (new) |
| `apply_frontend_update()` | (new) |
| `get_pending_frontend_update()` | (new) |
| `show_main_window()` | AppDelegate.showMainWindow |
| `hide_main_window()` | AppDelegate.showMainWindow(false) |
| `show_popover()` | AppDelegate.showPopover |
| `get_menu_state()` | current mood + state |

### 4.6 Tauri events

| Event | 方向 | Payload | 用途 |
|---|---|---|---|
| `store:changed` | Rust → React | `{ kind: "added"\|"updated"\|"deleted"\|"cleared" }` | React Query 失效缓存 |
| `prefs:changed` | Rust → React | `Prefs` | AppPreferences 同步 |
| `frontend:update-available` | Rust → React | `UpdateInfo` | 显示 banner |
| `frontend:update-applied` | Rust → React | `{ version: String }` | 通知用户下次启动生效 |
| `window:shown` / `window:hidden` | React → Rust | - | (optional) sync state |

### 4.7 Frontend updater (C 架构)

`src-tauri/src/frontend/manifest.rs`：

```rust
#[derive(Deserialize)]
pub struct Manifest {
    pub version: String,
    pub min_native_version: String,
    pub url: String,
    pub sri: String,
    pub size_bytes: u64,
    pub released_at: DateTime<Utc>,
    pub changelog_url: Option<String>,
}
```

`src-tauri/src/commands/updater.rs`：

```rust
#[tauri::command]
pub async fn check_frontend_update(
    state: State<FrontendState>,
) -> Result<Option<UpdateInfo>, String> {
    let manifest_url = state.config.manifest_url();
    let manifest: Manifest = reqwest::get(manifest_url).await
        .map_err(|e| e.to_string())?
        .json().await.map_err(|e| e.to_string())?;
    let current = state.current_version();
    if manifest.version > current {
        Ok(Some(UpdateInfo::from(manifest)))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn apply_frontend_update(
    state: State<FrontendState>,
) -> Result<String, String> {
    let manifest = state.fetch_manifest().await.map_err(|e| e.to_string())?;
    let bytes = download_frontend(&manifest.url, &manifest.sri).await
        .map_err(|e| e.to_string())?;
    let installed_at = install_frontend(&bytes, &manifest.version)
        .map_err(|e| e.to_string())?;
    Ok(installed_at.to_string_lossy().to_string())
}
```

`tauri.conf.json` 配置：

```json
{
  "build": {
    "frontendDist": "../dist-frontend"
  }
}
```

启动时 load priority：
1. `~/Library/.../frontend/cache/v1.0.1/` (latest cache)
2. `~/Library/.../frontend/cache/v1.0.0/` (older cache)
3. `bundled/` (shipped with app, fallback)

后台 task 启动时 check CDN，newer → download → install to cache → 下次启动用 cache。

### 4.8 React 端

`src/stores/ui.ts`：

```ts
import { create } from 'zustand'

export type Tab = 'new' | 'stats' | 'history'

interface UIState {
  pendingRealityCheck: Missing | null
  pendingGrounding: boolean
  pendingCompassion: boolean
  pendingCooldown: boolean
  showSoothingLink: boolean
  currentTab: Tab
  formDraft: {
    who: string
    mood: Mood
    intensity: Intensity
    triggers: Set<TriggerTag>
  }
  setPending: (kind: 'realityCheck' | 'grounding' | 'compassion' | 'cooldown', value: any) => void
}

export const useUI = create<UIState>((set) => ({
  pendingRealityCheck: null,
  pendingGrounding: false,
  pendingCompassion: false,
  pendingCooldown: false,
  showSoothingLink: false,
  currentTab: 'new',
  formDraft: { who: '', mood: 'happy', intensity: 'mild', triggers: new Set() },
  setPending: (kind, value) => set(/* dispatch */),
}))
```

`src/ipc/queries.ts`：

```ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'

export function useRecords() {
  const qc = useQueryClient()
  useEffect(() => {
    const unlisten = listen('store:changed', () => {
      qc.invalidateQueries({ queryKey: ['records'] })
    })
    return () => { unlisten.then(u => u()) }
  }, [qc])
  return useQuery({
    queryKey: ['records'],
    queryFn: () => invoke<Missing[]>('load_records'),
  })
}

export function useAddMissing() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input) => invoke<Missing>('add_missing', input),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['records'] }),
  })
}
```

`src/views/NewMissingForm.tsx`：

```tsx
export function NewMissingForm() {
  const { formDraft, setFormDraft } = useUI()
  const { data: latest } = useRecords()
  const addMissing = useAddMissing()

  return (
    <ScrollView>
      {showSoothingLink && <SoothingInlineLink />}
      <WhoField value={formDraft.who} onChange={v => setFormDraft({ ...formDraft, who: v })} />
      <MoodPicker value={formDraft.mood} onChange={...} />
      <IntensityPicker value={formDraft.intensity} onChange={...} />
      <TriggerPicker value={formDraft.triggers} onChange={...} />
      <SubmitButton onClick={() => {
        addMissing.mutate({ who: formDraft.who, mood: formDraft.mood, intensity: formDraft.intensity, trigger_tags: Array.from(formDraft.triggers) })
        // reset formDraft
      }} />
    </ScrollView>
  )
}
```

`src/views/HistoryList.tsx`：把 Swift `HistoryList` 1:1 翻译 + 加上 date group + 20 cap + load more。

`src/views/StatisticsView.tsx`：把 Swift `StatisticsView` 1:1 翻译 + 3 insight 卡片（WaveResolvedCard / TopTriggersCard / RealityCheckCard）。

`src/views/SettingsView.tsx`：把 Swift `SettingsView` 1:1 翻译 + 4 section（storage / statusbar / 依恋辅助 / cooldown / data / about）。

`src/sheets/RealityCheckSheet.tsx` 等 4 个 sheet：1:1 翻译 + icon-only sub-button（跟 Swift 一致）。

`src/components/FrontUpdateBanner.tsx`：监听 `frontend:update-available`，显示 banner "新版本已下载，下次启动生效"。

### 4.9 Dev workflow

`Dockerfile.dev`：

```dockerfile
FROM node:25-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
```

`docker-compose.dev.yml`：

```yaml
services:
  frontend-dev:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "5173:5173"
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      - CHOKIDAR_USEPOLLING=true
```

`src-tauri/tauri.conf.json` 在 dev 模式下指 `devUrl: "http://localhost:5173"`。

dev 命令：

```bash
docker compose -f docker-compose.dev.yml up -d
cd src-tauri && cargo tauri dev
```

### 4.10 Build & deploy pipeline

`.github/workflows/deploy-frontend.yml`：

```yaml
name: Deploy frontend
on:
  push:
    branches: [main]
jobs:
  build-deploy:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 25 }
      - run: npm ci
      - run: npm run build
      - name: Generate manifest
        run: |
          VERSION=$(date +%Y.%m.%d.%H%M)
          HASH=$(openssl dgst -sha384 -binary dist/index.html | base64)
          URL="https://app.missingpp.com/frontend/v${VERSION}.tar.gz"
          cat > dist/manifest.json <<EOF
          { "version": "$VERSION", "min_native_version": "0.1.0", "url": "$URL", "sri": "sha384-$HASH", "size_bytes": $(stat -f%z dist.tar.gz), "released_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
          EOF
      - name: Tar + upload
        run: |
          tar czf dist.tar.gz dist
          wrangler pages deploy dist --project-name missingpp
```

Manifest schema：

```json
{
  "version": "1.0.1",
  "min_native_version": "0.1.0",
  "url": "https://app.missingpp.com/frontend/v1.0.1.tar.gz",
  "sri": "sha384-AbCdEf...",
  "size_bytes": 1234567,
  "released_at": "2026-06-26T12:00:00Z",
  "changelog_url": "https://github.com/.../CHANGELOG.md"
}
```

## 5. 数据流

```
用户开 app
  ↓
Rust main()
  ├─ Persistence::new() → 拿 base_dir
  ├─ Store::new(persistence) → 内存 init
  ├─ app.manage(Store)
  ├─ setup frontend loader (bundled or cache)
  ├─ background: check_frontend_update (async)
  │   └─ newer → download → SRI 校验 → install to cache
  │       └─ emit('frontend:update-applied')  ← banner 提示
  └─ create system tray + main window + popover window
      ├─ tray click → show popover (load bundled or cache frontend)
      └─ main window click → show main window

React 启动 (vite dev 或 bundled/cache)
  ↓
App.tsx mount
  ├─ React Query 初始化
  ├─ useRecords() → invoke('load_records') → 缓存 + 显示
  ├─ listen('store:changed') → invalidateQueries
  └─ listen('frontend:update-applied') → 显示 banner

用户提交 missing
  ↓
React: addMissing.mutate({ who, mood, intensity, trigger_tags })
  ↓ (IPC)
Rust: add_missing command
  ↓
Store::add(item) → push to items → save_records (atomic) → emit('store:changed')
  ↓ (event)
React: invalidateQueries → re-fetch → UI 更新
  ↓ (if intensity == strong)
React: pendingRealityCheck = item → RealityCheckSheet 弹

用户标 resolved
  ↓
React: markResolved.mutate(id)
  ↓ (IPC)
Rust: mark_resolved(id) → items[idx].resolved_at = now → save + emit
  ↓ (event)
React: re-fetch → HistoryList 卡片显示 ✓
```

## 6. 错误处理 / 边界

- **Rust 启动时 records.json 损坏**：log error + 启动空 records（不 crash） + 备份损坏文件到 `records.json.corrupt.{timestamp}`
- **forward-compat**：trigger 未知 rawValue 过滤 + 缺字段 fallback（沿用 Swift 逻辑）
- **atomic write**：temp + rename，崩溃时不会半写
- **SRI 校验失败**：log + 保留旧 cache，不用坏版本
- **网络失败**：C 架构的 bundled fallback
- **Tauri command 异常**：返回 `Result<T, String>`，前端用 React Query 的 error state 显示
- **storage path 切换**（用户改 storage location）：Rust 端跟 Swift 一样，commands 重新 init Persistence
- **trigger enum 加新 case**：老 cache JSON 里未知 rawValue 自动过滤
- **app sandbox**（macOS / iOS）：Tauri 自动处理 entitlements

## 7. 验证清单

- [ ] `cargo tauri dev` 启动，docker compose frontend 跑起来
- [ ] `npm run build` 生成 `dist/`，Rust bundled 路径能 load
- [ ] 录一条 missing，IPC round-trip + JSON file 写盘 + re-fetch 显示
- [ ] 5 种 mood / 3 档 intensity / 8 个 trigger chip 正常
- [ ] strong intensity 自动弹 RealityCheckSheet
- [ ] mild intensity 5 秒 "想冷静一下？" inline link
- [ ] HistoryList 日期分组 + 20 cap + "加载更多…"
- [ ] StatisticsView 3 insight 卡片数字正确
- [ ] Settings 4 section（storage / statusbar / 依恋辅助 / cooldown）功能完整
- [ ] 4 个 sub-sheet (RealityCheck / Grounding / SelfCompassion / Cooldown) 正常
- [ ] 4 个 sub-button 入口（RealityCheckSheet 底 / HistoryList 卡 / NewMissingForm inline / Settings 入口）
- [ ] ⌥M 热键显隐主窗口
- [ ] menu bar icon 5 mood 染色
- [ ] notification body 含 trigger 信息
- [ ] 老 Swift `missings.json` 直接 copy 到 Tauri storage path 能读
- [ ] 部署新 frontend 到 CDN，启 app 检测到新版，下一次启动用新版
- [ ] SRI 校验失败不会破坏 app
- [ ] macOS / Windows / Linux 都能 build

## 8. 改动文件

**新增**（`missingpp-tauri/` 全新项目）：

- `src-tauri/Cargo.toml`
- `src-tauri/tauri.conf.json`
- `src-tauri/src/main.rs` + 4 个 modules（commands / data / frontend / platform / error）
- `src-tauri/src/data/{model,store,persistence}.rs`
- `src-tauri/src/commands/{records,preferences,notifications,updater}.rs`
- `src-tauri/src/frontend/{manifest,downloader,installer}.rs`
- `src-tauri/src/platform/{macos,windows,linux}.rs`
- `package.json` + `tsconfig.json` + `vite.config.ts` + `tailwind.config.js` + `index.html`
- `src/{App,main}.tsx` + `src/index.css`
- `src/ipc/{tauri,queries}.ts`
- `src/stores/{ui,prefs}.ts`
- `src/views/{PopoverContent,MenuBarContent,NewMissingForm,HistoryList,StatisticsView,SettingsView}.tsx`
- `src/sheets/{RealityCheckSheet,GroundingSheet,SelfCompassionView,CooldownSheet}.tsx`
- `src/components/{chips,forms,layout}/*` + `FrontUpdateBanner.tsx`
- `src/domain/{model,phrases,cooldown,bucket}.ts`
- `src/lib/{utils,format}.ts`
- `Dockerfile.dev` + `docker-compose.dev.yml`
- `.github/workflows/deploy-frontend.yml`
- `wrangler.toml`
- `README.md`

**不修改**（旧项目 `~/missing++/MissingPlusPlus/`）：保持不动，作为 baseline。

## 9. 「不要做」（这一轮新加）

按旧 `AGENTS.md §5.1` 已有规则继续生效，这一轮新加：

- 不要在 Rust commands 里直接 spawn UI 线程（用 `tauri::AppHandle::emit` 走 event 机制）
- 不要把 frontend bundle hash 存到 manifest 里（要 SRI hash of file，不是 version hash）
- 不要在 production 关掉 SRI 校验（防 CDN 攻破）
- 不要把 records 存到 SQLite（v1 选 A：JSON file，500 records 内无感）
- 不要在 React Query cache 里存 records 超过 5 分钟（mutation 频繁，cache 容易 stale）
- 不要给 iOS / Android 端做 native UI（v1 iOS / Android fallback 到简化单页，v2 再做）
- 不要让前端直接读 records.json（必须走 IPC + Rust store 单一真相）
- 不要在 Rust commands 里同步阻塞超过 100ms（重 IO 用 `tokio::task::spawn_blocking`）
- 不要把 frontend cache 暴露给文件系统（用户不该手动改）
- 不要做 trigger 标签用户自定义（沿用 v1 预定义 8 个）

## 10. 风险 / 备注

- **Rust 工具链装 1.5GB**（rustup + stable toolchain + cargo），首次 `cargo tauri dev` 还要下更多 deps，预留 15-30 min
- **C 架构复杂度**：bundled + cache + CDN 三层一致性，bug 难复现，要写 e2e test
- **Tauri 2.x 还在演进**：插件 API 可能小幅变化，写代码时锁版本（`tauri = "2.0"`，plugins 跟版本）
- **macOS code signing**：本地 dev 用 ad-hoc，生产分发要 Developer ID（跟旧 Swift app 一样的限制）
- **iOS / Android**：Tauri 2.x 实验性，可能要绕一些坑
- **跨平台 menu bar**：Tauri 2 的 system tray 在 macOS / Windows / Linux 都支持，但 iOS / Android 没有 menu bar 概念，v1 iOS 用简化的主窗口
- **CSS 主题**：shadcn/ui 默认是 light/dark 双主题，macOS 风格用 light，"思念计数器" pink 强调色从 Swift 直接搬
- **AGENTS.md**：旧项目 §1-§23 全部适用，新项目会单独建 `missingpp-tauri/AGENTS.md` 记录 Rust / Tauri / React 特定规则（不重复）
- **迁移路径**：用户可手动 copy `~/Library/Application Support/MissingPlusPlus/missings.json`（旧）到 `~/Library/Application Support/com.tuzhipeng.MissingPlusPlus/records.json`（新，Tauri 沙盒 container），Rust decode 1:1 兼容
- **当前 macOS app 维护**：旧 app 继续 ship 给现有用户，Tauri 版上线后逐步迁移（或者保持双版本）
