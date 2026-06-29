# Missing++ 项目级 Codex 准则

> 本文件只追加项目级约束；全局 `Codex 行为准则`（来自 Codex 配置）依然有效，下面不重复通用规则。

## 1. 项目形态

- macOS 菜单栏（Menu Bar）App，中文产品名 `思念计数器`。
- Bundle ID：`com.tuzhipeng.MissingPlusPlus`；Swift `5.0`；`MACOSX_DEPLOYMENT_TARGET` 见 Xcode 工程（工程里同时存在 `13.0` 与 `26.0` 两个值，按实际 target 配置为准）。
- `Info.plist` 中 `LSUIElement = false`（**有** Dock 图标 + 完整 app menu；详见 §12 "Dock + entitlements"）。
- `MissingPlusPlus.entitlements` 已开启 App Sandbox（`app-sandbox` + `files.user-selected.read-write`）。

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
├── Views/                              # MenuBarContent / NewMissingForm / HistoryList / SettingsView / ...
├── StatusBar/                          # 状态栏入口三件套
│   ├── StatusItemPanel.swift            #   NSPanel 浮动 button (macOS 26 替代 NSStatusItem)
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
└── (无 MissingPlusPlus/Resources 目录 — Resources 是 PBX group, 不是文件系统目录)

MissingPlusPlusTests/                   # 34 个 XCTest, 6 个 controller 全覆盖
├── ActiveStateControllerTests.swift    #   4 tests
├── HotKeyControllerTests.swift          #   7 tests
├── MenuBuilderTests.swift               #   6 tests
├── NotificationServiceTests.swift       #   8 tests
├── StatusPanelControllerTests.swift     #   5 tests
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
- [ ] 启动后状态栏出现 icon，控制台能看到 `[Missing++] final: visible=1`。
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

## 10. Menu Bar Icon 调试历史（合并 8 个 section）

这条线经历了 6 轮反复，最终稳定。Timeline：

### 第 1 轮：5 mood 彩色 PNG（§10 原始版）

`MenuBarIcon-{mood}.png` 22x22 px @1x 配 44/66 @2x/@3x，存到 `MissingPlusPlus/Resources/`。渲染走 `MenuBarIconRenderer.image(mood:style:)`（style 支持 `heart` / `emoji` / `思字` 三种 + 5 mood 染色）。

### 第 2 轮：小蓝点 bug（§14）

`Bundle.main.image(forResource: "MenuBarIcon")` 加载 44x44 px @2x retina PNG，返回的 `NSImage.size` 是 **(44, 44)**（把像素当成了点）。`NSStatusBarButton` 用 `squareLength` 锁 width=22pt，但 height 按 image size 长到 44pt —— **比 24pt 高的菜单栏还高**，于是只有图像顶端 1-2pt 从菜单栏里漏出来，看上去是一个"小蓝点"而不是心。

**修法**（`installStatusItem` + `updateMenuBarIcon`）：
```swift
if let image = Bundle.main.image(forResource: "MenuBarIcon") {
    image.size = NSSize(width: 22, height: 22)   // 显式 logical size
    image.isTemplate = true
    button.image = image
}
```

### 第 3 轮：回退到 `button.title = mood.emoji`（§15）

`image.size = (22, 22)` 修法在不同 OS / 不同 Xcode 组合下又翻车。改用文本路径：`button.title = mood.emoji`，emoji 字体（Apple Color Emoji）自带配色（开心黄 😊 / 愉悦绿 😄 / 欢乐粉 🥰 / 难过蓝 😢 / 思念紫 🥺），mood 联动保留，**完全绕开 NSImage sizing 那条坑**。

### 第 4 轮：emoji 0 宽 bug（§18）

`button.font = NSFont.systemFont(ofSize: 16)` 给的是 **SF Pro**，SF Pro 整套字符集里**没有 emoji 字形**。Cocoa fallback 不是显示"豆腐"方块，而是直接给一个 **0 宽度占位符** —— 文字在视觉上不存在，hit area 也不存在，**点不到也看不到**。

**修法**：
```swift
let emojiFont = NSFont(name: "AppleColorEmoji", size: 14)
    ?? NSFont.systemFont(ofSize: 16)
button.font = emojiFont
button.title = mood.emoji
```

### 第 5 轮：debug 阶段回退到 `attributedTitle = "思"`（§19）

