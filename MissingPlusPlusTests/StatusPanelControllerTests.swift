import XCTest
import AppKit
@testable import MissingPlusPlus

@MainActor
final class StatusPanelControllerTests: XCTestCase {

    // MARK: - setUp / tearDown

    private var originalShowStatusItem: Bool!
    private var originalMenuBarIconStyle: MenuBarIconStyle!
    /// 收集每个 test 创建的 controller,tearDown 统一调 dismiss 拆 status item,
    /// 避免上一个 test 创建的 NSStatusItem 漏到下一个 test。
    private var activeControllers: [StatusPanelController] = []

    override func setUp() async throws {
        try await super.setUp()
        originalShowStatusItem = AppPreferences.shared.showStatusItem
        originalMenuBarIconStyle = AppPreferences.shared.menuBarIconStyle
        // 每个 test 从干净状态开始 — 关掉 status item
        AppPreferences.shared.showStatusItem = false
    }

    override func tearDown() async throws {
        // 还原 prefs
        if let original = originalShowStatusItem {
            AppPreferences.shared.showStatusItem = original
        }
        if let original = originalMenuBarIconStyle {
            AppPreferences.shared.menuBarIconStyle = original
        }
        // 拆掉本 test 创建的所有 status item (NSStatusItem 没有公开 API 枚举,
        // 必须靠 controller 引用 → dismiss)
        for controller in activeControllers {
            controller.dismiss()
        }
        activeControllers.removeAll()
        try await super.tearDown()
    }

    private func makeController(
        onRecord: @escaping (Mood, String, Intensity) -> Void = { _, _, _ in },
        onOpenMain: @escaping () -> Void = {},
        onCheckForUpdates: @escaping () -> Void = {}
    ) -> StatusPanelController {
        let c = StatusPanelController(
            onRecord: onRecord,
            onOpenMain: onOpenMain,
            onCheckForUpdates: onCheckForUpdates
        )
        activeControllers.append(c)
        return c
    }

    // MARK: - install 行为

    func test_init_withShowStatusItemOn_installsStatusItem() {
        AppPreferences.shared.showStatusItem = true
        let controller = makeController()
        XCTAssertTrue(
            controller.isStatusItemVisible,
            "Should have a visible NSStatusItem after init when showStatusItem = true"
        )
    }

    func test_init_withShowStatusItemOff_doesNotInstallStatusItem() {
        AppPreferences.shared.showStatusItem = false
        let controller = makeController()
        XCTAssertFalse(
            controller.isStatusItemVisible,
            "Should not have a visible NSStatusItem when showStatusItem = false"
        )
    }

    // MARK: - prefs 变化响应

    func test_prefsChangeToOn_installsStatusItem() {
        AppPreferences.shared.showStatusItem = false
        let controller = makeController()
        XCTAssertFalse(controller.isStatusItemVisible, "Starting with no status item")

        // 模拟用户在 settings 里开了 "show status item"
        AppPreferences.shared.showStatusItem = true

        XCTAssertTrue(
            controller.isStatusItemVisible,
            "Should install status item after prefs change"
        )
    }

    func test_prefsChangeToOff_uninstallsStatusItem() {
        AppPreferences.shared.showStatusItem = true
        let controller = makeController()
        XCTAssertTrue(controller.isStatusItemVisible, "Starting with status item visible")

        // 模拟用户在 settings 里关了 "show status item"
        AppPreferences.shared.showStatusItem = false

        XCTAssertFalse(
            controller.isStatusItemVisible,
            "Should hide status item after prefs change"
        )
    }

    // MARK: - 双 prefs 变化 (不重复创建 / 不重复拆)

    func test_rapidPrefsChanges_matchesPrefs() {
        AppPreferences.shared.showStatusItem = true
        let controller = makeController()

        // 多次 toggle — 每次 toggle 不会创建/拆多余 status item
        for _ in 0..<5 {
            AppPreferences.shared.showStatusItem.toggle()
        }

        // 最终状态应该跟 prefs 一致
        let expected = AppPreferences.shared.showStatusItem
        XCTAssertEqual(controller.isStatusItemVisible, expected)
    }

    // MARK: - dismiss 显式拆

    func test_dismiss_uninstallsStatusItem() {
        AppPreferences.shared.showStatusItem = true
        let controller = makeController()
        XCTAssertTrue(controller.isStatusItemVisible)

        controller.dismiss()

        XCTAssertFalse(
            controller.isStatusItemVisible,
            "dismiss() should hide the status item"
        )
    }
}
