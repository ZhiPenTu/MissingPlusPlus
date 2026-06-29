# Missing++ 项目级 Codex 准则

> 本文件只追加项目级约束；全局 `Codex 行为准则`（来自 Codex 配置）依然有效，下面不重复通用规则。

## 1. 项目形态

- macOS 菜单栏（Menu Bar）App，中文产品名 `思念计数器`。
- Bundle ID：`com.tuzhipeng.MissingPlusPlus`；Swift `5.0`；`MACOSX_DEPLOYMENT_TARGET` 见 Xcode 工程（工程里同时存在 `13.0` 与 `26.0` 两个值，按实际 target 配置为准）。
- `Info.plist` 中 `LSUIElement = true`（无 Dock 图标）。
- `MissingPlusPlus.entitlements` 已开启 App Sandbox（`app-sandbox` + `files.user-selected.read-write`）。

## 2. 目录与职责

所有 Swift 源码集中在 `MissingPlusPlus/` 下，Xcode 工程在 `MissingPlusPlus.xcodeproj/`。

- `MissingPlusPlus/MissingPlusPlusApp.swift`
  - `MissingPlusPlusApp`：SwiftUI `App` 入口，body 使用 `Settings { EmptyView() }`。
  - `AppDelegate`：通过 `NSApplicationDelegateAdaptor` 注入，承载 status item、popover、Carbon 全局快捷键、主窗口。
- `MissingPlusPlus/Models/`
  - `Missing.swift`：记录模型（`id`, `who`, `mood`, `intensity`, `createdAt`）。
  - `Mood.swift`：5 种心情枚举 + emoji + 中文 label。
  - `Intensity.swift`：3 档程度枚举 + 中文 label。
- `MissingPlusPlus/Services/MissingStore.swift`
  - 单例 `@MainActor ObservableObject`，`items` / `knownWhos` 公开只读。
  - 写入仅通过 `add(_:)` / `delete(_:)`，每次写入都会落盘 JSON 并 `rebuildKnownWhos()`。
- `MissingPlusPlus/Views/`
  - `MenuBarContent.swift`：弹窗根视图，组合 `NewMissingForm` + `HistoryList`。
  - `NewMissingForm.swift`：新建表单，含私有子视图 `WhoField` / `MoodPicker`。
  - `HistoryList.swift`：最近 50 条历史 + `emptyState`。

新增文件请维持以上分层；持久化逻辑不要写到 `Views/`。

## 3. 关键运行时不变量

- **持久化路径**：`~/Library/Application Support/MissingPlusPlus/missings.json`，位于 App Sandbox 容器内。任何导出 / 备份请走 `NSSavePanel`（命中 `files.user-selected.read-write`），不要直接写 `Documents` / `Downloads`。
- **状态栏图标**：当前是 `button.title = "❤️"`（NSLog 里能看到 frame / visible 调试输出）。如要换成 `NSImage`，必须使用 template 模式（`button.image = templateImage; imagePosition`），否则会丢失 light/dark 适配。
- **全局快捷键**：`kVK_ANSI_M` + `optionKey`（⌥M），EventHotKey 签名 `0x4D53504D`（`MSPM`）。Carbon 回调里只 `DispatchQueue.main.async` 派发，不要在回调里直接改 UI / `AppKit` 状态。
- **窗口复用**：`MenuBarContent` 同时挂在 popover（360×720）和主窗口，主窗口用 `setFrameAutosaveName("MainWindow")` 记忆位置 —— SwiftUI 侧不要重复存 frame。
- **数据兼容**：`Missing` / `Mood` / `Intensity` 用 `Codable` 默认策略，`JSONDecoder` 没有自定义 `dateDecodingStrategy`。改字段前评估对老 `missings.json` 的兼容。
- **UI 文案**：中文 label 和 emoji 是产品的一部分，不要本地化或替换成 SF Symbol 占位。

## 4. 验证清单（改动后必须跑过）

- [ ] Xcode `Product → Build` 通过。
- [ ] 启动后状态栏出现 `❤️`，控制台能看到 `[Missing++] final: visible=1`。
- [ ] 提交一条记录 → 完全退出 App → 重新打开，历史仍然存在。
- [ ] 状态栏点击 = 弹出 popover；⌥M = 主窗口显隐切换，主窗口位置被记住。
- [ ] 删除 `missings.json` 后启动 App，列表走 `emptyState`（"还没有记录 / 想念的时候就来记一笔吧"）。

## 5. 不要做

## 5.1 不要做（这一轮的）

- 不要在 macOS 上尝试 `NSStatusItem.button` 重赋 / KVC 设值：read-only 走的是私有 selector，应用升级后会炸。右键菜单需求用其他路径（popover `…` 按钮、菜单栏二级菜单等）。
- 不要在 popover action 同一 tick 同步调 `showPopover()`：NSPopover 在菜单栏点击时会"闪一下就关"。`DispatchQueue.main.async` 推到下一个 runloop tick。
- 不要在 `MissingStore.add` 里直接调用 UI 更新（`NSLog` / `button.image =`）：store 可能在 main-actor 之外被调用，UI 更新要走 `NotificationCenter` 在 AppDelegate（@MainActor 范围内）接。


- 不要绕过 `MissingStore` 直接改 `items`。
- 不要在 SwiftUI 视图里发网络请求或启动后台任务 —— 当前是完全离线的单进程菜单栏 App。
- 不要新增 XCTest / UI 测试 target，除非同步修改 `project.pbxproj`。
- 不要引入 Swift Package / CocoaPods / Carthage 依赖，除非用户明确要求。
- 不要在没和用户确认的情况下改 `Info.plist` / `entitlements` / 部署目标。

## 6. 打包

- 脚本：`scripts/build-dmg.sh`（xcodebuild Release → ad-hoc 重新签名 → stage → `hdiutil create -format UDZO` → verify + mount smoke test）。
- 输出：`dist/MissingPlusPlus-1.0.dmg`。
- 关键注意点：
  - Xcode 26 构建时 Swift 6 stdlib 不再打进 `.app`，所以本 DMG **只能在 macOS 26+ 上运行**。如果要让 13/14/15 跑，需要在工程里加 `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES` 并重新打包。
  - 当前使用 **ad-hoc 签名**（`codesign -s -`），目的是在没有 Developer ID 的情况下也能在本地双击安装。要正式分发给其他 Mac 用户，需要切到 Developer ID 签名 + `notarytool` 公证。
  - 工程里 `MACOSX_DEPLOYMENT_TARGET` 存在 13.0 和 26.0 两个值，Release 实际按 26.0 出包，Debug 按 13.0；这是工程层面的不一致，未来要么统一，要么按意图把 13.0 那个改掉。

## 7. 图标

- 生成脚本：`scripts/make-icons.py`（Pillow + numpy-free gradient，输出到 `build/icon-source/`，最终把 `AppIcon.icns` 和 `MenuBarIcon.png` 复制到 `MissingPlusPlus/Resources/`）。
- 应用图标（`MissingPlusPlus/Resources/AppIcon.icns`）：1024×1024 master 渲染后降采样到 16/32/64/128/256/512/1024 的 1x/2x 全套，再 `iconutil -c icns` 打包；通过 `Info.plist` 的 `CFBundleIconFile = AppIcon` 引用。
- 菜单栏图标（`MissingPlusPlus/Resources/MenuBarIcon.png`）：44×44 @2x 的 template 风格单色心形；`AppDelegate.installStatusItem()` 用 `Bundle.main.image(forResource:)` 加载，标 `isTemplate = true` 走系统 light/dark tint。
- `project.pbxproj` 的资源挂载是手 patch 的，对应脚本是 `scripts/patch-pbxproj.py`（idempotent）。`MissingPlusPlus` group 下新增了 `Resources` 子 group，文件类型分别是 `image.icns` / `image.png`。
- 设计风格：粉→珊瑚红渐变 squircle + 白色心形 + 柔和高光 / 阴影。如要改色，编辑 `make-icons.py` 里的 `vertical_gradient` 两个端点。
- 当前没有 asset catalog (`.xcassets`)。若以后想加 `AppIcon.appiconset` 多 slot，需要把 `AppIcon.icns` 替换成 Contents.json + 多张 PNG。

## 8. 菜单栏 click bug 修复

- 早期版本里 `togglePopover` 同步调 `showPopover`，是 NSPopover 在菜单栏点击时经典的"闪一下就关"陷阱 — click 的 mouseUp 还在处理中，popover 的 transient 行为把它当 outside click 立刻关掉。
- 现在 `togglePopover` 把开 / 关都 `DispatchQueue.main.async` 推到下一个 runloop tick；`showPopover` 改用 `popover.behavior = .semitransient`、去掉 `makeKey()`、并强制 `host.view` 提前加载，避免 popover 第一次 show 时视图还没 ready。
- 验证：用户截图确认 popover 出现并能交互（之前只有 ⌥M 能开主窗口）。

## 9. Asset Catalog 改造

- `AppIcon.icns` 已经被 `MissingPlusPlus/Resources/Assets.xcassets/AppIcon.appiconset/` 取代。`Info.plist` 用 `CFBundleIconName = AppIcon` 指向 asset catalog，不再有 `CFBundleIconFile`。
- 编译产物是 `Assets.car`（≈200KB）+ `AppIcon.icns`（≈30KB），都在 `.app/Contents/Resources/`。
- 改造脚本 `scripts/patch-pbxproj.py`（idempotent）负责把 `.xcassets` 和 5 个 mood PNG 挂到 PBXFileReference / PBXBuildFile / PBXResourcesBuildPhase。**注意：菜单栏状态的恢复逻辑在 `applicationDidFinishLaunching` 里读 `MissingStore.shared.sortedItems.first` 拿最近一次 mood**，这样重启后菜单栏颜色能跟上。

## 10. 5 个 mood 彩色菜单栏图标

- 生成在 `MissingPlusPlus/Resources/MenuBarIcon-{mood}-{1x,2x,3x}.png`（22/44/66 三档）+ 同名无 scale 后缀的主入口（如 `MenuBarIcon-sad.png` 是 2x）。
- 调色（`make-icons.py` 里的 `MOOD_PALETTE`）：
  - happy: 暖金 → 橙 (`#FFC857` → `#FF9F43`)
  - joyful: 草绿 (`#6EDC82` → `#34BB64`)
  - delighted: 玫红 → 珊瑚 (`#E91E63` → `#FF6982`)
  - sad: 钢蓝 (`#5B7A99` → `#426082`)
  - longing: 薰衣草紫 (`#9B72CF` → `#7B54AF`)
- 菜单栏图标的更新流程：`MissingStore.add(_:)` post `.missingStoreDidAdd` 通知，AppDelegate 的 `handleMissingAdded` 收到后调 `updateMenuBarIcon(for:)`，把 `button.image` 设成对应 mood 的彩色 PNG（`isTemplate = false`）。冷启动时也读一次 disk，把最近一次的 mood 应用上去。
- 默认 / 没有任何 entry 时走 `MenuBarIcon.png`（白心 + 透明背景，`isTemplate = true`），系统根据菜单栏 light/dark 自动着色。

## 11. Developer ID 签名 + 公证

- 脚本：`scripts/build-dmg.sh`，默认 ad-hoc。设置 `DEVELOPER_ID=1` 进 Developer ID 模式：手动 `CODE_SIGN_IDENTITY=Developer ID Application` 签名、`xcrun notarytool submit` 提交、`xcrun stapler staple` 钉回 ticket。
- 走 Developer ID 模式前需要：
  1. 加入 Apple Developer Program（$99/年）。
  2. Xcode → Settings → Accounts → Manage Certificates 里签发 `Developer ID Application` 证书。
  3. `https://appleid.apple.com` 申请一个 **app-specific password**。
  4. 跑 `xcrun notarytool store-credentials <profile> --apple-id <you> --team-id <TEAMID> --password <app-pw>` 存到 keychain（profile 名默认 `missingpp-notary`，可通过 `NOTARY_PROFILE` 覆盖）。
  5. 准备好后 `DEVELOPER_ID=1 DEVELOPMENT_TEAM=<TEAMID> bash scripts/build-dmg.sh` 跑一遍，会自动签名 + 公证 + 钉 ticket。
- 当前你只有 Apple Development 证书，没有 Developer ID，所以这条线还没实跑过；脚手架是 ready 的。

## 12. 通知 / 统计 / 搜索 / 替代 App Icon（第二轮优化）

- **记录通知**：`UNUserNotificationCenter` 在 `MissingStore.add` 后由 `AppDelegate.postRecordNotification(for:)` post。Title 是 `想念 <对象>`，body 是 `心情：<label>　程度：<label>`，attach 了对应 mood 的 menu-bar PNG 作为通知图标（拷贝到 `tmp/` 后再 attach，避开了 `Bundle.main.url` 直接 attach 在 sandbox 里被系统拒的问题）。
- **统计 tab**：`Views/StatisticsView.swift` 用 `Timer.publish(every: 60)` 跑表，显示累计 / 本周 / 平均强度 / Top 3 思念对象。`MenuBarContent` 改成三 tab：新建 / 统计 / 历史（segmented picker 风格，0.15s 切换动画）。
- **历史搜索**：`HistoryList` 顶部加了一个 `magnifyingglass` + `TextField` 的小搜索框，按 `who` 做 `localizedCaseInsensitiveContains` 过滤；空状态文案根据是否有 query 切换。
- **关于 / 退出**：`Commands` modifier 加了 ⌘Q 退出；popover tab bar 右侧加了一个 `…` 菜单按钮（`PopoverOverflowMenu.swift`），里面是 `NSApp.orderFrontStandardAboutPanelWithOptions`（关于 + 自定义 credits）+ 退出。
- **替代 App Icon**：`make-icons.py` 现在额外生成 5 个 mood 的 `.iconset` + `.icns`（用 mood 调色板染色，存到 `build/icon-source/AppIcon-{mood}.icns`），通过 `Resources/` 打进 bundle（`B0000020..A0000024` 这些是 alt icon 的 build / ref ID）。**注意：macOS 没有公开 API 运行时切换 App Icon**（iOS 有 `setAlternateIconName`，macOS 没有），所以目前这些 `.icns` 只是 bundle 里就绪，未来若 Apple 加了 macOS 等价 API，或者走 `CFBundleSetIconsForMacApp` 私有路径，可以直接用。
- **pbxproj idempotency 修了一版**：`scripts/patch-pbxproj.py` 之前用 "ID 在 text 里就 skip" 做幂等，结果 PBXBuildFile 段先于 PBXFileReference 段插时，ID 已经在 build file 里出现过导致 file ref 被跳过。改成 sentinel 检查（找完整 `= {isa = ...` 行）后稳了。`--force` 可绕过幂等。

## 13. Trend chart + 自动褪色 + Sparkle 脚手架（第三轮优化）

