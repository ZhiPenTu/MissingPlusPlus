# Update Checker (GitHub Releases) — 设计

> 日期：2026-07-01
> 状态：待 review
> 涉及范围：`Services/UpdateChecker.swift` (新) / `Services/AppPreferences.swift` / `StatusBar/MenuBuilder.swift` / `StatusBar/MenuActionRouter.swift` (私有) / `MissingPlusPlusApp.swift` (AppDelegate) / `Windows/WindowController.swift` / `Views/UpdateBanner.swift` (新) / `Views/MenuBarContent.swift` / `Views/SettingsView.swift` / `MissingPlusPlusTests/UpdateCheckerTests.swift` (新) / `AGENTS.md`

## 1. 背景

`心安日记` (代码名 `MissingPlusPlus`) 的发布管道 (`docs/ci.md` §2 + `release.yml`) 已经成熟：tag push → `build-dmg.sh` → 上传 DMG 到 GitHub Releases (draft)。但**客户端完全没有"检测更新"** —— 用户在跑 v0.0.1 时不会知道 v0.0.2 已经发布，必须自己访问 GitHub Releases 页。

GitHub Releases API 公共 endpoint 稳定（实测 `https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest` 返回 200 + `tag_name: "v0.0.1"` + `html_url` + DMG asset），给自写检查器提供了最简单的零依赖路径。

**这一轮不引入 Sparkle**（理由见 AGENTS §5 现状 + §3 "不变量" + 推荐 B 路径），而是把"检测 + 引导用户去 GitHub 下载"这条链路打通。`UpdateChecker` 抽象层为未来切 Sparkle 留接口（v2 替换实现，UI / 调度不动）。

## 2. 目标

1. **静默检测**：app 启动后 5s 调一次 GitHub Releases API，跟本地 `CFBundleShortVersionString` 比对；有新版就在主窗口顶部挂 banner，sticky（不自动 fade），用户点"稍后"才消失。
2. **手动触发**：状态栏 NSMenu 末尾加 "Check for Updates…" item，立即检查；显示"已是最新" / "新版本 v0.0.X 可用" / "检查失败" 三种状态。
3. **设置可关**：`AppPreferences.updateCheckEnabled` 默认 `true`，Settings 里加 toggle 关闭所有自动/手动检查。
4. **可测试**：`UpdateChecker` 是纯 Swift 类，依赖通过 `URLSessionProtocol` 注入；3 个 XCTest case 覆盖 happy path / 无更新 / 网络失败。
5. **零新依赖**：不引 SPM / CocoaPods / Carthage，URLSession 直接打 GitHub API。
6. **零 controller 互引**：完全遵守 AGENTS §6 "controllers 之间不互相引用" 约束 —— `UpdateChecker` 不持有 `WindowController` 引用，所有跨边界走 NotificationCenter 二级派发。

## 3. 非目标

- **不下载 / 不安装 / 不替换 .app**：banner 跳转 GitHub release 页，用户手动下 DMG + 拖 Applications。下载 + 验签 + 退出时安装是 Sparkle 路线（v2）。
- **不做签名验证**：信 TLS + GitHub 域。GitHub Releases 本身没法验签（DMG 没 .sig），Sparkle 才有 EdDSA 路线。如果未来上 Sparkle，验签能力自动获得。
- **不动 `release.yml`**：现有发布流程（draft release）保持；spec 末尾给出"发布后记得 Publish release"的 checklist 提醒。
- **不动 `Info.plist` / `entitlements` / 部署目标 / Xcode 工程版本号**：`network.client` 已有 entitlement（AGENTS §1 §12），AT 默认走 https 不用加 NSAppTransportSecurity 例外。
- **不引 SPM / CocoaPods / Carthage 依赖**：AGENTS §5 既有约束。
- **不做 Delta 更新 / 增量下载**：完整 DMG 一次拉，10MB 内。
- **不解析 prerelease**：`tag_name` 带 `-alpha` / `-beta` / `-rc` 后缀的 release 默认跳过；这是保守选择，避免给 v0.0.2-alpha 用户推一条"已有 v0.0.1"假阳性。Settings 不暴露 prerelease 开关。
- **不做 release notes 解析**：banner 只展示 `tag_name` + "查看"，不展示 markdown changelog。Sparkle 路线才有 release notes UI。
- **不做国际化**：banner 文案中文硬编码（"新版本 X 可用" / "稍后" / "查看"），跟现有产品文案风格一致（AGENTS §3 "UI 文案"）。
- **不做"立即安装"按钮 / dmg 内嵌升级逻辑**：完全交给 GitHub release 页。

