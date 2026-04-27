# OpenLess 架构设计文档（v1 / Demo 版）

更新时间：2026-04-26
适用范围：第一轮 demo 单云端 provider 实现

> 本文与已有产品文档的关系：
> - 产品需求以 `openless-requirements.md` 为准
> - 总体逻辑以 `openless-overall-logic.md` 为准
> - 工程模块拆分原型以 `openless-development.md` 为准
> - 本文是它们的**收紧版**：把 v1 的范围、模块边界、依赖图、扩展点固化下来，作为后续代码骨架的唯一来源

---

## 1. 设计目标与非目标

### 1.1 v1 必须做到

1. 用户在任意 macOS app 的输入框按住快捷键说话，松开后文字出现在光标处。
2. 录音、识别、润色、插入、兜底（剪贴板）、历史，端到端打通。
3. 底部状态胶囊（图片同款视觉）覆盖 listening / processing / inserted / cancelled / copied / error 六种状态。
4. 设置页可填火山引擎 ASR 凭据和 Ark API Key，Keychain 持久化。
5. 4 个润色模式（原文 / 轻度 / 清晰结构 / 正式）通过菜单栏快速切换。
6. 历史可查看原始转写和最终文本，可复制、可重跑。

### 1.2 v1 明确不做

- 多 ASR / 多 LLM provider 抽象层（只对接火山引擎一家）
- 本地 ASR、FoundationModels 端侧润色
- BYOK 路由（实质上设置页填的就是用户自己的 key，但 UI 不暴露 provider 切换）
- per-app 风格、语音命令、批量文件转写、截屏上下文、团队共享
- macOS App Store 分发（开源 + Direct distribution）

### 1.3 设计原则

| 原则 | 在本架构中的体现 |
|---|---|
| KISS | 单 provider 直连，不写 ASRBackend / PolishProvider 协议族 |
| 留扩展位置而非抽象层 | 火山引擎相关代码放在 `Networking/Volcengine/` 子目录，未来加 provider 是新增同级目录而不是重构 |
| 纵向切片 | 每个 Swift Package 模块对应一个职责，不为了"层"而拆 |
| 失败不丢内容 | 任何环节失败，原始转写 + 最终文本都进历史 |
| 隐私默认安全 | 默认不存音频；Key 只进 Keychain，不进 UserDefaults / 配置文件 |

---

## 2. 总体架构

### 2.1 分层与依赖方向

```
┌──────────────────────────────────────────────────────────────┐
│ App Target  (OpenLess.app)                                   │
│  - AppDelegate / MenuBarController                           │
│  - DictationCoordinator (主用例编排)                         │
│  - 依赖注入装配（Container）                                 │
└──────┬───────────┬────────────┬────────────┬────────────┬───┘
       │           │            │            │            │
       ▼           ▼            ▼            ▼            ▼
  ┌────────┐ ┌──────────┐ ┌─────────┐  ┌──────────┐ ┌──────────┐
  │  Core  │ │ Recorder │ │   ASR   │  │  Polish  │ │Insertion │
  │(types) │ │(AVAudio) │ │ (WS)    │  │(HTTP)    │ │(AX/CG)   │
  └────┬───┘ └────┬─────┘ └────┬────┘  └────┬─────┘ └────┬─────┘
       │          │            │            │            │
       │          └────────────┴────────────┴────────────┘
       │                       │
       ▼                       ▼
  ┌──────────────┐      ┌──────────────┐
  │ Persistence  │      │   AppKit/    │
  │ (GRDB+Key-   │      │   SwiftUI    │
  │  chain)      │      │  组件库 (UI) │
  └──────────────┘      └──────────────┘
```

依赖规则：
- 上层可以依赖下层；同层互不依赖；下层永远不依赖上层。
- `Core` 是叶子模块，所有 Swift Package 都可以依赖它。
- App target 是唯一允许把所有模块组装起来的地方。

### 2.2 Swift Package 模块划分

