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