## 4. 架构

### 4.1 数据流 (二级 NotificationCenter 派发)

```
App launch (applicationDidFinishLaunching 末尾)
  └─ UpdateChecker.shared.startBackgroundCheck()         (fire-and-forget)
       │
       ├─ guard: prefs.updateCheckEnabled == true  // 默认 true
       ├─ guard: lastCheckedAt < 6h ago → 跳过     // 频率控制
       └─ Task { await silentCheck() }                  // 后台, async/await
              │
              ├─ URLSession.shared.data(from: githubURL) // User-Agent + Accept header
              │   └─ 失败 → log warning + return (静默吞)
              │
              ├─ parse JSON: tag_name / html_url
              ├─ strip "v" prefix, semver compare vs CFBundleShortVersionString
              ├─ skip prerelease (tag 含 "-")
              │
              └─ if remote > local AND remote != prefs.lastDismissedVersion:
                    └─ NotificationCenter.default.post(.didFindRemoteUpdate,
                         userInfo: ["version": remote, "url": html_url])
                                │
                                └─ AppDelegate 订阅 (queue: .main)：
                                    ├─ windowController.showMainWindow()  // 拉主窗口到前
                                    └─ NotificationCenter.default.post(.showUpdateBanner,
                                         userInfo: ["version": remote, "url": html_url])
                                            │
                                            └─ MenuBarContent (主窗口 SwiftUI root) 订阅：
                                                └─ 挂 UpdateBanner (顶部 overlay, sticky)

StatusBar NSMenu "Check for Updates…" item tapped
  └─ MenuBuilder onCheckForUpdates closure → AppDelegate
       └─ MenuActionRouter.checkForUpdatesFromMenu(_:)
              ├─ item title 改 "Checking…", disabled
              ├─ Task { await UpdateChecker.shared.checkNow() }
              └─ result 分支:
                  ├─ .upToDate → NSAlert("已是最新 v0.0.1")
                  ├─ .updateAvailable(v, url) → NSWorkspace.open(url) + main window banner (同上)
                  └─ .failed(reason) → NSAlert("检查更新失败: <reason>")
```

**为什么二级派发不直接 callback**:
- AGENTS §6 "controllers 之间不互相引用" —— `UpdateChecker` 不能持有 `WindowController`
- `MenuBarContent` 是 SwiftUI view,无法被 `UpdateChecker` 直接持有
- NotificationCenter 是项目现有 pattern (`missingStoreDidAdd` → `NotificationService` 走的就是它)
- 二级派发也解耦了"谁负责检测"和"谁负责展示"

### 4.2 `Services/UpdateChecker.swift` (新)

