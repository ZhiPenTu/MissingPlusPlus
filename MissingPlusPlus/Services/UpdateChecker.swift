import Foundation
import AppKit

// MARK: - Notifications

extension Notification.Name {
    /// Posted by `UpdateChecker` when remote version > local. userInfo:
    ///   "version": String (e.g. "0.0.2")
    ///   "url": URL (GitHub release html_url)
    static let didFindRemoteUpdate = Notification.Name("UpdateCheckerDidFindRemoteUpdate")

    /// Posted by `AppDelegate` after receiving `.didFindRemoteUpdate`. `MenuBarContent`
    /// subscribes via `.onReceive` to mount the banner overlay.
    /// userInfo:
    ///   "version": String
    ///   "htmlURL": URL  (GitHub release page)
    ///   "assetURL": URL? (DMG direct download, nil if release has no .dmg)
    ///   "sizeBytes": Int? (DMG size for display)
    static let showUpdateBanner = Notification.Name("UpdateCheckerShowUpdateBanner")

    /// Posted by `UpdateDownloader` during download. userInfo:
    ///   "progress": Double (0.0 - 1.0)
    static let updateDownloadProgress = Notification.Name("UpdateCheckerDownloadProgress")

    /// Posted by `UpdateDownloader` on success. userInfo:
    ///   "localURL": URL (path to downloaded DMG in app's container)
    static let updateDownloadComplete = Notification.Name("UpdateCheckerDownloadComplete")

    /// Posted by `UpdateDownloader` on failure. userInfo:
    ///   "error": String (localizedDescription)
    static let updateDownloadError = Notification.Name("UpdateCheckerDownloadError")
}

// MARK: - Result

enum UpdateCheckResult: Equatable {
    case upToDate(localVersion: String)
    /// `assetURL` 和 `sizeBytes` 是 release 自带的 .dmg 资产 (从 `assets[]` 取)。
    /// 没有 .dmg 的 release (e.g. 只有 source code) 时 assetURL = nil,
    /// banner 只显示 "稍后 / 查看",不显示 "下载"。
    case updateAvailable(
        version: String,
        htmlURL: URL,
        assetURL: URL?,
        sizeBytes: Int?
    )
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

        // MARK: - Public API

    /// Fire-and-forget background check. Respects the toggle and the 6h throttle.
    /// Posts `.didFindRemoteUpdate` notification on positive result.
    func startBackgroundCheck() {
        guard prefs.updateCheckEnabled else { return }
        guard shouldCheckNow() else { return }
        Task { [weak self] in
            await self?.silentCheck()
        }
    }

    /// Manual check (used by status-bar "Check for Updates…" item and
    /// Settings "立即检查" button). Bypasses the 6h throttle.
    func checkNow() async -> UpdateCheckResult {
        guard prefs.updateCheckEnabled else {
            return .failed(reason: "已在设置中关闭")
        }
        checkLock.lock(); defer { checkLock.unlock() }
        let result = await performCheck()
        // 所有 check 路径 (5s 后台 / 状态栏 / Settings) 都 post .didFindRemoteUpdate,
        // AppDelegate 接力 .showUpdateBanner → MenuBarContent 挂 banner。
        if case .updateAvailable(let version, let htmlURL, let assetURL, let sizeBytes) = result {
            NSLog("[MissingPlusPlus] checkNow: posting .didFindRemoteUpdate for v%@ (assetURL=%@, sizeBytes=%@)",
                  version, assetURL?.absoluteString ?? "nil", sizeBytes.map(String.init) ?? "nil")
            var info: [String: Any] = ["version": version, "htmlURL": htmlURL]
            if let assetURL { info["assetURL"] = assetURL }
            if let sizeBytes { info["sizeBytes"] = sizeBytes }
            NotificationCenter.default.post(
                name: .didFindRemoteUpdate,
                object: self,
                userInfo: info
            )
        } else {
            NSLog("[MissingPlusPlus] checkNow: result = %@ (no banner)", String(describing: result))
        }
        return result
    }

    // MARK: - Private

    private func performCheck() async -> UpdateCheckResult {
        prefs.lastCheckedAt = Date()

        do {
            var request = URLRequest(url: githubURL)
            request.setValue("MissingPlusPlus/0.0.24 (build 15) (macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(from: githubURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                NSLog("[MissingPlusPlus] update: GitHub HTTP %d", code)
                return .failed(reason: "GitHub 返回 HTTP \(code)")
            }

            // try? 让 JSON parse 错转 nil,走我们的 fallback 文案而不是 NSError 描述
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString) else {
                NSLog("[MissingPlusPlus] update: response format unexpected")
                return .failed(reason: "响应格式不符")
            }

            // 找 .dmg 资产 (DMG browser_download_url + size for "下载 5.2 MB" UI)
            let asset = (json["assets"] as? [[String: Any]] ?? []).first { entry in
                (entry["name"] as? String)?.hasSuffix(".dmg") == true
            }
            let assetURL = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))
            let sizeBytes = asset?["size"] as? Int

            // Skip prereleases (e.g. "v0.0.2-alpha")
            if tagName.contains("-") {
                return .upToDate(localVersion: currentLocalVersion())
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let local = currentLocalVersion()

            if Self.compareSemver(remote: remoteVersion, local: local) > 0 {
                prefs.lastKnownRemoteVersion = remoteVersion
                return .updateAvailable(
                    version: remoteVersion,
                    htmlURL: htmlURL,
                    assetURL: assetURL,
                    sizeBytes: sizeBytes
                )
            } else {
                return .upToDate(localVersion: local)
            }
        } catch {
            NSLog("[MissingPlusPlus] update: %@", error.localizedDescription)
            return .failed(reason: error.localizedDescription)
        }
    }

    private func shouldCheckNow() -> Bool {
        guard let last = prefs.lastCheckedAt else { return true }
        return Date().timeIntervalSince(last) > 6 * 3600
    }

    private func silentCheck() async {
        // checkNow 内部已经会 post .didFindRemoteUpdate (统一所有路径)
        _ = await checkNow()
    }

    private func currentLocalVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Compare two semver strings segment-by-segment. Missing trailing segments
    /// are treated as 0 (so "0.1" == "0.1.0"). Non-integer segments → 0.
    /// - Returns: > 0 if remote > local; < 0 if remote < local; 0 if equal.
    static func compareSemver(remote: String, local: String) -> Int {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv - lv }
        }
        return 0
    }
}
