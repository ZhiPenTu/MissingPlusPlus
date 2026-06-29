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
    // Status panel 全套走 StatusPanelController, AppDelegate 不再自己装/拆
    private var statusPanelController: StatusPanelController?
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
        // Status panel 走 StatusPanelController — init 内部订阅 prefs / 屏幕参数
        statusPanelController = StatusPanelController(
            onRecord: { mood, who, intensity in
                // 写入 store → post .missingStoreDidAdd → handleMissingAdded
                // → NotificationService.shared.postRecordNotification
                MissingStore.shared.add(Missing(who: who, mood: mood, intensity: intensity))
            },
            onOpenMain: { [weak self] in
                self?.windowController.showMainWindow()
            }
        )
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
        // 状态栏图标 mood 联动: StatusPanelController 自己订阅 .missingStoreDidAdd
        // 系统通知走 NotificationService, AppDelegate 不再自己持 UN 代码
        NotificationService.shared.postRecordNotification(for: missing)
    }

    // MARK: - 全局快捷键 (⌥M)

}
