# 状态栏图标设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 settings 里加上"是否显示状态栏图标"开关和"图标样式"三选一 picker，改动立即生效，跨重启保留。

**Architecture:** 新增 2 个 service 文件（`AppPreferences` 用 UserDefaults 存 prefs + post notification；`MenuBarIconRenderer` 收 3 种渲染路径并清残影），`AppDelegate` 拆掉 inline 渲染改走 renderer + 监听 prefs 变化装卸 statusItem，`SettingsView` 加一个 section，pbxproj 注册 2 个新 Swift 文件。

**Tech Stack:** Swift 5 / AppKit / SwiftUI / UserDefaults / `NSStatusBar` / `NSStatusBarButton` / SF Symbols / Apple Color Emoji font。

**项目状态注意：**
- 项目**不是 git 仓库**（`AGENTS.md` 没建 .git），所以本计划**没有 commit 步骤**。每个任务做完后用文件存在性 + 编译验证来"打卡"，不 commit。
- 项目**没有 XCTest target**（`AGENTS.md §5.1` 明确禁止新增），所以本计划用"build 通过 + 运行时 screencapture 像素验证 + 行为清单"代替单测。

---

## Task 1: 新增 `AppPreferences.swift`

**Files:**
- Create: `MissingPlusPlus/Services/AppPreferences.swift`

- [ ] **Step 1: 写文件**

完整内容（按 spec §4.1）：

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

**注意**：
- 文件**不在 pbxproj 里**，所以这一步只是落盘，**不会参与编译**。可以独立安全做。
- `MenuBarIconStyle` 也放在这文件里 — 跟 `AppPreferences` 一起，是它的"值类型"伴生概念，不另开文件（避免 Task 1+2 之后再 patch pbxproj 多一次）。

- [ ] **Step 2: 验证文件落盘**

```bash
ls -la MissingPlusPlus/Services/AppPreferences.swift
wc -l MissingPlusPlus/Services/AppPreferences.swift
```

预期：文件存在，行数 ≥ 50。

- [ ] **Step 3: 确认未参与编译也不会失败**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build 2>&1 | tail -20
```

预期：`** BUILD SUCCEEDED **`。新文件没进 pbxproj，Xcode 不会编译它，但其它文件应该照常过。

---

## Task 2: 新增 `MenuBarIconRenderer.swift`

**Files:**
- Create: `MissingPlusPlus/Services/MenuBarIconRenderer.swift`

- [ ] **Step 1: 写文件**

完整内容（按 spec §4.2 + §4.3）：

```swift
import AppKit

/// Renders the menu bar icon in one of three styles (heart / emoji / 思字).
/// Each style branch is responsible for cleaning up any state left over
/// from the previous style — see `AGENTS.md §15/§19` for the "切回去留残影"
/// bug this prevents. The cleanup block at the top of `apply` resets
/// `image` / `title` / `attributedTitle` / `contentTintColor` before the
/// style-specific code runs.
@MainActor
enum MenuBarIconRenderer {
    static func apply(to button: NSStatusBarButton,
                      mood: Mood?,
                      style: MenuBarIconStyle) {
        // 1. 清上一种 style 残留 — 三种 style 共用的清场
        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.contentTintColor = nil

        // 2. mood 为 nil 时统一默认 happy 暖金（spec §4.3 确认的方案）
        let effectiveMood = mood ?? .happy

        switch style {
        case .heart:
            applyHeart(to: button, mood: effectiveMood)
        case .emoji:
            applyEmoji(to: button, mood: effectiveMood)
        case .character:
            applyCharacter(to: button, mood: effectiveMood)
        }
    }

    // MARK: - Heart (SF Symbol heart.fill + lockFocus + sourceAtop 染色)

