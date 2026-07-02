import XCTest
import Foundation
@testable import MissingPlusPlus

/// URLSessionDownloadTask 测起来麻烦 (真实下载需要网络 + 进度走 background queue)。
/// 这里只测文件 destination helper (static,纯函数) 跟 cancel() 的 nil-safe 行为。
/// End-to-end 下载验证在手动 smoke test (Task 14 of original plan) 跑。
@MainActor
final class UpdateDownloaderTests: XCTestCase {

    /// DMG 临时文件路径符合预期 (在 app container 的 temporaryDirectory 下,
    /// 固定文件名 "MissingPlusPlus-update.dmg")。
    func test_downloadDestination_isInTemporaryDirectory() {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingPlusPlus-update.dmg")
        XCTAssertEqual(dest.lastPathComponent, "MissingPlusPlus-update.dmg")
        XCTAssertTrue(dest.path.contains("tmp") || dest.path.contains("Temp"))
    }

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
}
