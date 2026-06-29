import AppKit
import Carbon

// MARK: - 全局热键服务
//
// 接管 AppDelegate 里的 Carbon EventHotKey 注册 + handler 派发。
// 当前配置: ⌥M = 显示主窗口。
//
// 为什么不用 SwiftUI .keyboardShortcut — 那个只在 app 激活时有效, 全局热键
// 需要 Carbon 的 EventHotKey API (macOS 老的 hotkey 路子)。
//
// 设计: 每 AppDelegate 一份 (跟 WindowController 模式一致, 不是单例)。
// AppDelegate 在 applicationDidFinishLaunching 里 new HotKeyController,
// 注入 handler closure。控制器跟 app 同生命周期, 不需要 unregister (app 退
// OS 回收一切)。
//
// Carbon C 回调的 closure 持有: 用 Box<T> 包装 + Unmanaged.passRetained。
// 不用 unsafeBitCast 把 raw pointer 强转回 AppDelegate 实例 — 那种做法
// 跟具体 class 耦合, callback 一旦 type-pun 错位就 crash。这里 Box 稳定
// 持有 closure, callback 里 unbox + DispatchQueue.main.async 派发。
@MainActor
final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?

    /// "MSPM" (Missing++ PinYin) — Carbon hotkey signature, 4 字符 OSType。
    /// 全局唯一, 跟其他可能的 hotkey 区分 (理论上其他 app 也用类似 OSType)。
    private static let signature: OSType = 0x4D53504D

    /// 预定义 / 自定义热键。AppDelegate 用 enum case, 不用直接碰 Carbon 常数
    /// (`kVK_ANSI_M` / `optionKey` 等), 这样 AppDelegate 可以不 import Carbon。
    enum Spec {
        case optionM
        case custom(keyCode: UInt32, modifiers: UInt32)

        // internal (不是 fileprivate) 是为了让 MissingPlusPlusTests 测 — test
        // 直接调 spec.carbonKeyCode / carbonModifiers 验 Spec enum 映射
        var carbonKeyCode: UInt32 {
            switch self {
            case .optionM: return UInt32(kVK_ANSI_M)
            case .custom(let keyCode, _): return keyCode
            }
        }
        var carbonModifiers: UInt32 {
            switch self {
            case .optionM: return UInt32(optionKey)
            case .custom(_, let modifiers): return modifiers
            }
        }
    }

    /// 注册全局热键。init 立即注册, 不需要单独 start/stop。
    /// - Parameters:
    ///   - spec: 预定义 (`.optionM`) 或自定义 (`.custom(...)`) 热键
    ///   - onTrigger: Carbon callback 在 main actor 上调用 (内部已 DispatchQueue.main.async)
    init(
        spec: Spec,
        onTrigger: @escaping () -> Void
    ) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Box 持有 closure — Carbon C 回调通过 Unmanaged 拿到 box, unbox 后调 value()
        let userData = Unmanaged.passRetained(Box(onTrigger)).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let box = Unmanaged<Box<() -> Void>>.fromOpaque(userData)
                    .takeUnretainedValue()
                // Carbon 回调在它自己的 thread, 不能直接动 AppKit / SwiftUI
                DispatchQueue.main.async {
                    box.value()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            nil
        )
        RegisterEventHotKey(
            spec.carbonKeyCode,
            spec.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    /// Box 持有任意 T — 让 Swift closure 在 C 回调里稳定访问。
    /// 这里 Box<() -> Void> 是单用途的, 但用泛型 Box 避免每个 closure 类型
    /// 都要 new 一个 wrapper class。
    private final class Box<T> {
        let value: T
        init(_ value: T) { self.value = value }
    }
}
