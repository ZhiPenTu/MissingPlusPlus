import SwiftUI
import AppKit

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
    // 主窗口 / 设置窗口的生命周期在 WindowController 里,AppDelegate 只管转发入口。
    private let windowController = WindowController()
    private var statusPanel: StatusItemPanel?
    private var statusMenu: NSMenu?
    // Carbon ⌥M 全局热键走 HotKeyController, AppDelegate 不再自己装
    private var hotKeyController: HotKeyController?

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=false (Info.plist): app 启动是 .regular policy, 有
        // Dock icon + 完整 menu bar + 标准 app menu。**不要**调
        // setActivationPolicy(.regular) — macOS 26 上把 NSStatusItem
        // 路由到 Control Center scene, 但我们用的是 NSPanel
        // (`StatusItemPanel`), 不受这个 routing 影响, 所以可以放心
        // 显示 dock icon 同时保留菜单栏 panel。
        installStatusPanel()
        // ⌥M 全局热键 — Carbon EventHotKey 走 HotKeyController
        hotKeyController = HotKeyController(
            spec: .optionM,
            onTrigger: { [weak self] in
                self?.windowController.showMainWindow()
            }
        )

        // 监听新记录 → 更新状态栏图标 + 发通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMissingAdded(_:)),
            name: .missingStoreDidAdd,
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
        // 每次点击都 new MenuBuilder — builder + router 都是短命对象,
        // 跟 popUp 一起释放。actions 走 closure 注入, 不用在 AppDelegate
        // 持 @objc method。
        let builder = MenuBuilder(
            onRecord: { [weak self] mood, who, intensity in
                self?.recordMissing(mood: mood, who: who, intensity: intensity)
            },
            onOpenMain: { [weak self] in
                self?.windowController.showMainWindow()
            },
            onQuit: {
                // ⌘Q 已经在 SwiftUI app menu 注册, 这里菜单再 bind 一次
                // 让用户能从状态栏菜单退出
                NSApp.terminate(nil)
            }
        )
        let menu = builder.build(
            recentWhos: Array(MissingStore.shared.knownWhos.prefix(5))
        )
        statusMenu = menu
        // at: (0, 0) in panel.content → 菜单顶端对齐 panel 底端,
        // 系统自动处理"放不下就放上面"的越界翻转
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: 0),
            in: panel.content
        )
    }

    private func recordMissing(mood: Mood, who: String, intensity: Intensity) {
        MissingStore.shared.add(Missing(who: who, mood: mood, intensity: intensity))
        // 后续流程: MissingStore.add → post .missingStoreDidAdd →
        // handleMissingAdded 收到 → 状态栏图标变 mood 色 + post 系统通知
    }

    // MARK: - Dock 点击

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController.showMainWindow()
        return true
    }

    // MARK: - 主窗口 / 设置窗口

    // Dock / ⌥M / 状态栏 NSMenu "在主窗口记录" 都走这,真正 lazy 创建 +
    // frame autosave 在 WindowController 里,AppDelegate 不持有 window state。
    func showMainWindow() {
        windowController.showMainWindow()
    }

    // MARK: - 状态变化

    @objc private func handleMissingAdded(_ note: Notification) {
        guard let missing = note.userInfo?["missing"] as? Missing else { return }
        // 状态栏图标 mood 联动
        updateStatusPanelIcon()
        // 系统通知走 NotificationService, AppDelegate 不再自己持 UN 代码
        NotificationService.shared.postRecordNotification(for: missing)
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

    // MARK: - 全局快捷键 (⌥M)

}
