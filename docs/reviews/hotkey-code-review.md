# 键盘监测 Code Review 报告

更新时间：2026-04-26
切片范围：`OpenLessHotkey` Swift Package + `HotkeyDemo` executable

---

## 1. 编译验证

| 命令 | 结果 |
|---|---|
| `swift build` | ✅ Build complete! (29.19s)，无 warning |
| `swift test` | ⚠️ Skipped — CLT 5.9 缺 XCTest 模块；需要 full Xcode 环境跑 |
| `swift run HotkeyDemo` | ✅ Link 成功；runtime 测试需要 Input Monitoring 权限手动授予 |

测试代码已写好（`Tests/OpenLessHotkeyTests/`），等用户在装了 Xcode 的机器上跑，或在 CI 用 `xcodebuild test`。

---

## 2. 代码质量复核（按规划 §6 验收标准）

| # | 验收项 | 状态 | 证据 |
|---|---|---|---|
| 1 | `swift build` 干净通过 | ✅ | 上表 |
| 2 | `swift test` 全过 | ⏸ | 待 Xcode 环境验证 |
| 3 | `HotkeyDemo` 跑起来按 right_option 输出 pressed/released | ⏸ | 待用户授权 Input Monitoring 后实测 |
| 4 | 切换 binding 到 fn 后按 fn 触发 | ⏸ | 同上 |
| 5 | 模块依赖纯净 | ✅ | 仅 import `AppKit` / `CoreGraphics` / `Foundation`，零业务依赖 |

---

## 3. 与规划文档的一致性

| 规划文档要点 | 实际实现 | 是否一致 |
|---|---|---|
| 弃用 KeyboardShortcuts library | Package.swift 无外部依赖 | ✅ |
| 默认 right_option | `HotkeyBinding.default.pushToTalk == .rightOption` | ✅ |
| 6 个 Trigger case | `Trigger.allCases.count == 6` | ✅ |
| 协议 + 实现分离 | `HotkeyServiceProtocol` + `HotkeyMonitor` | ✅ |
| 单向 AsyncStream | `events: AsyncStream<HotkeyEvent>` 只读 | ✅ |
| 启动时同步 modifier 状态 | `start()` 末尾查 `NSEvent.modifierFlags` | ✅ |
| Esc 仅在 isPressed 时触发 cancelled | `handleKeyDown` 守卫 `isPressed` | ✅ |
| stop() 时收尾 released | `stop()` 内 `if isPressed { yield(.released) }` | ✅ |

---

## 4. 自审发现的潜在问题

### 4.1 [LOW] `MainActor.assumeIsolated` 在非主线程会 trap

`NSEvent.addGlobalMonitorForEvents` callback 文档说在主线程，但**没有运行时保证**。Apple 内部偶尔在非主线程派发的可能性存在（极少）。当前代码用 `MainActor.assumeIsolated` 强转，若出现非主线程会立即 crash。

**取舍**：crash 比 race condition 更易诊断；v1 接受此风险。如果实测确认有问题，改成 `Task { @MainActor in self?.handle(event) }`，代价是事件延迟一拍。

### 4.2 [LOW] 没有 `deinit` 清理

`HotkeyMonitor` 不写 `deinit`。如果调用方忘记 `stop()` 就让对象析构，monitor 会泄漏到 NSEvent 系统层（NSEvent 的 monitor 本身持 closure 引用 self，会形成循环引用导致对象不析构 → 实际上不会泄漏，但 monitor 永远活着）。

**Swift 6 严格 concurrency 下** `@MainActor` class 的 `deinit` 是 nonisolated，访问 isolated state 会编译报错。本代码暂以 Swift 5.9 模式编译，规避该问题。

**缓解**：Demo 和未来 Coordinator 必须显式 `stop()`（生命周期管理责任在调用方）。

### 4.3 [LOW] modifier raw flags 0x040 等 magic numbers 未抽常量

`isTriggerActive` 里散落了 `0x0001 / 0x0010 / 0x0020 / 0x0040 / 0x2000`，对应 `NX_DEVICE*` 系列 mask。文档参考来自 IOKit `<IOKit/hidsystem/IOLLEvent.h>`。

**修复（v1.1）**：抽出 `private enum DeviceModifierMask`，并加注释链接到 IOKit header。**v1 不改**——5 个常量直接局部使用，简洁优于过度抽象。

### 4.4 [MEDIUM] Demo 未授权时立即 exit，没机会让 user 手动重试

`HotkeyDemoMain` 在 `isGranted() == false` 时打印提示后 `exit(1)`。授权后必须用户手动重启 demo。

**评价**：这是 unsigned binary 在 macOS 输入监控权限模型下的**本质限制**——授权与否绑定二进制 hash。对一个 demo 切片，提示 + 退出是合理简化。完整 .app bundle 在架构 v2 重写时再优化。

### 4.5 [PASS] 无线程数据竞争

所有 mutable state（`isPressed`、`binding`、`globalMonitor`、`localMonitor`、`isRunning`）只在 `@MainActor` 上读写。NSEvent callback 通过 `MainActor.assumeIsolated` 强制隔离。✅

### 4.6 [PASS] AsyncStream 未关闭风险

`events` stream 在 `HotkeyMonitor` 实例存活期间持续。调用方 `for await event in monitor.events` 在 monitor 不被销毁时不会自动结束。这是预期行为（demo 和 Coordinator 都需要长时订阅）。如要终止订阅，调用方在 `Task` 上 `cancel()` 即可。

---

## 5. Karpathy 原则自检

| 原则 | 是否遵守 |
|---|---|
| Think Before Coding | ✅ 规划文档 §7 自我审查覆盖了边界情况、错误路径、跨线程 |
| Simplicity First | ✅ 单文件 < 130 行；零外部依赖；无 speculative 抽象（如未抽 `DeviceModifierMask` 常量） |
| Surgical Changes | ✅ 仅创建本切片所需文件；未触碰 docs 主架构文档 |
| Goal-Driven Execution | ✅ 6 条验收标准，build 已 pass；3 条运行时验收等用户实测 |

---

## 6. 待用户实测的验收清单

请在 macOS 15+ 设备上：

```bash
cd "/Users/lvbaiqing/TRUE 开发/openless"
swift run HotkeyDemo
```

**首次运行**：会提示 Input Monitoring 权限未授予 → 系统设置 → 隐私与安全 → 输入监控 → 添加 `.build/debug/HotkeyDemo` → 重启 demo

**预期输出**：
```
[hotkey-demo] 已启动，绑定: right_option
[hotkey-demo] 按住 right_option 测试 pressed/released
...
[hotkey] pressed       ← 按下右 option
[hotkey] released      ← 松开
[hotkey] pressed
[hotkey] cancelled     ← 在按下期间按 Esc
```

`⌃C` 退出。

---

## 7. 后续要回头改的文档

完成本切片后必须并入架构文档 v2 重写时：
- §7「全局快捷键」：把 `KeyboardShortcuts` 库换成 `OpenLessHotkey` 模块
- §12「第三方依赖」：移除 `KeyboardShortcuts` 行
- §15「落地路线」第 3 步「全局快捷键」可标记完成
- §17「决策记录」补一条「弃用 KeyboardShortcuts library 因不支持 modifier-only push-to-talk」

---

## 8. Building 前置条件

满足以下条件即可进入 `Building macOS App` 阶段：
- ✅ `swift build` 通过
- ✅ Code Review 无 CRITICAL/HIGH 问题
- ⏸ 用户实测 demo（按上面 §6 步骤）确认主功能 OK