```
OpenLess/
├── OpenLess.xcodeproj                       # App target
├── App/                                     # App 源码（.app 入口）
│   ├── OpenLessApp.swift                    # @main, AppDelegate
│   ├── AppContainer.swift                   # 依赖装配
│   ├── MenuBarController.swift              # 菜单栏图标 + 菜单
│   ├── DictationCoordinator.swift           # 主流程编排
│   └── Settings/                            # 设置窗口（SwiftUI）
└── Packages/                                # 本地 Swift Package
    ├── OpenLessCore/                        # 类型、状态机、错误码
    ├── OpenLessRecorder/                    # AVFoundation 录音
    ├── OpenLessASR/                         # 火山引擎流式 ASR 客户端
    ├── OpenLessPolish/                      # Ark Doubao 润色客户端
    ├── OpenLessInsertion/                   # 插入 + 剪贴板兜底
    ├── OpenLessPersistence/                 # SQLite 历史/词典 + Keychain
    └── OpenLessUI/                          # 胶囊视图 + 设置页通用组件
```

每个 Package 一个 `Package.swift`，`OpenLess` 主工程通过 local path 依赖它们。

### 2.3 模块职责一句话

| Package | 职责 | 不负责什么 |
|---|---|---|
| `OpenLessCore` | 共享类型（`PolishMode`、`DictationSession`、错误枚举）、`SessionStateMachine` | 任何 IO |
| `OpenLessRecorder` | 麦克风采集、音量采样、PCM chunk 推送、按需停止 | 转写、UI |
| `OpenLessASR` | 与火山 WebSocket 协议通信（鉴权头、二进制帧、gzip、partial/final 结果） | 录音采集、润色 |
| `OpenLessPolish` | Ark Chat Completions 调用、4 模式 prompt 模板、错误降级到原文 | 转写、UI |
| `OpenLessInsertion` | AX API 拼接到当前焦点、CGEvent 模拟粘贴、剪贴板兜底、`focus_lost` 检测 | 历史保存 |
| `OpenLessPersistence` | GRDB SQLite（历史、词典、片段）、Keychain（API key、access token） | UI |
| `OpenLessUI` | 胶囊视图（macOS 26 用 `.glassEffect()`，macOS 15 用 `NSVisualEffectView`）、设置页组件 | 业务流程 |

---

## 3. 核心数据流

### 3.1 正常输入流程（端到端）

```
用户                 App                        Recorder       ASR              Polish        Inserter
 │  按下快捷键         │                              │             │                 │             │
 │ ───────────────▶  │                              │             │                 │             │
 │                   │  Coordinator.start()         │             │                 │             │
 │                   │ ─────────────────────────▶   │             │                 │             │
 │                   │                              │ AVAudio开    │                 │             │
 │                   │  Capsule.show(.listening)    │             │                 │             │
 │                   │  ASR.openSession()           │             │                 │             │
 │                   │ ──────────────────────────────────────────▶│ WS 握手 + 鉴权  │             │
 │                   │                              │ 100-200ms   │                 │             │
 │                   │                              │ PCM chunk──▶│ 二进制帧+gzip   │             │
 │                   │                              │             │                 │             │
 │  说话…             │  AudioLevel更新胶囊白条       │             │                 │             │
 │                   │  partial result(definite=F)  ◀────────────│                 │             │
 │                   │  （丢弃，不显示给用户）        │             │                 │             │
 │  松开快捷键         │                              │             │                 │             │
 │ ───────────────▶  │                              │             │                 │             │
 │                   │  Recorder.stop()             │             │                 │             │
 │                   │ ─────────────────────────▶   │             │                 │             │
 │                   │  ASR.sendLastFrame()         │             │                 │             │
 │                   │  Capsule.set(.processing)    │             │                 │             │
 │                   │  final result(definite=T)    ◀────────────│                 │             │
 │                   │                              │             │                 │             │
 │                   │  Polish.polish(raw, mode)    │             │                 │             │
 │                   │ ───────────────────────────────────────────────────────────▶ │ Ark POST    │
 │                   │  finalText                   ◀───────────────────────────────│             │
 │                   │                              │             │                 │             │
 │                   │  Inserter.insert(finalText)  │             │                 │             │
 │                   │ ──────────────────────────────────────────────────────────────────────────▶│
 │                   │  insert OK                   ◀──────────────────────────────────────────────│
 │                   │                              │             │                 │             │
 │                   │  Persistence.save(session)   │             │                 │             │
 │                   │  Capsule.set(.inserted)→hide │             │                 │             │
 │                   │                              │             │                 │             │
```