```swift
extension Notification.Name {
    /// Posted by UpdateChecker when remote version > local. userInfo: ["version": String, "url": URL]
    static let didFindRemoteUpdate = Notification.Name("UpdateCheckerDidFindRemoteUpdate")
    /// Posted by AppDelegate after receiving .didFindRemoteUpdate, to ask MenuBarContent
    /// to mount the banner overlay. userInfo: ["version": String, "url": URL]
    static let showUpdateBanner = Notification.Name("UpdateCheckerShowUpdateBanner")
}

enum UpdateCheckResult: Equatable {
    case upToDate(localVersion: String)
    case updateAvailable(version: String, url: URL)
    case failed(reason: String)
}

protocol URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse)
}
extension URLSession: URLSessionProtocol {}

/// 跟 NotificationService.shared 一样是单例;不持有 controller 引用,只发 notification。
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let session: URLSessionProtocol
    private let prefs: AppPreferences
    private let githubURL: URL
    private var inFlight: Task<Void, Never>?

    init(
        session: URLSessionProtocol = URLSession.shared,
        prefs: AppPreferences = .shared,
        githubURL: URL = URL(string: "https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest")!
    ) {
        self.session = session
        self.prefs = prefs
        self.githubURL = githubURL
    }

    /// 启动后 fire-and-forget;走 6h 节流。失败/无更新都静默,不发 notification。
    func startBackgroundCheck() {
        guard prefs.updateCheckEnabled else { return }
        guard shouldCheckNow() else { return }
        inFlight = Task { [weak self] in
            await self?.silentCheck()
        }
    }

    /// 手动触发,不走节流;返回结果给菜单调用方 (NSAlert / NSWorkspace).
    func checkNow() async -> UpdateCheckResult {
        guard prefs.updateCheckEnabled else {
            return .failed(reason: "已在设置中关闭")
        }
        return await performCheck()
    }

    private func shouldCheckNow() -> Bool {
        guard let last = prefs.lastCheckedAt else { return true }
        return Date().timeIntervalSince(last) > 6 * 3600
    }

    private func silentCheck() async {
        let result = await performCheck()
        if case .updateAvailable(let version, let url) = result {
            NotificationCenter.default.post(
                name: .didFindRemoteUpdate,
                object: self,
                userInfo: ["version": version, "url": url]
            )
        }
    }

    private func performCheck() async -> UpdateCheckResult {
        // lastCheckedAt 在 disable-check 情况下不更新,避免污染时间戳
        prefs.lastCheckedAt = Date()

        do {
            var request = URLRequest(url: githubURL)
            request.setValue("MissingPlusPlus/0.0.1 (macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(from: githubURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .failed(reason: "GitHub 返回 HTTP \(code)")
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString) else {
                return .failed(reason: "响应格式不符")
            }

            // 跳过 prerelease (e.g. "v0.0.2-alpha")
            if tagName.contains("-") { return .upToDate(localVersion: currentLocalVersion()) }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let local = currentLocalVersion()

            if compareSemver(remote: remoteVersion, local: local) > 0 {
                prefs.lastKnownRemoteVersion = remoteVersion
                return .updateAvailable(version: remoteVersion, url: htmlURL)
            } else {
                return .upToDate(localVersion: local)
            }
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    private func currentLocalVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 返回 > 0: remote > local; < 0: remote < local; == 0: 相等
    private func compareSemver(remote: String, local: String) -> Int {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv - lv }
        }
        return 0
    }
}
```

**为什么 `final class` 不是 `actor`**:
- `AppPreferences` 是 `@MainActor`,`actor` 跨 actor 访问会要求 `await MainActor.run { ... }` 嵌套,代码丑
- 项目现有 `NotificationService.shared` / `MissingStore.shared` 都是 `@MainActor final class` 模式
- URLSession `data(from:)` 本身是 `async` 不阻塞主线程,不需要额外 actor 隔离
- 实际并发保护靠 `inFlight: Task` 字段,防止多次 in-flight 检查 (race)

**为什么 `inFlight: Task`**:
- 用户连续点 "Check for Updates…" → 避免 race
- `Task` cancel 旧任务,start 新的 (或者用串行: `if inFlight != nil { return }` 然后 await inFlight?.value)

简化版(用 NSLock 串行化):
```swift
private let checkLock = NSLock()
func checkNow() async -> UpdateCheckResult {
    checkLock.lock(); defer { checkLock.unlock() }
    // ... performCheck ...
}
```

spec 落地时二选一,推荐 `NSLock` 版本(更直白)。

### 4.3 `Services/AppPreferences.swift` 新增字段

按现有 `@Published var xxx: Bool { didSet { defaults.set(xxx, forKey: Keys.xxx) } }` 风格:

