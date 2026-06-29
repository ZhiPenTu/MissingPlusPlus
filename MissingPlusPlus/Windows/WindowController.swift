import AppKit
import SwiftUI

// MARK: - 窗口控制器
//
// 接管 AppDelegate 里 main window + settings window 的 NSWindow 生命周期。
// 两份窗口都是 NSWindow + NSHostingController(SwiftUI) 模式,共享相同的
// "lazy 创建 + 复用 + autosave frame" 套路,所以放一个 controller。
//
// 入口：
//   - showMainWindow()     — Dock / ⌥M / 状态栏 NSMenu "在主窗口记录" 都走这
//   - handleOpenSettings() — `.openSettings` notification (⌘,) 触发
//
// 不做：
//   - 不持有 store / prefs / ai service — 这些是 SwiftUI / AppDelegate 关心的
//   - 不管 status panel / popover — 那是 StatusBar/ 的事
//   - 不做窗口动画 / 透明度渐变 — 当前是普通 show/hide,够用
@MainActor
final class WindowController {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private static let mainWindowFrameName = "MainWindow"
    private static let settingsWindowFrameName = "SettingsWindow"

    private static let mainWindowSize = NSSize(width: 360, height: 720)
    private static let settingsWindowSize = NSSize(width: 480, height: 600)

    init() {
        // ⌘, 走 SwiftUI Settings scene 的标准路径 — 但我们的 SettingsView 是
        // 在 NSWindow 里手画的(支持自定义 frame autosave + 跟主窗口同样的
        // 视觉风格),所以 Settings scene body 是 EmptyView,需要监听
        // .openSettings notification 自己开窗口。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings(_:)),
            name: .openSettings,
            object: nil
        )
    }

    // MARK: - 主窗口

    /// 主窗口已经在前台 → 拉到最前;否则创建 / 显示。
    /// Dock click / ⌥M / 状态栏 NSMenu "在主窗口记录" 都走这。
    func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            mainWindow = makeWindow(
                frameName: Self.mainWindowFrameName,
                title: "思念计数器",
                contentSize: Self.mainWindowSize,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                rootView: MenuBarContent(store: MissingStore.shared)
            )
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 设置窗口

    /// 设置窗口已经在前台 → 拉到最前;否则创建 / 显示。
    @objc private func handleOpenSettings(_ note: Notification) {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            settingsWindow = makeWindow(
                frameName: Self.settingsWindowFrameName,
                title: "Missing++ 设置",
                contentSize: Self.settingsWindowSize,
                styleMask: [.titled, .closable, .miniaturizable],
                rootView: SettingsView(
                    store: MissingStore.shared,
                    storage: StorageService.shared
                )
            )
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 工厂

    /// 工厂方法 — 所有 NSWindow 初始化都走这里,统一 frame autosave /
    /// 释放策略 / 居中逻辑。`isReleasedWhenClosed = false` 保留 window 实例,
    /// 下次 showMainWindow / handleOpenSettings 复用,frame 由 autosave 恢复。
    private func makeWindow<Content: View>(
        frameName: String,
        title: String,
        contentSize: NSSize,
        styleMask: NSWindow.StyleMask,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(
            rootView: rootView.frame(width: contentSize.width, height: contentSize.height)
        )
        window.center()
        window.setFrameAutosaveName(frameName)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
