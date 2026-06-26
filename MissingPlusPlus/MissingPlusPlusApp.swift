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

// MARK: - Floating Status Panel
//
// macOS 26 上 NSStatusItem 默认进 Control Center 弹窗辅助区，屏幕顶部
// 菜单栏看不到 — 不管 .regular / .accessory / autosaveName / Visible Item-N
// 怎么设都不行。绕开 NSStatusItem 路线，直接用 NSPanel 在屏幕顶部右侧画
// 一个浮动 button：level = .statusBar（盖在 system status bar 之上）、
// nonactivatingPanel（不抢焦点）、canJoinAllSpaces（全屏也能看到）。
//
// 渲染走 MenuBarIconRenderer（heart / emoji / 思字 三种 style + 5 mood 染色），
// mood 联动通过重新 setIcon 实现。

final class StatusItemView: NSView {
    weak var clickTarget: AnyObject?
    var clickSelector: Selector?
    private let imageView = NSImageView()
    private var dragStartLocation: NSPoint = .zero
    /// 拖动结束回调 — AppDelegate 那边把 panel.frame.origin.x 写进 UserDefaults
    var onDragEnd: (() -> Void)?
    /// 拖动超过这个距离才算 drag，避免跟 click 冲突
    private let dragThreshold: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setIcon(_ image: NSImage) {
        imageView.image = image
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let current = event.locationInWindow
        let dx = current.x - dragStartLocation.x
        // 只在超过 threshold 时才算 drag，避免 click 误触
        if abs(current.x - dragStartLocation.x) < dragThreshold &&
           abs(current.y - dragStartLocation.y) < dragThreshold {
            return
        }
        let newOrigin = NSPoint(
            x: window.frame.origin.x + dx,
            y: window.frame.origin.y
        )
        window.setFrameOrigin(newOrigin)
        dragStartLocation = current
    }

    override func mouseUp(with event: NSEvent) {
        let moved = abs(event.locationInWindow.x - dragStartLocation.x) +
                    abs(event.locationInWindow.y - dragStartLocation.y)
        if moved < dragThreshold {
            // 没拖 — 当 click 处理
            if let target = clickTarget, let sel = clickSelector {
                _ = target.perform(sel, with: self)
            }
        } else {
            onDragEnd?()
        }
    }
}

final class StatusItemPanel: NSPanel {
    let content: StatusItemView

    init() {
        let size = NSSize(width: 22, height: 22)
        self.content = StatusItemView(frame: NSRect(x: 2, y: 2, width: 18, height: 18))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.contentView = content
    }

    func setIcon(_ image: NSImage) {
        content.setIcon(image)
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
        // 保持 LSUIElement=true 启动的 .accessory (UIElement) 默认 policy。
        // **不要**调 setActivationPolicy(.regular) — macOS 26 上会把
        // NSStatusItem 路由进 com.apple.controlcenter.statusitems scene
        // （Control Center 弹窗辅助区），屏幕顶部菜单栏看不到。
        // 改走 NSPanel 自定义浮动 panel（见 StatusItemPanel 上方注释）。
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

        let content = UNMutableNotificationContent()
        let who = missing.who.isEmpty ? "TA" : missing.who
        content.title = "想念 \(who)"
        let base = "心情：\(missing.mood.label)　程度：\(missing.intensity.label)"
        let triggerPart: String
        if AppPreferences.shared.notificationIncludeTriggers,
           !missing.triggerTags.isEmpty {
            let strs = missing.triggerTags.map(\.displayString)
            triggerPart = "　触发：" + strs.joined(separator: " ")
        } else {
            triggerPart = ""
        }
        content.body = base + triggerPart
        if let attachment = makeMoodAttachment(for: missing.mood) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(
            identifier: "missing-\(missing.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { _ in }
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