    private static func applyHeart(to button: NSStatusBarButton, mood: Mood) {
        guard let base = NSImage(systemSymbolName: "heart.fill",
                                 accessibilityDescription: "心安日记") else {
            // SF Symbol 拿不到时降级到 emoji（避免 cell 空掉）
            button.title = mood.emoji
            button.font = NSFont(name: "AppleColorEmoji", size: 14)
                ?? NSFont.systemFont(ofSize: 14)
            return
        }
        let color = nsColor(for: mood)
        let coloured = NSImage(size: base.size)
        coloured.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: base.size)
        base.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)
        rect.fill(using: .sourceAtop)
        coloured.unlockFocus()
        coloured.isTemplate = false
        button.image = coloured
    }

    // MARK: - Emoji (mood.emoji + AppleColorEmoji 字体)

    private static func applyEmoji(to button: NSStatusBarButton, mood: Mood) {
        button.title = mood.emoji
        // AGENTS.md §18: 必须显式 AppleColorEmoji，否则 SF Pro 给 0 宽占位
        button.font = NSFont(name: "AppleColorEmoji", size: 14)
            ?? NSFont.systemFont(ofSize: 14)
    }

    // MARK: - 思字 (attributedTitle + SF Pro semibold + mood 颜色)

    private static func applyCharacter(to button: NSStatusBarButton, mood: Mood) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: nsColor(for: mood),
        ]
        button.attributedTitle = NSAttributedString(
            string: "思",
            attributes: attrs
        )
    }

    // MARK: - 颜色

    private static func nsColor(for mood: Mood) -> NSColor {
        switch mood {
        case .happy:     return NSColor(red: 1.00, green: 0.78, blue: 0.34, alpha: 1.0)
        case .joyful:    return NSColor(red: 0.43, green: 0.86, blue: 0.51, alpha: 1.0)
        case .delighted: return NSColor(red: 0.91, green: 0.12, blue: 0.39, alpha: 1.0)
        case .sad:       return NSColor(red: 0.36, green: 0.48, blue: 0.60, alpha: 1.0)
        case .longing:   return NSColor(red: 0.61, green: 0.45, blue: 0.81, alpha: 1.0)
        }
    }
}
```

- [ ] **Step 2: 验证文件落盘**

```bash
ls -la MissingPlusPlus/Services/MenuBarIconRenderer.swift
wc -l MissingPlusPlus/Services/MenuBarIconRenderer.swift
```

预期：文件存在，行数 ≥ 80。

- [ ] **Step 3: 确认未参与编译也不会失败**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build 2>&1 | tail -20
```

预期：`** BUILD SUCCEEDED **`。两个新文件都还没进 pbxproj，原工程保持可编译。

---

## Task 3: Patch `project.pbxproj` 注册 2 个新文件

**Files:**
- Modify: `MissingPlusPlus.xcodeproj/project.pbxproj`（4 处插入，共 8 行新增）

- [ ] **Step 1: 先备份**

```bash
cp MissingPlusPlus.xcodeproj/project.pbxproj MissingPlusPlus.xcodeproj/project.pbxproj.bak
```

- [ ] **Step 2: 用 Python 脚本做 4 处插入**

跑下面这个 Python 脚本（一次完成所有 4 处）：

