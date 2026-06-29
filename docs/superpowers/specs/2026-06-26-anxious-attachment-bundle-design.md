# Anxious Attachment Record Bundle — 设计

> 日期：2026-06-26
> 状态：待 review
> 涉及范围：`Missing.swift` / 新增 `TriggerTag.swift` + `RealityCheckSheet.swift` / `MissingStore.swift` / `NewMissingForm.swift` / `HistoryList.swift` / `StatisticsView.swift` / `AppPreferences.swift` / `SettingsView.swift` / `AppDelegate` / `AGENTS.md`

## 1. 背景

`心安日记` (代码名 `MissingPlusPlus`) 是一个面向**焦虑型依恋人格**的 macOS 菜单栏 app（`AGENTS.md §1`）。当前模型（`Missing.swift`）只记 `who + mood + intensity + createdAt`，核心动作是"记一笔想念"。

焦虑型依恋的核心痛点（attachment theory + DBT/CBT 干预）：

- 容易 catastrophize（"TA 5h 没回 = 不爱了"）
- 浪来时不会 self-soothing，需要外部 nudge
- 想发消息（protest behavior）但事后后悔
- 缺少"过去 N 次浪都平复了"的累积证据
- 看不清自己的 trigger pattern

当前 app **只覆盖了"记录 + 模式"的一半**：能记想念、能看到统计趋势，但缺少"看见 trigger 模式 + 累积平复证据 + DBT 落点"这条线。这一轮补这块。

## 2. 目标

加 3 个互相依赖的字段 + 1 个新 view，让 attachment 场景的 self-awareness 浮上来：

1. **`triggerTags`**：记录想念的"触发器"（TA 没回 / 独处 / 刚吵完架等 8 个 attachment 场景）
2. **`resolvedAt`**：记录"浪过去了"的时点
3. **`realityCheck`**：DBT "Check the Facts" skill 的轻量落点（evidence for / against / next action）

并把这些字段贯穿到：

- **新建表单**（trigger picker + "上一条平复了吗" 回访 banner + 自动弹 reality check sheet）
- **历史卡片**（trigger chips + resolved icon + reality check 折叠 tag）
- **统计 tab**（3 个 insight 卡片：「浪都过去了」/「常见 trigger」/「现实检验完成度」）
- **Settings**（3 个新 toggle）
- **通知 body**（追加 trigger 信息）

## 3. 非目标

- 不做 self-soothing bundle（#5+#6+#7：「3 分钟 grounding」/「自我同情 break」/「cooldown 活动」）。那是下一轮，这一轮先立数据层。
- 不做"安全人快速联系" / "给未来的自己写信" / "沟通话术建议"（第三档功能）。
- 不改 menu bar / Dock / popover / 全局快捷键等已稳定的 UI 通道。
- 不改 `Mood` / `Intensity` 模型。
- 不改 `Info.plist` / `entitlements` / 部署目标 / Xcode 工程版本号。
- 不引入 SwiftPM / CocoaPods / Carthage 依赖。
- 不动 `scripts/build-dmg.sh` / `scripts/make-icons.py` / `scripts/patch-pbxproj.py`（这一轮新增 2 个 Swift 文件，按 `AGENTS.md §12` 既定 idempotent 流程走即可）。
- 不为 trigger 标签做用户自定义 / 增删 UI（v1 预定义 8 个，加自定义是独立 PR 的工作量）。
- 不在已 resolved 的记录上做"重新弹 reality check"按钮（一旦写了 `realityCheck` 就固定）。

## 4. 架构

### 4.1 数据模型

`MissingPlusPlus/Models/Missing.swift` 加 3 字段 + `RealityCheck` struct + 自定义 `Codable`：

