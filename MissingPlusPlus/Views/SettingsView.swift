import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// macOS settings window content. Replaces the `EmptyView()` that used to
/// live in the `Settings` scene, so `Cmd+,` and the menu bar's
/// "Settings…" entry point at a real, themed page.
///
/// Sections:
///   * 存储位置 — current path, iCloud badge, "更改…" / "恢复默认" buttons.
///   * 状态栏 — 是否在状态栏显示图标、图标样式（心形 / Emoji / 思字）。
///   * 数据 — import / export / clear-all (clear-all is gated by a
///     confirmation alert).
///
/// All file I/O is delegated to `StorageService`; this view only
/// orchestrates AppKit open/save panels and confirms.
struct SettingsView: View {
    @ObservedObject var store: MissingStore
    @ObservedObject var storage: StorageService
    @ObservedObject var prefs = AppPreferences.shared

    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var showingClearConfirm: Bool = false

    var body: some View {
        Form {
            storageSection
            menuBarSection
            dataSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 600)
        .alert("清空所有记录？", isPresented: $showingClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearAll()
                setStatus("已清空所有记录。", error: false)
            }
        } message: {
            Text("这会删除当前存储位置里的所有 \(store.items.count) 条记录，且无法撤销。建议先导出备份。")
        }
    }

    // MARK: - 状态栏

    private var menuBarSection: some View {
        Section {
            Toggle("在状态栏显示图标", isOn: $prefs.showStatusItem)
            Picker("图标样式", selection: $prefs.menuBarIconStyle) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } header: {
            Text("状态栏")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("关闭后可通过 ⌘, 重新打开设置，或用 Dock / ⌥M 打开主窗口。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("💡 找不到图标？macOS 26 会把菜单栏 app 的图标默认藏在 Apple menu 或 ControlCenter 日期后面。**按住 Cmd 把那个小图标拖到任意位置**即可，位置会自动记住。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 存储位置

    private var storageSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: storage.isOniCloud ? "icloud.fill" : "internaldrive")
                    .foregroundColor(storage.isOniCloud ? .blue : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(storage.currentURL.deletingLastPathComponent().path)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack(spacing: 4) {
                        if storage.isOniCloud {
                            Label("iCloud Drive", systemImage: "icloud")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else if storage.isCustom {
                            Text("自定义位置")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("默认位置")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(store.items.count) 条记录")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Button {
                    pickNewStorageLocation()
                } label: {
                    Label("更改…", systemImage: "folder.badge.gearshape")
                }
                if storage.isCustom {
                    Button {
                        storage.resetToDefault(currentItems: store.items)
                        store.reloadFromDisk()
                        setStatus("已恢复到默认位置。", error: false)
                    } label: {
                        Label("恢复默认", systemImage: "arrow.uturn.backward")
                    }
                }
                Spacer()
                Button {
                    revealInFinder()
                } label: {
                    Label("在访达中显示", systemImage: "magnifyingglass")
                }
                .help("打开当前存储位置所在的文件夹")
            }
        } header: {
            Text("存储位置")
        } footer: {
            Text("把数据放在 iCloud Drive 文件夹下可以自动同步到其他 Mac，避免单台机器损坏时丢失记录。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section {
            HStack(spacing: 8) {
                Button {
                    exportData()
                } label: {
                    Label("导出数据…", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    importData()
                } label: {
                    Label("导入数据…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)

            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                Label("清空所有记录", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(store.items.isEmpty)
        } header: {
            Text("数据")
        } footer: {
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(statusIsError ? .red : .green)
            } else {
                Text("导入时会按记录 ID 去重，已存在的记录会被跳过。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("\(AppInfo.shortVersion) (\(AppInfo.buildNumber))")
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            HStack {
                Text("数据文件")
                Spacer()
                Text(storage.currentURL.lastPathComponent)
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("关于")
        }
    }

    // MARK: - Actions

    private func pickNewStorageLocation() {
        let panel = NSOpenPanel()
        panel.title = "选择存储位置"
        panel.message = "选一个文件夹用来保存 missings.json。推荐选 iCloud Drive 下的文件夹，这样多台 Mac 之间会自动同步。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let newFile = url.appendingPathComponent("missings.json", isDirectory: false)
        let existing = FileManager.default.fileExists(atPath: newFile.path)

        if existing {
            // The new folder already has data — we have to decide what to
            // do with the existing records. Don't silently overwrite.
            let alert = NSAlert()
            alert.messageText = "目标位置已有数据"
            alert.informativeText = "目标文件夹里已经有一个 missings.json 文件。\n\n请选择怎么处理现有数据："
            alert.addButton(withTitle: "用目标位置的数据")
            alert.addButton(withTitle: "合并到当前数据")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .informational
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Use the new location as-is. Drop the current in-memory
                // data; it will be reloaded from the new path.
                storage.setStorageURL(url, copyCurrentData: [])
                store.reloadFromDisk()
                setStatus("已切换到目标位置的数据。", error: false)
            case .alertSecondButtonReturn:
                // Merge: bring the new file's records into the current
                // store, dedup by id, then point to the new path.
                if let incoming = storage.importItems(from: newFile) {
                    let added = store.merge(incoming)
                    storage.setStorageURL(url, copyCurrentData: store.items)
                    setStatus("已合并 \(added) 条新记录。", error: false)
                } else {
                    setStatus("目标位置的 missings.json 解析失败，未做改动。", error: true)
                }
            default:
                return
            }
        } else {
            // Empty new location: copy current data over so the move
            // behaves like a "move, not a delete".
            storage.setStorageURL(url, copyCurrentData: store.items)
            store.reloadFromDisk()
            setStatus("已切换到新位置，旧数据已一起搬过来。", error: false)
        }
    }

    private func revealInFinder() {
        let url = storage.currentURL
        // If the file doesn't exist yet, reveal the parent directory
        // instead of failing.
        let target = FileManager.default.fileExists(atPath: url.path)
            ? url
            : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.title = "导出数据"
        panel.nameFieldStringValue = StorageService.suggestedExportFilename()
        if let json = UTType("public.json") {
            panel.allowedContentTypes = [json]
        }
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let dest = panel.url else { return }
        if storage.exportItems(store.items, to: dest) {
            setStatus("已导出 \(store.items.count) 条记录到 \(dest.lastPathComponent)。", error: false)
        } else {
            setStatus("导出失败，请检查目标路径是否可写。", error: true)
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.title = "导入数据"
        panel.message = "选一个之前导出的 JSON 文件。会按记录 ID 去重，已存在的记录会被跳过。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let json = UTType("public.json") {
            panel.allowedContentTypes = [json]
        }

        guard panel.runModal() == .OK, let src = panel.url else { return }
        guard let incoming = storage.importItems(from: src) else {
            setStatus("文件解析失败，请确认是 Missing++ 导出的 JSON。", error: true)
            return
        }

        if incoming.isEmpty {
            setStatus("文件里没有可导入的记录。", error: false)
            return
        }

        let alert = NSAlert()
        alert.messageText = "导入 \(incoming.count) 条记录？"
        let existingIDs = Set(store.items.map(\.id))
        let toAdd = incoming.filter { !existingIDs.contains($0.id) }
        let skipped = incoming.count - toAdd.count
        var info = "已存在 \(skipped) 条记录会被跳过，新增 \(toAdd.count) 条。\n\n导入后总数：\(store.items.count + toAdd.count) 条。"
        if toAdd.isEmpty {
            info = "这 \(incoming.count) 条记录都已存在，没有新增。"
        }
        alert.informativeText = info
        alert.addButton(withTitle: toAdd.isEmpty ? "好" : "导入")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let added = store.merge(incoming)
            setStatus("已导入 \(added) 条新记录。", error: false)
        }
    }

    private func setStatus(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }
}
