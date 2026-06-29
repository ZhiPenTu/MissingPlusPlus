# 状态栏图标设置（显示 / 样式）— 设计

> 日期：2026-06-25
> 状态：已批准（待实现）
> 涉及范围：`MissingPlusPlusApp.swift` / `SettingsView.swift` / 新增 2 个 service / `project.pbxproj`

## 1. 背景

`心安日记` (代码名 `MissingPlusPlus`) 是一个 macOS 菜单栏 app（`AGENTS.md §1`），目前状态栏图标是写死的：始终显示一个按 mood 染色的 SF Symbol `heart.fill`（`MissingPlusPlusApp.swift:150-178` 的 `applyMenuBarIcon`）。

历史上手动试过 4 条渲染路线（`AGENTS.md §14-§19`），最终定在 heart.fill + lockFocus + sourceAtop 染色。但用户在 settings 里没有"开关"和"换样式"的入口 — 这是这一轮要补的。

## 2. 目标

在 settings（⌘, 打开）里增加两个用户可见控件：

1. **状态栏图标是否显示**（bool toggle）
2. **图标样式**（3 选 1 picker：心形 / Emoji / 思字）

修改立即生效，跨 app 重启保留。

## 3. 非目标

- 不改 mood 模型、不改 `Missing` 数据结构、不改持久化路径。
- 不加右键菜单（`AGENTS.md §13` 已有结论）。
- 不在 popover 的 `…` 菜单里复制一份 style 切换（避免双源真相）。
- 不动 `Info.plist` / `entitlements` / 部署目标。
- 不引入 SwiftPM / CocoaPods / Carthage 依赖。
- 不改 AGENTS.md 里记录的"不要做"清单（这一轮新加 4 条规则，详见 §9）。

## 4. 架构

### 4.1 新增 `Services/AppPreferences.swift`

```swift
import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted by `AppPreferences` whenever the user mutates `showStatusItem`
    /// or `menuBarIconStyle` from the settings UI. `AppDelegate` listens and
    /// re-evaluates the status item (install / remove / re-render).
    static let appPreferencesDidChange = Notification.Name(
        "MissingPlusPlusAppPreferencesDidChange"
    )
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var showStatusItem: Bool {
        didSet {
            defaults.set(showStatusItem, forKey: Keys.showStatusItem)
            NotificationCenter.default.post(name: .appPreferencesDidChange, object: self)
        }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle)
            NotificationCenter.default.post(name: .appPreferencesDidChange, object: self)
        }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let showStatusItem = "ShowStatusItem"
        static let menuBarIconStyle = "MenuBarIconStyle"
    }
    private init() {
        self.showStatusItem = defaults.object(forKey: Keys.showStatusItem) as? Bool ?? true
        self.menuBarIconStyle = MenuBarIconStyle(
            rawValue: defaults.string(forKey: Keys.menuBarIconStyle) ?? "heart"
        ) ?? .heart
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Codable {
    case heart
    case emoji
    case character

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .heart:     return "心形"
        case .emoji:     return "Emoji"
        case .character: return "思字"
        }
    }
}
```

> **理由**：把 prefs 包成 `ObservableObject` + `@Published` + `didSet` 落盘，UI 直接绑 `$prefs.xxx`，避免手写 NotificationCenter 同步代码。UserDefaults 是 preferences 的标准容器；和 records 持久化（`StorageService` → `missings.json`）路径**分开**。

### 4.2 新增 `Services/MenuBarIconRenderer.swift`

把 `AppDelegate.applyMenuBarIcon` 抽出来，签名变成：

```swift
@MainActor
enum MenuBarIconRenderer {
    static func apply(to button: NSStatusBarButton,
                      mood: Mood?,
                      style: MenuBarIconStyle) {
        // 1. 先清上一种 style 残留
        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.contentTintColor = nil
        // 2. 按 style 分支写
        switch style {
        case .heart:     applyHeart(to: button, mood: mood)
        case .emoji:     applyEmoji(to: button, mood: mood)
        case .character: applyCharacter(to: button, mood: mood)
        }
    }
    // 三个私有 helper，每条对应一个历史 turn 验过的渲染路径
}
```

