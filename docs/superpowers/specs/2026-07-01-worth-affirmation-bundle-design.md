# Worth Affirmation Bundle — 设计

> 日期：2026-07-01
> 状态：待 review
> 涉及范围：新增 1 view + 1 model / `RealityCheckSheet.swift` / `HistoryList.swift` / `NewMissingForm.swift` / `AppPreferences.swift` / `StatisticsView.swift` / `AGENTS.md`

## 1. 背景

v1.x 三轮 bundle 已经把"焦虑型依恋"的两层都立起来了:

- **Record bundle**(认知层,§16):trigger / resolved / reality check 三个字段,看见自己的 pattern
- **Self-soothing bundle**(body 层,§17):5-4-3-2-1 grounding / 自我同情 / 分散注意力,浪来时接住身体

但这两层都在**应对**焦虑 ——"焦虑来了怎么看见 / 怎么接住",没有解决**焦虑的来源**:把自己的价值外包给 TA 的回应。

依恋理论里这是不安全型(anxious)的核心 loop:**"我不确定 TA 爱不爱我" → 我去确认 → TA 不回应 → 焦虑更大 → 我更去确认**。打破这个 loop 的关键不是"再确认一次",而是把价值感**从外部拉回内部** —— "我的价值不取决于 TA 这一刻在不在"。

这一轮补这一块:**自己值得被爱的,确认**。1 张结构化卡片走完"看见焦虑 → 拆主体客体 → 向内求价值",1 次确认就把"我值得"这个内部资源落一次。

## 2. 目标

1 张新 view + 1 个新 model,3 个入口,1 张新统计卡片:

- **`WorthAffirmationView`** —— 1 张卡片,3 段竖排(看见 / 主体 vs 客体 / 向内求),结构化 affirmation
- **`WorthAffirmations` 池子** —— 10 条 curated 4 字段结构(seeing / subject / object / inward),v1 hardcode
- **3 个入口**:
  - **A 浪来时强 nudge**(`RealityCheckSheet` 底部 +1 sub-button)
  - **B 事后回访**(`HistoryList` 卡片底部 +1 sub-button)
  - **C 新建后 inline**(`NewMissingForm` "想冷静一下?" +1 sub-button)
- **1 张新统计卡片**(`StatisticsView` 第 4 张 insight 卡片)—— "本月你向内求了 X 次"
- **1 个新 preference**(`AppPreferences.worthConfirmations: [Date]`)—— append-only 时间戳列表,统计自己 filter

## 3. 非目标

- 不做 step-by-step 多步走完(5 步走完)。v1 走"1 张卡 3 段"结构化单卡,跟 SelfCompassionView / CooldownSheet 风格一致。
- 不做 AI 生成。3 段叙事是核心内容,hardcode curated pool 才稳;AI 走偏了"我值得被爱"会被稀释成鸡汤。
- 不做 streak / 每日目标 / 提醒。"向内求"是 in-the-moment 动作,变成 streak 就成了外部 KPI,跟"内部价值"目标冲突。
- 不做用户自定义 affirmation。v1 锁死 10 条 curated,避免"我自己写一句鸡汤" → 跳过审核 → 反向作用。
- 不在 popover 1-click(状态栏 NSMenu)路径里加 worth —— popover 是 peek,工具在主窗口用。
- 不动 Record bundle 已稳定的 13 个 commit,不动 self-soothing bundle 已稳定的 5 个 sheet。

## 4. 架构

### 4.1 数据层

`AppPreferences.swift` 加 1 个 `@Published`:

```swift
/// v1.x worth-affirmation bundle: 用户每次点「我已确认」的 timestamp。
/// append-only(删 = 失去一次确认历史,不允许)。
/// Statistics tab 自己 filter "本月" / "累计"。
@Published var worthConfirmations: [Date] {
    didSet {
        defaults.set(worthConfirmations, forKey: Keys.worthConfirmations)
    }
}

private enum Keys {
    static let worthConfirmations = "WorthConfirmations"
}

private init() {
    self.worthConfirmations =
        defaults.array(forKey: Keys.worthConfirmations) as? [Date] ?? []
}
```

**关键设计**:

