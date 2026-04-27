import AppKit
import SwiftUI
import OpenLessCore
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder
import OpenLessASR
import OpenLessPolish

struct SettingsView: View {
    @State private var selection: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview, insights, dictionary, credentials, hotkey, modes, history, privacy
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "概览"
            case .insights: return "效果"
            case .dictionary: return "词典"
            case .credentials: return "凭据"
            case .hotkey: return "快捷键"
            case .modes: return "模式"
            case .history: return "历史"
            case .privacy: return "隐私"
            }
        }

        var symbol: String {
            switch self {
            case .overview: return "checklist"
            case .insights: return "chart.line.uptrend.xyaxis"
            case .dictionary: return "text.book.closed"
            case .credentials: return "key"
            case .hotkey: return "keyboard"
            case .modes: return "text.badge.checkmark"
            case .history: return "clock"
            case .privacy: return "lock.shield"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
                    .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 196, ideal: 220)
        } detail: {
            Group {
                switch selection {
                case .overview: OverviewTab()
                case .insights: InsightsTab()
                case .dictionary: DictionaryTab()
                case .credentials: CredentialsTab()
                case .hotkey: HotkeyTab()
                case .modes: ModesTab()
                case .history: HistoryTab()
                case .privacy: PrivacyTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 940, minHeight: 660)
    }
}

// MARK: - Shared

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)

                content
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .background(Color.clear)
    }
}

private struct GlassSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 24)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 138, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}

private struct DividerLine: View {
    var body: some View {
        Divider()
            .padding(.leading, 154)
    }
}

private struct StatusLine: View {
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        SettingsRow(title: title) {
            Label(detail, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

private struct PasteableCredentialField: View {
    let placeholder: String
    let secure: Bool
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 390)

            Button {
                if let value = NSPasteboard.general.string(forType: .string) {
                    text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Label("粘贴", systemImage: "doc.on.clipboard")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("从剪贴板粘贴")
        }
    }
}

private struct PrimaryActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
        .padding(.top, 4)
    }
}

private func isFilled(_ value: String?) -> Bool {
    guard let value else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private extension View {
    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        }
    }
}

// MARK: - Overview

private struct OverviewTab: View {
    @State private var hasVolcCreds = false
    @State private var hasArkCreds = false
    @State private var hasAccessibility = false
    @State private var hasMicrophone = false
    @State private var dictionaryCount = 0