```swift
struct Missing: Identifiable, Codable, Hashable {
    let id: UUID
    let who: String
    let mood: Mood
    let intensity: Intensity
    let createdAt: Date
    var triggerTags: [TriggerTag]   // 新增，默认 []
    var resolvedAt: Date?           // 新增，默认 nil
    var realityCheck: RealityCheck? // 新增，默认 nil

    init(
        id: UUID = UUID(),
        who: String,
        mood: Mood,
        intensity: Intensity,
        createdAt: Date = Date(),
        triggerTags: [TriggerTag] = [],
        resolvedAt: Date? = nil,
        realityCheck: RealityCheck? = nil
    ) {
        self.id = id
        self.who = who
        self.mood = mood
        self.intensity = intensity
        self.createdAt = createdAt
        self.triggerTags = triggerTags
        self.resolvedAt = resolvedAt
        self.realityCheck = realityCheck
    }

    private enum CodingKeys: String, CodingKey {
        case id, who, mood, intensity, createdAt
        case triggerTags, resolvedAt, realityCheck
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.who = try c.decode(String.self, forKey: .who)
        self.mood = try c.decode(Mood.self, forKey: .mood)
        self.intensity = try c.decode(Intensity.self, forKey: .intensity)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)

        // Forward-compat: 老 JSON 缺 triggerTags → []; 未来加新 case 后老 JSON
        // 里的旧 rawValue → 过滤掉
        let rawTags = try c.decodeIfPresent([String].self, forKey: .triggerTags) ?? []
        self.triggerTags = rawTags.compactMap(TriggerTag.init(rawValue:))

        self.resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        self.realityCheck = try c.decodeIfPresent(RealityCheck.self, forKey: .realityCheck)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(who, forKey: .who)
        try c.encode(mood, forKey: .mood)
        try c.encode(intensity, forKey: .intensity)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(triggerTags, forKey: .triggerTags)
        try c.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try c.encodeIfPresent(realityCheck, forKey: .realityCheck)
    }
}

struct RealityCheck: Codable, Hashable {
    var evidenceFor: String?      // "这次想念的证据..."
    var evidenceAgainst: String?  // "反对的证据..."
    var nextAction: String?       // "我接下来会..."
    var checkedAt: Date           // 什么时候做的
}
```

**JSON 兼容策略**（关键）：

- 老 `missings.json` 不带 `triggerTags` / `resolvedAt` / `realityCheck` → decoder 用 `decodeIfPresent` + 默认值，自动读为 `[]` / `nil` / `nil`。
- 未来给 `TriggerTag` 加新 case 后，老 JSON 里的旧 rawValue（不再存在）→ `compactMap(TriggerTag.init(rawValue:))` 过滤掉，不 crash。
- `RealityCheck` 整体是 optional，老数据不会包含 → 老数据 `realityCheck == nil`，符合"还没做 reality check" 的语义。

### 4.2 新增 `Models/TriggerTag.swift`

```swift
enum TriggerTag: String, Codable, CaseIterable, Hashable, Identifiable {
    case noReply       = "noReply"
    case silent        = "silent"
    case fight         = "fight"
    case alone         = "alone"
    case sawSomething  = "sawSomething"
    case pastMemory    = "pastMemory"
    case separation    = "separation"
    case comparison    = "comparison"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .noReply:      return "💬"
        case .silent:       return "🔇"
        case .fight:        return "⚡️"
        case .alone:        return "🏠"
        case .sawSomething: return "👀"
        case .pastMemory:   return "🕰"
        case .separation:   return "✈️"
        case .comparison:   return "🪞"
        }
    }

    var label: String {
        switch self {
        case .noReply:      return "TA 没及时回"
        case .silent:       return "TA 没说想我"
        case .fight:        return "刚吵完架"
        case .alone:        return "独处时"
        case .sawSomething: return "看到某物/某地"
        case .pastMemory:   return "想到过去"
        case .separation:   return "分离/即将分离"
        case .comparison:   return "比较/嫉妒"
        }
    }

    /// "💬 TA 没及时回"  — chip / notification body 共用
    var displayString: String { "\(emoji) \(label)" }
}
```

**8 个 case 选择理由**（attachment 文献 + 中文用户高频场景）：

- 8 个 chip 一行排 4 个、两行刚好
- 覆盖 attachment 文献最常被提到的 6 类（不回复 / 沉默 / 冲突 / 独处 / 触发物 / 分离）
- 多加"比较"和"回忆"是中文用户场景里这两类很高频
- 不放"感到不被理解"和"身体/生理"是因为它们和 missing 的关联弱、强度低，留给 v2 用户反馈再加

### 4.3 新增 `Views/RealityCheckSheet.swift`