- 用 `[Date]` 不用单个 `Int` counter —— 让 Statistics 卡片能自己算"本月 / 上月 / 30 天"窗口,过滤逻辑不依赖一个写死的 `lastResetMonth` 字段。
- 不存 confirmation 关联的 affirmation 内容(哪一条)—— v1 只要"我确认过 N 次"的次数感,不记录"我看了哪一句"。"被算法画像"是 v1 故意避免的。
- 数组无界增长:10 年每天 10 次 = 36500 个 Date ≈ 600KB JSON,可接受;future 如要限制可加 prune-to-2-years。
- UserDefaults 缺字段 → `?? []` fallback,老用户无痛。

### 4.2 新增 `Models/WorthAffirmations.swift`

```swift
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
```

**关键设计**:

- 4 段合一叙事:`seeing` 把用户的当下焦虑说出来(mindfulness)→ `subject` 拆出"我"是什么(主体)→ `object` 拆出"TA"是什么(客体)→ `inward` 把价值拉回内部。
- 4 段是 1 个 `WorthAffirmation` struct(不分别 shuffle)—— 割裂组合会破坏叙事连贯("看见焦虑" 配 "TA 是另一个人" 配 "我先深呼吸 3 次" → 串不起来)。
- 命名 `WorthAffirmations`(集合)跟 `SelfCompassionPhrases`(池子)同 pattern。
- `randomDifferent(from:)` helper:把"换一组"逻辑集中在 model 层,view 不需要知道池子细节。

### 4.3 新增 `Views/WorthAffirmationView.swift`

```swift
import SwiftUI

/// 自己值得被爱的确认。一张结构化卡片,3 段竖排:
/// 1. 看见 (mindfulness — 说出来)
/// 2. 主体 vs 客体 (subject-object split — 拆开)
/// 3. 向内求 (inward — 拉回价值)
/// 「我已确认」= 计数 + dismiss;「再换一组」= 4 段一起换;「关闭」= 直接 dismiss。
struct WorthAffirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var affirmation: WorthAffirmation = .initial
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section(
                number: "1",
                title: "看见",
                body: affirmation.seeing,
                tint: .blue
            )
            subjectObjectSection
            section(
                number: "3",
                title: "向内求",
                body: affirmation.inward,
                tint: .green
            )
            HStack {
                Button {
                    affirmation = WorthAffirmations.randomDifferent(from: affirmation)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("再换一组")
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("我已确认") {
                    prefs.worthConfirmations.append(Date())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("自己值得被爱")
                    .font(.headline)
                Spacer()
                Text("内置")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                    )
                    .foregroundColor(.secondary)
            }
            Text("向内求:先看见 → 拆主体客体 → 确认")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var subjectObjectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("2 · 主体 vs 客体")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.purple)
            }
            HStack(alignment: .top, spacing: 10) {
                subjectObjectCard(label: "我是…", body: affirmation.subject, tint: .pink)
                subjectObjectCard(label: "TA 是…", body: affirmation.object, tint: .gray)
            }
        }
    }

    private func subjectObjectCard(label: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(body)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.08))
        )
    }

    private func section(number: String, title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("\(number) · \(title)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tint)
            }
            Text(body)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.06))
                )
        }
    }
}

private extension WorthAffirmation {
    /// 首次出现 random 选 1 条。
    static var initial: WorthAffirmation {
        WorthAffirmations.pool.randomElement() ?? WorthAffirmations.pool[0]
    }
}
```

**关键点**:

- 3 段配色:看见 = 蓝(mindfulness, 第三方观察);主体 = 粉(自我);客体 = 灰(TA 是不在我的色彩焦点里的独立存在);向内求 = 绿(生长 / 内部价值)。
- 主体 vs 客体 用 2 个并排小卡片:"我是…" / "TA 是…" 并列,明确分两个独立完整的人。
- 按钮层级:"再换一组"(次要)/ "我已确认"(主要,绿色,因为这是 green 行动)/ "关闭"(次要)—— "我已确认"是 in-control 的承诺动作,给 keyboardShortcut(.defaultAction)。
- "关闭"和"我已确认"分两个:close = "我读完了但不想现在收下"(不计数),confirm = "我收下了"(计数)。"再换一组"不影响计数(不承诺,只是看看)。
- 不持久化当前 affirmation:每次 reopen 重新 random 起步,避免用户"被算法画像"的不适。
- `width: 460` 比其他 sub-sheet(420)宽 40pt —— 主体 vs 客体 并排 2 卡需要横向空间。

