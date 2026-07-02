import Foundation
import AppKit

/// 打开下载好的 DMG — 之前是 `NSWorkspace.shared.open(url)`,但这有个问题:
/// app 自己还活着,用户拖 .app 去 /Applications 时 macOS 会说
/// "MissingPlusPlus 正在运行,无法替换" → 要用户手动 ⌘Q。
///
/// 修法: 启动一个 detached child process 跑 `/usr/bin/open <dmg>`,
/// 1.5s 后 exit(0) 自己。detached = reparented 到 launchd (PID 1),
/// 我们死后它还活着,DMG 照常挂载。
///
/// 流程:
///  1. /bin/sh -c "nohup /usr/bin/open '<dmg>' >/dev/null 2>&1 &"
///     - nohup: 忽略 SIGHUP (defensive)
///     - &: 后台执行,shell 立刻 exit
///  2. shell exit → open process 立刻被 reparent 到 launchd
///  3. 我们 exit(0) → 释放 /Applications/MissingPlusPlus.app 的文件锁
///  4. 用户拖 .app → macOS 不再弹"软件正在运行"
///
/// 关键: 用 `exit(0)` 而不是 `NSApp.terminate(nil)`。后者走 graceful
/// 路径 (applicationShouldTerminate → applicationWillTerminate →
/// runloop 检测到 flag → 退出),0.3s 不足以保证 process 真死;前者直接
/// _exit,无回调、无 runloop,立刻释放 fd 锁。对我们的 app 是安全的:
///   - UserDefaults 由系统自动 flush
///   - missings.json 在 MissingStore.add 时已经同步落盘
///   - 没有未释放的资源
///
/// ⚠️ Sandbox 限制: 沙盒 app 不能直接写 /Applications,所以仍然要用户拖。
/// 完全静默替换需要 privileged helper (Sparkle 那类工具的领域)。
@MainActor
enum UpdateInstaller {
    /// Open the downloaded DMG in Finder, then exit the app so the user can
    /// drag the .app to /Applications without macOS complaining that the
    /// app is in use.
    static func openDMG(at url: URL) {
        NSLog("[UpdateInstaller] openDMG: %@", url.path)

        let script = detachedOpenScript(forDMG: url)
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]

        do {
            try task.run()
            // shell 进程会立刻 exit (& 让它不等 child)。
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                // shell 启动成功但执行失败 (e.g. 路径含特殊字符, single quote escape 出错,
                // /usr/bin/open 不存在)。fall back 到 NSWorkspace, 不退出,
                // 让用户手动关 app 再拖。
                NSLog("[UpdateInstaller] shell wrapper exit=%d, falling back to NSWorkspace.open",
                      task.terminationStatus)
                NSWorkspace.shared.open(url)
                return
            }
            NSLog("[UpdateInstaller] nohup wrapper exit=%d, DMG open should be in flight", task.terminationStatus)
        } catch {
            NSLog("[UpdateInstaller] spawn /bin/sh failed: %@, falling back to NSWorkspace", error.localizedDescription)
            NSWorkspace.shared.open(url)
            return
        }

        // 给自己 1.5s 让 detached open 进程真的 exec 起来,
        // 然后 exit(0) 强制退出 (不走 NSApp.terminate 的 graceful
        // 路径,确保 process 在用户拖 .app 前真死)。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSLog("[UpdateInstaller] exit(0) to release /Applications lock")
            exit(0)
        }
    }

    /// Build the nohup shell script that detaches `/usr/bin/open` from us.
    /// Extracted from `openDMG` so we can unit-test the single-quote escape
    /// (paths containing `'` would break the shell otherwise).
    ///
    /// - Returns: A shell script that can be passed to `/bin/sh -c`.
    static func detachedOpenScript(forDMG url: URL) -> String {
        // Standard single-quote escape: close quote, escaped quote, open quote.
        // 'foo'\''bar'  ->  foo'bar  when shell parses it.
        let escapedPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
        // nohup: 让 child 忽略 SIGHUP; &: 后台执行; shell 立刻返回。
        return "nohup /usr/bin/open '\(escapedPath)' >/dev/null 2>&1 &"
    }
}
