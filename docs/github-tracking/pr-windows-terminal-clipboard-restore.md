## 摘要

Closes: 待关联 issue

这个 draft PR 用来收敛 Windows 插入路径里的剪贴板恢复时序问题，并补齐从隔离时序实验到完整 OpenLess 生命周期的回归证据。

当前结论不是“terminal 一定会 paste 旧剪贴板”，而是：

- race 模型在隔离实验里真实存在
- 最小修复已经落地
- 当前机器上的稳定化整链路回归未在 `wt-cmd` / `wt-powershell` / `notepad` 上复现用户报告的问题
- 因此该问题应被视为条件性问题，而不是所有 terminal 场景下的通用必现问题

## 修复 / 新增 / 改进

- Windows clipboard restore 从 `150ms` 提高到 `750ms`
- clipboard restore 改为后台线程执行，不阻塞插入返回
- 新增 Windows clipboard timing smoke，用于证明慢消费者 race
- 新增稳定化整链路自动化脚本，覆盖：
  - `wt-cmd`
  - `wt-powershell`
  - `notepad`
- 调整目标读回方式：
  - terminal 走 UIA 读取 `TermControl`
  - notepad 走 UIA 直接读取文本
- 新增 debug-only transcript override，用于桌面音频路由不稳定时继续覆盖真实 insertion 尾链
- 更新调查文档，沉淀隔离实验与整链路回归结论

## 兼容

- 正常用户路径不依赖 debug transcript override
- debug transcript override 仅在 `debug_assertions` / test 构建下参与
- Linux restore delay 保持原行为
- 不涉及 UI/视觉顺手修改
- 不涉及 QA hotkey / selection 主线逻辑修改

## 测试计划

- [x] `cargo fmt --all`
- [x] `cargo check --lib`
- [x] `python -m py_compile openless-all/app/scripts/windows-openless-lifecycle-e2e.py`
- [x] `windows-real-asr-insertion-smoke.ps1` 脚本解析通过
- [x] 隔离时序实验：
  - [x] 快消费者 + `150ms`
  - [x] 慢消费者 + `150ms`
  - [x] 慢消费者 + `750ms`
- [x] 稳定化整链路自动化：
  - [x] `wt-cmd`
  - [x] `wt-powershell`
  - [x] `notepad`
- [x] 证据路径：
  - `docs/2026-05-02-windows-terminal-clipboard-restore-investigation.md`
  - `docs/github-tracking/issue-windows-terminal-clipboard-restore.md`

## 当前结论

- root cause：
  - `PasteSent` 被误当成“paste 已完成”
  - 旧实现会在目标实际消费 clipboard 前恢复旧剪贴板
- 但当前稳定化整链路回归表明：
  - `wt-cmd`、`wt-powershell`、`notepad` 在本机都能拿到本次 `finalText`
  - 因此用户原始问题仍然依赖额外环境条件

## 剩余风险

- `750ms` 仍是启发式保护，不是目标确认式握手
- 条件性 race 仍可能在更慢或更特殊的目标环境下出现
- 如果后续要继续追原始问题，建议单独 follow-up 到更窄的环境变量，而不是继续扩大当前 PR 范围

建议 PR 标题：`fix(windows): 延后剪贴板恢复并补齐插入回归覆盖`
