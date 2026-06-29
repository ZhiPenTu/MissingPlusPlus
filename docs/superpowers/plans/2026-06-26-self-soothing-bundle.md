# Self-Soothing Bundle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 给 心安日记 加 3 个 self-soothing sub-sheet（5-4-3-2-1 grounding / self-compassion / cooldown activities），让焦虑型用户在浪来时用 30 秒手点引导走出 emotion flooding。

**Architecture:** 3 个新 view（GroundingSheet / SelfCompassionView / CooldownSheet）+ 1 个新 model（CooldownActivities + SelfCompassionPhrases enums）+ AppPreferences 加 1 个 `@Published cooldownActivities`。3 个 sub-sheet 都用 `@Environment(\.dismiss)` + `.sheet(isPresented:)` 模式。3 个入口：RealityCheckSheet 底部 / HistoryList 卡片底部 / NewMissingForm 5 秒 inline link。

**Tech Stack:** Swift 5.0 + SwiftUI + Combine + AppKit；macOS 13+ target；UserDefaults 存 cooldown 用户追加项；pbxproj 手 patch（按 `AGENTS.md §22` 记录的 SECOND `G0000001... Sources` sentinel 那条坑）。

**Spec:** `docs/superpowers/specs/2026-06-26-self-soothing-bundle-design.md`

**AGENTS.md 约束（持续生效）：** §1 / §5.1 / §6 / §9 / §10 / §12 / §13 / §16 / §20 / §22 + spec §9 新增 10 条「不要做」

---

## File Structure

**新增（4）：**
- `MissingPlusPlus/Models/CooldownActivities.swift` —— `CooldownActivities` enum (6 defaults) + `SelfCompassionPhrases` enum (7 phrases)
- `MissingPlusPlus/Views/GroundingSheet.swift` —— 5-4-3-2-1 step-by-step
- `MissingPlusPlus/Views/SelfCompassionView.swift` —— 1 句 + 再抽
- `MissingPlusPlus/Views/CooldownSheet.swift` —— 1 条 + 再抽

**修改（5）：**
- `MissingPlusPlus/Services/AppPreferences.swift` —— + `cooldownActivities: [String]` + `Keys.cooldownActivities`
- `MissingPlusPlus/Views/RealityCheckSheet.swift` —— + 3 sub-button + 3 sheet state + 3 sheet modifier
- `MissingPlusPlus/Views/HistoryList.swift` —— HistoryRow + 3 sub-button + 3 closure，HistoryList + 3 sheet state + 3 sheet modifier
- `MissingPlusPlus/Views/NewMissingForm.swift` —— + 5 秒 inline link + 3 sheet state + 3 sheet modifier
- `MissingPlusPlus/Views/SettingsView.swift` —— + `cooldownSection` + frame 660 → 720
- `AGENTS.md` —— + §23 章节

---

## Task 1: 新增 `Models/CooldownActivities.swift`

**Files:**
- Create: `MissingPlusPlus/Models/CooldownActivities.swift`

- [ ] **Step 1: 写完整文件**

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
```

- [ ] **Step 2: Build 验证**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **` (CooldownActivities 没在任何地方引用，build 不会 fail 但也没意义;不过先验证编译 OK)

- [ ] **Step 3: pbxproj patch**

按 §22 流程手 patch（SECOND `G0000001... Sources` sentinel 那条坑）。