### 3.2 状态机（顶层 Session）

```
                ┌────────────┐
                │   .idle    │
                └─────┬──────┘
                      │ hotkey down
                      ▼
                ┌────────────┐  esc / cancel    ┌────────────┐
                │ .listening │ ────────────────▶│.cancelled  │ → .idle
                └─────┬──────┘                  └────────────┘
                      │ hotkey up
                      ▼
                ┌─────────────┐  asr error      ┌────────────┐
                │.transcribing│ ───────────────▶│  .failed   │ → .idle
                └─────┬───────┘                 └────────────┘
                      │ final transcript
                      ▼
                ┌────────────┐  polish error   ┌────────────┐
                │ .polishing │ ───────────────▶│ .insertRaw │
                └─────┬──────┘  （兜底原文）     └────┬───────┘
                      │ final text                  │
                      ▼                             │
                ┌────────────┐                      │
                │ .inserting │ ◀─────────────────── │
                └─────┬──────┘
            ┌─────────┴──────────┐
   insert ok│                    │ insert fail
            ▼                    ▼
      ┌──────────┐         ┌──────────────┐
      │.inserted │         │.copiedFallback│
      └────┬─────┘         └──────┬────────┘
           │                      │
           └──────────┬───────────┘
                      ▼
                  .idle
```

实现：`OpenLessCore.SessionStateMachine` 是 `@Observable` 类，所有状态改变只有它能做；其他模块只能调它的 `transition(to:)`，并被卫语句拦截非法迁移。

---

## 4. 关键模块接口

> 这里只列**模块对外暴露的最小 API**，不列内部实现细节。

### 4.1 OpenLessCore

```swift
public enum PolishMode: String, CaseIterable, Codable {
    case raw, light, structured, formal
}

public struct RawTranscript: Sendable {
    public let text: String
    public let language: String?      // "zh", "en", "mixed"
    public let durationMs: Int
}

public struct FinalText: Sendable {
    public let text: String
    public let mode: PolishMode
}

public struct DictationSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let raw: String
    public let final: String
    public let mode: PolishMode
    public let appBundleId: String?
    public let appName: String?
    public let insertStatus: InsertStatus
    public let errorCode: String?
}

public enum InsertStatus: String, Codable, Sendable {
    case inserted, copiedFallback, failed
}

public enum DictationError: Error, Sendable {
    case micPermissionMissing
    case accessibilityMissing
    case asrFailed(String)
    case polishFailed(String)
    case networkUnavailable
    case credentialsMissing
}

@MainActor
public final class SessionStateMachine: ObservableObject {
    @Published public private(set) var state: SessionState = .idle
    public func transition(to next: SessionState) { /* 卫语句 */ }
}
```

### 4.2 OpenLessRecorder

```swift
public protocol AudioConsumer: AnyObject, Sendable {
    /// 16kHz / 16-bit PCM，单声道；100-200ms 一包
    func consume(pcmChunk: Data)
}

public final class Recorder {
    public init() throws
    public func start(consumer: AudioConsumer) async throws
    public func stop() async                           // 触发最后一个 chunk
    public func cancel() async                         // 不发送最后一个 chunk
    public var levelStream: AsyncStream<Float> { get } // 0...1，胶囊白条用
}
```

### 4.3 OpenLessASR（仅火山实现）

```swift
public protocol VolcengineCredentials: Sendable {
    var appKey: String { get }
    var accessKey: String { get }
    var resourceId: String { get }   // 通常 "volc.bigasr.sauc.duration"
}

public final class VolcengineStreamingASR: AudioConsumer {
    public init(credentials: VolcengineCredentials)
    public func openSession() async throws
    public func consume(pcmChunk: Data)               // AudioConsumer 实现
    public func sendLastFrame() async throws
    public func awaitFinalResult() async throws -> RawTranscript
    public func cancelSession() async
}
```

