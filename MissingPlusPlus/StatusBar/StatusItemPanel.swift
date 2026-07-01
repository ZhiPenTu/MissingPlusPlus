import AppKit

// MARK: - Floating Status Panel (macOS 26+ fallback)
//
// macOS 26 把 NSStatusItem 路由到 `com.apple.controlcenter:...-Aux[1]-NSStatusItemView`
// scene, 主菜单栏看不到 (log 多次确认: 即使 .regular / .accessory / 沙盒 on/off 都是
// 同样 routing; 其他 app (cmux / cc-switch) work, 但本 app 在这台机器上必然 routing)。
//
// `NSPanelStatusItemProvider` 在 macOS 26+ 用这个, 绕开 routing 直接在状态栏画一个
// 22x22 浮动 button。`level = .statusBar` 盖在 system status bar 之上,
// `nonactivatingPanel` 不抢焦点, `canJoinAllSpaces` 全屏能看到。
//
// 渲染走 MenuBarIconRenderer (heart / emoji / 思字 × 5 mood 染色)。
//
// **macOS < 26 不走这条**, 走官方 NSStatusItem (AppKit 接管 click / drag /
// ⌘-drag 重排 / accessibility / dark mode)。
final class StatusItemView: NSView {
    weak var clickTarget: AnyObject?
    var clickSelector: Selector?
    private let imageView = NSImageView()
    private var dragStartLocation: NSPoint = .zero
    /// 拖动结束回调 — provider 把 panel.frame.origin.x 写进 UserDefaults
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
            if let target = clickTarget, let sel = clickSelector {
                _ = target.perform(sel, with: self)
            }
        } else {
            onDragEnd?()
        }
    }
}

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
