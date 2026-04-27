# Codex 对抗性审查报告

## 1. 总体判断

当前架构能支撑 v1 主链路，但不能保证 6 个未来功能“无需主流程级重构”地引入。核心问题不是单云 provider，而是缺少一条独立于录音/ASR/润色/插入的“策略与学习平面”：模式与 prompt 没有持久身份，ASR 前没有识别提示注入点，LLM 前没有用户规则/记忆/词本/易错字注入点，Persistence 也没有可追溯的 prompt、词本、修正和长期记忆数据模型。若不在 v1 留出这些接口，未来会同时改 `DictationCoordinator`、`VolcengineStreamingASR.openSession()`、`DoubaoPolishClient.polish()`、`PolishMode`、`DictationSession` 和 SQLite schema。

## 2. CRITICAL 问题

### 2.1 模式与 prompt 被硬编码为 enum/内置模板，无法承载可编辑、可切换、可实验的 prompt

- 问题：`PolishMode: String, CaseIterable, Codable` 把“模式”当成固定枚举，`PolishPromptTemplates.swift` 把 prompt 当成模块内常量，`DictationSession.mode` 只记录枚举值；§10 又建议给 `PolishMode` 加 `.custom(id, name, prompt)`，这与 `String` raw value 和自动 `CaseIterable` 直接冲突，且历史无法知道当时使用的是哪一版 prompt。
- 触发场景（哪个未来功能暴露的）：2 自定义 prompt/mode/行为规则；4 switchable prompts 与 A/B test；1 个性化风格记忆；5 词本注入 LLM prompt；6 易错字修正规则注入 prompt。
- 现有架构文档位置：§4.1 `PolishMode`、`FinalText.mode`、`DictationSession.mode`；§4.4 `PolishPromptTemplates.swift`；§10「用户自定义润色模式」。
- 修订建议：把固定 enum 改为稳定 ID 模型：`ModeID`、`ModeDefinition`、`PromptTemplate`、`PromptRevision`、`PromptSet`。4 个 v1 模式作为 seeded records，不作为不可扩展 enum。新增表 `mode_definition`、`prompt_template`、`prompt_revision`、`prompt_experiment_assignment`；`dictation_session` 增加 `mode_id`、`prompt_revision_id`；`DoubaoPolishClient.polish` 改接收 `PolishRequest(modeID:promptRevisionID:prompt:)`，而不是从模块常量按 enum 查找。

### 2.2 缺少 DictationContext / PolicyResolver，未来能力没有统一注入点

- 问题：主链路是 `recording → streaming ASR → LLM polish → AX insertion → fallback clipboard → history`，但上下文只在 `PolishContext(appBundleId, appName)` 中出现，ASR 的 `openSession()` 没有 options 参数。未来个性化、词本、易错字、行为规则都需要在 ASR 前和 LLM 前同时注入，而不是散落在 Coordinator 的临时代码里。
- 触发场景（哪个未来功能暴露的）：1 表达习惯学习；2 行为规则；3 长期记忆；4 prompt 切换；5 词本 hot-words + prompt 注入；6 易错字优先修正。
- 现有架构文档位置：§3.1「正常输入流程」；§4.3 `VolcengineStreamingASR.openSession()`；§4.4 `PolishContext`；§10「per-app 风格规则」「个人词典提升识别准确率」。
- 修订建议：新增 `DictationContext` 与 `DictationPolicyResolver`。`DictationContext` 至少包含 `appBundleId`、`appName`、`languageHint`、`modeID`、`privacyClass`、`sessionIntent`。`DictationPolicy` 至少包含 `ASRSessionOptions(recognitionHints:)`、`PromptAssembly(modeID, promptRevisionID, fragments:)`、`BehaviorRules`、`MemoryDigest`。Coordinator 在 hotkey down 后、`ASR.openSession(options:)` 前解析一次 policy；`DoubaoPolishClient` 只消费组装后的 `PolishRequest`。

### 2.3 Persistence 只有历史表，不是可学习、可回放、可同步的长期数据层

