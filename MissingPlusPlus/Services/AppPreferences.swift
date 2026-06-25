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
    /// First-launch hint flag. false → 在 popover 顶部显示"找不到图标？
    /// 按 Cmd 拖出来"提示，用户点"知道了"后变 true。持久化到 UserDefaults
    /// 让提示只出现一次（除非用户手动清 prefs）。
    @Published var hasSeenDragHint: Bool {
        didSet {
            defaults.set(hasSeenDragHint, forKey: Keys.hasSeenDragHint)
        }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let showStatusItem = "ShowStatusItem"
        static let menuBarIconStyle = "MenuBarIconStyle"
        static let hasSeenDragHint = "HasSeenDragHint"
    }
    private init() {
        self.showStatusItem = defaults.object(forKey: Keys.showStatusItem) as? Bool ?? true
        self.menuBarIconStyle = MenuBarIconStyle(
            rawValue: defaults.string(forKey: Keys.menuBarIconStyle) ?? "heart"
        ) ?? .heart
        self.hasSeenDragHint = defaults.bool(forKey: Keys.hasSeenDragHint)
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
