import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted by `AppPreferences` whenever the user mutates `showStatusItem`
    /// or `menuBarIconStyle` from the settings UI. `AppDelegate` listens and
    /// re-evaluates the status item (install / remove / re-render).
    static let appPreferencesDidChange = Notification.Name(
        "MissingPlusPlusAppPreferencesDidChange"
    )
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var showStatusItem: Bool {
        didSet {
            defaults.set(showStatusItem, forKey: Keys.showStatusItem)
            NotificationCenter.default.post(name: .appPreferencesDidChange, object: self)
        }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle)
            NotificationCenter.default.post(name: .appPreferencesDidChange, object: self)
        }
    }
    /// First-launch hint flag — 之前 popover 顶部"找不到图标？按 Cmd 拖出来"
    /// 提示用过，popover 改 NSMenu 后没有对应 banner，但 flag 留着以备未来
    /// 状态栏/主窗口 first-launch 提示复用。
    @Published var hasSeenDragHint: Bool {
        didSet {
            defaults.set(hasSeenDragHint, forKey: Keys.hasSeenDragHint)
        }
    }
    /// v1.x anxious-attachment bundle: 在 intensity == strong submit 后自动弹
    /// RealityCheckSheet。默认开 —— 焦虑型用户最痛的是"看不见 pattern"不是"被打扰多"。
    @Published var autoPromptRealityCheck: Bool {
        didSet {
            defaults.set(autoPromptRealityCheck, forKey: Keys.autoPromptRealityCheck)
        }
    }
    /// v1.x anxious-attachment bundle: 新建表单顶部回访 banner
    /// "上次想念平复了吗？"（30 分钟 grace period 避免"刚提交就被问"）。
    @Published var autoPromptResolveLast: Bool {
        didSet {
            defaults.set(autoPromptResolveLast, forKey: Keys.autoPromptResolveLast)
        }
    }
    /// v1.x anxious-attachment bundle: 通知 body 追加 trigger 信息（如
    /// "　触发：💬 TA 没及时回"）。
    @Published var notificationIncludeTriggers: Bool {
        didSet {
            defaults.set(notificationIncludeTriggers, forKey: Keys.notificationIncludeTriggers)
        }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let showStatusItem = "ShowStatusItem"
        static let menuBarIconStyle = "MenuBarIconStyle"
        static let hasSeenDragHint = "HasSeenDragHint"
        static let autoPromptRealityCheck = "AutoPromptRealityCheck"
        static let autoPromptResolveLast = "AutoPromptResolveLast"
        static let notificationIncludeTriggers = "NotificationIncludeTriggers"
    }
    private init() {
        self.showStatusItem = defaults.object(forKey: Keys.showStatusItem) as? Bool ?? true
        self.menuBarIconStyle = MenuBarIconStyle(
            rawValue: defaults.string(forKey: Keys.menuBarIconStyle) ?? "heart"
        ) ?? .heart
        self.hasSeenDragHint = defaults.bool(forKey: Keys.hasSeenDragHint)
        self.autoPromptRealityCheck =
            defaults.object(forKey: Keys.autoPromptRealityCheck) as? Bool ?? true
        self.autoPromptResolveLast =
            defaults.object(forKey: Keys.autoPromptResolveLast) as? Bool ?? true
        self.notificationIncludeTriggers =
            defaults.object(forKey: Keys.notificationIncludeTriggers) as? Bool ?? true
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Codable {
    case heart
    case emoji
    case character

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .heart:     return "心形"
        case .emoji:     return "Emoji"
        case .character: return "思字"
        }
    }
}
