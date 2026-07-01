# 心安日记 (MissingPlusPlus) 项目级 Codex 准则

> 本文件只追加项目级约束；全局 `Codex 行为准则`（来自 Codex 配置）依然有效，下面不重复通用规则。
>
> 维护原则: 改动最小 + 准确; 跟代码/spec 偏离时先核对再改; 不外移到 docs/ 除非用户明确要求。

## 目录

1. [项目形态](#1-项目形态)
2. [目录与职责](#2-目录与职责)
3. [关键运行时不变量](#3-关键运行时不变量)
4. [验证清单](#4-验证清单改动后必须跑过)
5. [不要做](#5-不要做)
6. [架构总览](#6-架构总览)
7. [打包](#7-打包)
8. [图标 + Asset Catalog](#8-图标--asset-catalog)
9. [Developer ID 签名 + 公证](#9-developer-id-签名--公证)
10. [Menu Bar Icon 路线与坑](#10-menu-bar-icon-路线与坑)
11. [弹窗 / 主窗口 UI 设计](#11-弹窗--主窗口-ui-设计)
12. [Dock + entitlements](#12-dock--entitlements)
13. [Settings 布局修复](#13-settings-布局修复)
14. [AI 返回 <think> 推理块 bug 修复](#14-ai-返回-think-推理块-bug-修复)
15. [数据导入 / 导出 + iCloud 同步 + 自定义存储路径](#15-数据导入--导出--icloud-同步--自定义存储路径)
16. [Anxious Attachment Record Bundle (v1.x)](#16-anxious-attachment-record-bundlev1x)
17. [Self-Soothing Bundle (v1.x 第二轮)](#17-self-soothing-bundlev1x-第二轮)
18. [通知 / 统计 / 搜索 / 替代 App Icon](#18-通知--统计--搜索--替代-app-icon)
19. [Trend chart + 自动褪色 + Sparkle 脚手架](#19-trend-chart--自动褪色--sparkle-脚手架)
20. [AI 增强 (OpenAI 兼容 endpoint)](#20-ai-增强-openai-兼容-endpoint)
21. [AppDelegate 重构 (Phase 1-7)](#21-appdelegate-重构phase-1-7)
22. [测试 + shell 入口 (Phase 8-10)](#22-测试--shell-入口phase-8-10)
23. [CI / Release workflow](#23-ci--release-workflow)
24. [Worth Affirmation Bundle (v1.x §24)](#24-worth-affirmation-bundlev1x-§24)

> §23 是 GitHub/CI 基础设施 (详细见 [`docs/ci.md`](docs/ci.md)), 本机未推 GitHub 时可跳过; 其余章节都跟当前代码行为强相关.

## 1. 项目形态

- macOS 菜单栏（Menu Bar）App，中文产品名 **心安日记** (CFBundleDisplayName)。代码名沿用 `MissingPlusPlus` (CFBundleName / Bundle ID / 文件系统路径, 不动 — 改这个会丢用户数据)。
- Bundle ID：`com.tuzhipeng.MissingPlusPlus`；Swift `5.0`；`MACOSX_DEPLOYMENT_TARGET` 见 Xcode 工程（工程里同时存在 `13.0` 与 `26.0` 两个值，按实际 target 配置为准）。
- `Info.plist` 中 `LSUIElement = false`（**有** Dock 图标 + 完整 app menu；详见 §12 "Dock + entitlements"）。
- `MissingPlusPlus.entitlements` 已开启 App Sandbox（`app-sandbox` + `files.user-selected.read-write` + `network.client`），并为 Xcode 26 显式写 `com.apple.security.get-task-allow = true`（见 §12 §29）。

## 2. 目录与职责

所有 Swift 源码集中在 `MissingPlusPlus/` 下，Xcode 工程在 `MissingPlusPlus.xcodeproj/`，测试在 `MissingPlusPlusTests/`，脚本在 `scripts/`。

```
MissingPlusPlus/
├── MissingPlusPlusApp.swift            # SwiftUI App 入口 + AppDelegate (123 行, 纯 wiring 层)
├── MissingPlusPlus.entitlements
├── Info.plist
├── Assets.xcassets/
├── Resources/                          # PNG / icns 资源
├── Models/                             # Missing / Mood / Intensity / TriggerTag / CooldownActivities
├── Views/                              # MenuBarContent / NewMissingForm / HistoryList / SettingsView / StatisticsView / RealityCheckSheet / CooldownSheet / GroundingSheet / SelfCompassionView / LetterToThemView / ...
├── StatusBar/                          # 状态栏入口
│   ├── StatusItemPanel.swift            #   NSPanel 浮动 button (macOS 26 替代 NSStatusItem)
│   ├── StatusItemProvider.swift         #   NSStatusItem 抽象 (读 NSPanel/系统状态栏 screen 位置)
│   ├── MenuBuilder.swift                #   NSMenu 树 (5 mood × 5 who × 3 intensity) + MenuActionRouter
│   └── StatusPanelController.swift      #   装/卸 + click + 拖动 + icon 联动 (Phase 6 抽出)
├── Windows/                            # 窗口管理
│   └── WindowController.swift           #   主窗口 + 设置窗口 NSWindow 生命周期 (Phase 2 抽出)
├── Services/                           # 业务服务
│   ├── MissingStore.swift               #   数据层 (@MainActor ObservableObject, UserDefaults 持久化)
│   ├── AppPreferences.swift             #   用户设置 (showStatusItem / AI endpoint / ...)
│   ├── StorageService.swift             #   存储路径 / iCloud 同步
│   ├── AIService.swift                  #   OpenAI 兼容 chat client + 3 个 content generator
│   ├── KeychainService.swift            #   API key 安全存储
│   ├── MenuBarIconRenderer.swift        #   状态栏图标渲染 (heart/emoji/思字 × 5 mood 染色)
│   ├── NotificationService.swift        #   UNUserNotificationCenter 投递 (Phase 4 抽出, shared singleton)
│   ├── HotKeyController.swift           #   Carbon ⌥M 全局热键 (Phase 5 抽出)
│   └── ActiveStateController.swift      #   app 激活兜底拉主窗口 (Phase 7 抽出)
MissingPlusPlusTests/                   # 35 个 XCTest, 6 个 controller 全覆盖
├── ActiveStateControllerTests.swift    #   4 tests
├── HotKeyControllerTests.swift          #   7 tests
├── MenuBuilderTests.swift               #   6 tests
├── NotificationServiceTests.swift       #   8 tests
├── StatusPanelControllerTests.swift     #   6 tests
└── WindowControllerTests.swift          #   4 tests

scripts/                                 # shell-first 入口 (按 build-run-debug skill 约定)
├── build-dmg.sh                         #   DMG 打包 (ad-hoc / Developer ID)
├── build_and_run.sh                     #   kill + Debug/Release build + launch (Phase 9)
├── run_tests.sh                         #   xcodebuild test (Phase 9)
├── build-with-sparkle.sh                #   Sparkle 脚手架 (未实跑)
├── make-icons.py                        #   图标 + 菜单栏 PNG 生成
└── patch-pbxproj.py                     #   pbxproj 资源注册 (idempotent)
```

**新增文件请维持以上分层**：
- 持久化逻辑不写到 `Views/`
- 新 controller / service 放对应 `StatusBar/` `Windows/` `Services/` 目录
- 测试放 `MissingPlusPlusTests/`，文件名 `<ControllerName>Tests.swift`

## 3. 关键运行时不变量

- **持久化路径**：`~/Library/Application Support/MissingPlusPlus/missings.json`，位于 App Sandbox 容器内。任何导出 / 备份请走 `NSSavePanel`（命中 `files.user-selected.read-write`），不要直接写 `Documents` / `Downloads`。
- **状态栏图标**：当前是 `StatusItemPanel` (NSPanel) + `MenuBarIconRenderer.image(mood:style:)`。详见 §6 架构总览 + §10 Menu Bar Icon 调试历史。
- **全局快捷键**：`kVK_ANSI_M` + `optionKey`（⌥M），EventHotKey 签名 `0x4D53504D`（`MSPM`）。Carbon 回调里只 `DispatchQueue.main.async` 派发，不要在回调里直接改 UI / `AppKit` 状态。
- **窗口复用**：`MenuBarContent` (主窗口) + `SettingsView` (设置) 装在 NSWindow + NSHostingController 里，主窗口用 `setFrameAutosaveName("MainWindow")` 记忆位置 —— SwiftUI 侧不要重复存 frame。
- **数据兼容**：`Missing` / `Mood` / `Intensity` 用 `Codable` 默认策略，`JSONDecoder` 没有自定义 `dateDecodingStrategy`。改字段前评估对老 `missings.json` 的兼容。
- **UI 文案**：中文 label 和 emoji 是产品的一部分，不要本地化或替换成 SF Symbol 占位。

## 4. 验证清单（改动后必须跑过）

- [ ] `./scripts/build_and_run.sh` 通过（Debug build 成功 + .app 启动 + Dock 出现图标）。
- [ ] `./scripts/run_tests.sh` → `** TEST SUCCEEDED **`，34/34 tests pass。
- [ ] 启动后状态栏出现 icon，控制台能看到 `[MissingPlusPlus] final: visible=1` (log prefix 是代码名 MissingPlusPlus, 不是产品名)。
- [ ] 提交一条记录 → 完全退出 App → 重新打开，历史仍然存在。
- [ ] 状态栏点击 = 弹 1-click 记录菜单；⌥M = 主窗口显隐切换；Dock click = 主窗口。
- [ ] 删除 `missings.json` 后启动 App，列表走 `emptyState`（"还没有记录 / 想念的时候就来记一笔"）。
- [ ] `LSUIElement = false`（Dock icon 在），改回 `true` 会丢 Dock icon（见 §12）。

## 5. 不要做

- 不要绕过 `MissingStore` 直接改 `items`。
- 不要在 SwiftUI 视图里发网络请求或启动后台任务 —— 当前是完全离线的单进程菜单栏 App。
- 不要新增 XCTest / UI 测试 target，`MissingPlusPlusTests/` 已经在了，加文件即可。
- 不要引入 Swift Package / CocoaPods / Carthage 依赖，除非用户明确要求。
- 不要在没和用户确认的情况下改 `Info.plist` / `entitlements` / 部署目标。
- 不要在 macOS 上尝试 `NSStatusItem.button` 重赋 / KVC 设值：read-only 走的是私有 selector，应用升级后会炸。我们用 NSPanel (`StatusItemPanel`) 路线，详见 §10。
- 不要在 popover action 同一 tick 同步调 `showPopover()`：NSPopover 在菜单栏点击时会"闪一下就关"。`DispatchQueue.main.async` 推到下一个 runloop tick。
- 不要在 `MissingStore.add` 里直接调用 UI 更新（`NSLog` / `button.image =`）：store 可能在 main-actor 之外被调用，UI 更新要走 `NotificationCenter` 在 controller（@MainActor 范围内）接。
- 不要让 `NotificationService.postRecordNotification` 在测试里被多次调用 —— UNUserNotificationCenter 是 process singleton，重复发会真在通知中心刷屏。测 `makeMoodAttachment` / `titleForMissing` 静态方法即可。
- 不要在 `MenuBarContent` 里塞 submit 按钮的"替代品"（⌘R / 悬浮 + 等）—— 用户主动 popover 是为了 peek，要 act 就去 Dock 窗口。

## 6. 架构总览

AppDelegate 现在是**纯 wiring 层**（123 行），创建 4 个 controller + 调 1 个 service。
所有 OS-level 副作用（NSWindow / Carbon / NSPanel / UNUserNotificationCenter）都封在 controller / service 里。

```
MissingPlusPlusApp
    ├── Settings { SettingsView }     ← SwiftUI scene, ⌘, 触发 .openSettings
    └── .commands { about / quit }    ← CommandGroup

AppDelegate
    │
    ├── applicationDidFinishLaunching
    │     ├── new WindowController()                  // init 即订阅 .openSettings
    │     ├── new StatusPanelController(...)          // init 即订阅 prefs / 屏幕参数 / missingStoreDidAdd
    │     ├── new HotKeyController(spec: .optionM)   // init 即注册 Carbon EventHotKey
    │     ├── new ActiveStateController(...)          // init 即订阅 didBecomeActiveNotification
    │     └── NotificationCenter: 订阅 .missingStoreDidAdd → handleMissingAdded
    │
    ├── 转发 entry point:
    │     ├── applicationShouldHandleReopen → WindowController.showMainWindow
    │     ├── ⌥M Carbon callback         → WindowController.showMainWindow
    │     ├── app activation             → WindowController.showMainWindow (via ActiveStateController)
    │     └── .openSettings              → WindowController.handleOpenSettings
    │
    └── handleMissingAdded → NotificationService.shared.postRecordNotification
```

### 4 个 controller（每 AppDelegate 一份，不是单例）

| Controller | 文件 | 职责 |
|---|---|---|
| `WindowController` | `Windows/WindowController.swift` | 主窗口 + 设置窗口 NSWindow 生命周期，`setFrameAutosaveName` 持久化 frame |
| `StatusPanelController` | `StatusBar/StatusPanelController.swift` | 状态栏 NSPanel 装/卸 + click + 拖动 + icon mood 联动 |
| `HotKeyController` | `Services/HotKeyController.swift` | Carbon ⌥M 全局热键，`Box<T>` 包装 closure 避免 `unsafeBitCast` 强转 self |
| `ActiveStateController` | `Services/ActiveStateController.swift` | app 激活兜底拉主窗口，debounce 0.5s + delay 0.3s |

### 1 个 service（`shared` 单例）

| Service | 文件 | 职责 |
|---|---|---|
| `NotificationService.shared` | `Services/NotificationService.swift` | 新记录 → UNUserNotificationCenter，AI body + mood attachment（sandbox 跨容器 attach 修复） |

### 数据流

```
状态栏 panel click ──► StatusPanelController.statusPanelClicked
                          ├─ new MenuBuilder + popUp
                          │   ├─ onRecord ──► AppDelegate closure ──► MissingStore.shared.add
                          │   ├─ onOpenMain ► AppDelegate closure ──► WindowController.showMainWindow
                          │   └─ onQuit ───► NSApp.terminate
                          └─ statusMenu 强引用 NSMenu (popUp 期间)

Dock click / ⌥M ──────► AppDelegate ──► WindowController.showMainWindow
.app activation ──────► ActiveStateController ──► WindowController.showMainWindow

MissingStore.add ──► post .missingStoreDidAdd
                       │
                       ├─ StatusPanelController 听 → updateIcon（mood 联动）
                       └─ AppDelegate 听 → NotificationService.shared.postRecordNotification
```

### 关键不变量

- AppDelegate **不持** 任何 window / panel / hotkey ref —— 都在 controller 里
- AppDelegate **不持** 任何持久化 state —— 都走 singleton（`MissingStore` / `AppPreferences`）
- controllers 之间**不互相引用** —— 都通过 AppDelegate 的 closure 注入 + `NotificationCenter` 派发


## 7. 打包

- 脚本：`scripts/build-dmg.sh`（xcodebuild Release → ad-hoc 重新签名 → stage → `hdiutil create -format UDZO` → verify + mount smoke test）。
- 输出：`dist/MissingPlusPlus-1.0.dmg`。
- **关键注意点**：
  - Xcode 26 构建时 Swift 6 stdlib 不再打进 `.app`，所以本 DMG **只能在 macOS 26+ 上运行**。如果要让 13/14/15 跑，需要在工程里加 `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES` 并重新打包。
  - 当前使用 **ad-hoc 签名**（`codesign -s -`），目的是在没有 Developer ID 的情况下也能在本地双击安装。要正式分发给其他 Mac 用户，需要切到 Developer ID 签名 + `notarytool` 公证。
  - 工程里 `MACOSX_DEPLOYMENT_TARGET` 存在 13.0 和 26.0 两个值，Release 实际按 26.0 出包，Debug 按 13.0；这是工程层面的不一致，未来要么统一，要么按意图把 13.0 那个改掉。

## 8. 图标 + Asset Catalog

### AppIcon

- 应用图标（`MissingPlusPlus/Resources/AppIcon.icns`）：1024×1024 master 渲染后降采样到 16/32/64/128/256/512/1024 的 1x/2x 全套，再 `iconutil -c icns` 打包；通过 `Info.plist` 的 `CFBundleIconName = AppIcon` 指向 asset catalog。
- 5 个 mood 替代 AppIcon：`MissingPlusPlus/Resources/AppIcon-{mood}.icns` —— 用 mood 调色板染色，存在 bundle 里，未来想运行时切换可用 `setAlternateIconName`（macOS 没有公开 API 但 iOS 有）。

### 5 mood 菜单栏 PNG

- 生成在 `MissingPlusPlus/Resources/MenuBarIcon-{mood}-{1x,2x,3x}.png`（22/44/66 三档）。
- 调色（`make-icons.py` 里的 `MOOD_PALETTE`）：
  - happy: 暖金 → 橙 (`#FFC857` → `#FF9F43`)
  - joyful: 草绿 (`#6EDC82` → `#34BB64`)
  - delighted: 玫红 → 珊瑚 (`#E91E63` → `#FF6982`)
  - sad: 钢蓝 (`#5B7A99` → `#426082`)
  - longing: 薰衣草紫 (`#9B72CF` → `#7B54AF`)

### Asset Catalog

- `AppIcon.icns` 已经被 `MissingPlusPlus/Resources/Assets.xcassets/AppIcon.appiconset/` 取代。`Info.plist` 用 `CFBundleIconName = AppIcon` 指向 asset catalog，不再有 `CFBundleIconFile`。
- 编译产物是 `Assets.car`（≈200KB）+ `AppIcon.icns`（≈30KB），都在 `.app/Contents/Resources/`。

## 9. Developer ID 签名 + 公证

- 脚本：`scripts/build-dmg.sh`，默认 ad-hoc。设置 `DEVELOPER_ID=1` 进 Developer ID 模式：手动 `CODE_SIGN_IDENTITY=Developer ID Application` 签名、`xcrun notarytool submit` 提交、`xcrun stapler staple` 钉回 ticket。
- 走 Developer ID 模式前需要：
  1. 加入 Apple Developer Program（$99/年）。
  2. Xcode → Settings → Accounts → Manage Certificates 里签发 `Developer ID Application` 证书。
  3. `https://appleid.apple.com` 申请一个 **app-specific password**。
  4. 跑 `xcrun notarytool store-credentials <profile> --apple-id <you> --team-id <TEAMID> --password <app-pw>` 存到 keychain（profile 名默认 `missingpp-notary`，可通过 `NOTARY_PROFILE` 覆盖）。
  5. 准备好后 `DEVELOPER_ID=1 DEVELOPMENT_TEAM=<TEAMID> bash scripts/build-dmg.sh` 跑一遍，会自动签名 + 公证 + 钉 ticket。
- 当前你只有 Apple Development 证书，没有 Developer ID，所以这条线还没实跑过；脚手架是 ready 的。

## 10. Menu Bar Icon 路线与坑

**当前路线**: `StatusItemPanel` (NSPanel 子类, 22x22 浮动 button, `level=.statusBar` / `nonactivatingPanel` / `canJoinAllSpaces`) + `MenuBarIconRenderer.image(mood:style:)` (style 可选 `heart` / `emoji` / `思字`).

macOS 26 上 `NSStatusItem` 默认进 Control Center 弹窗辅助区, 屏幕顶部菜单栏看不到 — 改用 NSPanel 路线绕开. 历史 6 轮调试 (NSImage sizing / emoji 字体 / "思" 字兜底等) 见 `git log -- AGENTS.md` 老 commit.

### 不要做

- 不要用 `Bundle.main.image(forResource:)` 给 status bar button 设图, 除非先 `image.size = NSSize(width: logicalWidth, height: logicalHeight)` 并确认 PNG 是 1x/2x/3x retina-correct.
- 不要在 menu bar button 上用 `imageScaling = .scaleProportionallyDown` / `.scaleToFit`, 让 AppKit 用默认行为.
- 不要用 `NSFont.systemFont(ofSize:)` 给 `NSStatusBarButton` 显示 emoji, 要么显式 `NSFont(name: "AppleColorEmoji", size:)`, 要么用 `attributedTitle` + `kCTFontAttributeName` 指定 AppleColorEmoji.
- 不要看到 `NSLog("[...] visible=true")` 就以为菜单栏图标可见; Cocoa 渲染 emoji 失败是 silent failure.

## 11. 弹窗 / 主窗口 UI 设计

### §16 弹窗 UI 重设计

**之前的问题**（你截图反馈"界面设计的不好看"）：表单里 6 个 item（pill + header + 对象 + 心情 + 程度 + button）用 `VStack(spacing: 10)` 包，整个 popover 720pt 高但表单只占 ~400pt，剩 300+ pt 是空 —— 表单自然落到 popover **底部**，上半拉一片空白，pill 跑到了 y=600 那种离谱位置。

**重做后的结构**（`NewMissingForm`）：header 渐变 pink 背景 + ScrollView 包表单 + 按钮固定底部 `.borderedProminent` + `.tint(.pink)`，永远 enabled。`canSubmit` 不再因为 `who` 是空就 disable —— 空 `who` 自动 fallback 到 `"TA"`，按钮文案变成"记录（未指定对象）"。

**关键改动**：
1. header 拉到顶部（渐变 pink 0.10 → 0.02 alpha）+ 圆形 avatar + 标题 + 副标题
2. ScrollView 包表单 —— 表单能滚，操作按钮不挤出去
3. 按钮固定在底部，永远 visible / always enabled
4. **不要把表单用 `VStack` 直接放进固定高度的 popover 不带 ScrollView** —— 内容短就剩大空白，内容长就把按钮挤出去

### §20 Dock 真窗口 vs 状态栏 popover（双入口 UI 分开）

**之前的问题**（你"重新分开两种 entry 的 UI"）：状态栏点开的是 `MenuBarContent`（含 `NewMissingForm` submit 按钮），Dock 点开的是 `NSWindow` 包同一个 `MenuBarContent`。两边 UI 一模一样，违背了"popover 是 peek / Dock window 是 act"的产品语义。

**当前架构**（已演化为统一 `MenuBarContent` —— 状态栏改 NSMenu 1-click 记录，§20 的 PopoverContent 思路被废止）：
- 状态栏入口：`StatusPanelController.statusPanelClicked` → new `MenuBuilder` + popUp（5 mood × 5 who × 3 intensity，零表单）
- Dock 入口：`WindowController.showMainWindow` → `MenuBarContent` 完整 3-tab（新建 / 统计 / 历史）+ submit 按钮
- `MenuBarContent` 在 popover path 下不再出现（popover 整个被 NSMenu 替代了）

**当前代码里没有 `PopoverContent` 这个文件** —— 它在 commit `8569ae5 refactor(ui): remove PopoverContent` 被删了。如果未来要重新做 popover 路径，参考这个 commit 的 "之前" 版本。

### §17 Dock + 状态栏双入口（part of）

`Info.plist` 的 `LSUIElement` 改 `false` → app 启动是 .regular policy，天然有 Dock icon + 完整 app menu + Spotlight 标准 app 名。详见 §12。

## 12. Dock + entitlements（合并 §17 + §27 + §29）

### §17 Dock + 状态栏双入口

1. `LSUIElement` 从 `true` 改 `false` —— app 现在有 Dock 图标和标准 app menu。
2. `MissingPlusPlusApp.applicationDidFinishLaunching` 里更新注释：旧"**不要**调 `setActivationPolicy(.regular)` — macOS 26 上把 NSStatusItem 路由到 Control Center scene" 这条警告**不适用**当前架构。我们用的是 NSPanel (`StatusItemPanel`) 不是 NSStatusItem，不受 LSUIElement / activation policy routing 影响。
3. **不要在 LSUIElement=false 后再显式调 `setActivationPolicy(.regular)`** —— 改 Info.plist 已经让 app 启动是 .regular，显式再调一次会触发 macOS 26 那个 "NSStatusItem 被路由到 Control Center scene" 的 bug（虽然我们用 NSPanel 不受影响，但保持代码干净）。

### §27 LSUIElement=false — Dock icon 显示

**需求**（用户报告："打开主窗口时，希望在 dock 栏也能显示出来"）：之前 `Info.plist` 里 `LSUIElement=true` 让 app 以 .accessory policy 启动，没有 Dock icon，app menu 也是隐藏的。

**修法** (`Info.plist` + `MissingPlusPlusApp.swift`)：
1. `Info.plist` 的 `LSUIElement` 改 `false` → app 启动是 .regular policy，天然有 Dock icon + 完整 app menu + Spotlight 标准 app 名，**不需要显式 `setActivationPolicy(.regular)`**。
2. `applicationDidFinishLaunching` 注释：旧警告**不适用**当前 NSPanel 架构。

**验证 (lsappinfo info + osascript dock 列表)**：
```
flavor=3  (regular policy)
lsappinfo list: "MissingPlusPlus" ASN:0x0-0x3123120  bundleID=com.tuzhipeng.MissingPlusPlus
osascript dock 列表: 访达, App, ..., Codex, MissingPlusPlus, missing value, 下载, 废纸篓
status panel: (1018, 6) 22x22  ← 菜单栏还在
主窗口: 心安日记 360x752
```

### §29 Xcode 26 entitlements "modified during build" 修复

**症状**：Xcode GUI build 报
> Entitlements file "MissingPlusPlus.entitlements" was modified during the build, which is not supported.

Xcode 26 在 Debug build 时自动往 entitlements 注入 `get-task-allow=true`，写完的 `.app.xcent` 跟 source 出现 mtime 差就报错。

**修法**：
1. `project.pbxproj` Debug + Release 两个 build configuration 都加 `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION = YES`，永久生效。
2. `MissingPlusPlus.entitlements` source 加 `com.apple.security.get-task-allow=true`，让 Xcode 26 看到 source 已经有这个 key 就跳过 inject。

**不要做**：
- pbxproj 只加 `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION` 不加 source `get-task-allow` —— Xcode 26 还是会试图 inject 然后 mtime 冲突。
- 每次 build 之前 `defaults write com.apple.dt.Xcode ...` 设 environment —— GUI build 不读 env，必须改 pbxproj。
- `chmod -R` 改 entitlements 文件权限试图"解锁" Xcode —— Xcode 不看 POSIX 权限。

## 13. Settings 布局修复（合并 §24 + §25）

### §24 Settings AI section 布局修复

**症状**（你："设置的页面 需要修理一下布局和样式"）：我加的 `aiSection` 用了自己写的 `labeledField` HStack helper，跟 macOS 原生 `Form { Section { ... } }` 渲染不一致。

**根因**：`Form { Section { ... } }` 在 macOS 上自动把每个 row 渲染成 "label 列 + control 列" 两栏布局，但我自己写的 `labeledField` HStack 是手动布局，跟系统对不齐，看起来"很丑"。

**修法**：用 `Form { Section { ... } }` 的原生 row 模式（`LabeledContent` / 直接放 control），去掉 `labeledField` HStack helper。

### §25 Settings 窗口尺寸 / title bar 重叠修复

**症状**（你："窗口红色框框部分 重叠了。 底部也是一样"）：Settings scene 窗口顶部 title bar（含 close 按钮 + traffic lights）+ 底部 form 边界跟 SwiftUI Form 的 section 渲染重叠。

**根因**：旧版 `.frame(width: 480, height: 720)` 写死高度 720pt，但加 AI section 之后 form 实际总高 ~820pt，超出窗口高度 100pt，section 渲染时 title bar 区域 / form 底部都被裁切。

**修法**：
1. 窗口尺寸从 `.frame(width: 480, height: 720)` 改为 `.frame(width: 480, height: 600)`（去掉写死的高度，让 SwiftUI 自己算）
2. `Form` 用 `.formStyle(.grouped)` 配 native padding
3. 内部 ScrollView + `.frame(minHeight: 480)` 让 form 能滚

**不要做**：在 `SettingsView` 里硬编码 `.frame(...)` 高度 —— SwiftUI 自己算 content size，window autosave 记住用户拖过的尺寸。

## 14. AI 返回 <think> 推理块 bug 修复

**症状**（你："存在 bug,对接 ai 之后显示"）：用户开了 AI 增强，用 DeepSeek R1 / QwQ / o1 这类 reasoning model，通知 body 出现 `<think>...</think>` 推理块 —— AI 在 `<think>` 标签里做 chain-of-thought 推理，body 不该展示给用户。

**根因**：
- 旧 `AIServiceContext.firstCleanLine(text)` 只剥前导空白行，不知道 `<think>` 标签的存在
- `<think>...</think>` 是 reasoning model 的训练行为，关不掉

**修法**（`AIService.swift` `firstCleanLine`）：
1. 如果 `text` 包含 `</think>`，取 `</think>` 之后的内容
2. 如果内容以 `<think>` 开头（没结束标签，截断），整段丢掉
3. 再走原 `firstCleanLine` 逻辑（剥空白行 + 找第一行非空）

**验证**：开 AI 增强 + DeepSeek R1，记录一条想念，通知 body 显示 "想念 苏苏 🌙" 而不是 "<think>用户刚记...</think>想念 苏苏"。


## 15. 数据导入 / 导出 + iCloud 同步 + 可指定存储路径

**新需求**：用户想把数据备份 / 跨设备迁移 / 走 iCloud。

### 1. 导入 / 导出（备份 + 跨设备迁移）

- `StorageService.exportToFile()` → 用户在 `NSSavePanel` 选位置 → 写 JSON（`Missing` 全量 + 创建时间 + 设备 ID）
- `StorageService.importFromFile(url:)` → 用户在 `NSOpenPanel` 选文件 → 校验 schema + 合并 / 覆盖
- 默认"合并"策略（保留本地 + 补全远端），Settings 里可切"覆盖"（用远端替换本地）

### 2. iCloud 同步（多设备无感同步）

- 用 `NSUbiquitousKeyValueStore`（CloudKit 不必要，KV 存就够，1MB 限制 Missing 数据远用不完）
- 启动时 `synchronize()` 拉云端 → 合并 → 本地 + 云端
- 写入时 `set(_:forKey:)` + `synchronize()` 异步推
- 监听 `.didChangeExternallyNotification` 接收远端推送

### 3. 自定义存储路径（用户自选）

- Settings → "存储位置" section → "更改…" / "恢复默认" 按钮
- "更改…" 调 `NSOpenPanel(canChooseDirectories: true)` 让用户选目录
- 存储路径存 `AppPreferences.storagePath: String?`，nil = 默认 sandbox 路径
- 启动时检查路径，存在 + 可写 + 是 dir 才用，否则 fallback 默认

### 关键文件

- `StorageService.swift`（113 lines，2026-05 重写）
- `SettingsView.swift` 的 `storageSection`

## 16. Anxious Attachment Record Bundle (v1.x)

针对焦虑型依恋人格的"看见 pattern / 累积平复证据 / DBT 落点"扩展。Spec 在 `docs/superpowers/specs/2026-06-26-anxious-attachment-bundle-design.md` (source of truth, 改字段先改 spec)。

**`Missing` 新增 3 个字段**:
- `triggerTags: [TriggerTag]` (默认 `[]`, 必有值) —— 这次想念的诱因, 8 个预定义 (💬 TA 没及时回 / 🔇 TA 没说想我 / ⚡️ 刚吵完架 / 🏠 独处时 / 👀 看到某物 / 🕰 想到过去 / ✈️ 分离 / 🪞 比较)
- `resolvedAt: Date?` —— 平复时间戳 (用户主动标记, 30 分钟 grace period 避免"刚提交就被问")
- `realityCheck: RealityCheck?` —— DBT "Check the Facts" 轻量落点, 含 `evidenceFor` / `evidenceAgainst` / `nextAction` / `checkedAt`

**3 个新功能 (跟 spec 一致)**:
1. **RealityCheck sheet** (intensity == strong submit 后自动弹) —— DBT "Check the Facts" 引导
2. **ResolveLast banner** (新建表单顶部) —— 30 分钟前记录未平复时显示
3. **3 个 insight 卡片** (Statistics tab) —— "浪都过去了" / "常见 trigger" / "现实检验完成度"

**AppPreferences 关联**:
- `autoPromptRealityCheck` (默认 true) —— intensity == strong 后自动弹
- `autoPromptResolveLast` (默认 true) —— 30 分钟 grace 后显示 banner
- `notificationIncludeTriggers` (默认 true) —— 通知 body 追加 trigger 信息

**注意**:
- v1.x 简化版: 没有 "Reactivity Window" 等 v2.x 高级 UX
- `33b9176 revert: 撤回回避型依恋 bundle (准备重新设计)` 已撤回, 当前不包含
- 字段加新 case 时注意 `Missing.init(from:)` 用了 `compactMap(TriggerTag.init(rawValue:))` 做 forward-compat, 老 JSON 不会 crash

## 17. Self-Soothing Bundle (v1.x 第二轮)

针对焦虑型依恋人格的"浪来时接住你" —— body 层 self-soothing 工具, 跟 §16 认知层 (record) 形成完整链路。Spec 在 `docs/superpowers/specs/2026-06-26-self-soothing-bundle-design.md` (source of truth)。

**3 个 sub-sheet 工具** (在 `Views/`):

1. **GroundingSheet** —— 5-4-3-2-1 sensory grounding step-by-step 引导
2. **SelfCompassionView** —— Kristin Neff 3 元素 (mindfulness / common humanity / self-kindness) curated 短语 + "再抽一句" 按钮
3. **CooldownSheet** —— 6 预定义 + 用户追加的 DBT 活动卡片 (5 senses grounding / paced breathing / TIPP / etc) + "再抽一个" 按钮

**2 个入口** (A 路径浪来时强 nudge, B 路径事后回访, 都用同样的 3 个 sub-button):
- A 路径: `RealityCheckSheet` 底部加 3 个 sub-button, intensity == strong 提交后自动弹
- B 路径: `HistoryList` 卡片底部加同样的 3 个 sub-button, mild 也能用

**1 个轻度 inline nudge**: `NewMissingForm` 提交 intensity == mild 后短暂显示 "想冷静一下?" 链接 (3 秒后 fade)。

**17 句 self-compassion 文案** (`Models/CooldownActivities.swift` `defaults` 数组): 4 mindfulness + 4 common humanity + 5 self-kindness + 4 practical。

**AI fallback**: 用户开 AI 增强 + 配 endpoint 时, `AIService.generateSelfCompassion()` 覆盖这 17 句; 否则 `SelfCompassionView` 随机抽 1 句用。

## 18. 通知 / 统计 / 搜索 / 替代 App Icon（第二轮优化）

### 通知

`UNUserNotificationCenter` 在 `MissingStore.add` 后由 `NotificationService.shared.postRecordNotification` post。Title 是 "想念 {who}"，body 走 AI（或 fallback 固定模板），attach 当前 mood 的菜单栏 PNG 作为通知图标（拷贝到 `tmp/` 后再 attach，避开 sandbox 跨容器 B6 错）。

### 统计 tab

`Views/StatisticsView.swift` 用 `Timer.publish(every: 60)` 跑表，显示：
- 累计 / 本周 / 平均强度
- Top 3 思念对象
- 30 天 stacked bar chart (5 mood 颜色堆叠) —— `import Charts` (macOS 13+ 内建)
- 空数据时显示"近 30 天还没有记录"占位

### 搜索

`HistoryList` 顶部加 `magnifyingglass` + `TextField` 的小搜索框，按 `who` 做 `localizedCaseInsensitiveContains` 过滤；空状态文案根据是否有 query 切换。

### 替代 App Icon

`make-icons.py` 额外生成 5 个 mood 的 `.iconset` + `.icns`（用 mood 调色板染色，存到 `build/icon-source/AppIcon-{mood}.icns`），通过 `Resources/` 打进 bundle。**macOS 没有公开 API 运行时切换 App Icon**（iOS 有 `setAlternateIconName`），所以目前这些 `.icns` 只是 bundle 里就绪，未来若 Apple 加了 macOS 等价 API 可直接用。

## 19. Trend chart + 自动褪色 + Sparkle 脚手架（第三轮优化）

### 统计 trend chart

`StatisticsView` 新增 30 天 stacked bar chart，按日期 x 轴堆叠 5 种 mood 颜色，配色集中放在 `MoodColor.forMood(_:)` 里，和 `make-icons.py` 的 `MOOD_PALETTE` 端点保持一致。空数据时显示"近 30 天还没有记录"占位文案。

### 菜单栏自动褪色

记录后 mood 颜色的菜单栏图标显示 8 秒，然后 1.2s `CABasicAnimation(opacity)` ease-in-out 渐变到 0.25 透明度（让下面的 neutral template 隐约透出）。任何点击（`togglePopover`）和冷启动都会 `cancelMoodFade()` 还原满透明度，并 `layer.removeAnimation(forKey:)` 立刻清掉。Timer 用 `Timer.scheduledTimer` + `[weak self, weak button]`，按记录会 reschedule。

**注**：本功能在 commit `e94ba7f refactor(ui): remove PopoverContent` 之后未继续维护 —— 当前 NSPanel 路线没"togglePopover"概念。如需重做，参考 `StatusItemPanel` 现有的 8s/1.2s timer 思路。

### Sparkle 脚手架

`scripts/build-with-sparkle.sh` 检测 `xcodebuild / brew / generate_appcast / sign_update`，生成 `dist/appcast.xml.template`（item 1.0 的样子，含 EdDSA 签名占位符），打印 Sparkle 需要的 Info.plist keys（`SUFeedURL / SUEnableAutomaticChecks / SUPublicEDKey`），列了 4 步实际接入清单（生成 EdDSA keypair → vendoring `Sparkle.framework` → 把 `SPUUpdater` 接到 `…` 菜单的"检查更新"上 → host appcast）。**没有真实接入** —— 你没给 appcast 托管 URL，也没 sign up Sparkle 账号，这条线等基础设施准备好再走。

## 20. AI 增强 (OpenAI 兼容 endpoint)

**位置**：`MissingPlusPlus/Services/AIService.swift` + `Services/KeychainService.swift` + Settings 的 `aiSection`。

**架构**：
- `AIService.shared` 是 `actor`（不是 `@MainActor`），隔离 `chat(...)` 调网络
- 高层 `generateSelfCompassion` / `generateNotificationBody` / `generateAILetterToThem` / `generateAIRealityCheck` / `testConnection` 是 `@MainActor func`，负责读 `AppPreferences` + fallback 决策
- 不做 streaming、不做 retry、不做 token counting —— MVP 阶段用不上
- timeout 用 `URLSessionConfiguration.timeoutIntervalForRequest` + Task group 双保险
- base url 兼容：用户填 ".../v1" / ".../v1/" / "https://x.com" / "https://x.com/" 都行，内部归一化为 "{origin}/v1/chat/completions"

**AppPreferences 关联**：
- `aiEnabled`（默认 false）—— 总开关
- `aiBaseURL`（默认 `https://api.openai.com/v1`）—— OpenAI 兼容 endpoint
- `aiModel`（默认 `gpt-4o-mini`）—— 模型名
- `aiAPIKey`（存 Keychain，不进 UserDefaults）—— API key
- `aiTemperature`（默认 0.7）—— sampling temperature

**4 个 content generator**：
1. `generateNotificationBody(for: Missing)` —— 1 行通知正文（"想念 {who}" + 1 句温柔注脚）
2. `generateAILetterToThem(...)` —— "致 TA 的话"，3 封备选信里抽 1 封
3. `generateAIRealityCheck(recent: [Missing])` —— "过去 7 天 N 次想念 TA，平均强度 X/Y" 这种 pattern 描述
4. `generateSelfCompassion()` —— 替代 17 句 hardcoded 模板，AI 生成

**AI 关闭 / 配置缺失 / 失败**：所有 generator 自动 fallback 硬编码模板，**用户无感** —— 比如 `AIServiceContext.fixedNotificationBody(for:)` 是通知 body 的 fallback。

## 21. AppDelegate 重构（Phase 1-7）

AppDelegate 在 Phase 1-7 抽出了 6 个 controller / service，从 581 行瘦到 123 行。Timeline：

| Phase | 抽出 | 文件 | 行数 | 净减 |
|---|---|---|---|---|
| 1 | `StatusItemPanel` + `StatusItemView` | `StatusBar/StatusItemPanel.swift` | 105 | -98 |
| 2 | `WindowController` | `Windows/WindowController.swift` | 110 | -56 |
| 3 | `MenuBuilder` + `MenuActionRouter` | `StatusBar/MenuBuilder.swift` | 189 | -105 |
| 4 | `NotificationService` | `Services/NotificationService.swift` | 75 | -41 |
| 5 | `HotKeyController` | `Services/HotKeyController.swift` | 97 | -26 |
| 6 | `StatusPanelController` | `StatusBar/StatusPanelController.swift` | 171 | -114 |
| 7 | `ActiveStateController` | `Services/ActiveStateController.swift` | 57 | -18 |
| **合计** | — | — | **804** | **-458 (-79%)** |

**关键设计原则**（贯穿所有 phase）：
- 每 controller / service 一份（不是单例，除了 `NotificationService.shared`）
- closure 注入 action dispatch（`@objc` method 只在 `MenuActionRouter` 这种 router 上）
- `NotificationCenter` 派发事件，controllers 之间不互相引用
- 全部 `@MainActor`（hotkey 的 Carbon C 回调用 `Box<T>` 包装 closure 跨 thread 派发）
- AppDelegate 永远是纯 wiring 层

**关键踩过的坑**（避免重蹈）：
- `unsafeBitCast(userData, to: AppDelegate.self)` —— 强转 raw pointer 回去，type-pun 错位就 crash。Phase 5 改用 `Box<T>` + `Unmanaged.passRetained`
- `onQuit = { NSApp.terminate(nil) }` 默认值 —— Swift 6 strict concurrency 在 non-isolated context 求值报 warning。修法：去掉默认值，让 caller 显式传
- `installStatusPanel` 重复调 `position()` —— 写到 UserDefaults 又读回来是 no-op
- 4 个 `build*` 方法 + 2 个 `@objc` action 全塞 AppDelegate —— Phase 3 抽到 `MenuBuilder` + `MenuActionRouter`（router 是 NSObject 子类，接收 `@objc` 消息转 closure）

## 22. 测试 + shell 入口（Phase 8-10）

### 测试覆盖（34 tests, 6 controller 全覆盖）

| Test class | Count | 覆盖什么 |
|---|---|---|
| `ActiveStateControllerTests` | 4 | debounce + delay + rapid + window-fires-again |
| `HotKeyControllerTests` | 7 | Spec enum 映射 + Carbon modifier mask + init smoke |
| `MenuBuilderTests` | 6 | 树结构 + intensity submenu + representedObject + quit config |
| `NotificationServiceTests` | 8 | `makeMoodAttachment` + `titleForMissing` 格式 + postRecord smoke |
| `StatusPanelControllerTests` | 6 | install/uninstall + prefs 变化响应 + rapid toggle + dismiss |
| `WindowControllerTests` | 4 | 主/设窗口创建 + 双调用不崩 |
| **Total** | **35** | — |

**为了让测试能访问 production code，2 处小 refactor**：
- `NotificationService.makeMoodAttachment(for:)` 从 `private func` 改成 `internal static func` —— 测试直接调
- `HotKeyController.Spec.carbonKeyCode/carbonModifiers` 从 `fileprivate` 改成 `internal` —— 测试直接验 Spec enum 映射

**测试策略总结**（按 controller 难度排序）：
- **最容易**（纯逻辑）：`ActiveStateController` debounce/delay 用时间窗口
- **中等**（NSMenu 树）：`MenuBuilder` 直接构造 NSMenu 然后查 `.items.count` / `submenu`
- **中等**（NSWindow 创建）：`WindowController` 通过 `NSApp.windows.filter { $0.title == "心安日记" }` 验窗口存在
- **较难**（observer 协调）：`StatusPanelController` 操纵 `AppPreferences.shared.showStatusItem` 触发 didSet（写 defaults + post .appPreferencesDidChange），`NSApp.windows` 查 panel
- **最难**（外部 service）：`NotificationService` 抽 `makeMoodAttachment` / `titleForMissing` 为 internal static 绕开 UN 投递链路
- **不测**（无法直接验）：`HotKeyController` Carbon callback 真触发路径 —— 没有公开 API 反查 hotkey 绑定，init smoke 够

**踩过的坑**：
- pbxproj 只加 PBXSourcesBuildPhase 不够 —— 完整 4 处（BuildFile + FileRef + group + phase）一起加
- `Spec.carbonKeyCode` 是 `fileprivate` —— 改 `internal` 才能 `@testable` 访问
- `kVK_ANSI_Space` 找不到 —— `Carbon` import 不包括 HIToolbox/Events.h 里的 ANSI 系列，改用 `kVK_Space`
- `cmdKey | optionKey` 是 `Int`，Spec 期望 `UInt32` —— 加显式 `UInt32(...)` cast
- 不要给 `NotificationService.postRecordNotification` 写"验证 UN 投递成功"的测试 —— UN 是 process singleton，测试环境投递会真发通知干扰 dev 体验
- 不要给 HotKeyController 写"验证 ⌥M 真注册成功"的测试 —— Carbon EventHotKey 没有公开 API 反查

### Shell 入口（Phase 9）

按 `build-macos-apps:build-run-debug` skill 约定加 2 个 shell 脚本，xcodebuild 长命令包装成简单入口：

- `scripts/build_and_run.sh` —— kill + xcodebuild build + `/usr/bin/open -n .app`
  - `./scripts/build_and_run.sh`（default Debug）
  - `./scripts/build_and_run.sh --release`（Release build）
  - `./scripts/build_and_run.sh --verify`（build + launch + `pgrep -x` 验证）
  - `./scripts/build_and_run.sh --debug`（build + `lldb --attach-pid`）
  - `./scripts/build_and_run.sh --logs`（build + launch + `log stream` 过滤 subsystem）
- `scripts/run_tests.sh` —— `xcodebuild test` + 失败时 tail 末尾 60 行
  - `./scripts/run_tests.sh`（default Debug 全 test）
  - `./scripts/run_tests.sh --release`（Release 全 test）
  - `./scripts/run_tests.sh --filter <expr>`（自动补 `MissingPlusPlusTests/` 前缀跟 xcodebuild 格式匹配）
  - `./scripts/run_tests.sh --build-only`（`build-for-testing` 不跑）

**设计原则**：
- xcodebuild 走 `build/DerivedData/` 隔离，不污染 `~/Library/Developer/Xcode/DerivedData/`
- default no-flag 路径简单（一个命令跑完 kill + build + launch 整条链）
- run_tests.sh 失败时 tail 末尾 60 行重新打，人类能读懂
- 跟 `scripts/build-dmg.sh` 不冲突 —— 那个是发布入口，这两个是 dev 入口


## 23. CI / Release workflow

GitHub Actions 配置 (`.github/workflows/test.yml` + `release.yml`) 维护在 [`docs/ci.md`](docs/ci.md). 本机未推 GitHub 时可跳过. 相关打包/签名约束见 §7 + §9.

## 24. Worth Affirmation Bundle (v1.x §24)

针对"焦虑型依恋"最深的一层:把价值感从外部(TA 的回应)拉回内部(我自己的确认)。Spec 在 `docs/superpowers/specs/2026-07-01-worth-affirmation-bundle-design.md` (source of truth)。

### 1 张结构化卡片,3 段竖排

`Views/WorthAffirmationView.swift` —— 1 张卡 3 段,1 段叙事走完:

1. **看见** (mindfulness, 蓝色) —— "是的,我刚才在反复看 TA 的对话框。"
2. **主体 vs 客体** (subject-object split, 紫色) —— "我是…" / "TA 是…" 两个并排小卡
3. **向内求** (inward, 绿色) —— "我值得被爱,不取决于 TA 这一刻在不在。"

**3 段合一叙事**:每条 `WorthAffirmation` 是 1 个 4-field struct (`seeing / subject / object / inward`),"再换一组" 4 段一起换,不分段 shuffle(避免割裂组合破坏叙事连贯)。

### 3 个按钮:in-control 动作分层

- **"再换一组"** (bordered) —— 4 段一起换,不计數
- **"我已确认"** (borderedProminent, 绿色, defaultAction) —— append `Date()` + dismiss
- **"关闭"** (borderless, 小) —— dismiss 不计數

**"关闭" 和 "我已确认" 是 2 个不同的 in-control 动作**:close = "我读完了但不想现在收下"(不计数),confirm = "我收下了"(计数)。"再换一组" 也不计数(只是看看,不是承诺)。

### 10 条 curated pool (`Models/WorthAffirmations.swift`)

`pool: [WorthAffirmation]` v1 hardcode 10 条,覆盖 5 种想念场景(已读不回 / 没主动联系 / 翻旧朋友圈 / 想到过去 / 分离焦虑)+ 5 种情绪模式。`randomDifferent(from:)` 用 `while next == current` 防同组重复。

**v1 不开 AI 生成** —— 3 段叙事是核心内容,hardcode curated pool 才稳;AI 走偏了"我值得被爱"会被稀释成鸡汤。`WorthAffirmations.initial` 走 `pool.randomElement()` 起步。

### 3 个入口 (跟现有 sub-sheet 模式一致)

| 入口 | 位置 | icon | 颜色 |
|---|---|---|---|
| A 浪来时强 nudge | `RealityCheckSheet` 底部 sub-button (4 个) | `heart.circle.fill` | 绿 |
| B 事后回访 | `HistoryList` 卡片底部 sub-button (5 个,icon size `.callout` → `.caption`) | `heart.circle.fill` | 绿 |
| C 新建后 inline | `NewMissingForm` "想冷静一下?" 5 秒 link (5 个图标) | `heart.circle.fill` | 绿 |

**icon 选择**:`heart.circle.fill` —— 圆心 = 完整的自己,跟"自我同情"的 `heart.text.square`(方形短语卡片)区分;绿色 = 跟"向内求"section 配色一致。

**5 个图标挤 1 排**:HistoryList card icon size 从 `.callout` (16pt) 改 `.caption` (12pt),5×12+4×4=76pt,`who` 文字 `lineLimit(1)` + `Spacer(minLength: 4)` 维持弹性。inline link 保持 `.callout` + spacing 4pt。

### 1 个新 preference (`AppPreferences.worthConfirmations: [Date]`)

```swift
@Published var worthConfirmations: [Date] {
    didSet { defaults.set(worthConfirmations, forKey: Keys.worthConfirmations) }
}
```

**用 `[Date]` 不用单个 `Int` counter** —— 让 Statistics 卡片能自己算"本月 / 上月 / 30 天"窗口,过滤逻辑不依赖一个写死的 `lastResetMonth` 字段。append-only(删 = 失去一次确认历史)。

UserDefaults 缺字段 → `defaults.array(forKey:) as? [Date] ?? []` fallback,老用户无痛。

### 1 张新 insight 卡片 (`StatisticsView` 第 4 张)

```swift
WorthAffirmationCard(stats: worthStats)  // "本月你向内求 · N 次"
```

```swift
private var worthStats: (thisMonth: Int, total: Int) {
    let cal = Calendar.current
    let now = Date()
    let all = AppPreferences.shared.worthConfirmations
    let thisMonth = all.filter {
        cal.isDate($0, equalTo: now, toGranularity: .month)
    }.count
    return (thisMonth, all.count)
}
```

**大数字 = 本月**(近 30 天太宽,月份才对齐用户的时间感);副标题不写"继续努力" / "你很棒"—— 价值感已经在卡片里说过了,统计副标题只陈述事实。首次 0 状态引导文案直接指向 HistoryList 卡片底部的心形图标(具体可发现性 > 抽象引导)。

### 跟 self-compassion 的边界

- `SelfCompassionPhrases` (17 句,kindness 维度) = single phrase
- `WorthAffirmations` (10 条,4-field structured narrative) = "看见 → 拆 → 向内求" 3 段叙事

compassion 不做"我是 / TA 是"拆分,worth 不做 single 短语。2 个池子不交叉,UI 入口 icon shape 区分(`heart.text.square` vs `heart.circle.fill`)。

### 不要做

- 不要把 affirmation 做成 step-by-step 多步走完(5 步走完)
- 不要做 AI 生成 affirmation
- 不要做 streak / 每日目标 / 提醒(向内求是 in-control 动作,外部 KPI 跟"内部价值"目标冲突)
- 不要让用户自定义 affirmation(v1 锁死 10 条 curated)
- 不要在 popover(`MenuBarContent`)里加 worth 入口(popover 是 peek,工具在主窗口用)
- 不要在 mild submit 后的 RealityCheckSheet 路径上同时弹 worth(mild 不弹 RealityCheckSheet,走 inline link 5 个图标;strong 走 RealityCheckSheet 4 个 sub-button,2 条路径不重复)
- 不要给 WorthAffirmationView 加 "保存草稿" / "上次的进度" 恢复(每次 fresh random,不画像)
- 不要在统计卡片里加"还差 X 次达到本月目标" / "继续努力" / 进度条
- 不要在 worth sheet 关闭时强制 append Date("关闭" 和 "我已确认" 是不同 in-control 动作)
- 不要在 HistoryList 卡片底部加 dropdown / overflow menu 收 5 个图标(直接 .caption 紧排)

### 关键改动文件

**新增 (2 个)**:
- `MissingPlusPlus/Models/WorthAffirmations.swift`
- `MissingPlusPlus/Views/WorthAffirmationView.swift`

**修改 (5 个)**:
- `MissingPlusPlus/Services/AppPreferences.swift` (worthConfirmations + Key + init)
- `MissingPlusPlus/Views/RealityCheckSheet.swift` (+1 sub-button,spacing 8→6)
- `MissingPlusPlus/Views/HistoryList.swift` (+1 sub-button,icon size → .caption)
- `MissingPlusPlus/Views/NewMissingForm.swift` (+1 sub-button)
- `MissingPlusPlus/Views/StatisticsView.swift` (+第 4 张 insight 卡片)

**pbxproj**: 5 个 section 改 8 行新条目 (PBXBuildFile ×2 + PBXFileReference ×2 + Models group +1 + Views group +1 + App Sources phase +2),ID 分配 `A1000012000000000000A016/017` + `B1000012000000000000A016/017`(接现有 `A1000012000000000000A015` 之后)。


## 25. Update Checker (v0.0.2+)

启动后 5s 静默检查 GitHub Releases + 状态栏菜单 "Check for Updates…" 手动触发。零新依赖,完全自写 (不引 Sparkle)。

### 关键文件
- `Services/UpdateChecker.swift` — URLSession 拉 `https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest`,semver 比对,emit `.didFindRemoteUpdate` notification
- `Services/AppPreferences.swift` — 4 字段: `updateCheckEnabled` (持久化) / `lastDismissedVersion` (持久化) / `lastCheckedAt` (transient) / `lastKnownRemoteVersion` (transient)
- `StatusBar/MenuBuilder.swift` — 加 `onCheckForUpdates` closure + "Check for Updates…" item + `MenuActionRouter.checkForUpdatesFromMenu(_:)`
- `StatusBar/StatusPanelController.swift` — 转发 `onCheckForUpdates` 到 MenuBuilder
- `MissingPlusPlusApp.swift` (AppDelegate) — `startBackgroundCheck()` + 订阅 `.didFindRemoteUpdate` → 拉主窗口 + post `.showUpdateBanner`
- `Views/UpdateBanner.swift` — sticky pink gradient banner
- `Views/MenuBarContent.swift` — 订阅 `.showUpdateBanner` via `.onReceive` 挂 banner
- `Views/SettingsView.swift` — "更新" section: toggle + 立即检查按钮 + lastCheckedAt 显示
- `MissingPlusPlusTests/UpdateCheckerTests.swift` — 15 个 case (semver 5 + performCheck 2 + edge cases 4 + throttle 3 + smoke 1)

### 关键设计决策
- **二级 NotificationCenter 派发**:`UpdateChecker` → `.didFindRemoteUpdate` → AppDelegate → `.showUpdateBanner` → `MenuBarContent`。`UpdateChecker` 不持 controller 引用,符合 AGENTS §6。
- **6h 节流**:`lastCheckedAt` < 6h 跳过自动检查;手动菜单不受限。transient 字段,不持久化。
- **Skip prerelease**:`tag_name` 含 `-` (alpha/beta/rc) 视为"已是最新",避免给 prerelease 用户假阳性。
- **Fail-silent (启动) + NSAlert (手动)**:启动 5s 失败静默吞 (避免打断用户);手动检查失败 NSAlert (用户期待反馈)。
- **GitHub user/org rename 后 URL 失效**:URL 是常量,改 1 行;GitHub API 改 v4 时改 `Accept` header 即可。

### 发布流程 (publish checklist)
1. 现有:tag push → CI 跑 → draft release 创建
2. **手动**:GitHub Releases 页面打开 draft,点 "Publish release" 公开
3. **手动**:Publish 完几分钟后,跑一次旧版 app → 启动 5s 后 banner 应该出

GitHub API `/releases/latest` 不会返回 draft release,所以 publish 步骤必须有。

### 不要做
- 不要在 `UpdateChecker` 里持 `WindowController` 引用 (违反 AGENTS §6)
- 不要把 `lastCheckedAt` / `lastKnownRemoteVersion` 持久化 (transient)
- 不要在启动检查失败时 NSAlert 打断用户
- 不要解析 prerelease
- 不要在 v0.0.2 之前的版本上 (CFBundleShortVersionString == 0.0.0 / 0.0.1) 测 banner 出现 (banner 不会出,因为 remote == local)
