import SwiftUI
import AppKit

/// 菜单栏 app 入口。
///
/// 中文产品名：**心安日记** (CFBundleDisplayName)。代码名沿用 `MissingPlusPlus`
/// (CFBundleName / Bundle ID / 文件系统路径, 不动 — 改这个会丢用户数据)。
///
/// AppDelegate 现在是纯 wiring 层 — 创建 4 个 controller, 转发 3 个 entry point
/// (Dock click / ⌥M / 状态栏 panel click) + 1 个 dock reopen 回调, 订阅
/// .missingStoreDidAdd 转给 NotificationService。具体的实现细节在
/// `StatusBar/` + `Windows/` + `Services/` 目录的 controller / service 里。
///
/// 4 个 controller:
/// - `WindowController` — 主窗口 + 设置窗口 NSWindow 生命周期
/// - `StatusPanelController` — 状态栏 panel 装/卸 + click + 拖动
/// - `HotKeyController` — Carbon ⌥M 全局热键
/// - `ActiveStateController` — app 激活兜底拉主窗口
///
/// 1 个 service (singleton):
/// - `NotificationService.shared` — 新记录 → 系统通知
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
                Button("关于 心安日记") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button("退出 心安日记") {
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
    // App 激活兜底 (拉主窗口) 走 ActiveStateController, AppDelegate 不再自己 debounce
    private var activeStateController: ActiveStateController?

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=false (Info.plist): app 启动是 .regular policy, 有
        // Dock icon + 完整 menu bar + 标准 app menu。**不要**再显式调
        // setActivationPolicy(.regular) — 多余的重复设置在 macOS 26 上
        // 会触发 NSStatusItem 被路由到 Control Center scene 的 bug, 让
        // 状态栏 icon 看不到。Info.plist 已经声明 .regular, AppKit
        // 启动时直接按这个走就行。
        // Status item 走 StatusPanelController (NSStatusItem 路线) — init 内部订阅 prefs / missingStore
        statusPanelController = StatusPanelController(
            onRecord: { mood, who, intensity in
                // 写入 store → post .missingStoreDidAdd → handleMissingAdded
                // → NotificationService.shared.postRecordNotification
                MissingStore.shared.add(Missing(who: who, mood: mood, intensity: intensity))
            },
            onOpenMain: { [weak self] in
                self?.windowController.showMainWindow()
            },
            // 真正的 check 走 MenuActionRouter.checkForUpdatesFromMenu (它有 sender 可改 item 状态),
            // AppDelegate 这里只是 plumbing。Task 12 会在 .didFindRemoteUpdate 监听里把主窗口
            // 拉前 + 二次派发 .showUpdateBanner 给 MenuBarContent。
            onCheckForUpdates: {}
        )
        // ⌥M 全局热键 — Carbon EventHotKey 走 HotKeyController
        hotKeyController = HotKeyController(
            spec: .optionM,
            onTrigger: { [weak self] in
                self?.windowController.showMainWindow()
            }
        )
        // App 激活兜底 — 监听 .didBecomeActiveNotification, debounce 0.5s 后
        // 拉主窗口 (跟 applicationShouldHandleReopen 互补)
        activeStateController = ActiveStateController(
            onShouldRaiseMainWindow: { [weak self] in
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

        // v0.0.2 update-checker: 启动 5s 后静默检查 + 订阅 .didFindRemoteUpdate
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UpdateChecker.shared.startBackgroundCheck()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteUpdateFound(_:)),
            name: .didFindRemoteUpdate,
            object: nil
        )
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

    // MARK: - 更新检测

    @objc private func handleRemoteUpdateFound(_ note: Notification) {
        guard let version = note.userInfo?["version"] as? String,
              let url = note.userInfo?["url"] as? URL else { return }
        // 1. 拉主窗口到前
        windowController.showMainWindow()
        // 2. 二级派发,让 MenuBarContent 挂 banner
        NotificationCenter.default.post(
            name: .showUpdateBanner,
            object: nil,
            userInfo: ["version": version, "url": url]
        )
    }
}
