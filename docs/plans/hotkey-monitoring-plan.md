# 键盘监测实现规划

> 切片范围：实现 push-to-talk 全局键盘监测，作为 OpenLess 主链路的第一个独立切片。完成后可直接验证按键事件流，未来插入 `DictationCoordinator` 时不需要返工。

更新时间：2026-04-26

---

## 1. 目标

按住一个全局热键 → 触发 `pressed` 事件流；松开 → 触发 `released`；录音过程中按 `Esc` → 触发 `cancelled`。

**v1 必须做到：**
- 全局生效（任何 app 聚焦时都能监听到）
- 默认热键不与 macOS 系统功能冲突
- 用户可在设置里换热键
- 权限缺失时返回明确错误码（不静默失效）
- 模块对外只暴露事件流，**不持有 UI / 业务状态**（满足 Codex 审查 §4.5 解耦要求）

**v1 不做：**
- 复杂组合键（仅支持单 modifier 键 push-to-talk + 普通键 Esc 取消）
- toggle 模式（按一下开始、再按一下结束）
- 拦截事件（不阻止系统默认行为，仅监听）
- 多设备适配（外接键盘 fn 键差异）

---

## 2. 关键技术决策

### 2.1 弃用 `KeyboardShortcuts` library

架构文档 §12 原本计划用 [`sindresorhus/KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts)。**这里需要修订**。

**原因**：该 library 只支持组合键（modifier + 普通键），**不支持 modifier-only push-to-talk**（按住单个 modifier 触发）。Wispr Flow / Typeless / Superwhisper 默认体验都是按住单一 modifier 说话，这是 OpenLess 必备能力。

**替代**：直接用 `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents`，监听 `.flagsChanged`（modifier 变化）和 `.keyDown`（Esc）。零依赖。

### 2.2 默认热键选 `right_option`

候选评估：

| 键 | 优点 | 缺点 | 选/不选 |
|---|---|---|---|
| `fn` / Globe | 用户最熟悉（Wispr 风格） | macOS 13+ 默认绑系统听写 / emoji picker，会同时触发 | ❌ 默认 |
| `right_option` | 单独可检测、零冲突、几乎所有 Mac 键盘有 | 用户习惯感稍弱 | ✅ **默认** |
| `right_command` | 单独可检测 | 部分键盘没有右 cmd | ❌ |
| `right_control` | 单独可检测 | 部分键盘没有右 ctrl | ❌ |

**默认 `right_option`，但设置里允许切到 `fn`、`right_command`、`right_control` 等**（v1 实现 4 个候选，UI 留 dropdown）。

### 2.3 modifier-only 键如何检测

`NSEvent.flagsChanged` 事件的 `modifierFlags.rawValue` 包含设备级别的 modifier 位（NX_DEVICE 系列 mask），可区分左右：

| Trigger | NX_DEVICE_*_MASK |
|---|---|
| `.leftControl` | `0x0001` |
| `.rightCommand` | `0x0010` |
| `.leftOption` | `0x0020` |
| `.rightOption` | `0x0040` |
| `.rightControl` | `0x2000` |
| `.fn` | `NSEvent.ModifierFlags.function` |

判断按下 / 松开：维护一个 `isPressed` 状态，每次 `flagsChanged` 时重新计算 `isTriggerActive(event)`，与上次状态比较 → 触发 `.pressed` / `.released`。

### 2.4 权限处理

现代 macOS（13+）对全局键盘监听有 Input Monitoring 权限要求。`NSEvent.addGlobalMonitorForEvents` 在不少情况下能不要权限工作，但**不能保证**对所有 app 聚焦状态都收到事件。

**v1 方案**：
- 启动时调用 `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` 检查权限
- 未授权 → 抛 `HotkeyError.inputMonitoringNotGranted`，由上层引导用户开权限
- 已授权 → 安装 monitor

辅助功能（Accessibility）权限是文本插入需要的，不是键盘监听需要的。两者要分别引导。

### 2.5 线程模型

`NSEvent` monitor callback 默认在主线程。所有事件 yield 到 `AsyncStream` 也在主线程，consumer 默认主线程消费。无锁、无并发问题。

`AsyncStream.Continuation` 本身是 `Sendable` 的，跨线程 yield 安全。

---

## 3. 模块归属

新建 Swift Package：**`OpenLessHotkey`**

依赖：仅 `AppKit`、`IOKit.hidsystem`，**不依赖 OpenLessCore**（保持纯净的"键盘事件平面"模块）。

未来与 Coordinator 集成：在 `OpenLessWorkflow` 模块（架构文档 v2 计划新增）里订阅 `events: AsyncStream<HotkeyEvent>`，转发为 `DictationCommand`。Hotkey 模块本身不知道 Dictation 存在。

---

## 4. 接口契约

```swift
// HotkeyEvent.swift
public enum HotkeyEvent: Sendable, Equatable {
    case pressed
    case released
    case cancelled  // Esc 在 pressed 期间按下
}

// HotkeyBinding.swift
public struct HotkeyBinding: Codable, Sendable, Equatable {
    public enum Trigger: String, Codable, Sendable, CaseIterable {
        case rightOption
        case leftOption
        case rightCommand
        case rightControl
        case leftControl
        case fn
    }

    public let pushToTalk: Trigger

    public init(pushToTalk: Trigger) {
        self.pushToTalk = pushToTalk
    }

    public static let `default` = HotkeyBinding(pushToTalk: .rightOption)
}

// HotkeyError.swift
public enum HotkeyError: Error, Sendable, Equatable {
    case alreadyRunning
    case notRunning
    case inputMonitoringNotGranted
}

// HotkeyServiceProtocol.swift
@MainActor
public protocol HotkeyServiceProtocol: AnyObject {
    var events: AsyncStream<HotkeyEvent> { get }
    func start(binding: HotkeyBinding) throws
    func stop()
    func updateBinding(_ binding: HotkeyBinding)
    var isRunning: Bool { get }
}

// HotkeyMonitor.swift（实现）
@MainActor
public final class HotkeyMonitor: HotkeyServiceProtocol { /* NSEvent 实现 */ }

// InputMonitoringPermission.swift
public enum InputMonitoringPermission {
    public static func isGranted() -> Bool
    public static func request() -> Bool  // 触发系统弹窗
}
```

设计要点：
- 协议 + 实现分离，便于 Coordinator 端 mock 测试（未来 ViewModel 测试只需 `HotkeyServiceMock`）
- `AsyncStream` 单向数据流，consumer 不能反向调 service
- `updateBinding` 不需要 stop+start，只改内部状态（避免 monitor 抖动）
- `isRunning` 状态可读（设置页 UI 用得到）

---

## 5. 实现路径

按可独立验证拆分：

| # | 子任务 | 验证方式 |
|---|---|---|
| 5.1 | 创建 `Package.swift` + `OpenLessHotkey` library + `HotkeyDemo` executable | `swift build` 通过 |
| 5.2 | 写 `HotkeyEvent` / `HotkeyBinding` / `HotkeyError` 三个值类型 + 单元测试 | `swift test` 通过 |
| 5.3 | 写 `InputMonitoringPermission` + 一行权限检查测试 | 调 `isGranted()` 不崩溃 |
| 5.4 | 写 `HotkeyMonitor` NSEvent 安装/卸载逻辑（不处理事件） | start/stop 不崩溃，NSEvent monitor 正确装卸 |
| 5.5 | 实现 `flagsChanged` 处理 → 发出 pressed/released | `HotkeyDemo` 跑起来按 right_option 能看到 console 输出 |
| 5.6 | 实现 `keyDown` Esc 处理 → 发出 cancelled | 按 right_option + Esc 看到 cancelled |
| 5.7 | 实现 `updateBinding` 热切换 | demo 里切到 fn，按 fn 能触发 |
| 5.8 | 启动时同步当前 modifier 状态（避免漏 pressed） | 程序启动时已按住 right_option，调 start 后第一次松开能触发 released |

---

## 6. 验收标准（Goal-Driven）

1. ✅ `swift build` 在干净环境编译通过
2. ✅ `swift test` 全部单元测试通过
3. ✅ `swift run HotkeyDemo` 启动 5 秒后按住 `right_option` 1 秒再松开，console 输出严格三行：
   ```
   [hotkey] pressed
   [hotkey] released
   ```
   按 `Esc` 在按下 `right_option` 期间，应额外输出 `[hotkey] cancelled`
4. ✅ 切换 binding 到 `fn` 后，按 `right_option` 不再触发；按 fn 触发
5. ✅ 模块只 import `AppKit` / `IOKit.hidsystem` / `Foundation`，**不 import 其它业务模块**

---

## 7. 自我审查（Step 2 内嵌）

> 在编码前回看本规划，确认入口、边界、错误路径无漏。

### 7.1 入口正确性

- `HotkeyMonitor.init()`：仅创建 AsyncStream + continuation；不安装 monitor。✅
- `start(binding:)`：先权限检查 → 装 NSEvent monitor → 同步当前 modifier 状态 → 设 `isRunning = true`。✅
- `stop()`：卸 monitor → 如果当前 isPressed，最后发一个 `.released` → 设 `isRunning = false`。✅
- `updateBinding(_:)`：只改 `self.binding`；如果旧 trigger 当前 active 但新 trigger 不 active，发 `.released`。✅

### 7.2 边界情况

| 情况 | 处理 |
|---|---|
| 程序启动时用户已按住 `right_option` | start 后立即查 `NSEvent.modifierFlags`，若 active → 发 `.pressed` |
| 用户连续快速按下/松开（< 50ms） | 不 debounce，直接传递；上层判断是否有效（v1 由 Coordinator 决定最短录音长度） |
| 用户按住 right_option + 按 cmd | 仍是 right_option 按下，`flagsChanged` 触发但 `isTriggerActive` 仍 true → 不重复发 pressed |
| 用户在我们的 Settings 窗口聚焦时按 right_option | `addLocalMonitorForEvents` 接住，与全局 monitor 行为一致 |
| Esc 按下但 `right_option` 未按下 | 忽略，不发 `cancelled`（避免影响其它 app 的 Esc 用法） |
| `stop()` 时未发 `.released` 的 pressed 状态 | 在 stop 内显式发 `.released` 收尾 |
| 程序退出时 stream 没关闭 | `deinit` 调 `continuation.finish()` |

### 7.3 错误路径

- 权限缺失：`start` 抛 `inputMonitoringNotGranted`，调用方负责弹引导
- 重复 start：抛 `alreadyRunning`
- 在未 start 时 stop：no-op，不抛错（容错友好）
- NSEvent.addGlobalMonitorForEvents 返回 nil（理论极少）：抛 `inputMonitoringNotGranted`

### 7.4 跨线程安全

`HotkeyServiceProtocol` 标 `@MainActor`，强制调用方在主线程使用。`AsyncStream` consumer 可以在任意 actor 消费。✅

### 7.5 与未来架构的一致性

- 协议 → 实现分离 ✅（满足 §4.5 MVVM 推断）
- 不依赖业务模块 ✅
- 不持有 UI 引用 ✅
- 事件流单向 ✅
- 测试可注入 mock ✅

**结论**：规划无漏洞，可进入编码阶段。

---

## 8. 后续要更新的架构文档

完成后回头改：
- §7 全局快捷键：替换 `KeyboardShortcuts` 为 `OpenLessHotkey` 自实现
- §12 第三方依赖：移除 `KeyboardShortcuts`
- §10 扩展点矩阵：加一行"用户自定义键盘 binding 映射方案" → `HotkeyBinding.Trigger` 加 case 即可