```bash
python3 << 'PYEOF'
import re
from pathlib import Path
p = Path("/Users/tuzhipeng/missing++/MissingPlusPlus.xcodeproj/project.pbxproj")
text = p.read_text()
existing = set(re.findall(r"[AB][0-9A-F]{20,24}", text))
a_max = max((int(i[1:], 16) for i in existing if i.startswith("A") and len(i) == 24), default=0)
b_max = max((int(i[1:], 16) for i in existing if i.startswith("B") and len(i) == 24), default=0)
build_id = "A" + format(a_max + 1, "022X")[:23]
ref_id = "B" + format(b_max + 1, "022X")[:23]
print(f"build_id={build_id}, ref_id={ref_id}")

# PBXBuildFile
text = text.replace("/* End PBXBuildFile section */",
    f"\t\t{build_id} /* CooldownActivities.swift in Sources */ = "
    f"{{isa = PBXBuildFile; fileRef = {ref_id} /* CooldownActivities.swift */; }};\n"
    f"/* End PBXBuildFile section */")
# PBXFileReference
text = text.replace("/* End PBXFileReference section */",
    f"\t\t{ref_id} /* CooldownActivities.swift */ = "
    f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
    f"path = CooldownActivities.swift; sourceTree = \"<group>\"; }};\n"
    f"/* End PBXFileReference section */")
# Models group
group_sentinel = "D0000004000000000000A001 /* Models */ = {"
start = text.find(group_sentinel)
group_end = text.find("\n\t\t};\n", start)
group_block = text[start:group_end]
children_open = group_block.find("children = (") + len("children = (")
children_close = group_block.find("\n\t\t\t);", children_open)
children_block = group_block[children_open:children_close]
new_child = f"\n\t\t\t{ref_id} /* CooldownActivities.swift */,"
new_group_block = group_block[:children_open] + children_block + new_child + group_block[children_close:]
text = text[:start] + new_group_block + text[group_end:]
# PBXSourcesBuildPhase — SECOND occurrence
first_pos = text.find("G0000001000000000000A001 /* Sources */")
second_pos = text.find("G0000001000000000000A001 /* Sources */", first_pos + 1)
src_end = text.find("\n\t\t};\n", second_pos)
src_block = text[second_pos:src_end]
files_open = src_block.find("files = (") + len("files = (")
files_close = src_block.find("\n\t\t\t);", files_open)
files_block = src_block[files_open:files_close]
new_entry = f"\n\t\t\t{build_id} /* CooldownActivities.swift in Sources */,"
new_files = files_block + new_entry
new_src_block = src_block[:files_open] + new_files + src_block[files_close:]
text = text[:second_pos] + new_src_block + text[src_end:]

p.write_text(text)
print("PATCHED")
PYEOF
plutil -lint MissingPlusPlus.xcodeproj/project.pbxproj
```

Expected: `OK` + `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MissingPlusPlus/Models/CooldownActivities.swift MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(self-soothing): add CooldownActivities (6 defaults) + SelfCompassionPhrases (7 curated)"
```

---

## Task 2: 新增 `Views/GroundingSheet.swift`

**Files:**
- Create: `MissingPlusPlus/Views/GroundingSheet.swift`

- [ ] **Step 1: 写完整文件** (按 spec §4.3)

```swift
import SwiftUI

struct GroundingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int = 0

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

- [ ] **Step 2: pbxproj patch** (Views group + Sources phase)

```bash
python3 << 'PYEOF'
import re
from pathlib import Path
p = Path("/Users/tuzhipeng/missing++/MissingPlusPlus.xcodeproj/project.pbxproj")
text = p.read_text()
existing = set(re.findall(r"[AB][0-9A-F]{20,24}", text))
a_max = max((int(i[1:], 16) for i in existing if i.startswith("A") and len(i) == 24), default=0)
b_max = max((int(i[1:], 16) for i in existing if i.startswith("B") and len(i) == 24), default=0)
build_id = "A" + format(a_max + 1, "022X")[:23]
ref_id = "B" + format(b_max + 1, "022X")[:23]
print(f"build_id={build_id}, ref_id={ref_id}")

text = text.replace("/* End PBXBuildFile section */",
    f"\t\t{build_id} /* GroundingSheet.swift in Sources */ = "
    f"{{isa = PBXBuildFile; fileRef = {ref_id} /* GroundingSheet.swift */; }};\n"
    f"/* End PBXBuildFile section */")
text = text.replace("/* End PBXFileReference section */",
    f"\t\t{ref_id} /* GroundingSheet.swift */ = "
    f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
    f"path = GroundingSheet.swift; sourceTree = \"<group>\"; }};\n"
    f"/* End PBXFileReference section */")