- 问题：`DictationSession` 和 `dictation_session` 只保存 `raw_transcript`、`final_text`、`mode`、app、插入状态、错误码；没有 ASR run、polish run、prompt revision、词本 revision、易错字规则、用户反馈、派生记忆、删除血缘。未来一旦做长期学习或同步，无法解释某条输出由哪些规则产生，也无法安全回滚、重跑、清除或 A/B 对照。
- 触发场景（哪个未来功能暴露的）：1 个性化学习；3 长期持久化/跨设备同步；4 A/B prompt；5 词本效果追踪；6 易错字标注闭环。
- 现有架构文档位置：§4.1 `DictationSession`；§4.6 `HistoryStore`；§5.1 `dictation_session` schema；§10「同步 / 团队词典」。
- 修订建议：把 `HistoryStore` 降级为 UI 查询门面，新增 `SessionEventStore`、`PromptStore`、`LexiconStore`、`CorrectionStore`、`MemoryStore`。新增表 `recognition_run`、`polish_run`、`session_event`、`user_memory`、`memory_event`、`correction_annotation`、`lexicon_revision`、`sync_metadata`、`tombstone`。`dictation_session` 增加 `started_at`、`ended_at`、`duration_ms`、`language_hint`、`mode_id`、`prompt_revision_id`、`lexicon_revision_id`、`correction_revision_id`、`privacy_class`。

### 2.4 个人词本与易错字被压成一个弱 `dict_entry`，且 hot-words 归属放错层

- 问题：`dict_entry` 只有 `phrase`、`aliases_json`、`category`，无法表达权重、语言、作用域、启停、来源、最近使用、修正优先级、同步版本；§10 说“`Recorder` 启动 ASR 时把词典作为 hot words 传入”，但 `Recorder` 的职责是 PCM 采集，不应该知道 ASR hot-words，也没有 `ASRSessionOptions`。
- 触发场景（哪个未来功能暴露的）：5 个人词本；6 易错字标注；1 识别偏好学习；2 自定义词汇/行为规则。
- 现有架构文档位置：§2.3 `OpenLessRecorder` 职责；§4.2 `AudioConsumer`；§5.1 `dict_entry`；§10「个人词典提升识别准确率」。
- 修订建议：新增 `LexiconProvider` 与 `CorrectionProvider`，统一输出 `RecognitionHint(phrase, aliases, weight, language, scope, source)` 和 `PolishHint(kind: .lexicon/.correction, text:)`。ASR 层增加 `VolcengineASRRequestConfig.hotWords` 或通用 `ASRSessionOptions.recognitionHints`；LLM 层在 `PromptAssembly.fragments.lexicon`、`fragments.corrections` 注入。表结构改为 `lexicon_entry`、`lexicon_alias`、`lexicon_scope`、`correction_annotation`、`recognition_hint_usage`。

## 3. HIGH 问题

- §4.1 `RawTranscript` 只有 `text/language/durationMs`，没有 segment、confidence、alternatives、provider result id。影响 5/6/1：词本和易错字需要知道错误来自 ASR 候选、LLM 改写还是用户最终修改。
- §4.1 `FinalText` 只有 `text/mode`，没有 `promptRevisionID`、`appliedRuleIDs`、`memoryIDs`、`lexiconRevisionID`。影响 1/4/5/6：无法重跑、对照或解释个性化输出。
- §4.3 `VolcengineStreamingASR.openSession()` 无参数，§10 才说将来加 `hot_words`。影响 5/6：未来必须改 ASR public API 和 Coordinator 调用点。
- §4.6 `HistoryStore.clear()` 是全量清空，§5.1 schema 没有派生数据外键。影响 3/1/6：清历史时无法级联清除长期记忆、易错字规则和 prompt 实验记录。
- §6.2 设置页只有概览、凭据、快捷键、历史、隐私，删掉了 baseline 中的 Dictionary/Modes。影响 2/4/5/6：未来 UI 会反向逼迫 Persistence 和 Prompt 层重构。
- §9 “WS 中途断开”后原始转写丢弃，只写 `error_code`。影响 1/3/6：失败样本无法进入误识别学习，也无法让用户标注“这次哪里错了”。
- §10 `RemoteSyncAdapter` 只作为“同步/团队词典”的一句话，没有身份、版本、冲突、删除墓碑、加密边界。影响 3/5/6：跨设备同步一旦加入会牵动所有长期数据表。
- §10「per-app 风格规则」只说加 `AppStyleRule` 表和 prompt 前缀。影响 1/2：行为规则不一定只是 prompt，也可能改变 mode、词本作用域、插入策略和隐私策略。
- §14 测试策略没有 prompt revision、词本注入、易错字标注、长期记忆删除的 fixture。影响 3/4/5/6：这些能力晚加时很难证明没有污染主链路。

## 4. MEDIUM 问题

