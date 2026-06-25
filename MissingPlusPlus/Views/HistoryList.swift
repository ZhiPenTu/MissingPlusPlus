import SwiftUI

struct HistoryList: View {
    @ObservedObject var store: MissingStore
    @State private var query: String = ""

    private var filtered: [Missing] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return Array(store.sortedItems.prefix(50))
        }
        return store.sortedItems
            .filter { $0.who.localizedCaseInsensitiveContains(q) }
            .prefix(50)
            .map { $0 }
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
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { item in
                            HistoryRow(item: item)
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Text(item.mood.emoji)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.who)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(item.intensity.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(relativeTime(item.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
