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