火山协议要点（实现内部，对外不暴露）：
- WSS：`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`
- 鉴权 header：`X-Api-App-Key` / `X-Api-Access-Key` / `X-Api-Resource-Id` / `X-Api-Connect-Id`（UUID）
- 二进制帧：4 字节 header + 4 字节大端 payload size + payload
- Header 字段：Protocol Version `0b0001` / Header Size `0b0001` / Message Type（请求 `0b0001` / 音频 `0b0010` / 响应 `0b1001`）/ Serialization `0b0001`（JSON）
- Payload 用 gzip 压缩
- 第一帧：full client request（音频参数 + `model_name: "bigmodel"` + `enable_itn` + `enable_punc`）
- 后续帧：每 100-200ms 一包 PCM
- 最后一包：flags `0x02`
- 响应 utterances 中 `definite: true` 才是最终结果

### 4.4 OpenLessPolish（仅 Ark Doubao 实现）

```swift
public struct ArkCredentials: Sendable {
    public let apiKey: String
    public let modelId: String           // 默认 "deepseek-v3-2"，可改 doubao-seed-1-6 等
    public let endpoint: URL             // 默认 https://ark.cn-beijing.volces.com/api/v3/chat/completions
}

public struct PolishContext: Sendable {
    public let appBundleId: String?
    public let appName: String?
}

public final class DoubaoPolishClient {
    public init(credentials: ArkCredentials)
    public func polish(
        raw: RawTranscript,
        mode: PolishMode,
        context: PolishContext
    ) async throws -> FinalText
}
```

Prompt 模板（mode → system prompt）放在模块内的 `PolishPromptTemplates.swift`，与 `openless-development.md §7.3` 保持一致。

性能要点（实现时严格遵守）：
- HTTP 请求 `stream: true`，用 SSE 解析；TTFT 推进胶囊状态，但**插入仍等完整 finalText 一次性 AX 写入**（避免 stream-replace 在中文 IME / 富文本 app 的副作用）
- 默认选**非推理模型**（DeepSeek V3.2 / doubao-seed-1-6 / doubao-1-5-lite），润色任务无需 reasoning，省 1–3 秒
- system prompt 极简（≤80 字，4 模式只换其中一句指令）

### 4.5 OpenLessInsertion

```swift
public final class TextInserter {
    public init()
    public func insert(_ text: String) async throws -> InsertResult
}

public enum InsertResult: Sendable {
    case inserted
    case copiedFallback(reason: FallbackReason)
}

public enum FallbackReason: String, Sendable {
    case focusLost, accessibilityBlocked, unknown
}
```

实现策略（按顺序尝试，最简两步）：
1. AX API 找到 focused element，通过 `kAXValueAttribute` 替换 / 追加文本
2. 失败 → `NSPasteboard.general` 写入 + 通过 `CGEvent` 模拟 `Cmd+V`（需要辅助功能权限）
3. 仍失败 → 仅复制，返回 `copiedFallback`

### 4.6 OpenLessPersistence

```swift
public final class HistoryStore {
    public init() throws    // 自动创建 SQLite 表
    public func save(_ session: DictationSession) async throws
    public func recent(limit: Int) async throws -> [DictationSession]
    public func clear() async throws
}

public final class CredentialsVault {
    public init()
    public func saveVolcengine(_ creds: VolcengineCredentials) throws
    public func loadVolcengine() throws -> VolcengineCredentials?
    public func saveArk(_ creds: ArkCredentials) throws
    public func loadArk() throws -> ArkCredentials?
}
```

Keychain service 名：`com.openless.app`，account 区分用 `volcengine.app_key`、`volcengine.access_key`、`ark.api_key`。

### 4.7 OpenLessUI

```swift
public struct CapsuleOverlay: View {
    public init(state: CapsuleState, audioLevel: Float)
}

public enum CapsuleState: Equatable, Sendable {
    case hidden
    case listening      // 叉号 + 动态白条 + 勾号
    case processing     // 整理中
    case inserted       // 勾号高亮
    case cancelled      // 叉号高亮
    case copied         // "已复制"
    case error(String)  // 红点
}
```