你说"先不使用图标，使用文字替代"。`"思"` 单字撑满 22pt 单元格（17pt semibold），通过 `attributedTitle` 配 mood 颜色（5 mood RGB）走 SF Pro 字体渲染，避免 emoji 字体的 0 宽 fallback 问题。

### 第 6 轮（当前）：NSPanel 路线

macOS 26 上 `NSStatusItem` 默认进 Control Center 弹窗辅助区，屏幕顶部菜单栏看不到 —— 不管 `.regular` / `.accessory` / `autosaveName` 怎么设都不行。绕开 `NSStatusItem` 路线，用 **`StatusItemPanel`**（NSPanel 子类，22x22 浮动 button，level=.statusBar / nonactivatingPanel / canJoinAllSpaces）。

icon 走 `MenuBarIconRenderer.image(mood:style:)`，style 可选 `heart` / `emoji` / `思字`（用 `思` 字是 unicode `\u6015` 永远有 glyph，emoji 字体也能渲染）。

### "不要做"

- 不要在 `installStatusPanel` 用 `Bundle.main.image(forResource:)` 给 status bar button 设图，除非先 `image.size = NSSize(width: logicalWidth, height: logicalHeight)` 并确认 PNG 是 1x/2x/3x 的 retina-correct 版本。
- 不要在 menu bar button 上用 `imageScaling = .scaleProportionallyDown` / `.scaleToFit`，让 AppKit 用默认行为 + 显式 `image.size` 控制。
- 不要用 `NSFont.systemFont(ofSize:)` 给 `NSStatusBarButton` 显示 emoji，要么显式 `NSFont(name: "AppleColorEmoji", size:)`，要么用 `attributedTitle` + `kCTFontAttributeName` 指定 AppleColorEmoji。
- 不要看到 `NSLog("[...] visible=true")` 就以为菜单栏图标可见；Cocoa 渲染 emoji 失败是 silent failure。

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
主窗口: 思念计数器 360x752
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

## 16. Anxious Attachment Record Bundle（v1.x）

针对焦虑型依恋人格的"看见 pattern / 累积平复证据 / DBT 落点"扩展。Spec 在 `docs/superpowers/specs/2026-05-19-anxious-attachment-bundle.md`。

**新字段**（`Missing` 加 2 个 optional）：
- `triggers: [TriggerTag]?` —— 这次想念的诱因（💬 TA 没及时回 / 👀 看到合照 / ...）
- `resolvedAt: Date?` —— 平复时间戳（用户主动标记平复，30 分钟 grace period 避免"刚提交就被问"）

**5 个新功能**：
1. **RealityCheck sheet**（intensity == strong submit 后自动弹）—— "你过去 7 天有 3 次想念 TA，平均强度 4.2/5。这些想念的 pattern 是什么？"
2. **ResolveLast banner**（新建表单顶部）—— "上次想念平复了吗？30 分钟前你记了'想 TA'，现在心情平复了吗？"
3. **Cooldown activities**（resolve 之前弹）—— DBT ACCEPTS + IMPROVE 工具，6 条预定义 + 用户自定义
4. **Triggers 多选 chip**（新建表单）—— 一键打标，3 个默认 + 用户自定义
5. **平复率统计**（Statistics tab）—— "过去 30 天平复率 72%（18/25 次）"

**AppPreferences 关联**：
- `autoPromptRealityCheck`（默认 true）—— intensity == strong 后自动弹
- `autoPromptResolveLast`（默认 true）—— 30 分钟 grace 后显示 banner
- `notificationIncludeTriggers`（默认 true）—— 通知 body 追加 trigger 信息

**reverted line**: `33b9176 revert: 撤回回避型依恋 bundle (准备重新设计)` —— 当前代码是 v1.x 简化版（4 个新功能），没有 "Reactivity Window" 这种 v2.x 高级 UX。重新设计待用户启动。

## 17. Self-Soothing Bundle（v1.x 第二轮）

针对焦虑型依恋人格的"浪来时接住你" —— body 层 self-soothing 工具，和 §16 认知层（record）形成完整链路。Spec 在 `docs/superpowers/specs/2026-05-19-self-soothing-bundle.md`。

**3 个 sub-sheet 工具**（在 `Views/`）：

1. **CooldownSheet** —— 6 条 DBT 活动卡片（5 senses grounding / paced breathing / TIPP / 等等）
2. **GroundingSheet** —— 5-4-3-2-1 grounding exercise（5 看 / 4 触 / 3 听 / 2 闻 / 1 尝）
3. **SelfCompassionView** —— Kristin Neff 3 元素 self-compassion prompt（mindfulness / common humanity / self-kindness）

