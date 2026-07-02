import Foundation
import AppKit
import UniformTypeIdentifiers

/// URLSessionDownloadTask 包装 — 拉 GitHub release 的 .dmg 资产,带进度回调。
///
/// 关键设计:点 "下载" 时弹 NSSavePanel 让用户选保存位置 (~/Downloads 推荐)。
/// 避开 sandbox container 的 com.apple.quarantine 属性 —— 文件有 quarantine
/// 时,后续 NSWorkspace.open 会触发 "钥匙串验证" auth dialog。下载到用户
/// 选的正常位置就没这个属性,直接打开没 auth 弹窗。
@MainActor
final class UpdateDownloader: NSObject {
    static let shared = UpdateDownloader()

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    /// DMG 在用户选的位置 (via NSSavePanel)。通过 task.taskDescription 传给
    /// nonisolated delegate (避免跨 actor 访问 stored property)。
    private var destURL: URL?

    var onProgress: ((Double) -> Void)?
    var onComplete: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    /// 启动下载流程:弹 NSSavePanel → 用户选位置 → 开始下载。
    /// 用户取消 panel → 静默 return (banner 保持 available 状态,用户可重试)。
    /// 完成后通过 `onComplete(localURL)` 回调 (localURL = 用户选的位置)。
    func startDownload(assetURL: URL, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.title = "保存更新"
        panel.message = "选择 DMG 保存位置。\n推荐 ~/Downloads,可避免打开时弹钥匙串验证。"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.diskImage]
        }

        NSLog("[MissingPlusPlus] download: showing NSSavePanel")
        panel.begin { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let dest = panel.url else {
                NSLog("[MissingPlusPlus] download: user cancelled NSSavePanel, no error")
                return
            }
            NSLog("[MissingPlusPlus] download: NSSavePanel OK, dest = %@", dest.path)
            self.beginDownload(from: assetURL, to: dest)
        }
    }

    /// 内部:启动 URLSessionDownloadTask 到指定 URL。
    /// 取消任何 in-flight 任务。
    private func beginDownload(from url: URL, to destURL: URL) {
        cancel()
        self.destURL = destURL
        // 清掉旧文件
        try? FileManager.default.removeItem(at: destURL)

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        task = session?.downloadTask(with: url)
        // 把 dest 路径塞到 task description 给 nonisolated delegate。
        // 用 `destURL.path` (filesystem path, e.g. "/Users/foo/x.dmg")
        // 不用 `absoluteString` (URL-encoded, e.g. "file%3A///Users/foo/x.dmg"
        // — `:` 被 encode 成 `%3A`,delegate `URL(fileURLWithPath:)` 当
        // 字面路径读会把 DMG 存到 `file%3A/...` 的奇怪位置)。
        task?.taskDescription = destURL.path
        task?.resume()
    }

    /// 取消 in-flight 任务。被 dismiss banner / 取消 panel 时调用。
    func cancel() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

extension UpdateDownloader: URLSessionDownloadDelegate {
    /// 进度回调 — 系统在后台线程调,跳回 main actor
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor [weak self] in
            self?.onProgress?(progress)
        }
    }

    /// 下载完成 — 从系统 temp 移到 task description 里指定的 dest URL
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // dest 来自 task.taskDescription (NSSavePanel 选的路径,断电后还可访问)
        let destPath = downloadTask.taskDescription ?? ""
        let dest = URL(fileURLWithPath: destPath)
        guard !destPath.isEmpty else {
            NSLog("[MissingPlusPlus] download: missing taskDescription")
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            NSLog("[MissingPlusPlus] download: complete, saved to %@", dest.path)
            Task { @MainActor [weak self] in
                self?.onComplete?(dest)
            }
        } catch {
            NSLog("[MissingPlusPlus] download: moveItem failed: %@", error.localizedDescription)
            Task { @MainActor [weak self] in
                self?.onError?(error)
            }
        }
    }

    /// 任务级错误 (e.g. network error, 取消)
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error as NSError? else { return }
        // 取消不算错误 (用户主动 dismiss)
        if error.code == NSURLErrorCancelled { return }
        NSLog("[MissingPlusPlus] download: task error: %@", error.localizedDescription)
        Task { @MainActor [weak self] in
            self?.onError?(error)
        }
    }
}
