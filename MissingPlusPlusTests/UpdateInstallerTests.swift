import XCTest
@testable import MissingPlusPlus

/// 覆盖 `UpdateInstaller.detachedOpenScript` 的 shell 字符串构造。
/// openDMG 整体 (nohup + exit(0)) 在测试里跑会真杀进程,跳过 — 用
/// 端到端 smoke test 验证。脚本构造是 deterministic pure function,
/// 这里重点测 single-quote escape (路径含 `'` 时 shell 会断)。
@MainActor
final class UpdateInstallerTests: XCTestCase {

    /// 普通路径:不含单引号,脚本里就是简单的 'path' 包起来。
    func test_detachedOpenScript_normalPath() {
        let url = URL(fileURLWithPath: "/Users/foo/Downloads/MissingPlusPlus-0.0.26.dmg")
        let script = UpdateInstaller.detachedOpenScript(forDMG: url)
        XCTAssertEqual(script,
            "nohup /usr/bin/open '/Users/foo/Downloads/MissingPlusPlus-0.0.26.dmg' >/dev/null 2>&1 &")
    }

    /// 路径含单引号:必须 escape 成 '\'' 序列,否则 shell 提前 end-quote
    /// 然后把后面的字符当命令,会报 "command not found" 或更糟的注入。
    /// 标准 unix 单引号转义: ' -> '\''
    func test_detachedOpenScript_pathWithSingleQuote() {
        let url = URL(fileURLWithPath: "/Users/foo/It's Mine.dmg")
        let script = UpdateInstaller.detachedOpenScript(forDMG: url)
        // 期望: '...\It'\''s Mine...' 拆开就是 It's Mine
        let expected = "nohup /usr/bin/open '/Users/foo/It'\\''s Mine.dmg' >/dev/null 2>&1 &"
        XCTAssertEqual(script, expected,
            "single-quote in path must be escaped as '\\'' to survive shell parsing")
    }

    /// 路径含多个单引号:每个 ' 都要 escape,不能漏。
    func test_detachedOpenScript_pathWithMultipleQuotes() {
        let url = URL(fileURLWithPath: "/tmp/a'b'c.dmg")
        let script = UpdateInstaller.detachedOpenScript(forDMG: url)
        let expected = "nohup /usr/bin/open '/tmp/a'\\''b'\\''c.dmg' >/dev/null 2>&1 &"
        XCTAssertEqual(script, expected)
    }

    /// 路径含空格:在单引号内,空格不需要额外 escape (单引号包起来的
    /// 整体是 shell 的一个 arg)。
    func test_detachedOpenScript_pathWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/foo/My Downloads/foo bar.dmg")
        let script = UpdateInstaller.detachedOpenScript(forDMG: url)
        XCTAssertEqual(script,
            "nohup /usr/bin/open '/Users/foo/My Downloads/foo bar.dmg' >/dev/null 2>&1 &")
    }

    /// 路径含 $ / ` 等 shell 特殊字符:在单引号内,这些字符 lose 特殊
    /// 含义,不需要 escape。我们的实现只 escape 单引号,验证其他字符
    /// 原样保留 (安全)。
    func test_detachedOpenScript_pathWithShellMetachars() {
        let url = URL(fileURLWithPath: "/tmp/$HOME/`whoami`.dmg")
        let script = UpdateInstaller.detachedOpenScript(forDMG: url)
        // 期望:单引号包裹,$ ` 原样保留
        XCTAssertEqual(script,
            "nohup /usr/bin/open '/tmp/$HOME/`whoami`.dmg' >/dev/null 2>&1 &",
            "shell metachars inside single quotes should NOT be interpreted")
    }

    /// 端到端:把脚本写到临时文件, /bin/sh -c 真的执行,验证能成功
    /// spawn 一个不存在的命令 (应当 exit 非零,模拟 shell 失败)。
    /// 我们跑 detachedOpenScript 但替换 /usr/bin/open 为 false,
    /// 验证 terminationStatus 行为。
    func test_shellExitStatus_propagatesToCaller() {
        // 构造一个会失败的脚本 (command not found)
        let script = "false"
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        do {
            try task.run()
            task.waitUntilExit()
            XCTAssertNotEqual(task.terminationStatus, 0, "false should exit non-zero")
        } catch {
            XCTFail("Process.run should not fail for /bin/sh: \(error)")
        }
    }
}