### 4.4 `Views/RealityCheckSheet.swift` 加 1 sub-button

在 sheet 底部"想先做点别的?"那一行(已有 3 个图标:eye / heart.text.square / shuffle)加第 4 个图标:

```swift
@State private var pendingWorthAffirmation = false

// in sub-button row:
HStack(spacing: 6) {
    Text("想先做点别的?")
        .font(.caption)
        .foregroundColor(.secondary)
    Spacer()
    Button { pendingGrounding = true } label: {
        Image(systemName: "eye").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.blue)
    .help("5-4-3-2-1 grounding")
    Button { pendingCompassion = missing } label: {
        Image(systemName: "heart.text.square").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.pink)
    .help("自我同情")
    Button { pendingWorthAffirmation = true } label: {
        Image(systemName: "heart.circle.fill").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.green)
    .help("自己值得被爱")
    Button { pendingCooldown = true } label: {
        Image(systemName: "shuffle").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.purple)
    .help("分散注意力")
}
.padding(.top, 4)
```

加 1 个 sheet modifier:

```swift
.sheet(isPresented: $pendingWorthAffirmation) {
    WorthAffirmationView()
}
```

**icon 选择**:`heart.circle.fill` —— 圆心 = 完整的自己,跟"自我同情"的 `heart.text.square`(方形短语卡片)区分。绿色 = 跟"向内求"section 配色一致。

**spacing**:从 8 改 6(4 个图标 24pt + 3 spacing = 96 + 18 = 114pt;"想先做点别的?"占左半部分)。

### 4.5 `Views/HistoryList.swift` 卡片加 1 sub-button

`HistoryRow` 加 1 个 closure + 1 个图标按钮:

```swift
private struct HistoryRow: View {
    let item: Missing
    let onResolve: () -> Void
    let onRequestCheck: () -> Void
    let onRequestGrounding: () -> Void
    let onRequestCompassion: () -> Void
    let onRequestWorth: () -> Void    // 新
    let onRequestCooldown: () -> Void
    // ...
}
```

icon 全部改 `.caption`(12pt),spacing 4 维持视觉对齐:

```swift
HStack(spacing: 4) {
    Text(item.who).font(.subheadline).fontWeight(.medium).lineLimit(1)
    Text("·").foregroundColor(.secondary)
    Text(item.intensity.label).font(.caption).foregroundColor(.secondary)
    Text("·").foregroundColor(.secondary)
    Text(relativeTime(item.createdAt)).font(.caption2).foregroundColor(.secondary).lineLimit(1)
    Spacer(minLength: 4)
    resolvedButton
    if item.realityCheck == nil {
        Button(action: onRequestCheck) {
            Image(systemName: "checkmark.bubble").font(.caption)
        }
        .buttonStyle(.borderless).foregroundColor(.purple).help("做现实检验")
    }
    Button(action: onRequestGrounding) {
        Image(systemName: "eye").font(.caption)
    }
    .buttonStyle(.borderless).foregroundColor(.blue).help("5-4-3-2-1 grounding")
    Button(action: onRequestCompassion) {
        Image(systemName: "heart.text.square").font(.caption)
    }
    .buttonStyle(.borderless).foregroundColor(.pink).help("自我同情")
    Button(action: onRequestWorth) {                              // 新
        Image(systemName: "heart.circle.fill").font(.caption)
    }
    .buttonStyle(.borderless).foregroundColor(.green).help("自己值得被爱")
    Button(action: onRequestCooldown) {
        Image(systemName: "shuffle").font(.caption)
    }
    .buttonStyle(.borderless).foregroundColor(.purple).help("分散注意力")
}
```

`HistoryList` 加 1 个 `@State` + 1 个 sheet modifier + 1 个 closure 传 row:

```swift
@State private var pendingWorthAffirmation: Missing?

// in HistoryRow call:
HistoryRow(
    item: missing,
    onResolve: { store.markResolved(missing) },
    onRequestCheck: { pendingRealityCheck = missing },
    onRequestGrounding: { pendingGrounding = missing },
    onRequestCompassion: { pendingCompassion = missing },
    onRequestWorth: { pendingWorthAffirmation = missing },   // 新
    onRequestCooldown: { pendingCooldown = missing }
)

// in body, after existing sheet modifiers:
.sheet(item: $pendingWorthAffirmation) { _ in WorthAffirmationView() }
```