```swift
/// v0.0.2 update-checker: 启动 5s 后静默检查 GitHub Releases;有新版在主窗口顶部
/// 弹 banner。默认开。关闭后连手动 "Check for Updates…" 也禁用。
@Published var updateCheckEnabled: Bool {
    didSet { defaults.set(updateCheckEnabled, forKey: Keys.updateCheckEnabled) }
}
/// v0.0.2 update-checker: 启动检查节流用。transient, 不持久化。
@Published var lastCheckedAt: Date?
/// v0.0.2 update-checker: 上次发现的 remote version (debug/UI 用)。transient, 不持久化。
@Published var lastKnownRemoteVersion: String?
/// v0.0.2 update-checker: 用户点过 "稍后" 的版本。持久化,避免每次启动都重弹同一版本。
@Published var lastDismissedVersion: String? {
    didSet { defaults.set(lastDismissedVersion, forKey: Keys.lastDismissedVersion) }
}

private enum Keys {
    // ... 现有 14 个 key ...
    static let updateCheckEnabled = "UpdateCheckEnabled"
    static let lastDismissedVersion = "UpdateCheckerLastDismissedVersion"
}

// init() 末尾追加:
self.updateCheckEnabled = defaults.object(forKey: Keys.updateCheckEnabled) as? Bool ?? true
self.lastCheckedAt = nil  // transient
self.lastKnownRemoteVersion = nil  // transient
self.lastDismissedVersion = defaults.string(forKey: Keys.lastDismissedVersion)
```

**transient 字段不持久化**:
- `lastCheckedAt`: 重启后重新计 6h,无所谓丢
- `lastKnownRemoteVersion`: debug 用,丢无所谓
- `updateCheckEnabled` + `lastDismissedVersion`: 持久化 (`UserDefaults` Bool / String?)

**`SettingsView` 怎么拿到 `prefs`**:
- 现有 `SettingsView` 由 `WindowController.handleOpenSettings` 创建,只接收 `store: MissingStore.shared` + `storage: StorageService.shared`,**不**接收 prefs
- spec §4.7 在 SettingsView 内部用 `@ObservedObject private var prefs = AppPreferences.shared` 拿引用
- (如果未来 `SettingsView` 抽成单独子 view,可以让父 view 通过 `@EnvironmentObject` 注入,本轮不抽)

### 4.4 `StatusBar/MenuBuilder.swift` 加 closure + item

跟现有 `onRecord:onOpenMain:onQuit` 模式一致,加第 4 个 closure:

```swift
@MainActor
final class MenuBuilder {
    private let router: MenuActionRouter

    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,  // 新增
        onQuit: @escaping () -> Void
    ) {
        self.router = MenuActionRouter(
            onRecord: onRecord,
            onOpenMain: onOpenMain,
            onCheckForUpdates: onCheckForUpdates,
            onQuit: onQuit
        )
    }

    func build(recentWhos: [String]) -> NSMenu {
        // ... 现有 5 mood + "在主窗口新建记录…" + "退出 心安日记" ...

        // 在 "在主窗口新建记录…" 之后, "退出" 之前插入:
        menu.addItem(.separator())

        let checkItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(MenuActionRouter.checkForUpdatesFromMenu(_:)),
            keyEquivalent: ""
        )
        checkItem.target = router
        menu.addItem(checkItem)

        menu.addItem(.separator())

        let quit = NSMenuItem( /* ... 现有 ... */ )
        menu.addItem(quit)

        return menu
    }
}
```

**`MenuActionRouter` (私有 NSObject 子类) 加 @objc action**:

```swift
private final class MenuActionRouter: NSObject {
    private let onRecord: (Mood, String, Intensity) -> Void
    private let onOpenMain: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) { ... }

    @objc func openMainFromMenu(_ sender: NSMenuItem) { onOpenMain() }
    @objc func quitFromMenu(_ sender: NSMenuItem) { onQuit() }
    @objc func checkForUpdatesFromMenu(_ sender: NSMenuItem) {
        // 1. 立即 disable item + 改 title
        sender.title = "Checking…"
        sender.isEnabled = false
        // 2. 异步查
        Task { @MainActor in
            let result = await UpdateChecker.shared.checkNow()
            // 3. 恢复 item
            sender.title = "Check for Updates…"
            sender.isEnabled = true
            // 4. 弹结果 (详见 §4.5 MenuActionRouter 的 presentResult 流程)
            MenuActionRouter.presentResult(result)
        }
    }

    private static func presentResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate(let local):
            let alert = NSAlert()
            alert.messageText = "已是最新"
            alert.informativeText = "当前 v\(local) 已是最新版本。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        case .updateAvailable(let version, let url):
            // 直接打开 release 页,banner 由 .didFindRemoteUpdate 自动挂上
            NSWorkspace.shared.open(url)
        case .failed(let reason):
            let alert = NSAlert()
            alert.messageText = "检查更新失败"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}
```

