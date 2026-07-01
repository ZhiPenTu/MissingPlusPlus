import SwiftUI

/// 自己值得被爱的确认。一张结构化卡片,3 段竖排:
/// 1. 看见 (mindfulness — 说出来)
/// 2. 主体 vs 客体 (subject-object split — 拆开)
/// 3. 向内求 (inward — 拉回价值)
/// 「我已确认」= 计数 + dismiss;「再换一组」= 4 段一起换;「关闭」= 直接 dismiss。
struct WorthAffirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var affirmation: WorthAffirmation = .initial
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section(
                number: "1",
                title: "看见",
                body: affirmation.seeing,
                tint: .blue
            )
            subjectObjectSection
            section(
                number: "3",
                title: "向内求",
                body: affirmation.inward,
                tint: .green
            )
            HStack {
                Button {
                    affirmation = WorthAffirmations.randomDifferent(from: affirmation)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("再换一组")
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("我已确认") {
                    prefs.worthConfirmations.append(Date())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
                Button("关闭") { dismiss() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("自己值得被爱")
                    .font(.headline)
                Spacer()
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
            Text("向内求:先看见 → 拆主体客体 → 确认")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var subjectObjectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("2 · 主体 vs 客体")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.purple)
            }
            HStack(alignment: .top, spacing: 10) {
                subjectObjectCard(label: "我是…", body: affirmation.subject, tint: .pink)
                subjectObjectCard(label: "TA 是…", body: affirmation.object, tint: .gray)
            }
        }
    }

    private func subjectObjectCard(label: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(body)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.08))
        )
    }

    private func section(number: String, title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("\(number) · \(title)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tint)
            }
            Text(body)
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.06))
                )
        }
    }
}

private extension WorthAffirmation {
    /// 首次出现 random 选 1 条。
    static var initial: WorthAffirmation {
        WorthAffirmations.pool.randomElement() ?? WorthAffirmations.pool[0]
    }
}