**关键点**:

- 5 个图标挤 1 排:icon size 从 `.callout` (16pt) 改 `.caption` (12pt),5×12 + 4×4 = 76pt + spacing 容纳。`who` 文字 `lineLimit(1)` + `Spacer(minLength: 4)` 维持弹性。
- icon 配色:紫(check)/ 蓝(grounding)/ 粉(compassion)/ 绿(worth)/ 紫(cooldown)—— 5 个里有 2 个紫,区分要靠 icon shape 不是 color。
- per-card 一次性:`pendingWorthAffirmation: Missing?` 是 `.sheet(item:)` 模式,dismiss 时 SwiftUI 自动设回 nil,下次点别的 card 才能再触发。

### 4.6 `Views/NewMissingForm.swift` 加 1 sub-button 到 inline link

"想冷静一下?" inline link 现有 4 个图标(eye / heart.text.square / shuffle / paperplane),加第 5 个:

```swift
@State private var pendingWorthAffirmation: Missing? = nil

// in showSoothingLink HStack:
HStack(spacing: 4) {
    Image(systemName: "sparkles").foregroundColor(.pink)
    Text("想冷静一下?").font(.caption).lineLimit(1)
    Spacer()
    Button { pendingGrounding = true } label: {
        Image(systemName: "eye").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.blue).help("5-4-3-2-1 grounding")
    Button { pendingCompassion = latestSubmitted } label: {
        Image(systemName: "heart.text.square").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.pink).help("自我同情")
    Button { pendingWorthAffirmation = latestSubmitted } label: {        // 新
        Image(systemName: "heart.circle.fill").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.green).help("自己值得被爱")
    Button { pendingCooldown = true } label: {
        Image(systemName: "shuffle").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.purple).help("分散注意力")
    Button { pendingLetter = latestSubmitted } label: {
        Image(systemName: "paperplane").font(.callout)
    }
    .buttonStyle(.borderless).foregroundColor(.indigo).help("给 TA 写封信")
}
.padding(8)
.background(
    RoundedRectangle(cornerRadius: 6)
        .fill(Color.pink.opacity(0.06))
)
.transition(.opacity)
```

加 1 个 sheet modifier:

```swift
.sheet(item: $pendingWorthAffirmation) { _ in WorthAffirmationView() }
```

**关键点**:

- 5 个图标 in 一行:icon size 保持 `.callout` (16pt),spacing 4pt,5×16+4×4=96pt + "想冷静一下?" 文字 ≈ 80pt + sparkles 16pt = 192pt,inline link 区域总宽 ~360pt 容纳。
- inline link 5 秒后自动 fade:`showSoothingLink = false` 不影响 user-tapped sheet(sheet 是独立 modal)。
- "自己值得被爱"放在 compassion 之后,cooldown 之前 —— 顺序语义:自我同情 → 主体确认 → 分散(先向内,再向外)。

### 4.7 `Views/StatisticsView.swift` 加第 4 张 insight 卡片

```swift
private var insightCards: some View {
    VStack(spacing: 10) {
        WaveResolvedCard(stats: waveStats)
        TopTriggersCard(triggers: topTriggers)
        RealityCheckCard(stats: realityCheckStats)
        WorthAffirmationCard(stats: worthStats)        // 新
    }
    .padding(.bottom, 4)
}

private var worthStats: (thisMonth: Int, total: Int) {
    let cal = Calendar.current
    let now = Date()
    let all = AppPreferences.shared.worthConfirmations
    let thisMonth = all.filter {
        cal.isDate($0, equalTo: now, toGranularity: .month)
    }.count
    return (thisMonth, all.count)
}
```

新增卡片 view:

```swift
/// 卡片 4: 本月你向内求 —— 累计 + 本月数。
/// 跟其它 insight 卡片同 pattern: 1 个大数字 + 1 段温柔副标题,不做 streak / 目标 / 提醒。
private struct WorthAffirmationCard: View {
    let stats: (thisMonth: Int, total: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本月你向内求")
                .font(.subheadline.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(stats.thisMonth)")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                Text("次")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        if stats.total == 0 { return "还没有确认过 · 点 HistoryList 卡片底部的心形图标试试" }
        if stats.thisMonth == 0 { return "累计 \(stats.total) 次 · 还没有这个月" }
        return "每一次都是一次「我值得」练习 · 累计 \(stats.total) 次"
    }
}
```

