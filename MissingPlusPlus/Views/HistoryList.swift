import SwiftUI

struct HistoryList: View {
    @ObservedObject var store: MissingStore
    @State private var query: String = ""
    /// v1.x layout: limit 20 records by default + "load more" 展开
    @State private var showingAll: Bool = false
    /// v1.x: 点击卡片底部"做现实检验"按钮 → 弹这个 sheet（per-card 一次性）
    @State private var pendingRealityCheck: Missing?
    /// v1.x self-soothing: 3 个 sub-sheet 入口
    @State private var pendingGrounding: Missing?
    @State private var pendingCompassion: Missing?
    @State private var pendingCooldown: Missing?

    private var filtered: [Missing] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let cap = showingAll ? 100 : 20
        if q.isEmpty {
            return Array(store.sortedItems.prefix(cap))
        }
        return store.sortedItems
            .filter { $0.who.localizedCaseInsensitiveContains(q) }
            .prefix(cap)
            .map { $0 }
    }

    /// 把 filtered 按日期分桶（今天 / 昨天 / 本周 / 本月 / 更早），展平成 HistoryListItem 列表。
    private var sectioned: [HistoryListItem] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let weekStart = cal.date(byAdding: .day, value: -7, to: today)!
        let monthStart = cal.date(byAdding: .day, value: -30, to: today)!

        var result: [HistoryListItem] = []
        var lastBucket: DateBucket? = nil

        for item in filtered {
            let day = cal.startOfDay(for: item.createdAt)
            let bucket: DateBucket
            if day == today { bucket = .today }
            else if day == yesterday { bucket = .yesterday }
            else if day >= weekStart { bucket = .thisWeek }
            else if day >= monthStart { bucket = .thisMonth }
            else { bucket = .earlier }

            if bucket != lastBucket {
                result.append(.header(bucket.label))
                lastBucket = bucket
            }
            result.append(.row(item))
        }
        return result
    }

    /// v1.x layout: 是否还有更多（超过当前 cap）
    private var hasMore: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return store.sortedItems.count > filtered.count
        } else {
            let allMatches = store.sortedItems.filter { $0.who.localizedCaseInsensitiveContains(q) }
            return allMatches.count > filtered.count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(filtered.count) / \(store.items.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("按对象搜索", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.08))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if filtered.isEmpty {
                // v2 layout: Spacer 把空态推到 HistoryList 可用空间居中位置
                // (依赖 MenuBarContent 那边给 .frame(maxHeight: .infinity))。
                // 旧版没 Spacer + Group 自然高度 → 空态贴窗口底部, 中间一大段白。
                Spacer(minLength: 24)
                emptyState
                Spacer(minLength: 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sectioned, id: \.id) { item in
                            switch item {
                            case .header(let label):
                                HStack {
                                    Text(label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            case .row(let missing):
                                HistoryRow(
                                    item: missing,
                                    onResolve: { store.markResolved(missing) },
                                    onRequestCheck: { pendingRealityCheck = missing },
                                    onRequestGrounding: { pendingGrounding = missing },
                                    onRequestCompassion: { pendingCompassion = missing },
                                    onRequestCooldown: { pendingCooldown = missing }
                                )
                                Divider().padding(.leading, 40)
                            }
                        }
                        if hasMore && !showingAll {
                            Button {
                                withAnimation { showingAll = true }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("加载更多…")
                                        .font(.caption)
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .sheet(item: $pendingRealityCheck) { record in
            RealityCheckSheet(missing: record) { check in
                store.attachRealityCheck(record, check: check)
            } onSkip: {
                // no-op
            }
        }
        .sheet(item: $pendingGrounding) { _ in GroundingSheet() }
        .sheet(item: $pendingCompassion) { record in SelfCompassionView(missing: record) }
        .sheet(item: $pendingCooldown) { _ in CooldownSheet(prefs: AppPreferences.shared) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: query.isEmpty ? "heart.text.square" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.gray.opacity(0.4))
            Text(query.isEmpty ? "还没有记录" : "没有匹配的记录")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(query.isEmpty ? "想念的时候就来记一笔吧" : "试试别的关键字")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct HistoryRow: View {
    let item: Missing
    let onResolve: () -> Void
    let onRequestCheck: () -> Void
    let onRequestGrounding: () -> Void
    let onRequestCompassion: () -> Void
    let onRequestCooldown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.mood.emoji)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                // Row 1: who · intensity · time  +  [resolved] [4 icon buttons]
                HStack(spacing: 4) {
                    Text(item.who)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(item.intensity.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(relativeTime(item.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    resolvedButton
                    if item.realityCheck == nil {
                        Button(action: onRequestCheck) {
                            Image(systemName: "checkmark.bubble")
                                .font(.callout)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.purple)
                        .help("做现实检验")
                    }
                    Button(action: onRequestGrounding) {
                        Image(systemName: "eye")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.blue)
                    .help("5-4-3-2-1 grounding")
                    Button(action: onRequestCompassion) {
                        Image(systemName: "heart.text.square")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.pink)
                    .help("自我同情")
                    Button(action: onRequestCooldown) {
                        Image(systemName: "shuffle")
                            .font(.callout)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.purple)
                    .help("分散注意力")
                }
                triggerChips
                realityCheckSection
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var resolvedButton: some View {
        Button(action: onResolve) {
            if let resolvedAt = item.resolvedAt {
                Text("✓ " + relativeTime(resolvedAt))
                    .font(.caption2)
                    .foregroundColor(MoodColor.forMood(item.mood))
            } else {
                Text("○")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var triggerChips: some View {
        if !item.triggerTags.isEmpty {
            HStack(spacing: 3) {
                ForEach(item.triggerTags.prefix(3)) { tag in
                    Text(tag.displayString)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                }
                if item.triggerTags.count > 3 {
                    Text("+\(item.triggerTags.count - 3)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var realityCheckSection: some View {
        if let rc = item.realityCheck {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.bubble")
                    Text("已做现实检验")
                }
                .font(.caption2)
                .foregroundColor(.purple)
                if let s = rc.evidenceFor {
                    Text("• 证据：" + s)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let s = rc.evidenceAgainst {
                    Text("• 反对：" + s)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let s = rc.nextAction {
                    Text("• 接下来：" + s)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// v1.x layout: flat list item for date-grouped history view.
enum HistoryListItem: Identifiable {
    case header(String)
    case row(Missing)
    var id: String {
        switch self {
        case .header(let label): return "h-\(label)"
        case .row(let m): return "r-\(m.id.uuidString)"
        }
    }
}

/// v1.x layout: date buckets for grouping.
enum DateBucket: String, Hashable {
    case today, yesterday, thisWeek, thisMonth, earlier
    var label: String {
        switch self {
        case .today:     return "今天"
        case .yesterday: return "昨天"
        case .thisWeek:  return "本周"
        case .thisMonth: return "本月"
        case .earlier:   return "更早"
        }
    }
}
