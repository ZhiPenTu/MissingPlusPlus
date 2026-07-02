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
///   * 依恋辅助 — anxious-attachment bundle 开关。
///   * Cooldown 活动 — 内置 + 自定义。
///   * AI 增强 — OpenAI 兼容 endpoint, base-url + key + model + temperature。
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

    // AI 增强: API Key 存 Keychain,这里只做 UI 缓存。onAppear 时从 Keychain 读出来。
    @State private var apiKey: String = ""
    @State private var isTestingAI: Bool = false
    @State private var aiTestResult: AITestResult? = nil
    @State private var isCheckingUpdate: Bool = false

    enum AITestResult: Equatable {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            storageSection
            menuBarSection
            updateSection
            attachmentBundleSection
            cooldownSection
            aiSection
            dataSection
            aboutSection
        }
        .formStyle(.grouped)
        // Settings scene 窗口: 宽 560 给 section 内容更多呼吸空间, 高 1000 装
        // 6 个 section 不滚 (Cooldown 6 项 + 状态栏 / 依恋辅助 toggle 行) ,
        // 剩余 1-2 个 section 在窗口内自然 scroll。
        // **关键**: 写 height 之前先确认 Form 第一行 (section header) 的
        // y 坐标 > Settings scene title bar 高度 (实测 ~57pt) —— 否则
        // header 会跟 title bar 重叠 (旧版 720pt height 时的 bug)。
        // 不要用 minHeight/idealHeight 间接传高度 —— Settings scene 会选
        // 一个不够大的窗口把 Form 内容推到负 y (AX 实测 header 在 y=-521)。
        // 紧凑: 540x700, 用户屏幕 982pt 高度能装下, 头 3 个 section
        // (存储位置/状态栏/依恋辅助) 完整可见 + Cooldown 开头, 剩下的
        // (Cooldown 后续/AI 增强/数据/关于) 在窗口内自然 scroll。
        // 验证: form header 1 (存储位置) y=85 > title bar ~57pt, 顶部不重叠。
        .frame(width: 540, height: 700)
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

    // MARK: - 依恋辅助 (v1.x anxious-attachment bundle)

    private var updateSection: some View {
        Section {
            Toggle("自动检查更新", isOn: $prefs.updateCheckEnabled)
            Text("启动 5s 后静默检查 GitHub Releases,有新版时主窗口顶部提示。")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button("立即检查") {
                    isCheckingUpdate = true
                    Task { @MainActor in
                        let result = await UpdateChecker.shared.checkNow()
                        isCheckingUpdate = false
                        presentCheckResult(result)
                    }
                }
                .disabled(isCheckingUpdate)
                if isCheckingUpdate {
                    ProgressView().controlSize(.small)
                }
                if let last = prefs.lastCheckedAt {
                    Text("上次检查：\(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private var attachmentBundleSection: some View {
        Section {
            Toggle("高强度时弹出现实检验", isOn: $prefs.autoPromptRealityCheck)
            Toggle("新建时回访「上一条平复了吗」", isOn: $prefs.autoPromptResolveLast)
            Toggle("通知里带 trigger 信息", isOn: $prefs.notificationIncludeTriggers)
        } header: {
            Text("依恋辅助")
        } footer: {
            Text("这些工具帮助焦虑型依恋人格看见 trigger 模式、累积「浪会过去」的证据。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - AI 增强 (OpenAI 兼容 endpoint)

    /// 用 SwiftUI Form 原生 row 模式 — `TextField("label", text: ...)` 会被 Form
    /// 渲染成 "label 左, control 右" 的标准 settings row, 跟我们已有 状态栏 /
    /// 依恋辅助 section 风格一致。不要再包 labeledField HStack — 那种自定义
    /// layout 跟 Form 的列布局打架, 会出现 label 跟 input 叠加的怪样子 (上一轮截图)。
    private var aiSection: some View {
        Section {
            Toggle("启用 AI 增强", isOn: $prefs.aiEnabled)

            if prefs.aiEnabled {
                TextField("Base URL", text: $prefs.aiBaseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("sk-..."))
                    .onChange(of: apiKey) { _, newValue in
                        prefs.aiAPIKey = newValue
                    }
                TextField("模型", text: $prefs.aiModel, prompt: Text("gpt-4o-mini"))

                // 温度 = TextField + Stepper 同一行。Form 的 label 给 TextField,
                // Stepper 跟在 TextField 右边。给一个 100pt 宽的 stepper 框,
                // 防止它在 360pt 表单列里被挤变形。
                HStack(spacing: 6) {
                    TextField("温度",
                              value: $prefs.aiTemperature,
                              format: .number.precision(.fractionLength(0...2)),
                              prompt: Text("0.85"))
                    Stepper("",
                            value: $prefs.aiTemperature,
                            in: 0...2,
                            step: 0.05)
                        .labelsHidden()
                        .frame(width: 80)
                }

                Button {
                    runAITest()
                } label: {
                    HStack(spacing: 6) {
                        if isTestingAI {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("测试连接")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingAI || !prefs.aiIsConfigured)

                if let r = aiTestResult {
                    aiTestResultView(r)
                }

                if !prefs.aiIsConfigured {
                    Label("请填 Base URL 和 API Key 后再点测试连接。",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } header: {
            Text("AI 增强")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("开启后 self-compassion 文案、通知正文和「致 TA 的话」会通过你配置的 endpoint 实时生成。")
                Text("关闭时走内置文案库, 体验和之前一致。")
                Text("🔒 API Key 存 macOS Keychain, 不在 UserDefaults 也不在数据文件里。")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if apiKey.isEmpty {
                apiKey = prefs.aiAPIKey ?? ""
            }
        }
    }

    @ViewBuilder
    private func aiTestResultView(_ r: AITestResult) -> some View {
        switch r {
        case .success:
            Label("连接成功", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
        }
    }

    /// 立即检查的 NSAlert 反馈 — upToDate / updateAvailable / failed 各分支
    private func presentCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate(let local):
            let alert = NSAlert()
            alert.messageText = "已是最新"
            alert.informativeText = "当前 v\(local) 已是最新版本。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        case .updateAvailable(let version, _, let assetURL, _):
            // banner 已经在主窗口顶部挂了 (5s 后台检查触发),用户也会在
            // 状态栏手动点 Check for Updates… 时拿到 NSAlert。这里 Settings
            // 路径只 NSAlert 提示一下,UI 跟状态栏 item 一致。
            let alert = NSAlert()
            alert.messageText = "新版本 v\(version) 可用"
            alert.informativeText = assetURL == nil
                ? "用状态栏菜单的 'Check for Updates…' 跳到 release 页查看。"
                : "主窗口顶部 banner 可以点 '下载更新' 拉 DMG,或用状态栏菜单跳 release 页。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        case .failed(let reason):
            let alert = NSAlert()
            alert.messageText = "检查更新失败"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private func runAITest() {
        isTestingAI = true
        aiTestResult = nil
        Task {
            let result = await testAIConnection()
            await MainActor.run {
                isTestingAI = false
                switch result {
                case .success(let text):
                    aiTestResult = .success
                    NSLog("[Settings] AI test success: \(text)")
                case .failure(let err):
                    aiTestResult = .failure(err.localizedDescription)
                    NSLog("[Settings] AI test failed: \(err.localizedDescription)")
                }
            }
        }
    }

        // MARK: - Cooldown 活动 (v1.x self-soothing)

    @State private var newCooldownText: String = ""

    private var cooldownSection: some View {
        Section {
            ForEach(allCooldownActivities, id: \.self) { activity in
                HStack {
                    Text(activity)
                    Spacer()
                    if !CooldownActivities.defaults.contains(activity) {
                        Button {
                            removeCooldownActivity(activity)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "lock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            HStack {
                TextField("加一条你自己的…", text: $newCooldownText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCooldownActivity)
                Button("添加", action: addCooldownActivity)
                    .disabled(newCooldownText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Cooldown 活动")
        } footer: {
            Text("🔒 标记的是预定义 6 条（不能删）。你追加的可以删。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var allCooldownActivities: [String] {
        CooldownActivities.all(custom: prefs.cooldownActivities)
    }

    private func addCooldownActivity() {
        let trimmed = newCooldownText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = prefs.cooldownActivities
        if !CooldownActivities.all(custom: current).contains(trimmed) {
            current.append(trimmed)
            prefs.cooldownActivities = current
        }
        newCooldownText = ""
    }

    private func removeCooldownActivity(_ activity: String) {
        prefs.cooldownActivities.removeAll { $0 == activity }
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
            setStatus("文件解析失败，请确认是 心安日记 导出的 JSON。", error: true)
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

// MARK: - AppInfo

/// App version + build metadata. Used by Settings → About section.
/// Previously lived in PopoverOverflowMenu.swift which has been removed
/// (About / Settings / Quit entries are provided by SwiftUI's
///  app menu / Commands / Settings scene now).
enum AppInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