group_sentinel = "D0000006000000000000A001 /* Views */ = {"
start = text.find(group_sentinel)
group_end = text.find("\n\t\t};\n", start)
group_block = text[start:group_end]
children_open = group_block.find("children = (") + len("children = (")
children_close = group_block.find("\n\t\t\t);", children_open)
children_block = group_block[children_open:children_close]
new_child = f"\n\t\t\t{ref_id} /* GroundingSheet.swift */,"
new_group_block = group_block[:children_open] + children_block + new_child + group_block[children_close:]
text = text[:start] + new_group_block + text[group_end:]
first_pos = text.find("G0000001000000000000A001 /* Sources */")
second_pos = text.find("G0000001000000000000A001 /* Sources */", first_pos + 1)
src_end = text.find("\n\t\t};\n", second_pos)
src_block = text[second_pos:src_end]
files_open = src_block.find("files = (") + len("files = (")
files_close = src_block.find("\n\t\t\t);", files_open)
files_block = src_block[files_open:files_close]
new_entry = f"\n\t\t\t{build_id} /* GroundingSheet.swift in Sources */,"
new_files = files_block + new_entry
new_src_block = src_block[:files_open] + new_files + src_block[files_close:]
text = text[:second_pos] + new_src_block + text[src_end:]
p.write_text(text)
print("PATCHED")
PYEOF
plutil -lint MissingPlusPlus.xcodeproj/project.pbxproj
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MissingPlusPlus/Views/GroundingSheet.swift MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(self-soothing): add GroundingSheet (5-4-3-2-1 step-by-step)"
```

---

## Task 3: 新增 `Views/SelfCompassionView.swift`

**Files:**
- Create: `MissingPlusPlus/Views/SelfCompassionView.swift`

- [ ] **Step 1: 写完整文件** (按 spec §4.4)

```swift
import SwiftUI

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

- [ ] **Step 2: pbxproj patch** (同 Task 2 流程,view 名 SelfCompassionView)

- [ ] **Step 3: Build + Commit**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
git add MissingPlusPlus/Views/SelfCompassionView.swift MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(self-soothing): add SelfCompassionView (1 phrase + re-roll, 7 curated)"
```

---

## Task 4: 新增 `Views/CooldownSheet.swift`

**Files:**
- Create: `MissingPlusPlus/Views/CooldownSheet.swift`

- [ ] **Step 1: 写完整文件** (按 spec §4.5)

```swift
import SwiftUI

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

- [ ] **Step 2: pbxproj patch + build + commit**

```bash
# 同样 pbxproj patch 流程
git add MissingPlusPlus/Views/CooldownSheet.swift MissingPlusPlus.xcodeproj/project.pbxproj
git commit -m "feat(self-soothing): add CooldownSheet (1 activity + re-roll)"
```

---

## Task 5: `AppPreferences` 加 `cooldownActivities`

**Files:**
- Modify: `MissingPlusPlus/Services/AppPreferences.swift`

- [ ] **Step 1: 加 @Published cooldownActivities + Keys**

```swift
@Published var cooldownActivities: [String] {
    didSet {
        defaults.set(cooldownActivities, forKey: Keys.cooldownActivities)
    }
}
```

Keys enum 加 `static let cooldownActivities = "CooldownActivities"`

init 加：
```swift
self.cooldownActivities =
    defaults.stringArray(forKey: Keys.cooldownActivities) ?? []
```

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
git add MissingPlusPlus/Services/AppPreferences.swift
git commit -m "feat(self-soothing): AppPreferences.cooldownActivities (user-added only, defaults live in code)"
```

---

## Task 6: `RealityCheckSheet` 加 3 sub-button

**Files:**
- Modify: `MissingPlusPlus/Views/RealityCheckSheet.swift`

- [ ] **Step 1: 加 3 @State 触发 sheet**

```swift
@State private var pendingGrounding = false
@State private var pendingCompassion = false
@State private var pendingCooldown = false
```

- [ ] **Step 2: 在 "保存 / 跳过" 那行下面加 sub-button 行**

(按 spec §4.6)

- [ ] **Step 3: 加 3 .sheet modifier 在 body 末尾**

```swift
.sheet(isPresented: $pendingGrounding) { GroundingSheet() }
.sheet(isPresented: $pendingCompassion) { SelfCompassionView() }
.sheet(isPresented: $pendingCooldown) { CooldownSheet(prefs: AppPreferences.shared) }
```

- [ ] **Step 4: Build + commit**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
git add MissingPlusPlus/Views/RealityCheckSheet.swift
git commit -m "feat(self-soothing): RealityCheckSheet 3 sub-buttons (grounding/compassion/cooldown)"
```

---

## Task 7: `HistoryList` 卡片 + 3 sub-button

**Files:**
- Modify: `MissingPlusPlus/Views/HistoryList.swift`

