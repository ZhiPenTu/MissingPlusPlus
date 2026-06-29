# Anxious Attachment Record Bundle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 心安日记 加 3 个 Missing 扩展字段（triggerTags / resolvedAt / realityCheck）+ 8 个预定义 trigger 标签 + 1 个新 sheet view + 3 个 insight 统计卡片，让焦虑型依恋用户能看见自己的 trigger 模式、累积"浪会过去"证据、并在浪来时用 DBT Check the Facts 工具自我检验。

**Architecture:** 数据层（Missing + RealityCheck + TriggerTag）→ 业务层（MissingStore 3 方法 + AppPreferences 3 toggle）→ UI 层（NewMissingForm 3 处改动 / HistoryList 卡片扩展 / StatisticsView 3 insight 卡片 / SettingsView section / AppDelegate 通知 body）。所有新字段 Codable 向前兼容（decodeIfPresent + 未知 rawValue 过滤）。TriggerTag 预定义 8 个不开用户自定义。

**Tech Stack:** Swift 5.0 + SwiftUI + AppKit (NSStatusItem) + Combine + UNUserNotificationCenter；macOS 13+ target；Codable 自定义 `init(from:)` / `encode(to:)`；pbxproj 手 patch（按 `AGENTS.md §12`）。

**Spec:** `docs/superpowers/specs/2026-06-26-anxious-attachment-bundle-design.md`

**AGENTS.md 约束（持续生效）：** §1 / §5.1 / §6 / §9 / §10 / §12 / §13 / §16 / §20 / §21 + spec §9 新增 9 条「不要做」

---

## File Structure

**新增（2）：**
- `MissingPlusPlus/Models/TriggerTag.swift` —— 8-case enum + emoji/label/displayString
- `MissingPlusPlus/Views/RealityCheckSheet.swift` —— sheet view，3 TextField + 保存/跳过

**修改（9）：**
- `MissingPlusPlus/Models/Missing.swift` —— + 3 字段 + RealityCheck struct + 自定义 Codable
- `MissingPlusPlus/Services/MissingStore.swift` —— + 3 方法（markResolved/attachRealityCheck/updateTriggers）+ missingStoreDidUpdate
- `MissingPlusPlus/Views/NewMissingForm.swift` —— trigger picker + banner + 自动弹 sheet
- `MissingPlusPlus/Views/HistoryList.swift` —— 卡片 trigger chips / resolved icon / realityCheck tag / 手动按钮
- `MissingPlusPlus/Views/StatisticsView.swift` —— 顶部 3 insight 卡片
- `MissingPlusPlus/Services/AppPreferences.swift` —— + 3 @Published
- `MissingPlusPlus/Views/SettingsView.swift` —— + attachmentBundleSection
- `MissingPlusPlus/MissingPlusPlusApp.swift` 或 `AppDelegate.swift` —— 通知 body 加 trigger
- `AGENTS.md` —— + §22 章节
- `MissingPlusPlus.xcodeproj/project.pbxproj` —— 2 个新 Swift 文件 4 处插入

---

## Task 1: 加 TriggerTag enum（数据层第 1 块）

**Files:**
- Create: `MissingPlusPlus/Models/TriggerTag.swift`

- [ ] **Step 1: 写完整文件**

```swift
import Foundation

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

- [ ] **Step 2: 跑 patch-pbxproj.py 把 TriggerTag.swift 加进工程**

```bash
python3 scripts/patch-pbxproj.py --add TriggerTag.swift
```

（如果该脚本只支持 image 资源，fallback 手 patch pbxproj 4 处插入：PBXBuildFile + PBXFileReference + Models group + PBXSourcesBuildPhase。详见 Task 12 流程。）

- [ ] **Step 3: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MissingPlusPlus/Models/TriggerTag.swift MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(record-bundle): add TriggerTag enum with 8 attachment scenarios"
```

---

## Task 2: 扩 Missing 模型 + 加 RealityCheck struct（数据层第 2 块）

**Files:**
- Modify: `MissingPlusPlus/Models/Missing.swift`（完整重写）

- [ ] **Step 1: 替换整个 Missing.swift**

