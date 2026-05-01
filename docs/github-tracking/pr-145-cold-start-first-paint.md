## 摘要

Closes #98
References #143

这个 draft PR 继续承接 Windows cold-start first paint 生命周期问题，但状态已经从“纯问题定义”推进到“主线修复已见效、继续观察”。

本轮最新结论：

- 之前可见的一闪，主要与测试入口使用 backend immediate show 有关
- 冷启动脚本改成 frontend-managed first show 后，首屏体验明显更顺
- 实测主观体验是“几乎没有问题，人眼很难分辨”
- 但为了避免把 startup latency 优化和 lifecycle contract 修复混成一团，这条 PR 仍保持 draft
- `#143` 更适合作为已收敛的 first-paint 症状票；当前主线 closure 由 `#98` 承接

## 修复 / 新增 / 改进

- 保持 draft 角色，继续跟踪 `created -> shown -> first stable paint -> ready`
- 记录测试入口从 backend immediate show 切换到 frontend-managed first show 的影响
- 作为后续 cold-start visual smoke 与更细粒度 startup latency 优化的承接入口

## 兼容

- 不包含：主窗口圆角 / 外框 / 其他视觉适配
- 对现有用户 / 本地环境 / 构建流程的影响：继续只聚焦 startup lifecycle 主线

## 测试计划

- [x] 命令：`powershell -ExecutionPolicy Bypass -File openless-all/app/scripts/windows-cold-start.ps1 -PreferDebug -ShowMain`
- [x] 结果：能够走 frontend-managed first show
- [x] 证据路径：本地命令输出

- [x] 命令：3 秒与 8 秒冷启动截图对比
- [x] 结果：3 秒可见 startup shell；修正测试入口后正式首屏体验显著改善
- [x] 证据路径：`artifacts-cold-start-screenshot.png`、`artifacts-cold-start-screenshot-8s.png`、`artifacts-cold-start-screenshot-front-managed.png`

- [x] 命令：人工主观回归
- [x] 结果：冷启动过程“几乎没有问题，至少人眼很难分辨”
- [x] 证据路径：当前线程回归记录
关联 issue 建议标题：`[ui][windows] 冷启动前几秒出现 UI flash 和 layout drift`