视觉：
- macOS 26：`.glassEffect(.regular.interactive(), in: .capsule)`
- macOS 15：`NSVisualEffectView` material `.hudWindow` + manual blur background
- 通过 `if #available(macOS 26.0, *)` 二选一，封装在 `OpenLessUI` 内的 `GlassBackground` 私有视图

底部胶囊浮窗（NSWindow）：
- `level = .statusBar`、`isMovable = false`、`backgroundColor = .clear`、`hasShadow = false`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- 不抢焦点（`canBecomeKey = false`）
- 屏幕底部居中，距底边 24px
- 多屏：跟随 `NSScreen.main`（活跃 app 所在屏），监听 `NSWindow.didChangeScreenNotification`

---

## 5. 数据持久化

### 5.1 SQLite Schema（GRDB）

```sql
CREATE TABLE dictation_session (
  id              TEXT PRIMARY KEY,
  created_at      INTEGER NOT NULL,
  raw_transcript  TEXT NOT NULL,
  final_text      TEXT NOT NULL,
  mode            TEXT NOT NULL,
  app_bundle_id   TEXT,
  app_name        TEXT,
  insert_status   TEXT NOT NULL,
  error_code      TEXT
);
CREATE INDEX idx_session_created_at ON dictation_session(created_at DESC);

-- 词典 / 片段 v1 暂不实现，但表结构预留位置
CREATE TABLE dict_entry (
  id            TEXT PRIMARY KEY,
  phrase        TEXT NOT NULL,
  category      TEXT NOT NULL DEFAULT 'custom',
  notes         TEXT NOT NULL DEFAULT '',
  enabled       INTEGER NOT NULL DEFAULT 1,
  source        TEXT NOT NULL DEFAULT 'manual',
  created_at    INTEGER NOT NULL
);
CREATE TABLE snippet (
  id              TEXT PRIMARY KEY,
  trigger_phrase  TEXT NOT NULL UNIQUE,
  content         TEXT NOT NULL,
  enabled         INTEGER NOT NULL DEFAULT 1
);
```

存储路径：`~/Library/Application Support/OpenLess/openless.sqlite`

### 5.2 用户偏好（UserDefaults）

非敏感字段：
- `hotkey_record`（默认 `fn`，可改）
- `default_mode`（默认 `light`）
- `history_retention_days`（默认 `30`）
- `save_audio`（默认 `false`，且 v1 不实现）
- `last_used_app_bundle_id`

### 5.3 凭据（Keychain）

| account | 内容 |
|---|---|
| `volcengine.app_key` | X-Api-App-Key |
| `volcengine.access_key` | X-Api-Access-Key |
| `volcengine.resource_id` | 默认 `volc.bigasr.sauc.duration`，允许覆盖 |
| `ark.api_key` | Ark Bearer token |
| `ark.model_id` | 默认 `doubao-seed-1-6`，允许覆盖 |
| `ark.endpoint` | 默认 `https://ark.cn-beijing.volces.com/api/v3/chat/completions` |

---

## 6. UI 规格落地

### 6.1 胶囊状态对应视觉

| 状态 | 中部内容 | 宽度 | 动效 |
|---|---|---|---|
| `.listening` | 5 根白色音量条，跟随 `Recorder.levelStream` | 160px | spring 出现 |
| `.processing` | 3 根条静止 + 缓慢明灭，或 spinner | 180px | width spring 变宽 |
| `.inserted` | 中部隐藏，右侧勾号 0.4s 高亮 | 140px | 0.8s 后淡出 |
| `.cancelled` | 中部隐藏，左侧叉号 0.4s 高亮 | 140px | 快速淡出 |
| `.copied` | 文字"已复制" | 180px | 保留 2s |
| `.error(msg)` | 红点 + 短文案，点击展开详情 | 200px | 不自动消失 |

参考用户提供的截图：深色 graphite 胶囊，中央青绿色微光跳动条，左叉右勾。

### 6.2 设置窗口（SwiftUI `Form`）

