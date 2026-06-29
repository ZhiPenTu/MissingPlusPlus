import SwiftUI

/// DBT "Check the Facts" skill 的轻量落点：把"我现在的情绪"拆成
/// "证据 / 反对证据 / 接下来做什么" 三栏事实，焦虑型最容易在 strong intensity
/// 时被 emotion flooding 拉走，这个 sheet 是温柔的外部 nudge。
struct RealityCheckSheet: View {
    let missing: Missing
    var onSave: (RealityCheck) -> Void
    var onSkip: () -> Void

    @State private var evidenceFor: String = ""
    @State private var evidenceAgainst: String = ""
    @State private var nextAction: String = ""
    @Environment(\.dismiss) private var dismiss
    // v1.x self-soothing: 3 个 sub-button 触发对应 sub-sheet
    @State private var pendingGrounding = false
    @State private var pendingCompassion: Missing?
    @State private var pendingCooldown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("现实检验")
                    .font(.headline)
                Text("DBT 的「Check the Facts」：写下来，情绪就变成可观察的事实。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            field(title: "这次想念的证据是…",
                  placeholder: "比如：TA 5h 没回我消息",
                  text: $evidenceFor)
            field(title: "反对的证据是…",
                  placeholder: "比如：上周 TA 也这样，后来回我说在加班",
                  text: $evidenceAgainst)
            field(title: "我接下来会…",
                  placeholder: "比如：再等 30 分钟；不主动发消息",
                  text: $nextAction)

            HStack {
                Button("跳过") {
                    onSkip()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    let check = RealityCheck(
                        evidenceFor: trimmedOrNil(evidenceFor),
                        evidenceAgainst: trimmedOrNil(evidenceAgainst),
                        nextAction: trimmedOrNil(nextAction),
                        checkedAt: Date()
                    )
                    onSave(check)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false)
            }

            // v1.x self-soothing: 3 icon-only sub-button (hover tooltip 显示 label)
            HStack(spacing: 8) {
                Text("想先做点别的？")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    pendingGrounding = true
                } label: {
                    Image(systemName: "eye")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                .help("5-4-3-2-1 grounding")
                Button {
                    pendingCompassion = missing
                } label: {
                    Image(systemName: "heart.text.square")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.pink)
                .help("自我同情")
                Button {
                    pendingCooldown = true
                } label: {
                    Image(systemName: "shuffle")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.purple)
                .help("分散注意力")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .sheet(isPresented: $pendingGrounding) { GroundingSheet() }
        .sheet(item: $pendingCompassion) { _ in SelfCompassionView(missing: missing) }
        .sheet(isPresented: $pendingCooldown) { CooldownSheet(prefs: AppPreferences.shared) }
    }

    private var canSave: Bool {
        trimmedOrNil(evidenceFor) != nil ||
        trimmedOrNil(evidenceAgainst) != nil ||
        trimmedOrNil(nextAction) != nil
    }

    private func field(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
