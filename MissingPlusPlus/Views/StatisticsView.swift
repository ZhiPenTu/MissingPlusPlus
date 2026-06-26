import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject var store: MissingStore
    @State private var now: Date = Date()

    /// Re-render once a minute so "this week" stays current.
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private let lookbackDays: Int = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                Divider()

                summary

                Divider()

                insightCards

                Divider()

                trendSection
            }
            .padding(12)
        }
        .onReceive(tick) { now = $0 }
    }

    // MARK: - sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundColor(.pink)
            Text("统计")
                .font(.headline)
            Spacer()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("累计思念", value: "\(store.items.count) 条")
            row("本周新增", value: "\(thisWeekCount) 条")
            row("平均强度", value: averageIntensityLabel)
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("近 \(lookbackDays) 天")
                .font(.subheadline)
                .fontWeight(.medium)

            if dailyBuckets.allSatisfy({ $0.total == 0 }) {
                Text("近 \(lookbackDays) 天还没有记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                Chart(dailyBuckets) { bucket in
                    ForEach(bucket.moodCounts, id: \.mood) { entry in
                        BarMark(
                            x: .value("日期", bucket.date, unit: .day),
                            y: .value("次数", entry.count)
                        )
                        .foregroundStyle(by: .value("心情", entry.mood.label))
                    }
                }
                .chartForegroundStyleScale(moodColorMapping)
                .chartLegend(.hidden)
                .frame(height: 120)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    let stride = max(1, lookbackDays / 6)
                    AxisMarks(values: .stride(by: .day, count: stride)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }

                HStack(spacing: 10) {
                    ForEach(Mood.allCases) { mood in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(MoodColor.forMood(mood))
                                .frame(width: 8, height: 8)
                            Text(mood.label)
                                .font(.caption2)
                        }
                    }
                }
                .padding(.top, 2)
            }

            Divider().padding(.vertical, 2)

            Text("最想念的人 · Top 3")
                .font(.caption)
                .foregroundColor(.secondary)
            if topThree.isEmpty {
                Text("还没有记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(topThree, id: \.who) { entry in
                    HStack {
                        Text(entry.who)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(entry.count) 次")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - helpers

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
    }

    private var thisWeekCount: Int {
        let cal = Calendar.current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else {
            return 0
        }
        return store.items.filter { $0.createdAt >= weekStart }.count
    }

    private var averageIntensityLabel: String {
        let map: [Intensity: Int] = [.none: 0, .mild: 1, .strong: 2]
        let scores = store.items.map { map[$0.intensity] ?? 1 }
        guard !scores.isEmpty else { return "—" }
        let avg = Double(scores.reduce(0, +)) / Double(scores.count)
        if avg < 0.5 { return "无" }
        if avg < 1.5 { return "一般" }
        return "非常"
    }

    private var topThree: [(who: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in store.items {
            let key = item.who.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (who: $0.key, count: $0.value) }
    }

    // MARK: - v1.x anxious-attachment insights (过去 30 天)

    private var last30Days: [Missing] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        return store.items.filter { $0.createdAt >= cutoff }
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

    // MARK: - chart data

    private struct DailyBucket: Identifiable {
        let id = UUID()
        let date: Date
        let moodCounts: [(mood: Mood, count: Int)]
        var total: Int { moodCounts.reduce(0) { $0 + $1.count } }
    }

    private var dailyBuckets: [DailyBucket] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<lookbackDays).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let dayStart = cal.startOfDay(for: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
            let dayItems = store.items.filter { $0.createdAt >= dayStart && $0.createdAt < dayEnd }
            var counts: [Mood: Int] = [:]
            for item in dayItems {
                counts[item.mood, default: 0] += 1
            }
            // Stable order matching the legend: happy/joyful/delighted/sad/longing
            let order: [Mood] = [.happy, .joyful, .delighted, .sad, .longing]
            let entries = order.compactMap { mood -> (mood: Mood, count: Int)? in
                guard let c = counts[mood], c > 0 else { return nil }
                return (mood, c)
            }
            return DailyBucket(date: day, moodCounts: entries)
        }
    }

    private var moodColorMapping: KeyValuePairs<String, Color> {
        // SwiftUI Charts reads this as a discrete scale, so we map mood label
        // to the matching color from MoodColor.forMood().
        [
            Mood.happy.label:     MoodColor.forMood(.happy),
            Mood.joyful.label:    MoodColor.forMood(.joyful),
            Mood.delighted.label: MoodColor.forMood(.delighted),
            Mood.sad.label:       MoodColor.forMood(.sad),
            Mood.longing.label:   MoodColor.forMood(.longing),
        ]
    }
    // MARK: - v1.x insight cards (3 个)

    private var insightCards: some View {
        VStack(spacing: 10) {
            WaveResolvedCard(stats: waveStats)
            TopTriggersCard(triggers: topTriggers)
            RealityCheckCard(stats: realityCheckStats)
        }
        .padding(.bottom, 4)
    }
}

/// 卡片 1: 浪都过去了 — bundle 最核心的 evidence: "想念是有限时的"
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

/// 卡片 2: 你的常见 trigger
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

/// 卡片 3: 现实检验完成度
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

/// Single source of truth for mood colors. Mirrors the gradient endpoints
/// used in `make-icons.py`'s MOOD_PALETTE so the chart and menu bar stay
/// visually consistent.
enum MoodColor {
    static func forMood(_ mood: Mood) -> Color {
        switch mood {
        case .happy:     return Color(red: 1.00, green: 0.78, blue: 0.34)   // #FFC857
        case .joyful:    return Color(red: 0.43, green: 0.86, blue: 0.51)   // #6EDC82
        case .delighted: return Color(red: 0.91, green: 0.12, blue: 0.39)   // #E91E63
        case .sad:       return Color(red: 0.36, green: 0.48, blue: 0.60)   // #5B7A99
        case .longing:   return Color(red: 0.61, green: 0.45, blue: 0.81)   // #9B72CF
        }
    }
}