**关键设计**:

- 大数字 = 本月(**近 30 天太宽,月份才对齐用户的时间感**)。
- 副标题不写"继续努力" / "你很棒" —— 价值感已经在卡片里说过了,统计副标题只陈述事实。
- 首次 0 状态引导文案:直接指向 HistoryList 卡片底部的心形图标(具体可发现性 > 抽象引导)。
- 0 状态不显示空表格 / 占位框(跟现有 3 个 insight 一致)。

## 5. 数据流

```
用户提交 strong missing
    ↓
MissingStore.add → post .missingStoreDidAdd
    ↓
NewMissingForm 弹 RealityCheckSheet (per-record 自动)
    ↓
用户填完/跳过 RealityCheckSheet
    ↓
4 个 sub-button 可点 → 弹对应 sub-sheet
    ├─ 5-4-3-2-1 → GroundingSheet
    ├─ 自我同情 → SelfCompassionView
    ├─ 自己值得被爱 → WorthAffirmationView (新)
    └─ 分散 → CooldownSheet
    ↓
用户在 WorthAffirmationView 点「我已确认」
    ↓
prefs.worthConfirmations.append(Date()) → 持久化
dismiss
    ↓
Statistics tab 下次刷新 → "本月你向内求" 卡片 +1


用户提交 mild missing
    ↓
MissingStore.add → post .missingStoreDidAdd
    ↓
NewMissingForm 5 秒 inline "想冷静一下?" link + 5 sub-button
    ├─ 5-4-3-2-1
    ├─ 自我同情
    ├─ 自己值得被爱 → WorthAffirmationView (新)
    ├─ 分散
    └─ 给 TA 写封信
    ↓
同上


用户点 HistoryList 卡片 sub-button
    ↓
5 个图标:check / grounding / compassion / worth (新) / cooldown
    ↓
点 worth → 弹 WorthAffirmationView (per-card 一次性)
    ↓
同上
```

## 6. 错误处理 / 边界

- **`worthConfirmations` UserDefaults 缺字段**:`defaults.array(forKey:) as? [Date] ?? []` fallback 到 `[]`,老用户无痛。
- **`worthConfirmations` 数据类型不对**(比如被外部工具改成 `[String]`):`as? [Date]` 失败 fallback `[]`,不 crash。
- **`WorthAffirmations.pool` 改顺序后 existing users 看到的 "再换一组" 不会重复**:每个 `WorthAffirmation` 是 `Hashable` struct,`==` 比 4 个 String 字段全等,pool 顺序变了不破坏 `randomDifferent(from:)` 的语义。
- **"再换一组"按到同一条**:v1 pool 10 条 + `while next == current` 防同组重复。
- **统计卡片 0 状态不报错**:`stats.total == 0` 显示引导文案,不显示空图表。
- **用户没点 "我已确认" 就 dismiss**:`prefs.worthConfirmations` 不变("关闭" 和 "再换一组" 都不 append Date)。
- **5 个图标挤在 HistoryList card 第一排**:icon `.callout` → `.caption` (12pt),spacing 4pt,5×12+4×4=76pt + who/text 部分。`lineLimit(1)` + `Spacer(minLength: 4)` 维持弹性。
- **5 个图标挤在 NewMissingForm inline link**:"想冷静一下?" 文字 5 秒后自动 fade,期间不展开,5 个 icon spacing 4pt 紧排可以 fit。
- **WorthAffirmationView dismiss 不持久化 affirmation**:每次 reopen 重新 random 起步,不记忆"上次看到哪句",避免"被算法画像"。
- **`@State` 在 sheet 关闭后丢失**:每次 reopen 是 fresh random,`WorthAffirmations.randomDifferent(from:)` 起步。
- **WorthAffirmationView 不在 popover(`MenuBarContent`)里出现**:popover 是 peek,sub-sheet 入口在主窗口 HistoryList 卡片 / RealityCheckSheet / inline link,不在 popover 顶部小区域。

## 7. 测试 / 验证

