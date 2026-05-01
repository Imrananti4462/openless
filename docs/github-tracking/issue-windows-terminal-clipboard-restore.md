## 现象 / Symptom

Windows 终端文本输入场景里，用户曾观察到这样一类问题：

- 光标位于终端输入行
- 触发 OpenLess 听写
- 会话结束后，目标最终拿到的不是本次识别/润色后的文本
- 体感像是 OpenLess 先把本次结果写进剪贴板，随后又恢复成听写前的旧剪贴板，导致目标实际 paste 的是旧内容

### 证据 / Evidence

- `openless-all/app/src-tauri/src/insertion.rs`
  - Windows 路径把 synthetic paste 视为 `PasteSent`，旧实现会在固定 `150ms` 后恢复旧剪贴板
- `docs/2026-05-02-windows-terminal-clipboard-restore-investigation.md`
  - 已沉淀完整隔离实验、真实目标回归与整链路自动化证据
- 隔离时序实验已确认 race 模型存在：
  - 快消费者 + `150ms` restore：通过
  - 慢消费者 + `150ms` restore：读到旧剪贴板
  - 慢消费者 + `750ms` restore：恢复正常
- 稳定化完整生命周期自动化已覆盖：
  - `wt-cmd`
  - `wt-powershell`
  - `notepad`
- 当前机器上的稳定化整链路回归结果：
  - 三类目标都收到本次 `finalText`
  - 三类目标都没有收到旧剪贴板哨兵值

### 5 Whys / 根因分析

1. 为什么会怀疑是 clipboard lifecycle 问题？
   - 因为 `PasteSent` 只能证明发出了 synthetic `Ctrl+V`，不能证明目标已经消费完 clipboard。
2. 为什么固定 `150ms` restore 有风险？
   - 因为较慢的目标会在 restore 之后才读取 clipboard，于是会读到旧内容。
3. 为什么用户会在 terminal 里感知到这个问题？
   - terminal 是最容易怀疑的目标类型，但当前证据说明它不是“必现目标”，而是可能触发 race 的一种环境。
4. 为什么现在不能把问题定义成“Windows terminal 通用必现”？
   - 因为稳定化整链路自动化下，`wt-cmd` 和 `wt-powershell` 当前都没有复现该问题。
5. 现阶段最合理的结论是什么？
   - race 模型真实存在，但用户报告的问题具有条件性，还依赖额外环境因子。

### 平台边界 / Platform Scope

- 直接范围：Windows
- 关注层次：`clipboard lifecycle`、`insertion lifecycle`
- 非主因：`focus restore`
- 当前判断：不是“所有 Windows terminal 一定复现”，也不是单纯的全局 Windows clipboard bug

### 认领 / Ownership

- owner intent：`@Cooper-X-Oak`
- 当前对应 draft PR：待创建

## 影响 / Impact

- 会削弱用户对 Windows 听写插入可靠性的信任
- 会让 `PasteSent` 的用户语义与目标实际行为产生偏差
- 会增加 Windows terminal / 文本输入场景下的排障复杂度

## 建议接受标准 / Proposed Acceptance Criteria

- [x] 明确 `PasteSent` 与“实际 paste 已完成”不是同一语义
- [x] 完成最小修复：Windows clipboard restore 从 `150ms` 提高到 `750ms`，并异步 restore
- [x] 提供隔离时序实验，证明 race 条件存在
- [x] 提供稳定化整链路自动化，覆盖：
  - [x] `wt-cmd`
  - [x] `wt-powershell`
  - [x] `notepad`
- [x] 明确当前机器上的稳定化整链路回归未复现用户原始问题
- [ ] 若后续继续追用户原始问题，需要补充更具体的环境条件（terminal host/profile、输入法、焦点切换时序等）

## TODO / 不确定项

- 用户最初复现场景是否依赖特定 terminal host / profile / session state
- 是否存在当前自动化未覆盖的输入法、前台切换或第三方软件干扰
- 是否需要后续把 `PasteSent` 的用户提示文案进一步收紧，避免被理解为“已确认粘贴成功”

建议 issue 标题：`[windows][insertion] 终端旧剪贴板粘贴问题具有条件性，当前整链路回归未复现`