5 个分页（左侧 sidebar）：
1. **概览**：当前快捷键、麦克风状态、API 凭据是否齐、最近一次成功输入时间
2. **凭据**：填火山 ASR 三件套 + Ark API Key / Model ID
3. **快捷键**：录音键、取消键、粘贴上一条键（用 `KeyboardShortcuts` 库）
4. **历史**：表格，列：时间 / app / 最终文本 / 操作（复制 / 重跑 / 删除）
5. **隐私**：清空历史、关闭历史保存的开关

### 6.3 菜单栏

图标：SF Symbol `mic.circle`（普通）/ `mic.fill`（录音中）

菜单项：
- 当前模式：· 原文 · 轻度润色 · 清晰结构 · 正式表达（单选）
- ────
- 打开设置…
- 查看历史…
- ────
- 退出 OpenLess

---

## 7. 全局快捷键

依赖 [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) 库（开源、维护活跃、API 简洁）。

默认绑定：
- 录音：`fn`（按住）
- 取消：`Esc`（仅在 listening 状态注册）
- 粘贴上一条：`⌥⌘V`

录音键采用 `onKeyDown` + `onKeyUp` 实现 push-to-talk；toggle 模式延后实现。

---

## 8. 权限与首次启动引导

启动时按顺序检查（`PermissionController`）：

| 权限 | 检查 API | 缺失时引导 |
|---|---|---|
| 麦克风 | `AVCaptureDevice.authorizationStatus(for: .audio)` | 弹出系统授权 → 引导到「系统设置 → 隐私与安全 → 麦克风」 |
| 辅助功能 | `AXIsProcessTrustedWithOptions` | 弹引导卡，按钮直接打开「隐私与安全 → 辅助功能」 |
| 输入监控 | `IOHIDCheckAccess(.eventTap)` | 同上，「输入监控」面板 |
| API 凭据 | `CredentialsVault.loadVolcengine() && loadArk()` | 跳转设置页凭据分页 |

任一未通过 → 菜单栏图标显示警告徽章 + 主流程拒绝执行（胶囊弹"需补全权限"）。

---

## 9. 错误降级策略

| 失败点 | 降级路径 |
|---|---|
| 麦克风权限缺 | 不进 listening，胶囊弹引导文案 |
| WS 握手失败（鉴权错） | 胶囊红点"识别凭据无效，请检查设置" |
| WS 中途断开 | 重试一次；仍失败 → 胶囊红点"识别失败"，原始转写丢弃 |
| ASR 成功 + 润色失败 | 直接插入原始转写 + 胶囊"已插入原文" |
| 插入失败（focus_lost / AX block） | 复制到剪贴板 + 胶囊"已复制" |
| 网络完全不可用 | 胶囊"网络不可用"，结束流程 |

录音 PCM 在 ASR 失败前**保留在内存**直到流程结束（用户可"重试上一次录音"，v2 实现）。v1 失败即丢，但历史里写一条 `error_code` 记录。

---

## 10. 扩展点（为"加竞品功能"预留）

> 这部分**不在 v1 实现范围**，但目录、命名、协议要为它们留位置，避免未来重构。

