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
    /// v0.0.2 update-checker: 启动 5s 后静默检查 GitHub Releases;有新版在主窗口顶部
    /// 弹 banner。默认开。关闭后连手动 "Check for Updates…" 也禁用。
    @Published var updateCheckEnabled: Bool {
        didSet { defaults.set(updateCheckEnabled, forKey: Keys.updateCheckEnabled) }
    }
    /// v0.0.2 update-checker: 启动检查节流用。transient, 不持久化。
    @Published var lastCheckedAt: Date?
    /// v0.0.2 update-checker: 上次发现的 remote version (debug/UI 用)。transient, 不持久化。
    @Published var lastKnownRemoteVersion: String?
    /// v0.0.2 update-checker: 用户点过 "稍后" 的版本。持久化,避免每次启动都重弹同一版本。
    @Published var lastDismissedVersion: String? {
        didSet { defaults.set(lastDismissedVersion, forKey: Keys.lastDismissedVersion) }
    }
    /// v1.x self-soothing bundle: 用户追加的 cooldown 活动。
    /// 预定义 6 条在 `CooldownActivities.defaults`，永远在前面；
    /// 这个数组只存用户追加的，渲染时 `CooldownActivities.all(custom:)` 拼接。
    /// UserDefaults 缺字段 fallback 到 []，predefined 6 条仍在。
    @Published var cooldownActivities: [String] {
        didSet {
            defaults.set(cooldownActivities, forKey: Keys.cooldownActivities)
        }
    }

    /// v1.x worth-affirmation bundle: 用户每次点「我已确认」的 timestamp。
    /// append-only(删 = 失去一次确认历史,不允许)。
    /// Statistics tab 自己 filter "本月" / "累计"。
    @Published var worthConfirmations: [Date] {
        didSet {
            defaults.set(worthConfirmations, forKey: Keys.worthConfirmations)
        }
    }

    /// AI 增强总开关。false → 走现有 hardcoded 文本（SelfCompassion 17 句 / 通知固定模板 / 3 封备选信）。
    @Published var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
        }
    }
    /// OpenAI 兼容协议的 base url，结尾 /v1 或不带都行，AIService 内部归一化。
    @Published var aiBaseURL: String {
        didSet {
            defaults.set(aiBaseURL, forKey: Keys.aiBaseURL)
        }
    }
    /// 调用的模型名，例如 "gpt-4o-mini"、"deepseek-chat"、"qwen-turbo"。
    @Published var aiModel: String {
        didSet {
            defaults.set(aiModel, forKey: Keys.aiModel)
        }
    }
    /// 0.0 - 2.0，越高越发散。0.85 是写文案比较合适的中间值。
    @Published var aiTemperature: Double {
        didSet {
            defaults.set(aiTemperature, forKey: Keys.aiTemperature)
        }
    }
    /// 单次请求最大 token，控制成本 + 防止跑飞。
    @Published var aiMaxTokens: Int {
        didSet {
            defaults.set(aiMaxTokens, forKey: Keys.aiMaxTokens)
        }
    }
    /// 单次请求 timeout 秒。0.8s - 2.0s 是文案场景的合理区间。
    @Published var aiRequestTimeout: Double {
        didSet {
            defaults.set(aiRequestTimeout, forKey: Keys.aiRequestTimeout)
        }
    }
    /// API key 不存在 UserDefaults，单独走 Keychain。account 名固定。
    static let aiKeychainAccount = "openai"

    private let defaults: UserDefaults
    private enum Keys {
        static let aiEnabled = "AIEnabled"
        static let aiBaseURL = "AIBaseURL"
        static let aiModel = "AIModel"
        static let aiTemperature = "AITemperature"
        static let aiMaxTokens = "AIMaxTokens"
        static let aiRequestTimeout = "AIRequestTimeout"
        static let showStatusItem = "ShowStatusItem"
        static let menuBarIconStyle = "MenuBarIconStyle"
        static let hasSeenDragHint = "HasSeenDragHint"
        static let autoPromptRealityCheck = "AutoPromptRealityCheck"
        static let autoPromptResolveLast = "AutoPromptResolveLast"
        static let notificationIncludeTriggers = "NotificationIncludeTriggers"
        static let cooldownActivities = "CooldownActivities"
        static let worthConfirmations = "WorthConfirmations"
        static let updateCheckEnabled = "UpdateCheckEnabled"
        static let lastDismissedVersion = "UpdateCheckerLastDismissedVersion"
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        self.cooldownActivities =
            defaults.stringArray(forKey: Keys.cooldownActivities) ?? []
        self.worthConfirmations =
            defaults.array(forKey: Keys.worthConfirmations) as? [Date] ?? []
        self.aiEnabled =
            defaults.object(forKey: Keys.aiEnabled) as? Bool ?? false
        self.aiBaseURL =
            defaults.string(forKey: Keys.aiBaseURL) ?? "https://api.openai.com/v1"
        self.aiModel =
            defaults.string(forKey: Keys.aiModel) ?? "gpt-4o-mini"
        self.aiTemperature = defaults.object(forKey: Keys.aiTemperature) as? Double ?? 0.85
        self.aiMaxTokens = defaults.object(forKey: Keys.aiMaxTokens) as? Int ?? 200
        self.aiRequestTimeout = defaults.object(forKey: Keys.aiRequestTimeout) as? Double ?? 2.0
        self.updateCheckEnabled =
            defaults.object(forKey: Keys.updateCheckEnabled) as? Bool ?? true
        self.lastCheckedAt = nil  // transient
        self.lastKnownRemoteVersion = nil  // transient
        self.lastDismissedVersion =
            defaults.string(forKey: Keys.lastDismissedVersion)
    }

    // MARK: - API key (Keychain)

    /// API key 存 Keychain，外部读写都走这里。
    var aiAPIKey: String? {
        get { KeychainService.shared.get(account: Self.aiKeychainAccount) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainService.shared.set(v, account: Self.aiKeychainAccount)
            } else {
                KeychainService.shared.delete(account: Self.aiKeychainAccount)
            }
        }
    }

    /// AI 是否真的可用（开关 + 有 key + base url 非空）。Settings 显示状态灯用。
    var aiIsConfigured: Bool {
        aiEnabled
            && !(aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !((aiAPIKey ?? "").isEmpty)
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
