import AppKit
import SwiftUI
import OpenLessCore
import OpenLessHotkey
import OpenLessPersistence
import OpenLessRecorder
import OpenLessASR
import OpenLessPolish

enum OpenLessMainTab: String, CaseIterable, Identifiable {
    case home
    case history
    case dictionary
    case polish
    case help
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .history: return "历史记录"
        case .dictionary: return "词汇表"
        case .polish: return "风格"
        case .help: return "帮助中心"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "chart.line.uptrend.xyaxis"
        case .history: return "clock"
        case .dictionary: return "text.book.closed"
        case .polish: return "paintpalette"
        case .help: return "questionmark.circle"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: OpenLessMainTab

    init(selection: OpenLessMainTab = .home) {
        self.selection = selection
    }
}

struct SettingsView: View {
    @ObservedObject private var navigation: SettingsNavigationModel

    init(navigation: SettingsNavigationModel) {
        self.navigation = navigation
    }

    var body: some View {
        HStack(spacing: 14) {
            FixedSidebar(selection: $navigation.selection)
            Group {
                switch navigation.selection {
                case .home: HomeTab()
                case .history: HistoryTab()
                case .dictionary: DictionaryTab()
                case .polish: StyleTab()
                case .help: HelpTab()
                case .settings: SettingsHubTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // 右栏顶部留点空白，避免内容贴到 title bar 区域。
            .padding(.top, 12)
        }
        // 左/下/右用相等 12pt；上方为 0，让侧边栏顶边贴窗口顶，
        // 红绿灯（系统画在 title bar 层）就自然落在侧边栏的圆角矩形内部。
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .background(WindowCanvasBackground())
        .frame(minWidth: 1040, minHeight: 700)
    }
}

private struct FixedSidebar: View {
    @Binding var selection: OpenLessMainTab
    @State private var stats = SidebarStatsSnapshot.load()
    // 圆角 22pt：和系统窗口外圆角 ~10pt 形成"放大同心"感（同弧形、内小外大）。
    private let sidebarShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("OpenLess")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("自然说话，完美书写")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            // 顶部内卡片预留 36pt：让 OpenLess 标题落在红绿灯下方。
            .padding(.top, 36)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 10)
            // 内卡片再上移到红绿灯之下；侧边栏顶边到内卡片顶边的可见距离 ~10pt。
            .padding(.top, 10)
            .padding(.bottom, 8)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: 8) {
                        ForEach(OpenLessMainTab.allCases) { tab in
                            Button {
                                selection = tab
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: tab.symbol)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(selection == tab ? Color.blue : .secondary)
                                        .frame(width: 22)
                                    Text(tab.title)
                                        .font(.system(size: 14, weight: selection == tab ? .semibold : .regular))
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(selection == tab ? .primary : .secondary)
                                .background(
                                    selection == tab ? Color.blue.opacity(0.10) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .help(tab.title)
                        }
                    }

                    SidebarUsageCard(stats: stats)
                    SidebarConnectionCard(stats: stats)

                    VStack(alignment: .leading, spacing: 7) {
                        Label("右 Option 开始录音", systemImage: "keyboard")
                        Label("Esc 取消", systemImage: "escape")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 264)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(sidebarShape)
        .glassPanel(cornerRadius: 22)
        .contentShape(sidebarShape)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessHistoryChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessDictionaryChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessCredentialsChanged)) { _ in refresh() }
    }

    private func refresh() {
        stats = SidebarStatsSnapshot.load()
    }
}

private struct WindowCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.035),
                    Color.clear,
                    Color.accentColor.opacity(0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct SidebarUsageCard: View {
    let stats: SidebarStatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("今日概览", systemImage: "chart.bar.xaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stats.sessionCountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            MiniUsageChart(values: stats.chartValues)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SidebarMetricBox(title: "时长", value: stats.durationText, symbol: "waveform")
                SidebarMetricBox(title: "总字数", value: "\(stats.totalCharacters)", symbol: "number")
                SidebarMetricBox(title: "每分钟", value: "\(stats.charactersPerMinute)", symbol: "speedometer")
                SidebarMetricBox(title: "词条", value: "\(stats.dictionaryCount)", symbol: "text.book.closed")
            }
        }
        .padding(13)
        .glassPanel(cornerRadius: 20)
    }
}

