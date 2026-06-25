import SwiftUI

struct NewMissingForm: View {
    @ObservedObject var store: MissingStore
    @State private var who: String = ""
    @State private var mood: Mood = .happy
    @State private var intensity: Intensity = .mild
    @State private var isSubmitting = false

    private var trimmedWho: String {
        who.trimmingCharacters(in: .whitespaces)
    }

    /// Submit is always allowed — an empty `who` falls back to a placeholder
    /// so the form doesn't sit in a perpetually-disabled state. (The original
    /// "must type a name first" rule was hostile for the most common case
    /// of wanting to log a quick mood with no subject in mind.)
    private var canSubmit: Bool {
        !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.10), Color.pink.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WhoField(who: $who, suggestions: store.knownWhos)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("心情")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        MoodPicker(selection: $mood)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("程度")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("程度", selection: $intensity) {
                            ForEach(Intensity.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(16)
            }

            Divider()

            actionButton
                .padding(16)
                .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.pink, Color.pink.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.pink.opacity(0.25), radius: 4, y: 1)
                Image(systemName: "heart.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("思念计数器")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text("已记录 \(store.items.count) 个时刻")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let latest = store.sortedItems.first {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(latest.mood.emoji)
                            .font(.caption)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - action button

    private var actionButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(isSubmitting ? "记录中…" : (trimmedWho.isEmpty ? "记录（未指定对象）" : "记录这一刻"))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.pink)
        .disabled(!canSubmit)
    }

    // MARK: - submit

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let entry = Missing(
            who: trimmedWho.isEmpty ? "TA" : trimmedWho,
            mood: mood,
            intensity: intensity
        )
        store.add(entry)

        // Reset form for the next entry; keep the mood/intensity since
        // people usually log several in a row at the same emotional state.
        who = ""
        mood = .happy
        intensity = .mild
        isSubmitting = false
    }
}

private struct WhoField: View {
    @Binding var who: String
    let suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("对象")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("想念 谁?", text: $who)
                .textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) { who = name }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

private struct MoodPicker: View {
    @Binding var selection: Mood

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Mood.allCases) { mood in
                Button {
                    selection = mood
                } label: {
                    Text(mood.emoji)
                        .font(.title2)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == mood
                                      ? Color.pink.opacity(0.18)
                                      : Color.gray.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selection == mood
                                        ? Color.pink
                                        : Color.gray.opacity(0.18),
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(mood.label)
            }
        }
    }
}
