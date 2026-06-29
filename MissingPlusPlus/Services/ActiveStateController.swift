import AppKit

// MARK: - app 激活状态控制器
//
// 接管 AppDelegate 里 "app 激活 → 拉主窗口" 的 debounce + 延迟逻辑。
//
// 为什么需要这个:
// - `applicationShouldHandleReopen` 只在 hidden app 被 Dock 召唤时触发,
//   从 Finder / Spotlight / alt-tab 切回来不会走这条路径
// - 用户从这些入口打开 app 只能看到状态栏 panel (macOS 26 还经常被
//   Control Center 盖住), 找不到主窗口
// - 兜底: 监听 `NSApplication.didBecomeActiveNotification`, 任何 app
//   激活都拉主窗口
//
// 防抖: 0.5s 内多次激活不重复拉 (快速 alt-tab 不会反复开/关)。
// 延迟: 0.3s 后才真正 showMainWindow, 让 macOS 自己的窗口切换动画跑完,
// 避免和系统动画打架。
//
// 设计: 跟 NotificationService / HotKeyController 一样是"app-lifecycle
// observer + closure dispatch"模式, 住 Services/。每 AppDelegate 一份。
@MainActor
final class ActiveStateController {
    private var lastActivationAt: Date = .distantPast

    /// 防抖间隔: 0.5s 内多次激活只算一次。Configurable via init。
    private let debounce: TimeInterval
    /// 触发后等多久才真正调 closure。让系统窗口切换动画跑完。
    private let activationDelay: TimeInterval

    private let onShouldRaiseMainWindow: () -> Void

    init(
        debounce: TimeInterval = 0.5,
        activationDelay: TimeInterval = 0.3,
        onShouldRaiseMainWindow: @escaping () -> Void
    ) {
        self.debounce = debounce
        self.activationDelay = activationDelay
        self.onShouldRaiseMainWindow = onShouldRaiseMainWindow

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleDidBecomeActive() {
        let now = Date()
        guard now.timeIntervalSince(lastActivationAt) >= debounce else { return }
        lastActivationAt = now
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) { [weak self] in
            self?.onShouldRaiseMainWindow()
        }
    }
}
