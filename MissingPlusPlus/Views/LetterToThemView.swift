import SwiftUI
import AppKit

/// 致 TA 的话 sheet：AI 根据 who + mood + intensity + triggers 生成 80-140 字
/// 的"想对 TA 说、但还没发出去"的一段话。可换一封、可复制到剪贴板。
///
/// AI 关闭 / 出错 → 抽 `LetterTemplates.fallback` 里的一封备选。
struct LetterToThemView: View {
    let missing: Missing
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var letter: String = ""
    @State private var isGenerating: Bool = false
    @State private var didGenerate: Bool = false
    @State private var copyConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            letterBody
            HStack {
                Button {
                    generate()
                } label: {
                    HStack(spacing: 4) {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(didGenerate ? "再写一封" : "写一封")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copyConfirm ? "checkmark.circle.fill" : "doc.on.doc")
                        Text(copyConfirm ? "已复制" : "复制")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.pink)
                .disabled(letter.isEmpty)
                Button("完成") {
                    onDone()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if !didGenerate { generate() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("致 \(missing.who.isEmpty ? "TA" : missing.who)")
                .font(.headline)
            Text(missingSubtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var missingSubtitle: String {
        var parts: [String] = ["\(missing.mood.emoji) \(missing.mood.label)", "程度：\(missing.intensity.label)"]
        if !missing.triggerTags.isEmpty {
            parts.append("触发：" + missing.triggerTags.map(\.label).joined(separator: "、"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var letterBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if letter.isEmpty && isGenerating {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在写...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
                } else if letter.isEmpty {
                    Text("点「写一封」让 AI 帮你起个草稿，或读读一封备选。")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    Text(letter)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 180, maxHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.pink.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.pink.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func generate() {
        isGenerating = true
        let snapshotMissing = missing
        Task {
            // 调用 AIService。失败会自动降级到 LetterTemplates.fallback。
            let result = await generateLetterToThem(for: snapshotMissing)
            await MainActor.run {
                self.letter = result
                self.isGenerating = false
                self.didGenerate = true
            }
        }
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(letter, forType: .string)
        copyConfirm = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyConfirm = false
        }
    }
}
