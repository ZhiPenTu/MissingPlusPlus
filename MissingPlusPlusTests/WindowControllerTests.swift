import XCTest
import AppKit
@testable import MissingPlusPlus

@MainActor
final class WindowControllerTests: XCTestCase {

    // MARK: - 主窗口创建

    func test_showMainWindow_createsWindowWithExpectedTitle() {
        _ = WindowController()
        // 通过 NSApp.windows 找到新窗口
        let windows = NSApp.windows.filter { $0.title == "心安日记" }
        XCTAssertGreaterThanOrEqual(windows.count, 1, "Should have at least one 心安日记 window")
    }

    func test_showMainWindowTwice_doesNotCrash() {
        let controller = WindowController()
        controller.showMainWindow()
        // 第二次应该是 "bring to front" 路径, 不创建新窗口
        controller.showMainWindow()

        let windows = NSApp.windows.filter { $0.title == "心安日记" }
        XCTAssertGreaterThanOrEqual(windows.count, 1)
    }

    // MARK: - 设置窗口创建

    func test_settingsWindowNotification_createsWindowWithExpectedTitle() {
        _ = WindowController()
        NotificationCenter.default.post(name: .openSettings, object: nil)
        // NotificationCenter.post 同步派发, observer 同步执行
        let windows = NSApp.windows.filter { $0.title == "心安日记 设置" }
        XCTAssertGreaterThanOrEqual(windows.count, 1, "Should have at least one 心安日记 设置 window")
    }

    func test_settingsWindowTwice_doesNotCrash() {
        _ = WindowController()
        NotificationCenter.default.post(name: .openSettings, object: nil)
        NotificationCenter.default.post(name: .openSettings, object: nil)

        let windows = NSApp.windows.filter { $0.title == "心安日记 设置" }
        XCTAssertGreaterThanOrEqual(windows.count, 1)
    }
}