**AppDelegate 创建 MenuBuilder 时传新 closure**:

```swift
// MissingPlusPlusApp.swift / AppDelegate statusPanelClicked:
let builder = MenuBuilder(
    onRecord: { mood, who, intensity in
        MissingStore.shared.add(who: who, mood: mood, intensity: intensity)
    },
    onOpenMain: { [weak self] in
        self?.windowController.showMainWindow()
    },
    onCheckForUpdates: {  // 新增, 直接走 UpdateChecker (closure 内部异步)
        // 注意: 这里只是路由,NSAert / open 调用在 MenuActionRouter 内部做
        // 为避免循环,presentResult 写成 MenuActionRouter 的 static 方法
    },
    onQuit: { NSApp.terminate(nil) }
)
```

**简化**:把 `onCheckForUpdates` closure 在 AppDelegate 里实现也 OK,但要小心 Task capture。看 `MenuActionRouter` 现有 `openMainFromMenu` 的模式,closure 在 router init 时就 capture 住了,AppDelegate 这边 closure 短小,只要不持有 router 之外的 state 就 OK。

### 4.5 `MissingPlusPlusApp.swift` (AppDelegate) wiring

```swift
// applicationDidFinishLaunching 末尾 (在现有 NotificationService.shared 订阅之后):
UpdateChecker.shared.startBackgroundCheck()

// 订阅 .didFindRemoteUpdate
NotificationCenter.default.addObserver(
    forName: .didFindRemoteUpdate, object: nil, queue: .main
) { [weak self] note in
    guard let version = note.userInfo?["version"] as? String,
          let url = note.userInfo?["url"] as? URL else { return }
    guard let self = self else { return }
    // 1. 把主窗口拉前
    self.windowController.showMainWindow()
    // 2. 二级派发,让 MenuBarContent 挂 banner
    NotificationCenter.default.post(
        name: .showUpdateBanner, object: nil,
        userInfo: ["version": version, "url": url]
    )
}
```

**AppDelegate 持有 windowController 是 wiring 期的合法持有**(AGENTS §6 表格明确: "AppDelegate 不持任何 window / panel / hotkey ref" — 但**wiring 期 new + 持有引用**是 OK 的,因为没有 controller 之间的互引)。

### 4.6 `Views/UpdateBanner.swift` (新) + `Views/MenuBarContent.swift` 挂载

`UpdateBanner.swift` (新, ~55 行):
```swift
struct UpdateBanner: View {
    let version: String
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("新版本 v\(version) 可用")
                    .font(.subheadline.weight(.medium))
                Text("点击「查看」去 GitHub release 页下载最新 DMG。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("稍后") { onDismiss() }
                .buttonStyle(.borderless)
            Button("查看") {
                NSWorkspace.shared.open(url)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.12), Color.pink.opacity(0.04)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.pink.opacity(0.25)),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

`MenuBarContent.swift` 加 @State + 订阅:
```swift
struct MenuBarContent: View {
    @ObservedObject var store: MissingStore
    @State private var updateBanner: (version: String, url: URL)?
    @State private var bannerVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 1. banner overlay (top, sticky)
            if let banner = updateBanner, bannerVisible {
                UpdateBanner(
                    version: banner.version,
                    url: banner.url,
                    onDismiss: {
                        AppPreferences.shared.lastDismissedVersion = banner.version
                        withAnimation { bannerVisible = false }
                    }
                )
            }