```swift
import Foundation

struct Missing: Identifiable, Codable, Hashable {
    let id: UUID
    let who: String
    let mood: Mood
    let intensity: Intensity
    let createdAt: Date
    var triggerTags: [TriggerTag]
    var resolvedAt: Date?
    var realityCheck: RealityCheck?

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
    var evidenceFor: String?
    var evidenceAgainst: String?
    var nextAction: String?
    var checkedAt: Date
}
```

- [ ] **Step 2: Build 验证（数据层兼容老 JSON 的关键检查）**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 启动 app，验证老数据仍能读**

读当前 `~/Library/Application Support/MissingPlusPlus/missings.json`（手写一条老格式 JSON 测也行）：

```bash
open -a MissingPlusPlus
# 看菜单栏能开、点开 popover、HistoryList 正常
# 退出 app
killall MissingPlusPlus
```

Expected: 老 JSON 启动不崩；HistoryList 正常列出（每条老记录的 `triggerTags=[]`, `resolvedAt=nil`, `realityCheck=nil`）。

- [ ] **Step 4: Commit**

```bash
git add MissingPlusPlus/Models/Missing.swift
git commit -m "feat(record-bundle): extend Missing with triggerTags/resolvedAt/realityCheck + forward-compat Codable"
```

---

## Task 3: MissingStore 加 3 方法 + 1 notification

**Files:**
- Modify: `MissingPlusPlus/Services/MissingStore.swift`

- [ ] **Step 1: 在 `Notification.Name` extension 加 missingStoreDidUpdate**

找到 `extension Notification.Name { ... }` 这块，追加：

```swift
/// Posted by `MissingStore` when a record is mutated in place
/// (resolved stamped, reality check attached, triggers updated).
/// `userInfo: ["missing": Missing]` carries the updated record.
static let missingStoreDidUpdate = Notification.Name("MissingStoreDidUpdate")
```

- [ ] **Step 2: 在 `final class MissingStore` 内部、最后加 3 方法**

```swift
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
```

- [ ] **Step 3: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MissingPlusPlus/Services/MissingStore.swift
git commit -m "feat(record-bundle): MissingStore.markResolved/attachRealityCheck/updateTriggers + missingStoreDidUpdate"
```

---

## Task 4: AppPreferences 加 3 个 toggle

**Files:**
- Modify: `MissingPlusPlus/Services/AppPreferences.swift`

- [ ] **Step 1: 加 3 个 @Published 属性**

在 `AppPreferences` class 内、现有 `@Published` 旁加：

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
```

- [ ] **Step 2: 扩 Keys enum**

```swift
private enum Keys {
    // 现有 keys
    static let autoPromptRealityCheck = "AutoPromptRealityCheck"
    static let autoPromptResolveLast = "AutoPromptResolveLast"
    static let notificationIncludeTriggers = "NotificationIncludeTriggers"
}
```

- [ ] **Step 3: init 里加 3 行默认值**

