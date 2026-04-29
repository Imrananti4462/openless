import AppKit
import SwiftUI
import OpenLessCore
import OpenLessPersistence

/// LLM Provider 设置 Tab：顶部 picker 切 active provider，下方表单编辑当前 provider 字段。
///
/// 设计要点：
/// - 状态来源是 `CredentialsVault.shared`：所有读 / 写都直接打 vault，UI 是无状态视图层。
/// - 表单字段编辑后用 0.5s debounce 写盘，避免每按一个键就触发文件 IO 和通知风暴。
/// - 任何写盘成功都 post `.openLessCredentialsChanged`，让 DictationCoordinator 等订阅方刷新缓存。
/// - 删除按钮在 active provider 上禁用；用户必须先切走才能删。
@MainActor
struct LLMProvidersTab: View {
    @StateObject private var model = LLMProvidersModel()
    @State private var showingAddSheet = false
    @State private var showingDeleteConfirm = false
    @State private var lastSavedFlash = false

    var body: some View {
        SettingsPage(
            title: "LLM Provider",
            subtitle: "选择哪家大模型负责把你的口述整理成最终文本。任何 OpenAI 兼容协议的供应商都能用。"
        ) {
            GlassSection(title: "当前 Provider", symbol: "wand.and.stars") {
                SettingsRow(title: "Active") {
                    activePicker
                }
                DividerLine()
                Text(activeHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            providerForm

            if lastSavedFlash {
                HStack {
                    Spacer()
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .onAppear { model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .openLessCredentialsChanged)) { _ in
            // 别的窗口 / Coordinator 改了凭据时刷新视图，避免显示过时数据。
            model.load()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLLMProviderSheet(
                isPresented: $showingAddSheet,
                existingIds: Set(model.configuredIds),
                onAdd: { providerId, displayName in
                    model.addProvider(providerId: providerId, displayName: displayName)
                    flashSaved()
                }
            )
        }
        .alert("删除此 provider？", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                model.deleteSelected()
                flashSaved()
            }
        } message: {
            Text("删除后该 provider 的 API Key、baseURL、Model 都会从本机 credentials.json 移除。")
        }
    }

    // MARK: - Active picker

    private var activePicker: some View {
        HStack(spacing: 10) {
            Picker("Provider", selection: Binding(
                get: { model.selectedProviderId },
                set: { newValue in
                    model.selectProvider(newValue)
                    flashSaved()
                }
            )) {
                ForEach(model.configuredIds, id: \.self) { id in
                    Text(model.displayName(for: id)).tag(id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 260, alignment: .leading)

            Button {
                showingAddSheet = true
            } label: {
                Label("添加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("添加另一个 LLM provider")
        }
    }

    private var activeHint: String {
        if let preset = LLMProviderRegistry.preset(for: model.selectedProviderId) {
            return "\(preset.displayName) · \(preset.defaultBaseURL.absoluteString)"
        }
        return "自定义 OpenAI 兼容 provider"
    }

    // MARK: - Provider form

    @ViewBuilder
    private var providerForm: some View {
        let preset = LLMProviderRegistry.preset(for: model.selectedProviderId)
        let isCustom = preset == nil
        let isActive = model.selectedProviderId == model.activeProviderId

        GlassSection(title: providerFormTitle, symbol: "key") {
            // Display name：自定义可改；预设给出 read-only 提示。
            SettingsRow(title: "名称") {
                if isCustom {
                    TextField("展示名", text: Binding(
                        get: { model.draft.displayName },
                        set: { newValue in
                            model.updateDisplayName(newValue)
                            flashSavedDebounced()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 390)
                } else {
                    Text(preset?.displayName ?? model.selectedProviderId)
                        .foregroundStyle(.secondary)
                }
            }
            DividerLine()

            SettingsRow(title: "API Key") {
                PasteableCredentialField(
                    placeholder: model.draft.apiKey.isEmpty ? "请填入 API Key" : "Bearer Token",
                    secure: true,
                    text: Binding(
                        get: { model.draft.apiKey },
                        set: { newValue in
                            model.updateApiKey(newValue)
                            flashSavedDebounced()
                        }
                    )
                )
            }
            DividerLine()

            SettingsRow(title: "Base URL") {
                HStack(spacing: 8) {
                    PasteableCredentialField(
                        placeholder: preset?.defaultBaseURL.absoluteString ?? "https://api.example.com/v1",
                        secure: false,
                        text: Binding(
                            get: { model.draft.baseURL },
                            set: { newValue in
                                model.updateBaseURL(newValue)
                                flashSavedDebounced()
                            }
                        )
                    )
                    if let preset, model.draft.baseURL == preset.defaultBaseURL.absoluteString || model.draft.baseURL.isEmpty {
                        baseURLDefaultBadge
                    }
                }
            }
            DividerLine()

            SettingsRow(title: "Model") {
                PasteableCredentialField(
                    placeholder: preset?.defaultModel.isEmpty == false ? preset!.defaultModel : "endpoint id / model name",
                    secure: false,
                    text: Binding(
                        get: { model.draft.model },
                        set: { newValue in
                            model.updateModel(newValue)
                            flashSavedDebounced()
                        }
                    )
                )
            }
            DividerLine()

            SettingsRow(title: "Temperature") {
                temperatureControl
            }

            if let preset {
                DividerLine()
                presetHelpDisclosure(preset)
            }
        }

        // 删除按钮独占一行，用 destructive 强调；active 时禁用并提示。
        HStack {
            Spacer()
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("删除此 provider", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(isActive)
            .help(isActive ? "当前 active provider 不能删除——先切到别的 provider" : "从本机移除该 provider 的所有字段")
        }
    }

    private var providerFormTitle: String {
        if let preset = LLMProviderRegistry.preset(for: model.selectedProviderId) {
            return preset.displayName
        }
        if !model.draft.displayName.isEmpty {
            return model.draft.displayName
        }
        return "自定义 Provider (\(model.selectedProviderId))"
    }

    private var baseURLDefaultBadge: some View {
        Text("默认")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    private var temperatureControl: some View {
        HStack(spacing: 12) {
            Slider(value: Binding(
                get: { model.draft.temperature },
                set: { newValue in
                    model.updateTemperature(newValue)
                    flashSavedDebounced()
                }
            ), in: 0.0...1.0, step: 0.05)
            .frame(width: 220)
            Text(String(format: "%.2f", model.draft.temperature))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
    }

    private func presetHelpDisclosure(_ preset: LLMProviderRegistry.Preset) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.helpText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let docsURL = preset.docsURL {
                    Button {
                        NSWorkspace.shared.open(docsURL)
                    } label: {
                        Label("打开 \(docsURL.host ?? "API Key 页")", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("怎么获取 API Key？", systemImage: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 提示反馈

    private func flashSaved() {
        lastSavedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { lastSavedFlash = false }
    }

    /// 防止"每按一个键就闪一次"——表单字段编辑用更短的 debounce。
    private func flashSavedDebounced() {
        // 模型自身已经在 0.5s debounce 之后写盘；这里仅仅控制视觉提示节奏。
        lastSavedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { lastSavedFlash = false }
    }
}

// MARK: - Model

/// LLM Providers 视图模型：管理 picker 选择 / 草稿表单 / 保存到 vault。
@MainActor
final class LLMProvidersModel: ObservableObject {
    @Published private(set) var configuredIds: [String] = []
    @Published private(set) var activeProviderId: String = defaultActiveLLMProviderId
    @Published private(set) var selectedProviderId: String = defaultActiveLLMProviderId
    @Published var draft = LLMProviderDraft()

    /// 表单 debounce：防止每按一个键就写一次 credentials.json。
    private var saveTask: Task<Void, Never>?

    func load() {
        let vault = CredentialsVault.shared
        configuredIds = vault.configuredLLMProviderIds
        activeProviderId = vault.activeLLMProviderId
        // 第一次加载或 active 不在列表里时，selectedProviderId 跟随 active；
        // 用户切换过 selected 后保留用户选择。
        if selectedProviderId.isEmpty || !configuredIds.contains(selectedProviderId) {
            selectedProviderId = activeProviderId
        }
        loadDraftFromVault()
    }

    func displayName(for providerId: String) -> String {
        if let preset = LLMProviderRegistry.preset(for: providerId) {
            return preset.displayName
        }
        // 自定义 provider：从 vault 读 displayName。
        let vault = CredentialsVault.shared
        if let cfg = vault.llmProviderConfig(for: providerId), !cfg.displayName.isEmpty {
            return cfg.displayName
        }
        return providerId
    }

    func selectProvider(_ providerId: String) {
        flushDraftIfDirty()
        selectedProviderId = providerId
        loadDraftFromVault()

        // 选 active 应该立即生效——但只有当用户选择的是已存在的 provider 时。
        let vault = CredentialsVault.shared
        if vault.activeLLMProviderId != providerId {
            vault.activeLLMProviderId = providerId
            activeProviderId = providerId
            NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        }
        configuredIds = vault.configuredLLMProviderIds
    }

    func addProvider(providerId: String, displayName: String) {
        let vault = CredentialsVault.shared
        let preset = LLMProviderRegistry.preset(for: providerId)
        let baseURL = preset?.defaultBaseURL ?? URL(string: "https://api.example.com/v1")!
        let model = preset?.defaultModel ?? ""
        let resolvedDisplayName = displayName.isEmpty ? (preset?.displayName ?? providerId) : displayName

        let cfg = OpenAICompatibleConfig(
            providerId: providerId,
            displayName: resolvedDisplayName,
            baseURL: baseURL,
            apiKey: "",
            model: model,
            extraHeaders: [:],
            temperature: 0.3
        )
        vault.setLLMProviderConfig(cfg)
        // 切到新加的 provider 让用户立即填字段。
        vault.activeLLMProviderId = providerId
        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        load()
        selectedProviderId = providerId
        loadDraftFromVault()
    }

    func deleteSelected() {
        let vault = CredentialsVault.shared
        guard selectedProviderId != activeProviderId else { return }
        do {
            try vault.removeLLMProvider(selectedProviderId)
        } catch {
            // 删除失败不阻塞 UI；下一次 load 会重新拉。
        }
        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
        load()
        selectedProviderId = activeProviderId
        loadDraftFromVault()
    }

    // MARK: - Draft 字段更新（debounce 写盘）

    func updateDisplayName(_ value: String) {
        draft.displayName = value
        scheduleSave()
    }

    func updateApiKey(_ value: String) {
        draft.apiKey = value
        scheduleSave()
    }

    func updateBaseURL(_ value: String) {
        draft.baseURL = value
        scheduleSave()
    }

    func updateModel(_ value: String) {
        draft.model = value
        scheduleSave()
    }

    func updateTemperature(_ value: Double) {
        draft.temperature = value
        scheduleSave()
    }

    // MARK: - 私有

    private func loadDraftFromVault() {
        let vault = CredentialsVault.shared
        let cfg = vault.llmProviderConfig(for: selectedProviderId)
        let preset = LLMProviderRegistry.preset(for: selectedProviderId)

        draft.displayName = cfg?.displayName ?? preset?.displayName ?? selectedProviderId
        draft.apiKey = cfg?.apiKey ?? ""
        draft.baseURL = cfg?.baseURL.absoluteString
            ?? preset?.defaultBaseURL.absoluteString
            ?? ""
        draft.model = cfg?.model ?? preset?.defaultModel ?? ""
        draft.temperature = cfg?.temperature ?? 0.3
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            self?.flushDraftIfDirty()
        }
    }

    private func flushDraftIfDirty() {
        let vault = CredentialsVault.shared
        let trimmedBaseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = LLMProviderRegistry.preset(for: selectedProviderId)
        let baseURL: URL
        if let parsed = URL(string: trimmedBaseURL), !trimmedBaseURL.isEmpty, parsed.scheme != nil {
            baseURL = parsed
        } else if let preset {
            baseURL = preset.defaultBaseURL
        } else {
            // 自定义 + 无效 baseURL：暂不写盘，等用户填完。
            return
        }

        let cfg = OpenAICompatibleConfig(
            providerId: selectedProviderId,
            displayName: draft.displayName,
            baseURL: baseURL,
            apiKey: draft.apiKey,
            model: draft.model,
            extraHeaders: [:],
            temperature: draft.temperature
        )
        vault.setLLMProviderConfig(cfg)
        NotificationCenter.default.post(name: .openLessCredentialsChanged, object: nil)
    }
}

/// 编辑中的 provider 表单字段。`OpenAICompatibleConfig` 用 URL 不允许中间态非法字符串，
/// 所以表单层用 String 草稿；保存前再 try URL。
struct LLMProviderDraft {
    var displayName: String = ""
    var apiKey: String = ""
    var baseURL: String = ""
    var model: String = ""
    var temperature: Double = 0.3
}

// MARK: - Add Provider Sheet

/// 添加 provider 的 sheet：列出所有预设 + "自定义"；选 "自定义" 时多一步收集 slug + displayName。
@MainActor
struct AddLLMProviderSheet: View {
    @Binding var isPresented: Bool
    let existingIds: Set<String>
    let onAdd: (_ providerId: String, _ displayName: String) -> Void

    @State private var customId: String = ""
    @State private var customDisplayName: String = ""
    @State private var step: Step = .pick

    enum Step {
        case pick
        case customDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(step == .pick ? "添加 LLM Provider" : "自定义 OpenAI 兼容 Provider")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                switch step {
                case .pick:
                    pickList
                case .customDetails:
                    customDetailsForm
                }
            }
            .frame(minHeight: 360, maxHeight: 480)
        }
        .frame(width: 520)
    }

    private var pickList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LLMProviderRegistry.presets, id: \.providerId) { preset in
                presetRow(preset)
                Divider().padding(.leading, 16)
            }
            customRow
        }
        .padding(.vertical, 4)
    }

    private func presetRow(_ preset: LLMProviderRegistry.Preset) -> some View {
        let alreadyAdded = existingIds.contains(preset.providerId)
        return Button {
            guard !alreadyAdded else { return }
            onAdd(preset.providerId, preset.displayName)
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(alreadyAdded ? .green : .secondary)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(preset.defaultBaseURL.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(preset.helpText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .help(alreadyAdded ? "已添加" : "添加 \(preset.displayName)")
    }

    private var customRow: some View {
        Button {
            step = .customDetails
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LLMProviderRegistry.customDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("任何遵循 OpenAI Chat Completions 协议的供应商都能填进来——比如自建网关、私有化部署、或表里没列的云厂商。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customDetailsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Provider ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("custom-gateway", text: $customId)
                    .textFieldStyle(.roundedBorder)
                Text("唯一 slug，建议小写字母 / 数字 / 短横线；不能与已存在的 id 重复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("展示名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("公司内部网关", text: $customDisplayName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("返回") {
                    step = .pick
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("添加") {
                    let id = customId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAdd(id, name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isCustomReady)
            }
            .padding(.top, 6)
        }
        .padding(20)
    }

    private var isCustomReady: Bool {
        let id = customId.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !name.isEmpty else { return false }
        // slug 不能撞预设 id 也不能撞已存在的条目。
        if LLMProviderRegistry.preset(for: id) != nil { return false }
        if existingIds.contains(id) { return false }
        return true
    }
}
