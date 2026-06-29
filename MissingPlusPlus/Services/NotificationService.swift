import AppKit
import UserNotifications

// MARK: - 通知服务
//
// 接管 AppDelegate 里"记录新建 → 系统通知"的所有逻辑:
//   - UNUserNotificationCenter authorization 申请
//   - title 拼装 ("想念 {who}")
//   - 复制 mood PNG 到 tmp 沙盒外 (sandbox 直接 attach bundle URL 会被拒)
//   - body 走 AIService.generateAINotificationBody (AI 失败自动 fallback)
//   - submit UNNotificationRequest
//
// 单例模式: 跟 MissingStore / AppPreferences / StorageService / AIService 一致。
// AppDelegate 在 handleMissingAdded 收到 MissingStoreDidAdd 时调用本服务,
// 不再自己持通知发送代码。
//
// 不做:
//   - 不持 MissingStore / AppPreferences 引用 — 它们是数据源, 服务是无状态投递
//   - 不写"通知到达后做什么" — 那是 SwiftUI 视图层 (SettingsView 显示最近通知)
//   - 不发"系统通知权限被拒"的二级提示 — 静默失败, 用户在 Settings 看状态
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// 记录新建 → 系统通知。auth 弹一次(macOS 系统去重), body 走 AI 生成,
    /// 失败 fallback 到固定模板, attach 当前 mood 的菜单栏 PNG 作为通知图标。
    func postRecordNotification(for missing: Missing) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let who = missing.who.isEmpty ? "TA" : missing.who
        let title = "想念 \(who)"
        let attachment = Self.makeMoodAttachment(for: missing.mood)
        let identifier = "missing-\(missing.id.uuidString)"

        // body 走 AI。AI 关闭/超时/出错 → AIServiceContext.fixedNotificationBody
        // 自动 fallback 到原来的固定模板,用户无感。
        // 1.5s timeout (AIService 内部写死) → 通知最多延迟 1.5s,仍比用户感知快。
        Task { @MainActor in
            let body = await generateAINotificationBody(for: missing)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let attachment {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    /// 复制 mood 的菜单栏 PNG 到 tmp 目录,再 attach。
    /// sandbox 下直接 attach `Bundle.main.url` 会被系统拒 (B6 跨容器),
    /// 复制到 `NSTemporaryDirectory` 后用副本路径就 OK。
    ///
    /// `internal static` (不是 private) 是为了给 MissingPlusPlusTests 测 —
    /// 测试直接调 `NotificationService.makeMoodAttachment(for:)` 验文件
    /// 复制 + attachment 创建,不依赖 UNUserNotificationCenter 投递链路。
    internal static func makeMoodAttachment(for mood: Mood) -> UNNotificationAttachment? {
        let name = "MenuBarIcon-\(mood.rawValue)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("missingpp-mood-\(UUID().uuidString).png")
        try? FileManager.default.copyItem(at: url, to: tmp)
        return try? UNNotificationAttachment(
            identifier: "mood-\(mood.rawValue)",
            url: tmp,
            options: nil
        )
    }
}
