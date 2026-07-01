import AppKit

/// Renders the menu bar icon in one of three styles (heart / emoji / 思字).
/// Each style branch is responsible for cleaning up any state left over
/// from the previous style — see `AGENTS.md §15/§19` for the "切回去留残影"
/// bug this prevents. The cleanup block at the top of `apply` resets
/// `image` / `title` / `attributedTitle` / `contentTintColor` before the
/// style-specific code runs.
///
/// 现状：macOS 13-15 走官方 NSStatusItem (`StatusItemProvider` 协议里的
/// `NSStatusItemProvider`)，macOS 26+ 走 NSPanel fallback
/// (`NSPanelStatusItemProvider` — 绕过 Apple 把 NSStatusItem 路由到
/// Control Center scene 的 bug)。两套实现都通过 `image(mood:style:) ->
/// NSImage` 拿渲染好的图，不需要碰 NSImage 操作细节。三个 style 分支
/// 内部都用 lockFocus + 画图/文字，输出一致。
@MainActor
enum MenuBarIconRenderer {
    /// 18x18pt — system status bar item 实际 icon 渲染区域
    /// (NSStatusBar.squareLength=22pt cell 减 2pt 上/下 padding)。
    /// 用 NSPanel 路线后这里跟 panel 内部 view 18x18 frame 对齐。
    static let iconSize = NSSize(width: 18, height: 18)

    // MARK: - 旧接口 (apply 到 NSStatusBarButton) — 留作 fallback / 单测
    // NSStatusItem 路线如果将来要回来用，可以直接调用。MenuBarExtra 路线
    // 不调这个。

    static func apply(to button: NSStatusBarButton,
                      mood: Mood?,
                      style: MenuBarIconStyle) {
        // 1. 清上一种 style 残留 — 三种 style 共用的清场
        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.contentTintColor = nil

        let effectiveMood = mood ?? .happy
        button.image = image(mood: effectiveMood, style: style)
    }

    // MARK: - 新接口 (返回 NSImage 给 SwiftUI MenuBarExtra label)

    /// 渲染 menu bar icon 为 NSImage — 给 SwiftUI `Image(nsImage:)` 用。
    /// 三个 style 分支内部 lockFocus 画图（heart 用 SF Symbol + sourceAtop
    /// 染色，emoji / 思字用 NSAttributedString 画文字），确保输出跟旧
    /// NSStatusItem 路线像素级一致。
    static func image(mood: Mood?, style: MenuBarIconStyle) -> NSImage {
        let effectiveMood = mood ?? .happy
        let image = NSImage(size: iconSize)
        // 必须设 transparent background — NSImage 默认 backgroundColor 是
        // 黑色 (Gamma 2.2 colorspace 0 0)，lockFocus 之前不透明化会让
        // SF Symbol / 文字以外的区域渲染成黑色方框（在 light vibrancy
        // 下显示成浅色方框，看起来像 panel "有 box outline"）。
        image.backgroundColor = .clear
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: iconSize)
        switch style {
        case .heart:
            drawHeart(in: rect, mood: effectiveMood)
        case .emoji:
            drawText(in: rect, text: effectiveMood.emoji, font: emojiFont())
        case .character:
            drawText(in: rect, text: "思", font: characterFont(), color: nsColor(for: effectiveMood))
        }
        return image
    }

    // MARK: - 字体

    private static func emojiFont() -> NSFont {
        // AGENTS.md §18: 必须显式 AppleColorEmoji，否则 SF Pro 给 0 宽占位
        NSFont(name: "AppleColorEmoji", size: 14) ?? NSFont.systemFont(ofSize: 14)
    }

    private static func characterFont() -> NSFont {
        NSFont.systemFont(ofSize: 17, weight: .semibold)
    }

    // MARK: - 画图

    /// SF Symbol heart.fill + lockFocus + sourceAtop 染色（AGENTS.md §14 验证路径）
    private static func drawHeart(in rect: NSRect, mood: Mood) {
        guard let base = NSImage(systemSymbolName: "heart.fill",
                                 accessibilityDescription: "心安日记") else {
            // SF Symbol 拿不到时降级到 emoji（避免 cell 空掉）
            drawText(in: rect, text: mood.emoji, font: emojiFont())
            return
        }
        let color = nsColor(for: mood)
        color.set()
        // 把 SF Symbol 缩放到 iconSize (18x18) — 不用 base.size (默认 51x51
        // 会让 heart 看起来比 system status bar icon 大很多)
        base.size = iconSize
        base.draw(in: rect, from: NSRect(origin: .zero, size: iconSize),
                  operation: .sourceOver, fraction: 1.0)
        rect.fill(using: .sourceAtop)
    }

    /// NSAttributedString 居中画文字
    private static func drawText(in rect: NSRect, text: String, font: NSFont, color: NSColor = .labelColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        // 文字 baseline 调整: 居中
        let textSize = str.size()
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.minY + (rect.height - textSize.height) / 2,
            width: rect.width,
            height: textSize.height
        )
        str.draw(in: drawRect)
    }

    // MARK: - 5 mood 颜色

    private static func nsColor(for mood: Mood) -> NSColor {
        switch mood {
        case .happy:     return NSColor(red: 1.00, green: 0.78, blue: 0.34, alpha: 1.0)
        case .joyful:    return NSColor(red: 0.43, green: 0.86, blue: 0.51, alpha: 1.0)
        case .delighted: return NSColor(red: 0.91, green: 0.12, blue: 0.39, alpha: 1.0)
        case .sad:       return NSColor(red: 0.36, green: 0.48, blue: 0.60, alpha: 1.0)
        case .longing:   return NSColor(red: 0.61, green: 0.45, blue: 0.81, alpha: 1.0)
        }
    }
}
