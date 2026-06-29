import SwiftUI
import AppKit
import Carbon
import UserNotifications

/// 菜单栏 app 入口。
///
/// AppDelegate 负责：
/// - 自定义 NSPanel 浮动 status item（macOS 26 上 NSStatusItem 默认进
///   Control Center 弹窗辅助区，屏幕顶部菜单栏看不到 — 改用 NSPanel 自己画）
/// - NSMenu 1-click 记录（panel 点击 → 5 mood × who submenu → store.add）
/// - Dock 点击（`applicationShouldHandleReopen` → showMainWindow）
/// - ⌥M 全局热键（Carbon `EventHotKey`）
/// - 通知（`UNUserNotificationCenter`）
/// - 主窗口 / 设置窗口的生命周期
@main
struct MissingPlusPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = MissingStore.shared
    @StateObject private var prefs = AppPreferences.shared
    @StateObject private var storage = StorageService.shared

    var body: some Scene {
        Settings {
            SettingsView(store: store, storage: storage, prefs: prefs)
        }

        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 Missing++") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button("退出 Missing++") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusPanel: StatusItemPanel?
    private var statusMenu: NSMenu?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: () -> Void = {}

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=false (Info.plist): app 启动是 .regular policy, 有
        // Dock icon + 完整 menu bar + 标准 app menu。**不要**调
        // setActivationPolicy(.regular) — macOS 26 上把 NSStatusItem
        // 路由到 Control Center scene, 但我们用的是 NSPanel
        // (`StatusItemPanel`), 不受这个 routing 影响, 所以可以放心
        // 显示 dock icon 同时保留菜单栏 panel。
        installStatusPanel()
        installGlobalHotKey()

        // 监听新记录 → 更新状态栏图标 + 发通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMissingAdded(_:)),
            name: .missingStoreDidAdd,
            object: nil
        )
        // 监听设置入口（保留 notification 路径供未来菜单调用）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings(_:)),
            name: .openSettings,
            object: nil
        )
        // 监听 prefs 变化（showStatusItem / menuBarIconStyle）→ 重画 / 重建 status panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrefsChanged(_:)),
            name: .appPreferencesDidChange,
            object: nil
        )
        // 监听屏幕参数变化（显示器插拔 / 分辨率变化）→ 重新定位 panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // 监听 app 激活（Finder 打开 / Spotlight 启动 / alt-tab 切回来）
        // → 兜底拉主窗口。`applicationShouldHandleReopen` 只在 hidden app
        // 被 Dock 召唤那条路径触发, 没这条的话用户从 Finder / Spotlight 打开
        // 只会看到状态栏 panel (macOS 26 经常被 Control Center 盖住), 找不到主窗口。
        // 0.5s debounce 防抖: 快速 alt-tab 不会反复开/关主窗口。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - 激活兜底 (主窗口)

    private var lastBecomeActiveAt: Date = .distantPast
    private static let becomeActiveDebounce: TimeInterval = 0.5

    @objc private func handleAppDidBecomeActive() {
        let now = Date()
        guard now.timeIntervalSince(lastBecomeActiveAt) >= Self.becomeActiveDebounce else { return }
        lastBecomeActiveAt = now
        // 0.5s 之后才开主窗口, 让 macOS 自己的窗口切换动画跑完, 避免和系统动画打架。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showMainWindow()
        }
    }

    // MARK: - 状态栏 panel

    private func installStatusPanel() {
        guard AppPreferences.shared.showStatusItem else { return }
        if statusPanel != nil { return }
        let panel = StatusItemPanel()
        panel.content.clickTarget = self
        panel.content.clickSelector = #selector(statusPanelClicked)
        panel.content.onDragEnd = { [weak self, weak panel] in
            guard let x = panel?.frame.origin.x else { return }
            UserDefaults.standard.set(Double(x), forKey: Self.panelXKey)
            self?.screenParametersChanged()  // 触发布局 sanity check
        }
        positionStatusPanel(panel)
        panel.orderFront(nil)
        statusPanel = panel
        updateStatusPanelIcon()
    }

    private static let panelXKey = "MissingPlusPlusStatusPanelX"

    private func positionStatusPanel(_ panel: StatusItemPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let panelSize = panel.frame.size
        // 默认位置：屏幕顶部状态栏，screen 60% 处 — 在 Codex menu 结束（~30%）
        // 之后、system status bar items（~70% 起）之前的空隙。
        // 用户可以拖动 panel 到任意位置，x 会持久化到 UserDefaults。
        let savedX = UserDefaults.standard.double(forKey: Self.panelXKey)
        let x: CGFloat = savedX > 0 ? CGFloat(savedX) : frame.maxX * 0.60
        // 垂直居中到 status bar 视觉中心 (macOS 26 status bar 高 33pt，
        // item 22pt 居中 — 中心 y = (frame.maxY + visibleFrame.maxY) / 2)
        let centerY = (frame.maxY + screen.visibleFrame.maxY) / 2
        let y = centerY - panelSize.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc private func screenParametersChanged() {
        if let panel = statusPanel {
            positionStatusPanel(panel)
        }
    }

    private func updateStatusPanelIcon() {
        guard let panel = statusPanel else { return }
        let latestMood = MissingStore.shared.sortedItems.first?.mood
        let image = MenuBarIconRenderer.image(
            mood: latestMood,
            style: AppPreferences.shared.menuBarIconStyle
        )
        panel.setIcon(image)
    }

    // MARK: - 状态栏菜单 (1-click 记录)

    /// 状态栏 panel 点击入口 — pop up 1-click 记录菜单。NSMenu 在
    /// `popUp(...)` 期间由 `statusMenu` 强引用，菜单被用户关掉后系统
    /// 会持有最后一份；下次点 panel 重新 build 一次反映最新的 knownWhos。
    @objc private func statusPanelClicked() {
        guard let panel = statusPanel else { return }
        let menu = buildStatusMenu()
        statusMenu = menu
        // at: (0, 0) in panel.content → 菜单顶端对齐 panel 底端，
        // 系统自动处理"放不下就放上面"的越界翻转
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: 0),
            in: panel.content
        )
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 5 mood 顶层项 — 每个挂一个 who 选择 submenu
        let recentWhos = Array(MissingStore.shared.knownWhos.prefix(5))
        for mood in Mood.allCases {
            let item = NSMenuItem(
                title: "\(mood.emoji)  \(mood.label)",
                action: nil,
                keyEquivalent: ""
            )
            item.submenu = buildMoodSubmenu(for: mood, recentWhos: recentWhos)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openMain = NSMenuItem(
            title: "在主窗口新建记录…",
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: ""
        )
        openMain.target = self
        menu.addItem(openMain)

        menu.addItem(.separator())

        // ⌘Q 已经在 SwiftUI app menu 注册 (CommandGroup(.appTermination)),
        // 这里再 bind 一次让菜单显示快捷键提示
        let quit = NSMenuItem(
            title: "退出 Missing++",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }

    private func buildMoodSubmenu(for mood: Mood, recentWhos: [String]) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false

        // 不要 "TA" 默认 fallback — 用户每次都指定具体对象, "TA" 占位无意义。
        // 直接列 recent whos；每个 who 是一个 submenu, 强度(一般/非常/无)在第三级
        if recentWhos.isEmpty {
            let hint = NSMenuItem(
                title: "(还没有记录过对象)",
                action: nil,
                keyEquivalent: ""
            )
            hint.isEnabled = false
            sub.addItem(hint)
            sub.addItem(.separator())
        } else {
            for who in recentWhos {
                sub.addItem(buildWhoItem(who: who, mood: mood))
            }
            sub.addItem(.separator())
        }

        let custom = NSMenuItem(
            title: "在主窗口记录…",
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: ""
        )
        custom.target = self
        sub.addItem(custom)

        return sub
    }

    private func buildWhoItem(who: String, mood: Mood) -> NSMenuItem {
        let item = NSMenuItem(
            title: who,
            action: nil,
            keyEquivalent: ""
        )
        item.submenu = buildIntensitySubmenu(who: who, mood: mood)
        return item
    }

    private func buildIntensitySubmenu(who: String, mood: Mood) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        // 一般 → 非常 → 无: 一般最常用, 排最前让 Return 直接 = 默认强度
        let order: [Intensity] = [.mild, .strong, .none]
        for intensity in order {
            let item = NSMenuItem(
                title: intensity.label,
                action: #selector(recordFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = RecordRequest(
                mood: mood, who: who, intensity: intensity
            )
            sub.addItem(item)
        }
        return sub
    }

    @objc private func recordFromMenu(_ sender: NSMenuItem) {
        guard let req = sender.representedObject as? RecordRequest else { return }
        let entry = Missing(who: req.who, mood: req.mood, intensity: req.intensity)
        MissingStore.shared.add(entry)
        // 后续流程: MissingStore.add → post .missingStoreDidAdd →
        // handleMissingAdded 收到 → 状态栏图标变 mood 色 + post 系统通知
    }

    @objc private func openMainWindowFromMenu() {
        // 菜单会自动 dismiss，showMainWindow 是 main 窗口标准入口
        showMainWindow()
    }

    /// NSMenuItem.representedObject 的载体 — 把 (mood, who, intensity)
    /// 一起传给 recordFromMenu。struct 比 tuple 友好 (能 as? 强转)。
    private struct RecordRequest {
        let mood: Mood
        let who: String
        let intensity: Intensity
    }

    // MARK: - Dock 点击

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - 主窗口 / 设置窗口

    func showMainWindow() {
        if let window = mainWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "思念计数器"
            window.contentViewController = NSHostingController(
                rootView: MenuBarContent(store: MissingStore.shared)
                    .frame(width: 360, height: 720)
            )
            window.center()
            window.setFrameAutosaveName("MainWindow")
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettingsWindow() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Missing++ 设置"
            window.contentViewController = NSHostingController(
                rootView: SettingsView(
                    store: MissingStore.shared,
                    storage: StorageService.shared
                )
                .frame(width: 480, height: 600)
            )
            window.center()
            window.setFrameAutosaveName("SettingsWindow")
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleOpenSettings(_ note: Notification) {
        showSettingsWindow()
    }

    // MARK: - 状态变化

    @objc private func handleMissingAdded(_ note: Notification) {
        guard let missing = note.userInfo?["missing"] as? Missing else { return }
        // 状态栏图标 mood 联动
        updateStatusPanelIcon()
        postRecordNotification(for: missing)
    }

    @objc private func handlePrefsChanged(_ note: Notification) {
        // showStatusItem 切换：true → 安装 / false → 移除
        if AppPreferences.shared.showStatusItem {
            if statusPanel == nil {
                installStatusPanel()
            } else {
                updateStatusPanelIcon()
            }
        } else if let panel = statusPanel {
            statusMenu = nil
            panel.orderOut(nil)
            statusPanel = nil
        }
    }

    // MARK: - 新增记录 → 通知

    private func postRecordNotification(for missing: Missing) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let who = missing.who.isEmpty ? "TA" : missing.who
        let title = "想念 \(who)"
        let attachment = makeMoodAttachment(for: missing.mood)
        let identifier = "missing-\(missing.id.uuidString)"

        // body 走 AI。AI 关闭/超时/出错 → AIServiceContext.fixedNotificationBody
        // 自动 fallback 到原来的固定模板,用户无感。
        // 1.5s timeout (AIService 内部写死) → 通知最多延迟 1.5s,仍比用户感知快。
        Task { @MainActor in
            let body = await generateAINotificationBody(for: missing)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let attachment {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func makeMoodAttachment(for mood: Mood) -> UNNotificationAttachment? {
        let name = "MenuBarIcon-\(mood.rawValue)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("missingpp-mood-\(UUID().uuidString).png")
        try? FileManager.default.copyItem(at: url, to: tmp)
        return try? UNNotificationAttachment(
            identifier: "mood-\(mood.rawValue)",
            url: tmp,
            options: nil
        )
    }

    // MARK: - 全局快捷键 (⌥M)

    private func installGlobalHotKey() {
        hotKeyHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.showMainWindow()
            }
        }
        registerHotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(optionKey))
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D53504D), id: 1)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                let handler = unsafeBitCast(userData, to: AppDelegate.self)
                handler.hotKeyHandler()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }
}
