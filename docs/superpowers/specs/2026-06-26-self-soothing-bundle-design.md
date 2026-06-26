# Self-Soothing Bundle — 设计

> 日期：2026-06-26
> 状态：待 review
> 涉及范围：新增 3 view + 1 model / `RealityCheckSheet.swift` / `HistoryList.swift` / `NewMissingForm.swift` / `AppPreferences.swift` / `SettingsView.swift` / `AGENTS.md`

## 1. 背景

Record bundle（v1.x 第一轮，spec `2026-06-26-anxious-attachment-bundle-design.md`）已经把"记录 + 看见 pattern + 累积平复证据"这条线立起来 —— trigger / resolved / reality check 三个字段 + 3 个统计 insight 卡片。

但 **record bundle 是认知层（"看清你的 pattern"），self-soothing 是 body 层（"浪来时怎么接住你"）**。焦虑型最痛的不是"我不知道我为什么会这样"，是"浪来时我接不住自己" —— 认知清楚了也顶不住 emotion flooding。

这一轮补这一块：3 个 sub-sheet 工具（5-4-3-2-1 grounding / 自我同情 break / cooldown 活动），让浪来时**手点引导**走完一次 30 秒左右的 self-soothing。

## 2. 目标

3 个 sub-sheet 工具：

1. **`GroundingSheet`** —— 5-4-3-2-1 sensory grounding，step-by-step 引导（5 步走完 1 次 grounding）
2. **`SelfCompassionView`** —— 1 句 Kristin Neff 风格 curated 短语 + "再抽一句"按钮
3. **`CooldownSheet`** —— 从 6 预定义 + 用户追加的活动里随机抽 1 条 + "再抽一个"按钮

2 个入口：

- **A 路径**（浪来时强 nudge）：`RealityCheckSheet` 底部加 3 个 sub-button，自动弹时（intensity == strong）路径最短
- **B 路径**（事后回访）：`HistoryList` 卡片底部加同样的 3 个 sub-button，mild 也能用

1 个轻度 inline nudge：

- `NewMissingForm` 提交 intensity == mild 后短暂显示 "想冷静一下？" 链接（3 秒后 fade），用户主动点进 sub-sheet

## 3. 非目标

- 不做 timer-based "5 分钟冥想"（5-4-3-2-1 是手点引导，不是被动 timer）
- 不做 self-compassion 用户自定义短语（v1 curated 7 句，避免鸡汤合集）
- 不在 popover（`PopoverContent`）里加 3 sub-button（popover 是 peek，工具在主窗口用）
- 不在 `Missing` 模型里加新字段（这次所有数据走 AppPreferences/UserDefaults）
- 不做 push notification 主动推送 self-soothing（v1 永远 opt-in via 按钮）
- 不动 Record bundle 已稳定的 13 个 commit

## 4. 架构

### 4.1 数据层

`AppPreferences.swift` 加 1 个 `@Published`：

```swift
/// v1.x self-soothing bundle: 用户追加的 cooldown 活动（预定义 6 条永远在前面，
/// 用户新增的 append 在后面；预定义不能删，用户追加的能删）。
@Published var cooldownActivities: [String] {
    didSet {
        defaults.set(cooldownActivities, forKey: Keys.cooldownActivities)
    }
}

private enum Keys {
    // 现有 keys
    static let cooldownActivities = "CooldownActivities"
}

private init() {
    // 现有 init
    self.cooldownActivities =
        defaults.stringArray(forKey: Keys.cooldownActivities) ?? []
}
```

**关键设计**：`cooldownActivities` 只存**用户追加的**（不是全部 9 条）。预定义 6 条 hardcode 在代码里（`CooldownActivities.defaults: [String]`），cooldown sheet 渲染时取 `defaults + cooldownActivities` 拼接。这样：
- 老数据无 `CooldownActivities` 字段 → `cooldownActivities = []`，preference 缺字段 fallback
- 预定义 6 条跟随 app 版本更新（"新版多加了 '整理桌面'"）
- 用户追加的活动跨版本保留