```swift
struct RealityCheckSheet: View {
    let missing: Missing
    var onSave: (RealityCheck) -> Void
    var onSkip: () -> Void

    @State private var evidenceFor: String = ""
    @State private var evidenceAgainst: String = ""
    @State private var nextAction: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("现实检验")
                .font(.headline)
            Text("DBT 的「Check the Facts」: 写下来，情绪就变成可观察的事实。")
                .font(.caption)
                .foregroundColor(.secondary)

            field(title: "这次想念的证据是…",
                  placeholder: "比如：TA 5h 没回我消息",
                  text: $evidenceFor)
            field(title: "反对的证据是…",
                  placeholder: "比如：上周 TA 也这样，后来回我说在加班",
                  text: $evidenceAgainst)
            field(title: "我接下来会…",
                  placeholder: "比如：再等 30 分钟；不主动发消息",
                  text: $nextAction)

            HStack {
                Button("跳过") { onSkip(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    let check = RealityCheck(
                        evidenceFor: trimmedOrNil(evidenceFor),
                        evidenceAgainst: trimmedOrNil(evidenceAgainst),
                        nextAction: trimmedOrNil(nextAction),
                        checkedAt: Date()
                    )
                    onSave(check)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    trimmedOrNil(evidenceFor) == nil &&
                    trimmedOrNil(evidenceAgainst) == nil &&
                    trimmedOrNil(nextAction) == nil
                )
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
```

**为什么 3 个 TextField 全空时「保存」disabled**：避免"按了保存但 0 信息"，DBT skill 的价值在"写下来"，全空就跳过。

**为什么"跳过"无副作用**：焦虑型用户最怕"被工具 push"，跳过要零成本。

### 4.4 `Services/MissingStore.swift` 新增 3 方法 + 1 个 notification

```swift
extension Notification.Name {
    static let missingStoreDidUpdate = Notification.Name("MissingStoreDidUpdate")
}

@MainActor
final class MissingStore {
    // … 现有 …

    func markResolved(_ missing: Missing, at date: Date = Date()) {
        guard let idx = items.firstIndex(where: { $0.id == missing.id }) else { return }
        items[idx].resolvedAt = date
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidUpdate, object: self,
            userInfo: ["missing": items[idx]]
        )
    }

    func attachRealityCheck(_ missing: Missing, check: RealityCheck) {
        guard let idx = items.firstIndex(where: { $0.id == missing.id }) else { return }
        items[idx].realityCheck = check
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidUpdate, object: self,
            userInfo: ["missing": items[idx]]
        )
    }

    func updateTriggers(_ missing: Missing, tags: [TriggerTag]) {
        guard let idx = items.firstIndex(where: { $0.id == missing.id }) else { return }
        items[idx].triggerTags = tags
        save()
        NotificationCenter.default.post(
            name: .missingStoreDidUpdate, object: self,
            userInfo: ["missing": items[idx]]
        )
    }
}
```

3 个方法都用 `id` 定位 + `firstIndex` mutate + `save()` + post notification。`missingStoreDidUpdate` 和现有 `missingStoreDidAdd` 分开是因为它们的语义不同：add 是新建，update 是补丁（resolved / realityCheck / triggers）。

### 4.5 `Views/NewMissingForm.swift` 改动

**a) trigger picker**（intensity 行之后、submit 按钮之前）：

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("触发（多选）")
        .font(.caption)
        .foregroundColor(.secondary)
    LazyVGrid(columns: [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ], spacing: 6) {
        ForEach(TriggerTag.allCases) { tag in
            TriggerChip(
                tag: tag,
                isSelected: selectedTriggers.contains(tag)
            ) {
                if selectedTriggers.contains(tag) {
                    selectedTriggers.remove(tag)
                } else {
                    selectedTriggers.insert(tag)
                }
            }
        }
    }
}
```

- 8 个 chip 排成 4×2 网格
- 多选 toggle，不强制选
- 强度 0/1 也显示 —— 低强度想念也有 context

**b) "上一条平复了吗" banner**（ScrollView 顶部、header 之后）：

```swift
if let latest = MissingStore.shared.sortedItems.first,
   latest.resolvedAt == nil,
   Date().timeIntervalSince(latest.createdAt) > 30 * 60,
   AppPreferences.shared.autoPromptResolveLast
{
    ResolveLastBanner(latest: latest) { response in
        switch response {
        case .yes: MissingStore.shared.markResolved(latest)
        case .no, .skip: break
        }
    }
}
```

- **30 分钟 grace period**（`timeIntervalSince(latest.createdAt) > 30 * 60`）：避免"刚提交完新一条 → banner 立刻问刚那条" 的 awkwardness；给想念"先活 30 分钟"再被问
- banner 内 3 按钮：「是（stamp `resolvedAt = Date()`）」/「否（保持） 」/「跳过」
- banner 是纯 SwiftUI 组件，state 由父 view 持有

**c) 自动弹 RealityCheckSheet**（submit 后）：

```swift
@State private var pendingRealityCheck: Missing?

