import Foundation
import AppKit

// MARK: - Notifications

extension Notification.Name {
    /// Posted by `UpdateChecker` when remote version > local. userInfo:
    ///   "version": String (e.g. "0.0.2")
    ///   "url": URL (GitHub release html_url)
    static let didFindRemoteUpdate = Notification.Name("UpdateCheckerDidFindRemoteUpdate")

    /// Posted by `AppDelegate` after receiving `.didFindRemoteUpdate`. `MenuBarContent`
    /// subscribes via `.onReceive` to mount the banner overlay. userInfo same as above.
    static let showUpdateBanner = Notification.Name("UpdateCheckerShowUpdateBanner")
}

// MARK: - Result

enum UpdateCheckResult: Equatable {
    case upToDate(localVersion: String)
    case updateAvailable(version: String, url: URL)
    case failed(reason: String)
}

// MARK: - URLSession protocol (for test injection)

protocol URLSessionProtocol {
    func data(from url: URL) async throws -> (Data, URLResponse)
}
extension URLSession: URLSessionProtocol {}

// MARK: - UpdateChecker

/// 跟 NotificationService.shared / MissingStore.shared 一样是单例。
/// 不持有 controller 引用,只发 notification。
///
/// - App launch 后 5s 调 `startBackgroundCheck()` (静默,走 6h 节流)
/// - 状态栏 "Check for Updates…" item 调 `checkNow()` (手动,不走节流)
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let session: URLSessionProtocol
    private let prefs: AppPreferences
    private let githubURL: URL
    private let checkLock = NSLock()

    init(
        session: URLSessionProtocol = URLSession.shared,
        prefs: AppPreferences = .shared,
        githubURL: URL = URL(string: "https://api.github.com/repos/ZhiPenTu/MissingPlusPlus/releases/latest")!
    ) {
        self.session = session
        self.prefs = prefs
        self.githubURL = githubURL
    }

    // (performCheck / checkNow / startBackgroundCheck added in Tasks 4-7)
}