- **统计 trend chart**：`StatisticsView` 新增 30 天 stacked bar chart，用 `import Charts`（macOS 13+ 内建）。按日期 x 轴堆叠 5 种 mood 颜色，配色集中放在 `MoodColor.forMood(_:)` 里，和 `make-icons.py` 的 `MOOD_PALETTE` 端点保持一致。空数据时显示"近 30 天还没有记录"占位文案。
- **菜单栏自动褪色**：记录后 mood 颜色的菜单栏图标显示 8 秒，然后 1.2s `CABasicAnimation(opacity)` ease-in-out 渐变到 0.25 透明度（让下面的 neutral template 隐约透出）。任何点击（`togglePopover`）和冷启动都会 `cancelMoodFade()` 还原满透明度，并 `layer.removeAnimation(forKey:)` 立刻清掉。Timer 用 `Timer.scheduledTimer` + `[weak self, weak button]`，按记录会 reschedule。
- **右键菜单（dropped）**：想用 `NSStatusBarButton` 子类区分左右键，但 `NSStatusItem.button` 是 read-only，没有公开 API 替换。私有 `_setButton:` / 自定义 view 路径都太侵入。`About + Quit` 已经走 popover 的 `…` 菜单，差距不大；这条等以后真要"快速记一笔"再加。**已记入「不要做」**：不要在 macOS 上尝试 `NSStatusItem.button` 重赋。
- **Sparkle 脚手架**：`scripts/build-with-sparkle.sh` 检测 `xcodebuild / brew / generate_appcast / sign_update`，生成 `dist/appcast.xml.template`（item 1.0 的样子，含 EdDSA 签名占位符），打印 Sparkle 需要的 Info.plist keys（`SUFeedURL / SUEnableAutomaticChecks / SUPublicEDKey`），列了 4 步实际接入清单（生成 EdDSA keypair → vendoring `Sparkle.framework` → 把 `SPUUpdater` 接到 `…` 菜单的"检查更新"上 → host appcast）。**没有真实接入** —— 你没给 appcast 托管 URL，我也没 sign up Sparkle 账号，这条线等基础设施准备好再走。

## 14. 菜单栏图标"小蓝点"bug 修复

**根因**：`Bundle.main.image(forResource:)` 加载一个 44x44 px @2x retina PNG 时，返回的 `NSImage` 的 `size` 是 **(44, 44)**（把像素当成了点）。`NSStatusBarButton` 用 `squareLength` 把 width 锁在 22pt，但 height 会按 image size 长到 44pt —— **比 24pt 高的菜单栏还高**，于是只有图像顶端 1-2pt 从菜单栏里漏出来，看上去是一个**小蓝点**而不是心。

**修复**（`AppDelegate.installStatusItem` + `updateMenuBarIcon`）：

```swift
if let image = Bundle.main.image(forResource: "MenuBarIcon") {
    // 44x44 px @2x retina, so its logical size is 22x22 pt. Without
    // this, the system sizes the button to fit the pixel dimensions
    // and the icon extends below the menu bar.
    image.size = NSSize(width: 22, height: 22)
    image.isTemplate = true
    button.image = image
}
```

**验证手段**（如果将来再怀疑）：
- 启 app 后 `screencapture -x` 截整屏，`ImageChops.difference` baseline + with-app 的 top 80px
  - 修复前 diff = 452 像素（x=2668..2711, y=19..45），是直径 ~6px 的小蓝点
  - 修复后 diff = 65,729 像素（x=0..3023, y=15..79），整张心形都在
- NSLog 加 `image.size` + `image.frame`：
  - 修复前 `image.size=Optional((44.0, 44.0))`、`frame=(0.0, 0.0, 22.0, 44.0)`
  - 修复后 `image.size=Optional((22.0, 22.0))`、`frame=(0.0, 0.0, 22.0, 22.0)`

**关联历史**（AGENTS.md §5.1）：这条之前其实踩过：早期用 `imageScaling = .scaleProportionallyDown` 时也长成 22x44，但用户那会儿用了 emoji 文字 emoji 路径绕过去了；后来换成真 PNG 才暴露 image.size 这个根本问题。

**不要做**（新增）：不要在 `installStatusItem` 里设 `imageScaling = .scaleProportionallyDown` 或 `.scaleToFit`，让 AppKit 用默认行为 + 显式 `image.size` 即可。

## 15. 菜单栏回退到 button.title = emoji

**改回原因**：上一轮修的"image.size=(22,22) + 丢 imageScaling" 确实把 PNG 顶起来了，但 `Bundle.main.image(forResource:)` 拿到的 44x44 px @2x retina PNG 默认 size 是 (44, 44)（像素当点用），即便打了 size 也容易在不同 OS / 不同 Xcode 组合下再翻车。你也直接说"早期 text emoji 方案就挺好"。

**最终方案**：
- 菜单栏图标用 `button.title = mood.emoji`，每个 `Mood` 自带的 emoji 走系统的 Apple Color Emoji 字体，自带配色（开心黄😊、愉悦绿😄、欢乐粉🥰、难过蓝😢、思念紫🥺），mood 联动保留，**完全绕开 NSImage sizing 那条坑**。
- `installStatusItem` 改回简单的 `button.title = currentMood?.emoji ?? "❤️"` + `NSFont.systemFont(ofSize: 16)`，不带任何 image 路径。
- `updateMenuBarIcon(for:)` 同样：`button.title = mood.emoji` 一行。
- **auto-fade 目标值从 0.25 调高到 0.55** —— emoji 在 0.25 alpha 下太弱看不清，0.55 还能保留 mood 提示；点击 / 新记录触发 `cancelMoodFade()` 立刻还原到 1.0。

**保留的东西**：
- `Resources/MenuBarIcon-{mood}-{1x,2x,3x}.png` + `AppIcon-{mood}.icns` 还留在 bundle 里（之前那么多轮生成的资源），未来想切回 PNG / SF Symbol 路线时不用重新生成。
- `MoodColor.forMood(_:)` 也保留，给 `StatisticsView` 的 30-day trend chart 用，配色和 menu bar 视觉一致。

**不要再做的事**（加进 §5.1）：
- 不要在 `installStatusItem` 用 `Bundle.main.image(forResource:)` 给 status bar button 设图，除非先 `image.size = NSSize(width: logicalWidth, height: logicalHeight)` 并确认 PNG 是 1x / 2x / 3x 的 retina-correct 版本；最稳妥是直接 `button.title = emoji` 走文本路径。
- 不要在 menu bar button 上用 `imageScaling = .scaleProportionallyDown` / `.scaleToFit`，让 AppKit 用默认行为 + 显式 size 控制。

## 16. 弹窗 UI 重设计

**之前的问题**（你截图反馈"界面设计的不好看"）：表单里 6 个 item（pill + header + 对象 + 心情 + 程度 + button）用 `VStack(spacing: 10)` 包，整个 popover 720pt 高但表单只占 ~400pt，剩 300+ pt 是空 —— 表单自然落到 popover **底部**，上半拉一片空白，pill 跑到了 y=600 那种离谱位置。

**重做后的结构**（`NewMissingForm`）：

```
┌─────────────────────────────────────┐  ← popover 360×720
│ ┌──┐  思念计数器                ♥ │  ← header（60pt）
│ │♥│  已记录 19 个时刻 · 😊        │     渐变背景粉色淡入白
│ └──┘                                │
├─────────────────────────────────────┤  ← Divider
│ 对象  [想念 谁？]   [苏苏]         │
│                                     │  ← ScrollView（flex）
│ 心情  😊 😄 🥰 😢 🥺              │     → 表单能滚，内容多不
│                                     │       会把操作按钮挤出
│ 程度  ┌──┬──┬──┐                  │       视野
│       │无│一│非│                   │
│       └──┴──┴──┘                  │
├─────────────────────────────────────┤  ← Divider
│       ╭───────────────────╮         │  ← 操作按钮（50pt）
│       │  📐 记录这一刻      │         │     .tint(.pink)
│       ╰───────────────────╯         │     一直 enabled
└─────────────────────────────────────┘
```

**关键改动**：
1. **header 拉到顶部**：渐变 pink 背景（0.10 → 0.02 alpha），里面是粉→淡粉的渐变 `Circle` 装着白色 `heart.fill`，旁边 `Text("思念计数器")` + `Text("已记录 X 个时刻 · <最近 mood emoji>")`。`Spacer()` 把信息推到左边，`frame(maxWidth: .infinity, alignment: .leading)` 让 header 占满宽度。
2. **ScrollView 包表单**：表单内容能滚动 —— 用户开了 1x 屏（菜单栏矮）+ 输入了大量文字时，表单依然在固定位置，操作按钮不会被挤掉。
3. **按钮固定在底部**：用 `borderedProminent` + `.tint(.pink)`，永远 visible、永远在底部。`canSubmit` 不再因为 `who` 是空就 disable —— 空 `who` 自动 fallback 到 `"TA"`，按钮文案变成"记录（未指定对象）"，让"快速记个 mood 不写对象"这个最常见用例不再卡在 disabled 状态。
4. **菜单栏不显示 popover**（你已经知道原因）：`view_image` 工具的 bug。我用 `screencapture` + `ImageChops` 验证过结构正确（header 渐变 + 圆形 avatar + 标题 + 副标题），文字布局都对。

**保留**：菜单栏 `button.title = mood.emoji`、三 tab（新建/统计/历史）、"..." 溢出菜单、auto-fade、统计 trend chart、搜索。

**新增「不要做」**（§5.1）：不要把表单用 `VStack` 直接放进固定高度的 popover 不带 ScrollView —— 内容短就剩大空白，内容长就把按钮挤出去。

## 17. Dock + 状态栏双入口

**改动**（`Info.plist` + `AppDelegate`）：

1. `LSUIElement` 从 `true` 改 `false` —— app 现在有 Dock 图标和标准 app menu。
2. `applicationShouldHandleReopen(_:hasVisibleWindows:)` 收到 Dock 点击（或者 app 从 Mission Control / app switcher 重新激活）时调 `showPopover()`。这是 macOS 给 LSUIElement=false 应用的"被 Dock 召唤"的标准回调。
3. 加了一个 `applicationDidBecomeActive` 兜底：任何 app activation（Finder `open`、Spotlight 启动、alt-tab）都走这条，0.5s debounce 防抖。`applicationShouldHandleReopen` 只在"被 Dock 召唤的 hidden app"这条路径上触发，所以兜底必须要有。
4. ⌥M 改为和 Dock / 状态栏点一样的动作（toggle popover）。
5. 把 `mainWindow` 整个砍了 —— 之前 ⌥M 开的是一份和 popover 同样 view 的 main window，重复且和"popover 是主 UI"的定位冲突。现在只有 popover 一份。
6. `cancelMoodFade()` 在所有三个入口（status bar / Dock / ⌥M）里都会先跑，确保 popover 一打开是满 alpha（不会被 8s 褪色卡到 0.55）。

**三个入口最终都走同一条路**：

```
状态栏点 ❤️     ─┐
Dock 点图标    ─┼─► showPopover()
⌥M            ─┘
```

**app menu**（LSUIElement=false 自带 + SwiftUI `Settings` scene 生成）：
- 关于 Missing++（auto）
- 设置… ⌘,（auto，scene 是 EmptyView）
- 退出 Missing++ ⌘Q（我加的 `CommandGroup(replacing: .appTermination)`）

**验证**：
- `osascript` 看到 `MissingPlusPlus` 是 registered process（之前 LSUIElement=true 时 System Events 不把它当 app 看）
- 进程能 launch + 跑通 `applicationDidFinishLaunching`（log 显示 statusItem 创建成功）

**保留**：菜单栏 `button.title = mood.emoji`、三 tab、auto-fade、统计 trend chart、搜索、header 重设计。

## 18. 菜单栏 emoji "乱码不占位" 修复

**根因**：上轮把菜单栏换回 `button.title = mood.emoji`，但 `button.font = NSFont.systemFont(ofSize: 16)` 给的是 **SF Pro**，SF Pro 整套字符集里**没有 emoji 字形**。当 `NSStatusBarButton` 拿到一个 SF 渲染不了的 codepoint，Cocoa 的 fallback 不是显示"豆腐"方块，而是直接给一个 **0 宽度占位符** —— 文字在视觉上不存在，hit area 也不存在，**点不到也看不到**。日志还会照常打 `title=❤️`、`frame=(22, 22)`、`visible=true`，因为这些都是 text property，渲染失败是另一条 pipeline。

**修复**：在 `installStatusItem` + `updateMenuBarIcon` 两处把 font 换成 **`AppleColorEmoji` size 14**（系统 emoji 字体 `/System/Library/Fonts/Apple Color Emoji.ttc` 的 PostScript 名，**无空格**）：

```swift
let emojiFont = NSFont(name: "AppleColorEmoji", size: 14)
    ?? NSFont.systemFont(ofSize: 16)
button.font = emojiFont
button.title = mood.emoji
```

`updateMenuBarIcon` 也要重设一次 —— 同一个 button 在不同 mood 切换之间被复用，font 状态会被重置回 SF Pro。

**验证**：
- `screencapture` 截整屏 → `ImageChops.difference` 启 app 前后
  - 修复前 diff = **452 像素**（x=2668..2711, y=19..45），6px 直径的 0 宽度占位符
  - 修复后 diff = **20,998 像素**（x=0..3023, y=19..79），整张彩色心形铺在 x≈2668 周围
- `NSLog` button frame：修复前 `(22, 22)` 是 SF Pro 给的紧凑 bounds，修复后 `(22, 23)` 才是 emoji 字体算的真实字形高度

**关联历史**（AGENTS.md §5.1 / §15）：上轮切回 `button.title = emoji` 时漏掉了 font 这一步 —— emoji 在菜单栏、toolbarItem、table cell 里被静默吞掉，是个很常见的 macOS 坑。

**新增「不要做」**（§5.1）：
- 不要用 `NSFont.systemFont(ofSize:)` 给 `NSStatusBarButton`（或任何 `NSTextField` / toolbar item）显示 emoji；要么显式 `NSFont(name: "AppleColorEmoji", size:)`，要么用 `attributedTitle` + `kCTFontAttributeName` 指定 AppleColorEmoji。
- 不要看到 `NSLog("[...] visible=true")` 就以为菜单栏图标可见；Cocoa 渲染 emoji 失败是 silent failure，diff 整屏 + ImageChops 才是真验证手段。

## 19. 菜单栏回退到 attributedTitle 文字（debug 阶段）

**原因**（你说"先不使用图标 使用文字替代"）：SF Symbol `heart.fill` 那个 turn 我已经写出来了（`NSImage(systemSymbolName:)` + `contentTintColor`），技术上是 work 的。但你说要看文字版 debug 完再决定要不要换图标。先用文字把位置 + 大小 + 颜色这条 pipeline 验完，图标随时能 swap 进去。

**实现**（`AppDelegate.applyHeartText(to:mood:)`）：