17 句 self-compassion 文案（`Models/CooldownActivities.swift` `defaults` 数组）：
- 4 mindfulness: "这一刻是这样的。它会过去。" / "我不需要立刻做什么。" / ...
- 4 common humanity: "想一个人是人类的本能。" / "很多人都会这样。" / ...
- 5 self-kindness: "我可以对自己温柔一点。" / "我已经在努力了。" / ...
- 4 practical: "喝一杯水。深呼吸 3 次。" / "洗个手，感受水的温度。" / ...

**AI fallback**：用户开 AI 增强 + 配 endpoint 时，这 17 句被 AIServiceContext 的 hardcoded 模板覆盖（"AI 增强 §20" 路径），否则随机抽 1 句用。

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
| `StatusPanelControllerTests` | 5 | install/uninstall + prefs 变化响应 + rapid toggle |
| `WindowControllerTests` | 4 | 主/设窗口创建 + 双调用不崩 |
| **Total** | **34** | — |

**为了让测试能访问 production code，2 处小 refactor**：
- `NotificationService.makeMoodAttachment(for:)` 从 `private func` 改成 `internal static func` —— 测试直接调
- `HotKeyController.Spec.carbonKeyCode/carbonModifiers` 从 `fileprivate` 改成 `internal` —— 测试直接验 Spec enum 映射

**测试策略总结**（按 controller 难度排序）：
- **最容易**（纯逻辑）：`ActiveStateController` debounce/delay 用时间窗口
- **中等**（NSMenu 树）：`MenuBuilder` 直接构造 NSMenu 然后查 `.items.count` / `submenu`
- **中等**（NSWindow 创建）：`WindowController` 通过 `NSApp.windows.filter { $0.title == "思念计数器" }` 验窗口存在
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


## 23. CI (GitHub Actions)

`.github/workflows/test.yml` — 每次 push / PR 到 `main` 跑：

1. **macOS 14 runner** + **Xcode 15.4**（用具体版本避免 macos-latest 默认变化导致 build 飘，工程 deployment target 13.5 完全兼容）
2. **Build (Debug)** — `xcodebuild build-for-testing`（不 launch .app，CI 不需要图形界面）
3. **Run Tests** — `./scripts/run_tests.sh`（失败时 tail 末尾 60 行重新打）
4. **失败时上传 xcresult artifact** — 本地能用 `xcodebuild -resultBundlePath` 看 detail

**Cache**：`build/DerivedData` 走 `actions/cache@v4`，key 用 `hashFiles('*.xcodeproj/project.pbxproj')`（pbxproj 改了缓存失效，缓存命中能省 1-2 分钟）。

**Concurrency**：同一 PR 不并发跑（`concurrency: missingpp-${{ github.ref }}` + `cancel-in-progress: true`），节省 macOS runner quota。

**本地没推 GitHub 之前这个 workflow 不会跑**——但配置文件是 ready 的，等你推到 GitHub 立刻生效。push 前先在本地跑 `./scripts/run_tests.sh` 确认 34/34 pass。

**不要做**：
- 不要用 `macos-latest` —— 默认 Xcode 版本会变，工程 build 飘时排查很痛
- 不要在 workflow 里写 `sudo xcodebuild` —— GitHub Actions runner 已经在 root 下，xcodebuild 直接调
- 不要传 secret 给 `run:` 命令 —— secret 会出现在 log 里。用 env 变量
- 不要 `actions/upload-artifact` 上传 `build/DerivedData/Build/Products/Debug/MissingPlusPlus.app` —— 整个 .app 几十 MB，没必要

**未来加的 workflow**（如果用户推 GitHub 后想加）：
- `release.yml` — 跑 `./scripts/build-dmg.sh` 出 DMG，上传 GitHub Release
- `lint.yml` — SwiftLint / swift-format check（如果未来引入 lint）

## 24. 环境配置 (Codex Run button)

如果用 Codex desktop 客户端，可以加 `.codex/environments/environment.toml` 把 `./scripts/build_and_run.sh` 暴露成 Run button。当前**未加**——

