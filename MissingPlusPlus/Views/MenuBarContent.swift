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
                    NewMissingForm(store: store)
                        .padding(12)
                        .background(Color(NSColor.windowBackgroundColor))
                case .stats:
                    StatisticsView(store: store)
                        .background(Color(NSColor.windowBackgroundColor))
                case .history:
                    HistoryList(store: store)
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == item ? Color.pink.opacity(0.18) : Color.clear)
                        )
                        .foregroundColor(tab == item ? .pink : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            PopoverOverflowMenu()
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
    }
}

/// The status-bar popover's content. Compact dashboard view — no record
/// form, no submit button. The user can hop into the main window (which
/// has the full record form + submit button) via the "在主窗口记录"
/// button at the bottom, or by clicking the Dock icon directly.
///
/// Why the split (Dock=form, popover=read-only):
///   * macOS popovers are designed for "compact, click-outside-to-dismiss"
///     interactions; the user clicks the menu bar to *peek*, not to *act*.
///   * The Dock entry has a proper title bar + traffic lights, which
///     signals "this is the full app" — the right place for a record form.
///   * Removing the submit button from the popover also removes the
///     "form-without-submit" confusion that came from sharing one view
///     between both entry points.
struct PopoverContent: View {
    @ObservedObject var store: MissingStore
    @ObservedObject var prefs = AppPreferences.shared
    /// Called when the user wants to leave the popover and open the
    /// main window (Dock-style entry). The AppDelegate wires this up
    /// to close the popover and `showMainWindow()`.
    let onOpenMainWindow: () -> Void
    @State private var tab: PopoverTab = .stats

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

            if !prefs.hasSeenDragHint {
                dragHintBanner
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            tabBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Group {
                switch tab {
                case .stats:
                    StatisticsView(store: store)
                        .background(Color(NSColor.windowBackgroundColor))
                case .history:
                    HistoryList(store: store)
                        .background(Color(NSColor.windowBackgroundColor))
                case .newEntry:
                    // Defensive: popover never exposes this tab via the
                    // tab bar, but if a future refactor adds it back we
                    // show a clear pointer to the main window instead
                    // of a broken form-without-submit.
                    redirectToMainWindow
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            openMainWindowButton
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 360, height: 560)
    }

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

    // MARK: - header

    private var header: some View {
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
                Text("思念计数器")
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
            PopoverOverflowMenu()
        }
    }

    // MARK: - tab bar (no 新建)

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(PopoverTab.allCases.filter { $0 != .newEntry }) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == item ? Color.pink.opacity(0.18) : Color.clear)
                        )
                        .foregroundColor(tab == item ? .pink : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
    }

    // MARK: - main window CTA

    private var openMainWindowButton: some View {
        Button(action: onOpenMainWindow) {
            HStack(spacing: 8) {
                Image(systemName: "macwindow.on.rectangle")
                Text("在主窗口记录")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(.pink)
        .help("打开主窗口以记录新的思念")
    }

    private var redirectToMainWindow: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32))
                .foregroundColor(.pink.opacity(0.7))
            Text("请在主窗口记录")
                .font(.headline)
            Text("状态栏弹窗是只读视图，新建条目需要在主窗口里完成。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: onOpenMainWindow) {
                Label("打开主窗口", systemImage: "macwindow.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}



/// 菜单栏 app 状态栏 item 的 SwiftUI label — 给 `MenuBarExtra(content:label:)`
/// 用 (C 方案)。
///
/// 行为：
/// - `prefs.showStatusItem == false` → 完全不渲染（不占菜单栏位，hit area
///   也没有；用户主动关掉后，"打开 popover" 只能走 Dock / ⌥M / ⌘, 三条路）
/// - `prefs.showStatusItem == true` → 调 `MenuBarIconRenderer.image` 拿到
///   当前 mood + style 对应的 NSImage，包成 SwiftUI `Image` 给 MenuBarExtra
///
/// Mood 联动是 SwiftUI 声明式的：prefs / store 变化 → view 自动 re-render，
/// 不需要 NotificationCenter 手动 push（这跟旧 NSStatusItem 路线最大的区别）。
struct StatusBarIcon: View {
    @ObservedObject var store: MissingStore
    @ObservedObject var prefs: AppPreferences

    var body: some View {
        if prefs.showStatusItem {
            let latestMood = store.sortedItems.first?.mood
            Image(nsImage: MenuBarIconRenderer.image(mood: latestMood, style: prefs.menuBarIconStyle))
        }
    }
}
