import SwiftUI
import AppKit

/// The small "..." menu in the popover tab bar. Exposes About + Quit and
/// acts as the only entry point to the standard About panel for a
/// LSUIElement (menu bar) app, which has no Dock icon to right-click.
struct PopoverOverflowMenu: View {
    var body: some View {
        Menu {
            Button {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationName: "Missing++",
                    .applicationVersion: AppInfo.shortVersion + " (" + AppInfo.buildNumber + ")",
                    .credits: NSAttributedString(
                        string: "思念计数器 · 本地菜单栏应用\n所有数据保存在本地 ~/Library/Application Support/MissingPlusPlus/",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ]
                    ),
                ])
            } label: {
                Text("关于 Missing++")
            }

            Button {
                // AppDelegate 监听这个 notification；这样 Cmd+, 走主菜单、
                // 这里点 "…" 走这条路径，最终都是 showSettingsWindow()。
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Text("设置… (⌘,)")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出 (⌘Q)")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 22, height: 22)
    }
}

enum AppInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