### 4.2 新增 `Models/CooldownActivities.swift`

```swift
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
```

### 4.3 新增 `Views/GroundingSheet.swift`

```swift
import SwiftUI

/// 5-4-3-2-1 sensory grounding，step-by-step 引导。每步 1 句引导 + "下一个"按钮。
/// 5 步走完弹"你刚刚做了一次 grounding"完成页。
struct GroundingSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    // 5 steps + 1 done page = 6 states

    private let senses: [(sense: String, prompt: String)] = [
        ("看", "慢慢环顾四周，说出你能看到的 5 样东西。"),
        ("听", "现在注意听，说出你能听到的 4 种声音。"),
        ("触", "感受身体接触的 3 样东西（椅子/衣服/手）。"),
        ("闻", "找出空气中的 2 种气味。"),
        ("尝", "注意你嘴里的 1 种味道。"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if step < senses.count {
                // Progress
                HStack {
                    Text("\(step + 1) / \(senses.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(senses[step].sense)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(senses[step].prompt)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)

                HStack {
                    Spacer()
                    Button(step < senses.count - 1 ? "下一个" : "完成") {
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                // Done page
                VStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text("你刚刚做了一次 grounding")
                        .font(.headline)
                    Text("想关掉就点下面；想再来一次也行。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button("再来一次") { step = 0 }
                            .buttonStyle(.bordered)
                        Button("关闭") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

### 4.4 新增 `Views/SelfCompassionView.swift`

```swift
import SwiftUI

