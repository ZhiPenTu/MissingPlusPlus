import Foundation
import AppKit

/// 打开下载好的 DMG — 之前是 `NSWorkspace.shared.open(url)`,但这有个问题:
/// app 自己还活着,用户拖 .app 去 /Applications 时 macOS 会说
/// "MissingPlusPlus 正在运行,无法替换" → 要用户手动 ⌘Q。
///
/// 修法: 启动一个 detached child process 跑 `/usr/bin/open <dmg>`,
/// 0.3s 后 NSApp.terminate 自己。detached = reparented 到 launchd (PID 1),
/// 我们死后它还活着,DMG 照常挂载。
///
/// 流程:
///  1. /bin/sh -c "nohup /usr/bin/open '<dmg>' >/dev/null 2>&1 &"
///     - nohup: 忽略 SIGHUP (defensive)
///     - &: 后台执行,shell 立刻 exit
///  2. shell exit → open process 立刻被 reparent 到 launchd
///  3. 我们 terminate → 释放 /Applications/MissingPlusPlus.app 的文件锁
///  4. 用户拖 .app → macOS 不再弹"软件正在运行"
///
/// ⚠️ Sandbox 限制: 沙盒 app 不能直接写 /Applications,所以仍然要用户拖。
/// 完全静默替换需要 privileged helper (Sparkle 那类工具的领域)。
@MainActor
enum UpdateInstaller {
    /// Open the downloaded DMG in Finder, then quit the app so the user can
    /// drag the .app to /Applications without macOS complaining that the
    /// app is in use.
    static func openDMG(at url: URL) {
        NSLog("[UpdateInstaller] openDMG: %@", url.path)

        // 1. escape 单引号 (路径里出现 ' 就 break shell)
        let escapedPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
        // nohup: 让 child 忽略 SIGHUP (我们 exit 时会发);
        // &: 后台执行,shell 立刻返回。
        // 整体 ≈ "open in background, fully detached from us"
        let script = "nohup /usr/bin/open '\(escapedPath)' >/dev/null 2>&1 &"

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]

        do {
            try task.run()
            // shell 进程会立刻 exit (& 让它不等 child)。
            // waitUntilExit 等到 shell 退出 (child open 此时已被 reparent
            // 到 launchd,跟我们无关了)。
            task.waitUntilExit()
            NSLog("[UpdateInstaller] nohup wrapper exit=%d, DMG open should be in flight", task.terminationStatus)
        } catch {
            NSLog("[UpdateInstaller] spawn /usr/bin/open failed: %@, falling back to NSWorkspace", error.localizedDescription)
            NSWorkspace.shared.open(url)
            // 失败时不退出,让用户手动关 app 再拖
            return
        }

        // 2. 给自己 0.3s 让 detached open 进程真的 exec 起来,
        //    然后 graceful quit。NSApp.terminate 会走 applicationShouldTerminate
        //    → applicationWillTerminate,UserDefaults 改动会 flush,数据安全。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSLog("[UpdateInstaller] terminating app to release /Applications lock")
            NSApp.terminate(nil)
        }
    }
}