// in submit handler:
if missing.intensity == .strong,
   AppPreferences.shared.autoPromptRealityCheck {
    pendingRealityCheck = missing
}

// view modifier:
.sheet(item: $pendingRealityCheck) { record in
    RealityCheckSheet(missing: record) { check in
        MissingStore.shared.attachRealityCheck(record, check: check)
    } onSkip: {
        // no-op
    }
}
```

- **触发条件**：`intensity == .strong`（即原"≥ 2"，对应 `none=0 / mild=1 / strong=2`）+ setting 开
- 用 `sheet(item:)` 而不是 `sheet(isPresented:)`，因为我们要传 `missing` 进去（`Missing` 现在是 `Hashable`，符合 `Identifiable`/sheet item 要求）
- "弹过"是 per-record 一次性 —— `pendingRealityCheck = missing` 后 sheet dismiss 时 SwiftUI 把它设回 nil，下次添加新一条才再次触发

### 4.6 `Views/HistoryList.swift` 改动

每条卡片在现有布局上加 inline：

```
[who + mood emoji]  [intensity dots]  [✓ 2h 前 / ○]      ← 现有行
[💬 🏠 ✈️] trigger chips (选了的才显示)               ← 新增
[📋 已做现实检验] 折叠 tag (有 realityCheck 才显示)  ← 新增
[6/15 14:30]                                          ← 现有
[做现实检验] 按钮 (无 realityCheck 才显示)         ← 新增
```

- **trigger chips**：emoji + label 拼成小 chip，1-3 个最多；超过 3 个用 `+N more` trunc
- **resolved icon**：右上角，"✓ 2h 前" 用对应 mood 颜色（`MoodColor.forMood(mood)`），"○" 灰色；点击调 `markResolved(missing)`
- **realityCheck 折叠 tag**：点开 inline 展开 3 栏内容（evidenceFor / evidenceAgainst / nextAction 各 1-2 行 trunc）
- **"做现实检验" 按钮**：触发同一个 `RealityCheckSheet`（与自动弹共用 view）

### 4.7 `Views/StatisticsView.swift` 改动

顶部加 3 个 insight 卡片（按顺序），下面保留现有 30-day trend chart + Top 3 思念对象。

**计算函数**（view-time computed，scope 30 天）：

```swift
private var last30Days: [Missing] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    return items.filter { $0.createdAt >= cutoff }
}

/// 卡片 1: 平复率 + 平均平复时长
private var waveStats: (rate: Double, count: Int, total: Int, avg: TimeInterval?) {
    let last = last30Days
    let total = last.count
    guard total > 0 else { return (0, 0, 0, nil) }
    let durations: [TimeInterval] = last.compactMap { item in
        item.resolvedAt?.timeIntervalSince(item.createdAt)
    }
    let count = durations.count
    let rate = Double(count) / Double(total)
    let avg = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
    return (rate, count, total, avg)
}

/// 卡片 2: Top 3 trigger
private var topTriggers: [(tag: TriggerTag, count: Int, total: Int)] {
    let last = last30Days
    let total = last.count
    guard total > 0 else { return [] }
    var counts: [TriggerTag: Int] = [:]
    for item in last {
        for tag in item.triggerTags { counts[tag, default: 0] += 1 }
    }
    return counts.sorted { $0.value > $1.value }
        .prefix(3)
        .map { (tag: $0.key, count: $0.value, total: total) }
}

