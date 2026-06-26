import SwiftUI

enum PopoverTab: String, CaseIterable, Identifiable {
    case newEntry = "新建"
    case stats = "统计"
    case history = "历史"
    var id: String { rawValue }
}

/// The Dock-opened "real" app window content. Has the full record form
/// (with the "记录这一刻" submit button), plus stats + history tabs. This
/// is the canonical place to *do* things.
///
/// The status-bar popover is intentionally NOT this view — it routes
/// through `PopoverContent` (below), which is read-only and points the
/// user back here when they want to record a new entry.
struct MenuBarContent: View {
    @ObservedObject var store: MissingStore
    @State private var tab: PopoverTab = .newEntry

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Group {
                switch tab {
                case .newEntry:
                    // fill maxHeight — form 顶部对齐 tab bar，action button
                    // 贴主窗口底，ScrollView 撑中间（字段多时能滚）
                    NewMissingForm(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                case .stats:
                    StatisticsView(store: store)
                        .background(Color(NSColor.windowBackgroundColor))
                case .history:
                    HistoryList(store: store)
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
            // 顶部对齐 — 不 fill maxHeight，否则 NewMissingForm 居中
            // 渲染（Group 默认 .center 对齐），tab bar 下方留 164pt 空
            // 看起来"主窗口布局乱"
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 360, height: 720)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(PopoverTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == item ? Color.pink.opacity(0.18) : Color.clear)
                        )
                        .foregroundColor(tab == item ? .pink : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        // PopoverOverflowMenu 删了 — 关于 / 设置 (⌘,) / 退出 (⌘Q)
        // 走 SwiftUI app menu / Commands / Settings scene, 不会再跟
        // form 头部重叠。
        .padding(.trailing, 4)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

/// The status-bar popover's content. **Quick-record entry** — 直接点开
/// 就能新建一条思念，统计/历史在主窗口 (Dock / ⌥M / "在主窗口查看" 菜单)
/// 里看。
///
/// 设计意图：
///   * popover 是"快速记一笔" — 不需要切 tab，不需要看历史，开 popover
///     就提交，提交完关掉
///   * 统计 / 历史是回看动作，回看应该去主窗口（完整 title bar + 流量
///     更适合浏览），不是 peek 场景
///   * "..." 菜单保留 "在主窗口查看" 入口 (PopoverOverflowMenu 的 Open
///     Main Window action)
struct PopoverContent: View {
    @ObservedObject var store: MissingStore
    @ObservedObject var prefs = AppPreferences.shared
    let onOpenMainWindow: () -> Void

    @State private var who: String = ""
    @State private var mood: Mood = .happy
    @State private var intensity: Intensity = .mild
    @State private var isSubmitting = false

    private var trimmedWho: String {
        who.trimmingCharacters(in: .whitespaces)
    }

    /// Submit 始终允许 — 空 who fallback 到 "TA" 占位符。原始 "必须先输入名字"
    /// 规则对最常见的"快速记录 mood 不指定对象"场景太不友好。
    private var canSubmit: Bool {
        !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            // header — 简洁 32pt 小圆心 + "..." 菜单
            popoverHeader

            Divider()

            // form fields 紧贴 header, no gap
            VStack(alignment: .leading, spacing: 14) {
                whoField
                moodField
                intensityField
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // 主操作：提交按钮 (大粉色)
            submitButton
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // 次要操作：前往主窗口 (小按钮) — 点击后由 AppDelegate 关闭
            // popover 并打开主窗口
            Button(action: onOpenMainWindow) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 12))
                    Text("在主窗口查看")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 360)
    }

    // MARK: - header

    private var popoverHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color.pink.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "heart.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("想念计数器")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    Text("已记录 \(store.items.count) 个时刻")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let latest = store.sortedItems.first {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(latest.mood.emoji)
                            .font(.caption2)
                    }
                }
            }
            Spacer()
            // PopoverOverflowMenu 删了 — 弹出的菜单会越过 popover 顶部覆盖
            // 状态栏的心形 panel。设置 (⌘,) / 退出 (⌘Q) 走 SwiftUI app menu
            // / Commands, 主窗口入口有专门的 "在主窗口查看" 按钮。
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - form fields

    private var whoField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("对象")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("想念 谁?", text: $who)
                .textFieldStyle(.roundedBorder)
            if !store.knownWhos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.knownWhos, id: \.self) { name in
                            Button(name) { who = name }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var moodField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("心情")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(Mood.allCases) { m in
                    Button {
                        mood = m
                    } label: {
                        Text(m.emoji)
                            .font(.title2)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(mood == m
                                          ? Color.pink.opacity(0.18)
                                          : Color.gray.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var intensityField: some View {
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
    }

    // MARK: - submit button

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSubmitting
                     ? "记录中…"
                     : (trimmedWho.isEmpty ? "记录（未指定对象）" : "记录这一刻"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(canSubmit ? Color.pink : Color.gray.opacity(0.3))
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    // MARK: - submit

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let entry = Missing(
            who: trimmedWho.isEmpty ? "TA" : trimmedWho,
            mood: mood,
            intensity: intensity
        )
        store.add(entry)
        // Reset form for the next entry; keep mood/intensity since
        // people usually log several in a row at the same emotional state.
        who = ""
        mood = .happy
        intensity = .mild
        isSubmitting = false
    }

    // MARK: - 找不到图标提示

    // MARK: - 找不到图标提示

    /// First-launch 提示：macOS 26 会把 NSStatusItem 默认放到 (0, 0)（Apple menu
    /// 后面）或 ControlCenter 日期 pill 后面，用户找不到。
    /// 提示用户按 Cmd 拖出来，位置由 autosaveName 持久化。
    private var dragHintBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("找不到菜单栏图标？")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("按住 Cmd 把菜单栏左/右端那个小小的心形拖到任意位置，位置会自动记住。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    prefs.hasSeenDragHint = true
                }
            } label: {
                Text("知道了")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.18))
                    )
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
    }

}