> **理由**：三种 style 切换时**必须**清掉上一态（`image` / `title` / `attributedTitle`），否则菜单栏 cell 会混（心形 image + emoji title 同时出现）。`AGENTS.md §15/§19` 都踩过这个"切回去留残影"的坑。

### 4.3 三种 style 的渲染细节

| style | button.image | button.title | button.attributedTitle | button.font | mood 联动 |
|-------|--------------|--------------|------------------------|-------------|----------|
| `.heart` | lockFocus+sourceAtop 染色的 NSImage | `""` | 空 | (default) | 颜色（5 mood 5 颜色） |
| `.emoji` | `nil` | `mood.emoji` | 空 | `NSFont(name: "AppleColorEmoji", size: 14) ?? .systemFont(ofSize: 14)` | 字符本身（5 mood 5 emoji） |
| `.character` | `nil` | `""` | `NSAttributedString(string: "思", attributes: [.font: SF Pro 17pt semibold, .foregroundColor: mood color])` | (default) | 颜色（同 heart） |

mood = nil 的统一默认走 `.happy` 暖金（用户在 §4 确认的方案）：

- `.heart` → `nsColor(for: .happy)` = `(1.00, 0.78, 0.34)`
- `.emoji` → `😊`（happy 的 emoji）
- `.character` → 暖金色"思"

### 4.4 AppDelegate 改动

