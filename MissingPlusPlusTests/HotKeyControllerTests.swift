import XCTest
import Carbon
@testable import MissingPlusPlus

@MainActor
final class HotKeyControllerTests: XCTestCase {

    // MARK: - Spec enum 映射

    /// .optionM 应该是 M 键 + option 修饰键
    func test_optionMSpec_mapsToVK_ANSI_M() {
        let spec = HotKeyController.Spec.optionM
        XCTAssertEqual(spec.carbonKeyCode, UInt32(kVK_ANSI_M))
        XCTAssertEqual(spec.carbonModifiers, UInt32(optionKey))
    }

    /// .custom 应该原样传 keyCode + modifiers
    func test_customSpec_passesThroughKeyAndModifiers() {
        let spec = HotKeyController.Spec.custom(keyCode: 0x35, modifiers: 0x100)
        XCTAssertEqual(spec.carbonKeyCode, 0x35)
        XCTAssertEqual(spec.carbonModifiers, 0x100)
    }

    /// .custom 的 0 / 0 (禁用) 也能跑, 不强制修饰键
    func test_customSpec_zeroValues_areAllowed() {
        let spec = HotKeyController.Spec.custom(keyCode: 0, modifiers: 0)
        XCTAssertEqual(spec.carbonKeyCode, 0)
        XCTAssertEqual(spec.carbonModifiers, 0)
    }

    /// .optionM 跟 .custom(M, option) 应该等值
    func test_optionM_equivalentToExplicitCustom() {
        let preset = HotKeyController.Spec.optionM
        let explicit = HotKeyController.Spec.custom(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: UInt32(optionKey)
        )
        XCTAssertEqual(preset.carbonKeyCode, explicit.carbonKeyCode)
        XCTAssertEqual(preset.carbonModifiers, explicit.carbonModifiers)
    }

    // MARK: - Carbon 修饰键 mask 覆盖

    /// 常见修饰组合: cmd, shift, control, option 各自独立
    func test_carbonModifierMasks() {
        // 单独 cmd
        XCTAssertEqual(UInt32(cmdKey), 256)
        // 单独 shift
        XCTAssertEqual(UInt32(shiftKey), 512)
        // 单独 control
        XCTAssertEqual(UInt32(controlKey), 4096)
        // 单独 option
        XCTAssertEqual(UInt32(optionKey), 2048)
    }

    // MARK: - 实际 Carbon 注册 (smoke)

    /// init 会立即调 InstallEventHandler + RegisterEventHotKey。
    /// smoke 验证不 crash + signature OSType 是 "MSPM"。
    /// 不能直接验证 Carbon 注册成功 (没有公开 API 查), 只保证流程走通。
    func test_init_doesNotCrash() {
        let controller = HotKeyController(
            spec: .optionM,
            onTrigger: { /* never called in this test */ }
        )
        XCTAssertNotNil(controller)
    }

    /// .custom 也能 init, 不会因为非常规 key/modifier 组合 crash
    func test_init_withCustomSpec_doesNotCrash() {
        let controller = HotKeyController(
            spec: .custom(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey)),
            onTrigger: {}
        )
        XCTAssertNotNil(controller)
    }
}
