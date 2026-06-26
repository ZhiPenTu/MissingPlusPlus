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
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                Text("思念计数器")
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