| 未来要加的功能 | 改哪里 | 是否需要重构现有代码 |
|---|---|---|
| 加新 ASR provider（Deepgram / 讯飞 / Apple SpeechAnalyzer） | 在 `OpenLessASR/` 下加 `Deepgram/` 子目录，新增 client 类；提一个最小协议 `ASRClient`，让 `Coordinator` 持有协议而非具体类 | **半重构**：Coordinator 改 1 处依赖类型 |
| 加新 LLM provider（Claude / GPT / Gemini） | 同上，`OpenLessPolish/` 下加子目录；提 `PolishClient` 协议 | 半重构 |
| 用户自定义润色模式 | `PolishMode` 加 `.custom(id, name, prompt)`；模板引擎从内置常量改为 dict lookup；设置页加自定义 mode 编辑器 | 不动其它模块 |
| per-app 风格规则 | `PolishContext` 已带 `appBundleId`，加 `AppStyleRule` 表 + Polish 调用前 hook 注入 prompt 前缀 | 不动 ASR / 录音 |
| 语音命令（"new line"、"delete that"） | 在 `OpenLessASR` 输出与 `OpenLessPolish` 之间插一层 `VoiceCommandInterpreter` | 不动其它模块 |
| 个人词典提升识别准确率 | `Recorder` 启动 ASR 时把词典作为 hot words 传入；ASR full client request 加 `hot_words` 字段 | ASR client 加字段 |
| 截屏上下文 | `PolishContext` 加可选 `screenshot: Data?`；调用方决定是否传 | 走多模态模型 |
| 同步 / 团队词典 | `Persistence` 加 `RemoteSyncAdapter` 协议；CloudKit 或自建后端 | 不动业务逻辑 |
| 批量文件转写 | 新增 `OpenLessBatch` 模块复用 `OpenLessASR`；新窗口 + 队列 | 不动主流程 |
| iOS 键盘 | 不在 macOS 工程里做；新建 iOS app + Custom Keyboard Extension，复用 `OpenLessCore` / `OpenLessASR` / `OpenLessPolish` | 0 |

**核心保证**：上面 10 条里有 7 条是「新增模块或新增字段」，3 条是「半重构」，没有一条需要改动 Recorder / Inserter / Persistence / UI 主结构。这就是"良好扩展性"的具体定义。

---

## 11. macOS 版本兼容（双轨）

最低支持 macOS 15.0；macOS 26.0 启用增强体验。

| 能力 | macOS 15 | macOS 26 |
|---|---|---|
| 胶囊背景 | `NSVisualEffectView` material `.hudWindow` | `.glassEffect(.regular.interactive(), in: .capsule)` |
| 设置页材质 | 默认 SwiftUI form | `.glassEffect()` 包装 |
| 胶囊状态切换动画 | `withAnimation(.spring())` | `withAnimation(.spring())` + `glassEffectID` 实现 morph |
| 端侧润色（v2） | 不可用 | `FoundationModels.SystemLanguageModel` |

封装：所有版本分支只在 `OpenLessUI` 内部，不污染业务模块。

---

## 12. 第三方依赖

> 严格控制外部依赖。每加一个都要列理由。

| 依赖 | 用途 | 替代方案？ | 决策 |
|---|---|---|---|
| `KeyboardShortcuts` (sindresorhus) | 全局快捷键录入 + 持久化 | 自己写 Carbon RegisterEventHotKey | 用，省 200 行 |
| `GRDB.swift` | SQLite ORM | SwiftData (要 macOS 14+，其实 OK；但 GRDB 更稳) | 用 GRDB |
| `swift-log` | 结构化日志 | `os.Logger` | 用 `os.Logger`（系统自带，不引入） |

**不用**：Alamofire、SnapKit、RxSwift、Sparkle（v1 暂不做自动更新）。

---

## 13. 安全与隐私

- **API Key 全部进 Keychain**，绝不写 `UserDefaults` / `~/Library/Preferences/*.plist` / 工程内常量
- **音频默认不落盘**：Recorder 在 `Data` 缓冲区里持有 PCM，stop 后释放
- **历史只存文本**：`raw_transcript` + `final_text`，不存音频文件路径
- **网络请求最小化日志**：URL / 状态码 / 错误码 OK，但 request body / response body 仅 DEBUG 构建打印
- **崩溃日志**：仅本地 `~/Library/Logs/OpenLess/`，不上传

---

## 14. 测试策略

v1 测试范围：

| 类型 | 覆盖 | 工具 |
|---|---|---|
| 单元测试 | `OpenLessCore` 状态机迁移、`OpenLessASR` 二进制帧编解码、`OpenLessPolish` prompt 拼装 | Swift Testing |
| 集成测试 | `VolcengineStreamingASR.openSession()` 用 mock WebSocket（先验证协议帧正确，无需真凭据）；`DoubaoPolishClient` 用录制的固定 fixture | Swift Testing |
| 手工 UAT | 5 个常用 app 跑通端到端：TextEdit / Notes / 微信 / Cursor / ChatGPT 网页 | 人工 |

