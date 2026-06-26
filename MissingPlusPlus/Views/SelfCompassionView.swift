import SwiftUI

struct SelfCompassionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = .random(in: 0..<SelfCompassionPhrases.phrases.count)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("自我同情")
                .font(.headline)
            Text("DBT / Kristin Neff：对自己说一句有用的话。")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(SelfCompassionPhrases.phrases[index])
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 32)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.pink.opacity(0.06))
                )

            HStack {
                Button("再抽一句") {
                    var next = index
                    while next == index && SelfCompassionPhrases.phrases.count > 1 {
                        next = .random(in: 0..<SelfCompassionPhrases.phrases.count)
                    }
                    index = next
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