/// 卡片 3: reality check 完成度
private var realityCheckStats: (rate: Double, completed: Int, eligible: Int) {
    let last = last30Days
    let eligible = last.filter { $0.intensity == .strong }.count
    guard eligible > 0 else { return (0, 0, 0) }
    let completed = last.filter { $0.intensity == .strong && $0.realityCheck != nil }.count
    return (Double(completed) / Double(eligible), completed, eligible)
}
```

**卡片 1「浪都过去了」**：

```swift
struct WaveResolvedCard: View {
    let stats: (rate: Double, count: Int, total: Int, avg: TimeInterval?)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("浪都过去了")
                .font(.subheadline.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int((stats.rate * 100).rounded()))%")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(stats.rate >= 0.8 ? .green : .primary)
                Text("过去 30 天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.pink.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        if stats.total == 0 { return "还没有记录" }
        if let avg = stats.avg {
            let hours = avg / 3600
            if hours < 1 {
                return "\(stats.count) / \(stats.total) 次平复，平均 \(Int(avg / 60)) 分钟"
            } else if hours < 48 {
                return "\(stats.count) / \(stats.total) 次平复，平均 \(String(format: "%.1f", hours)) 小时"
            } else {
                return "\(stats.count) / \(stats.total) 次平复，平均 \(String(format: "%.1f", hours / 24)) 天"
            }
        } else {
            return "\(stats.count) / \(stats.total) 次平复"
        }
    }
}
```

**卡片 2「你的常见 trigger」**：

```swift
struct TopTriggersCard: View {
    let triggers: [(tag: TriggerTag, count: Int, total: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你的常见 trigger")
                .font(.subheadline.weight(.medium))
            if triggers.isEmpty {
                Text("记几次带 trigger 标签的想念后会看到")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(triggers, id: \.tag) { entry in
                    HStack {
                        Text(entry.tag.displayString).font(.callout)
                        Spacer()
                        Text("\(entry.count) 次 · \(Int(Double(entry.count) / Double(entry.total) * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.pink.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(entry.count) / CGFloat(entry.total))
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

**卡片 3「现实检验完成度」**：

```swift
struct RealityCheckCard: View {
    let stats: (rate: Double, completed: Int, eligible: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("现实检验完成度")
                .font(.subheadline.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int((stats.rate * 100).rounded()))%")
                    .font(.title2.weight(.semibold))
                Text("强烈的想念里")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(stats.eligible == 0
                 ? "还没有强烈的想念需要检验"
                 : "\(stats.completed) / \(stats.eligible) 次完成 DBT Check the Facts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

`StatisticsView` body 在现有 trend chart 之前按顺序塞这 3 个 card。`StatisticsView` 已经是 ScrollView，3 卡片不破坏结构。

### 4.8 `Services/AppPreferences.swift` 加 3 个 `@Published`

```swift
@Published var autoPromptRealityCheck: Bool {
    didSet {
        defaults.set(autoPromptRealityCheck, forKey: Keys.autoPromptRealityCheck)
    }
}
@Published var autoPromptResolveLast: Bool {
    didSet {
        defaults.set(autoPromptResolveLast, forKey: Keys.autoPromptResolveLast)
    }
}
@Published var notificationIncludeTriggers: Bool {
    didSet {
        defaults.set(notificationIncludeTriggers, forKey: Keys.notificationIncludeTriggers)
    }
}

private enum Keys {
    // 现有 …
    static let autoPromptRealityCheck = "AutoPromptRealityCheck"
    static let autoPromptResolveLast = "AutoPromptResolveLast"
    static let notificationIncludeTriggers = "NotificationIncludeTriggers"
}

private init() {
    // 现有 …
    self.autoPromptRealityCheck =
        defaults.object(forKey: Keys.autoPromptRealityCheck) as? Bool ?? true
    self.autoPromptResolveLast =
        defaults.object(forKey: Keys.autoPromptResolveLast) as? Bool ?? true
    self.notificationIncludeTriggers =
        defaults.object(forKey: Keys.notificationIncludeTriggers) as? Bool ?? true
}
```

3 个都默认开 —— 见 §2 理由，焦虑型用户最痛不是"打扰多"是"看不见 pattern"。

### 4.9 `Views/SettingsView.swift` 加 1 个 section

在 `menuBarSection` 之后加一个 `attachmentBundleSection`：

```swift
private var attachmentBundleSection: some View {
    Section {
        Toggle("高强度时弹出现实检验", isOn: $prefs.autoPromptRealityCheck)
        Toggle("新建时回访「上一条平复了吗」", isOn: $prefs.autoPromptResolveLast)
        Toggle("通知里带 trigger 信息", isOn: $prefs.notificationIncludeTriggers)
    } header: {
        Text("依恋辅助")
    } footer: {
        Text("这些工具帮助焦虑型依恋人格看见 trigger 模式、累积「浪会过去」的证据。")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

frame 高度从 600 → 660（容纳新 section + footer），宽度 480 不变。

### 4.10 通知 body 更新

`AppDelegate.postRecordNotification(for:)` body 拼接：

```swift
let base = "想念 \(missing.who)　心情：\(missing.mood.label)　程度：\(missing.intensity.label)"
let triggerPart: String
if AppPreferences.shared.notificationIncludeTriggers,
   !missing.triggerTags.isEmpty {
    let strs = missing.triggerTags.map(\.displayString)
    triggerPart = "　触发：" + strs.joined(separator: " ")
} else {
    triggerPart = ""
}
let body = base + triggerPart
```

triggerTags 非空 + setting 开 → 追加"　触发：💬 TA 没及时回 🏠 独处时"。空 → 不追加（保持现状）。

## 5. 数据流

```
用户提交一条新 missing (intensity = strong)
    ↓
MissingStore.add → post .missingStoreDidAdd
    ↓ (3 个分支)
    ├─→ NewMissingForm.pendingRealityCheck = missing
    │       ↓
    │   .sheet(item: $pendingRealityCheck) 弹 RealityCheckSheet
    │       ↓ (用户填完保存)
    │   MissingStore.attachRealityCheck(record, check:) → .missingStoreDidUpdate
    │
    ├─→ AppDelegate.handleMissingAdded → currentMood + 通知 (body 含 trigger)
    │
    └─→ (下次打开 NewMissingForm) banner 检测 latest unresolved + > 30min → 显示


用户点击 HistoryList 卡片"○ 平复"
    ↓
MissingStore.markResolved(missing) → post .missingStoreDidUpdate
    ↓
HistoryList / StatisticsView 自动刷新（@Published items）


Settings 改 toggle
    ↓ (Binding)
AppPreferences.@Published → didSet 落盘 + (现成 post .appPreferencesDidChange)
    ↓
下次弹 sheet / banner 时按新 setting 走
```

## 6. 错误处理 / 边界

- **老 JSON 缺 3 字段**：`Missing.init(from:)` 用 `decodeIfPresent` + 默认值，自动读为 `[]` / `nil` / `nil`。**关键测试**（见 §7）：手写 1 条无新字段的 JSON 启动 app 能读不崩。
- **老 JSON 有未知 trigger rawValue**：`compactMap(TriggerTag.init(rawValue:))` 过滤掉，trigger 列表中不会出现"幽灵 chip"。
- **未 resolved 的 intensity < strong 记录**：banner 仍显示（banner 触发只看 `resolvedAt == nil`，不限 intensity）—— 这是 v1 行为，§10 列为"未确定项"，后续可调。
- **冷启动 + 没记录**：3 个 insight 卡片走 empty state 文案（"还没有记录" / "记几次带 trigger 标签的想念后会看到" / "还没有强烈的想念需要检验"）。
- **填 reality check 全空 → 按"保存"被 disabled**：强制写至少 1 栏。
- **填 reality check 部分 → 保存**：3 栏可独立 nil/空；空字符串 normalize 为 nil。
- **`pendingRealityCheck` 触发后用户强行关掉 sheet**（点 X / Cmd+W）：sheet dismiss 但 record 没拿到 realityCheck，符合"用户主动跳过"语义。`pendingRealityCheck` 回到 nil，下条记录提交时可再触发。
- **`markResolved` 重复点**：幂等。再次调只是把 `resolvedAt` 更新到 now；卡片上"✓ 2h 前" 会重置（v1 接受这个行为，v2 可加"已平复不重复 stamp" 开关）。
- **`autoPromptRealityCheck` setting 关闭**：submit 后不弹 sheet，但 HistoryList 手动按钮仍可用（B 路径兜底）。
- **bundle 3 个 setting 全部关闭**：app 行为退回 v1 现状（只记 who/mood/intensity）。
- **trigger picker 选了又取消**：行为正常，存的就是 `[]`。

## 7. 测试 / 验证

**Build**：

- [ ] `xcodebuild -configuration Debug` → `** BUILD SUCCEEDED **`
- [ ] `xcodebuild -configuration Release` → `** BUILD SUCCEEDED **`

**功能**：

- [ ] 启动 → ⌘, → 看到新 section "依恋辅助"，3 个 toggle 都默认开
- [ ] 录一条 intensity=strong + 2 trigger → 自动弹 RealityCheckSheet → 填 evidenceFor + 保存 → 卡片显示 trigger chips + "📋 已做现实检验" tag
- [ ] 录一条 intensity=mild + 1 trigger → 不弹 sheet（intensity 不够），但 trigger chips 仍显示
- [ ] 录一条 intensity=strong 不弹 sheet 时（setting 关了 autoPromptRealityCheck）→ HistoryList 卡片底部出现"做现实检验"按钮 → 点了弹同一个 sheet
- [ ] HistoryList 卡片右上角点"○" → 变"✓ 刚刚"，过 1 小时变"✓ 1h 前"
- [ ] 等 30 分钟后新建表单 → 顶部出现"上次想念平复了吗？" banner
- [ ] banner 点"是" → 上一条立刻显示"✓ 刚刚"，banner 消失
- [ ] banner 点"跳过" → banner 消失，record 状态不变
- [ ] 看统计 tab → 3 个 insight 卡片数字正确（手工核对 1-2 条）
- [ ] 通知 body 含"触发：💬 TA 没及时回"（setting 开时）

**JSON 兼容**：

- [ ] 删 `~/Library/Application Support/MissingPlusPlus/missings.json` → 启动 → empty state ✓
- [ ] 手写 1 条无新字段的 JSON（`{"id":...,"who":"X","mood":"longing","intensity":"strong","createdAt":...}`）→ 启动 → 能读不崩，新字段走默认
- [ ] 写 1 条带 `triggerTags: ["noReply", "DELETED_FUTURE_CASE"]` 的 JSON → 启动 → `["noReply"]` 被读入，"DELETED_FUTURE_CASE" 被过滤掉，不崩

**回归防坑**（AGENTS.md §5/§16/§20）：

- [ ] popover 仍走 `PopoverContent`（stat + history tab，不含 form）
- [ ] 主窗口仍走 `MenuBarContent`（3 tab）
- [ ] 菜单栏 `button.title = mood.emoji` + 5 mood 染色 + auto-fade 行为不变
- [ ] 菜单栏 `applyHeartText`/`applyHeartImage` 切换行为不变
- [ ] `MissingStore.add` 仍 post `.missingStoreDidAdd`（不是被替换成 update）
- [ ] `MissingStore.delete` / `replaceAll` / `merge` 行为不变
- [ ] `AGENTS.md` §5.1 既有"不要做"清单继续生效

**打包**：

- [ ] `bash scripts/build-dmg.sh` 跑通
- [ ] `scripts/patch-pbxproj.py` 幂等：2 个新文件（`TriggerTag.swift` / `RealityCheckSheet.swift`）按 §12 流程 patch 进去不重复
- [ ] pbxproj 4 处插入（PBXBuildFile ×2 / PBXFileReference ×2 / 各自 group ×2 / PBXSourcesBuildPhase ×2）跑通

## 8. 改动文件

**新增（2 个）**：

| 文件 | 类型 | 说明 |
|------|------|------|
| `MissingPlusPlus/Models/TriggerTag.swift` | 新增 | enum + 8 case + emoji/label/displayString |
| `MissingPlusPlus/Views/RealityCheckSheet.swift` | 新增 | sheet view，3 TextField + 保存/跳过 |

**修改（9 个）**：

| 文件 | 说明 |
|------|------|
| `MissingPlusPlus/Models/Missing.swift` | 加 3 字段 + `RealityCheck` struct + 自定义 `init(from:)` / `encode(to:)` |
| `MissingPlusPlus/Services/MissingStore.swift` | 加 3 方法（`markResolved` / `attachRealityCheck` / `updateTriggers`）+ `missingStoreDidUpdate` notification |
| `MissingPlusPlus/Views/NewMissingForm.swift` | trigger picker + "上一条平复了吗" banner + 自动弹 sheet |
| `MissingPlusPlus/Views/HistoryList.swift` | 卡片新增 trigger chips / resolved icon / realityCheck tag / 手动按钮 |
| `MissingPlusPlus/Views/StatisticsView.swift` | 顶部 3 insight 卡片（`WaveResolvedCard` / `TopTriggersCard` / `RealityCheckCard`）|
| `MissingPlusPlus/Services/AppPreferences.swift` | 加 3 `@Published` + 3 `@AppStorage` key + init 默认值 |
| `MissingPlusPlus/Views/SettingsView.swift` | 加 `attachmentBundleSection` + frame 600 → 660 |
| `MissingPlusPlus/MissingPlusPlusApp.swift` 或 `AppDelegate.swift` | `postRecordNotification` body 加 trigger 部分 |
| `AGENTS.md` | 新增章节（建议编号 §22）记录 bundle 行为 + JSON 兼容策略 |

**pbxproj 4 处插入**：

- PBXBuildFile ×2（`TriggerTag.swift` / `RealityCheckSheet.swift`）
- PBXFileReference ×2
- Models group ×1（TriggerTag）
- Views group ×1（RealityCheckSheet）
- PBXSourcesBuildPhase ×2

**不改**：

- `MissingPlusPlus/Models/Mood.swift` / `Intensity.swift`
- `MissingPlusPlus/Services/StorageService.swift` / `MenuBarIconRenderer.swift`
- `MissingPlusPlus/Views/MenuBarContent.swift` / `PopoverOverflowMenu.swift`
- `MissingPlusPlus/Resources/*`（图标资源不变）
- `MissingPlusPlus/Info.plist` / `.entitlements`
- `scripts/build-dmg.sh` / `scripts/make-icons.py`（不重做图标）

## 9. 「不要做」（新增）

按 `AGENTS.md §5.1` 已有规则继续生效，这一轮新加：

- 不要把 trigger 标签做成用户可自定义（v1 预定义 8 个，加自定义是独立 PR）。
- 不要在已 resolved 的 record 上再弹 reality check sheet（record 已经有 `realityCheck != nil` 时不弹）。
- 不要在 `MissingStore` 里直接读 `AppPreferences`（保持 store 不碰 UI/prefs；调用方传值）。
- 不要把 `triggerTags` / `resolvedAt` / `realityCheck` 写进 `note` 字段（用结构化字段，note 留给用户自由文本）。
- 不要做"重新弹 reality check"按钮（一旦写了 `realityCheck` 就固定，DBT 强调"做完就完"，不要回头反复 check）。
- 不要做 trigger 用户自定义增删 UI（v1 严禁）。
- 不要在 popover（`PopoverContent`）里加 trigger picker（popover 是 peek 视图，记录功能留给主窗口 `MenuBarContent` / `NewMissingForm`）。
- 不要把 3 个 insight 卡片的数字"凑好看"（比如人为 floor 30% → 50%），用真实数字。
- 不要把 "上一条平复了吗" banner 的 30 分钟 grace period 缩到 < 10 分钟（焦虑型用户提交后立刻被问会 push 反效果）。
- 不要给 `RealityCheckSheet` 加"上次的草稿"（每次 fresh 写，不要做"自动恢复"，避免"上次的情绪污染这次的判断"）。

## 10. 风险 / 备注

- **`pendingRealityCheck` 状态机**：sheet 关闭时 SwiftUI 把 `pendingRealityCheck` 设回 nil；如果用户同时打开多个 sheet（不应该发生但理论上可能），state 会乱。`@State` 写在 `NewMissingForm` 内部而不是全局 store，避免这个问题。
- **30 分钟 grace period 是不是太短**：v1 试 30 分钟；用户反馈"banner 来得太快 / 太慢"再调（设置项可加"banner grace period"，但 v1 不加）。
- **trigger picker 选 5+ 个时 UI 拥挤**：8 个 chip 在 360pt 宽 popover 里 4×2 网格；用户选多了不展开（v1 直接全显示，不做"折叠更多"）。
- **统计 tab 3 个 insight 卡片 + 现有 trend chart 总高度可能 > 720pt**：scrollable，`StatisticsView` 已经是 ScrollView，加 3 卡片不破坏结构；trend chart 高度不变。
- **`postRecordNotification` 改 body 格式可能影响现有用户对通知的预期**：默认 `notificationIncludeTriggers = true` 保持体感一致；想关回老格式的用户有 toggle。
- **`markResolved` 重复点击**：`resolvedAt` 重置到 now（v1 行为，§6 已说明）。如要"已平复不重复 stamp" 改语义，需加 `if items[idx].resolvedAt != nil { return }` 守卫。
- **`MoodColor.forMood(_:)` 复用**：`StatisticsView` 已有这个 helper（`AGENTS.md §10/§13`），resolved icon 颜色直接复用，不新写。
- **pbxproj patch 风险**：`AGENTS.md §12` 提到 `scripts/patch-pbxproj.py` 之前有过幂等 bug 修过一版，sentinel check 稳。这一轮 2 个新 Swift 文件走 idempotent 流程；如果 ID 冲突手 patch 也行，参照 `MissingStore.swift` / `StorageService.swift` 现有 block。
- **macOS 26 + Xcode 26 限制**：`AGENTS.md §6` 提到 Xcode 26 不 embed Swift stdlib，这一轮不动 `Info.plist` / `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES`，沿用现状。
- **AGENTS.md 章节编号**：当前到 §21，新增章节接 §22 写"Record bundle 行为 + JSON 兼容 + 3 个新 toggle"。建议在 §21 之后追加，编号连续。
- **未确定项**（v1 不阻塞，可后续讨论）：banner 的"上一条"是否只问 `intensity == .strong` 的记录？还是所有 unresolved 都问？v1 选择"所有 unresolved"，理由是"温和 nudge 比精准更安全"。