/// 自我同情 break —— 1 句 Kristin Neff 风格短语 + "再抽一句"按钮。
struct SelfCompassionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = .random(in: 0..<SelfCompassionPhrases.phrases.count)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自我同情")
                .font(.headline)
            Text("DBT / Kristin Neff：对自己说一句有用的话。")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(SelfCompassionPhrases.phrases[index])
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 32)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.pink.opacity(0.06))
                )

            HStack {
                Button("再抽一句") {
                    var next = index
                    while next == index && SelfCompassionPhrases.phrases.count > 1 {
                        next = .random(in: 0..<SelfCompassionPhrases.phrases.count)
                    }
                    index = next
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

**关键点**：换下一句时确保 `next != index`（避免按了"再抽一句"还在同一句），用 `while` 循环直到不同。池子只有 1 句时直接 reuse（虽然 v1 有 7 句但 defensive）。

### 4.5 新增 `Views/CooldownSheet.swift`

```swift
import SwiftUI

/// Cooldown 活动 —— 从 6 预定义 + 用户追加的活动里随机抽 1 条 + "再抽一个"按钮。
struct CooldownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var prefs: AppPreferences
    @State private var index: Int = 0
    @State private var available: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("分散注意力")
                .font(.headline)
            Text("从清单里挑一件做 5 分钟，让情绪过一下。")
                .font(.caption)
                .foregroundColor(.secondary)

            if available.isEmpty {
                Text("没有 cooldown 活动了 —— 去 settings 加几条。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 24)
            } else {
                Text(available[index])
                    .font(.title2.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple.opacity(0.06))
                    )
            }

            HStack {
                Button("再抽一个") {
                    guard !available.isEmpty else { return }
                    var next = index
                    while next == index && available.count > 1 {
                        next = .random(in: 0..<available.count)
                    }
                    index = next
                }
                .buttonStyle(.bordered)
                .disabled(available.isEmpty)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            available = CooldownActivities.all(custom: prefs.cooldownActivities)
            if !available.isEmpty {
                index = .random(in: 0..<available.count)
            }
        }
    }
}
```

**关键点**：`available` 在 `.onAppear` 时计算（prefs 可能在 sheet 期间改），initial index 随机。

### 4.6 `Views/RealityCheckSheet.swift` 加 3 sub-button

在 sheet 底部 "保存 / 跳过" 那行下面加：

```swift
HStack {
    Text("想先做点别的？")
        .font(.caption)
        .foregroundColor(.secondary)
    Spacer()
    Button {
        pendingGrounding = true
    } label: {
        Label("5-4-3-2-1", systemImage: "eye")
            .font(.caption2)
    }
    .buttonStyle(.borderless)
    Button {
        pendingCompassion = true
    } label: {
        Label("自我同情", systemImage: "heart.text.square")
            .font(.caption2)
    }
    .buttonStyle(.borderless)
    Button {
        pendingCooldown = true
    } label: {
        Label("分散", systemImage: "shuffle")
            .font(.caption2)
    }
    .buttonStyle(.borderless)
}
.padding(.top, 4)
```

加 3 个 `@State` 触发 sheet：

```swift
@State private var pendingGrounding = false
@State private var pendingCompassion = false
@State private var pendingCooldown = false
```

加 3 个 `.sheet` modifier：

```swift
.sheet(isPresented: $pendingGrounding) {
    GroundingSheet()
}
.sheet(isPresented: $pendingCompassion) {
    SelfCompassionView()
}
.sheet(isPresented: $pendingCooldown) {
    CooldownSheet(prefs: AppPreferences.shared)
}
```

**关键点**：3 个 sub-button 是**纯 opt-in**（不强弹），用户填完 RealityCheckSheet 也能直接保存走人。

### 4.7 `Views/HistoryList.swift` 卡片加 3 sub-button

HistoryRow 加 3 个 sub-button 在卡片底部"做现实检验"按钮旁：

```swift
HStack(spacing: 8) {
    if item.realityCheck == nil {
        Button(action: onRequestCheck) {
            Label("做现实检验", systemImage: "checkmark.bubble")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .foregroundColor(.purple)
    }
    // v1.x: self-soothing sub-buttons (per-card 手动)
    Button(action: { onRequestGrounding() }) {
        Label("5-4-3-2-1", systemImage: "eye")
            .font(.caption2)
    }
    .buttonStyle(.borderless)
    .foregroundColor(.blue)
    Button(action: { onRequestCompassion() }) {
        Label("自我同情", systemImage: "heart.text.square")
            .font(.caption2)
    }
    .buttonStyle(.borderless)
    .foregroundColor(.pink)
    Button(action: { onRequestCooldown() }) {
        Label("分散", systemImage: "shuffle")
            .font(.caption2)
    }
    .buttonStyle(.borderless)
    .foregroundColor(.purple)
}
```

加 3 个 closure 到 `HistoryRow`：

```swift
private struct HistoryRow: View {
    let item: Missing
    let onResolve: () -> Void
    let onRequestCheck: () -> Void
    let onRequestGrounding: () -> Void
    let onRequestCompassion: () -> Void
    let onRequestCooldown: () -> Void
    // ...
}
```

`HistoryList` 加 3 个 `@State` + 3 个 `.sheet` modifier：

```swift
@State private var pendingGrounding: Missing?
@State private var pendingCompassion: Missing?
@State private var pendingCooldown: Missing?
```

`.sheet(item:)` 传 Missing 是为了"per-record context"（虽然 sub-sheet 不显示 who，但 future-proof）：

```swift
.sheet(item: $pendingGrounding) { _ in GroundingSheet() }
.sheet(item: $pendingCompassion) { _ in SelfCompassionView() }
.sheet(item: $pendingCooldown) { _ in CooldownSheet(prefs: AppPreferences.shared) }
```

**关键点**：`Missing` 现在是 `Hashable`（record bundle Task 2 加的），所以 `.sheet(item:)` 能用。

### 4.8 `Views/NewMissingForm.swift` 加 "想冷静一下？" inline link

submit 后、mild 路径（没弹 RealityCheckSheet），在表单顶部短暂显示 inline link：

```swift
@State private var showSoothingLink: Bool = false

// in submit handler, after store.add:
if entry.intensity != .strong {
    // mild 路径不弹 RealityCheckSheet，给一个 inline "想冷静一下？" 链接
    showSoothingLink = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        showSoothingLink = false
    }
}

// in body, near top of formFields:
if showSoothingLink {
    HStack {
        Image(systemName: "sparkles")
            .foregroundColor(.pink)
        Text("想冷静一下？")
            .font(.caption)
        Spacer()
        Button("5-4-3-2-1") { pendingGrounding = true }
            .buttonStyle(.borderless)
            .font(.caption2)
        Button("自我同情") { pendingCompassion = true }
            .buttonStyle(.borderless)
            .font(.caption2)
        Button("分散") { pendingCooldown = true }
            .buttonStyle(.borderless)
            .font(.caption2)
    }
    .padding(8)
    .background(
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.pink.opacity(0.06))
    )
    .transition(.opacity)
}
```

加 3 个 sheet state + modifier（和 HistoryList 一样的 pattern）：

```swift
@State private var pendingGrounding = false
@State private var pendingCompassion = false
@State private var pendingCooldown = false
```

`.sheet(isPresented:)` for each.

**关键点**：
- 只在 mild 路径显示（strong 走 RealityCheckSheet sub-button，路径不重复）
- 5 秒后自动 fade（`showSoothingLink = false`），不打扰用户
- 用户可以提前点关闭（如果加 close 按钮；v1 不加，5 秒自动 fade 即可）

### 4.9 `Views/SettingsView.swift` 加 CooldownSection

```swift
private var cooldownSection: some View {
    Section {
        ForEach(allCooldownActivities, id: \.self) { activity in
            HStack {
                Text(activity)
                Spacer()
                if !CooldownActivities.defaults.contains(activity) {
                    Button {
                        removeCooldownActivity(activity)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "lock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        HStack {
            TextField("加一条你自己的…", text: $newCooldownText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addCooldownActivity)
            Button("添加", action: addCooldownActivity)
                .disabled(newCooldownText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    } header: {
        Text("Cooldown 活动")
    } footer: {
        Text("🔒 标记的是预定义 6 条（不能删）。你追加的可以删。")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

@State private var newCooldownText: String = ""

private var allCooldownActivities: [String] {
    CooldownActivities.all(custom: prefs.cooldownActivities)
}

private func addCooldownActivity() {
    let trimmed = newCooldownText.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    var current = prefs.cooldownActivities
    if !CooldownActivities.all(custom: current).contains(trimmed) {
        current.append(trimmed)
        prefs.cooldownActivities = current
    }
    newCooldownText = ""
}

private func removeCooldownActivity(_ activity: String) {
    prefs.cooldownActivities.removeAll { $0 == activity }
}
```

`body` 加 `cooldownSection`（在 attachmentBundleSection 之后）：

```swift
storageSection
menuBarSection
attachmentBundleSection
cooldownSection
dataSection
aboutSection
```

frame 660 → 720（容纳新 section + footer）。

## 5. 数据流

```
用户提交 mild missing
    ↓
MissingStore.add → post .missingStoreDidAdd
    ↓
NewMissingForm 5 秒 inline "想冷静一下？" link + 3 sub-button
    ↓ (用户点 sub-button)
.sheet(isPresented: $pendingGrounding/Compassion/Cooldown)
    ↓
GroundingSheet / SelfCompassionView / CooldownSheet
    ↓
dismiss → 回到 NewMissingForm


用户提交 strong missing
    ↓
MissingStore.add → post .missingStoreDidAdd
    ↓
NewMissingForm 弹 RealityCheckSheet (per-record 自动)
    ↓
用户填完/跳过 RealityCheckSheet
    ↓
3 个 sub-button 可点 → 弹对应 sub-sheet
    ↓
dismiss → 回到 RealityCheckSheet


用户点 HistoryList 卡片 sub-button
    ↓
.sheet(item: $pendingGrounding/Compassion/Cooldown)
    ↓
sub-sheet
    ↓
dismiss → 回到 HistoryList
```

## 6. 错误处理 / 边界

- **`cooldownActivities` UserDefaults 缺字段**：`defaults.stringArray(forKey:) ?? []` fallback 到 `[]`，predefined 6 条永远在。
- **用户追加的 cooldown 重复 predefined 6 条**：`CooldownActivities.all(custom:)` 内部 `.filter { !defaults.contains($0) }` 去重，UI 不显示重复。
- **用户加的 cooldown 重复自己加的**：`addCooldownActivity` 检查 `allCooldownActivities` 不重复再 append。
- **cooldown 列表为空**（用户全删了 6 条 predefined 还在，但极少见）：`CooldownSheet` 显示 "没有 cooldown 活动了 —— 去 settings 加几条"，"再抽一个" disabled。
- **5-4-3-2-1 进行中点取消**：sheet dismiss，state 丢失（下次重开从 step 0 开始）—— 不保存进度。
- **重复点同一个 sub-button**（"再抽一句" / "再抽一个"）：用 `while next == index` 防同句重复；池子只有 1 句时直接 reuse。
- **`@State` 在 sub-sheet 关闭后丢失**：每次重开是 fresh 的（random 起步），不记忆"上次看到哪句" —— v1 故意，避免用户"被算法画像"的不适。

## 7. 测试 / 验证

**Build**：
- [ ] `xcodebuild -configuration Debug -scheme MissingPlusPlus build` → BUILD SUCCEEDED
- [ ] `xcodebuild -configuration Release` → BUILD SUCCEEDED

**功能**：
- [ ] 启动 → ⌘, → 看到 "Cooldown 活动" section，列出 6 条预定义 + 🔒
- [ ] settings 加 "给妈妈打电话" → 列表 append 第 7 条
- [ ] 删 "给妈妈打电话" → 列表回到 6 条
- [ ] 录 strong missing → 自动弹 RealityCheckSheet → 底部 3 sub-button 都可点
- [ ] 点 "5-4-3-2-1" sub-button → 弹 GroundingSheet → 走完 5 步 → "你刚刚做了一次 grounding" 完成页
- [ ] 录 mild missing → 顶部出现 5 秒 "想冷静一下？" link → 点 sub-button → 弹对应 sub-sheet
- [ ] HistoryList 任意卡片 → 底部 3 sub-button 都可点
- [ ] CooldownSheet 点 "再抽一个" → 换不同条目（不重复）
- [ ] SelfCompassionView 点 "再抽一句" → 换不同短语

**JSON 兼容**：
- [ ] UserDefaults 无 `CooldownActivities` → 启动 → 6 条预定义正常显示
- [ ] UserDefaults 有 `CooldownActivities = ["给妈妈打电话"]` → 启动 → 7 条显示

**回归防坑**（AGENTS.md §5/§16/§20/§22）：
- [ ] popover 仍走 `PopoverContent`（stat + history tab，不含 form 和 sub-button）
- [ ] 主窗口 3 tab（新建 / 统计 / 历史）不变
- [ ] 菜单栏 `button.title = mood.emoji` + 5 mood 染色 + auto-fade 不变
- [ ] Record bundle 13 个 commit 行为不变（trigger / resolved / reality check / 3 insight 卡片 / banner / 自动弹 sheet / 通知 body）

## 8. 改动文件

**新增（4 个）**：
- `MissingPlusPlus/Models/CooldownActivities.swift` —— `CooldownActivities` enum + `SelfCompassionPhrases` enum
- `MissingPlusPlus/Views/GroundingSheet.swift` —— 5-4-3-2-1 step-by-step
- `MissingPlusPlus/Views/SelfCompassionView.swift` —— 1 句 + 再抽
- `MissingPlusPlus/Views/CooldownSheet.swift` —— 1 条 + 再抽

**修改（5 个）**：
- `MissingPlusPlus/Services/AppPreferences.swift` —— + `@Published cooldownActivities` + `CooldownActivities` Keys
- `MissingPlusPlus/Views/RealityCheckSheet.swift` —— + 3 sub-button + 3 sheet state + 3 sheet modifier
- `MissingPlusPlus/Views/HistoryList.swift` —— HistoryRow + 3 sub-button + 3 closure，HistoryList + 3 sheet state + 3 sheet modifier
- `MissingPlusPlus/Views/NewMissingForm.swift` —— + 5 秒 inline link + 3 sheet state + 3 sheet modifier
- `MissingPlusPlus/Views/SettingsView.swift` —— + `cooldownSection` + frame 660 → 720
- `AGENTS.md` —— + §23 章节

**pbxproj 6 处插入**：
- PBXBuildFile ×4（4 个新 Swift）
- PBXFileReference ×4
- Models group ×1（CooldownActivities）
- Views group ×3（3 个 sub-sheet）
- PBXSourcesBuildPhase ×4（**注意 SECOND `G0000001... Sources` sentinel，那条坑**）

**不改**：
- `Missing.swift` / `Mood.swift` / `Intensity.swift` / `TriggerTag.swift`
- `MissingStore.swift`（不动 mutation API）
- `MenuBarContent.swift` / `PopoverOverflowMenu.swift`
- `StorageService.swift` / `MenuBarIconRenderer.swift`
- `MissingPlusPlusApp.swift`（不动通知 body）
- `StatisticsView.swift`（不动 3 insight 卡片）
- `Info.plist` / `.entitlements`
- `scripts/*`

## 9. 「不要做」（新增）

按 `AGENTS.md §5.1` 已有规则继续生效，这一轮新加：

- 不要把 self-compassion 短语做成用户自定义（v1 curated 7 句，避免鸡汤合集）
- 不要做 timer-based "5 分钟 grounding"（5-4-3-2-1 是手点引导式）
- 不要在 RealityCheckSheet 弹出的同时强制弹 self-soothing（让用户选）
- 不要把 cooldown 活动存到 records 里（preference-level 数据）
- 不要在 popover（`PopoverContent`）里加 3 个 sub-button（popover 是 peek，工具在主窗口用）
- 不要给 sub-sheet 加 "上次的草稿" 恢复（每次 fresh 写，sub-sheet 是 transient self-soothing，不是 journal）
- 不要让 3 个 sub-sheet 自动循环 / 自动重开（用户主动点是 in control，让 auto 重开是反 control）
- 不要把预定义 6 条 cooldown 暴露给用户删（v1 锁死，6 条是"开箱即用"的 fallback）
- 不要在 5-4-3-2-1 step 中加 timer / 自动跳下一步（手点 = 用户 in control，timer = 被动焦虑放大）
- 不要给 CooldownSheet 加 "完成打卡" / "我做了" 按钮（这工具是"想到一个可做的事"，不是 task tracker）

## 10. 风险 / 备注

- **cooldown 只存用户追加（不存全部 9 条）** 是个隐性约定，靠 `CooldownActivities.all(custom:)` 拼接还原。如果以后加 cache / sync，要明确"预定义 6 条是 code-anchored，用户追加是 data-anchored"。
- **3 个 sub-sheet 都是 transient**：state 不持久化（关闭 = 全清），这是有意的（sub-sheet 是 "now"，不是 "history"）。
- **pbxproj patch 风险**：record bundle 已经踩过 1 次（"unrecognized selector"），这次 4 个新 Swift 文件按 §22 记录的流程（SECOND `G0000001... Sources` sentinel 那条坑）走，应该稳。
- **5-4-3-2-1 文案**：v1 走标准感官 5 步；future 迭代可以加"盒式呼吸" / "身体扫描"作为可选 sub-tool，但 v1 不开。
- **inline link 5 秒自动 fade**：用 `DispatchQueue.main.asyncAfter` 不是 SwiftUI 动画的 `withAnimation`，是 v1 简化；future 可改用 `withAnimation` + `transition(.opacity)`。
- **AGENTS.md 章节编号**：当前到 §22，新增章节接 §23。
- **mild submit 路径不弹 RealityCheckSheet**（record bundle 设计）—— bundle 这一轮的 inline link 是给 mild 用的兜底入口，**两条路径不重复**。