**Build**:
- [ ] `xcodebuild -configuration Debug -scheme MissingPlusPlus build` → BUILD SUCCEEDED
- [ ] `xcodebuild -configuration Release` → BUILD SUCCEEDED
- [ ] `bash scripts/run_tests.sh` → `** TEST SUCCEEDED **`, 35/35 tests pass(自 sooting bundle 完成后已稳定)

**功能**:
- [ ] 启动 → 主窗口 "统计" tab → 看到 4 张 insight 卡片,第 4 张是"本月你向内求 · 0 次"
- [ ] HistoryList 任意卡片 → 看到 5 个图标(第 5 个是绿色心形)→ 点 → 弹 WorthAffirmationView
- [ ] 录 strong missing → 自动弹 RealityCheckSheet → 看到 4 个 sub-button(第 3 个是绿色心形)→ 点 → 弹
- [ ] 录 mild missing → 顶部 5 秒 inline link 出现 5 个图标 → 点绿色心形 → 弹
- [ ] 在 WorthAffirmationView 看 3 段内容:看见 / 主体 vs 客体("我是…" + "TA 是…")/ 向内求
- [ ] 点 "再换一组" → 4 段一起换,不重复
- [ ] 点 "我已确认" → dismiss → 统计 tab 第 4 张卡片数字 +1
- [ ] 反复点 "我已确认" 多次 → 数字对应累加
- [ ] 点 "关闭"(不点"我已确认")→ dismiss → 统计不变

**JSON 兼容**:
- [ ] UserDefaults 无 `WorthConfirmations` → 启动 → 统计卡显示 0 次,sheets 都正常
- [ ] UserDefaults 有 `WorthConfirmations = [Date1, Date2]` → 启动 → 统计卡显示正确

**回归防坑**(AGENTS.md §5/§16/§17/§22):
- [ ] popover 1-click(状态栏 NSMenu)不变
- [ ] 主窗口 3 tab(新建 / 统计 / 历史)不变
- [ ] 菜单栏 icon mood 染色 + auto-fade 不变
- [ ] Record bundle 13 个 commit 行为不变(trigger / resolved / reality check / 3 insight 卡片 / banner)
- [ ] Self-soothing bundle 4 sub-sheet 行为不变(grounding / compassion / cooldown / letter)

**pbxproj 验证**:
- [ ] `plutil -lint MissingPlusPlus.xcodeproj/project.pbxproj` → OK
- [ ] xcodebuild 不报 "unrecognized selector" / "missing file ref"

## 8. 改动文件

**新增(2 个)**:
- `MissingPlusPlus/Models/WorthAffirmations.swift` —— `WorthAffirmation` struct + `WorthAffirmations` enum (pool + randomDifferent)
- `MissingPlusPlus/Views/WorthAffirmationView.swift` —— 3 段卡片 + 3 按钮

**修改(5 个)**:
- `MissingPlusPlus/Services/AppPreferences.swift` —— + `@Published worthConfirmations: [Date]` + `WorthConfirmations` Key + init fallback
- `MissingPlusPlus/Views/RealityCheckSheet.swift` —— + 1 sub-button + 1 sheet state + 1 sheet modifier (4 个 sub-button total)
- `MissingPlusPlus/Views/HistoryList.swift` —— HistoryRow + 1 closure + 1 icon (5 sub-button total, icon size 改 .caption) + 1 sheet state + 1 sheet modifier
- `MissingPlusPlus/Views/NewMissingForm.swift` —— + 1 sub-button 到 inline link (5 sub-button total) + 1 sheet state + 1 sheet modifier
- `MissingPlusPlus/Views/StatisticsView.swift` —— + 第 4 张 `WorthAffirmationCard` + `worthStats` helper + 改 `insightCards`
- `AGENTS.md` —— + §24 章节

**pbxproj 4 处插入**(A1000012000000000000A016/017 + B1000012000000000000A016/017):
- PBXBuildFile ×2(WorthAffirmations.swift + WorthAffirmationView.swift in Sources)
- PBXFileReference ×2
- Models group +1(`B1000012000000000000A016 /* WorthAffirmations.swift */`)
- Views group +1(`B1000012000000000000A017 /* WorthAffirmationView.swift */`)
- PBXSourcesBuildPhase `G0000001000000000000A001` +2(按 §22 流程在第二个 sentinel 后插,避开"unrecognized selector"坑)

