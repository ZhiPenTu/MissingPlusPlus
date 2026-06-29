import AppKit

// MARK: - Floating Status Panel
//
// macOS 26 上 NSStatusItem 默认进 Control Center 弹窗辅助区, 屏幕顶部
// 菜单栏看不到 — 不管 .regular / .accessory / autosaveName / Visible Item-N
// 怎么设都不行。绕开 NSStatusItem 路线, 直接用 NSPanel 在屏幕顶部右侧画
// 一个浮动 button: level = .statusBar (盖在 system status bar 之上)、
// nonactivatingPanel (不抢焦点)、canJoinAllSpaces (全屏也能看到)。
//
// 渲染走 MenuBarIconRenderer (heart / emoji / 思字 三种 style + 5 mood 染色),
// mood 联动通过重新 setIcon 实现。

/// `StatusItemPanel` 的内容 view, 18x18 NSImageView 装 icon。
/// 自己处理 mouseDown / mouseDragged / mouseUp 区分 click vs drag,
/// drag 结束通过 `onDragEnd` 回调通知 AppDelegate 持久化 x 坐标。
final class StatusItemView: NSView {
    weak var clickTarget: AnyObject?
    var clickSelector: Selector?
    private let imageView = NSImageView()
    private var dragStartLocation: NSPoint = .zero
    /// 拖动结束回调 — AppDelegate 那边把 panel.frame.origin.x 写进 UserDefaults
    var onDragEnd: (() -> Void)?
    /// 拖动超过这个距离才算 drag, 避免跟 click 冲突
    private let dragThreshold: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setIcon(_ image: NSImage) {
        imageView.image = image
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let current = event.locationInWindow
        // 只在超过 threshold 时才算 drag, 避免 click 误触
        if abs(current.x - dragStartLocation.x) < dragThreshold &&
           abs(current.y - dragStartLocation.y) < dragThreshold {
            return
        }
        let newOrigin = NSPoint(
            x: window.frame.origin.x + (current.x - dragStartLocation.x),
            y: window.frame.origin.y
        )
        window.setFrameOrigin(newOrigin)
        dragStartLocation = current
    }

    override func mouseUp(with event: NSEvent) {
        let moved = abs(event.locationInWindow.x - dragStartLocation.x) +
                    abs(event.locationInWindow.y - dragStartLocation.y)
        if moved < dragThreshold {
            // 没拖 — 当 click 处理
            if let target = clickTarget, let sel = clickSelector {
                _ = target.perform(sel, with: self)
            }
        } else {
            onDragEnd?()
        }
    }
}

/// 22x22 浮动 panel, 装 StatusItemView (内嵌 18x18 icon view)。
/// `level = .statusBar` 让它盖在 system status bar 之上 (跟状态栏 app icon 同层级)。
/// `nonactivatingPanel` 不抢 app 焦点, 点完不卡主窗口。
/// `canJoinAllSpaces + fullScreenAuxiliary` 让全屏 app 时也能看到。
final class StatusItemPanel: NSPanel {
    let content: StatusItemView

    init() {
        let size = NSSize(width: 22, height: 22)
        self.content = StatusItemView(frame: NSRect(x: 2, y: 2, width: 18, height: 18))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.contentView = content
    }

    func setIcon(_ image: NSImage) {
        content.setIcon(image)
    }
}
