import SwiftUI
import AppKit

/// v0.0.11+ 状态栏菜单 "Check for Updates…" 触发 / 5s 后台检查触发
/// 挂在主窗口顶部的 sticky banner。4 个阶段:
/// - `.available` — 看到新版本,3 按钮: 稍后 / 查看 / 下载
/// - `.downloading` — 进度条 + 稍后(取消下载)
/// - `.downloaded` — 2 按钮: 稍后 / 立即安装 (打开 DMG) / 查看
/// - `.installing` — 1.5s 退出准备期间显示 "正在准备安装…",避免用户
///   在 banner 消失 + 进程真退出之间的空窗期重复点"立即安装"二次触发
enum UpdateBannerState: Equatable {
    case available(version: String, sizeMB: Double?, htmlURL: URL, assetURL: URL?)
    case downloading(version: String, progress: Double)
    case downloaded(version: String, htmlURL: URL, assetURL: URL, localURL: URL)
    case installing(version: String)
}

struct UpdateBanner: View {
    let state: UpdateBannerState
    let onDismiss: () -> Void
    let onStartDownload: (URL) -> Void
    let onInstall: (URL) -> Void

    var body: some View {
        Group {
            switch state {
            case .available(let version, let sizeMB, let htmlURL, let assetURL):
                availableBody(
                    version: version,
                    sizeText: sizeText(sizeMB),
                    htmlURL: htmlURL,
                    assetURL: assetURL
                )
            case .downloading(let version, let progress):
                downloadingBody(version: version, progress: progress)
            case .downloaded(let version, let htmlURL, _, let localURL):
                downloadedBody(version: version, htmlURL: htmlURL, localURL: localURL)
            case .installing(let version):
                installingBody(version: version)
            }
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

    // MARK: - Sub-views per state

    @ViewBuilder
    private func availableBody(
        version: String,
        sizeText: String,
        htmlURL: URL,
        assetURL: URL?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundColor(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("新版本 v\(version) 可用")
                    .font(.subheadline.weight(.medium))
                Text(sizeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("稍后") { onDismiss() }
                .buttonStyle(.borderless)
            Button("查看") {
                NSWorkspace.shared.open(htmlURL)
                onDismiss()
            }
            .buttonStyle(.borderless)
            if let assetURL {
                Button("下载更新 ↓") { onStartDownload(assetURL) }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
            }
        }
    }

    @ViewBuilder
    private func downloadingBody(version: String, progress: Double) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在下载 v\(version)…")
                    .font(.subheadline.weight(.medium))
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.pink)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("稍后") { onDismiss() }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func downloadedBody(
        version: String,
        htmlURL: URL,
        localURL: URL
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.pink)
            VStack(alignment: .leading, spacing: 2) {
                Text("v\(version) 已下载")
                    .font(.subheadline.weight(.medium))
                Text("点击「立即安装」自动退出并打开 DMG,把 .app 拖到 Applications 替换。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("稍后") { onDismiss() }
                .buttonStyle(.borderless)
            Button("立即安装") { onInstall(localURL) }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            // BUG FIX #12: .available 状态的"查看"按钮会 onDismiss(),
            // .downloaded 之前漏了,行为不一致。统一行为:点"查看"都
            // 打开 GitHub release 页面 + 关闭 banner。
            Button("查看") {
                NSWorkspace.shared.open(htmlURL)
                onDismiss()
            }
            .buttonStyle(.borderless)
        }
    }

    /// BUG FIX #7: .downloaded → 用户点"立即安装" → 我们 spawn
    /// nohup open + 1.5s 后 exit(0)。这 1.5s 期间之前 banner 已被
    /// onInstall closure 的 `withAnimation { updateState = nil }` 收掉,
    /// 用户看着空 UI 不知道在干嘛,可能再点。新增 .installing 状态
    /// 显示 spinner + "正在准备安装…",exit(0) 前给用户明确反馈。
    @ViewBuilder
    private func installingBody(version: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在准备安装 v\(version)…")
                    .font(.subheadline.weight(.medium))
                Text("1-2 秒后自动退出,打开 DMG 完成替换。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // 不放按钮 — 这个状态是不可取消的,1.5s 后自动 exit(0)。
            // 让用户看着 spinner 知道在做事。
        }
    }

    private func sizeText(_ sizeMB: Double?) -> String {
        guard let sizeMB else { return "点击「下载」获取 DMG。" }
        return "下载 \(String(format: "%.1f", sizeMB)) MB · 点击「下载」开始"
    }
}