```bash
python3 - << 'PY_EOF'
from pathlib import Path
p = Path('MissingPlusPlus.xcodeproj/project.pbxproj')
text = p.read_text()

# 用的 ID（与现有 ID 都不冲突）：
#   AppPreferences:        build A1000011, ref B1000011
#   MenuBarIconRenderer:   build A1000012, ref B1000012

BUILD_APP = "A1000011000000000000A001"
REF_APP   = "B1000011000000000000A001"
BUILD_REN = "A1000012000000000000A001"
REF_REN   = "B1000012000000000000A001"

# 1. PBXBuildFile section: 在 HistoryList 之后插 2 行
old_build_tail = "A1000009000000000000A001 /* HistoryList.swift in Sources */ = {isa = PBXBuildFile; fileRef = B1000009000000000000A001 /* HistoryList.swift */; };"
new_build_tail = old_build_tail + (
    f"\n\t\t{BUILD_APP} /* AppPreferences.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {REF_APP} /* AppPreferences.swift */; }};"
    f"\n\t\t{BUILD_REN} /* MenuBarIconRenderer.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {REF_REN} /* MenuBarIconRenderer.swift */; }};"
)
assert old_build_tail in text, "build tail not found"
text = text.replace(old_build_tail, new_build_tail, 1)

# 2. PBXFileReference section: 在 HistoryList 之后插 2 行
old_ref_tail = "B1000009000000000000A001 /* HistoryList.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryList.swift; sourceTree = \"<group>\"; };"
new_ref_tail = old_ref_tail + (
    f"\n\t\t{REF_APP} /* AppPreferences.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppPreferences.swift; sourceTree = \"<group>\"; }};"
    f"\n\t\t{REF_REN} /* MenuBarIconRenderer.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MenuBarIconRenderer.swift; sourceTree = \"<group>\"; }};"
)
assert old_ref_tail in text, "ref tail not found"
text = text.replace(old_ref_tail, new_ref_tail, 1)

# 3. Services PBXGroup children: 在 StorageService 之后插 2 行
old_grp = "B1000010000000000000A001 /* StorageService.swift */,\n\t\t\t);"
new_grp = (
    f"B1000010000000000000A001 /* StorageService.swift */,"
    f"\n\t\t\t{REF_APP} /* AppPreferences.swift */,"
    f"\n\t\t\t{REF_REN} /* MenuBarIconRenderer.swift */,"
    f"\n\t\t\t);"
)
assert old_grp in text, "services group tail not found"
text = text.replace(old_grp, new_grp, 1)

# 4. PBXSourcesBuildPhase files: 在 StorageService 之后插 2 行
old_src = "A1000010000000000000A001 /* StorageService.swift in Sources */,\n\t\t\t);"
new_src = (
    f"A1000010000000000000A001 /* StorageService.swift in Sources */,"
    f"\n\t\t\t{BUILD_APP} /* AppPreferences.swift in Sources */,"
    f"\n\t\t\t{BUILD_REN} /* MenuBarIconRenderer.swift in Sources */,"
    f"\n\t\t\t);"
)
assert old_src in text, "sources build phase tail not found"
text = text.replace(old_src, new_src, 1)

p.write_text(text)
print("OK: 4 sections patched")
PY_EOF
```

- [ ] **Step 3: 验证插入结果**

```bash
grep -n "AppPreferences.swift\|MenuBarIconRenderer.swift" MissingPlusPlus.xcodeproj/project.pbxproj
```

预期：8 行匹配（4 个 build/ref ID × 2 文件），分布在 4 个 section 里。

- [ ] **Step 4: 编译验证**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`。两个新 Swift 文件进编译，没有 import 错误。

- [ ] **Step 5: 失败回滚（如果上一步失败）**

```bash
cp MissingPlusPlus.xcodeproj/project.pbxproj.bak MissingPlusPlus.xcodeproj/project.pbxproj
```

回到原始 pbxproj 后**不要删备份**（Task 8 之前都保留，方便对比）。

---

## Task 4: `AppDelegate` 拆 inline 渲染 → 改走 `MenuBarIconRenderer`

**Files:**
- Modify: `MissingPlusPlus/MissingPlusPlusApp.swift`

- [ ] **Step 1: 替换 `installStatusItem` 末尾的 `applyMenuBarIcon` 调用**

文件 `MissingPlusPlus/MissingPlusPlusApp.swift` 的 `installStatusItem` 末尾原本是：

```swift
applyMenuBarIcon(mood: currentMood ?? .happy)
```

改成：

```swift
MenuBarIconRenderer.apply(
    to: button,
    mood: currentMood ?? .happy,
    style: AppPreferences.shared.menuBarIconStyle
)
```

- [ ] **Step 2: 替换 `handleMissingAdded` 里的 `applyMenuBarIcon` 调用**

原代码（`MissingPlusPlusApp.swift` 的 `handleMissingAdded`）：

```swift
@objc private func handleMissingAdded(_ note: Notification) {
    guard let missing = note.userInfo?["missing"] as? Missing else { return }
    currentMood = missing.mood
    applyMenuBarIcon(mood: missing.mood)
    postRecordNotification(for: missing)
}
```

改成（**和原行为对齐**，不加 mood-fade — 当前的 `scheduleMoodFade` 是个 no-op 空架子，timer 触发只调 `invalidate` 自己；AGENTS.md §13 描述的 CABasicAnimation 在当前代码里没实现，YAGNI 不补）：

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
    postRecordNotification(for: missing)
}
```