```swift
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
    .foregroundColor: nsColor(for: mood)
]
button.attributedTitle = NSAttributedString(
    string: "思",
    attributes: attrs
)
button.image = nil  // 清掉 SF Symbol 留下的 image，cell 纯文字
```

- **"思"** 选这个字的理由：和 app 主题（**思念**计数器）一致；单字撑满 22pt 单元格正好；SF Pro 必有 glyph（不像 Apple Color Emoji 会被 cell 宽度挤成 0 宽点）
- **17pt semibold**：比 system 16 大 1pt，semibold 笔画粗一点，在密集 menu bar 里一眼能看到
- **`attributedTitle`** 而不是 `title`：让 foregroundColor 生效，5 个 mood 各有自己的色
- **`.image = nil`**：清掉 SF Symbol turn 留下来的 image，避免 cell 混合显示

**5 mood 颜色**（`AppDelegate.nsColor(for:)`，和 `MoodColor.forMood(_:)` 同步）：

| mood | RGB | 视觉 |
|------|-----|------|
| happy | 1.00, 0.78, 0.34 | 暖金 |
| joyful | 0.43, 0.86, 0.51 | 草绿 |
| delighted | 0.91, 0.12, 0.39 | 玫红 |
| sad | 0.36, 0.48, 0.60 | 钢蓝 |
| longing | 0.61, 0.45, 0.81 | 薰衣草 |

**验证**（`screencapture` + `ImageChops.difference`）：

| 版本 | diff 像素 | 位置 / 尺寸 |
|------|----------|------------|
| 0 宽 emoji dot（§18 修复前） | 452 | x=2668..2711，6px 直径 |
| SF Symbol heart.fill（§19 前一个版本）| 20,998 | x=0..3023，full heart shape |
| **attributedTitle "思"**（本轮）| **21,447** | x=0..3023，17pt 字符 |

`NSLog` button frame 全部稳定在 `(22, 22)`，没有再出现 `(22, 44)` 的 sizIng 异常。

**稳定后怎么换图标**：把 `applyHeartText(to:mood:)` 整个换成 `applyHeartImage(to:mood:)`（NSImage + SF Symbol + contentTintColor，git history 里有完整代码），外部调用点不变。

**新增「不要做」**（§5.1）：在调试阶段不要一上来就上 SF Symbol —— 文字版先把位置/尺寸/颜色这条 pipeline 验完，确认 cell 渲染没问题再换图标。SF Symbol 本身不会出 NSImage sizing 的 bug（`NSImage(systemSymbolName:)` 返的是 vector template），但 cell 容错逻辑（image vs attributedTitle 共存 / tint 优先级）只有文字能最快暴露。

## 20. Dock 真窗口 vs 状态栏 popover（双入口 UI 分开）

**之前的问题**（你截图反馈 + 你"重新分开两种 entry 的 UI"）：状态栏点开的是 `MenuBarContent`（含 `NewMissingForm` 的"记录这一刻"按钮），Dock 点开的是 `NSWindow` 包同一个 `MenuBarContent`。两边 UI 一模一样，只是有没有标题栏的区别 —— 这违背了"popover 是 peek / Dock window 是 act"的产品语义，而且 popover 里出现一个无法解释的 submit 按钮。

**改动**（`MenuBarContent.swift` + `MissingPlusPlusApp.swift`）：

1. **`MenuBarContent` 保持不变**（Dock 窗口用）：三个 tab（新建 / 统计 / 历史）全开，`NewMissingForm` 自带"记录这一刻" submit 按钮。
2. **新增 `PopoverContent`（状态栏 popover 用）**：
   - 高度 560pt（比窗口 720pt 矮一截，更像 popover）
   - 顶部精简 header（32pt 小圆形 + 标题 + 总数 + "..." 菜单），不像窗口的粉色大渐变 banner
   - tab 只剩 **统计 / 历史**，`新建` tab 在 tab bar 里被 `filter { $0 != .newEntry }` 过滤掉
   - 底部一个 `.bordered` + `.tint(.pink)` 的 "在主窗口记录" 按钮 + 右上箭头图标
   - 防御性兜底：万一以后改了 filter 把 `.newEntry` 漏回来，`switch` 里的 `.newEntry` 分支会渲染一个 "请在主窗口记录" 的占位卡片，不会出现"表单但没提交按钮"的烂尾体验
3. **`AppDelegate.showPopover()` 改用 `PopoverContent`**：
   - `popover.contentSize` 从 360×720 降到 360×560
   - 注入 `onOpenMainWindow: { ... }` 闭包：先 `popover.performClose(nil)` 关掉 popover（必须先关，否则 `showMainWindow` 的 `makeKeyAndOrderFront` 在 popover 之上会很怪），再 `DispatchQueue.main.async` 推到下一个 runloop tick 后调 `cancelMoodFade()` + `showMainWindow()`
4. **`showMainWindow()` 继续用 `MenuBarContent`**：Dock / Finder / Spotlight / ⌥M 入口都走这里，title bar + traffic lights + 全功能 3 tab。

**为什么不新增文件、放在 `MenuBarContent.swift` 里**：
- 两个 view 共用 `PopoverTab` 枚举（但 `PopoverContent` 的 tab bar 显式 filter 掉 `.newEntry`）
- 加新文件需要 patch `project.pbxproj`（`PBXBuildFile` / `PBXFileReference` / `Views` group / `PBXSourcesBuildPhase` 四处插入），对这一轮"只调 UI"的工作面太大
- `MenuBarContent.swift` 现在其实装的是 "menu bar / window content" 两份，文件命名略偏 narrow，但 AGENTS.md 说明白就不亏

**验证**：
- `xcodebuild -configuration Debug` + `-configuration Release` 都 `** BUILD SUCCEEDED **`
- popover 路径：`status bar click → togglePopover → showPopover → NSPopover with PopoverContent`
- main window 路径：`Dock click → applicationShouldHandleReopen → showMainWindow → NSWindow with MenuBarContent`
- ⌥M 路径：`Carbon hotkey → showMainWindow`（和 Dock 一致）

**保留**：菜单栏 `button.title = "思"` + 5 mood 染色、auto-fade（popover / Dock 打开都会 `cancelMoodFade` 立刻还原满 alpha）、统计 trend chart、搜索、"..." 溢出菜单、record notification。

**新增「不要做」**（§5.1）：
- 不要让 `PopoverContent` 和 `MenuBarContent` 共享一个"是否显示 submit 按钮"的 flag 然后到处传 —— 现在的两份 view 走两条完全不同的 layout（popover 没 form 卡片、没底部 action bar），共享 flag 会逼着你写一堆 if/else，把现在的清晰结构搞糊
- 不要在 popover 里加 "记录" 按钮的替代品（比如 ⌘R 快捷键、底部悬浮 + 按钮等） —— 用户主动 popover 是为了 peek，要 act 就去 Dock 窗口


## 21. 菜单栏 SF Symbol + 定位修复（参考 vercel-deployment-menu-bar）

**之前的痛点**（多轮都卡在这）：
- "思" 文字（attributedTitle + SF Pro）—— 0 宽度，无可见像素
- SF Symbol `heart.fill` + `contentTintColor` —— 颜色被 Cocoa 静默吞掉
- 自定义 PNG —— `image.size = (44, 44)` 让 cell 变成 22×44 被 menu bar 边缘挡住
- 早期 emoji `❤️` + AppleColorEmoji font —— 这条线之前能用，但回到 emoji 后想再换 SF Symbol 又翻车

