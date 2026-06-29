import AppKit

// MARK: - 状态栏 panel 控制器
//
// 接管 AppDelegate 里 status panel 的全生命周期:
//   - install / uninstall (按 AppPreferences.showStatusItem)
//   - 屏幕定位 (saved x 或 60% 处) + 拖动持久化
//   - icon 联动 (mood / style)
//   - click handler (弹 1-click 记录菜单)
//   - 响应 prefs 变化 (NotificationCenter observer)
//   - 响应屏幕参数变化 (显示器插拔 / 分辨率变化)
//
// 跟 StatusItemPanel / MenuBuilder 同住 StatusBar/ — 三者构成"状态栏入口
// 三件套": Panel 是 UI, MenuBuilder 是菜单结构, StatusPanelController 是
// 把两者串起来的协调层。
//
// 设计: 每 AppDelegate 一份 (跟 WindowController / HotKeyController 模式
// 一致, 不是单例)。init 立即按当前 prefs 决定装/不装 panel, 同时订阅 prefs
// + 屏幕参数变化。
@MainActor
final class StatusPanelController {
    private var panel: StatusItemPanel?
    private var statusMenu: NSMenu?

    /// 拖动 x 坐标持久化 key。UserDefaults 0 表示没存过 (默认走 60% 处)。
    private static let panelXKey = "MissingPlusPlusStatusPanelX"

    private let onRecord: (Mood, String, Intensity) -> Void
    private let onOpenMain: () -> Void

    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void
    ) {
        self.onRecord = onRecord
        self.onOpenMain = onOpenMain

        // 监听 prefs 变化 (showStatusItem 切换时拆/装 panel)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrefsChanged(_:)),
            name: .appPreferencesDidChange,
            object: nil
        )
        // 监听屏幕参数变化 (显示器插拔 / 分辨率变化) → 重新定位 panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // 监听新记录 → 状态栏图标 mood 联动
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMissingAdded),
            name: .missingStoreDidAdd,
            object: nil
        )

        installIfNeeded()
    }

    // MARK: - 装/卸 (公开)

    /// 按当前 prefs 决定装/不装 / 刷新 icon。
    /// init 调用一次; `.appPreferencesDidChange` 也会触发。
    func installIfNeeded() {
        if AppPreferences.shared.showStatusItem {
            if panel == nil {
                install()
            } else {
                updateIcon()
            }
        } else if let p = panel {
            statusMenu = nil
            p.orderOut(nil)
            panel = nil
        }
    }

    // MARK: - 私有: 装 / 定位 / icon

    private func install() {
        let p = StatusItemPanel()
        p.content.clickTarget = self
        p.content.clickSelector = #selector(statusPanelClicked)
        p.content.onDragEnd = { [weak self, weak p] in
            guard let x = p?.frame.origin.x else { return }
            UserDefaults.standard.set(Double(x), forKey: Self.panelXKey)
            self?.position()  // 触发布局 sanity check
        }
        position(panel: p)
        p.orderFront(nil)
        panel = p
        updateIcon()
    }

    private func position(panel target: StatusItemPanel? = nil) {
        guard let p = target ?? self.panel else { return }
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let panelSize = p.frame.size
        // 默认位置: 屏幕顶部状态栏, screen 60% 处 — 在 Codex menu 结束 (~30%)
        // 之后、system status bar items (~70% 起) 之前的空隙。
        // 用户可以拖动 panel 到任意位置, x 会持久化到 UserDefaults。
        let savedX = UserDefaults.standard.double(forKey: Self.panelXKey)
        let x: CGFloat = savedX > 0 ? CGFloat(savedX) : frame.maxX * 0.60
        // 垂直居中到 status bar 视觉中心 (macOS 26 status bar 高 33pt,
        // item 22pt 居中 — 中心 y = (frame.maxY + visibleFrame.maxY) / 2)
        let centerY = (frame.maxY + screen.visibleFrame.maxY) / 2
        let y = centerY - panelSize.height / 2
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func updateIcon() {
        guard let p = panel else { return }
        let latestMood = MissingStore.shared.sortedItems.first?.mood
        let image = MenuBarIconRenderer.image(
            mood: latestMood,
            style: AppPreferences.shared.menuBarIconStyle
        )
        p.setIcon(image)
    }

    // MARK: - 观察者

    @objc private func screenParametersChanged() {
        position()
    }

    @objc private func handlePrefsChanged(_ note: Notification) {
        installIfNeeded()
    }

    @objc private func handleMissingAdded(_ note: Notification) {
        // 新记录触发 mood 联动 — 只刷 icon, 不动 panel 装/卸
        updateIcon()
    }

    // MARK: - Click 入口

    @objc private func statusPanelClicked() {
        guard let p = panel else { return }
        // 每次点击都 new MenuBuilder — builder + router 都是短命对象,
        // 跟 popUp 一起释放。actions 走 closure 注入, 不用持 @objc method。
        let builder = MenuBuilder(
            onRecord: { [weak self] mood, who, intensity in
                self?.onRecord(mood, who, intensity)
            },
            onOpenMain: { [weak self] in
                self?.onOpenMain()
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
            in: p.content
        )
    }
}
