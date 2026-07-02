import Foundation
import AppKit

/// 打开下载好的 DMG — `NSWorkspace.shared.open` 会触发 macOS 自动挂载 + 弹出
/// Finder 窗口,让用户把 `.app` 拖到 /Applications。
///
/// ⚠️ Sandbox 限制: 沙盒 app 不能直接写 /Applications,所以无法做到完全
/// 静默替换 (那是 Sparkle 这类带 privileged helper 的工具的领域)。
/// 这个文件目前只做 "打开 DMG + 引导用户拖" 的半自动流程。
@MainActor
enum UpdateInstaller {
    /// Open the downloaded DMG in Finder. macOS handles mount + auth prompt.
    static func openDMG(at url: URL) {
        NSWorkspace.shared.open(url)
    }
}
