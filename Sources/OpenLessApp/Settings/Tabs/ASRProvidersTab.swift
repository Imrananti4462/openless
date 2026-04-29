import AppKit
import SwiftUI
import OpenLessCore
import OpenLessPersistence

/// ASR Provider 设置 Tab：横向 chip 切换 active provider，下方显示当前选项的提示
/// 与"凭据填在哪里"的指引；底部一个明显的主操作「保存」按钮把 selection 持久化。
///
/// 设计要点：
/// - 状态来源是 `CredentialsVault.shared`：所有读 / 写都直接打 vault，UI 是无状态视图层。
/// - 与 `LLMProvidersTab` 的差异：ASR 各家协议字段差异大（火山 3 字段 / Apple Speech 0 字段），
///   不能像 LLM 那样共用一份表单——所以这里只承担"切 active"，具体字段：
///     * 火山引擎 → 跳「设置」Tab 的 ASR 字段段
///     * Apple Speech → 无字段，仅提示权限会被系统询问
/// - 「保存」按钮采用主操作样式（borderedProminent），让用户看见明确的提交动作。
///   切 chip 不立即写盘，避免误触；只有点击保存才会落到 credentials.json 里。
@MainActor
struct ASRProvidersTab: View {
    @StateObject private var model = ASRProvidersModel()
    @State private var saved = false

    var body: some View {
        SettingsPage(
            title: "ASR Provider",
            subtitle: "选择哪家语音识别引擎负责把你的语音转成文字。火山引擎更准但要 API key；macOS 本地 (Apple Speech) 完全离线、零配置，第一次切换时系统会请求语音识别权限。"
        ) {
            GlassSection(title: "选择 ASR", symbol: "waveform") {
                providerChips
                DividerLine()
                Text(model.helpTextForSelection)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            GlassSection(title: detailSectionTitle, symbol: detailSectionSymbol) {
                providerDetail
            }

            PrimaryActionRow {
                Button {
                    model.commitSelection()
                    flashSaved()
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.hasUnsavedChanges)

                if saved {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .onAppear { model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessCredentialsChanged)) { _ in
            model.load()
        }
    }

    // MARK: - Chip row

    private var providerChips: some View {
        HStack(spacing: 10) {
            ForEach(ASRProviderRegistry.presets, id: \.providerId) { preset in
                ASRProviderChip(
                    preset: preset,
                    isSelected: model.selectedProviderId == preset.providerId,
                    isActive: model.activeProviderId == preset.providerId,
                    onSelect: { model.selectProvider(preset.providerId) }
                )
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail section

    private var detailSectionTitle: String {
        if let preset = ASRProviderRegistry.preset(for: model.selectedProviderId) {
            return preset.displayName
        }
        return model.selectedProviderId
    }

    private var detailSectionSymbol: String {
        switch model.selectedProviderId {
        case "apple-speech": return "lock.shield"
        case "volcengine": return "key"
        default: return "info.circle"
        }
    }

    @ViewBuilder
    private var providerDetail: some View {
        switch model.selectedProviderId {
        case "apple-speech":
            appleSpeechDetail
        case "volcengine":
            volcengineDetail
        default:
            Text("未知 ASR provider：\(model.selectedProviderId)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var appleSpeechDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailLine("无需配置 API key —— Apple Speech 完全由 macOS 系统提供。", symbol: "checkmark.seal")
            detailLine("中文 (zh-CN) 在 Apple Silicon 上支持完全离线识别；其他语言或 Intel 机器会回退到 Apple 云端。", symbol: "globe")
            detailLine("第一次切换并开始录音时，系统会弹窗请求「语音识别」权限——选择允许即可。", symbol: "hand.raised.fill")
            detailLine("保存后，下一次按下录音键就会通过 Apple Speech 识别。", symbol: "play.circle.fill")
        }
        .padding(.vertical, 4)
    }

    private var volcengineDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailLine("火山引擎使用云端流式识别，准确度高，需要在控制台获取 App ID / Access Token / Resource ID。", symbol: "cloud")
            detailLine("具体凭据字段填在 「设置」Tab 的「火山引擎大模型流式 ASR」段。", symbol: "gearshape")
            detailLine("缺少凭据时本 Tab 选中火山引擎依然能保存——但下一次录音会回落到演示模式。", symbol: "exclamationmark.triangle")
        }
        .padding(.vertical, 4)
    }

    private func detailLine(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - 提示反馈

    private func flashSaved() {
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}

// MARK: - Chip

@MainActor
private struct ASRProviderChip: View {
    let preset: ASRProviderRegistry.Preset
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: chipSymbol)
                    .symbolRenderingMode(.hierarchical)
                Text(preset.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if isActive {
                    Text("当前")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.green.opacity(0.18))
                        )
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .help(preset.helpText)
    }

    private var chipSymbol: String {
        switch preset.providerId {
        case "apple-speech": return "applelogo"
        case "volcengine": return "cloud.fill"
        default: return "waveform"
        }
    }
}

// MARK: - Model

@MainActor
final class ASRProvidersModel: ObservableObject {
    @Published private(set) var configuredIds: [String] = []
    @Published private(set) var activeProviderId: String = defaultActiveASRProviderId
    @Published private(set) var selectedProviderId: String = defaultActiveASRProviderId

    /// 用户切了 chip 但还没点保存。保存按钮的 enable 状态依赖这个。
    var hasUnsavedChanges: Bool {
        selectedProviderId != activeProviderId
    }

    var helpTextForSelection: String {
        ASRProviderRegistry.preset(for: selectedProviderId)?.helpText
            ?? "未知 ASR provider；请联系开发者或检查 ~/.openless/credentials.json。"
    }

    func load() {
        let vault = CredentialsVault.shared
        configuredIds = vault.configuredASRProviderIds
        activeProviderId = vault.activeASRProviderId
        // 第一次加载或 active 不在列表里时，selectedProviderId 跟随 active；
        // 用户切换过 selected 后保留用户选择直到保存或离开。
        if !configuredIds.contains(selectedProviderId) {
            selectedProviderId = activeProviderId
        }
    }

    func selectProvider(_ providerId: String) {
        selectedProviderId = providerId
    }

    /// 把当前 selection 写回 vault；触发凭据变更通知，让 DictationCoordinator 等订阅方刷新缓存。
    func commitSelection() {
        let vault = CredentialsVault.shared
        guard vault.activeASRProviderId != selectedProviderId else { return }
        vault.activeASRProviderId = selectedProviderId
        activeProviderId = selectedProviderId
        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
    }
}