> 注意：原 inline `applyMenuBarIcon` 末尾有 `cancelMoodFade()`，搬到 renderer 后**没**保留（renderer 不该碰 AppDelegate 的 `moodFadeTimer`）。这等价于 no-op（moodFadeTimer 在非 popover 路径下基本是 nil），行为不变。

- [ ] **Step 3: 删除 `AppDelegate` 里的 `applyMenuBarIcon(mood:)` 和 `nsColor(for:)` 函数**

`MissingPlusPlus/MissingPlusPlusApp.swift` 当前有两段需要整段删除：

- 第一段：`/// 用 lockFocus + sourceAtop ...` 注释块开始 → `applyMenuBarIcon(mood:)` 函数结束 `}`
- 第二段：`nsColor(for:)` 整个函数体

**从 doc comment 开头到 `nsColor` 函数的结束 `}` 后那个空行止，全部删除**。删除后这一段应该是空行（保留前一个 `installStatusItem` 函数的结束 `}` 后面那个空行，作为新的 section 间隔）。

**具体做法**：用下面这个 Python 脚本（先写到 `/tmp/strip_appdelegate.py`，再跑）：

```bash
cat > /tmp/strip_appdelegate.py << 'INNER_EOF'
from pathlib import Path
import re
p = Path('MissingPlusPlus/MissingPlusPlusApp.swift')
text = p.read_text()
# 匹配从 doc comment 开头到 nsColor 函数结束的整段（含其后一个空行）
pat = re.compile(
    r'\n\t/// 用 lockFocus \+ sourceAtop 把 heart\.fill 染成 mood 颜色\.\n'
    r'\t/// \uff08[^\n]*\n'
    r'\t/// 所以必须把颜色烤进 bitmap\.\uff09\n'
    r'\tprivate func applyMenuBarIcon\(mood: Mood\) \{.*?\n\t\}\n'
    r'\n'
    r'\tprivate func nsColor\(for mood: Mood\) -> NSColor \{.*?\n\t\}\n',
    re.DOTALL,
)
m = pat.search(text)
assert m, 'block not matched — re-check file content'
text = pat.sub('\n', text, count=1)
p.write_text(text)
print('OK deleted', m.end() - m.start(), 'chars')
INNER_EOF
python3 /tmp/strip_appdelegate.py
```

删完再 grep 确认：

```bash
grep -n "applyMenuBarIcon\|nsColor(for:" MissingPlusPlus/MissingPlusPlusApp.swift
```

预期：只看到 `MenuBarIconRenderer.apply` 或 renderer 内的 `nsColor` 引用，**看不到** `func applyMenuBarIcon(mood:)` 或 `func nsColor(for:` 的定义。Task 5 还会动 `applicationDidFinishLaunching` 里最后一处 call site。

