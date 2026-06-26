import Foundation

/// 预定义的 6 条 cooldown 活动。v1 写死，不让用户改。
/// 用户能 append 自己的（在 AppPreferences.cooldownActivities），不能删这些。
enum CooldownActivities {
    static let defaults: [String] = [
        "喝杯水",
        "出门走 5 分钟",
        "深呼吸 10 次",
        "听一首喜欢的歌",
        "给朋友发条消息",
        "抱抱毛绒玩具 / 家里的宠物",
    ]

    /// 渲染 CooldownSheet 时用的全列表 = defaults + 用户追加。
    /// 顺序固定：defaults 在前，用户的在后面。
    /// 去重：如果用户追加了与 default 重复的，过滤掉。
    static func all(custom: [String]) -> [String] {
        defaults + custom.filter { !defaults.contains($0) }
    }
}

/// Self-compassion 7 句 curated 池子（Kristin Neff 风格：
/// mindfulness + common humanity + self-kindness 三要素）。v1 hardcode，
/// 不让用户改，避免鸡汤合集。
enum SelfCompassionPhrases {
    static let phrases: [String] = [
        "想念意味着这个人对你重要 —— 这本身没有错。",
        "这种感觉很痛苦，但痛苦不是永久的。",
        "你不需要立刻采取行动，先让自己喘口气。",
        "很多人都会在依恋关系里有这种挣扎，你不是一个人。",
        "哪怕现在很难，你已经在照顾自己了 —— 记下这一笔就是证据。",
        "现在的不安是真实的，但不一定代表会发生什么坏事。",
        "我先对自己温柔一点，等情绪过了再决定要不要做什么。",
    ]
}