- [ ] **Step 1: HistoryList 加 3 @State + 3 .sheet modifier**

```swift
@State private var pendingGrounding: Missing?
@State private var pendingCompassion: Missing?
@State private var pendingCooldown: Missing?

// body 末尾:
.sheet(item: $pendingGrounding) { _ in GroundingSheet() }
.sheet(item: $pendingCompassion) { _ in SelfCompassionView() }
.sheet(item: $pendingCooldown) { _ in CooldownSheet(prefs: AppPreferences.shared) }
```

- [ ] **Step 2: HistoryRow 加 3 closure + 3 sub-button**

HistoryRow 定义加 3 closure:
```swift
let onRequestGrounding: () -> Void
let onRequestCompassion: () -> Void
let onRequestCooldown: () -> Void
```

ForEach 传 3 closure:
```swift
HistoryRow(
    item: item,
    onResolve: { store.markResolved(item) },
    onRequestCheck: { pendingRealityCheck = item },
    onRequestGrounding: { pendingGrounding = item },
    onRequestCompassion: { pendingCompassion = item },
    onRequestCooldown: { pendingCooldown = item }
)
```

HistoryRow 内部在"做现实检验"按钮旁加 3 sub-button (按 spec §4.7)

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
git add MissingPlusPlus/Views/HistoryList.swift
git commit -m "feat(self-soothing): HistoryList card 3 sub-buttons (grounding/compassion/cooldown)"
```

---

## Task 8: `NewMissingForm` 加 5 秒 inline link

**Files:**
- Modify: `MissingPlusPlus/Views/NewMissingForm.swift`

- [ ] **Step 1: 加 @State**

```swift
@State private var showSoothingLink: Bool = false
@State private var pendingGrounding = false
@State private var pendingCompassion = false
@State private var pendingCooldown = false
```

- [ ] **Step 2: submit handler 加 mild 路径 + 5 秒 fade**

```swift
if entry.intensity != .strong {
    showSoothingLink = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        showSoothingLink = false
    }
}
```

- [ ] **Step 3: body 加 inline link + 3 .sheet modifier**

(按 spec §4.8)

- [ ] **Step 4: Build + commit**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
git add MissingPlusPlus/Views/NewMissingForm.swift
git commit -m "feat(self-soothing): NewMissingForm 5s inline '想冷静一下?' link for mild path"
```

---

## Task 9: `SettingsView` 加 `cooldownSection` + frame 660→720

**Files:**
- Modify: `MissingPlusPlus/Views/SettingsView.swift`

- [ ] **Step 1: 加 @State + helper methods + section view**

(按 spec §4.9)

- [ ] **Step 2: body 插入 + frame 高度改**

```swift
storageSection
menuBarSection
attachmentBundleSection
cooldownSection  // 新增
dataSection
aboutSection
```

```swift
.frame(width: 480, height: 720)  // 660 → 720
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
git add MissingPlusPlus/Views/SettingsView.swift
git commit -m "feat(self-soothing): SettingsView cooldownSection (add/remove user activities)"
```

---

## Task 10: `AGENTS.md` §23 章节

**Files:**
- Modify: `AGENTS.md` (在 §22 后追加)

- [ ] **Step 1: 追加 §23 章节**

