import AppKit

// MARK: - 状态栏 controller
//
// 接管 AppDelegate 里 status item 的全生命周期:
//   - install / uninstall (按 AppPreferences.showStatusItem)
//   - icon 联动 (mood / style)
//   - 菜单构建 (5 mood × 5 who × 3 intensity, v0.0.11 含 "Check for Updates…")
//   - 响应 prefs 变化 (NotificationCenter observer)
//   - 响应新记录 (NotificationCenter observer → 刷 icon + rebuild menu)
//
// 实现选型 (`StatusItemProvider` 协议):
// - macOS 13-15: `NSStatusItemProvider` — 官方 NSStatusItem, AppKit 接管一切
// - macOS 26+:   `NSPanelStatusItemProvider` — 绕开 NSStatusItem 被路由到
//                Control Center scene 的系统行为 (log 多次确认)
//
// 设计: 每 AppDelegate 一份 (跟 WindowController / HotKeyController 模式
// 一致, 不是单例)。init 立即按当前 macOS 版本选 provider + 按 prefs 装/不装。
@MainActor
final class StatusPanelController {
    private let provider: StatusItemProvider
    private let menuBuilder: MenuBuilder

    private let onRecord: (Mood, String, Intensity) -> Void
    private let onOpenMain: () -> Void
    private let onCheckForUpdates: () -> Void

    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.onRecord = onRecord
        self.onOpenMain = onOpenMain
        self.onCheckForUpdates = onCheckForUpdates

        // 选 provider: macOS 26+ 走 NSPanel fallback, 其他走官方 NSStatusItem
        if #available(macOS 26, *) {
            self.provider = NSPanelStatusItemProvider()
        } else {
            self.provider = NSStatusItemProvider()
        }

        // MenuBuilder closures — 直接捕获 init 参数, 不 [weak self] (没循环引用风险)
        let onRecordRef = onRecord
        let onOpenMainRef = onOpenMain
        let onCheckForUpdatesRef = onCheckForUpdates
        self.menuBuilder = MenuBuilder(
            onRecord: { mood, who, intensity in
                onRecordRef(mood, who, intensity)
            },
            onOpenMain: {
                onOpenMainRef()
            },
            onCheckForUpdates: {
                onCheckForUpdatesRef()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        // 监听 prefs 变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrefsChanged(_:)),
            name: .appPreferencesDidChange,
            object: nil
        )
        // 监听新记录 → 状态栏图标 mood 联动 + 菜单 rebuild
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMissingAdded),
            name: .missingStoreDidAdd,
            object: nil
        )

        installIfNeeded()
    }

    /// 当前 status item 是否处于可见状态 (供单测断言 + 调试用)。
    var isStatusItemVisible: Bool { provider.isVisible }

    /// 显式拆 status item (供单测 tearDown 用)。
    func dismiss() {
        provider.dismiss()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 装/卸 (公开)

    func installIfNeeded() {
        if AppPreferences.shared.showStatusItem {
            if !provider.isVisible {
                provider.install()
            }
            updateIcon()
            provider.setMenu(buildMenu())
        } else {
            provider.dismiss()
        }
    }

    // MARK: - 私有: icon / menu

    private func updateIcon() {
        let latestMood = MissingStore.shared.sortedItems.first?.mood
        provider.updateIcon(
            mood: latestMood,
            style: AppPreferences.shared.menuBarIconStyle
        )
    }

    private func buildMenu() -> NSMenu {
        menuBuilder.build(
            recentWhos: Array(MissingStore.shared.knownWhos.prefix(5))
        )
    }

    // MARK: - 观察者

    @objc private func handlePrefsChanged(_ note: Notification) {
        installIfNeeded()
    }

    @objc private func handleMissingAdded(_ note: Notification) {
        updateIcon()
        provider.setMenu(buildMenu())
    }
}
