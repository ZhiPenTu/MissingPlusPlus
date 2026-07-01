import AppKit

// MARK: - Status Item Provider
//
// 抽象层: 隐藏 `NSStatusItem` (官方, macOS 13-15) 跟 `NSPanel` (macOS 26+
// fallback) 之间的实现差异。`StatusPanelController` 按 macOS 版本选 provider,
// 调用方只看到统一接口, 不需要知道底层用哪个。
//
// 为什么需要 2 个实现:
// - macOS 13-15: `NSStatusBar.system.statusItem` 正常工作, AppKit 接管
//   click / drag / ⌘-drag 重排 / retina / focus / accessibility / dark mode
// - macOS 26+: NSStatusItem 被路由到 `com.apple.controlcenter:...-Aux[1]-NSStatusItemView`
//   scene, 主菜单栏看不到 (log 多次确认)。fallback 用 NSPanel (level=.statusBar)
//   画一个浮动 button, 绕开 routing。
//
// 选型逻辑是系统级硬编码, 跟用户 prefs 无关。
@MainActor
protocol StatusItemProvider: AnyObject {
    /// provider 当前是否对外可见 (单测断言用)
    var isVisible: Bool { get }
    /// 安装到 status bar / 浮层, 立即可见
    func install()
    /// 拆掉, 不再可见
    func dismiss()
    /// 刷新 icon (mood / style 变化时调用)
    func updateIcon(mood: Mood?, style: MenuBarIconStyle)
    /// 替换菜单 (knownWhos 变化时调用)
    func setMenu(_ menu: NSMenu)
}

// MARK: - NSStatusItem 实现 (官方 API)
@MainActor
final class NSStatusItemProvider: StatusItemProvider {
    private var statusItem: NSStatusItem?

    var isVisible: Bool { statusItem?.isVisible == true }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = true
        statusItem = item
    }

    func dismiss() {
        guard let item = statusItem else { return }
        item.isVisible = false
        statusItem = nil
    }

    func updateIcon(mood: Mood?, style: MenuBarIconStyle) {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarIconRenderer.image(mood: mood, style: style)
    }

    func setMenu(_ menu: NSMenu) {
        statusItem?.menu = menu
    }
}

// MARK: - NSPanel 实现 (macOS 26+ fallback)
@MainActor
final class NSPanelStatusItemProvider: StatusItemProvider {
    private var panel: StatusItemPanel?
    private var menu: NSMenu?

    private static let panelXKey = "MissingPlusPlusStatusPanelX"

    var isVisible: Bool { panel?.isVisible == true }

    func install() {
        let p = StatusItemPanel()
        p.content.clickTarget = self
        p.content.clickSelector = #selector(panelClicked)
        p.content.onDragEnd = { [weak p] in
            guard let x = p?.frame.origin.x else { return }
            UserDefaults.standard.set(Double(x), forKey: Self.panelXKey)
        }
        position(panel: p)
        p.orderFront(nil)
        panel = p
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    func dismiss() {
        NotificationCenter.default.removeObserver(self)
        guard let p = panel else { return }
        p.orderOut(nil)
        panel = nil
    }

    func updateIcon(mood: Mood?, style: MenuBarIconStyle) {
        guard let p = panel else { return }
        p.setIcon(MenuBarIconRenderer.image(mood: mood, style: style))
    }

    func setMenu(_ menu: NSMenu) {
        self.menu = menu
    }

    @objc private func panelClicked() {
        guard let menu = self.menu, let p = panel else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: p.content)
    }

    @objc private func screenParametersChanged() {
        position()
    }

    private func position(panel target: StatusItemPanel? = nil) {
        guard let p = target ?? self.panel else { return }
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let panelSize = p.frame.size
        let savedX = UserDefaults.standard.double(forKey: Self.panelXKey)
        let x: CGFloat = savedX > 0 ? CGFloat(savedX) : frame.maxX * 0.60
        let centerY = (frame.maxY + screen.visibleFrame.maxY) / 2
        let y = centerY - panelSize.height / 2
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
