import XCTest
@testable import MissingPlusPlus

@MainActor
final class ActiveStateControllerTests: XCTestCase {

    // MARK: - debounce 行为

    func test_singleActivation_firesOnce() {
        let exp = expectation(description: "main window raised")
        let controller = ActiveStateController(
            debounce: 0.05,
            activationDelay: 0.01,
            onShouldRaiseMainWindow: { exp.fulfill() }
        )
        // 第一次激活
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        wait(for: [exp], timeout: 1.0)
        _ = controller  // 防止 unused warning
    }

    func test_rapidActivations_onlyFirstFires() {
        var callCount = 0
        let exp = expectation(description: "exactly one fire")
        exp.expectedFulfillmentCount = 1
        let controller = ActiveStateController(
            debounce: 1.0,  // 大 debounce 让后续激活都被吞掉
            activationDelay: 0.01,
            onShouldRaiseMainWindow: {
                callCount += 1
                exp.fulfill()
            }
        )

        // 5 次激活紧贴着发, 只第一次应该 fire
        for _ in 0..<5 {
            NotificationCenter.default.post(
                name: NSApplication.didBecomeActiveNotification, object: nil
            )
        }
        wait(for: [exp], timeout: 1.0)

        // 等一会儿确认没有二次 fire
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(callCount, 1, "Expected 1 fire, got \(callCount)")
        }
        _ = controller
    }

    func test_activationAfterDebounceWindow_firesAgain() {
        var callCount = 0
        let exp = expectation(description: "two fires")
        exp.expectedFulfillmentCount = 2
        let controller = ActiveStateController(
            debounce: 0.1,
            activationDelay: 0.01,
            onShouldRaiseMainWindow: {
                callCount += 1
                exp.fulfill()
            }
        )

        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        // 等过 debounce 窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: NSApplication.didBecomeActiveNotification, object: nil
            )
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(callCount, 2)
        _ = controller
    }

    // MARK: - delay 行为

    func test_activationDelay_delaysDispatch() {
        let exp = expectation(description: "delayed fire")
        let startTime = Date()
        let controller = ActiveStateController(
            debounce: 0.5,
            activationDelay: 0.2,
            onShouldRaiseMainWindow: {
                let elapsed = Date().timeIntervalSince(startTime)
                XCTAssertGreaterThanOrEqual(elapsed, 0.2, "Should wait at least activationDelay")
                exp.fulfill()
            }
        )
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        wait(for: [exp], timeout: 1.0)
        _ = controller
    }
}
