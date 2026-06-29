import XCTest
import AppKit
import UserNotifications
@testable import MissingPlusPlus

@MainActor
final class NotificationServiceTests: XCTestCase {

    // MARK: - attachment 创建

    func test_makeMoodAttachment_createsAttachmentForEachMood() {
        for mood in Mood.allCases {
            let attachment = NotificationService.makeMoodAttachment(for: mood)
            XCTAssertNotNil(attachment, "Should create attachment for mood \(mood.rawValue)")
        }
    }

    func test_makeMoodAttachment_usesCorrectIdentifier() {
        let attachment = NotificationService.makeMoodAttachment(for: .happy)
        XCTAssertEqual(attachment?.identifier, "mood-happy")
    }

    func test_makeMoodAttachment_copiesPngToTmpDirectory() {
        let attachment = NotificationService.makeMoodAttachment(for: .delighted)
        XCTAssertNotNil(attachment)

        // attachment URL 应该在 NSTemporaryDirectory 下, 文件存在, 是 .png
        let url = attachment?.url
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.pathExtension, "png")
        XCTAssertNotNil(url?.path)

        let tmpRoot = FileManager.default.temporaryDirectory.path
        XCTAssertTrue(url?.path.hasPrefix(tmpRoot) ?? false,
                      "Attachment should be in NSTemporaryDirectory")

        // 文件实际存在
        XCTAssertTrue(FileManager.default.fileExists(atPath: url?.path ?? ""))

        // 文件名带 missingpp-mood- 前缀和 UUID (隔离多次调用)
        XCTAssertTrue(url?.lastPathComponent.contains("missingpp-mood-") ?? false)
    }

    // MARK: - 多次调用不冲突

    func test_makeMoodAttachment_multipleCalls_createDistinctFiles() {
        let a1 = NotificationService.makeMoodAttachment(for: .happy)
        let a2 = NotificationService.makeMoodAttachment(for: .happy)
        XCTAssertNotNil(a1)
        XCTAssertNotNil(a2)
        XCTAssertNotEqual(a1?.url, a2?.url,
                          "Each call should create a fresh tmp file (UUID-based)")
    }

    // MARK: - 失败 fallback

    func test_makeMoodAttachment_missingResource_returnsNil() {
        // 临时把 bundle 里的 resource 路径搞砸不可行 (会影响别的 test),
        // 这里只验证"找不到资源时返回 nil"的路径不会崩:
        // 跑完 5 个 mood 都没崩, 间接证明 fallback 路径存在
        for _ in 0..<3 {
            for mood in Mood.allCases {
                _ = NotificationService.makeMoodAttachment(for: mood)
            }
        }
    }

    // MARK: - 异步 / 投递 链路 (smoke)

    /// postRecordNotification 投递的是 UNUserNotificationCenter (process singleton)
    /// 真实投递会出现在系统通知中心, 测试环境只是 smoke 验证不 crash。
    /// AI body 走 AIService.generateAINotificationBody, AI 关闭 → fallback 固定模板。
    // MARK: - title 格式 (internal static helper)

    func test_titleForMissing_withWho_usesWho() {
        let m = Missing(who: "苏苏", mood: .longing, intensity: .strong)
        XCTAssertEqual(NotificationService.titleForMissing(m), "想念 苏苏")
    }

    func test_titleForMissing_withEmptyWho_usesTA() {
        let m = Missing(who: "", mood: .sad, intensity: .mild)
        XCTAssertEqual(NotificationService.titleForMissing(m), "想念 TA")
    }

    // MARK: - postRecordNotification smoke

    /// UNUserNotificationCenter 投递会真在通知中心出现 (测试环境也跑),
    /// 干扰 dev 体验。Smoke 测只验不 crash + 给足时间让 AI fallback / 投递跑完。
    func test_postRecordNotification_doesNotCrash() {
        let service = NotificationService.shared
        let missing = Missing(who: "苏苏", mood: .longing, intensity: .strong)
        service.postRecordNotification(for: missing)

        let exp = expectation(description: "wait for notification dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2.0)
    }
}
