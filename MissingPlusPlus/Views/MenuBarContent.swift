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
/// 状态栏现在是 NSMenu 1-click 记录（AppDelegate.buildStatusMenu），
/// 没有 popover；Dock / ⌥M 入口都直接走这个 view。
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                case .history:
                    HistoryList(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
            // **关键**: maxHeight: .infinity 让 Group 撑满外层 VStack 剩余空间
            // (720 - tabBar 50 - Divider 1 = 669pt)。否则 HistoryList 的 VStack
            // 自然高度只有 ~130pt, 但 Group 在 720pt 的 VStack 里被推到底部,
            // "最近 / 搜索 / 空态" 整体被甩到窗口底部, 中间一大段白。
            // NewMissingForm / StatisticsView 内部已经自己 fill maxHeight,
            // 这里加 maxHeight: .infinity 主要是给 HistoryList 用, 让它
            // 内部能用 Spacer() 把空态垂直居中。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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