- §4.4 要求 system prompt ≤80 字。影响 1/2/4/5/6：对 v1 延迟有利，但未来应改为 `PromptBudget`，限制总 token 和各 fragment 上限，而不是硬限制 system prompt 字数。
- §5.1 `snippet` 表与 §10 语音命令/行为规则没有关系。影响 2：片段、命令、行为规则最好共用 `BehaviorRule` 或 `CommandAction` 模型。
- §5.2 `UserDefaults` 有 `last_used_app_bundle_id`，但没有 per-app settings。影响 1/2：至少预留 `app_profile` 表，不要把 app 适配塞进 UserDefaults。
- §4.5 `FallbackReason` 只有 `focusLost/accessibilityBlocked/unknown`。影响 1/2：未来按 app 学习插入偏好时，需要 `targetAppCapability`、`insertionMethod`、`failureDiagnostics`。
- §2.3 `OpenLessPersistence` 声称负责“历史、词典、片段”，但 §4.6 public API 只暴露 `HistoryStore` 和 `CredentialsVault`。影响 5/6：v1 至少应暴露空实现的 `LexiconStore`、`CorrectionStore`。
- §13 允许 DEBUG 打印 request/response body。影响 1/3/5/6：长期记忆、词本和易错字通常包含敏感名词，即便 DEBUG 也应默认脱敏。

## 4.5 UI/backend 解耦约束（未来约束 7）

当前 §2 的 7 个 Swift Package（`OpenLessCore`、`OpenLessRecorder`、`OpenLessASR`、`OpenLessPolish`、`OpenLessInsertion`、`OpenLessPersistence`、`OpenLessUI`）只做到了“代码目录和编译模块拆分”，还没有真正做到 UI/backend 解耦。关键风险在 §2.2 App target：`AppDelegate`、`MenuBarController`、`Settings/` 和 `DictationCoordinator` 同处 App 层，而 §2.1 又规定 App target 是唯一装配所有模块的地方。结果是 `DictationCoordinator` 很容易变成同时懂 UI 状态、快捷键事件、ASR、润色、插入、历史的上帝对象。

对未来约束 7，这个结构的主要缺口是：`OpenLessUI` 只是视图组件库，不是 UI 状态边界；架构没有声明 `ViewModel` 层，也没有声明 Views 只能通过 `@Observable ViewModel` 订阅状态。只要 SwiftUI/AppKit Views 直接调用 `DictationCoordinator.start()/stop()` 或读写 service，未来拆出设置 app、菜单栏 app、历史窗口、prompt 编辑器时，业务状态会被多个 UI 入口直接操纵。

路径 A：进程内 MVVM 解耦。形态是 `SwiftUI/AppKit Views → @Observable ViewModel → UseCase/Service protocol → Recorder/ASR/Polish/Insertion/Persistence`。服务层只暴露 `AsyncStream<DictationEvent>` 或 Combine publisher，不 import `SwiftUI`/`AppKit` UI 类型；ViewModel 负责把 `SessionState`、`CapsuleState`、设置表单状态和错误文案映射给 View。

路径 B：进程级 XPC 解耦。形态是录音/识别/润色/历史作为 LaunchAgent 或 XPC service，菜单栏 UI 和设置 UI 通过 XPC 调用同一个 backend。好处是 UI crash 不影响 backend，会自然支持“菜单栏 app + 设置 app 共用后端”，也更接近长期后台服务模型。

建议：v1 选 A，不选 B。依据是 §1.3 明确 KISS，§17 决策记录也偏向单 provider 直连和控制依赖；§15 落地路线强调先用 12 步跑通主链路。XPC 会引入 service lifecycle、权限归属、Keychain access group、音频权限归属、XPC 编码、崩溃恢复、升级兼容和调试成本，对 v1 的收益不足。

如果未来选择 B，合理触发条件应是：需要 UI 退出后继续录音/识别、需要多个独立前端同时连接 backend、或需要把后台学习/同步长期驻留为系统服务。当前 §1.1 v1 主链路和 §8 权限引导都没有提出这些硬需求。

但“不做 XPC”不等于接受当前 App target 直连所有业务。v1 至少要把 `DictationCoordinator` 从 UI 事件处理器改成无 UI 感知的 use case，并让 UI 只认识 ViewModel。否则 §2 的 7 package 拆分会被 App target 重新耦合起来，后续约束 7 会和 1/2/4/5/6 一起放大重构成本。

推荐的最小改动：