- [ ] **Step 4: 编译验证**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`。如果失败提示 "cannot find `applyMenuBarIcon` in scope" — 一定是 Step 1 或 2 没替换干净，回去检查。

- [ ] **Step 5: 行为不变验证（心形 default 仍渲染）**

启动一次 app，目测状态栏出现彩色 heart（happy 暖金 default，因为还没记录）。如果有 `screencapture` 工具可以：

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build
APP="/Users/tuzhipeng/Library/Developer/Xcode/DerivedData/MissingPlusPlus-gtavjnkeybhdnnfysnkcqzgorbra/Build/Products/Debug/MissingPlusPlus.app"
screencapture -x /tmp/menubar-pre.png
open "$APP"
sleep 2
screencapture -x /tmp/menubar-post.png
# 用 PIL ImageChops diff 验证有像素
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/menubar-pre.png').crop((2500, 0, 3024, 80)); b=Image.open('/tmp/menubar-post.png').crop((2500, 0, 3024, 80)); d=ImageChops.difference(a,b); bb=d.getbbox(); print('diff bbox:', bb, 'pixels:', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：`diff bbox` 是某个 x≈2668、y≈15-30 区间，pixels > 5000（说明图标确实可见）。如果 pixels ≈ 0 或 0 宽 dot，**回退到 Step 1 看 renderer 是不是没接到**。

---

## Task 5: `AppDelegate` 加 visibility guard + `handlePrefsChanged`

**Files:**
- Modify: `MissingPlusPlus/MissingPlusPlusApp.swift`

- [ ] **Step 1: 改 `applicationDidFinishLaunching` — 状态栏按 prefs 决定挂不挂**

原 `applicationDidFinishLaunching`（`MissingPlusPlusApp.swift`）：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    installAppMenu()
    installStatusItem()
    installGlobalHotKey()
    // 反映最近一次 mood
    if let latest = MissingStore.shared.sortedItems.first {
        currentMood = latest.mood
        applyMenuBarIcon(mood: latest.mood)
    }
    // 监听新记录
    NotificationCenter.default.addObserver(...)
    // 监听设置入口
    NotificationCenter.default.addObserver(...)
}
```

改成（**注意 applyMenuBarIcon(mood:) 已经删了，调用要拿掉**）：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    installAppMenu()
    installGlobalHotKey()
    // 反映最近一次 mood（不直接画 — installStatusItem 内部会画）
    if let latest = MissingStore.shared.sortedItems.first {
        currentMood = latest.mood
    }
    // 状态栏只在"用户允许"时挂
    if AppPreferences.shared.showStatusItem {
        installStatusItem()
    }
    // 监听新记录
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleMissingAdded(_:)),
        name: .missingStoreDidAdd,
        object: nil
    )
    // 监听设置入口
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleOpenSettings(_:)),
        name: .openSettings,
        object: nil
    )
    // 监听 prefs 变化
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handlePrefsChanged(_:)),
        name: .appPreferencesDidChange,
        object: nil
    )
}
```

- [ ] **Step 2: 新增 `handlePrefsChanged` 方法**

在 `MissingPlusPlusApp.swift` 的 `// MARK: - 新增记录` 上面新增一个 `// MARK: - 状态栏 prefs 变化` section，写：

```swift
// MARK: - 状态栏 prefs 变化

@objc private func handlePrefsChanged(_ note: Notification) {
    let prefs = AppPreferences.shared
    if prefs.showStatusItem {
        if statusItem == nil {
            installStatusItem()
        } else {
            // statusItem 还在 — 用当前 mood + 新 style 立刻重画
            MenuBarIconRenderer.apply(
                to: statusItem!.button!,
                mood: currentMood ?? .happy,
                style: prefs.menuBarIconStyle
            )
        }
    } else {
        // 先关 popover（如果还开着），再卸 statusItem，避免 anchor 没了留 orphan
        popover?.performClose(nil)
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 4: 手动验证 visibility 默认行为不变**

```bash
# 启动 app — 状态栏应该照常出现（默认 visibility = true）
APP="/Users/tuzhipeng/Library/Developer/Xcode/DerivedData/MissingPlusPlus-gtavjnkeybhdnnfysnkcqzgorbra/Build/Products/Debug/MissingPlusPlus.app"
open "$APP"
sleep 2
# screencapture + ImageChops，期望有可见像素（和 Task 4 Step 5 同款）
```

预期：状态栏仍有心形图标。  
退出 app（⌘Q 或 `osascript -e 'tell app "MissingPlusPlus" to quit'`）。

- [ ] **Step 5: 手动验证 visibility 关闭路径（手动改 UserDefaults 模拟）**

```bash
# 关掉 app 后写 prefs
defaults write com.tuzhipeng.MissingPlusPlus ShowStatusItem -bool false
# 再启动
open "$APP"
sleep 2
# screencapture 验证状态栏**没有**图标
screencapture -x /tmp/menubar-hidden.png
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/menubar-pre.png'); b=Image.open('/tmp/menubar-hidden.png'); d=ImageChops.difference(a,b); print('diff pixels:', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：状态栏在 icon 位置**没有新像素**（diff 接近 0），说明 statusItem 没挂上。

