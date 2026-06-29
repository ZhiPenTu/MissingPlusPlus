import SwiftUI

/// 自我同情 sheet。AI 启用时 → 调 `generateSelfCompassion(for: missing)`；
/// 关闭 / 出错 → 从 `SelfCompassionPhrases.phrases` 抽一条。
/// 右上角小角标显示当前是「AI」还是「内置」文案。
struct SelfCompassionView: View {
    let missing: Missing

    @Environment(\.dismiss) private var dismiss
    @State private var phrase: String = ""
    @State private var usedAI: Bool = false
    @State private var isRegenerating: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            phraseBox
            HStack {
                Button {
                    regenerate()
                } label: {
                    HStack(spacing: 4) {
                        if isRegenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("再换一句")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRegenerating)
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { regenerate() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("自我同情")
                    .font(.headline)
                Spacer()
                if usedAI {
                    Text("AI")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.pink.opacity(0.15))
                        )
                        .foregroundColor(.pink)
                } else {
                    Text("内置")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.15))
                        )
                        .foregroundColor(.secondary)
                }
            }
            Text("DBT / Kristin Neff：对自己说一句有用的话。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var phraseBox: some View {
        Group {
            if phrase.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 32)
                .padding(.horizontal, 12)
            } else {
                Text(phrase)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.pink.opacity(0.06))
        )
    }

    // MARK: - Actions

    private func regenerate() {
        isRegenerating = true
        let snapshot = missing
        let aiEnabled = AppPreferences.shared.aiEnabled
            && AppPreferences.shared.aiIsConfigured
        Task {
            // 内部会根据 prefs 自动 fallback;但我们需要知道这次用的是 AI 还是内置,
            // 所以这里直接看 prefs 决策。
            let text = await generateSelfCompassion(for: snapshot)
            await MainActor.run {
                self.phrase = text
                self.usedAI = aiEnabled
                self.isRegenerating = false
            }
        }
    }
}