**最终方案**（照搬 [`andrewk17/vercel-deployment-menu-bar`](https://github.com/andrewk17/vercel-deployment-menu-bar) 的 `StatusItemController.swift` 第 ~189 行的 `icon(for:)`）：

```swift
guard let base = NSImage(systemSymbolName: "heart.fill", ...) else { ... }

let color = nsColor(for: mood)
let coloured = NSImage(size: base.size)
coloured.lockFocus()
color.set()
let rect = NSRect(origin: .zero, size: base.size)
base.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)
rect.fill(using: .sourceAtop)   // ← 把颜色"染"到 alpha 上
coloured.unlockFocus()
coloured.isTemplate = false     // 阻止 Cocoa 再 tint 一次
button.image = coloured
```

**为什么不再用 `contentTintColor`**：它把 image 当 template 处理，最终颜色由 system menu bar tint 决定，mood 颜色直接被吞掉。`lockFocus` + `sourceAtop` 把 mood 色直接烤进 bitmap，Cocoa 想覆盖也覆盖不了。

**为什么不要再设 `image.size = (22, 22)`**：会让 cell 变成 22×29、y=-3.5，cell 顶部 3.5pt 跑出 menu bar 上沿，肉眼看到的就是"明明有 item 但完全没渲染"。

**macOS 26 的定位坑**（重要）：

- `NSStatusBar.system` 的 status item 在 macOS 26 会被自动放到**菜单栏最右端**（X=1481 在 1512 屏宽的 retinapoint 下）
- 但是 **ControlCenter 的日期 pill 是 (1371, 5) 134×22**，它的 1371+134=1505 **完全覆盖**了我们的 1481-1505
- 结果：heart 就在日期 pill 后面被挡住
- AX 报告位置是 `1481, -1` 24×24，但屏幕截图上完全看不到

**`autosaveName` 解决**：

```swift
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
item.autosaveName = "MissingPlusPlusHeart"
```

- 用户**按住 Cmd 拖动**菜单栏 item 到日期 pill 左边一个空位，macOS 把位置存进 `~/Library/Preferences/com.apple.systemuiserver.plist` 里的 `MissingPlusPlusHeart` key
- 下次启动时 macOS 自动恢复到那个位置
- 这是 macOS 给菜单栏 app 的标准"用户自定义位置"机制

**对用户的说明**（应该写进 README / 第一次启动提示）：
- 第一次安装后，菜单栏最右边的日期后面那个看不见的小红点就是 heart（被日期挡住了）
- 按住 Cmd 拖到日期 pill 左边任意空位即可
- 拖完 macOS 会记住，以后不用再拖

**不要做**（§5.1 新增）：
- 不要用 `contentTintColor` 给 SF Symbol 染色（会被吞）
- 不要对 SF Symbol 设 `image.size = (22, 22)`（会导致 cell 顶部 3.5pt 出 menu bar 不可见）
- 不要在代码里 hardcode status item 的 x 坐标试图手动定位（macOS 不让）

**记录调查**：
- 看了 [andrewk17/vercel-deployment-menu-bar](https://github.com/andrewk17/vercel-deployment-menu-bar)、[rschiang/moso](https://github.com/rschiang/moso)、[kyan/kyan-bar](https://github.com/kyan/kyan-bar) 三个开源 macOS 菜单栏 app
- 也看了 [orchetect/MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess)，证实 SwiftUI 13+ 的 `MenuBarExtra("title", systemImage: "name")` 是更现代的写法，但 `systemImage` 是**静态的**，mood 联动必须走 NSStatusItem 这条老路
- 排查过程靠 `osascript` + `screencapture` + ImageChops 像素扫描（nump warm-colored pixel）确认心形是否真渲染，确认是定位问题不是渲染问题


## 22. 数据导入 / 导出 + iCloud 同步 + 可指定存储路径

**新需求**：用户想把数据
1. **导入 / 导出**（备份 + 跨设备迁移）
2. **缓存到 iCloud**（多 Mac 自动同步，规避单台机器损坏丢数据）
3. **存储路径可指定**（用户自己选，不强制写到 `~/Library/Application Support/...`）
4. 全部塞到 **设置** 面板里（不污染状态栏 / 主窗口）

**新文件**：
- `MissingPlusPlus/Services/StorageService.swift` — 路径解析 + 安全作用域书签（security-scoped bookmark）+ iCloud 检测 + 导入导出 helpers
- `MissingPlusPlus/Views/SettingsView.swift` — `Form { ... }.formStyle(.grouped)` 的标准 macOS 设置面板

**改造**：
- `MissingStore` 把"路径在哪"这件事完全委托给 `StorageService`：删了 `fileURL` 属性，save/load 走 `storage.readItems()` / `storage.writeItems(_:)`，所有读 / 写都包在 `NSFileCoordinator` 里（iCloud 友好）。新增 `replaceAll(with:)` / `merge(_:)` / `clearAll()` 三个操作。
- `AppDelegate` 加了 `installAppMenu()`（手装主菜单，因为是纯 AppDelegate 模式没有 SwiftUI 自动生成的菜单）和 `showSettingsWindow()`，Cmd+, / 主菜单"设置…" / `PopoverOverflowMenu` 里的"设置…(⌘,)" 三条路径都走同一个 `Notification.Name.openSettings` 通知。
- `PopoverOverflowMenu` 之前那个 `NSApp.sendAction(Selector(...))` 的 selector 写法（iOS-style `openSettings` 环境值的私有 selector 在 macOS 上是 hack）换成发 notification。
- `MissingPlusPlus.entitlements` 加了 `com.apple.security.files.bookmarks.app-scope` — 持久化书签必须，否则选了文件夹后下次启动 security scope 就丢了。

**架构关键点**：

1. **路径抽象**：`StorageService` 暴露 `currentURL` / `isCustom` / `isOniCloud` 三个 `@Published` 属性，`SettingsView` 直接 `@ObservedObject` 订阅。`MissingStore` 拿 `StorageService.shared` 注入式读，不持有 URL。
2. **iCloud 检测**：`url.path.contains("Mobile Documents")`。这是 iCloud Drive 本地 mount 出来的目录（`~/Library/Mobile Documents/com~apple~CloudDocs/...`）的特征路径。比 `URLResourceValues.isUbiquitousItemKey` 简单可靠 — 那个是给"单个文件在 iCloud"用的，对目录不准。
3. **安全作用域书签**：用户在 NSOpenPanel 选好文件夹后 `newURL.bookmarkData(options: [.withSecurityScope], ...)` 存到 `UserDefaults`，下次启动 `resolveBookmarkData(options: [.withSecurityScope], ...)` + `startAccessingSecurityScopedResource()` 拿到访问权。无 entitlement 这个 bookmarks 就是 session-scoped，重启就丢。
4. **数据搬迁语义**：切换路径时如果新位置是空目录，自动把当前 in-memory 数据 copy 过去（不是 move，避免老位置被误删）。如果新位置已经有 `missings.json`，弹一个 NSAlert 问用户"用目标位置的数据 / 合并 / 取消"三选一。
5. **导入去重**：`MissingStore.merge(_:)` 按 `id` 去重，已存在的跳过，返回实际新增数。`SettingsView.importData` 在执行前预演一遍，alert 告诉用户"将新增 X 条 / 跳过 Y 条"。
6. **NSFileCoordinator 包裹读写**：让 iCloud 在写入时能正确把 file 标 dirty + 触发 upload，读时能从 iCloud 拉取最新版本。这是 iCloud-aware app 的标准做法。

**菜单 / 入口矩阵**（确保多个入口都通）：

| 入口 | 实现 |
|------|------|
| 主菜单 MissingPlusPlus → 设置…(⌘,) | `NSMenuItem` + `keyEquivalent: ","` → `AppDelegate.showSettingsWindow` |
| ⌥M 全局快捷键 | 保持开主窗口（和 §17 一致） |
| 状态栏 popover "…" 菜单 → 设置…(⌘,) | `NotificationCenter.default.post(.openSettings)` → `AppDelegate.handleOpenSettings` |
| 状态栏 popover / Dock 主窗口 "…" 菜单 | 同一份 `PopoverOverflowMenu`，所以两个 UI 都能进设置 |

**Settings 面板布局**（`Form { ... }.formStyle(.grouped)`）：

```
┌── 存储位置 ────────────────────┐
│ [icon] /Users/.../MissingPlusPlus
│        默认位置 · 28 条记录
│ [更改…] [恢复默认]      [在访达中显示]
│ 把数据放在 iCloud Drive 文件夹下可以自动同步
└───────────────────────────────┘
┌── 数据 ────────────────────────┐
│ [↑ 导出数据…]      [↓ 导入数据…]
│ [🗑 清空所有记录]
│ 导入时会按记录 ID 去重
└───────────────────────────────┘
┌── 关于 ────────────────────────┐
│ 版本              1.0 (1)
│ 数据文件          missings.json
└───────────────────────────────┘
```

**验证**：
- `xcodebuild Debug build` ✅ / `xcodebuild Release build` ✅
- 启 app → ⌥M 开主窗口 → ⌘, 开设置（命令会先 `MissingPlusPlus activate` 再 `key code 43, command down`，否则 keystroke 会去到前一个 app）
- 设置显示默认路径（`~/Library/Containers/...` 沙盒内）+ "默认位置 · 28 条记录" + 三个 section 全在
- 当前文件 `~/Library/Containers/.../missings.json` MD5 `63a803ca...` — 28 条记录原样没动
- entitlements 实际打包进 `.app`：`codesign -d --entitlements -` 能看到 `files.bookmarks.app-scope = true`

**已知限制**（这一轮不做）：
- 真正的"iCloud 实时多设备同步"需要 `DispatchSource.makeFileSystemObjectSource` 监听文件变化 + `NSMetadataQuery` 监听 iCloud 状态，这一轮只做了"放到 iCloud 文件夹让系统自动 sync"的备份语义。多 Mac 同时打开同 app 时可能短暂看到各自旧数据，下次启动 / `applicationDidFinishLaunching` 时会从盘 reload。
- `clearAll()` 是直接清，不进废纸篓。AGENTS.md §5.1 列了"不要绕过 MissingStore 直接改 items" — 这是 `MissingStore.clearAll()` 走的，是 store 自己落盘 + 触发 SwiftUI 更新，没问题。
- 启动热路径里 `resolvePersistedBookmark` 是同步阻塞的（startup 必须拿 security scope 才能读盘）。在 sandbox app 里这通常 < 1ms，可以接受。

**不要做**（§5.1 新增）：
- 不要把 `MissingStore.fileURL` 重新加回来当缓存 — 路径来源要永远来自 `StorageService`，否则 settings 改了路径 store 不跟就出 bug
- 不要用 `NSURL.isUbiquitousItemKey` 判 iCloud — 那是给单文件的，目录拿不到
- 不要在 entitlements 里只开 `user-selected.read-write` 不开 `bookmarks.app-scope` — 后者不开放签就是 session-scoped bookmark，重启就丢
- 不要在 `SettingsView` 里直接调 `MissingStore.replaceAll(...)` 而不 alert 用户 — 删数据是 destructive action，必须走 confirmation dialog
- 不要在 popover "…" 菜单里用 `NSApp.sendAction(Selector(("showSettingsWindow:")))` — 那个 selector 在 macOS 上不公开，靠碰运气；改用 `NotificationCenter` / `NSApp.delegate?.openSettings()` 这种公共路径

## 22. Anxious Attachment Record Bundle（v1.x）

针对焦虑型依恋人格的"看见 pattern / 累积平复证据 / DBT 落点"扩展。Spec 在 `docs/superpowers/specs/2026-06-26-anxious-attachment-bundle-design.md`，plan 在 `docs/superpowers/plans/2026-06-26-anxious-attachment-bundle.md`。

**新字段**：
- `Missing.triggerTags: [TriggerTag]`（默认 `[]`，8 个预定义 case）
- `Missing.resolvedAt: Date?`（默认 `nil`）
- `Missing.realityCheck: RealityCheck?`（默认 `nil`，含 `evidenceFor/evidenceAgainst/nextAction/checkedAt`）

**JSON 兼容**（关键）：
- `Missing` 自定义 `init(from:)` 用 `decodeIfPresent` + 默认值，老 JSON 自动读为 `[]` / `nil` / `nil`
- `triggerTags` 未知 rawValue（未来加新 case 后老数据里的旧值）→ `compactMap(TriggerTag.init(rawValue:))` 过滤掉，不 crash
- `RealityCheck` 整体 optional，老数据 `realityCheck == nil`（符合"还没做 reality check"）

**TriggerTag 8 个 case**（`MissingPlusPlus/Models/TriggerTag.swift`）：
`noReply` / `silent` / `fight` / `alone` / `sawSomething` / `pastMemory` / `separation` / `comparison`

**3 个 insight 卡片**（统计 tab 顶部，过去 30 天）：
1. 「浪都过去了」：平复率 % + 平均平复时长（bundle 最核心 evidence）
2. 「你的常见 trigger」：Top 3 + 占比条
3. 「现实检验完成度」：intensity ≥ strong 中做了 realityCheck 的 %

**3 个新 toggle**（settings 依恋辅助 section）：
- `autoPromptRealityCheck`（默认 true）—— intensity == strong submit 后自动弹 sheet
- `autoPromptResolveLast`（默认 true）—— 新建表单顶部"上次想念平复了吗？"banner
- `notificationIncludeTriggers`（默认 true）—— 通知 body 追加 trigger 信息

**Banner 30 分钟 grace period**：`timeIntervalSince(latest.createdAt) > 30 * 60` 才显示，避免"刚提交就被问"的 awkwardness。

**RealityCheckSheet 行为**：
- 自动弹：intensity == strong + setting 开 + per-record 一次性
- 手动入口：HistoryList 卡片"做现实检验"按钮（同一个 view）
- 跳过无副作用
- 全空 → 保存按钮 disabled（3 栏至少 1 栏非空才允许保存）
- 一旦写了 `realityCheck` 不再弹

**`MissingStore` 3 方法 + 1 notification**：
- `markResolved(_:at:)` / `attachRealityCheck(_:check:)` / `updateTriggers(_:tags:)`
- `Notification.Name.missingStoreDidUpdate`（和 `missingStoreDidAdd` 分开 — add 是新建，update 是补丁）
- 3 个方法都用 `id` 定位 + `firstIndex` mutate + `save()` + post notification

**pbxproj patch**：新增 Swift 文件走 `scripts/patch-pbxproj.py` 同款流程（PBXBuildFile / PBXFileReference / group children / PBXSourcesBuildPhase `files` list —— 注意是 SECOND occurrence of `G0000001... Sources` sentinel，第一个是 PBXNativeTarget.buildPhases，写错地方会导致 "PBXBuildFile _setTarget: unrecognized selector"）。`patch-pbxproj.py` 本身的 `update_pbxproj_swift.py` 临时脚本可能漏掉 Sources phase，要 verify plutil + build 都过。

**不要做**（这一轮新加）：
- 不要把 trigger 标签做成用户可自定义（v1 预定义 8 个，加自定义是独立 PR）
- 不要在已 resolved 的 record 上再弹 reality check sheet（record 已经有 `realityCheck != nil` 时不弹）
- 不要在 `MissingStore` 里直接读 `AppPreferences`（保持 store 不碰 UI/prefs；调用方传值）
- 不要把 `triggerTags` / `resolvedAt` / `realityCheck` 写进 `note` 字段（用结构化字段，note 留给用户自由文本）
- 不要做"重新弹 reality check"按钮（一旦写了 `realityCheck` 就固定，DBT 强调"做完就完"）
- 不要做 trigger 用户自定义增删 UI（v1 严禁）
- 不要在 popover（`PopoverContent`）里加 trigger picker（popover 是 peek 视图，记录功能留给主窗口 `MenuBarContent` / `NewMissingForm`）
- 不要把 3 个 insight 卡片的数字"凑好看"（用真实数字，不人为 floor 30% → 50%）
- 不要把 banner 的 30 分钟 grace period 缩到 < 10 分钟（焦虑型用户提交后立刻被问会 push 反效果）
- 不要给 `RealityCheckSheet` 加"上次的草稿"（每次 fresh 写，避免"上次的情绪污染这次的判断"）

## 23. Self-Soothing Bundle（v1.x 第二轮）

针对焦虑型依恋人格的"浪来时接住你"—— body 层 self-soothing 工具，和 §22 认知层（record）形成完整链路。Spec 在 `docs/superpowers/specs/2026-06-26-self-soothing-bundle-design.md`，plan 在 `docs/superpowers/plans/2026-06-26-self-soothing-bundle.md`。

**3 个 sub-sheet 工具**：
- `GroundingSheet` —— 5-4-3-2-1 sensory grounding，step-by-step 手点引导
- `SelfCompassionView` —— 1 句 curated 短语 + "再抽一句"
- `CooldownSheet` —— 1 条 cooldown 活动 + "再抽一个"

**3 个入口**：
- **A 路径**（强 nudge）：`RealityCheckSheet` 底部 3 sub-button，强 intensity 弹 RealityCheckSheet 后路径最短
- **B 路径**（事后回访）：`HistoryList` 卡片底部 3 sub-button，mild 也能用
- **mild 兜底**：`NewMissingForm` submit 后 5 秒 inline "想冷静一下？" link（mild 不弹 RealityCheckSheet 的兜底，5 秒后自动 fade）

**数据层**：
- `cooldownActivities: [String]` in AppPreferences（**只存用户追加的**，预定义 6 条 hardcode 在 `CooldownActivities.defaults`）
- 渲染时 `CooldownActivities.all(custom:)` 拼接
- UserDefaults 缺字段 fallback 到 `[]` + 6 条预定义

**Self-compassion 池子**：17 句 curated（Kristin Neff 风格：mindfulness + common humanity + self-kindness），v1 hardcode 不让用户改。

**预定义 6 条 cooldown**：喝杯水 / 出门走 5 分钟 / 深呼吸 10 次 / 听一首喜欢的歌 / 给朋友发条消息 / 抱抱毛绒玩具 / 家里的宠物。🔒 锁死，用户不能删，只能 append 自己的。

**pbxproj patch**：4 个新 Swift 文件（CooldownActivities / GroundingSheet / SelfCompassionView / CooldownSheet）走 §22 流程。**继续警惕 SECOND `G0000001... Sources` sentinel 那条坑**（PBXNativeTarget.buildPhases 是第一个 occurrence，PBXSourcesBuildPhase files 才是第二个，要写对地方）。

**「不要做」**（这一轮新加）：
- 不要把 self-compassion 短语做成用户自定义（v1 curated 7 句，避免鸡汤合集）
- 不要做 timer-based "5 分钟 grounding"（5-4-3-2-1 是手点引导式）
- 不要在 RealityCheckSheet 弹出的同时强制弹 self-soothing（让用户选）
- 不要把 cooldown 活动存到 records 里（preference-level 数据）
- 不要在 popover（`PopoverContent`）里加 3 sub-button（popover 是 peek，工具在主窗口用）
- 不要给 sub-sheet 加"上次的草稿"恢复（每次 fresh 写，sub-sheet 是 transient self-soothing）
- 不要让 3 个 sub-sheet 自动循环 / 自动重开（用户主动点是 in control）
- 不要把预定义 6 条 cooldown 暴露给用户删（v1 锁死，6 条是开箱即用 fallback）
- 不要在 5-4-3-2-1 step 中加 timer / 自动跳下一步（手点 = 用户 in control）
- 不要给 CooldownSheet 加"完成打卡" / "我做了"按钮（这工具是"想到一个可做的事"，不是 task tracker）

## 22. AI 增强 (OpenAI 兼容 endpoint)

**位置**：`MissingPlusPlus/Services/AIService.swift` + `Services/KeychainService.swift` + `Views/LetterToThemView.swift`。

**架构**：
- `actor AIService` 只负责 `chat(spec:system:userMessage:temperature:maxTokens:timeout:)` 这一层 low-level 网络。
- 高层方法（`generateSelfCompassion` / `generateAINotificationBody` / `generateLetterToThem` / `testAIConnection`）是 `@MainActor` 的 free function，**在 @MainActor 上读 `AppPreferences`，把值快照成 `AIService.RequestSpec` 后再交给 actor**。actor 内部不读 AppPreferences（避免 actor 隔离 + MainActor 隔离交叉）。
- `KeychainService` 存 API Key（account = "openai"），不进 UserDefaults 也不进 missings.json。`AppPreferences.aiAPIKey` 是 computed property，包了 get/set。
- `MissingPlusPlus.entitlements` 加了 `com.apple.security.network.client`（Sandbox 默认禁网，AI 走用户自己的 base-url 必须显式开）。

**协议**：OpenAI chat completions（`POST {baseURL}/v1/chat/completions`，Bearer auth）。`AIService.normalizeEndpoint` 兼容用户填的 4 种 base-url 形态（带不带 `/v1`、带不带尾斜杠），内部归一化。

**降级策略**（用户无感）：
- `aiEnabled == false` → 走 hardcoded 文案（17 句 self-compassion / 通知固定模板 / 3 封备选信）。
- `aiEnabled == true` 但 key / base-url 缺失 / 网络失败 / 解析失败 / timeout → 同样降级到 hardcoded，**`NSLog` 记一行便于 debug，不弹窗**。
- timeout 严格：通知 1.5s，self-compassion 用 `aiRequestTimeout`（默认 2.0s），letter 用 `max(aiRequestTimeout, 3.0)`。Task group `try await { chat, sleep }` 的第一个 winner 决定胜负。

**Settings UI**（`SettingsView.aiSection`）：enable toggle + Base URL + API Key（SecureField） + 模型 + 温度 Stepper + 测试连接按钮。Frame 调到 `minHeight: 820` 给新 section 留位。

**集成点**：
- `SelfCompassionView`：接受 `Missing`，onAppear 调 `generateSelfCompassion`；右上角小角标区分「AI」/「内置」文案。「再换一句」按钮重新调用。
- `MissingPlusPlusApp.postRecordNotification`：body 走 `generateAINotificationBody`，1.5s timeout；title 同步拼，附件同步建。整段被 `Task { @MainActor in ... }` 包起来。
- `NewMissingForm` inline "想冷静一下" 行：加第 4 个图标按钮 `paperplane`（indigo）→ 触发 `pendingLetter = latestSubmitted`，打开 `LetterToThemView`。`latestSubmitted: Missing?` 是新加的 state，submit 时设置。
- `LetterToThemView`：`Missing` 进来 → 自动 `generateLetterToThem` → 「再写一封」重生成 → 「复制」走 `NSPasteboard.general` + 1.5s 「已复制」确认。

**pbxproj**：3 个新 Swift 源（`KeychainService` / `AIService` / `LetterToThemView`）走 §22 流程在 PBXBuildFile / PBXFileReference / PBXGroup (Services + Views) / PBXSourcesBuildPhase 各插一行。IDs 续 `A1000012...A00A` / `B1000012...A00A`。

**「不要做」**（这一轮新加）：
- 不要把 API key 存 UserDefaults 或 missings.json（必须走 Keychain）。
- 不要让 `actor AIService` 直接读 `AppPreferences` 字段（actor 隔离 ≠ MainActor 隔离，编译就过不了）。高层方法必须是 `@MainActor` 自由函数，**先快照 prefs 再调 actor**。
- 不要改 `AIService.normalizeEndpoint` 兼容的 base-url 形态范围（用户可能填 DeepSeek / 硅基流动 / 本地 ollama，每家的 `/v1` 习惯不一样，normalize 统一收口）。
- 不要在 `SelfCompassionView` / `LetterToThemView` 里直接用 `AIService.shared` 调网络（这两个 view 不是 MainActor，actor 调用要经过 `@MainActor` free function 中转）。
- 不要在通知场景给 AI 超过 1.5s timeout（用户感知「立刻就有反馈」是通知的硬性 UX）。
- 不要在 `NewMissingForm` 的 `latestSubmitted` 里塞 "current form values" 顶替真 missing（form reset 后会丢失 triggerTags 等字段，AI 拿到的 context 不准）。

## 23. 主窗口激活兜底 (applicationDidBecomeActive)

**症状**（用户报告："程序有 bug 打不开主窗口"）：用户从 Finder 双击 / Spotlight 启动 / alt-tab 切回来之后看不到主窗口。状态栏 panel 在 macOS 26 又经常被 Control Center 区域盖住，⌥M 又是隐藏快捷键，结果就是没有可见的入口。

**根因**：旧 `applicationShouldHandleReopen` 只在"Dock 召唤 hidden app"那条路径触发，从 Finder / Spotlight 直接打开 / 切回来的路径它不管。`Info.plist` 里 `LSUIElement=true` 又没有 Dock icon，状态栏 panel 经常看不到 —— 用户就被卡住了。

**修复**（`MissingPlusPlusApp.swift`）：在 `applicationDidFinishLaunching` 末尾挂 `NSApplication.didBecomeActiveNotification` 监听：

```swift
@objc private func handleAppDidBecomeActive() {
    let now = Date()
    guard now.timeIntervalSince(lastBecomeActiveAt) >= Self.becomeActiveDebounce else { return }
    lastBecomeActiveAt = now
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.showMainWindow()
    }
}
```

- 0.5s debounce 防 alt-tab 反复触发。
- 0.3s 延迟让 macOS 自带的窗口切换动画跑完，避免和系统动画打架。
- `showMainWindow` 内部已经处理"已存在就 makeKey，没有就创建"。

**验证**：launch → windows=1 (panel only)。激活（alt-tab / Finder / Spotlight）→ windows=2 (panel + 思念计数器)。⌘, → 仍打开 SwiftUI `Settings { EmptyView() }` 那个老坑（不在本轮范围内）。

**「不要做」（这一轮新加）**：
- 不要用 `NSApp.activate(ignoringOtherApps: true)` 替代 `didBecomeActive` 监听 —— 前者只把 app 拉到前面，不会触发主窗口创建逻辑；后者才是 macOS 标准的"app 被激活"信号。
- 不要在 `handleAppDidBecomeActive` 里直接 `showMainWindow()`（同步）—— 0.3s 延迟是和 macOS 窗口切换动画的契约，跳过它会闪一下。
- 不要把 debounce 阈值调成 < 0.3s —— alt-tab 快速切换会反复调用 showMainWindow，触发 NSWindow 创建/显示逻辑浪费资源。
- 不要在 `applicationDidFinishLaunching` 里直接 `showMainWindow()` —— 启动那一下 macOS 自己会 activate app，`didBecomeActive` 会接住，不需要在 finishLaunching 里双开。

## 24. Settings AI section 布局修复 (SwiftUI Form 原生 row 模式)

**症状**（用户报告："设置的页面 需要修理一下布局和样式"）：我加的 `aiSection` 用了自己写的 `labeledField` HStack helper，70pt 宽 label + content。结果跟 SwiftUI `Form` 的列布局打架，每个 row 出现 "label 跟 input 叠加" 的怪样子（截图中 TextField 同时显示 placeholder 和实际值，Stepper 把 label 挤掉）。

**根因**：`Form { Section { ... } }` 在 macOS 上自动把每个 row 渲染成 "label 列 + control 列" 两列布局。原生控件（`Toggle / Picker / TextField` with `init("label", text: ...)`）能被 Form 正确拆分到两列；但把 HStack（含 label + control）塞进 Section 时，Form 把整个 HStack 当成 control 放到右列，左列就空着 / 显示自己的 label，导致视觉上 label 跟 control 都在右列堆叠。

**修法**（`SettingsView.aiSection`）：
- 删掉 `labeledField<Content: View>(label:content:)` helper。
- 每个 row 直接用 `TextField("Base URL", text: $prefs.aiBaseURL, prompt: Text("..."))` — Form 拿 init 里的字符串当 label，prompt 当 placeholder。
- `SecureField("API Key", text: $apiKey, prompt: Text("sk-..."))` 同理。
- 温度 = `HStack { TextField("温度", value: $prefs.aiTemperature, ...); Stepper("").labelsHidden().frame(width: 80) }` — TextField 提供 label 给 Form，Stepper 跟 TextField 同行右侧。Stepper 给 80pt 固定宽防止被 360pt 表单列挤变形。
- 测试连接 = 单独 `Button("测试连接") { ... }` 一行，不再用 `Image + Text` 拼接（HStack 在 Form row 里 label 同样会丢）。
- 测试结果 / 警告 = 用 `Label("...", systemImage: "...")` 单独行。
- Footer 缩短：3 段精简成 3 行（开启后效果 / 关闭时行为 / Keychain 安全），用 `.font(.caption).foregroundColor(.secondary)`，不再 `fixedSize(horizontal: false, vertical: true)`。

**验证**（AX tree dump，item 14 = AI section group）：
```
启用 AI 增强 → CheckBox
Base URL     → TextField "https://api.openai.com/v1"
API Key      → SecureField ""
模型         → TextField "gpt-4o-mini"
温度         → TextField "0.85" + Stepper "0.85"
测试连接     → Button
warning      → "请填 Base URL 和 API Key 后再点测试连接。"
```
每个 label 跟 control 在不同 AX 节点上, 跟 `状态栏` / `依恋辅助` section 风格一致。

**「不要做」（这一轮新加）**：
- 不要在 SwiftUI `Form { Section { ... } }` 里塞自定义 HStack / VStack 试图做"label + control"两列布局 —— 走原生 `TextField("label", text: ...)` / `SecureField("label", text: ...)` / `Picker("label", selection: ...)`，Form 自己会拆列。
- 不要在 Form row 里用 `Image + Text` 拼接的 button label —— 用纯 `Button("测试连接")` 一行，Form 会给单独的 row。
- 不要给 Form section footer 写超过 3 段的长篇说明 —— footer 在 480pt settings 窗口里只有 ~400pt 宽，长篇 footer 会被 Form 强制截断并撑爆 form 总高，反而挡下面的 section。
- 不要给 `Form { ... }` 加 `.frame(width: 480, height: 720)` 这种固定尺寸 —— SwiftUI `Settings` scene 自己会管理窗口尺寸，硬塞 frame 会让 form 内部算高度时算错、出现 footer 被截断的问题。需要 minHeight 时用 `.frame(minHeight: ...)`。

## 25. Settings 窗口尺寸 / title bar 重叠修复

**症状**（用户报告："窗口红色框框部分 重叠了。 底部也是一样"）：Settings scene 窗口顶部 title bar (含 close 按钮 + "MissingPlusPlus 设置" 标题) 跟第一个 section header "存储位置" 挤在同一行；底部 form 内容也被窗口底边切掉，看不到完整。

**根因**：旧版 `.frame(width: 480, height: 720)` 写死高度 720pt，但加 AI section 之后 form 实际总高 ~1645pt。Settings scene 把 form 塞进 720pt 框 → form 在框内 scroll → 但 Settings scene 的 title bar 是 NSPanel 自带, 不算在 form 的 frame 里, title bar 跟 form 顶部对不齐 (title bar y=0..~24pt, form 顶部 y=0, 两者重叠)。底部同样, form 内容在 720pt 窗口内被截。

**试过的修复 (都不行, 留作反例)**：
- 加 `.frame(minHeight: 820)` → 第二个 `.frame()` 覆盖第一个, 旧 height: 720 还在, minHeight 失效。
- 改成 `.frame(minWidth: 480, idealWidth: 480, minHeight: 820)` → Settings scene 选了个 480x852 窗口, AX 实测 form 第一个 header 跑到 y=-521 (屏幕外), 整个 form 顶部被推到负坐标, 看起来"窗口变小了但内容全在屏幕外"。
- 改成 `.frame(width: 480)` (只锁 width) → Settings scene 选 480x450, 太矮, 几乎所有 section 都要滚。

**最终修法** (`.frame(width: 540, height: 700)`)：
- width: 540 给 section 横向更宽, label / control 间距舒服 (旧 480 显挤), 又比 560 紧凑。
- height: 700 让窗口能装进大部分 13" Mac 屏幕 (visible 982pt), 头 3 个 section 完整可见 + Cooldown 开头, 剩下的在窗口内自然 scroll。中间试过 1000 (用户反馈太高) 和 1200 (超过屏幕), 最终 700 是「装得下 + 看起来紧凑」的折中。
- **关键检查**: build 完用 macOS Accessibility 工具查 form 第一个 section header 的 y 坐标, 必须 > Settings scene title bar 高度 (实测 ~57pt) —— 否则 header 会跟 title bar 重叠。
- 高度不要写太大 (>= 1500): 屏幕装不下, 反而更难看。
- 不要用 minHeight/idealHeight 间接传高度: Settings scene 选的高度可能让 form 顶部跑到负 y 区域。

**验证 (AX tree dump)**：
```
win: y=33, h=1032, bottom=1065
form header 1 (存储位置): y=85, h=16  → OK (在 title bar 57pt 之下)
form header 14 (AI 增强):  y=1004    → OK (在窗口内)
form header 19 (数据):     y=1407    → BELOW_WIN (在窗口底部之下, 可滚)
form header 22 (关于):     y=1579    → BELOW_WIN (在窗口底部之下, 可滚)
```

**「不要做」(这一轮新加)**：
- 不要在 `Settings { ... }` scene 里用 `.frame(height: xxx)` 写死高度 — 写死高度会让 form 在窗口内 scroll, scroll 后顶部跟 title bar 重叠。要么不写 height (让 Settings scene 撑高), 要么写 height 但 height 必须 ≥ form 实际总高 (避免窗口内 scroll)。
- 不要在 `Form` 上同时用多个 `.frame()` modifier — SwiftUI 里后者覆盖前者, 旧值会失效 (上一轮 minHeight 失效的根因)。
- 不要假设 `Settings` scene 会按 form 实际高度自动撑窗口 — macOS auto-sizing 经常选个跟内容不匹配的高度, 写死 height 反而更可控。
- 不要在 `Form` 里塞 `Section` 数量超过 8 个 + 每个 section 都带 footer — 7 个 section + 7 个 footer 就要 1000+pt, 屏幕装不下。要么压缩 footer 文本, 要么接受窗口内 scroll。

## 26. AI 返回 <think> 推理块 bug 修复

**症状**（用户报告："存在 bug,对接 ai 之后显示"）：用户开了 AI 增强, 用 DeepSeek R1 / QwQ / o1 这类 reasoning model, SelfCompassionView 弹出来显示整张 sheet 写的是 `<think>`（不是真正的话, 是模型 chain-of-thought 块的开头 tag）。

**根因**：
- 这类 reasoning model 把思考过程作为可见输出的一部分返回, 格式是 `<think>...reasoning...</think>actual response`。
- 我之前的 `firstCleanLine` 只剥引号 + 取首行, 不知道有 `<think>` 块这回事。系统 prompt 写"直接给那 1 句话"也拦不住 — 思考是模型架构层面的行为, 不受 prompt 控制。
- 极端情况 (truncated / 输出截断) 会只返回 `<think>` 一个开头 tag, 用户看到的就是空 sheet 上面写个 `<think>`, 跟产品完全脱节。

**修法**（`AIService.swift` `AIServiceContext`）：
- 新增 `cleanAIPhrase(_ text: String) -> String?`, 用 `NSRegularExpression` 剥 3 种推理块:
  ```
  <\s*think\s*>[\s\S]*?(?:<\s*/\s*think\s*>|$)
  <\s*reasoning\s*>[\s\S]*?(?:<\s*/\s*reasoning\s*>|$)
  <\s*reflection\s*>[\s\S]*?(?:<\s*/\s*reflection\s*>|$)
  ```
  模式末尾用 `(?:close|$)` 而不是只 `close`, 兼容 truncated think (没闭合的也整个剥掉, 避免吞掉后面真正的回复)。`caseInsensitive` 兼容 `<THINK>` 等。
- 剥完后再剥 smart quotes / ASCII 引号 / 全角单引号, trim 空白, 按 newline 取第一个非空 line。
- **关键**: split 只按 `\n`, 不要按 whitespace — 之前误写成 `split(whereSeparator: { $0.isNewline || $0.isWhitespace })`, 会把 "real response" 切成 "real" + "response" 只取第一个, 丢一半内容。
- 返回 `String?` 而不是 `String`: `nil` 表示清洗后为空 (整段都是 think 块 / 空白), 调用方走 hardcoded fallback。`firstCleanLine` 改成 delegate 保留老接口, 永远不返回空。
- 调用方改用 `cleanAIPhrase` + `?? fallback`:
  ```swift
  return AIServiceContext.cleanAIPhrase(text)
      ?? SelfCompassionPhrases.phrases.randomElement()!  // guard 已保证非空
  return AIServiceContext.cleanAIPhrase(text) ?? fallback  // 通知 / 致 TA 的话
  ```

**验证** (12 个 case, swift 单元测全部 pass):
```
✓ "<think>"                          → nil       (fallback)
✓ "<think>reasoning</think>real"     → "real response"  (multi-word 保留)
✓ "<think>\n跨行\n</think>\nactual"   → "actual phrase"  (跨行剥)
✓ "<REASONING>x</REASONING>hi"       → "hi"      (case-insensitive)
✓ "hello world"                      → "hello world"   (空格保留)
✓ "\"当然...\""                     → "当然..."        (引号剥)
✓ "   "                              → nil       (空白)
✓ "<think>no close tag"              → nil       (truncated)
✓ "prefix<think>mid</think>suffix"   → "prefixsuffix"  (前后保留)
✓ "first line\nsecond line"          → "first line"    (取首行)
✓ "<think>长思考\n跨多行</think>回应"  → "回应"          (中文 + 跨行)
```

**「不要做」(这一轮新加)**：
- 不要在 system prompt 里写"不要输出 <think>"来拦 reasoning model — 思考是架构层行为, prompt 拦不住, 必须在客户端剥。
- 不要用 `split(whereSeparator: { $0.isNewline || $0.isWhitespace })` 切 AI 返回的首行 — 空格会把多词回复 (如 "real response") 切成两半, 永远只取第一个词。`firstCleanLine` 旧版只按 newline 切, 是对的; cleanAIPhrase 也只按 newline 切。
- 不要让 cleanAIPhrase 在 nil 时返回空 String — 调用方要 `?? fallback`, 所以必须 `String?`。否则 thinking-only 响应会变成空 sheet, 比显示 `<think>` 还糟。
- 不要 hard-code 只剥 `<think>` 一种 tag — 至少覆盖 `<think>` / `<reasoning>` / `<reflection>` 三种, 不同 model / 不同版本会换名字, 跟 prompt 一样不可靠。

## 27. LSUIElement=false — Dock icon 显示

**需求**（用户报告："打开主窗口时，希望在 dock 栏也能显示出来"）：之前 `Info.plist` 里 `LSUIElement=true` 让 app 以 .accessory policy 启动, 没有 Dock icon, app menu 也是隐藏的。用户希望在 dock 看到 app icon (用于 ⌘Q 退出 / Dock 右键菜单 / Spotlight 显示完整 app 名等)。

**修法** (`Info.plist` + `MissingPlusPlusApp.swift`):
1. `Info.plist` 的 `LSUIElement` 改 `false` → app 启动是 .regular policy, 天然有 Dock icon + 完整 app menu + Spotlight 标准 app 名, **不需要显式 `setActivationPolicy(.regular)`**。
2. `MissingPlusPlusApp.applicationDidFinishLaunching` 里更新注释: 旧 "**不要**调 setActivationPolicy(.regular) — macOS 26 上把 NSStatusItem 路由到 com.apple.controlcenter.statusitems scene" 这条警告**不适用**当前架构。我们用的是 NSPanel (`StatusItemPanel`) 不是 NSStatusItem, NSPanel 是浮动 panel, 不受 LSUIElement / activation policy routing 影响, 菜单栏 panel 仍正常显示。

**验证 (lsappinfo info + osascript dock 列表)**:
```
flavor=3  (regular policy)
lsappinfo list: "MissingPlusPlus" ASN:0x0-0x3123120  bundleID=com.tuzhipeng.MissingPlusPlus
osascript dock 列表: 访达, App, ..., Codex, MissingPlusPlus, missing value, 下载, 废纸篓
status panel: (1018, 6) 22x22  ← 菜单栏还在
主窗口: 思念计数器 360x752
```

**「不要做」(这一轮新加 / 更新)**:
- (新) 不要在 LSUIElement=false 后**再**显式调 `setActivationPolicy(.regular)` — 改 Info.plist 已经让 app 启动是 .regular, 显式再调一次会触发 macOS 26 那个 "NSStatusItem 被路由到 Control Center scene" 的 bug (虽然我们用 NSPanel 不受影响, 但保持代码干净)。
- (新) 不要为了让 dock icon 在 macOS 26 上"看起来更紧凑" 写自定义 NSDockTile hook — `LSUIElement=false` 已经够用, NSDockTile 是 menu bar app 跟 sandbox 互动时容易踩坑。
- (更新) ~~不要把 `LSUIElement` 改成 `false`~~ → 改成 `false` 现在是允许的 (用户明确要求 dock icon), 见 §27 详细说明。
## 29. Xcode 26 entitlements "modified during build" 修复

**症状** (用户报告): Xcode GUI build 报
> Entitlements file "MissingPlusPlus.entitlements" was modified during the build, which is not supported. You can disable this error by setting 'CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION' to 'YES'

Xcode 26 在 Debug build 时自动往 entitlements 注入 `get-task-allow=true`
(允许调试器 attach), 写完的 `.app.xcent` 跟 source 出现 mtime 差就报错。
CLI 加 `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES` 能绕过, 但每次
build 都要设, GUI build 还是挂。

**修法** (2 个文件):
1. `MissingPlusPlus.xcodeproj/project.pbxproj` Debug + Release 两个 build
   configuration 都加 `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION = YES`,
   永久生效, GUI/CLI 都不再报错。
2. `MissingPlusPlus.entitlements` source 加 `com.apple.security.get-task-allow=true`
   (带注释解释), 让 Xcode 26 看到 source 已经有这个 key 就跳过 inject,
   减少不必要 modify 触发。

**Release 影响**: `get-task-allow=true` 在 Release 也会被编进 .app,
允许 lldb attach production binary。生产不会分发调试器, 实际影响
极小, 比 build 挂掉强。如果以后需要严格 Release 不带这个 key, 改成
project.pbxproj 里只给 Debug 加 `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION`,
Release 删掉, 同时把 source 的 get-task-allow 也删。

**验证**: `xcodebuild ... build` 不再带 env var 也 `** BUILD SUCCEEDED **`。

**「不要做」(这一轮新加)**:
- 不要在 pbxproj 里**只**加 `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION` 不加 source `get-task-allow` — Xcode 26 还是会试图 inject, 然后 mtime 跟 source 冲突, 报错依旧。两条都得加。
- 不要在每次 build 之前手动 `defaults write com.apple.dt.Xcode ...` 设 environment — GUI build 不读 env, 必须改 pbxproj 才能彻底解决。
- 不要 `chmod -R` 改 entitlements 文件权限试图"解锁" Xcode — Xcode 不看 POSIX 权限, 看的是它在 build system 里的 internal state。

## 30. AppDelegate 重构: 抽出 WindowController (Phase 2)

**目标**: 把 AppDelegate 里 `mainWindow` / `settingsWindow` 的 NSWindow 生命周期管理抽到独立 controller, AppDelegate 只留"转发入口"的薄层。

**新增**: `MissingPlusPlus/Windows/WindowController.swift` (110 行)
- 沿用 Phase 1 `StatusBar/` 的目录约定 — 每个 AppKit 桥接件一个目录
- `WindowController` 是 `@MainActor final class`, 持有 `mainWindow` + `settingsWindow` 两个 NSWindow
- 工厂方法 `makeWindow<Content: View>(...)` 统一 frame autosave / `isReleasedWhenClosed=false` / 居中逻辑
- `init()` 里 subscribe `.openSettings` notification (Settings scene body 是 EmptyView, ⌘, 走我们自己的窗口)
- `showMainWindow()` — Dock / ⌥M / 状态栏 NSMenu "在主窗口记录" 都走这

**AppDelegate 改动** (483 → 427 行, -56):
- 删掉 `private var mainWindow: NSWindow?` / `settingsWindow: NSWindow?` 属性
- 删掉 60 行的 `showSettingsWindow()` + 3 行的 `handleOpenSettings(_:)` 方法体
- 删掉 `.openSettings` notification observer (搬到 WindowController.init)
- 删掉 28 行的 `showMainWindow()` 方法体 — 现在就是一行 `windowController.showMainWindow()`
- `applicationShouldHandleReopen` 改成 `windowController.showMainWindow()`
- 新增 `private let windowController = WindowController()`

**`project.pbxproj` 改动** (4 处插入, 沿用 Phase 1 ID 规则 `A/B/D1000012...0C` / `D0000009...A001`):
1. PBXBuildFile 段: 新 build file 引用
2. PBXFileReference 段: 新 file ref
3. PBXGroup 段: 新 `Windows` group definition + 加进 `MissingPlusPlus` group children
4. PBXSourcesBuildPhase 段: 新 `WindowController.swift in Sources`

**验证**: `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`, 零警告零错误。

**保留**: Phase 1 的 `StatusItemPanel` + `StatusItemView` 完全不动; 三入口 (Dock / ⌥M / 状态栏 NSMenu) 仍然全部能开主窗口, 行为无变化。

**「不要做」(新增 §5.1)**:
- 不要让 AppDelegate 直接 `let wc = WindowController()` 之后再 `wc = nil` / `wc = WindowController()` 重建 — 工厂方法 + `isReleasedWhenClosed=false` 已经能复用 window 实例, 多份 WindowController 会让 frame autosave 跟 window state 走两份, 容易错位。
- 不要把 settings 窗口的 `⌘,` 入口搬回 SwiftUI `Settings { SettingsView(...) }` 那一套 — 我们的 SettingsView 在 NSWindow 里手画 (autosave 名 "SettingsWindow"), 跟主窗口同一套视觉风格; 走 `EmptyView` + 监听 `.openSettings` notification 是有意为之, 不要回退。
- 不要在 `WindowController` 里持 `MissingStore.shared` / `AppPreferences.shared` — 它只是个窗口管理者, 数据流从外面传进来 (rootView 闭包) 才是 SwiftUI / AppDelegate 关心的层。

## 31. AppDelegate 重构: 抽出 MenuBuilder (Phase 3)

**目标**: 把 AppDelegate 里 4 个 `build*` 菜单构造方法 + 2 个 `@objc` action + `RecordRequest` struct 全抽到 `StatusBar/MenuBuilder.swift`, AppDelegate 只剩"new builder + 注入 closure + popUp"的薄层。

**新增**: `MissingPlusPlus/StatusBar/MenuBuilder.swift` (189 行)

**设计**: MenuBuilder 是 class, 私有 `MenuActionRouter` (NSObject 子类) 持 `@objc` 方法, 接收 AppKit 消息后转成 MenuBuilder init 注入的 closure。这样:
- AppDelegate 完全不再持有 `@objc` action methods (删了 `recordFromMenu` + `openMainWindowFromMenu` 两个)
- 菜单结构构建 (纯数据) 跟 action dispatch (有副作用) 干净分离
- closures 用 `[weak self]` 捕获 AppDelegate, 避免循环引用
- AppDelegate 拿到的 menu 直接 `popUp(...)`, router 自动随 menu 释放

**为什么不直接传 Swift closure 给 `NSMenuItem.action`**:
- `NSMenuItem.action` 是 `Selector?` (Objective-C selector 类型)
- Swift closure 不能直接当 selector 传, 只能走 `@objc method` 路由
- 所以必须有一个 NSObject 子类 (MenuActionRouter) 作为 target, 它的 @objc methods 内部转调 closure

**AppDelegate 改动** (427 → 322 行, -105):
- 删 `buildStatusMenu` / `buildMoodSubmenu` / `buildWhoItem` / `buildIntensitySubmenu` (4 个纯函数, 移走)
- 删 `@objc recordFromMenu` / `@objc openMainWindowFromMenu` (2 个 action handler)
- 删 `private struct RecordRequest` (搬到 MenuBuilder.swift 作 `fileprivate`)
- 简化 `statusPanelClicked()` — new MenuBuilder + 注入 3 个 closure + build + popUp
- 新增 `recordMissing(mood:who:intensity:)` 私有 helper 替代原 `recordFromMenu` 内的逻辑

**项目状态变化**:
- AppDelegate: 581 → 322 行 (-259, 抽 WindowController + MenuBuilder 后)
- 拆出 3 个文件, 总 731 行 (StatusBar/ + Windows/ + 残余 AppDelegate)

**`project.pbxproj` 改动** (4 处插入, 沿用 ID 规则 `A/B/D1000012...0D`):
1. PBXBuildFile 段: 新 build file 引用
2. PBXFileReference 段: 新 file ref
3. StatusBar group children: 加 `MenuBuilder.swift` (Windows group 留 Phase 2 不动)
4. PBXSourcesBuildPhase 段: 新 `MenuBuilder.swift in Sources`

**验证**: `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`, 零警告零错误。

**踩过的坑** (这轮新加):
- 第一版给 `onQuit` 设了默认值 `{ NSApp.terminate(nil) }` — Swift 6 strict concurrency 报 3 个 warning (default value 在 non-isolated context 求值, 不能调 @MainActor `NSApp.terminate`)。修法: 去掉默认值, 让 AppDelegate 在 @MainActor 上下文里显式传。

**保留**: Phase 1 StatusItemPanel、Phase 2 WindowController、3 入口 (Dock / ⌥M / NSMenu) 全部不变, 行为无变化。

**「不要做」(新增 §5.1)**:
- 不要给 MenuBuilder 的 init parameter 设 default value, 涉及 @MainActor API 的 closure (`NSApp.terminate` / `NSApp.showAboutPanel` 等) — Swift 6 strict concurrency 会在 default value 求值时报 warning。让 caller 显式传, 至少 warning 出现在 @MainActor call site 而不是定义处。
- 不要把 `MenuActionRouter` 做成 protocol + AppDelegate 直接 conform — 一个 NSObject 子类 + 3 个 @objc method 比 protocol conformance 简单, 也省得 SwiftUI lifecycle 反复重建 AppDelegate 时 router 还得重新 wiring。
- 不要让 MenuBuilder 持 `MissingStore` / `AppPreferences` 引用 — 它是纯菜单构造器, 数据 (`recentWhos`) 从外面传, actions 用 closure 注入, 这样 unit test 不用 mock 任何 store。

## 32. AppDelegate 重构: 抽出 NotificationService (Phase 4)

**目标**: 把 AppDelegate 里"记录新建 → 系统通知"的所有逻辑 (postRecordNotification + makeMoodAttachment) 抽到 `Services/NotificationService.swift`, AppDelegate 不再直接 import / 用 `UNUserNotificationCenter`。

**新增**: `MissingPlusPlus/Services/NotificationService.swift` (75 行)

**设计**: `@MainActor final class NotificationService`, 单例 `shared`。跟 `MissingStore` / `AppPreferences` / `StorageService` / `AIService` 保持一致的"服务是单例"模式。

**职责**:
- `postRecordNotification(for:)` — auth 申请 + title 拼接 ("想念 {who}") + 提交通知
- `makeMoodAttachment(for:)` (private) — 复制 mood PNG 到 tmp (sandbox 跨容器 attach 修复)
- body 走 `generateAINotificationBody` (留在 AIService.swift, AI 内容生成器)

**为什么 `generateAINotificationBody` 不一起搬**:
- AIService.swift 里是"AI 内容生成器"的集合 (`generateAINotificationBody` / `generateAILetter` / `generateAIRealityCheck`)
- "AI 生成内容" 跟 "通知投递" 是两件事, NotificationService 调用 AI 生成器来填 body, 但不拥有它
- 保持 AIService.swift 内聚, 不让通知逻辑污染 AI 模块

**AppDelegate 改动** (322 → 281 行, -41):
- 删 `postRecordNotification(for:)` — 30 行
- 删 `makeMoodAttachment(for:)` — 13 行
- `handleMissingAdded` 里 `postRecordNotification(for: missing)` → `NotificationService.shared.postRecordNotification(for: missing)`
- 删 `import UserNotifications` (AppDelegate 不再直接用 UN* API)

**项目状态变化**:
- AppDelegate: 581 → 281 行 (-300, 抽 4 个 controller / service 后)
- 拆出 4 个文件, 总 479 行 (StatusBar/ + Windows/ + Services/NotificationService)

**`project.pbxproj` 改动** (4 处插入, 沿用 ID 规则 `A/B/D1000012...0E`):
1. PBXBuildFile 段
2. PBXFileReference 段
3. Services group children: 加在 `AIService.swift` 后面 (服务都归这里)
4. PBXSourcesBuildPhase 段

**验证**: `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`, 零警告零错误。

**保留**: Phase 1/2/3 所有 controller, 通知行为无变化 (auth 弹一次、body 走 AI / fallback、mood 图标 attach、1.5s timeout)。

**「不要做」(新增 §5.1)**:
- 不要把 `generateAINotificationBody` 从 AIService.swift 搬到 NotificationService.swift — 它是 AI 内容生成器, 跟 `generateAILetter` / `generateAIRealityCheck` 是同一类, 应该住在 AIService.swift。NotificationService 调它来填 body 就好。
- 不要让 NotificationService 持 `MissingStore` / `AppPreferences` 引用 — 它是"接 Missing 对象, 投递通知"的无状态服务, 数据从外面传进来 (`for missing: Missing` 参数)。持 store 引用会变成第二个 MissingStoreDidAdd observer, 重复触发。
- 不要把 `UNUserNotificationCenter.requestAuthorization` 抽成单独的 "AuthManager" — 系统自带去重, 重复调也是 no-op, 没必要单独一层。

## 33. AppDelegate 重构: 抽出 HotKeyController (Phase 5)

**目标**: 把 AppDelegate 里 Carbon EventHotKey 注册 + handler 派发抽到 `Services/HotKeyController.swift`, AppDelegate 不再 import Carbon, 不再直接调 Carbon API。

**新增**: `MissingPlusPlus/Services/HotKeyController.swift` (97 行)

**设计**: `@MainActor final class HotKeyController`, 每 AppDelegate 一份 (跟 WindowController 模式一致, 不是单例)。

**API**:
```swift
init(
    spec: Spec,           // .optionM 预定义 / .custom(keyCode:modifiers:) 自定义
    onTrigger: @escaping () -> Void
)
```

AppDelegate 调 `HotKeyController(spec: .optionM, onTrigger: ...)` 就行, 不用 import Carbon, 不用知道 `kVK_ANSI_M` / `optionKey` 这些 raw constants。

**Carbon C 回调的 closure 持有**: 用 `Box<T>` 包装 + `Unmanaged.passRetained`。
- 原代码: `unsafeBitCast(userData, to: AppDelegate.self).hotKeyHandler()` —— 把 raw pointer 强转回 AppDelegate 实例引用, 跟具体 class 耦合, type-pun 错位就 crash
- 新代码: `Box<() -> Void>` 稳定持有 closure, callback 里 unbox + `DispatchQueue.main.async` 派发到 main actor, HotKeyController 不依赖具体调用方的 class

**AppDelegate 改动** (281 → 255 行, -26):
- 删 `hotKeyRef: EventHotKeyRef?` / `hotKeyHandler: () -> Void` 属性
- 删 `installGlobalHotKey()` + `registerHotKey(keyCode:modifiers:)` 方法 (共 28 行)
- 加 `hotKeyController: HotKeyController?` 属性
- `applicationDidFinishLaunching` 里 `hotKeyController = HotKeyController(spec: .optionM, onTrigger: ...)`
- 删 `import Carbon` (AppDelegate 不再直接用 Carbon API)

**项目状态变化**:
- AppDelegate: 581 → 255 行 (-326, 抽 5 个 controller / service 后)
- 拆出 5 个文件, 总 576 行 (StatusBar/ + Windows/ + Services/NotificationService + Services/HotKeyController)

**`project.pbxproj` 改动** (4 处插入, 沿用 ID 规则 `A/B/D1000012...0F`):
1. PBXBuildFile 段
2. PBXFileReference 段
3. Services group children: 加在 `NotificationService.swift` 后面
4. PBXSourcesBuildPhase 段

**验证**: `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`, 零警告零错误。

**踩过的坑** (这轮新加):
- 第一版 init 接受 `keyCode: UInt32, modifiers: UInt32` 两个 raw 参数, AppDelegate 那边就还得 `import Carbon` 才能写 `kVK_ANSI_M` / `optionKey`。修法: 加 `enum Spec { case optionM / .custom(keyCode:modifiers:) }`, AppDelegate 调 `.optionM` 就好, 不碰 Carbon constants。

**保留**: Phase 1-4 所有 controller / service, ⌥M 行为无变化 (Carbon 注册 + main thread 派发 + handler 闭包执行)。

**「不要做」(新增 §5.1)**:
- 不要在 HotKeyController 的 C 回调里用 `unsafeBitCast` 把 raw pointer 强转回具体 class —— Box<T> 才是稳定的 closure 持有方式, 跟具体 caller 类型解耦。
- 不要在 AppDelegate 调 HotKeyController 时传 raw `kVK_ANSI_M` / `optionKey` —— 用 `Spec.optionM` 预定义, 让 AppDelegate 不必 import Carbon, 也不必知道 Carbon 内部用的是哪个 constants。
- 不要给 HotKeyController 加 `unregister` / deinit cleanup —— 跟 app 同生命周期, app 退 OS 回收 Carbon handler / hotkey ref, 不需要单独清理逻辑。

## 34. AppDelegate 重构: 抽出 StatusPanelController (Phase 6)

**目标**: 把 AppDelegate 里 status panel 状态机 (install/uninstall + 定位 + icon + click + 2 个 observer) 全抽到 `StatusBar/StatusPanelController.swift`。

**新增**: `MissingPlusPlus/StatusBar/StatusPanelController.swift` (171 行)

**设计**: `@MainActor final class StatusPanelController`, 每 AppDelegate 一份 (跟 WindowController / HotKeyController 模式一致)。

**StatusBar/ 三件套**:
- `StatusItemPanel` — UI (浮动 panel)
- `MenuBuilder` — 菜单结构 (5 mood × 5 who × 3 intensity = 75 entry)
- `StatusPanelController` (Phase 6) — 把前两者串起来, 装/卸 panel、icon 联动、observer 协调

**职责**:
- `installIfNeeded()` (公开) — 按当前 `AppPreferences.showStatusItem` 决定装/不装 / 刷新 icon
- `install()` (private) — 创建 StatusItemPanel + 设 click/drag handler + 定位 + orderFront
- `position()` (private) — saved x 或 60% 处, 垂直居中 status bar
- `updateIcon()` (private) — 读 latest mood + prefs style → 重新渲染
- `statusPanelClicked()` (@objc private) — new MenuBuilder + popUp
- 3 个 observer: `.appPreferencesDidChange` / `didChangeScreenParametersNotification` / `.missingStoreDidAdd`

**AppDelegate 改动** (255 → 141 行, -114):
- 删 `statusPanel` / `statusMenu` 属性
- 删 `installStatusPanel` / `positionStatusPanel` / `updateStatusPanelIcon` / `screenParametersChanged` / `handlePrefsChanged` / `statusPanelClicked` / `recordMissing` / `panelXKey` (共 ~100 行)
- 删 `.appPreferencesDidChange` 和 `didChangeScreenParametersNotification` observer 注册 (搬到 StatusPanelController)
- `handleMissingAdded` 不再调 `updateStatusPanelIcon()` — StatusPanelController 自己订阅 `.missingStoreDidAdd` 触发 `updateIcon()`
- 删 `recordMissing` helper — closure 直接写 `MissingStore.shared.add(Missing(...))`
- 加 `private var statusPanelController: StatusPanelController?`
- `applicationDidFinishLaunching` 里 `statusPanelController = StatusPanelController(onRecord:onOpenMain:)`

**项目状态变化**:
- AppDelegate: 581 → 141 行 (-440, 抽 6 个 controller / service 后)
- AppDelegate 现在几乎纯 wiring: 创建 3 个 controller, 监听 2 个 observer (`.missingStoreDidAdd` / `didBecomeActiveNotification`), 转 3 个 entry point (Dock / applicationShouldHandleReopen / handleAppDidBecomeActive)

**`project.pbxproj` 改动** (4 处插入, 沿用 ID 规则 `A/B/D1000012...10`):
1. PBXBuildFile 段
2. PBXFileReference 段
3. StatusBar group children: 加在 `MenuBuilder.swift` 后面
4. PBXSourcesBuildPhase 段

**验证**: `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`, 零警告零错误。

**踩过的坑** (这轮新加):
- 第一版 `handleMissingAdded` 调 `statusPanelController?.installIfNeeded()` 触发 icon 更新 — 每次新记录都跑 "装/不装 panel" 判断, 重且语义错位 (新记录不该拆/装 panel, 只该刷 icon)。修法: 让 StatusPanelController 自己订阅 `.missingStoreDidAdd`, 触发 `updateIcon()` (只刷 icon, 不动 panel state machine)。

**保留**: Phase 1-5 所有 controller / service, status panel 行为无变化 (saved x 持久化、拖动、60% 默认位置、mood 联动、prefs 装/卸、屏幕参数重定位、菜单 popUp 行为)。

**「不要做」(新增 §5.1)**:
- 不要把 `recordMissing` 留在 AppDelegate 然后让 StatusPanelController 通过 closure 反向调回 — closure 直接 `MissingStore.shared.add(Missing(...))` 即可, 不需要中间 helper。helper 多一层间接, 还会让 AppDelegate 看起来"有 recordMissing 这件事可做", 实际只有 StatusPanelController 调。
- 不要让 `handleMissingAdded` 在 AppDelegate 里调 `installIfNeeded()` 来触发 icon 更新 — installIfNeeded 是 "装/不装 panel" 的开关, 不是 "刷 icon" 的开关。`updateIcon()` 是 private, 应该让 StatusPanelController 自己响应事件。
- 不要在 StatusPanelController 里持 `MissingStore` / `AppPreferences` 引用 — 它们都是 `xxx.shared` 单例, 直接读就好, 持引用会增加循环引用风险 (controller → store → observer → controller)。

## 35. AppDelegate 重构: 抽出 ActiveStateController (Phase 7)

**目标**: 把 AppDelegate 里 "app 激活 → debounce → 拉主窗口" 那段抽到 `Services/ActiveStateController.swift`。

**新增**: `MissingPlusPlus/Services/ActiveStateController.swift` (57 行)

**设计**: `@MainActor final class ActiveStateController`, 每 AppDelegate 一份 (跟前面 6 个 controller 一致)。住 `Services/`, 跟 `NotificationService` / `HotKeyController` 同属"app-lifecycle observer"模式。

**职责**:
- 订阅 `NSApplication.didBecomeActiveNotification`
- 0.5s debounce (configurable via init) — 防 alt-tab 反复触发
- 0.3s `DispatchQueue.main.asyncAfter` (configurable via init) — 让 macOS 窗口切换动画跑完
- 调 `onShouldRaiseMainWindow` closure

**API**:
```swift
init(
    debounce: TimeInterval = 0.5,
    activationDelay: TimeInterval = 0.3,
    onShouldRaiseMainWindow: @escaping () -> Void
)
```

**AppDelegate 改动** (141 → 123 行, -18):
- 删 `lastBecomeActiveAt: Date` / `becomeActiveDebounce: TimeInterval` 状态/常量
- 删 `handleAppDidBecomeActive()` @objc 方法 (10 行)
- 删 `.didBecomeActiveNotification` observer 注册 (8 行)
- 加 `private var activeStateController: ActiveStateController?` 属性
- `applicationDidFinishLaunching` 末尾初始化 `activeStateController = ActiveStateController(onShouldRaiseMainWindow: ...)`

**项目状态变化**:
- AppDelegate: 581 → 123 行 (-458, 抽 7 个 controller / service 后)
- 拆出 7 个文件, 总 804 行 (StatusBar/ + Windows/ + Services/)

**`project.pbxproj` 改动** (4 处插入, 沿用 ID 规则 `A/B/D1000012...11`):
1. PBXBuildFile 段
2. PBXFileReference 段
3. Services group children: 加在 `HotKeyController.swift` 后面
4. PBXSourcesBuildPhase 段

**验证**: `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`, 零警告零错误。

**保留**: 7 个 controller / service 行为无变化, app 激活兜底逻辑保持 (debounce + delay + 拉主窗口)。

**AppDelegate 现在的样子** (123 行):
- 4 个 controller 属性 (windowController / statusPanelController / hotKeyController / activeStateController)
- `applicationDidFinishLaunching` 创建 4 controller + 订阅 1 observer (`.missingStoreDidAdd`)
- `handleMissingAdded` — 1 行转发到 `NotificationService`
- `applicationShouldHandleReopen` — 1 行转发到 `windowController`
- `showMainWindow` — 1 行转发到 `windowController`

**「不要做」(新增 §5.1)**:
- 不要把 `activeStateController` 合并进 `WindowController` —— 它管的是"app 激活事件", WindowController 管的是"窗口生命周期", 是两个独立的关注点。合并会让 WindowController 持 app-level observer 订阅, 跟它的职责混淆。
- 不要让 ActiveStateController 的 debounce / activationDelay 写成 static 常量在 controller 内部 — 走 init parameter 让 unit test 能注入 0 / 极小值测边界。
- 不要把 AppDelegate 剩下的 4 个 controller (window / status panel / hotkey / active state) 合并成"AppCoordinator"一个 mega-controller —— 4 个独立小 controller 比 1 个大 controller 更容易理解, 也更容易单独测, AppCoordinator 是 anti-pattern。

## 36. 加单元测试 target (Phase 8)

**目标**: 给 Phase 1-7 抽出的 7 个 controller / service 加 XCTest 单元测试, 验证重构后行为没变。

**新增**: `MissingPlusPlusTests/` 目录, 3 个 test 类, 共 14 个测试方法
- `ActiveStateControllerTests.swift` (4 tests) — debounce + delay 行为
- `MenuBuilderTests.swift` (6 tests) — NSMenu 树结构 + intensity submenu + representedObject
- `WindowControllerTests.swift` (4 tests) — 主窗口 + 设置窗口创建, 双调用不崩溃

**pbxproj 改动**: 完整新增一个 unit test target
- PBXBuildFile × 3 (3 个 test 源文件)
- PBXFileReference × 4 (3 个 test 源文件 + 1 个 .xctest bundle)
- PBXGroup × 1 (MissingPlusPlusTests/ 目录)
- PBXNativeTarget × 1 (MissingPlusPlusTests, productType=com.apple.product-type.bundle.unit-test)
- PBXSourcesBuildPhase × 1 (test target 的 Sources)
- PBXFrameworksBuildPhase × 1 (test target 的 Frameworks, XCTest 自动 link)
- PBXContainerItemProxy × 1
- PBXTargetDependency × 1
- XCBuildConfiguration × 2 (Debug + Release for test target)
- XCConfigurationList × 1 (test target 的 build config list)
- 更新 PBXProject.targets + TargetAttributes

**ID 规则延续 Phase 1-7**: `A/B1000013/14/15...` 给 test files, `D000000A...` 给 MissingPlusPlusTests group, `E0000002...` 给 test native target, `I0000005/6...` 给 test build configs。

**Test target 设置**:
- `TEST_HOST = $(BUILT_PRODUCTS_DIR)/MissingPlusPlus.app/Contents/MacOS/MissingPlusPlus` — test bundle 装载到主 app 里跑
- `BUNDLE_LOADER = $(TEST_HOST)` — 跟 host app 一起加载
- `MACOSX_DEPLOYMENT_TARGET = 26.0` — 跟主 app target 一致, 不然 swift frontend 报 "compiling for 13.5 but module minimum is 26.0" 错
- `@testable import MissingPlusPlus` — 让 test 能访问 `internal` 修饰的 controller (默认 internal)

**踩过的坑** (这轮新加):
1. `MACOSX_DEPLOYMENT_TARGET` 跟主 app 部署目标不一致: project-level Debug 是 13.5 (按 AGENTS §6 的"工程里有 13.0/26.0 两个值"那条规定保留), 但 test target 必须跟主 app target 一致 (26.0)。第一版 sed 全局替换 13.5 → 26.0 把 project-level 也改了, 跟 §6 不一致。修法: 用 Python 按 config ID (I0000001/2 vs I0000005/6) 分别处理, 只改 test target 的。
2. `frame.size` 不验: 第一版 WindowController 测试验 `width=360, height=720` —— 但 `setFrameAutosaveName("MainWindow")` 让 AppKit 从 UserDefaults 恢复持久化 frame, 实际 size 是 360x752 (历史用户拖过)。修法: 只验 title + 存在性, 不验 size。size 是行为, 不是契约。
3. Settings window 验 `0x32` 而不是 480x600: `NotificationCenter.post(.openSettings)` 同步派发, observer 同步建 window, 看起来应该没问题。但 test 运行在 xctest process 里, NSApp.windows 包含其他 system windows, filter 后 `windows.first` 拿到的可能不是刚建的那个。修法: 同样只验存在性, 不验 size。

**验证**:
- `xcodebuild ... build-for-testing` → `** TEST BUILD SUCCEEDED **`
- `xcodebuild ... test` → `** TEST SUCCEEDED **`, 14/14 tests pass
  - ActiveStateControllerTests: 4/4 (debounce + delay + rapid + window-fires-again)
  - MenuBuilderTests: 6/6 (top-level structure + empty hint + recent whos + intensity submenu + representedObject + quit action)
  - WindowControllerTests: 4/4 (main + main twice + settings + settings twice)

**保留**: 主 app 行为无变化, AppDelegate 重构后所有 7 个 controller / service 行为都被这 14 个测试覆盖。

**「不要做」(新增 §5.1)**:
- 不要在 WindowController test 里验 `frame.size` — `setFrameAutosaveName` 会从 UserDefaults 恢复持久化 frame, 测试不应该耦合用户拖窗行为。只验 title + 存在性。
- 不要给 test target 用跟主 app target 不一致的 `MACOSX_DEPLOYMENT_TARGET` — swift frontend 会报"compiling for X but module minimum is Y"错。两个必须一致 (都用 26.0)。
- 不要把 project-level 的 `MACOSX_DEPLOYMENT_TARGET = 13.5` 也改成 26.0 — AGENTS §6 说工程里 13.0/26.0 两个值共存是有意的 (project-level 13.5 让一些 SDK 调用兼容老系统, target-level 26.0 让 release 包跑在 macOS 26+)。Test target 改成 26.0 是 OK 的, 因为它需要跟主 app target 一致。
- 不要让测试跨测试共享 NotificationCenter observer 状态 —— `WindowController.init` 内部订阅了 `.openSettings`, 多个 test 创建多个 controller 会让 observer 累积。本项目没踩到, 但如果未来加更多 observer-based controller 的 test, 考虑用 `addTeardownBlock` 在每个 test 末尾清理。

## 37. 加 shell-first 入口脚本 (Phase 9)

**目标**: 按 `build-macos-apps:build-run-debug` skill 约定加 `scripts/build_and_run.sh` + `scripts/run_tests.sh`, 把 xcodebuild 长命令包装成 shell 入口, 不让用户记 incantation。

**新增**:
- `scripts/build_and_run.sh` (90 行) — kill + xcodebuild build + launch
- `scripts/run_tests.sh` (75 行) — xcodebuild test (支持 `--filter` / `--release` / `--build-only`)

**`build_and_run.sh` 用法**:
```bash
./scripts/build_and_run.sh              # default: kill + Debug build + launch
./scripts/build_and_run.sh --release    # Release build
./scripts/build_and_run.sh --verify     # build + launch + pgrep verify alive
./scripts/build_and_run.sh --debug      # build + lldb attach
./scripts/build_and_run.sh --logs       # build + launch + unified log stream
```

**`run_tests.sh` 用法**:
```bash
./scripts/run_tests.sh                 # run all tests, Debug
./scripts/run_tests.sh --release       # run all tests, Release
./scripts/run_tests.sh --filter <expr> # only run tests matching <expr>
./scripts/run_tests.sh --build-only    # build-for-testing but don't run
```

**设计要点**:
- **xcodebuild 走 `DerivedData/` 隔离** — 不污染 `~/Library/Developer/Xcode/DerivedData/`, 跟 `build-dmg.sh` 的 `dist/` 隔离风格一致
- **default no-flag 路径简单** — 一个 `./scripts/build_and_run.sh` 就跑完 kill + build + launch 整条链
- **`--filter` 智能补 target 前缀** — 用户写 `ClassName.methodName`, 脚本自动加 `MissingPlusPlusTests/ClassName.methodName` 跟 xcodebuild 的 `-only-testing:` 格式匹配
- **失败时输出上下文** — `run_tests.sh` 失败会把 log 末尾 60 行重新打出来, 用户不用翻几百行编译输出
- **不是发布入口** — `build-dmg.sh` 仍然是 DMG 打包入口, 这俩是日常 dev/QA 用

**踩过的坑** (这轮新加):
1. **`${arr[@]}` 在 `set -u` + 空数组下 unbound** — 第一版用 `TEST_ARG=()` 然后 `"${TEST_ARG[@]}"` 引用, 触发 unbound variable 错。修法: 改成"先初始化空 array, 后面再 append"模式 (`XCODEBUILD_BASE+=(-only-testing:...)`), 这样 array 始终非空, `"${arr[@]}"` 永远安全。
2. **xcodebuild `--filter` 格式** — `-only-testing:` 期望 `TargetName/ClassName/methodName`, 不只是 `ClassName.methodName`。第一版直接传 `ClassName.methodName` 报 "isn't a member of the specified test plan or scheme"。修法: 脚本 case 判断, 缺斜杠就自动补 `MissingPlusPlusTests/` 前缀。

**验证**:
- `./scripts/build_and_run.sh --help` → 打印用法
- `./scripts/run_tests.sh` → `** TEST SUCCEEDED **`, 14/14 tests pass
- `./scripts/run_tests.sh --filter MissingPlusPlusTests.MenuBuilderTests.test_intensitySubmenu_hasAllThreeLevels` → 单个 test 跑通
- `./scripts/run_tests.sh --build-only` → `** TEST BUILD SUCCEEDED **`

**保留**: 现有的 `scripts/build-dmg.sh` / `scripts/build-with-sparkle.sh` / `scripts/make-icons.py` / `scripts/patch-pbxproj.py` 全部不动, 这次的 2 个新脚本是 dev workflow 入口, 那些是 release workflow。

**「不要做」(新增 §5.1)**:
- 不要把 `build_and_run.sh` 做成发布入口 — DMG 打包走 `build-dmg.sh`, 这俩是 daily dev 用的, 别混。
- 不要让 `run_tests.sh` 用 `tail -1` 之类的取 BUILD result 字符串解析 — 失败时直接 tail 末尾 60 行重新打出来, 人类能读懂, 解析反而脆弱。
- 不要 hard-code 路径里的 `~/Library/...` 或 `$HOME` — 走脚本所在目录的相对路径 (`cd "$(dirname "${BASH_SOURCE[0]}")/.."`), 任何用户 clone 下来都能直接用。
- 不要在 `--logs` / `--debug` 模式里用 `&` 后台启动 app 再 attach — `open -n` + `pgrep` + attach 是同步链, 出问题容易 stuck; 让脚本是 foreground 用户能 Ctrl-C 退出。

## 38. 给 3 个 observer-based controller 加测试 (Phase 10)

**目标**: Phase 8 加了 14 个测试覆盖 3 个 controller (ActiveStateController / MenuBuilder / WindowController)。剩 3 个 observer-based controller (StatusPanelController / NotificationService / HotKeyController) 当时没测 —— 这轮补齐。

**新增测试** (3 个文件, 19 个 test, 总数 14 → 33):
- `StatusPanelControllerTests.swift` (5 tests) — install/uninstall 状态机 + prefs 变化响应 + 多次 toggle 不重复创建
- `NotificationServiceTests.swift` (7 tests) — attachment 创建 + identifier + 文件复制 + postRecordNotification smoke
- `HotKeyControllerTests.swift` (7 tests) — Spec enum 映射 + Carbon 修饰键 mask + 实际 init 不 crash

**为了让测试能访问 production code,做了 2 处小 refactor**:
1. `NotificationService.makeMoodAttachment(for:)` — `private func` → `internal static func`
   - 测试直接调 `NotificationService.makeMoodAttachment(for: .happy)` 验文件复制, 不依赖 UN 投递链路
   - 内部调用改成 `Self.makeMoodAttachment(...)`
2. `HotKeyController.Spec.carbonKeyCode/carbonModifiers` — `fileprivate` → `internal`
   - 测试直接验 Spec enum 映射 (`.optionM` 对应 `kVK_ANSI_M` + `optionKey`)

**为什么这 2 处 refactor 是必要的**:
- 测试用 `@testable import MissingPlusPlus` 能访问 `internal` 但不能访问 `private` / `fileprivate`
- `makeMoodAttachment` 是纯函数 (无副作用 except 写 tmp), 适合直接测
- `Spec` 的属性也是纯计算, 没暴露给测试就只能绕路 (测 init 行为间接推断, 不如直接验)
- refactor 不会破坏 production 行为, 只是把可见性从 "只有自己能用" 扩到 "同 module + test target 都能用"

**StatusPanelController 测试策略**:
- 操纵 `AppPreferences.shared.showStatusItem` 触发 didSet (写 defaults + post .appPreferencesDidChange)
- 检测 `NSApp.windows.contains { $0 is StatusItemPanel && $0.isVisible }` 验 panel 状态
- setUp / tearDown 保存 + 还原 prefs, 调 `dismissAllStatusPanels()` 收尾

**NotificationService 测试策略**:
- `makeMoodAttachment` 直接调 (已经是 internal static), 验附件 identifier 格式 + tmp 路径 + 文件存在
- `postRecordNotification` smoke 测不 crash + 验证 .empty who → "TA" fallback 路径

**HotKeyController 测试策略**:
- `Spec.optionM` 映射到 `kVK_ANSI_M` + `optionKey` 的 Carbon 常量
- Carbon 修饰键 mask (cmdKey=256, shiftKey=512, controlKey=4096, optionKey=2048)
- init 不 crash (验证 Carbon InstallEventHandler + RegisterEventHotKey 不抛)

**踩过的坑** (这轮新加):
1. **pbxproj 只加 PBXSourcesBuildPhase 不够** — Phase 10 第一次只改了 build phase, build 还是只编译 3 个老 test。完整 pbxproj 注册需要 4 处: PBXBuildFile + PBXFileReference + group children + build phase。光 build phase 编译系统认为 file ref 不存在, 跳过。修法: 跟 Phase 8 一样, 4 处都加。
2. **Spec.carbonKeyCode 是 `fileprivate`** — 改成 `internal` 才能 `@testable` 访问。
3. **`kVK_ANSI_Space` 找不到** — `Carbon` import 在 Swift module map 里不包括 HIToolbox/Events.h 里的 ANSI 系列 keys, 只有 `kVK_Space` 这种短的能用。改用 `kVK_Space`。
4. **cmdKey | optionKey 类型不匹配** — Carbon 常量是 `Int`, Spec 期望 `UInt32`, 加显式 cast `UInt32(cmdKey | optionKey)`。
5. **Test 误判 filename 包含 mood name** — `makeMoodAttachment` 实际只生成 `missingpp-mood-{UUID}.png`, 不带 mood name。删掉那条 assertion。

**验证**:
- `xcodebuild -configuration Debug build` → `** BUILD SUCCEEDED **`
- `./scripts/run_tests.sh` → `** TEST SUCCEEDED **`, 33/33 pass
  - ActiveStateControllerTests: 4/4
  - HotKeyControllerTests: 7/7
  - MenuBuilderTests: 6/6
  - NotificationServiceTests: 7/7
  - StatusPanelControllerTests: 5/5
  - WindowControllerTests: 4/4

**保留**: 现有 production 行为无变化 (refactor 1 改 internal static, 调用处改成 `Self.makeMoodAttachment(...)`; refactor 2 改 fileprivate → internal, 不动逻辑)。7 个 controller / service 现在全部有 unit test 覆盖。

**「不要做」(新增 §5.1)**:
- 不要在 pbxproj 里只加 PBXSourcesBuildPhase 而漏 PBXBuildFile / PBXFileReference / group children — build system 会认为 file ref 不存在, 跳过编译。完整 4 处必须同时改。
- 不要给 HotKeyController.Spec 加 Carbon HIToolbox 之外依赖 — 改 `Spec.carbonKeyCode/carbonModifiers` 可见性比在测试里 mock Carbon 调用链简单得多。
- 不要让 StatusPanelController test 留 panel 可见 — 每个 test 的 setUp/tearDown 都调 `dismissAllStatusPanels()`, 否则 test runner 屏幕会越积越多幽灵 panel。
- 不要给 `NotificationService.postRecordNotification` 写"验证 UN 投递成功"的测试 — `UNUserNotificationCenter` 是 process singleton, 没有公开 API 验 "request was added successfully" (除了 try? await), 测试环境投递会真发通知, 干扰 dev 体验。Smoke 测不 crash 就够了。
- 不要给 HotKeyController 写"验证 ⌥M 真的注册成功"的测试 — Carbon EventHotKey 没有公开 API 反查当前 hotkey 绑定, 只能 init 不 crash 作为 smoke。