```bash
# 恢复 prefs + 退出 app
defaults delete com.tuzhipeng.MissingPlusPlus ShowStatusItem
osascript -e 'tell app "MissingPlusPlus" to quit'
```

- [ ] **Step 6: 手动验证 ⌘, 在隐藏状态下仍能开 settings**

```bash
open "$APP"
sleep 2
# 此时 prefs ShowStatusItem = true（刚 delete 掉），状态栏有图标
# 用 osascript 模拟 ⌘,
osascript -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
# screencapture 看是否有 settings 窗口
screencapture -x /tmp/settings-open.png
# 用户目测 / 或用 osascript 列窗口
osascript -e 'tell application "System Events" to get name of every window of (every process whose name contains "MissingPlusPlus")'
```

预期：出现"心安日记 设置"窗口。

- [ ] **Step 7: 退出 app**

```bash
osascript -e 'tell app "MissingPlusPlus" to quit'
```

---

## Task 6: `SettingsView` 加 `menuBarSection`

**Files:**
- Modify: `MissingPlusPlus/Views/SettingsView.swift`

- [ ] **Step 1: 加 `@ObservedObject prefs` 属性**

文件 `MissingPlusPlus/Views/SettingsView.swift` 在 `struct SettingsView: View {` 后、`@ObservedObject var store: MissingStore` 之后加：

```swift
@ObservedObject var prefs = AppPreferences.shared
```

- [ ] **Step 2: 在 `body` 里把 `menuBarSection` 插到 `storageSection` 和 `dataSection` 之间**

`body` 原代码：

```swift
var body: some View {
    Form {
        storageSection
        dataSection
        aboutSection
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 560)
    .alert(...)
}
```

改成：

```swift
var body: some View {
    Form {
        storageSection
        menuBarSection
        dataSection
        aboutSection
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 600)
    .alert(...)
}
```

- [ ] **Step 3: 新增 `menuBarSection` computed property**

在 `// MARK: - 存储位置` 之前新增一个 `// MARK: - 状态栏` section，写：

```swift
// MARK: - 状态栏

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

- [ ] **Step 4: 编译验证**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug build 2>&1 | tail -10
```

预期：`** BUILD SUCCEEDED **`。如果提示 `AppPreferences` / `MenuBarIconStyle` 找不到 — 检查 Task 1 是不是文件没落盘或 pbxproj 没插对。

---

## Task 7: 完整构建验证（Debug + Release）

**Files:** (none)

- [ ] **Step 1: Debug build**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Debug clean build 2>&1 | tail -15
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 2: Release build**

```bash
xcodebuild -project MissingPlusPlus.xcodeproj -scheme MissingPlusPlus -configuration Release build 2>&1 | tail -15
```

预期：`** BUILD SUCCEEDED **`。

- [ ] **Step 3: 失败排错**

如果 release 失败但 debug 过 — 通常是 Swift 6 strictness 或 release 优化下的类型推断问题。看具体报错，回到对应任务修。

---

## Task 8: 运行时端到端验证

**Files:** (none)

- [ ] **Step 1: 启动 app（debug build）**

```bash
APP="/Users/tuzhipeng/Library/Developer/Xcode/DerivedData/MissingPlusPlus-gtavjnkeybhdnnfysnkcqzgorbra/Build/Products/Debug/MissingPlusPlus.app"
defaults delete com.tuzhipeng.MissingPlusPlus 2>/dev/null  # 清 prefs 走 default
open "$APP"
sleep 2
```