#### `applicationDidFinishLaunching`

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    installAppMenu()
    installGlobalHotKey()
    if let latest = MissingStore.shared.sortedItems.first {
        currentMood = latest.mood
    }
    // 状态栏只在"用户允许"时挂
    if AppPreferences.shared.showStatusItem {
        installStatusItem()
    }
    // 监听 prefs 变化（didSet 内会 post）
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handlePrefsChanged(_:)),
        name: .appPreferencesDidChange,
        object: nil
    )
    // 已有监听保留
    NotificationCenter.default.addObserver(self, selector: #selector(handleMissingAdded(_:)), name: .missingStoreDidAdd, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(handleOpenSettings(_:)), name: .openSettings, object: nil)
}
```

#### `installStatusItem`

不变（只创建 button + 装 target/action + 设 autosaveName），但末尾的 `applyMenuBarIcon(mood: currentMood ?? .happy)` 改成：

```swift
MenuBarIconRenderer.apply(
    to: button,
    mood: currentMood ?? .happy,
    style: AppPreferences.shared.menuBarIconStyle
)
```

#### `handleMissingAdded`（已有，路径换走 renderer）

```swift
@objc private func handleMissingAdded(_ note: Notification) {
    guard let missing = note.userInfo?["missing"] as? Missing else { return }
    currentMood = missing.mood
    guard let button = statusItem?.button else { return }
    MenuBarIconRenderer.apply(
        to: button,
        mood: missing.mood,
        style: AppPreferences.shared.menuBarIconStyle
    )
    cancelMoodFade()
    scheduleMoodFade()
    postRecordNotification(for: missing)
}
```

> 注意：guard `statusItem?.button` — visibility 关闭时这条路径直接 return，不报错。

#### 新增 `handlePrefsChanged`

```swift
@objc private func handlePrefsChanged(_ note: Notification) {
    let prefs = AppPreferences.shared
    if prefs.showStatusItem {
        if statusItem == nil { installStatusItem() }
        // 当前 mood + 新 style 立刻应用
        MenuBarIconRenderer.apply(
            to: statusItem!.button!,
            mood: currentMood ?? .happy,
            style: prefs.menuBarIconStyle
        )
    } else {
        // 先关 popover（如果还开），再卸 statusItem
        popover?.performClose(nil)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
```

> **顺序**：visibility off 时**先关 popover**（anchor 还在），再 `removeStatusItem`。否则 popover 失去 anchor 后会留 orphan。

### 4.5 Settings UI 改动

`SettingsView` 加：

```swift
@ObservedObject var prefs = AppPreferences.shared
```

新增 section（顺序：存储位置 → **状态栏** → 数据 → 关于）：

```swift
private var menuBarSection: some View {
    Section {
        Toggle("在状态栏显示图标", isOn: $prefs.showStatusItem)
        Picker("图标样式", selection: $prefs.menuBarIconStyle) {
            ForEach(MenuBarIconStyle.allCases) { style in
                Text(style.displayName).tag(style)
            }
        }
    } header: {
        Text("状态栏")
    } footer: {
        Text("关闭后可通过 ⌘, 重新打开设置，或用 Dock / ⌥M 打开主窗口。")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

`Picker` 总是 enabled（visibility off 时也不灰）— 用户可以预选样式，下次开 visibility 时直接生效。

设置窗口 frame 高度从 560 → 600（容纳新 section + footer），宽度 480 不变。

## 5. 数据流

```
用户改 Toggle
    ↓ (Binding)
AppPreferences.@Published showStatusItem = newValue
    ↓ (didSet)
UserDefaults.set(...) + NotificationCenter.post(.appPreferencesDidChange)
    ↓
AppDelegate.handlePrefsChanged
    ↓
    if on:  installStatusItem() (if nil) + MenuBarIconRenderer.apply
    if off: popover.performClose + NSStatusBar.removeStatusItem
```

```
新记录
    ↓
MissingStore.add → post .missingStoreDidAdd
    ↓
AppDelegate.handleMissingAdded
    ↓
currentMood = missing.mood
    ↓
MenuBarIconRenderer.apply(button, mood, AppPreferences.shared.menuBarIconStyle)
    ↓
scheduleMoodFade (8s → 0.55 alpha, style 无关)
```

## 6. 错误处理 / 边界

- **冷启动 + 没记录 + 第一次用**：visibility = true (default), style = .heart (default), 状态栏显示 happy 暖金色 heart。和今天行为**完全一致**，向后兼容。
- **冷启动 + 之前用户关掉了 visibility**：`applicationDidFinishLaunching` 看到 `prefs.showStatusItem == false`，跳过 `installStatusItem`。状态栏干净。Dock + ⌥M 仍可开主窗口。
- **prefs 文件被外部改坏 / cast 失败**：init 里的 `?? true` / `?? .heart` 兜底回 default，不 crash。
- **visibility 切换瞬间 popover 正在开**：handler 里 `popover?.performClose(nil)` 在 `removeStatusItem` 之前；`performClose` 在 popover 不存在或未 shown 时是 no-op，安全。
- **style 切换瞬间**：`MenuBarIconRenderer.apply` 第一个动作是清 3 个状态字段，残留状态一定被冲掉。

## 7. 测试 / 验证

构建：

- [ ] `xcodebuild -configuration Debug` → `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -configuration Release` → `** BUILD SUCCEEDED **`

功能：

- [ ] 启动 → ⌘, → 看到 4 个 section，新 section "状态栏" 出现
- [ ] toggle off → 状态栏图标立刻消失
- [ ] toggle on → 状态栏图标以**当前选中的 style**立刻出现
- [ ] 切 style → emoji → 图标变 mood emoji
- [ ] 切 style → 思字 → 图标变"思"字，颜色随 mood
- [ ] 切 style → 心形 → 图标变彩色 heart
- [ ] 三种 style 下各记一条新记录 → icon 正确反映新 mood
- [ ] quit + relaunch → visibility + style 都保留

可达性：

- [ ] hide 状态栏时按 ⌘, → settings 打开（不依赖 statusItem）
- [ ] hide 状态栏时点 Dock → 主窗口打开
- [ ] hide 状态栏时按 ⌥M → 主窗口打开

回归防坑（`AGENTS.md §14-§19` 踩过的）：

- [ ] `screencapture -x` 截整屏 + `ImageChops.difference` baseline 校验：
  - emoji style 有可见像素（不是 0 宽 dot）
  - 思字 style 有可见像素（17pt semibold）
  - 三种 style 切换时 cell 不留前一种的残影（image / title 都被清）
- [ ] `NSLog` 校验 button frame：`(22, 22)` 或 `(22, 23)`，不出现 `(22, 44)` 的 image.size=44 翻车

打包：

- [ ] `bash scripts/build-dmg.sh` 跑通，DMG 生成
- [ ] pbxproj 幂等：跑 `scripts/patch-pbxproj.py`（如果用了）不重复插 build / ref ID

## 8. 改动文件

新增（2 个 + pbxproj 4 处插入）：

| 文件 | 类型 | 说明 |
|------|------|------|
| `MissingPlusPlus/Services/AppPreferences.swift` | 新增 | 单例 prefs |
| `MissingPlusPlus/Services/MenuBarIconRenderer.swift` | 新增 | 渲染逻辑（3 style 分支） |
| `MissingPlusPlus.xcodeproj/project.pbxproj` | 修改 | 4 处插入（PBXBuildFile ×2 / PBXFileReference ×2 / Services group ×2 / PBXSourcesBuildPhase ×2） |

修改：

| 文件 | 说明 |
|------|------|
| `MissingPlusPlus/MissingPlusPlusApp.swift` | 拆 `applyMenuBarIcon` 到 renderer；启动按 prefs 决定挂不挂；新增 `handlePrefsChanged`；`handleMissingAdded` 改走 renderer |
| `MissingPlusPlus/Views/SettingsView.swift` | 加 `@ObservedObject prefs` + `menuBarSection`；frame 480×600 |

不改：

- `MissingPlusPlus/Models/Mood.swift`
- `MissingPlusPlus/Services/MissingStore.swift` / `StorageService.swift`
- `MissingPlusPlus/Views/MenuBarContent.swift` / `NewMissingForm.swift` / `HistoryList.swift` / `StatisticsView.swift` / `PopoverOverflowMenu.swift`
- `MissingPlusPlus/Resources/*`（图标资源）
- `MissingPlusPlus/Info.plist` / `.entitlements`
- `scripts/*`（除非 pbxproj 脚本需要为新资源 patch，按 `AGENTS.md §9/§12` 既定流程）

## 9. 「不要做」（新增）

按 `AGENTS.md §5.1` 已有规则继续生效，这一轮新加：

- 不要把 visibility / style prefs 存到 `missings.json`（records 文件） — 用 `UserDefaults` 和 record 持久化分开。
- 不要在 popover 的 `…` 菜单里复制一份 style 切换 — 单一入口在 settings，避免双源真相。
- 不要在 `MissingStore.add` 里读 `AppPreferences.shared` — store 不碰 UI/prefs 状态（`AGENTS.md §5.1` 已有 spirit）。
- 不要让 `Picker` 在 visibility 关闭时变灰 — 用户应该能预选 style 后再开。

## 10. 风险 / 备注

- **项目无 git**：本 spec 写到文件即可，不 commit（不是 spec 阶段的事）。
- **pbxproj patch 风险**：`AGENTS.md §12` 提到 `scripts/patch-pbxproj.py` 之前有过幂等 bug，sentinel check 修过一版。这一轮两个新文件都是 `.swift`，按 §12 的 idempotent 流程走应该稳；如果遇到 ID 冲突，手 patch `project.pbxproj` 同样可行（4 处插入都参照 `MissingStore.swift` / `StorageService.swift` 现有的 block）。
- **macOS 26 + Xcode 26 限制**：`AGENTS.md §6` 提到 Xcode 26 构建的 Swift stdlib 不再 embed — 这一轮没动 `Info.plist` / `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES`，沿用现状。
- **`@Published didSet` 时机**：SwiftUI 对 `Binding` 写入是 transaction 内部完成的；`didSet` 在 `willSet` 之后、publisher 发之前，所以 UserDefaults 落盘和 notification post 都发生在 view 状态更新之后。安全。