private struct SidebarConnectionCard: View {
    let stats: SidebarStatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SidebarConnectionRow(title: "ASR", detail: stats.hasVolcCredentials ? "已配置" : "待配置", ok: stats.hasVolcCredentials)
            SidebarConnectionRow(title: "润色", detail: stats.hasArkCredentials ? "已配置" : "原文兜底", ok: stats.hasArkCredentials)
        }
        .padding(13)
        .glassPanel(cornerRadius: 20)
    }
}

private struct SidebarMetricBox: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .glassPanel(cornerRadius: 15)
    }
}

private struct SidebarConnectionRow: View {
    let title: String
    let detail: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(ok ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 13)
    }
}

private struct MiniUsageChart: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(height: max(8, 44 * value))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(height: 66)
        .glassPanel(cornerRadius: 15)
    }
}

private struct SidebarStatsSnapshot {
    let totalSeconds: Double
    let totalCharacters: Int
    let charactersPerMinute: Int
    let dictionaryCount: Int
    let hasVolcCredentials: Bool
    let hasArkCredentials: Bool
    let chartValues: [Double]
    let sessionCount: Int

    var durationText: String {
        if totalSeconds < 60 {
            return "\(Int(totalSeconds.rounded())) 秒"
        }
        return String(format: "%.1f 分", totalSeconds / 60)
    }

    var sessionCountText: String {
        "\(sessionCount) 次"
    }

    static func load() -> SidebarStatsSnapshot {
        let sessions = HistoryStore().recent(limit: 100)
        let totalCharacters = sessions.reduce(0) { $0 + $1.finalText.count }
        let actualMs = sessions.compactMap(\.durationMs).reduce(0, +)
        let totalSeconds = actualMs > 0 ? Double(actualMs) / 1000 : Double(totalCharacters) / 240 * 60
        let charactersPerMinute = totalSeconds > 0 ? Int((Double(totalCharacters) / totalSeconds * 60).rounded()) : 0
        let recentCounts = Array(sessions.prefix(7).reversed()).map { Double(max($0.finalText.count, 1)) }
        let maxCount = recentCounts.max() ?? 1
        let chartValues = recentCounts.isEmpty ? Array(repeating: 0.18, count: 7) : recentCounts.map { $0 / maxCount }
        let vault = CredentialsVault.shared

        return SidebarStatsSnapshot(
            totalSeconds: totalSeconds,
            totalCharacters: totalCharacters,
            charactersPerMinute: charactersPerMinute,
            dictionaryCount: DictionaryStore().enabledEntries().count,
            hasVolcCredentials: isFilled(vault.get(CredentialAccount.volcengineAppKey)) && isFilled(vault.get(CredentialAccount.volcengineAccessKey)),
            hasArkCredentials: isFilled(vault.get(CredentialAccount.arkApiKey)),
            chartValues: chartValues,
            sessionCount: sessions.count
        )
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
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if secure && !revealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 390)