- [ ] **Step 2: 打开 settings（⌘,）**

```bash
osascript -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
screencapture -x /tmp/settings.png
```

**目测** settings 窗口，看到 4 个 section：存储位置 / 状态栏 / 数据 / 关于。状态栏 section 有 "在状态栏显示图标" toggle（默认开）和 "图标样式" picker（默认心形）。

- [ ] **Step 3: 心形 style 像素验证（baseline）**

```bash
screencapture -x /tmp/style-heart-pre.png
sleep 1
screencapture -x /tmp/style-heart.png
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/style-heart-pre.png').crop((2400, 0, 3024, 80)); b=Image.open('/tmp/style-heart.png').crop((2400, 0, 3024, 80)); d=ImageChops.difference(a,b); bb=d.getbbox(); print('heart: bbox=', bb, 'px=', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：bbox 在 x≈2660 附近，px > 5000。

- [ ] **Step 4: 切到 emoji style**

在 settings 窗口里用 AppleScript 把 picker 切到 "Emoji"（`AGENTS.md §16/§20` — 用 osascript 不便模拟 Picker 点击，可手动：

1. 鼠标点 picker
2. 选 "Emoji"

）然后：

```bash
sleep 1
screencapture -x /tmp/style-emoji.png
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/style-heart-pre.png').crop((2400, 0, 3024, 80)); b=Image.open('/tmp/style-emoji.png').crop((2400, 0, 3024, 80)); d=ImageChops.difference(a,b); bb=d.getbbox(); print('emoji: bbox=', bb, 'px=', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：bbox 在 x≈2660 附近，px > 5000。如果是 0 宽 dot（`AGENTS.md §18`）— 退回看 renderer 里的 `applyEmoji` 是不是漏了 `AppleColorEmoji` 字体。

- [ ] **Step 5: 切到 思字 style**

同样手动切：

```bash
sleep 1
screencapture -x /tmp/style-char.png
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/style-heart-pre.png').crop((2400, 0, 3024, 80)); b=Image.open('/tmp/style-char.png').crop((2400, 0, 3024, 80)); d=ImageChops.difference(a,b); bb=d.getbbox(); print('char: bbox=', bb, 'px=', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：bbox 在 x≈2660 附近，px > 5000。

- [ ] **Step 6: 验证三 style 切换不留残影**

```bash
# 从 思字 切回 心形，再 screencapture
sleep 1
screencapture -x /tmp/style-heart-back.png
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/style-heart.png'); b=Image.open('/tmp/style-heart-back.png'); d=ImageChops.difference(a,b); bb=d.getbbox(); print('heart back: bbox=', bb, 'px=', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：和原 heart 几乎相同，px < 500（微小像素差可接受，比如 alpha 残留）。

- [ ] **Step 7: 验证 visibility toggle off**

settings 里把"在状态栏显示图标"关掉：

```bash
sleep 1
screencapture -x /tmp/vis-off.png
python3 -c "from PIL import Image, ImageChops; a=Image.open('/tmp/style-heart.png').crop((2400, 0, 3024, 80)); b=Image.open('/tmp/vis-off.png').crop((2400, 0, 3024, 80)); d=ImageChops.difference(a,b); print('vis-off diff px:', sum(1 for p in d.getdata() if any(c>10 for c in p)))"
```

预期：vis-off 状态栏位置**没有新像素**（diff px ≈ 0）。

- [ ] **Step 8: 验证 visibility 关闭时 ⌘, 仍能开 settings**

```bash
osascript -e 'tell application "System Events" to keystroke "," using command down'
sleep 1
osascript -e 'tell application "System Events" to get name of every window of (every process whose name contains "MissingPlusPlus")'
```

预期：能看到 "心安日记 设置" 窗口名 — 即使状态栏图标关了 settings 也能开（`AGENTS.md §17` 兜底）。