```markdown
## 23. Self-Soothing Bundle（v1.x 第二轮）

针对焦虑型依恋人格的"浪来时接住你"—— body 层 self-soothing 工具，和 §22 认知层（record）形成完整链路。Spec 在 `docs/superpowers/specs/2026-06-26-self-soothing-bundle-design.md`，plan 在 `docs/superpowers/plans/2026-06-26-self-soothing-bundle.md`。

**3 个 sub-sheet 工具**：
- `GroundingSheet` —— 5-4-3-2-1 sensory grounding，step-by-step 手点引导
- `SelfCompassionView` —— 1 句 curated 短语 + "再抽一句"
- `CooldownSheet` —— 1 条 cooldown 活动 + "再抽一个"

**3 个入口**：
- **A 路径**（强 nudge）：`RealityCheckSheet` 底部 3 sub-button，强 intensity 弹 RealityCheckSheet 后路径最短
- **B 路径**（事后回访）：`HistoryList` 卡片底部 3 sub-button，mild 也能用
- **mild 兜底**：`NewMissingForm` submit 后 5 秒 inline "想冷静一下？" link（mild 不弹 RealityCheckSheet 的兜底）

**数据层**：
- `cooldownActivities: [String]` in AppPreferences（**只存用户追加的**，预定义 6 条 hardcode 在 `CooldownActivities.defaults`）
- 渲染时 `CooldownActivities.all(custom:)` 拼接
- UserDefaults 缺字段 fallback 到 `[]` + 6 条预定义

**Self-compassion 池子**：7 句 curated（Kristin Neff 风格：mindfulness + common humanity + self-kindness），v1 hardcode 不让用户改。

**预定义 6 条 cooldown**：喝杯水 / 出门走 5 分钟 / 深呼吸 10 次 / 听一首喜欢的歌 / 给朋友发条消息 / 抱抱毛绒玩具 / 家里的宠物。🔒 锁死，用户不能删，只能 append 自己的。

**pbxproj patch**：4 个新 Swift 文件（CooldownActivities / GroundingSheet / SelfCompassionView / CooldownSheet）走 §22 流程。**继续警惕 SECOND `G0000001... Sources` sentinel 那条坑**（PBXNativeTarget.buildPhases 是第一个 occurrence，PBXSourcesBuildPhase files 才是第二个，要写对地方）。

**「不要做」**（这一轮新加）：
- 不要把 self-compassion 短语做成用户自定义（v1 curated 7 句，避免鸡汤合集）
- 不要做 timer-based "5 分钟 grounding"（5-4-3-2-1 是手点引导式）
- 不要在 RealityCheckSheet 弹出的同时强制弹 self-soothing（让用户选）
- 不要把 cooldown 活动存到 records 里（preference-level 数据）
- 不要在 popover（`PopoverContent`）里加 3 sub-button（popover 是 peek，工具在主窗口用）
- 不要给 sub-sheet 加"上次的草稿"恢复（每次 fresh 写，sub-sheet 是 transient self-soothing）
- 不要让 3 个 sub-sheet 自动循环 / 自动重开（用户主动点是 in control）
- 不要把预定义 6 条 cooldown 暴露给用户删（v1 锁死，6 条是开箱即用 fallback）
- 不要在 5-4-3-2-1 step 中加 timer / 自动跳下一步（手点 = 用户 in control）
- 不要给 CooldownSheet 加"完成打卡" / "我做了"按钮（这工具是"想到一个可做的事"，不是 task tracker）
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): §23 self-soothing bundle"
```

---

## Task 11: 最终验证

- [ ] **Step 1: Debug build**

```bash
xcodebuild -configuration Debug -scheme MissingPlusPlus build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Release build**

```bash
xcodebuild -configuration Release -scheme MissingPlusPlus build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 启动 app 跑通**

```bash
killall MissingPlusPlus 2>/dev/null
APP="/Users/tuzhipeng/Library/Developer/Xcode/DerivedData/MissingPlusPlus-gtavjnkeybhdnnfysnkcqzgorbra/Build/Products/Debug/MissingPlusPlus.app"
"$APP/Contents/MacOS/MissingPlusPlus" > /tmp/mpp-soothing.log 2>&1 &
sleep 4
ps aux | grep MissingPlusPlus | grep -v grep | head -1
killall MissingPlusPlus
```

Expected: 启动不崩，pid 存活 4s+。

- [ ] **Step 4: UserDefaults 缺字段测试**

清掉 UserDefaults 测试 fallback 路径（开发者设置里清"CooldownActivities" key 即可，或用 `defaults delete com.tuzhipeng.MissingPlusPlus CooldownActivities`）。

启动 app → ⌘, → cooldown section 应该显示 6 条预定义。

- [ ] **Step 5: 回归防坑**

- [ ] popover 仍 2 tab（stat / history）
- [ ] 主窗口 3 tab（新建 / 统计 / 历史）
- [ ] 菜单栏 `button.title = mood.emoji` + 5 mood 染色 + auto-fade 不变
- [ ] Record bundle 13 个 commit 行为不变（trigger / resolved / reality check / 3 insight 卡片 / banner / 自动弹 sheet / 通知 body）

- [ ] **Step 6: 任何 final commit**

```bash
git status
# 任何未 commit 的改动
git add ...
git commit -m "chore: final cleanup after self-soothing bundle"
```
