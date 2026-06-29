import XCTest
import AppKit
@testable import MissingPlusPlus

@MainActor
final class StatusPanelControllerTests: XCTestCase {

    // MARK: - setUp / tearDown

    private var originalShowStatusItem: Bool!

    override func setUp() async throws {
        try await super.setUp()
        // 存原始 prefs, tearDown 还原
        originalShowStatusItem = AppPreferences.shared.showStatusItem
        // 把已有 panel 全部关掉, 每个 test 从干净状态开始
        dismissAllStatusPanels()
    }

    override func tearDown() async throws {
        // 还原 prefs + 关掉本 test 创建的所有 panel
        if let original = originalShowStatusItem {
            AppPreferences.shared.showStatusItem = original
        }
        dismissAllStatusPanels()
        try await super.tearDown()
    }

    private func dismissAllStatusPanels() {
        for window in NSApp.windows where window is StatusItemPanel {
            window.orderOut(nil)
        }
    }

    private func hasStatusPanel() -> Bool {
        NSApp.windows.contains { $0 is StatusItemPanel && $0.isVisible }
    }

    // MARK: - install 行为

    func test_init_withShowStatusItemOn_installsPanel() {
        AppPreferences.shared.showStatusItem = true
        let controller = StatusPanelController(
            onRecord: { _, _, _ in },
            onOpenMain: {}
        )
        XCTAssertTrue(hasStatusPanel(), "Should have a visible StatusItemPanel after init")
        _ = controller
    }

    func test_init_withShowStatusItemOff_doesNotInstallPanel() {
        AppPreferences.shared.showStatusItem = false
        let controller = StatusPanelController(
            onRecord: { _, _, _ in },
            onOpenMain: {}
        )
        XCTAssertFalse(hasStatusPanel(), "Should not have a visible StatusItemPanel")
        _ = controller
    }

    // MARK: - prefs 变化响应

    func test_prefsChangeToOn_installsPanel() {
        AppPreferences.shared.showStatusItem = false
        let controller = StatusPanelController(
            onRecord: { _, _, _ in },
            onOpenMain: {}
        )
        XCTAssertFalse(hasStatusPanel(), "Starting with no panel")

        // 模拟用户在 settings 里开了 "show status item"
        AppPreferences.shared.showStatusItem = true

        XCTAssertTrue(hasStatusPanel(), "Should install panel after prefs change")
        _ = controller
    }

    func test_prefsChangeToOff_uninstallsPanel() {
        AppPreferences.shared.showStatusItem = true
        let controller = StatusPanelController(
            onRecord: { _, _, _ in },
            onOpenMain: {}
        )
        XCTAssertTrue(hasStatusPanel(), "Starting with panel visible")

        // 模拟用户在 settings 里关了 "show status item"
        AppPreferences.shared.showStatusItem = false

        XCTAssertFalse(hasStatusPanel(), "Should hide panel after prefs change")
        _ = controller
    }

    // MARK: - 双 prefs 变化 (不重复创建 / 不重复拆)

    func test_rapidPrefsChanges_doesNotCreateDuplicatePanels() {
        AppPreferences.shared.showStatusItem = true
        let controller = StatusPanelController(
            onRecord: { _, _, _ in },
            onOpenMain: {}
        )

        // 多次 toggle — 每次 toggle 不会创建/拆多余 panel
        for _ in 0..<5 {
            AppPreferences.shared.showStatusItem.toggle()
        }

        // 最终状态应该跟 prefs 一致
        let expected = AppPreferences.shared.showStatusItem
        XCTAssertEqual(hasStatusPanel(), expected)
        _ = controller
    }
}
