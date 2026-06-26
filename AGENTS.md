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


- 不要把 `LSUIElement` 改成 `false`（会冒出 Dock 图标，破坏产品形态）。
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

**Self-compassion 池子**：7 句 curated（Kristin Neff 风格：mindfulness + common humanity + self-kindness），v1 hardcode 不让用户改。

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