- **理由 1**：环境配置文件不在 `MissingPlusPlus.xcodeproj/` 同步链上，Codex 客户端启动时按需读，但 AGENTS.md 是全局读的，混在 AGENTS.md 反而更直观
- **理由 2**：`build_and_run.sh` 名字 + `kill existing + xcodebuild + open -n` 行为 跟 Codex 的 "Run app" 默认预期一致，不需要额外 wrapper
- **理由 3**：本机没推 GitHub，CI 还没跑，dev workflow 暂时不需要 Run button 暴露

未来如果用户明确要 "Codex GUI 里点 Run 直接跑 app"，再加这个文件。

## 25. Release workflow (`release.yml`)

`.github/workflows/release.yml` — tag push 或 manual dispatch 触发，跑 `build-dmg.sh` 出 DMG + 上传 GitHub Release（**draft**，用户手动 review + publish）。

**Triggers**：
- `push: tags: ['v*.*.*']` — `git tag v1.2.3 && git push origin v1.2.3` 自动跑
- `workflow_dispatch: inputs.version` — GitHub Actions 页面点 "Run workflow"，输入 version 字符串（e.g. `1.2.3`）

**Steps**：
1. checkout（`fetch-depth: 0`，git describe 需要全部 history）
2. select Xcode 15.4
3. cache DerivedData（key = `hashFiles('*.xcodeproj/project.pbxproj')`）
4. **Resolve version** —— tag push 取 `GITHUB_REF_NAME` 去掉 `v` 前缀；dispatch 取 `inputs.version`
5. **Build DMG** —— `VERSION=$version ./scripts/build-dmg.sh`（见下）
6. **Verify DMG** —— 验证 `dist/MissingPlusPlus-$VERSION.dmg` 存在 + `shasum -a 256`
7. **Read CFBundleVersion** —— 用 `PlistBuddy` 读 `CFBundleShortVersionString` + `CFBundleVersion`，**校验** tag 版本必须 == `CFBundleShortVersionString`（防止 release v1.2.0 但 app 实际是 1.0.0 的错位）
8. **Create GitHub Release** —— `softprops/action-gh-release@v2`，`files: dist/*.dmg`，`draft: true`，`generate_release_notes: true`（从 merged PRs 自动生成 notes）

**Permissions**：`contents: write`（创建 Release 需要）

**Concurrency**：`group: missingpp-release-${{ github.ref }}` + `cancel-in-progress: false`（release 不能中途取消，serialize 跑）

**`build-dmg.sh` 的 VERSION 支持**（小幅 refactor）：
- 旧：`DMG_NAME="MissingPlusPlus-1.0.dmg"`（硬编码）
- 新：`VERSION="${VERSION:-1.0}"` + `DMG_NAME="MissingPlusPlus-${VERSION}.dmg"`
- 向后兼容：本地 `bash scripts/build-dmg.sh` 仍然出 `MissingPlusPlus-1.0.dmg`
- CI：`VERSION=${{ steps.version.outputs.version }} ./scripts/build-dmg.sh` → `MissingPlusPlus-$VERSION.dmg`

**签名限制**：workflow 当前出 **ad-hoc 签名** 的 DMG（仅本地用）。正式分发需要：
- 加入 Apple Developer Program（$99/年）
- 签发 `Developer ID Application` 证书
- `xcrun notarytool store-credentials <profile>` 存到 keychain
- workflow 加 `DEVELOPER_ID=1` + `DEVELOPMENT_TEAM=<TEAMID>` + `NOTARY_PROFILE` 3 个 GitHub secret
- 然后 `xcrun notarytool submit + staple` 跑公证

当前 workflow 没设这 3 个 secret，所以默认 ad-hoc。详见 §7 + §9。

**不要做**：
- 不要把 `Developer ID` 证书 / notary profile 直接 commit 到 repo（用 GitHub secret）
- 不要 `cancel-in-progress: true` —— release 跑到一半被取消会留下半截 DMG
- 不要在 release workflow 里跑 `git push --force` —— 万一 build 出问题，tag 已经被 force push 了
- 不要在 release notes 里写敏感信息（API key / 测试 token）—— release 是公开的
- 不要用 `softprops/action-gh-release@v1` —— 旧版，v2 才是当前支持的

**推 GitHub 后第一次 release 的检查清单**：
1. `git tag v1.0.1 && git push origin v1.0.1`（或者 Actions 页面手动 dispatch）
2. workflow 跑完后到 Releases 页面，应该看到 draft release
3. 检查 draft release 的 notes + DMG 文件 + SHA256
4. 点 "Publish release" 公开
