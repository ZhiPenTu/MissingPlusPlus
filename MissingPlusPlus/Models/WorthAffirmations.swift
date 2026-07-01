import Foundation

/// 4 字段结构化 affirmation: 看见 / 主体 / 客体 / 向内求。
/// 4 段合一是一段完整叙事 —— "再换一组"时 4 段一起换(保持叙事连贯),
/// 不是 4 段独立 shuffle(避免"看见焦虑"配"他人走开"配"向内求"的割裂组合)。
struct WorthAffirmation: Hashable {
    let seeing: String
    let subject: String
    let object: String
    let inward: String
}

/// Worth affirmation curated 池子。v1 hardcode 10 条,
/// 不让用户改,避免"我自己写一句鸡汤"被反向作用。
/// 覆盖 5 种想念场景(已读不回 / 没主动联系 / 翻旧朋友圈 / 想到过去 / 分离焦虑)+ 5 种情绪模式。
enum WorthAffirmations {
    static let pool: [WorthAffirmation] = [
        WorthAffirmation(
            seeing:  "是的,我刚才在反复看 TA 的对话框。",
            subject: "我是因为在意 TA 才这样。",
            object:  "TA 是另一个人,有 TA 的节奏。",
            inward:  "我值得被爱,不取决于 TA 这一刻在不在。"
        ),
        WorthAffirmation(
            seeing:  "是的,我现在因为 TA 没及时回消息而焦虑。",
            subject: "我渴望被回应是真实的需要。",
            object:  "TA 没回复不等于不在乎。",
            inward:  "我先给自己这份回应:我在这里。"
        ),
        WorthAffirmation(
            seeing:  "是的,我又在想 TA 了。",
            subject: "想念是我的情绪,不是我的全部。",
            object:  "TA 是 TA,我是我。",
            inward:  "我完整地存在,不需要 TA 来证明。"
        ),
        WorthAffirmation(
            seeing:  "是的,我刚才在翻看 TA 的旧朋友圈。",
            subject: "我想回到那个被 TA 关注的时刻。",
            object:  "TA 的现在有 TA 的生活。",
            inward:  "我能为现在这一刻的自己,做点什么呢?"
        ),
        WorthAffirmation(
            seeing:  "是的,TA 没说「想我」让我有点失落。",
            subject: "我想要被表达的渴望是合理的。",
            object:  "TA 的表达方式可能跟我不一样。",
            inward:  "我先对现在这个自己说:「我看到你了」。"
        ),
        WorthAffirmation(
            seeing:  "是的,我刚才想给 TA 发消息又忍住了。",
            subject: "我在练习「先稳一会儿」。",
            object:  "TA 不需要立刻收到我的消息。",
            inward:  "我等得了,因为我相信自己也值得被等。"
        ),
        WorthAffirmation(
            seeing:  "是的,我有时候觉得只有 TA 能让我开心。",
            subject: "我把自己的快乐外包给 TA 了。",
            object:  "TA 是 TA,不是我的快乐供应商。",
            inward:  "我可以重新学习:让自己开心的能力,本来就在我身上。"
        ),
        WorthAffirmation(
            seeing:  "是的,我又在猜 TA 是不是不爱我了。",
            subject: "这种恐惧是过去的伤口,不是现在的事实。",
            object:  "TA 没说过不爱我。",
            inward:  "我先爱自己这一刻的不安全感。"
        ),
        WorthAffirmation(
            seeing:  "是的,TA 冷淡了一下我心里就翻江倒海。",
            subject: "我对 TA 的反应很敏感。",
            object:  "TA 偶尔的冷淡不等于否定。",
            inward:  "我值得被稳定地爱,从我自己开始。"
        ),
        WorthAffirmation(
            seeing:  "是的,我又在想「如果 TA 不爱我怎么办」。",
            subject: "这种恐惧提醒我有多在乎被爱。",
            object:  "TA 的行为不等于 TA 的全部心意。",
            inward:  "我值得被爱,这份爱不靠猜来验证。"
        ),
    ]

    /// "再换一组" 时 4 段一起换。用 `while next == current` 防同组重复;
    /// 池子只有 1 条时直接 reuse(defensive,v1 是 10 条不会触发)。
    static func randomDifferent(from current: WorthAffirmation?) -> WorthAffirmation {
        guard pool.count > 1 else { return pool[0] }
        var next = pool.randomElement()!
        while next == current {
            next = pool.randomElement()!
        }
        return next
    }
}