    var body: some View {
        SettingsPage(
            title: "OpenLess",
            subtitle: "本地优先、低打扰、可控润色的 macOS 语音输入层。"
        ) {
            GlassSection(title: "状态", symbol: "checkmark.seal") {
                StatusLine(title: "火山引擎 ASR", detail: hasVolcCreds ? "已配置" : "缺少 App ID 或 Access Token", ok: hasVolcCreds)
                DividerLine()
                StatusLine(title: "Ark 润色", detail: hasArkCreds ? "已配置" : "未配置，识别后会直接插入原文", ok: hasArkCreds)
                DividerLine()
                StatusLine(title: "辅助功能", detail: hasAccessibility ? "已授权" : "未授权", ok: hasAccessibility)
                DividerLine()
                StatusLine(title: "麦克风", detail: hasMicrophone ? "已授权" : "未授权", ok: hasMicrophone)
            }

            GlassSection(title: "当前设置", symbol: "slider.horizontal.3") {
                SettingsRow(title: "录音快捷键") {
                    Text(UserPreferences.shared.hotkeyTrigger.displayName)
                }
                DividerLine()
                SettingsRow(title: "默认输出模式") {
                    Text(UserPreferences.shared.polishMode.displayName)
                }
                DividerLine()
                SettingsRow(title: "启用词典") {
                    Text("\(dictionaryCount) 个词条")
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        let v = CredentialsVault.shared
        hasVolcCreds = isFilled(v.get(CredentialAccount.volcengineAppKey))
            && isFilled(v.get(CredentialAccount.volcengineAccessKey))
        hasArkCreds = isFilled(v.get(CredentialAccount.arkApiKey))
        hasAccessibility = AccessibilityPermission.isGranted()
        hasMicrophone = MicrophonePermission.isGranted()
        dictionaryCount = DictionaryStore().enabledEntries().count
    }
}

// MARK: - Insights

private struct InsightsTab: View {
    @State private var sessions: [DictationSession] = []
    @State private var dictionaryEntries: [DictionaryEntry] = []
    private let history = HistoryStore()
    private let dictionary = DictionaryStore()

    var body: some View {
        SettingsPage(
            title: "自然说话，完美书写",
            subtitle: "用实际输入记录展示口述速度、节省时间、词典建议和个人词汇积累。"
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                MetricTile(title: "累计口述", value: formattedDuration(totalSpeakingSeconds), symbol: "waveform")
                MetricTile(title: "估算节省", value: formattedDuration(savedTypingSeconds), symbol: "keyboard.badge.clock")
                MetricTile(title: "平均口述", value: "\(Int(spokenCharsPerMinute.rounded())) 字/分钟", symbol: "speedometer")
                MetricTile(title: "速度提升", value: String(format: "%.1fx", speedLift), symbol: "bolt.fill")
                MetricTile(title: "词典参与", value: "\(dictionaryUsageCount) 次", symbol: "text.badge.checkmark")
                MetricTile(title: "启用词条", value: "\(enabledDictionaryCount) 个", symbol: "text.book.closed")
            }

            GlassSection(title: "最近效果", symbol: "sparkles") {
                if sessions.isEmpty {
                    Text("完成几次语音输入后，这里会展示口述速度、节省打字时间和词典建议记录。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(sessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { DividerLine() }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.createdAt, style: .time)
                                Text(session.mode.displayName)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let durationMs = session.durationMs {
                                    Text(formattedDuration(Double(durationMs) / 1000))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(session.finalText)
                                .lineLimit(2)
                            if (session.dictionaryEntryCount ?? 0) > 0 {
                                Text("后期模型已参考 \(session.dictionaryEntryCount ?? 0) 个词典词条进行语义判断")
                                    .font(.footnote)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
            }

            GlassSection(title: "词典展示", symbol: "text.book.closed") {
                if dictionaryEntries.isEmpty {
                    Text("添加 Claude、OpenLess、内部项目名等正确词后，OpenLess 会把它们注入 ASR 热词和后期模型上下文，由模型根据整句语义自动判断是否需要修正。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(dictionaryEntries.prefix(5).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { DividerLine() }
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.phrase)
                                    .font(.headline)
                                Text(entry.source.displayName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .onAppear { reload() }
    }

    private var totalCharacters: Int {
        sessions.reduce(0) { $0 + $1.finalText.count }
    }

    private var totalSpeakingSeconds: Double {
        let actual = sessions.compactMap(\.durationMs).reduce(0, +)
        if actual > 0 { return Double(actual) / 1000 }
        return Double(totalCharacters) / 240 * 60
    }

    private var savedTypingSeconds: Double {
        max(0, estimatedTypingSeconds - totalSpeakingSeconds)
    }

    private var estimatedTypingSeconds: Double {
        Double(totalCharacters) / 90 * 60
    }

    private var spokenCharsPerMinute: Double {
        guard totalSpeakingSeconds > 0 else { return 0 }
        return Double(totalCharacters) / totalSpeakingSeconds * 60
    }

    private var speedLift: Double {
        guard totalSpeakingSeconds > 0 else { return 0 }
        return estimatedTypingSeconds / totalSpeakingSeconds
    }

    private var dictionaryUsageCount: Int {
        sessions.reduce(0) { total, session in
            total + ((session.dictionaryEntryCount ?? 0) > 0 ? 1 : 0)
        }
    }

    private var enabledDictionaryCount: Int {
        dictionaryEntries.filter(\.enabled).count
    }

    private func reload() {
        sessions = history.recent(limit: 100)
        dictionaryEntries = dictionary.all()
    }

    private func formattedDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds.rounded())) 秒"
        }
        return String(format: "%.1f 分钟", seconds / 60)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .glassPanel(cornerRadius: 22)
    }
}

// MARK: - Dictionary

private struct DictionaryTab: View {
    @State private var entries: [DictionaryEntry] = []
    @State private var selectedID: UUID?
    @State private var phrase = ""
    @State private var category: DictionaryEntryCategory = .aiTool
    @State private var notes = ""
    @State private var enabled = true
    @State private var saved = false
    private let store = DictionaryStore()

    var body: some View {
        SettingsPage(
            title: "词典",
            subtitle: "把 Claude、OpenLess、内部项目名等正确词放进词典。ASR 会优先识别；后期模型会根据整句语义自动判断是否需要修正。"
        ) {
            GlassSection(title: "词条", symbol: "text.book.closed") {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        if entries.isEmpty {
                            ContentUnavailableView("还没有词条", systemImage: "text.book.closed", description: Text("先添加一个 Claude 示例。ASR 会优先识别 Claude；后期模型会根据语义判断 Cloud 是否应为 Claude。"))
                                .frame(maxWidth: .infinity, minHeight: 230)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(entries) { entry in
                                        DictionaryRow(entry: entry, selected: selectedID == entry.id)
                                            .onTapGesture { select(entry) }
                                    }
                                }
                            }
                            .frame(minHeight: 260, maxHeight: 330)
                        }

                        HStack {
                            Button("Claude 示例") { addClaudeExample() }
                            Button("新建") { clearForm() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(width: 310)

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow(title: "标准词") {
                            TextField("Claude", text: $phrase)
                                .textFieldStyle(.roundedBorder)
                        }
                        SettingsRow(title: "分类") {
                            Picker("分类", selection: $category) {
                                ForEach(DictionaryEntryCategory.allCases, id: \.self) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 180, alignment: .leading)
                        }
                        SettingsRow(title: "启用") {
                            Toggle("用于 ASR 热词和后期语义判断", isOn: $enabled)
                                .toggleStyle(.checkbox)
                        }
                        SettingsRow(title: "备注") {
                            TextField("例如：AI 产品名，模型可按语义判断是否需要修正", text: $notes, axis: .vertical)
                                .lineLimit(2...5)
                                .textFieldStyle(.roundedBorder)
                        }

                        PrimaryActionRow {
                            Button("删除") { deleteSelected() }
                                .disabled(selectedID == nil)
                            Button("保存词条") { saveEntry() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                                .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if saved {
                                Label("已保存", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            GlassSection(title: "工作方式", symbol: "arrow.triangle.2.circlepath") {
                dictionaryStep("ASR 阶段", "把启用词条的标准词传入火山 ASR context.hotwords，优先让识别结果靠近正确专有名词。")
                DividerLine()
                dictionaryStep("后期模型", "把同一批正确词包裹进模型上下文，要求模型根据整句语义自动判断：明确是误识别就修正，明确是其他真实概念就保留。")
                DividerLine()
                dictionaryStep("自动学习", "每次完成输入后，OpenLess 会从结果中学习像 Claude、ChatGPT、OpenLess 这样的专有词，后续作为候选正确词参与识别。")
            }
        }
        .onAppear { reload() }
    }

    private func dictionaryStep(_ title: String, _ body: String) -> some View {
        SettingsRow(title: title) {
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reload() {
        entries = store.all()
        if let selectedID, let selected = entries.first(where: { $0.id == selectedID }) {
            select(selected)
        }
    }

    private func select(_ entry: DictionaryEntry) {
        selectedID = entry.id
        phrase = entry.phrase
        category = entry.category
        notes = entry.notes
        enabled = entry.enabled
    }

    private func clearForm() {
        selectedID = nil
        phrase = ""
        category = .aiTool
        notes = ""
        enabled = true
    }

    private func saveEntry() {
        let entry = DictionaryEntry(
            id: selectedID ?? UUID(),
            phrase: phrase,
            category: category,
            notes: notes,
            enabled: enabled,
            source: selectedID.flatMap { id in entries.first(where: { $0.id == id })?.source } ?? .manual
        )
        store.upsert(entry)
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        saved = true
        reload()
        selectedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { saved = false }
    }

    private func deleteSelected() {
        guard let selectedID else { return }
        store.delete(id: selectedID)
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        clearForm()
        reload()
    }

    private func addClaudeExample() {
        phrase = "Claude"
        category = .aiTool
        notes = "AI 产品名；后期模型会根据整句语义判断是否需要把误识别内容修正为 Claude。"
        enabled = true
        selectedID = nil
        saveEntry()
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.enabled ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.phrase)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.category.displayName)
                    Text(entry.source.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Credentials

private struct CredentialsTab: View {
    @State private var volcAppKey = ""
    @State private var volcAccessKey = ""
    @State private var volcResourceId = VolcengineCredentials.defaultResourceId
    @State private var arkApiKey = ""
    @State private var arkModelId = ArkCredentials.defaultModelId
    @State private var arkEndpoint = ArkCredentials.defaultEndpoint.absoluteString
    @State private var saved = false

    var body: some View {
        SettingsPage(
            title: "凭据",
            subtitle: "凭据只写入本机受保护文件，不写入仓库、日志或公开配置。"
        ) {
            GlassSection(title: "火山引擎大模型流式 ASR", symbol: "waveform") {
                SettingsRow(title: "APP ID") {
                    PasteableCredentialField(placeholder: "X-Api-App-Key", secure: false, text: $volcAppKey)
                }
                DividerLine()
                SettingsRow(title: "Access Token") {
                    PasteableCredentialField(placeholder: "X-Api-Access-Key", secure: true, text: $volcAccessKey)
                }
                DividerLine()
                SettingsRow(title: "Resource ID") {
                    PasteableCredentialField(placeholder: "X-Api-Resource-Id", secure: false, text: $volcResourceId)
                }
                DividerLine()
                Text("当前接口使用 APP ID、Access Token 和 Resource ID。Secret Key 只在 HMAC 或旧接口场景中使用，OpenLess 不会发送它。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }

            GlassSection(title: "Ark / DeepSeek V3.2 润色", symbol: "wand.and.stars") {
                SettingsRow(title: "API Key") {
                    PasteableCredentialField(placeholder: "Bearer Token", secure: true, text: $arkApiKey)
                }
                DividerLine()
                SettingsRow(title: "Model ID") {
                    PasteableCredentialField(placeholder: "Model ID", secure: false, text: $arkModelId)
                }
                DividerLine()
                SettingsRow(title: "Endpoint") {
                    PasteableCredentialField(placeholder: "Endpoint", secure: false, text: $arkEndpoint)
                }
            }

            PrimaryActionRow {
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        let v = CredentialsVault.shared
        volcAppKey = v.get(CredentialAccount.volcengineAppKey) ?? ""
        volcAccessKey = v.get(CredentialAccount.volcengineAccessKey) ?? ""
        volcResourceId = v.get(CredentialAccount.volcengineResourceId) ?? VolcengineCredentials.defaultResourceId
        arkApiKey = v.get(CredentialAccount.arkApiKey) ?? ""
        arkModelId = v.get(CredentialAccount.arkModelId) ?? ArkCredentials.defaultModelId
        arkEndpoint = v.get(CredentialAccount.arkEndpoint) ?? ArkCredentials.defaultEndpoint.absoluteString
    }

    private func save() {
        let v = CredentialsVault.shared
        try? v.set(volcAppKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAppKey)
        try? v.set(volcAccessKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineAccessKey)
        try? v.set(volcResourceId.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.volcengineResourceId)
        try? v.set(arkApiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.arkApiKey)
        try? v.set(arkModelId.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.arkModelId)
        try? v.set(arkEndpoint.trimmingCharacters(in: .whitespacesAndNewlines), for: CredentialAccount.arkEndpoint)
        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}

// MARK: - Hotkey

private struct HotkeyTab: View {
    @State private var trigger: HotkeyBinding.Trigger = UserPreferences.shared.hotkeyTrigger

    var body: some View {
        SettingsPage(
            title: "快捷键",
            subtitle: "按一次开始录音，再按一次结束；录音中按 Esc 取消。"
        ) {
            GlassSection(title: "录音", symbol: "keyboard") {
                SettingsRow(title: "触发键") {
                    Picker("触发键", selection: $trigger) {
                        ForEach(HotkeyBinding.Trigger.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                    .onChange(of: trigger) { _, newValue in
                        UserPreferences.shared.hotkeyTrigger = newValue
                        NotificationCenter.default.post(name: .openLessHotkeyChanged, object: nil)
                    }
                }

                DividerLine()

                Text("现在按下触发键时会立即弹出录音状态，不再等到松开后才显示。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 9)

                if trigger == .fn {
                    Label("Fn / Globe 可能被系统听写或表情面板占用；如果冲突，建议改用右 Option。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                }
            }
        }
    }
}

// MARK: - Modes

private struct ModesTab: View {
    @State private var current: PolishMode = UserPreferences.shared.polishMode

    var body: some View {
        SettingsPage(
            title: "输出模式",
            subtitle: "选择识别后默认使用的文本整理方式。"
        ) {
            GlassSection(title: "默认模式", symbol: "text.badge.checkmark") {
                Picker("模式", selection: $current) {
                    ForEach(PolishMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: current) { _, newValue in
                    UserPreferences.shared.polishMode = newValue
                }

                DividerLine()

                Text(modeHint(current))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    private func modeHint(_ mode: PolishMode) -> String {
        switch mode {
        case .raw: return "尽量忠实转写，只做基础标点和必要分句。"
        case .light: return "去掉明显口癖和重复，尽量保留原句式和语气。"
        case .structured: return "整理句子、段落和列表，适合 prompt 与笔记。"
        case .formal: return "适合邮件、工作沟通和正式文档。"
        }
    }
}

// MARK: - History

private struct HistoryTab: View {
    @State private var sessions: [DictationSession] = []
    private let store = HistoryStore()

    var body: some View {
        SettingsPage(
            title: "历史",
            subtitle: "最近的识别结果只保存在本机。"
        ) {
            PrimaryActionRow {
                Button("刷新") { reload() }
                Button("清空") { store.clear(); reload() }
            }

            if sessions.isEmpty {
                ContentUnavailableView("还没有历史记录", systemImage: "clock", description: Text("完成一次语音输入后会显示在这里。"))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                GlassSection(title: "最近记录", symbol: "clock") {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { DividerLine() }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.createdAt, style: .time)
                                Text(session.mode.displayName)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(session.insertStatus.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(session.finalText)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        sessions = store.recent(limit: 100)
    }
}

// MARK: - Privacy

private struct PrivacyTab: View {
    var body: some View {
        SettingsPage(
            title: "隐私",
            subtitle: "OpenLess 默认只保存必要的文本历史、词典和本机受保护凭据文件。"
        ) {
            GlassSection(title: "本机", symbol: "lock.shield") {
                privacyRow("音频默认不保存到磁盘", symbol: "mic.slash")
                DividerLine()
                privacyRow("API Key 仅存本机 0600 权限文件", symbol: "key")
                DividerLine()
                privacyRow("历史只保存原始转写和最终文本", symbol: "doc.text")
            }

            GlassSection(title: "云端", symbol: "icloud") {
                privacyRow("使用云端 ASR 时，音频会发送给火山引擎", symbol: "waveform")
                DividerLine()
                privacyRow("开启 Ark 润色时，转写文本会发送给 Ark", symbol: "wand.and.stars")
            }
        }
    }

    private func privacyRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

extension Notification.Name {
    static let openLessHotkeyChanged = Notification.Name("openless.hotkey_changed")
    static let openLessCredentialsChanged = Notification.Name("openless.credentials_changed")
    static let openLessDictionaryChanged = Notification.Name("openless.dictionary_changed")
}
