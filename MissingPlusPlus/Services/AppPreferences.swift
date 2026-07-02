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

    /// 是否配过 AI API key (只存 flag,不存 key 本身)。key 仍在 Keychain,
    /// 但 app 启动时不去碰它 —— 否则用户装新版本后第一次启动就会被
    /// 弹 "登录钥匙串密码" (因为 keychain 处于 locked 状态)。
    /// `aiIsConfigured` 用这个 flag 判断"是否已配",避免无谓地读 keychain。
    /// `aiAPIKey` getter 是 lazy load,只在用户真要用 AI (测试连接 / 调
    /// 用) 时才触发 keychain 读。`aiAPIKey` setter 同步更新 flag。
    @Published var hasAIKey: Bool {
        didSet {
            defaults.set(hasAIKey, forKey: Keys.hasAIKey)
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
    /// API key 内存缓存 —— `aiAPIKey` getter 走这里,避免每次
    /// SwiftUI body 重新渲染都打 Keychain (会触发"钥匙串验证"
    /// auth dialog)。init 时一次性读取,setter 时同步写 Keychain。
    /// 这是单进程 app,key 只可能被本 app 写,缓存永远权威。
    /// (v0.0.21 fix: 用户每次打开 Settings 都弹"钥匙串验证"。)
    /// (v0.0.24 fix: keychain 处于 locked 状态时 init 读 key 会
    /// 弹"登录钥匙串密码"。改成 lazy: 第一次 getter 访问才读。)
    private var _cachedAIKey: String?
    /// 是否已经尝试过 lazy load。getter 第一次访问时 = false,
    /// 触发 keychain 读后 = true。setter 写 keychain 时也 = true
    /// (避免 setter 后再 getter 又触发一次冗余读)。
    private var _didTryLoadAIKey: Bool = false

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
        static let hasAIKey = "HasAIKey"
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
        // hasAIKey 反映"用户配过 key"。key 本身在 keychain 里,
        // 但 init 不去读 —— 避免用户每次装新版本第一次启动就被弹
        // "登录钥匙串密码" (keychain locked 时必弹)。
        // lazy load 见 `aiAPIKey` getter。
        self.hasAIKey = defaults.bool(forKey: Keys.hasAIKey)
        self.aiEnabled =
            defaults.object(forKey: Keys.aiEnabled) as? Bool ?? false
        self.aiBaseURL =
            defaults.string(forKey: Keys.aiBaseURL) ?? "https://api.openai.com/v1"
        self.aiModel =
            defaults.string(forKey: Keys.aiModel) ?? "gpt-4o-mini"
        self.aiTemperature = defaults.object(forKey: Keys.aiTemperature) as? Double ?? 0.85
        self.aiMaxTokens = defaults.object(forKey: Keys.aiMaxTokens) as? Int ?? 200
        self.aiRequestTimeout = defaults.object(forKey: Keys.aiRequestTimeout) as? Double ?? 2.0
        // init 故意不读 keychain。懒加载见 aiAPIKey getter。
        self._cachedAIKey = nil
        self._didTryLoadAIKey = false
        self.updateCheckEnabled =
            defaults.object(forKey: Keys.updateCheckEnabled) as? Bool ?? true
        self.lastCheckedAt = nil  // transient
        self.lastKnownRemoteVersion = nil  // transient
        self.lastDismissedVersion =
            defaults.string(forKey: Keys.lastDismissedVersion)
        // 所有 stored property 初始化完之后才能 log hasAIKey
        // (Swift 严格检查 self 访问时机)。
        NSLog("[AppPreferences] init: skipping keychain read (lazy); hasAIKey flag=%@",
              self.hasAIKey ? "true" : "false")
    }

    // MARK: - API key (Keychain, lazy-loaded + cached in memory)

    /// Lazy load: getter 第一次访问时打 keychain,后续走 `_cachedAIKey` 缓存。
    /// 这避免 init 时就触发 keychain 读 (keychain locked 时会弹"登录
    /// 钥匙串密码" dialog,装新版本后第一次启动必中招)。
    /// 真正的 keychain 访问时机:
    ///  - 用户在 Settings 点"测试连接"
    ///  - 用户实际调用 AI (通知 / self-compassion / 致 TA 的话)
    ///  - 应用启动后第一次访问 `aiAPIKey`
    /// setter 同步写 keychain + 更新 `hasAIKey` flag,这样后续 `aiIsConfigured`
    /// 不用碰 keychain 就能判断"是否已配"。
    var aiAPIKey: String? {
        get {
            if !_didTryLoadAIKey {
                _didTryLoadAIKey = true
                let loaded = KeychainService.shared.get(account: Self.aiKeychainAccount)
                _cachedAIKey = loaded
                NSLog("[AppPreferences] aiAPIKey lazy-load: keychain returned %@",
                      loaded != nil ? "present" : "nil (locked or not set)")
                // Migration: v0.0.23 -> v0.0.24 升级场景。旧版没设 hasAIKey
                // flag,如果 keychain 里其实有 key,把 flag 修正过来,避免
                // aiIsConfigured 一直返 false 导致 Settings 显示"未配置"。
                if loaded != nil && !hasAIKey {
                    NSLog("[AppPreferences] aiAPIKey lazy-load: migrating hasAIKey flag false->true")
                    hasAIKey = true
                }
            }
            return _cachedAIKey
        }
        set {
            _didTryLoadAIKey = true
            let trimmed = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            _cachedAIKey = trimmed.isEmpty ? nil : trimmed
            // 同步 hasAIKey flag,避免 aiIsConfigured 再去碰 keychain
            let newFlag = (_cachedAIKey != nil)
            if newFlag != hasAIKey {
                hasAIKey = newFlag
            }
            if let v = _cachedAIKey {
                KeychainService.shared.set(v, account: Self.aiKeychainAccount)
            } else {
                KeychainService.shared.delete(account: Self.aiKeychainAccount)
            }
        }
    }

    /// AI 是否真的可用(开关 + 有 key + base url 非空)。Settings 显示状态灯用。
    /// 用 `hasAIKey` flag 而不是 `_cachedAIKey` —— 避免 SwiftUI body
    /// 重渲时触发 lazy load 弹"登录钥匙串密码"。flag 在 setter 时同步
    /// 更新,所以"用户配过 key"这个信息在 `aiIsConfigured` 这里无需碰
    /// keychain 就准确。
    var aiIsConfigured: Bool {
        aiEnabled
            && !(aiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && hasAIKey
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