- 新增 `OpenLessWorkflow` 或 `OpenLessApplication` 模块，放置 `DictationUseCase` / `DictationCoordinator`，App target 只负责装配和创建 ViewModel。
- 新增 `OpenLessViewModels` 模块，至少包含 `CapsuleViewModel`、`SettingsViewModel`、`HistoryViewModel`、`ModePickerViewModel`；`OpenLessUI` 只依赖这些 ViewModel 或纯 display state。
- 在 `OpenLessCore` 增加协议：`DictationServiceProtocol`、`SettingsServiceProtocol`、`HistoryServiceProtocol`，以及事件模型 `DictationEvent`、`DictationCommand`。
- `DictationServiceProtocol` 暴露 `var events: AsyncStream<DictationEvent> { get }`、`start(context:)`、`stop()`、`cancel()`、`rerun(sessionID:modeID:)`；不要暴露具体 `VolcengineStreamingASR`、`DoubaoPolishClient`。
- `CapsuleState` 应由 `CapsuleViewModel` 从 `SessionState`/`DictationEvent` 映射，不让 `OpenLessRecorder`、`OpenLessASR`、`OpenLessPolish` 直接知道胶囊 UI。
- `Settings/` 不直接访问 `CredentialsVault`、`HistoryStore`、`UserDefaults`，而是通过 `SettingsViewModel` 调 `SettingsServiceProtocol`，避免设置页成为第二个业务编排入口。
- `DictationCoordinator` 输出结构化事件，如 `.recordingStarted`、`.partialTranscriptIgnored`、`.finalTranscriptReceived`、`.polishStarted`、`.inserted`、`.copiedFallback(reason:)`、`.failed(errorCode:)`，ViewModel 只消费事件。
- 为未来 XPC 保留可迁移边界：service protocol 的参数和返回值使用 `Codable`/`Sendable` DTO，不把 `NSView`、`NSWindow`、`AXUIElement`、`AVAudioPCMBuffer` 这类进程内对象泄露到 UI-facing protocol。
- App target 的 `AppContainer` 只做依赖装配，不持有业务状态；业务状态放在 service/use case，展示状态放在 ViewModel。
- 测试策略应补一类 ViewModel 单元测试：用 mock `DictationServiceProtocol` 驱动事件流，验证胶囊、历史、设置页不会直接依赖真实 ASR/LLM/AX。

结论：§2 的模块结构是必要但不充分。v1 不值得做 XPC，但必须做进程内 MVVM + UseCase/service protocol，否则 `DictationCoordinator` 会吞掉 UI/backend 边界，未来要拆独立设置 app、prompt 编辑 UI、长期后台学习服务时会变成架构级重构。

## 5. 隐私 / 长期化数据生命周期风险

- §13 “历史只存文本”对 v1 是安全简化，但对 1/3 会把 `raw_transcript` 和 `final_text` 变成默认学习语料。需要 `privacy_class`、`learnable`、`retention_policy_id`、`do_not_learn` 字段，且默认只进入历史，不进入长期记忆。
- §5.1 `dictation_session` 没有派生数据血缘。对 3/6，用户删除一条历史时，系统必须知道哪些 `user_memory`、`correction_annotation`、`recognition_hint_usage` 来自该 session，并可级联删除或重算。
- §5.2 只有全局 `history_retention_days` 和 `save_audio`。对 3/5/6，历史、词本、易错字、prompt 实验、同步日志应有不同 TTL 和导出/删除策略。
- §13 DEBUG body logging 应改为默认禁止正文日志，只允许结构化 metadata：provider、latency、status、error_code、token/audio duration。对 1/3/5/6，正文、词本、修正规则、prompt 片段都应走 redaction。
- §5.3 Keychain 保存 API Key 是正确的，但 `ark.endpoint`、`ark.model_id` 与 `volcengine.resource_id` 会影响数据出境和模型路径。对 3，需要在 session provenance 中记录实际 provider endpoint/model/resource，而不是只放 Keychain。
- §10 同步提案没有加密和冲突策略。对 3/5/6，长期记忆、个人词本和易错字标注默认应 local-only；同步必须显式 opt-in，并要求端到端加密或至少应用层加密字段。

## 6. 你的反提案

### 6.1 我会这样重写 §10 扩展点矩阵

| 未来功能 | v1 必须预留的接口 | 新模块/层 | 新字段/表 | 主链路接入点 |
|---|---|---|---|---|
| 1 个性化 | `MemoryProvider`、`StyleProfileResolver` | `OpenLessPersonalization` | `user_memory`、`memory_event`、`style_profile`；session `memory_revision_id` | ASR 前取识别偏好；Polish 前注入 style/memory fragment |
| 2 自定义 | `BehaviorRuleEngine`、`ModeRegistry` | `OpenLessPrompting`、`OpenLessRules` | `mode_definition`、`behavior_rule`、`rule_assignment` | PolicyResolver 输出 mode/rules/prompt fragments |
| 3 长期持久化 | `SessionEventStore`、`SyncAdapter` | `OpenLessPersistence` 内的 long-term 子层 | `session_event`、`sync_metadata`、`tombstone`、`retention_policy` | session 完成后写 event；清除时按血缘删除 |
| 4 Prompt 切换 | `PromptRegistry`、`PromptExperimentEngine` | `OpenLessPrompting` | `prompt_template`、`prompt_revision`、`prompt_set`、`prompt_experiment_assignment` | PolishRequest 固定记录 `prompt_revision_id` |
| 5 个人词本 | `LexiconProvider`、`RecognitionHintProvider` | `OpenLessLexicon` | `lexicon_entry`、`lexicon_alias`、`lexicon_revision`、`recognition_hint_usage` | ASR `openSession(options:)` 注入 hot-words；Polish 注入术语约束 |
| 6 易错字标注 | `CorrectionStore`、`CorrectionProvider` | `OpenLessFeedback` | `correction_annotation`、`correction_rule`、`correction_observation` | ASR 前提高候选权重；Polish 前注入纠错规则 |

