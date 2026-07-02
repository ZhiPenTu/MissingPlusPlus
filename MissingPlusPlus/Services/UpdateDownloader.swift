import Foundation
import AppKit

/// URLSessionDownloadTask 包装 — 拉 GitHub release 的 .dmg 资产,带进度回调。
///
/// 行为:
/// - `download(from:)` 启动下载 (替换任何 in-flight 任务)
/// - 进度通过 `onProgress` (0.0 - 1.0) 回调
/// - 完成通过 `onComplete(localURL:)` 回调
/// - 失败通过 `onError(error:)` 回调
/// - 完成后文件在 `FileManager.default.temporaryDirectory / MissingPlusPlus-update.dmg`
///
/// @MainActor 是因为 callbacks 都要碰 UI 状态;URLSession delegate 方法本身
/// 由系统调度,通过 `Task { @MainActor }` 跳回主线程。
@MainActor
final class UpdateDownloader: NSObject {
    static let shared = UpdateDownloader()

    /// 下载完成的临时文件名 (跟 progress / complete notification 的 localURL 一致)
    static let downloadFileName = "MissingPlusPlus-update.dmg"

    /// DMG 最终位置 (由 performCheck 时算,避免 stored property 跨 actor 访问)
    /// nonisolated 因为 URLSession delegate 在 background 线程调
    nonisolated private static func downloadDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(downloadFileName)
    }

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    var onProgress: ((Double) -> Void)?
    var onComplete: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    /// 启动下载。同一时间只允许一个 in-flight 任务,新调用会取消旧的。
    func download(from url: URL) {
        cancel()
        let dest = Self.downloadDestination()
        try? FileManager.default.removeItem(at: dest)

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        task = session?.downloadTask(with: url)
        task?.resume()
    }

    /// 取消 in-flight 任务 (如果有)。被 dismiss banner 时调用。
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

    /// 下载完成 — 移动到 destURL,callback
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = Self.downloadDestination()
        do {
            // 系统给的 location 是临时文件,我们要 move 到我们的 dest
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor [weak self] in
                self?.onComplete?(dest)
            }
        } catch {
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
        Task { @MainActor [weak self] in
            self?.onError?(error)
        }
    }
}