            // 2. 现有 NewMissingForm / HistoryList / StatisticsView tabs
            // (不动, 走原 content)
            // ...
        }
        .onReceive(NotificationCenter.default.publisher(for: .showUpdateBanner)) { note in
            guard let version = note.userInfo?["version"] as? String,
                  let url = note.userInfo?["url"] as? URL else { return }
            // 同版本已 dismiss 过 → 不重弹
            if AppPreferences.shared.lastDismissedVersion == version { return }
            withAnimation {
                updateBanner = (version, url)
                bannerVisible = true
            }
        }
    }
}
```

**为什么用 `.onReceive(NotificationCenter.publisher)` 不是 `addObserver`**:
- SwiftUI 风格,生命周期跟 view 自动绑定,view dismiss 时自动 cancel
- 跟现有 `MissingStore.shared` 一样用 `@ObservedObject` 接 store,新 notification 用 `.onReceive` 接

**banner 跟 NewMissingForm header 视觉对齐**:
- NewMissingForm header (AGENTS §11 §16) 是 pink 渐变 + 圆形 avatar
- UpdateBanner 用同色系 pink 渐变 0.12→0.04,保持产品调性

### 4.7 `Views/SettingsView.swift` 新增 section

`SettingsView` 现有结构 (需要 grep 确认) 大致是 `Form { Section { ... } }` 一组 section,加新 section:

```swift
@MainActor
struct SettingsView: View {
    let store: MissingStore
    let storage: StorageService
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var isChecking = false