```swift
self.autoPromptRealityCheck =
    defaults.object(forKey: Keys.autoPromptRealityCheck) as? Bool ?? true
self.autoPromptResolveLast =
    defaults.object(forKey: Keys.autoPromptResolveLast) as? Bool ?? true
self.notificationIncludeTriggers =
    defaults.object(forKey: Keys.notificationIncludeTriggers) as? Bool ?? true
```

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/Services/AppPreferences.swift
git commit -m "feat(record-bundle): AppPreferences autoPromptRealityCheck/ResolveLast/notificationIncludeTriggers"
```

---

## Task 5: 加 RealityCheckSheet view

**Files:**
- Create: `MissingPlusPlus/Views/RealityCheckSheet.swift`

- [ ] **Step 1: 写完整文件**

```swift
import SwiftUI

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
            VStack(alignment: .leading, spacing: 4) {
                Text("现实检验")
                    .font(.headline)
                Text("DBT 的「Check the Facts」：写下来，情绪就变成可观察的事实。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
                Button("跳过") {
                    onSkip()
                    dismiss()
                }
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
                .disabled(canSave == false)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var canSave: Bool {
        trimmedOrNil(evidenceFor) != nil ||
        trimmedOrNil(evidenceAgainst) != nil ||
        trimmedOrNil(nextAction) != nil
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

- [ ] **Step 2: pbxproj patch（详见 Task 12 流程，单独跑一次）**

- [ ] **Step 3: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MissingPlusPlus/Views/RealityCheckSheet.swift MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(record-bundle): add RealityCheckSheet view (DBT Check the Facts)"
```

---

## Task 6: NewMissingForm 加 trigger picker

**Files:**
- Modify: `MissingPlusPlus/Views/NewMissingForm.swift`

- [ ] **Step 1: 在 @State 区加 selectedTriggers**

找到 NewMissingForm 的 `@State private var ...` 区，追加：

```swift
@State private var selectedTriggers: Set<TriggerTag> = []
```

- [ ] **Step 2: 在表单 ScrollView 主体里、intensity 行之后、submit 按钮之前加 trigger picker 块**

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("触发（多选，可不选）")
        .font(.caption)
        .foregroundColor(.secondary)
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
        ForEach(TriggerTag.allCases) { tag in
            Button {
                if selectedTriggers.contains(tag) {
                    selectedTriggers.remove(tag)
                } else {
                    selectedTriggers.insert(tag)
                }
            } label: {
                Text(tag.displayString)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTriggers.contains(tag)
                                  ? Color.pink.opacity(0.18)
                                  : Color.gray.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedTriggers.contains(tag)
                                    ? Color.pink.opacity(0.6)
                                    : Color.clear, lineWidth: 1)
                    )
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 3: submit handler 里把 selectedTriggers 传进 Missing 构造**

找到 submit handler（约在 `MissingStore.shared.add` 那一行），把 `Missing` 构造补上 `triggerTags: Array(selectedTriggers).sorted { $0.rawValue < $1.rawValue }`：

```swift
let missing = Missing(
    who: who,
    mood: selectedMood,
    intensity: selectedIntensity,
    triggerTags: Array(selectedTriggers).sorted { $0.rawValue < $1.rawValue }
)
MissingStore.shared.add(missing)
```

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 手动验证**

启动 app，录一条 missing，选 2 个 trigger，提交，看 `missings.json`：

```bash
cat ~/Library/Application\ Support/MissingPlusPlus/missings.json | python3 -m json.tool | tail -20
```

Expected: 新记录里有 `"triggerTags": ["alone", "noReply"]`（按 rawValue 排序）

- [ ] **Step 6: Commit**

```bash
git add MissingPlusPlus/Views/NewMissingForm.swift
git commit -m "feat(record-bundle): NewMissingForm trigger picker (8 chips, multi-select)"
```

---

## Task 7: NewMissingForm 加"上一条平复了吗"banner + 自动弹 sheet

**Files:**
- Modify: `MissingPlusPlus/Views/NewMissingForm.swift`

- [ ] **Step 1: 加 @State pendingRealityCheck + inject MissingStore observation**

```swift
@State private var pendingRealityCheck: Missing?
@State private var lastSubmittedMissing: Missing?

// NewMissingForm 顶部 @ObservedObject:
@ObservedObject private var store = MissingStore.shared
```

- [ ] **Step 2: submit handler 里加 2 件事**

```swift
let missing = Missing( ... triggerTags: ... )
MissingStore.shared.add(missing)
lastSubmittedMissing = missing

// 触发 reality check sheet
if missing.intensity == .strong,
   AppPreferences.shared.autoPromptRealityCheck {
    pendingRealityCheck = missing
}
```

- [ ] **Step 3: body 顶部加 sheet modifier + banner**

```swift
// sheet (放在 body 最后，或其他 modifier 旁)
.sheet(item: $pendingRealityCheck) { record in
    RealityCheckSheet(missing: record) { check in
        MissingStore.shared.attachRealityCheck(record, check: check)
    } onSkip: {
        // no-op
    }
}

// banner (在表单 ScrollView 顶部，header 之后)
if let latest = store.sortedItems.first,
   latest.resolvedAt == nil,
   Date().timeIntervalSince(latest.createdAt) > 30 * 60,
   AppPreferences.shared.autoPromptResolveLast
{
    ResolveLastBanner(latest: latest) { response in
        switch response {
        case .yes: store.markResolved(latest)
        case .no, .skip: break
        }
    }
    .padding(.bottom, 6)
}
```

- [ ] **Step 4: 加 ResolveLastBanner 组件（放在 NewMissingForm.swift 文件末尾，private struct）**

```swift
private struct ResolveLastBanner: View {
    enum Response { case yes, no, skip }
    let latest: Missing
    let onResponse: (Response) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("上次想念平复了吗？")
                    .font(.subheadline.weight(.medium))
                Text("对象：\(latest.who) · \(formatRelative(latest.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(spacing: 4) {
                Button("是") { onResponse(.yes) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("否") { onResponse(.no) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("跳过") { onResponse(.skip) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.pink.opacity(0.06))
        )
    }

    private func formatRelative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}
```

- [ ] **Step 5: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 手动验证**

启动 app：
1. 录一条 strong + 任意 trigger，submit → 自动弹 RealityCheckSheet → 跳过
2. 30 分钟后（或者改测试：先 hack `lastSubmittedMissing` 把 `createdAt` 改成 1h 前，或把 grace period 改成 0）打开新建表单 → 顶部出现 banner
3. banner 点"是" → 那条 missing 的 `resolvedAt` 被 stamp，HistoryList 卡片显示"✓ 刚刚"

- [ ] **Step 7: Commit**

```bash
git add MissingPlusPlus/Views/NewMissingForm.swift
git commit -m "feat(record-bundle): NewMissingForm banner (resolve-last 30min grace) + auto sheet (strong intensity)"
```

---

## Task 8: HistoryList 卡片扩展（trigger chips + resolved icon + realityCheck tag + 手动按钮）

**Files:**
- Modify: `MissingPlusPlus/Views/HistoryList.swift`

- [ ] **Step 1: 在卡片 view 主体里按 spec §4.6 顺序插 4 块**

在现有 `who + mood emoji` 行后（保留 intensity dots），按以下顺序插入：

```swift
// 1. trigger chips（只显示选了的）
if !missing.triggerTags.isEmpty {
    HStack(spacing: 4) {
        ForEach(missing.triggerTags.prefix(3)) { tag in
            Text(tag.displayString)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.1))
                .clipShape(Capsule())
        }
        if missing.triggerTags.count > 3 {
            Text("+\(missing.triggerTags.count - 3)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// 2. reality check 折叠 tag
if let rc = missing.realityCheck {
    DisclosureGroup {
        VStack(alignment: .leading, spacing: 4) {
            if let s = rc.evidenceFor { Text("• 证据：\(s)").font(.caption) }
            if let s = rc.evidenceAgainst { Text("• 反对：\(s)").font(.caption) }
            if let s = rc.nextAction { Text("• 接下来：\(s)").font(.caption) }
        }
        .foregroundColor(.secondary)
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.bubble")
            Text("已做现实检验")
        }
        .font(.caption2)
        .foregroundColor(.purple)
    }
}

// 3. "做现实检验" 按钮（仅当无 realityCheck 时显示）
if missing.realityCheck == nil {
    Button {
        pendingRealityCheck = missing
    } label: {
        Label("做现实检验", systemImage: "checkmark.bubble")
            .font(.caption)
    }
    .buttonStyle(.borderless)
    .foregroundColor(.purple)
}
```

- [ ] **Step 2: 卡片右上角加 resolved icon（点击调 markResolved）**

```swift
// 在卡片 HStack 右上角
Button {
    MissingStore.shared.markResolved(missing)
} label: {
    if let resolvedAt = missing.resolvedAt {
        Text("✓ \(formatRelative(resolvedAt))")
            .font(.caption2)
            .foregroundColor(MoodColor.forMood(missing.mood))
    } else {
        Text("○")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}
.buttonStyle(.plain)
```

- [ ] **Step 3: 在 HistoryList 顶部加 @State pendingRealityCheck + sheet modifier**

```swift
@State private var pendingRealityCheck: Missing?

// .sheet(item:) 加在 body 末
.sheet(item: $pendingRealityCheck) { record in
    RealityCheckSheet(missing: record) { check in
        MissingStore.shared.attachRealityCheck(record, check: check)
    } onSkip: { /* no-op */ }
}
```

- [ ] **Step 4: 加 formatRelative 私有 helper（放文件末尾）**

```swift
private func formatRelative(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "刚刚" }
    if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
    if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
    return "\(Int(interval / 86400)) 天前"
}
```

- [ ] **Step 5: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 手动验证**

启动 app：
1. HistoryList 看老 missing → trigger chips 区域空（老数据无 trigger），右上角"○"可点
2. 点"○" → 立刻变"✓ 刚刚"
3. 看新录的 missing（有 trigger）→ trigger chips 显示
4. 看有 realityCheck 的 missing → 折叠 tag 点开有 3 栏内容
5. 看没 realityCheck 的 strong missing → 卡片底部"做现实检验"按钮可点

- [ ] **Step 7: Commit**

```bash
git add MissingPlusPlus/Views/HistoryList.swift
git commit -m "feat(record-bundle): HistoryList card with trigger chips/resolved icon/realityCheck tag/manual button"
```

---

## Task 9: StatisticsView 加 3 insight 卡片

**Files:**
- Modify: `MissingPlusPlus/Views/StatisticsView.swift`

- [ ] **Step 1: 加 3 个计算函数（私有，在 body 之前）**

```swift
private var last30Days: [Missing] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    return items.filter { $0.createdAt >= cutoff }
}

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

private var realityCheckStats: (rate: Double, completed: Int, eligible: Int) {
    let last = last30Days
    let eligible = last.filter { $0.intensity == .strong }.count
    guard eligible > 0 else { return (0, 0, 0) }
    let completed = last.filter { $0.intensity == .strong && $0.realityCheck != nil }.count
    return (Double(completed) / Double(eligible), completed, eligible)
}
```

- [ ] **Step 2: 加 3 个私有 card view（放文件末尾）**

```swift
private struct WaveResolvedCard: View {
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

private struct TopTriggersCard: View {
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

private struct RealityCheckCard: View {
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

- [ ] **Step 3: 在 body 顶部、trend chart 之前插 3 个 card**

```swift
// 假设 StatisticsView body 是 ScrollView { VStack { ... } }
// 在 trend chart 之前：
VStack(spacing: 10) {
    WaveResolvedCard(stats: waveStats)
    TopTriggersCard(triggers: topTriggers)
    RealityCheckCard(stats: realityCheckStats)
}
.padding(.bottom, 10)
```

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 手动验证**

启动 app → 主窗口 → 统计 tab → 看到 3 个 insight 卡片，数字与手算一致。

- [ ] **Step 6: Commit**

```bash
git add MissingPlusPlus/Views/StatisticsView.swift
git commit -m "feat(record-bundle): StatisticsView 3 insight cards (wave resolved / top triggers / reality check)"
```

---

## Task 10: SettingsView 加 attachmentBundleSection

**Files:**
- Modify: `MissingPlusPlus/Views/SettingsView.swift`

- [ ] **Step 1: 加 attachmentBundleSection private view**

在文件末尾（或合适位置）加：

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

- [ ] **Step 2: 在 body 里 menuBarSection 之后插入**

```swift
attachmentBundleSection
```

- [ ] **Step 3: frame 高度从 600 → 660**

找到 `SettingsView` body 顶部的 `.frame(width:height:)`，高度改成 660。

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 手动验证**

启动 app → ⌘, → settings 看到新 section "依恋辅助"，3 个 toggle 都默认开。关 toggle 退出 app 重启仍保留。

- [ ] **Step 6: Commit**

```bash
git add MissingPlusPlus/Views/SettingsView.swift
git commit -m "feat(record-bundle): SettingsView attachment bundle section (3 toggles)"
```

---

## Task 11: 通知 body 加 trigger

**Files:**
- Modify: `MissingPlusPlus/MissingPlusPlusApp.swift` 或 `AppDelegate`（按 spec §4.10）

- [ ] **Step 1: 找到 `postRecordNotification(for:)` 的 body 拼接处**

- [ ] **Step 2: 把 body 拼成 spec §4.10 形式**

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

- [ ] **Step 3: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证**

启动 app，录一条带 2 trigger 的 missing，看 macOS 通知中心。

Expected: body 含"　触发：💬 TA 没及时回 🏠 独处时"

- [ ] **Step 5: Commit**

```bash
git add MissingPlusPlus/MissingPlusPlusApp.swift
git commit -m "feat(record-bundle): notification body include trigger info (opt-in via preference)"
```

---

## Task 12: pbxproj patch 一次性把 TriggerTag + RealityCheckSheet 加进工程

**Files:**
- Modify: `MissingPlusPlus.xcodeproj/project.pbxproj`

- [ ] **Step 1: 试 idempotent patch 脚本**

```bash
ls scripts/patch-pbxproj.py 2>&1
# 看脚本支持的 --add 参数
```

- [ ] **Step 2: 如脚本支持，按 README 跑**

```bash
python3 scripts/patch-pbxproj.py --add-swift MissingPlusPlus/Models/TriggerTag.swift
python3 scripts/patch-pbxproj.py --add-swift MissingPlusPlus/Views/RealityCheckSheet.swift
```

- [ ] **Step 3: 如脚本不支持，手 patch pbxproj 4 处**

参考现有 Swift 文件（`MissingStore.swift` / `StorageService.swift`）的 block，在 pbxproj 4 处插入：

1. `PBXBuildFile` 段加 2 个 file ref
2. `PBXFileReference` 段加 2 个 file entry
3. `Models` group 段加 1 个 `TriggerTag.swift` children
4. `Views` group 段加 1 个 `RealityCheckSheet.swift` children
5. `PBXSourcesBuildPhase` 段加 2 个 file ref

每处用 24-char hex ID（参考 `MissingStore.swift` 的 ID 格式）。

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`（没有 pbxproj 报 missing source 错）

- [ ] **Step 5: 跑 `--force` 防重复**

```bash
python3 scripts/patch-pbxproj.py --force 2>&1
# Expected: "all up to date" 或类似幂等成功
```

- [ ] **Step 6: 单独 commit（因为前几个 task 已经 commit 过新文件但还没 patch 进工程）**

```bash
git add MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "chore(pbxproj): add TriggerTag.swift + RealityCheckSheet.swift to project"
```

---

## Task 13: AGENTS.md 加 §22 章节

**Files:**
- Modify: `AGENTS.md`（在 §21 之后追加）

- [ ] **Step 1: 找到 §21 末尾**

- [ ] **Step 2: 追加 §22 章节**

```markdown
## 22. Anxious Attachment Record Bundle（v1.x）

针对焦虑型依恋人格的"看见 pattern / 累积平复证据 / DBT 落点"扩展。Spec 在 `docs/superpowers/specs/2026-06-26-anxious-attachment-bundle-design.md`，plan 在 `docs/superpowers/plans/2026-06-26-anxious-attachment-bundle.md`。

**新字段**：
- `Missing.triggerTags: [TriggerTag]`（默认 `[]`，8 个预定义 case）
- `Missing.resolvedAt: Date?`（默认 `nil`）
- `Missing.realityCheck: RealityCheck?`（默认 `nil`，含 `evidenceFor/evidenceAgainst/nextAction/checkedAt`）

**JSON 兼容**（关键）：
- `Missing` 自定义 `init(from:)` 用 `decodeIfPresent` + 默认值，老 JSON 自动读为 `[]` / `nil` / `nil`
- `triggerTags` 未知 rawValue（未来加新 case 后老数据里的旧值）→ `compactMap(TriggerTag.init(rawValue:))` 过滤掉，不 crash
- `RealityCheck` 整体 optional，老数据 `realityCheck == nil`（符合"还没做 reality check"）

**TriggerTag 8 个 case**（`MissingPlusPlus/Models/TriggerTag.swift`）：
`noReply` / `silent` / `fight` / `alone` / `sawSomething` / `pastMemory` / `separation` / `comparison`

**3 个 insight 卡片**（统计 tab 顶部）：
1. 「浪都过去了」：过去 30 天平复率 % + 平均平复时长
2. 「你的常见 trigger」：Top 3 + 占比条
3. 「现实检验完成度」：intensity ≥ strong 中做了 realityCheck 的 %

**3 个新 toggle**（settings 依恋辅助 section）：
- `autoPromptRealityCheck`（默认 true）—— intensity == strong submit 后自动弹 sheet
- `autoPromptResolveLast`（默认 true）—— 新建表单顶部"上次想念平复了吗？"banner
- `notificationIncludeTriggers`（默认 true）—— 通知 body 追加 trigger 信息

**Banner 30 分钟 grace period**：`timeIntervalSince(latest.createdAt) > 30 * 60` 才显示，避免"刚提交就被问"的 awkwardness。

**RealityCheckSheet 行为**：
- 自动弹：intensity == strong + setting 开
- 手动入口：HistoryList 卡片"做现实检验"按钮
- 跳过无副作用
- 全空 → 保存按钮 disabled
- 一旦写了 `realityCheck` 不再弹

**`MissingStore` 3 方法 + 1 notification**：
- `markResolved(_:at:)` / `attachRealityCheck(_:check:)` / `updateTriggers(_:tags:)`
- `Notification.Name.missingStoreDidUpdate`（和 `missingStoreDidAdd` 分开）

**「不要做」（这一轮新加）**：
- 不要把 trigger 标签做成用户可自定义（v1 预定义 8 个）
- 不要在已 resolved 的 record 上再弹 reality check sheet
- 不要在 `MissingStore` 里直接读 `AppPreferences`
- 不要把 `triggerTags` / `resolvedAt` / `realityCheck` 写进 `note` 字段
- 不要做"重新弹 reality check"按钮
- 不要做 trigger 用户自定义增删 UI
- 不要在 popover（`PopoverContent`）里加 trigger picker
- 不要把 3 个 insight 卡片的数字"凑好看"
- 不要把 banner 的 30 分钟 grace period 缩到 < 10 分钟
- 不要给 `RealityCheckSheet` 加"上次的草稿"
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): §22 anxious attachment record bundle"
```

---

## Task 14: 最终验证（Debug + Release + JSON 兼容 + 回归）

**Files:** 无（验证步骤）

- [ ] **Step 1: Debug build**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Release build**

```bash
xcodebuild -configuration Release -scheme MissingPlusPlus build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 删 JSON 测 empty state**

```bash
rm -f ~/Library/Application\ Support/MissingPlusPlus/missings.json
open -a MissingPlusPlus
```

Expected: 启动正常，HistoryList 显示 empty state（"还没有记录 / 想念的时候就来记一笔吧"）。

- [ ] **Step 4: 手写老 JSON 测兼容**

```bash
cat > ~/Library/Application\ Support/MissingPlusPlus/missings.json << 'JSON_EOF'
{
  "items": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "who": "苏苏",
      "mood": "longing",
      "intensity": "strong",
      "createdAt": 700000000.0
    }
  ]
}
JSON_EOF
killall MissingPlusPlus
open -a MissingPlusPlus
```

Expected: 启动不崩；HistoryList 列出"苏苏"那条；trigger chips 空（老数据无）；resolved icon 是"○"；没 realityCheck tag；没"做现实检验"按钮外露（其实有，因为老数据也没 realityCheck；这条 OK，v1 行为）。

- [ ] **Step 5: 测未知 trigger rawValue 过滤**

```bash
cat > ~/Library/Application\ Support/MissingPlusPlus/missings.json << 'JSON_EOF'
{
  "items": [
    {
      "id": "22222222-2222-2222-2222-222222222222",
      "who": "TA",
      "mood": "sad",
      "intensity": "mild",
      "createdAt": 700000000.0,
      "triggerTags": ["noReply", "DELETED_FUTURE_CASE"]
    }
  ]
}
JSON_EOF
killall MissingPlusPlus
open -a MissingPlusPlus
```

Expected: 启动不崩；该条 missing 的 trigger chips 只显示"💬 TA 没及时回"，"DELETED_FUTURE_CASE" 被过滤。

- [ ] **Step 6: 完整流程测（强 intensity 路径）**

1. 删 missings.json
2. 启动 app
3. 录一条 intensity=strong + 2 trigger 的 missing
4. 提交 → RealityCheckSheet 自动弹 → 填 evidenceFor + 保存
5. HistoryList 卡片看到 trigger chips + "📋 已做现实检验" tag
6. 点卡片右上角"○" → 变"✓ 刚刚"
7. 通知 body 应含"　触发：..."

- [ ] **Step 7: 回归防坑**

- [ ] 菜单栏 `button.title = mood.emoji` 不变
- [ ] popover 仍走 `PopoverContent`（stat + history tab，不含 form）
- [ ] 主窗口 3 tab（新建 / 统计 / 历史）
- [ ] ⌥M / Dock 入口行为不变
- [ ] popover click bug 修复仍生效（不闪关）

- [ ] **Step 8: 打包验证**

```bash
bash scripts/build-dmg.sh 2>&1 | tail -30
```

Expected: `dist/MissingPlusPlus-1.0.dmg` 生成（Xcode 26 限制：仅 macOS 26+ 能跑，详见 AGENTS.md §6）。

- [ ] **Step 9: 没 commit 的 final commit（如有）**

```bash
git status
# 任何未 commit 的改动
git add ...
git commit -m "chore: final cleanup after record-bundle"
```
