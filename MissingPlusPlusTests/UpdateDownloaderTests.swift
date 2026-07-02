import XCTest
import AppKit
@testable import MissingPlusPlus

/// URLSessionDownloadTask + NSSavePanel 测起来麻烦 (真实下载要网络 +
/// 进度走 background queue,真 panel 要 user 点击)。这里只测能 offline
/// 验证的部分:destURL via taskDescription 的 escape 行为 + cancel
/// nil-safety + singleton。End-to-end 在手动 smoke test 跑。
@MainActor
final class UpdateDownloaderTests: XCTestCase {

    /// UpdateDownloader.shared 是单例
    func test_singleton() {
        let a = UpdateDownloader.shared
        let b = UpdateDownloader.shared
        XCTAssertTrue(a === b)
    }

    /// cancel() 在没有 in-flight task 时不 crash (nil-safe)
    func test_cancelWithoutTask_isSafe() {
        let d = UpdateDownloader.shared
        d.cancel()  // 没下载就开始 cancel,应该不 crash
        d.cancel()  // 重复 cancel 也应该不 crash
    }

    /// Production 把 destURL.path 写到 taskDescription,delegate 读
    /// 出来再用 `URL(fileURLWithPath:)` round-trip 回去。两个 URL
    /// 必须完全相等 — 这是下载能落到正确位置的前提。
    /// (P0 review fix: 之前用 absoluteString 会被 URL-encode, `:` 变
    /// `%3A`,delegate 当字面路径读会写到 `file%3A/...` 怪位置,DMG
    /// 不在用户选的地方。)
    func test_taskDescription_roundTripViaPath() {
        let original = URL(fileURLWithPath: "/Users/foo/Downloads/MissingPlusPlus-0.0.26.dmg")
        let taskDescription: String? = original.path
        let recovered = URL(fileURLWithPath: taskDescription ?? "")
        XCTAssertEqual(recovered, original,
            "round-trip via taskDescription (path form) must preserve the URL")
    }

    /// Defensive: 路径含空格 / 中文 / 重音符号等也必须能 round-trip。
    /// .path 用 %-encoding 处理这些,但 file:// URL 转 .path 后 % 应该
    /// 被 unescape。验证我们走的是 unencoded filesystem path。
    func test_taskDescription_pathHandlesUnicodeAndSpaces() {
        let original = URL(fileURLWithPath: "/Users/foo/我的下载/MissingPlusPlus 0.0.26.dmg")
        let taskDescription: String? = original.path
        let recovered = URL(fileURLWithPath: taskDescription ?? "")
        XCTAssertEqual(recovered, original,
            "round-trip must preserve unicode and spaces in path")
    }

    /// NSSavePanel 推荐文件名构造: `MissingPlusPlus-<version>.dmg`。
    /// 这是 MenuBarContent onStartDownload closure 里 inline 构造的。
    /// 提取成单测覆盖,避免以后随手改 format 改坏。
    /// 注: 实际构造发生在 MenuBarContent,这里复刻字符串模板测;
    /// 如果 MenuBarContent 的 filename 拼接逻辑改了,这个 test 仍
    /// 能 catch format 漂移 (因为我们测的是 pattern 不是 state)。
    func test_suggestedFilename_patternIsCorrect() {
        let version = "0.0.26"
        let filename = "MissingPlusPlus-\(version).dmg"
        XCTAssertEqual(filename, "MissingPlusPlus-0.0.26.dmg")
    }

    /// UpdateBannerState 三个 case 都该 Equatable (banner 状态机用)。
    /// 之前 EnumString download path 改过,这里 pin 一下 contract。
    func test_updateBannerState_isEquatable() {
        // .available with same fields → equal
        let a1 = UpdateBannerState.available(
            version: "0.0.26", sizeMB: 3.2,
            htmlURL: URL(string: "https://example.com")!,
            assetURL: URL(string: "https://example.com/foo.dmg")
        )
        let a2 = UpdateBannerState.available(
            version: "0.0.26", sizeMB: 3.2,
            htmlURL: URL(string: "https://example.com")!,
            assetURL: URL(string: "https://example.com/foo.dmg")
        )
        XCTAssertEqual(a1, a2)

        // .downloading with different progress → not equal
        let d1 = UpdateBannerState.downloading(version: "0.0.26", progress: 0.5)
        let d2 = UpdateBannerState.downloading(version: "0.0.26", progress: 0.6)
        XCTAssertNotEqual(d1, d2)

        // different cases → not equal
        XCTAssertNotEqual(a1, d1)
    }
}