    var body: some View {
        Form {
            // ... 现有 sections ...

            Section("更新") {
                Toggle("自动检查更新", isOn: $prefs.updateCheckEnabled)
                Text("启动 5s 后静默检查 GitHub Releases,有新版时主窗口顶部提示。")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Button("立即检查") {
                        isChecking = true
                        Task { @MainActor in
                            _ = await UpdateChecker.shared.checkNow()
                            isChecking = false
                        }
                    }
                    .disabled(isChecking)
                    if isChecking { ProgressView().controlSize(.small) }
                    if let last = prefs.lastCheckedAt {
                        Text("上次检查：\(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
```

`lastCheckedAt` transient + UI 显示,让用户感知"检查过没"。

## 5. 文件改动清单

| 文件 | 改动类型 | 大致行数 |
|---|---|---|
| `Services/UpdateChecker.swift` | 新建 | ~110 |
| `Services/AppPreferences.swift` | 改 (4 字段 + 2 Keys + init 4 行) | +25 |
| `StatusBar/MenuBuilder.swift` | 改 (1 closure + 1 item + 1 separator) | +15 |
| `StatusBar/MenuBuilder.swift` 内部 `MenuActionRouter` | 改 (1 closure + 1 @objc + 1 static) | +35 |
| `MissingPlusPlusApp.swift` (AppDelegate) | 改 (1 启动调用 + 1 NotificationCenter 订阅 + 1 MenuBuilder init 参数) | +20 |
| `Windows/WindowController.swift` | **不改** (AppDelegate 调 `showMainWindow()` 即可) | 0 |
| `Views/UpdateBanner.swift` | 新建 | ~55 |
| `Views/MenuBarContent.swift` | 改 (2 @State + 1 onReceive + 1 if) | +25 |
| `Views/SettingsView.swift` | 改 (1 @ObservedObject + 1 Section) | +25 |
| `MissingPlusPlusTests/UpdateCheckerTests.swift` | 新建 | ~100 |
| `project.pbxproj` | 改 (新 3 文件注册) | +6 (走 `patch-pbxproj.py` idempotent) |
| `AGENTS.md` | 改 (§24 新增 "Update Checker (v0.0.2+)" 章节) | +50 |

**总计**:9 个文件改 + 2 个文件新建,~365 行新增,~5 行删除。

**不动**:`Info.plist` / `entitlements` / `release.yml` / `build-dmg.sh` / `run_tests.sh` / `build_and_run.sh` / `Windows/WindowController.swift`。

## 6. 错误处理

| 场景 | 行为 |
|---|---|
| 启动 5s 后 `prefs.updateCheckEnabled == false` | 完全跳过,不联网 |
| 6h 内已检查 (transient `lastCheckedAt`) | 跳过自动检查(手动菜单项不受限) |
| HTTP 4xx (e.g. 403 rate limit) | log warning, 静默吞;返回 `.failed(reason: "GitHub 返回 HTTP 403")` |
| HTTP 5xx | 同上 |
| URLSession 网络错 (DNS / timeout) | log warning, 静默吞;返回 `.failed(reason: <error>)` |
| JSON 解析失败 | log warning, 静默吞;返回 `.failed(reason: "响应格式不符")` |
| `tag_name` 含 `-` (prerelease) | 视为"已是最新",返回 `.upToDate`,不推 banner |
| `CFBundleShortVersionString` 缺失 | fallback `"0.0.0"`,所有 remote 都视为更新 —— fail-safe |
| GitHub API rate limit (60/h 未认证) | 返回 403,走"HTTP 4xx"分支 log warning |
| 用户点过"稍后"同版本 (`lastDismissedVersion`) | 不重弹 (在 `MenuBarContent.onReceive` 检查) |
| 状态栏 "Check for Updates…" 检查中 | item title 变 "Checking…",disabled |
| 检查失败手动触发 | NSAlert("检查更新失败: <reason>") |
| 已最新手动触发 | NSAlert("当前 v0.0.1 已是最新版本。") |
| 启动检查发现新版本但主窗口已关闭 | `showMainWindow()` 拉主窗口到前,banner 挂上 |
| 启动检查发现新版本但主窗口已开但被遮 | `showMainWindow()` `makeKeyAndOrderFront` 拉到前,banner 挂上 |

**为什么静默吞 (启动检查失败)**:
- 启动 5s 检查失败不应该 NSAlert 打断用户(AGENTS §17 "焦虑型不被打扰")
- banner 本身只在"真有更新"时出现,fail 路径对用户透明
- log 输出让 dev / 高级用户在 Console.app 里能看到

**为什么手动检查失败弹 NSAlert**:
- 用户主动点了菜单,期待反馈
- 静默吞会让用户怀疑"是不是又卡了"

**`NSLog` vs `os.Logger`**:
- 现有项目用 `NSLog` (AGENTS §6 数据流注释中提到),保持一致
- 前缀 `[MissingPlusPlus] update: ...` 跟其他 controller 一致

## 7. 测试策略

`MissingPlusPlusTests/UpdateCheckerTests.swift` 5 个 case,走 `URLSessionProtocol` mock:

```swift
final class MockURLSession: URLSessionProtocol {
    var stubbedData: Data?
    var stubbedResponse: URLResponse?
    var stubbedError: Error?
    var lastRequest: URLRequest?
    func data(from url: URL) async throws -> (Data, URLResponse) {
        if let error = stubbedError { throw error }
        return (stubbedData ?? Data(), stubbedResponse ?? URLResponse())
    }
}

final class UpdateCheckerTests: XCTestCase {
    var mockSession: MockURLSession!
    var mockPrefs: AppPreferences!
    var checker: UpdateChecker!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        // AppPreferences 是 @MainActor + singleton, 需要小心测试内 init
        // 这里用一个 in-memory mock 替代 (或者在测试 setUp/tearDown 隔离 UserDefaults)
    }

    // 1. happy path: remote v0.0.2 > local v0.0.1 → .updateAvailable
    // 2. no update: remote v0.0.1 == local v0.0.1 → .upToDate
    // 3. network failure: URLError(.notConnectedToInternet) → .failed
    // 4. prerelease: tag_name = "v0.0.2-alpha" → .upToDate
    // 5. semver compare edge: remote v1.0.0 > local v0.99.99 → .updateAvailable
}
```

**测试挑战**:
- `AppPreferences.shared` 是 singleton + 真实 UserDefaults,测试会污染 user 状态
- 解决方案 A: `AppPreferences` init 接受 `defaults: UserDefaults` 参数 (用 `.init(suiteName: "test")` 隔离)
- 解决方案 B: 测试只测 `UpdateChecker` 的 `performCheck` 私有逻辑,把 `prefs` 抽象成 protocol
- 落地时选 A (更小 diff,只改 AppPreferences init 一行)

mock URLSession 不需要真打网络,测试稳定 / 快 / 不依赖 GitHub。

**集成验证** (不走 XCTest, 人肉跑):
1. `bash scripts/build_and_run.sh` 启动 app
2. 启动后 5s 主窗口顶部出 pink banner "新版本 v0.0.2 可用" (临时改 CFBundleShortVersionString 到 0.0.0 模拟)
3. 点 "查看" → 浏览器打开 release 页
4. 退出 → 改回 0.0.1 → 重启 → banner 不重弹 (lastDismissedVersion 持久化生效)
5. 状态栏点开 → "Check for Updates…" → item 变 "Checking…" → 几秒后 → NSAlert "已是最新 v0.0.1"

## 8. 发布流程 (用户动作, 不动 release.yml)

`release.yml` 当前 `draft: true` (AGENTS §23 解释是"用户手动 review + publish")。**GitHub API `/releases/latest` 不会返回 draft release**,所以:

**publish checklist** (在 `AGENTS.md` §24 末尾加一行,或在 `docs/ci.md` §2 末尾加):
1. 现有步骤:tag push → CI 跑 → draft release 创建
2. **新增**:GitHub Releases 页面打开 draft,点 "Publish release" 公开
3. **新增**:Publish 完几分钟后,跑一次 v0.0.1 的 app → 启动 5s 后 banner 应该出 (如果本地是 v0.0.1,远端是 v0.0.2,等场景)

**为什么不改 release.yml**:
- 现有设计意图是"用户手动 review release notes" (AGENTS §23 §2)
- 自动 publish 会让 DMG 还没验证就公开,违背 review 流程
- 一次小代价 (每次发布多 1 次点击) 换稳定 review,值得

**v2 优化方向 (out of scope)**:release.yml 拆成两段 workflow_dispatch,先 "build & upload draft",再 "publish after manual approval",GitHub 内置 "Environments + required reviewers" 也能做,但这是 v2 的话题。

## 9. 风险

| 风险 | 严重度 | 缓解 |
|---|---|---|
| GitHub API 改协议 (e.g. 强制 v4) | 低 | `Accept: application/vnd.github+json` 显式声明,跟当前 v3 兼容 |
| 未认证 API 限流 60/h | 低 | 6h 节流 + 启动 1 次,正常用户用不到上限;限流了 fail-silent |
| DMG 名字 / 路径变了,GitHub Release 找不到 asset | 低 | 我们的 API 调用只读 `tag_name` + `html_url`,**不**解析 asset list;asset list 解析留 Sparkle |
| 用户在企业网 / 防火墙禁 GitHub | 中 | fail-silent;Settings 显示 `lastCheckedAt` 让用户感知 |
| `lastDismissedVersion` 持久化用错 key 跟 `updateCheckEnabled` 冲突 | 低 | UserDefaults 用明确 key (Keys enum) 隔离 |
| 用户改 `CFBundleShortVersionString` 测试时不重 build | 低 | Info.plist 改 version → Clean build 才能生效,文档化 |
| `AppPreferences` 是 singleton + 真实 UserDefaults,测试污染 | 中 | AppPreferences init 加 `defaults: UserDefaults = .standard` 参数,测试用 suite 隔离 |
| banner 把表单挤出去 | 低 | banner 走 SwiftUI `.transition` + `withAnimation`,主窗口 ScrollView 留足 padding |
| 主窗口在屏外 / minimized 时 banner 看不见 | 中 | `showMainWindow()` 在挂 banner 前先拉主窗口到前 (§4.5 已包含) |
| 状态栏 "Check for Updates…" 多次点击 race | 低 | `NSLock` (或 `Task` cancel) 串行化 check (§4.2 已设计) |
| `MenuBarContent` 关闭后 `.onReceive` 还活着 | 低 | SwiftUI `.onReceive` 自动跟 view lifecycle 绑定,view 释放时自动 cancel |
| GitHub user/org rename 后 URL 失效 | 极低 | URL 是常量写在 spec §4.2,真实发生时 1 行改 URL |

## 10. 未来扩展 (out of scope, 仅记录)

- **Sparkle 切换路径**:把 `UpdateChecker` 内部实现替换成 `SPUUpdater` adapter,banner / 菜单 / Settings UI 都不动;`UpdateCheckResult` 三 case 跟 Sparkle 的 `SPUUpdateCheckResult` 1-1 映射
- **release notes UI**:banner 加 expandable 区域,从 GitHub Release `body` 字段拉 markdown 渲染
- **prerelease 开关**:Settings 加 "包含 prerelease",给 v0.1.0-alpha 内部测试用
- **自动下载 + 退出时安装**:Sparkle 路线
- **iCloud 同步 + Update**:多设备时只在 one device 弹 banner(同 iCloud account)