- [ ] **Step 9: 验证 visibility 关闭时 Dock / ⌥M 仍能开主窗口**

```bash
# ⌥M
osascript -e 'tell application "System Events" to keystroke "m" using option down'
sleep 1
osascript -e 'tell application "System Events" to get name of every window of (every process whose name contains "MissingPlusPlus")'
```

预期：能看到 "心安日记" 主窗口。

- [ ] **Step 10: 重启 app 验证 prefs 持久化**

```bash
osascript -e 'tell app "MissingPlusPlus" to quit'
# 在 settings 里手动把"在状态栏显示图标"重开 + 选 思字 style（如果还没）
defaults read com.tuzhipeng.MissingPlusPlus  # 应该看到 ShowStatusItem=0 + MenuBarIconStyle=character
open "$APP"
sleep 2
screencapture -x /tmp/restart.png
# 期望 statusItem 重新挂上、style = 思字
```

预期：状态栏重新出现 "思" 字（暖金 happy default，因为还没记录）。

- [ ] **Step 11: 记一条新记录，验证 mood 联动（每种 style 各一次）**

```bash
# 默认 思字 style + happy 暖金色 — 记一条
osascript -e 'tell application "System Events" to keystroke "m" using option down'  # ⌥M 开主窗口
sleep 1
# 填表 + 提交：手动操作或用 osascript 模拟
# 提交后 8s 内 screencapture 验证图标已更新
screencapture -x /tmp/after-record.png
```

预期：主窗口里提交一条记录，状态栏"思"字颜色变成新 mood 的颜色（如果选了不同 mood）。8s 后开始 fade 到 0.55 alpha（`AGENTS.md §13`）。

- [ ] **Step 12: 退出 app**

```bash
osascript -e 'tell app "MissingPlusPlus" to quit'
```

---

## Task 9: 清理（可选）

**Files:** (none)

- [ ] **Step 1: 删除 pbxproj 备份**

```bash
rm MissingPlusPlus.xcodeproj/project.pbxproj.bak
```

---

## Self-Review

1. **Spec 覆盖**：
   - §4.1 `AppPreferences` + `Notification.Name` — Task 1 ✓
   - §4.2 `MenuBarIconRenderer` 抽离 + 清残影 — Task 2 ✓
   - §4.3 三种 style 渲染 — Task 2 内 3 个 helper ✓
   - §4.4 AppDelegate 4 处改动 — Task 4 + Task 5 ✓
   - §4.5 SettingsView 新 section + frame 480×600 — Task 6 ✓
   - §6 错误处理 / 边界 — Task 5 Step 1 (popover.performClose before removeStatusItem), Task 5 Step 4 (default = true 时行为不变), Task 1 init 用 `?? default` 兜底 ✓
   - §7 测试 / 验证 — Task 7 build + Task 8 运行时 ✓
   - §8 改动文件 — Task 1/2 (新增) + Task 3 (pbxproj) + Task 4/5/6 (改) ✓
   - §9 不要做 — 反映在 Step 里（"不要让 Picker 灰" → Task 6 Step 3 不加 `.disabled`）✓
   - §10 风险 — Task 3 Step 5 给出回滚路径 ✓

2. **Placeholder scan**：无 "TBD" / "TODO" / "类似 Task N" / "适当 error 处理"。

3. **Type consistency**：
   - `AppPreferences.shared.menuBarIconStyle` 跨 Task 1/4/5/6 一致。
   - `MenuBarIconStyle.heart/emoji/character` rawValue 与 Task 1 init 的 `"heart"` 兜底一致。
   - `Notification.Name.appPreferencesDidChange` 在 Task 1 定义、Task 5 监听，名字一致。
   - `MenuBarIconRenderer.apply(to:mood:style:)` 签名在 Task 2 定义、Task 4/5 调用，参数一致。
   - `AppPreferences.shared.showStatusItem` 在 Task 1 定义、Task 5/6 读，名字一致。
