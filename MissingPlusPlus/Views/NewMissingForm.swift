import SwiftUI

struct NewMissingForm: View {
    @ObservedObject var store: MissingStore
    // 服务主窗口 "新建" tab (MenuBarContent) — 状态栏 1-click 记录
    // 走 AppDelegate.buildStatusMenu 里的 NSMenu，不复用本组件。
    @State private var who: String = ""
    @State private var mood: Mood = .happy
    @State private var intensity: Intensity = .mild
    @State private var isSubmitting = false
    /// v1.x anxious-attachment bundle: 当前选中的 trigger tags。空 = 没选。
    /// intensity 0/1 也允许选 —— 低强度想念也有 context。
    @State private var selectedTriggers: Set<TriggerTag> = []
    /// Submit 后若 intensity == strong + setting 开，置这个 → 弹 sheet。
    /// sheet dismiss 时 SwiftUI 自动把它设回 nil，下次提交新一条才再次触发。
    @State private var pendingRealityCheck: Missing?
    /// v1.x self-soothing: mild submit 后 5 秒显示 "想冷静一下？" inline link。
    @State private var showSoothingLink: Bool = false
    @State private var pendingGrounding = false
    @State private var pendingCompassion: Missing?
    /// 「致 TA 的话」 sheet 触发器。和 pendingCompassion 同样的 pattern。
    @State private var pendingLetter: Missing?
    @State private var pendingWorthAffirmation: Missing?
    @State private var pendingCooldown = false
    /// 刚提交的那一条 missing,用于让 "想冷静一下" 的 inline link 把 context 传给
    /// SelfCompassionView / LetterToThemView。Submit 时设置,新一条 submit 覆盖。
    @State private var latestSubmitted: Missing?

    private var trimmedWho: String {
        who.trimmingCharacters(in: .whitespaces)
    }

    /// Submit is always allowed — an empty `who` falls back to a placeholder
    /// so the form doesn't sit in a perpetually-disabled state. (The original
    /// "must type a name first" rule was hostile for the most common case
    /// of wanting to log a quick mood with no subject in mind.)
    private var canSubmit: Bool {
        !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.10), Color.pink.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Divider()

            ScrollView {
                formFields
                    .padding(16)
            }

            // Spacer 撑中间空 — 字段少时不会让 ScrollView 区域空出大块
            // (ScrollView fill maxHeight 会让背景色铺满中间，看出"空")
            Spacer(minLength: 0)

            Divider()

            actionButton
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $pendingRealityCheck) { record in
            RealityCheckSheet(missing: record) { check in
                store.attachRealityCheck(record, check: check)
            } onSkip: {
                // no-op — 用户主动跳过，无副作用
            }
        }
        .sheet(isPresented: $pendingGrounding) { GroundingSheet() }
        .sheet(item: $pendingCompassion) { record in SelfCompassionView(missing: record) }
        .sheet(item: $pendingLetter) { record in LetterToThemView(missing: record) }
        .sheet(item: $pendingWorthAffirmation) { _ in WorthAffirmationView() }
        .sheet(isPresented: $pendingCooldown) { CooldownSheet(prefs: AppPreferences.shared) }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showSoothingLink {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.pink)
                    Text("想冷静一下？")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        pendingGrounding = true
                    } label: {
                        Image(systemName: "eye")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .help("5-4-3-2-1 grounding")
                    Button {
                        pendingCompassion = latestSubmitted
                    } label: {
                        Image(systemName: "heart.text.square")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.pink)
                    .help("自我同情")
                    Button {
                        pendingWorthAffirmation = latestSubmitted
                    } label: {
                        Image(systemName: "heart.circle.fill")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.green)
                    .help("自己值得被爱")
                    Button {
                        pendingCooldown = true
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.purple)
                    .help("分散注意力")
                    Button {
                        pendingLetter = latestSubmitted
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.indigo)
                    .help("给 TA 写封信")
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.pink.opacity(0.06))
                )
                .transition(.opacity)
            }
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
            }
            WhoField(who: $who, suggestions: store.knownWhos)
            VStack(alignment: .leading, spacing: 6) {
                Text("心情")
                    .font(.caption)
                    .foregroundColor(.secondary)
                MoodPicker(selection: $mood)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("程度")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("程度", selection: $intensity) {
                    ForEach(Intensity.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            triggerPickerView
        }
    }

    /// 8 个 attachment 场景 chip picker，多选，可不选。
    /// 1 行 4 个，2 行排开；3 列 + 1 列的 fallback 通过 LazyVGrid 自动 wrap。
    private var triggerPickerView: some View {
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
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color.pink.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.pink.opacity(0.25), radius: 4, y: 1)
                Image(systemName: "heart.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("心安日记")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("已记录 \(store.items.count) 个时刻")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let latest = store.sortedItems.first {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(latest.mood.emoji)
                            .font(.caption)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - action button

    private var actionButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSubmitting ? "记录中…" : (trimmedWho.isEmpty ? "记录（未指定对象）" : "记录这一刻"))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.pink)
        .disabled(!canSubmit)
    }

    // MARK: - submit

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let entry = Missing(
            who: trimmedWho.isEmpty ? "TA" : trimmedWho,
            mood: mood,
            intensity: intensity,
            triggerTags: Array(selectedTriggers).sorted { $0.rawValue < $1.rawValue }
        )
        store.add(entry)
        latestSubmitted = entry

        // v1.x: intensity == strong + setting 开 → 弹 RealityCheckSheet。
        // 一旦弹了（pendingRealityCheck 被 set），sheet dismiss 时 SwiftUI
        // 会把它设回 nil，下次提交新一条才再次触发（per-record 一次性）。
        if entry.intensity == .strong,
           AppPreferences.shared.autoPromptRealityCheck {
            pendingRealityCheck = entry
        } else {
            // mild 路径不弹 RealityCheckSheet，给一个 inline "想冷静一下？" 链接
            // 5 秒后自动 fade
            showSoothingLink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                showSoothingLink = false
            }
        }

        // Reset form for the next entry; keep the mood/intensity since
        // people usually log several in a row at the same emotional state.
        who = ""
        mood = .happy
        intensity = .mild
        selectedTriggers = []
        isSubmitting = false
    }
}

private struct WhoField: View {
    @Binding var who: String
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("对象")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("想念 谁?", text: $who)
                .textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) { who = name }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

private struct MoodPicker: View {
    @Binding var selection: Mood

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Mood.allCases) { mood in
                Button {
                    selection = mood
                } label: {
                    Text(mood.emoji)
                        .font(.title2)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == mood
                                      ? Color.pink.opacity(0.18)
                                      : Color.gray.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selection == mood
                                        ? Color.pink
                                        : Color.gray.opacity(0.18),
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(mood.label)
            }
        }
    }
}


// MARK: - 上次想念平复了吗 banner

/// 30 分钟 grace period 避免"刚提交就被问"。3 按钮: 是(stamp)/否(保持)/跳过。
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
                    .tint(.pink)
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
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return "\(Int(interval / 86400)) 天前"
    }
}
