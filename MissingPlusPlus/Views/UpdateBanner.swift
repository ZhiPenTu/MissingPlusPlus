import SwiftUI
import AppKit

/// Sticky pink-gradient banner pinned to the top of the main window.
/// Mounted by `MenuBarContent` when it receives `.showUpdateBanner` notification.
///
/// 设计: 跟 NewMissingForm header 同色系 (AGENTS §11 §16 "焦虑型产品调性"),
/// sticky (不自动 fade) — 用户点 "稍后" 或 "查看" 才消失。
struct UpdateBanner: View {
    let version: String
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("新版本 v\(version) 可用")
                    .font(.subheadline.weight(.medium))
                Text("点击「查看」去 GitHub release 页下载最新 DMG。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("稍后") { onDismiss() }
                .buttonStyle(.borderless)
            Button("查看") {
                NSWorkspace.shared.open(url)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.pink.opacity(0.12), Color.pink.opacity(0.04)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.pink.opacity(0.25)),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