**不改**:
- `Missing.swift` / `Mood.swift` / `Intensity.swift` / `TriggerTag.swift` / `CooldownActivities.swift`(model 层不动)
- `MissingStore.swift`(不动 mutation API)
- `MenuBarContent.swift` / `LetterToThemView.swift` / `SelfCompassionView.swift` / `GroundingSheet.swift` / `CooldownSheet.swift`(其它 4 个 sub-sheet 不动)
- `MenuBuilder.swift` / `StatusBar/*`(状态栏 NSMenu 不动)
- `StorageService.swift` / `MenuBarIconRenderer.swift` / `KeychainService.swift` / `AIService.swift`(service 层不动)
- `MissingPlusPlusApp.swift`(不动通知 / AppDelegate)
- `Info.plist` / `.entitlements`
- `scripts/*`

## 9. 「不要做」(新增)

按 `AGENTS.md §5` 已有规则继续生效,这一轮新加:

- 不要把 affirmation 做成 step-by-step 多步走完(v1 走"1 张卡 3 段"结构化单卡)
- 不要做 AI 生成 affirmation(hardcode curated pool 才稳)
- 不要做 streak / 每日目标 / 提醒(向内求是 in-the-moment 动作,外部 KPI 跟"内部价值"目标冲突)
- 不要让用户自定义 affirmation(v1 锁死 10 条 curated)
- 不要在 popover(`MenuBarContent`)里加 worth 入口(popover 是 peek,工具在主窗口用)
- 不要在 mild submit 后的 RealityCheckSheet 路径上同时弹 worth(mild 不弹 RealityCheckSheet,走 inline link 5 个图标;strong 走 RealityCheckSheet 4 个 sub-button,2 条路径不重复)
- 不要给 WorthAffirmationView 加 "保存草稿" / "上次的进度" 恢复(每次 fresh random,不画像)
- 不要在统计卡片里加"还差 X 次达到本月目标" / "继续努力" / 进度条(向内求是 in-control 动作,不是 task 进度)
- 不要在 worth sheet 关闭时强制 append Date("关闭" 和 "我已确认" 是不同 in-control 动作;"我已确认" 才计数)
- 不要在 HistoryList 卡片底部加 dropdown / overflow menu 收 5 个图标(直接 .caption 紧排,避免增加 tap path)

## 10. 风险 / 备注

- **主体性确认的 pedagogy 跟现有 self-compassion 边界**:`SelfCompassionPhrases` 17 句是"对自己说一句有用的话"(kindness),`WorthAffirmations` 10 条是"看见 → 拆 → 向内求"3 段叙事。两者边界:compassion 是 single phrase,worth 是 4-field structured narrative。2 个池子不交叉(compassion 不做"我是 / TA 是"拆分,worth 不做 single 短语)。
- **5 个图标挤 1 排**:HistoryList card icon size 改 `.callout` → `.caption`,这是项目首次减小 existing icon size 适配。如果 build 后实测卡住,再上 dropdown / overflow menu(v1.1)。
- **`worthConfirmations` 数组无界增长**:v1 简单 append,10 年每天 10 次 ≈ 600KB JSON。future 如果想限,加 prune-to-2-years 即可。
- **pbxproj patch 风险**:4 处插入(2 个新 Swift + 2 个 group ref),比 self-soothing bundle 的 12 处少,should 稳。按 §22 流程走 patch-pbxproj 一样的 idempotency sentinel。
- **WorthAffirmationView 跟 `SelfCompassionView` 视觉上看起来像**:都是单卡 1 句 + "再换" 按钮。区分:worth 多了"主体 vs 客体"横向双卡,是 4 段结构化卡片(不是单一短语卡片)。未来如果加 v1.x 第 4 个类似 sheet,要用更明显的结构区分。
- **AGENTS.md 章节编号**:当前到 §23,新增章节接 §24。
- **AI 留口**:`WorthAffirmations` pool 跟 `SelfCompassionPhrases` pool 一样 hardcode,v1 不开 AI。future 迭代可以加 `generateWorthAffirmation(for: missing)` 在 `AIService` 里,作为 opt-in 增强("再换一组"按钮长按 → AI 生成自定义)。但 v1 不开。