**不**做 UI snapshot test、E2E 自动化（v1 投产成本不划算）。

---

## 15. 落地路线（开发顺序）

按可独立验证的最小步骤拆：

| # | 步骤 | 验证方式 |
|---|---|---|
| 1 | Xcode 工程 + 7 个 Package 骨架 + App target 能跑出空菜单栏图标 | `Cmd+R` 看到菜单栏图标 |
| 2 | 设置窗口 + 凭据分页 + Keychain 存读 | 填一组假 key，重启 app 能读出来 |
| 3 | 全局快捷键（仅 log，不录音） | 按 `fn` 控制台打印「pressed / released」 |
| 4 | 麦克风录音 + AVAudio 16kHz/16bit/mono PCM | `dump WAV` 调试方法导出能播放 |
| 5 | 火山 ASR WS 协议（先打通鉴权 + 一次小录音的 finalText） | 终端能看到 final transcript |
| 6 | Doubao 润色（一个 mode） | console 看到 4 模式的 finalText |
| 7 | 胶囊浮窗 + 状态机串起 1-6 步 | 屏幕底部能看到胶囊变化 |
| 8 | 文本插入到 TextEdit + 剪贴板兜底 | TextEdit 收到字 |
| 9 | 历史持久化 + 设置页历史分页 | 设置页能看到 3 条记录 |
| 10 | 4 模式菜单栏切换 + per-mode prompt | 同一段语音切换模式输出不同 |
| 11 | 错误降级 + 胶囊错误状态 | 拔网络/改错 key 看胶囊红点 |
| 12 | 5 app UAT | 中文/英文/中英混输各 3 句 |

每一步必须能跑（pass）才进下一步。如果某步阻塞超过预算，回退到「v1 不做」清单或单独提出。

---

## 16. 不在本文范围

- 完整 prompt 内容（参考 `openless-development.md §7`）
- 4 个模式具体的 prompt 文本（实现时与产品文档逐句对齐）
- 历史 UI 的复杂筛选 / 搜索（v2）
- 自动更新机制（v2 接 Sparkle）
- 多语言 UI（v1 仅中文）

---

## 17. 决策记录

| 决策 | 备选 | 选择理由 |
|---|---|---|
| 单火山 provider 直连，不抽象 | 多 provider 协议族 | KISS，加新 provider 时再提抽象不晚 |
| 默认 LLM `deepseek-v3-2`（火山 Ark） | doubao-seed-1-6 / 推理模型 | 轻便、非推理、Ark 兼容；用户可在设置页改 |
| LLM `stream: true` 但等完整文本插入 | streaming + 边收边插 | 保留低延迟胶囊反馈，规避 stream-replace 副作用 |
| WSS 流式 ASR | HTTP 一次性 | 用户指定；松开快捷键到出文字延迟更短 |
| API Key 进 Keychain | .env / config | 开源仓库零泄露风险；UI 即引导，符合产品定位 |
| 最低 macOS 15 + 26 增强 | 仅 macOS 26 | 26 装机量小，开源软件需要更宽用户群 |
| Direct distribution | MAS | 沙盒不允许必要的 AX / Input Monitoring 完整能力 |
| GRDB | SwiftData | macOS 15 SwiftData 可以用，但 GRDB API 稳定、查询表达力强 |
| `KeyboardShortcuts` 库 | 自实现 Carbon | 省时间、维护活跃 |

---

## 18. 与已有文档的去重

| 已有文档 | 与本文关系 |
|---|---|
| `openless-requirements.md` | 产品需求源头，本文不重复，仅引用 |
| `openless-overall-logic.md` | 业务逻辑源头，本文不重复 |
| `openless-development.md` | 工程模块原型；本文是其**v1 落地版**，遇到分歧以本文为准 |
| `voice-input-mvp-requirements.md` | 第一轮总需求；本文是其工程切片 |
| `competitor-reviews-and-ui-direction.md` | UI / 竞品调研；本文 §10 引用其作为扩展点设计依据 |
| `openless-product-concept-diagnosis.md` | 概念诊断；本文不引用 |
