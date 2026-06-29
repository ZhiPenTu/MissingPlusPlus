import XCTest
import AppKit
@testable import MissingPlusPlus

@MainActor
final class MenuBuilderTests: XCTestCase {

    // MARK: - 顶层结构

    func test_build_returnsMenuWithCorrectTopLevelStructure() {
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onQuit: {}
        )
        let menu = builder.build(recentWhos: [])

        // 5 mood items + separator + 在主窗口记录 + separator + 退出 = 9
        XCTAssertEqual(menu.items.count, 9, "Expected 9 top-level items")

        // 5 个 mood item 都是 disabled submenu parent
        for i in 0..<5 {
            let moodItem = menu.items[i]
            XCTAssertNotNil(moodItem.submenu, "Mood item \(i) should have submenu")
        }

        // 退出是最后一个 item
        let quitItem = menu.items[8]
        XCTAssertEqual(quitItem.title, "退出 心安日记")
        XCTAssertEqual(quitItem.keyEquivalent, "q")
    }

    func test_build_emptyRecentWhos_moodSubmenuHasHint() {
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onQuit: {}
        )
        let menu = builder.build(recentWhos: [])
        let happyItem = menu.items[0]
        let happySub = happyItem.submenu

        XCTAssertNotNil(happySub)
        XCTAssertEqual(happySub?.items.count, 3, "Hint + separator + 在主窗口记录")

        // 第一个 item 是 disabled hint
        let hint = happySub?.items[0]
        XCTAssertEqual(hint?.title, "(还没有记录过对象)")
        XCTAssertFalse(hint?.isEnabled ?? true)
    }

    func test_build_withRecentWhos_moodSubmenuHasWhoItems() {
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onQuit: {}
        )
        let whos = ["苏苏", "妈", "前同事"]
        let menu = builder.build(recentWhos: whos)
        let happyItem = menu.items[0]
        let happySub = happyItem.submenu

        // 3 个 who + separator + 在主窗口记录 = 5
        XCTAssertEqual(happySub?.items.count, 5)

        // 每个 who item 都有自己的 intensity submenu
        for i in 0..<3 {
            let whoItem = happySub?.items[i]
            XCTAssertEqual(whoItem?.title, whos[i])
            XCTAssertNotNil(whoItem?.submenu, "Who item should have intensity submenu")
        }
    }

    // MARK: - intensity 三档

    func test_intensitySubmenu_hasAllThreeLevels() {
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onQuit: {}
        )
        let menu = builder.build(recentWhos: ["苏苏"])
        let whoItem = menu.items[0].submenu?.items[0]
        let intensitySub = whoItem?.submenu

        XCTAssertEqual(intensitySub?.items.count, 3, "mild + strong + none")

        // 顺序: mild → strong → none (mild 最常用, Return 直接 = 默认强度)
        XCTAssertEqual(intensitySub?.items[0].title, Intensity.mild.label)
        XCTAssertEqual(intensitySub?.items[1].title, Intensity.strong.label)
        XCTAssertEqual(intensitySub?.items[2].title, Intensity.none.label)
    }

    // MARK: - representedObject 序列化

    func test_intensityItem_representedObject_carriesTriple() {
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onQuit: {}
        )
        let menu = builder.build(recentWhos: ["苏苏"])
        let mildItem = menu.items[0].submenu?.items[0].submenu?.items[0]

        // 用 Mirror / 直接 key access 验证 (fileprivate struct)
        // 通过 description 验证它有 mood / who / intensity 三个值
        let desc = String(describing: mildItem?.representedObject)
        XCTAssertTrue(desc.contains("mood: MissingPlusPlus.Mood"))
        XCTAssertTrue(desc.contains("who: \"苏苏\""))
        XCTAssertTrue(desc.contains("intensity: MissingPlusPlus.Intensity"))
    }

    // MARK: - onQuit 配置

    /// Quit item 的 action 指向 MenuActionRouter.quitFromMenu, target 是 router。
    /// 不实际 fire (避免 NSApp.terminate 把测试进程杀掉) — 只验 item 配置正确。
    func test_quitItem_hasActionAndTarget() {
        let builder = MenuBuilder(
            onRecord: { _, _, _ in },
            onOpenMain: {},
            onQuit: {}
        )
        let menu = builder.build(recentWhos: [])
        let quitItem = menu.items[8]
        XCTAssertNotNil(quitItem.action, "Quit should have an @objc action selector")
        XCTAssertNotNil(quitItem.target, "Quit should have a target")
    }
}
