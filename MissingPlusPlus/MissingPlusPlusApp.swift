import SwiftUI
import AppKit
import Carbon
import UserNotifications

/// 标准的 macOS 菜单栏 app 入口 — **C 方案**（SwiftUI `MenuBarExtra`）。
///
/// 之前用 AppDelegate + NSStatusBar（AGENTS.md §14-§19），macOS 26 把
/// NSStatusItem 默认放到 (0, 0) — 被 Apple menu 遮住。`autosaveName`
/// + Cmd+drag 是 workaround，但用户体验差。
///
/// C 方案改用 SwiftUI `MenuBarExtra(content:label:)`（macOS 13+ 推荐）。
/// `label` 闭包接受自定义 SwiftUI view，mood 联动用 `@ObservedObject`
/// 声明式实现 — 不用 NotificationCenter 手动 push，prefs / store 变化
/// 自动 re-render。SwiftUI App framework 帮我们处理 status item 的
/// 生命周期 + 定位 + click → popover。
///
/// AppDelegate 还留着（不是 @main）做：
/// - Dock 点击 (`applicationShouldHandleReopen` → `showMainWindow`)
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
        MenuBarExtra {
            // popover 内容（被点击时显示）
            PopoverContent(
                store: store,
                onOpenMainWindow: { appDelegate.showMainWindow() }
            )
        } label: {
            // 菜单栏 item 的图标（SwiftUI 声明式 — mood 联动自动 re-render）
            StatusBarIcon(store: store, prefs: prefs)
        }
        .menuBarExtraStyle(.window)   // popover 风格（vs .menu）

        Settings {
            SettingsView(store: store, storage: storage, prefs: prefs)
        }

        .commands {
            // App 菜单（关于/退出）— SwiftUI 替代了原来的 installAppMenu NSMenu 装法
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

/// 留 AppDelegate 跑 Dock 点击 / ⌥M / 通知 / 窗口管理。
/// 不再持有 NSStatusItem（MenuBarExtra 接管）— NSStatusItem 的位置 bug
/// 在 macOS 26 + `LSUIElement` 各种组合下都跑不通，C 方案绕过它。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: () -> Void = {}

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .regular：Dock icon + app menu bar。MenuBarExtra 状态栏 item 在
        // 这种模式下会被 macOS 当成 app menu bar item，位置在 screen (0, 0) —
        // Apple menu 后面，**但有 tiny 心形在屏幕最左上角露出来**，用户能看到。
        // 不调 setActivationPolicy 时（默认 LSUIElement=true 行为），心形完全
        // 不可见。
        // macOS 26 + MenuBarExtra 的已知行为 — 用户得 Cmd+drag 拖到可见位置。
        NSApp.setActivationPolicy(.regular)
        installGlobalHotKey()

        // 监听新记录 → 发通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMissingAdded(_:)),
            name: .missingStoreDidAdd,
            object: nil
        )
        // 监听设置入口（popover "…" 菜单 → post .openSettings → 开 settings 窗口）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings(_:)),
            name: .openSettings,
            object: nil
        )
        // 监听 prefs 变化（MenuBarExtra 的 StatusBarIcon 是 @ObservedObject，
        // 自动 re-render — AppDelegate 这里只 log，未来要加副作用可以补)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrefsChanged(_:)),
            name: .appPreferencesDidChange,
            object: nil
        )
    }

    @objc private func handlePrefsChanged(_ note: Notification) {
        // StatusBarIcon 走 SwiftUI @ObservedObject 路径，prefs 变化自动 re-render。
        // 这里留个钩子，将来如果要从 AppDelegate 层面处理 prefs 副作用可以补。
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

    // MARK: - 新增记录 → 通知

    @objc private func handleMissingAdded(_ note: Notification) {
        guard let missing = note.userInfo?["missing"] as? Missing else { return }
        postRecordNotification(for: missing)
    }

    private func postRecordNotification(for missing: Missing) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let content = UNMutableNotificationContent()
        let who = missing.who.isEmpty ? "TA" : missing.who
        content.title = "想念 \(who)"
        content.body = "心情：\(missing.mood.label)　程度：\(missing.intensity.label)"
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
        var hotKeyID = EventHotKeyID(signature: OSType(0x4D53504D), id: 1)
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