            if secure {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(revealed ? "隐藏密钥" : "显示密钥")
            }

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

private func polishModeHint(_ mode: PolishMode) -> String {
    switch mode {
    case .raw: return "尽量忠实转写，只做基础标点和必要分句。"
    case .light: return "去掉明显口癖和重复，尽量保留原句式和语气。"
    case .structured: return "整理句子、段落和列表，适合 prompt 与笔记。"
    case .formal: return "适合邮件、工作沟通和正式文档。"
    }
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
                // 边线半透明压到 0.04 + lineWidth 0.5：避免侧边栏外圈出现明显灰带。
                .overlay(shape.strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
                // 阴影 radius 从 16 → 6：侧边栏顶 padding=0 时不会再被裁出黑色矩形带。
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
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
                SettingsRow(title: "启用词汇表") {
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

// MARK: - Home

private struct HomeTab: View {
    @State private var sessions: [DictationSession] = []
    @State private var dictionaryEntries: [DictionaryEntry] = []
    private let history = HistoryStore()
    private let dictionary = DictionaryStore()

    var body: some View {
        SettingsPage(
            title: "首页",
            subtitle: "用个人输入记录展示口述时长、总字数、平均每分钟字数和节省时间。"
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                MetricTile(title: "口述时长", value: formattedDuration(totalSpeakingSeconds), symbol: "waveform")
                MetricTile(title: "总字数", value: "\(totalCharacters) 字", symbol: "number")
                MetricTile(title: "平均每分钟", value: "\(Int(spokenCharsPerMinute.rounded())) 字", symbol: "speedometer")
                MetricTile(title: "估算节省", value: formattedDuration(savedTypingSeconds), symbol: "keyboard.badge.clock")
                MetricTile(title: "速度提升", value: String(format: "%.1fx", speedLift), symbol: "bolt.fill")
                MetricTile(title: "启用词条", value: "\(enabledDictionaryCount) 个", symbol: "text.book.closed")
            }

            GlassSection(title: "最近效果", symbol: "sparkles") {
                if sessions.isEmpty {
                    Text("完成几次语音输入后，这里会展示口述速度、节省打字时间和词汇表建议记录。")
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
                                Text("后期模型已参考 \(session.dictionaryEntryCount ?? 0) 个词汇表词条进行语义判断")
                                    .font(.footnote)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
            }

            GlassSection(title: "词汇表展示", symbol: "text.book.closed") {
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

            GlassSection(title: "今日概览", symbol: "chart.bar.xaxis") {
                MiniUsageChart(values: chartValues)
                    .padding(.vertical, 6)
            }

            GlassSection(title: "风格", symbol: "paintpalette") {
                HStack(spacing: 12) {
                    Image(systemName: UserPreferences.shared.polishEnabled ? "checkmark.circle.fill" : "pause.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(UserPreferences.shared.polishEnabled ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(UserPreferences.shared.polishEnabled ? UserPreferences.shared.polishMode.displayName : "已关闭")
                            .font(.system(size: 14, weight: .semibold))
                        Text(UserPreferences.shared.polishEnabled
                             ? polishModeHint(UserPreferences.shared.polishMode)
                             : "识别后会直接插入原文，不调用 Ark 润色。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
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

    private var chartValues: [Double] {
        let recent = Array(sessions.prefix(7).reversed()).map { Double(max($0.finalText.count, 1)) }
        let maxCount = recent.max() ?? 1
        return recent.isEmpty ? Array(repeating: 0.18, count: 7) : recent.map { $0 / maxCount }
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
    @State private var editingEntry: DictionaryEntry?
    @State private var isShowingEditor = false
    @State private var input: String = ""
    @State private var hoveredID: UUID?
    @State private var showsClearConfirm = false
    private let store = DictionaryStore()

    var body: some View {
        SettingsPage(
            title: "词汇表",
            subtitle: "在识别前告诉模型可能出现的词——包括模型不认识的生词、新词或专业词汇。同时进入 ASR 热词与后期模型上下文。"
        ) {
            GlassSection(title: "易错词", symbol: "text.book.closed") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Spacer()
                        Button(action: resetHits) {
                            Label("重置统计", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                        .disabled(!hasHits)

                        Button(action: { showsClearConfirm = true }) {
                            Text("清除全部")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(entries.isEmpty)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        TextField("输入词语，每行一个…", text: $input, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)

                        Button(action: addFromInput) {
                            Label("添加", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(width: 92)
                    }

                    if entries.isEmpty {
                        Text("还没有词条。说一句包含 Claude、OpenLess 等词的话，或在上方批量输入即可。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else {
                        ChipFlow(spacing: 8, lineSpacing: 8) {
                            ForEach(entries) { entry in
                                DictionaryChip(
                                    entry: entry,
                                    hovered: hoveredID == entry.id,
                                    onHoverChanged: { isInside in
                                        if isInside {
                                            hoveredID = entry.id
                                        } else if hoveredID == entry.id {
                                            hoveredID = nil
                                        }
                                    },
                                    onTap: { beginEdit(entry) },
                                    onDelete: { delete(entry) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessDictionaryChanged)) { _ in reload() }
        .sheet(isPresented: $isShowingEditor) {
            DictionaryEditorSheet(entry: editingEntry) { entry in
                store.upsert(entry)
                NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
                reload()
            } onDelete: { id in
                store.delete(id: id)
                NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
                reload()
            }
        }
        .confirmationDialog("确定清除全部词汇？", isPresented: $showsClearConfirm, titleVisibility: .visible) {
            Button("清除全部", role: .destructive) {
                store.clearAll()
                NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可恢复。")
        }
    }

    private var hasHits: Bool {
        entries.contains { $0.hitCount > 0 }
    }

    private func reload() {
        // 命中次数高的排前面，没用过的按更新时间倒序。
        entries = store.all().sorted { lhs, rhs in
            if lhs.hitCount != rhs.hitCount { return lhs.hitCount > rhs.hitCount }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func beginEdit(_ entry: DictionaryEntry) {
        editingEntry = entry
        isShowingEditor = true
    }

    private func delete(_ entry: DictionaryEntry) {
        if hoveredID == entry.id { hoveredID = nil }
        store.delete(id: entry.id)
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        reload()
    }

    private func addFromInput() {
        let lines = input.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        var seen = Set(entries.map { $0.trimmedPhrase.lowercased() })
        for phrase in lines {
            let key = phrase.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            store.upsert(DictionaryEntry(phrase: phrase, source: .manual))
        }
        input = ""
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        reload()
    }

    private func resetHits() {
        store.resetHits()
        NotificationCenter.default.post(name: .openLessDictionaryChanged, object: nil)
        reload()
    }
}

private struct DictionaryChip: View {
    let entry: DictionaryEntry
    let hovered: Bool
    let onHoverChanged: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 6) {
                Text(entry.phrase)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Text("\(entry.hitCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5)
            )
            .opacity(entry.enabled ? 1 : 0.55)
            .contentShape(Capsule())
            .onTapGesture(perform: onTap)

            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Color.secondary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("删除")
                .offset(x: 5, y: -5)
                .transition(.opacity)
            }
        }
        .onHover(perform: onHoverChanged)
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

/// 自适应折行布局：把一组 chip 平铺并按行宽自动 wrap。
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + lineSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct DictionaryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void
    let onDelete: (UUID) -> Void
    @State private var phrase: String
    @State private var category: DictionaryEntryCategory
    @State private var notes: String
    @State private var enabled: Bool

    init(
        entry: DictionaryEntry?,
        onSave: @escaping (DictionaryEntry) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        self.onDelete = onDelete
        _phrase = State(initialValue: entry?.phrase ?? "")
        _category = State(initialValue: entry?.category ?? .aiTool)
        _notes = State(initialValue: entry?.notes ?? "")
        _enabled = State(initialValue: entry?.enabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry == nil ? "新建词条" : "编辑词条")
                    .font(.system(size: 24, weight: .semibold))
                Text("把 Claude、OpenLess、内部项目名等模型可能写错的词放进来。它会进入 ASR 热词与后期模型上下文，整句语义匹配时自动修正。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                SettingsRow(title: "标准词") {
                    TextField("Claude", text: $phrase)
                        .textFieldStyle(.roundedBorder)
                }
                DividerLine()
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
                DividerLine()
                SettingsRow(title: "启用") {
                    Toggle("用于 ASR 热词和后期语义判断", isOn: $enabled)
                        .toggleStyle(.checkbox)
                }
                DividerLine()
                SettingsRow(title: "备注") {
                    TextField("例如：AI 产品名，模型可按语义判断是否需要修正", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .glassPanel(cornerRadius: 20)

            HStack {
                if let entry {
                    Button("删除") {
                        onDelete(entry.id)
                        dismiss()
                    }
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(DictionaryEntry(
                        id: entry?.id ?? UUID(),
                        phrase: trimmed,
                        category: category,
                        notes: notes,
                        enabled: enabled,
                        source: entry?.source ?? .manual,
                        createdAt: entry?.createdAt ?? Date()
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(26)
        .frame(width: 560)
    }
}

// MARK: - Help

private struct HelpTab: View {
    var body: some View {
        SettingsPage(
            title: "帮助中心",
            subtitle: "快速上手 OpenLess、查阅快捷键、检查授权状态、跳转到文档与反馈渠道。"
        ) {
            GlassSection(title: "快速上手", symbol: "play.circle") {
                helpStep(num: 1, title: "配置火山 ASR", body: "在「火山 ASR」页面填入 APP ID 和 Access Token；没有 ASR 凭据时只能走演示模式。")
                DividerLine()
                helpStep(num: 2, title: "（可选）配置润色", body: "「润色模式」页面填入 Ark API Key 后，识别结果会按所选模式润色；不填也能用，会直接插入原文。")
                DividerLine()
                helpStep(num: 3, title: "授权辅助功能 + 麦克风", body: "首次启动会请求权限。授权后必须完全退出 OpenLess 再重新打开，全局快捷键才会生效。")
                DividerLine()
                helpStep(num: 4, title: "开始说话", body: "默认按右 Option 开始/停止录音；说完后文字自动插入到当前光标位置。Esc 取消本次。")
            }

            GlassSection(title: "快捷键速查", symbol: "keyboard") {
                helpKey("开始 / 停止录音", value: UserPreferences.shared.hotkeyTrigger.displayName)
                DividerLine()
                helpKey("取消本次录音", value: "Esc")
                DividerLine()
                helpKey("胶囊确认插入", value: "点击右侧 ✓")
            }

            GlassSection(title: "常见问题", symbol: "questionmark.bubble") {
                helpFAQ(q: "全局快捷键没反应？", a: "确认「系统设置 → 隐私与安全 → 辅助功能」里 OpenLess 已勾选；首次授权之后必须完全退出再重启 App。")
                DividerLine()
                helpFAQ(q: "胶囊一直显示「演示」？", a: "缺少火山 ASR 凭据。到「火山 ASR」页面填入 APP ID + Access Token 即可。")
                DividerLine()
                helpFAQ(q: "插入失败 / 只复制到剪贴板？", a: "目标 App 不支持 AX 写入或粘贴模拟。OpenLess 会自动降级为复制到剪贴板，按 ⌘V 粘贴即可。")
            }

            GlassSection(title: "更多", symbol: "link") {
                helpLink(title: "GitHub 仓库", url: "https://github.com/baiqing/openless")
                DividerLine()
                helpLink(title: "提交问题或建议", url: "https://github.com/baiqing/openless/issues")
            }
        }
    }

    private func helpStep(num: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(num)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    private func helpKey(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.vertical, 9)
    }

    private func helpFAQ(q: String, a: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(q).font(.system(size: 14, weight: .semibold))
            Text(a).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }

    private func helpLink(title: String, url: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let parsed = URL(string: url) {
                Link(destination: parsed) {
                    Label(url, systemImage: "arrow.up.right.square")
                        .font(.callout)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Settings Hub

/// 所有可调项汇总：录音 + 凭据（Volc ASR + Ark 润色）+ 授权 + 隐私 + 关于。
private struct SettingsHubTab: View {
    @State private var trigger: HotkeyBinding.Trigger = UserPreferences.shared.hotkeyTrigger
    @State private var hotkeyMode: HotkeyMode = UserPreferences.shared.hotkeyMode
    @State private var hasAccessibility = false
    @State private var hasMicrophone = false

    @State private var volcAppKey = ""
    @State private var volcAccessKey = ""
    @State private var volcResourceId = VolcengineCredentials.defaultResourceId
    @State private var arkApiKey = ""
    @State private var arkModelId = ArkCredentials.defaultModelId
    @State private var arkEndpoint = ArkCredentials.defaultEndpoint.absoluteString
    @State private var saved = false

    var body: some View {
        SettingsPage(
            title: "设置",
            subtitle: "录音快捷键、凭据、授权状态、隐私和版本信息全部在这里。"
        ) {
            GlassSection(title: "录音", symbol: "keyboard") {
                SettingsRow(title: "录音快捷键") {
                    Picker("触发键", selection: $trigger) {
                        ForEach(HotkeyBinding.Trigger.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
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
                SettingsRow(title: "录音方式") {
                    Picker("录音方式", selection: $hotkeyMode) {
                        ForEach(HotkeyMode.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220, alignment: .leading)
                    .onChange(of: hotkeyMode) { _, newValue in
                        UserPreferences.shared.hotkeyMode = newValue
                        NotificationCenter.default.post(name: .openLessHotkeyChanged, object: nil)
                    }
                }
                DividerLine()
                Text(hotkeyMode.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

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
                Button("保存凭据") { saveCredentials() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            GlassSection(title: "授权状态", symbol: "checkmark.seal") {
                StatusLine(title: "辅助功能", detail: hasAccessibility ? "已授权" : "未授权", ok: hasAccessibility)
                DividerLine()
                StatusLine(title: "麦克风", detail: hasMicrophone ? "已授权" : "未授权", ok: hasMicrophone)
            }

            GlassSection(title: "隐私", symbol: "lock.shield") {
                privacyRow("音频默认不保存到磁盘", symbol: "mic.slash")
                DividerLine()
                privacyRow("API Key 仅存本机 0600 权限文件", symbol: "key")
                DividerLine()
                privacyRow("历史只保存原始转写和最终文本", symbol: "doc.text")
                DividerLine()
                privacyRow("云端 ASR 会上传音频；开启 Ark 润色时上传转写文本", symbol: "icloud")
            }

            GlassSection(title: "关于", symbol: "info.circle") {
                SettingsRow(title: "版本") {
                    Text(versionString)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                DividerLine()
                SettingsRow(title: "更新") {
                    Button("检查更新…") {
                        NSApp.sendAction(#selector(UpdaterController.checkForUpdates(_:)), to: nil, from: nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onAppear { refresh() }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }

    private func refresh() {
        trigger = UserPreferences.shared.hotkeyTrigger
        hotkeyMode = UserPreferences.shared.hotkeyMode
        hasAccessibility = AccessibilityPermission.isGranted()
        hasMicrophone = MicrophonePermission.isGranted()
        let v = CredentialsVault.shared
        volcAppKey = v.get(CredentialAccount.volcengineAppKey) ?? ""
        volcAccessKey = v.get(CredentialAccount.volcengineAccessKey) ?? ""
        volcResourceId = v.get(CredentialAccount.volcengineResourceId) ?? VolcengineCredentials.defaultResourceId
        arkApiKey = v.get(CredentialAccount.arkApiKey) ?? ""
        arkModelId = v.get(CredentialAccount.arkModelId) ?? ArkCredentials.defaultModelId
        arkEndpoint = v.get(CredentialAccount.arkEndpoint) ?? ArkCredentials.defaultEndpoint.absoluteString
    }

    private func saveCredentials() {
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

    private func privacyRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Style (was Polish)

/// 风格 Tab：参考 LazyTyper 风格页 — 顶部启用开关 + 4 个模式卡片网格。
/// 选中卡片得绿色顶 stroke + 标题前 ✓；样例文本固定，仅作示意。
private struct StyleTab: View {
    @State private var enabled = UserPreferences.shared.polishEnabled
    @State private var mode: PolishMode = UserPreferences.shared.polishMode

    var body: some View {
        SettingsPage(
            title: "风格",
            subtitle: "为不同场景配置输出风格。每个风格包含 AI 润色与文本优化设置。"
        ) {
            HStack {
                Spacer()
                Toggle("启用", isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .onChange(of: enabled) { _, newValue in
                        UserPreferences.shared.polishEnabled = newValue
                    }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(PolishMode.allCases, id: \.self) { m in
                    StyleCard(
                        mode: m,
                        selected: mode == m,
                        enabled: enabled,
                        onSelect: {
                            mode = m
                            UserPreferences.shared.polishMode = m
                        }
                    )
                }
            }
            .opacity(enabled ? 1 : 0.55)
            .allowsHitTesting(enabled)
        }
        .onAppear {
            enabled = UserPreferences.shared.polishEnabled
            mode = UserPreferences.shared.polishMode
        }
    }
}

private struct StyleCard: View {
    let mode: PolishMode
    let selected: Bool
    let enabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                // 顶条：选中时绿色，未选中时透明
                Rectangle()
                    .fill(selected ? Color.green : Color.clear)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(selected ? Color.green : Color.green.opacity(0.45))
                            .font(.system(size: 13))
                        Text(mode.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                    Text(modeSubtitle(mode))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sampleText(mode))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.8))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.green.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func modeSubtitle(_ m: PolishMode) -> String {
        switch m {
        case .raw: return "忠实转写"
        case .light: return "去口癖保语气"
        case .structured: return "结构化整理"
        case .formal: return "正式书面"
        }
    }

    private func sampleText(_ m: PolishMode) -> String {
        switch m {
        case .raw: return "嗯那个我刚刚看了下新出的电影预告片，挺有意思的你有空也看看。"
        case .light: return "我刚看了下新出的电影预告片，挺有意思的，你有空也看看。"
        case .structured: return "刚看了新电影预告片，挺有意思的。建议有空也看一下，反馈一下你的想法。"
        case .formal: return "我刚刚观看了新电影的预告片，内容颇具新意。如有时间，建议你也观看，并分享你的看法。"
        }
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
            subtitle: "OpenLess 默认只保存必要的文本历史、词汇表和本机受保护凭据文件。"
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
    static let openLessHistoryChanged = Notification.Name("openless.history_changed")
    static let openLessHotkeyChanged = Notification.Name("openless.hotkey_changed")
    static let openLessCredentialsChanged = Notification.Name("openless.credentials_changed")
    static let openLessDictionaryChanged = Notification.Name("openless.dictionary_changed")
}
