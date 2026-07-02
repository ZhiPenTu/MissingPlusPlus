import AppKit

// MARK: - 状态栏菜单构造器
//
// 状态栏 StatusItemPanel 点击后弹出的 NSMenu 树:
//   mood (5) → who (≤5) → intensity (3)  =  ≤75 个 record entry
//   + "在主窗口记录" / "退出" 根级 action
//
// 设计: MenuBuilder 是 class, 私有 MenuActionRouter (NSObject 子类) 接收
// @objc 消息并转成 closure 回调。这样:
//   - AppDelegate 不需要再持有 @objc action methods
//   - 菜单构建 (纯数据) 跟 action dispatch (有副作用) 干净分离
//   - closures 用 [weak self] 捕获 AppDelegate, 避免循环引用
//
// 生命周期: 每次 panel 点击都 new 一个 MenuBuilder (短命), 配套 router 也是
// 短命 — 没必要复用。NSMenu 在 popUp 期间由 AppDelegate.statusMenu 强引用,
// 关掉后释放, builder / router 跟着释放。
@MainActor
final class MenuBuilder {
    private let router: MenuActionRouter

    /// - Parameters:
    ///   - onRecord: 用户选了 (mood, who, intensity) 组合时调用
    ///   - onOpenMain: 用户选 "在主窗口记录…" 时调用
    ///   - onCheckForUpdates: 用户选 "Check for Updates…" 时调用
    ///   - onQuit: 用户选 "退出 心安日记" 时调用
    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.router = MenuActionRouter(
            onRecord: onRecord,
            onOpenMain: onOpenMain,
            onCheckForUpdates: onCheckForUpdates,
            onQuit: onQuit
        )
    }

    /// 构建状态栏菜单。每次 panel 点击都重新 build, 反映最新的 knownWhos。
    /// - Parameter recentWhos: 最多展示的 who 数量 (AppDelegate 传
    ///   `MissingStore.shared.knownWhos.prefix(5)`)。
    func build(recentWhos: [String]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 5 mood 顶层项 — 每个挂一个 who 选择 submenu
        for mood in Mood.allCases {
            let item = NSMenuItem(
                title: "\(mood.emoji)  \(mood.label)",
                action: nil,
                keyEquivalent: ""
            )
            item.submenu = buildMoodSubmenu(mood: mood, recentWhos: recentWhos)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openMain = NSMenuItem(
            title: "在主窗口新建记录…",
            action: #selector(MenuActionRouter.openMainFromMenu(_:)),
            keyEquivalent: ""
        )
        openMain.target = router
        menu.addItem(openMain)

        menu.addItem(.separator())

        let checkItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(MenuActionRouter.checkForUpdatesFromMenu(_:)),
            keyEquivalent: ""
        )
        checkItem.target = router
        menu.addItem(checkItem)

        menu.addItem(.separator())

        // ⌘Q 已经在 SwiftUI app menu 注册 (CommandGroup(.appTermination)),
        // 这里再 bind 一次让菜单显示快捷键提示
        let quit = NSMenuItem(
            title: "退出 心安日记",
            action: #selector(MenuActionRouter.quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quit.target = router
        menu.addItem(quit)

        return menu
    }

    private func buildMoodSubmenu(mood: Mood, recentWhos: [String]) -> NSMenu {
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
            action: #selector(MenuActionRouter.openMainFromMenu(_:)),
            keyEquivalent: ""
        )
        custom.target = router
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
                action: #selector(MenuActionRouter.recordFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = router
            item.representedObject = RecordRequest(
                mood: mood, who: who, intensity: intensity
            )
            sub.addItem(item)
        }
        return sub
    }
}

// MARK: - Action Router
//
// NSMenuItem 的 target — NSObject 子类, 持有 @objc methods 把 AppKit
// 消息转成 MenuBuilder init 注入的 closure。必须 NSObject 子类是因为
// NSMenuItem.action 是 Selector? 类型, Swift closure 不能直接当 selector
// 传, 只能走 @objc method 路由。
@MainActor
private final class MenuActionRouter: NSObject {
    private let onRecord: (Mood, String, Intensity) -> Void
    private let onOpenMain: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onRecord: @escaping (Mood, String, Intensity) -> Void,
        onOpenMain: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onRecord = onRecord
        self.onOpenMain = onOpenMain
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
    }

    @objc func recordFromMenu(_ sender: NSMenuItem) {
        guard let req = sender.representedObject as? RecordRequest else { return }
        onRecord(req.mood, req.who, req.intensity)
    }

    @objc func openMainFromMenu(_ sender: NSMenuItem) {
        onOpenMain()
    }

    @objc func checkForUpdatesFromMenu(_ sender: NSMenuItem) {
        // 1. 视觉反馈: item 变 "Checking…", disabled
        sender.title = "Checking…"
        sender.isEnabled = false
        // 2. 异步查
        Task { @MainActor in
            let result = await UpdateChecker.shared.checkNow()
            // 3. 恢复 item
            sender.title = "Check for Updates…"
            sender.isEnabled = true
            // 4. 弹结果
            Self.presentResult(result)
        }
    }

    @objc func quitFromMenu(_ sender: NSMenuItem) {
        onQuit()
    }

    private static func presentResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate(let local):
            let alert = NSAlert()
            alert.messageText = "已是最新"
            alert.informativeText = "当前 v\(local) 已是最新版本。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        case .updateAvailable(_, let htmlURL, _, _):
            // 直接打开 release 页;banner 由 .didFindRemoteUpdate 自动挂上
            NSWorkspace.shared.open(htmlURL)
        case .failed(let reason):
            let alert = NSAlert()
            alert.messageText = "检查更新失败"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}

// MARK: - Record Request
//
// NSMenuItem.representedObject 的载体 — 把 (mood, who, intensity) 一起
// 传给 recordFromMenu。struct 比 tuple 友好 (能 as? 强转)。
fileprivate struct RecordRequest {
    let mood: Mood
    let who: String
    let intensity: Intensity
}