### 6.2 建议新增的模块或抽象层

- `OpenLessPolicy`：`DictationPolicyResolver`，把 app、mode、隐私、词本、记忆、prompt 实验解析成一次会话的 policy。
- `OpenLessPrompting`：`ModeRegistry`、`PromptRegistry`、`PromptAssembler`，负责 mode/prompt 的版本化和片段拼装。
- `OpenLessLexicon`：`LexiconStore`、`RecognitionHintProvider`，把个人词本转换为 ASR hot-words 和 LLM 术语约束。
- `OpenLessFeedback`：`CorrectionStore`、`FeedbackEventSink`，承接用户标注、重跑、手改后的学习事件。
- `OpenLessPersonalization`：`MemoryStore`、`StyleProfileResolver`，只产出可审计的 memory/style fragments，不直接改 prompt 常量。
- `OpenLessSync`：`SyncAdapter`、`SyncMetadataStore`，v1 可空实现，但数据表从第一天带 version/tombstone。

建议把 provider 层接口从“多 provider 抽象”降级为“请求对象稳定化”：`ASRSessionOptions`、`ASRResult`、`PolishRequest`、`PolishResult`。这样不违背单火山 v1，但未来加词本、prompt 和易错字不必改主 Coordinator 签名。

### 6.3 v1 “不做”清单里应保留接口桩的项目

- §1.2「per-app 风格」：不做 UI 和规则引擎，但保留 `app_profile` 表和 `StyleProfileResolver.empty`。
- §1.2「多 ASR / 多 LLM provider 抽象层」：不做 provider router，但保留 `ASRSessionOptions`、`PolishRequest` 这种请求对象，避免未来 hot-words/prompt revision 改签名。
- §1.2「BYOK 路由」：UI 不暴露 provider 切换可以，但 `dictation_session` 要记录 `provider_route`、`asr_provider`、`llm_provider`、`model_id`、`endpoint_host`。
- §1.2「语音命令」：不做命令执行，但保留 `BehaviorRule`/`CommandAction` 表，避免片段、规则和命令各自长出模型。
- §5.1 `dict_entry` / §10「个人词典提升识别准确率」：不做词典 UI 可以，但 `LexiconStore`、`RecognitionHintProvider.empty` 应在 v1 存在。
- §4.1 `PolishMode` / §6.3 菜单栏模式切换：不做复杂模式市场，但内置 4 模式也应来自 `mode_definition` seeded records。
- §1.2/§10「同步」：不做 CloudKit/后端，但长期表必须有 `updated_at`、`version`、`deleted_at/tombstone`。

## 7. 不同意原文的地方

- 我不同意“为了未来功能现在就必须做多 provider 抽象”。§1.2 和 §17 选择单火山/Ark 直连是对的；6 个未来功能主要需要 policy、prompt、lexicon、memory、feedback 抽象，不需要 v1 上来做 Deepgram/Claude/GPT router。
- §4.4 “LLM `stream: true` 但等完整 finalText 一次性 AX 写入”是正确取舍。对 4 prompt A/B、1 个性化和 6 易错字回放来说，完整 polish run 更可审计；stream-replace 会让插入状态和历史 provenance 变复杂。
- §13 “API Key 进 Keychain、音频默认不落盘”是正确底线。未来 3 长期持久化也不应该从保存音频开始，而应从用户可控的文本、词本、标注和记忆对象开始。
- §4.4 `PolishContext` 先放 `appBundleId/appName` 是正确起点。不要删掉它；应扩展成 `DictationContext`，让 1 个性化和 2 per-app 规则有稳定入口。
- §11 把 macOS 26 glass/端侧能力封装在 UI 或未来模型层，不污染业务模块，是正确边界。未来 1/2/4/5/6 不应依赖 macOS 26 专属 API 才能工作。
