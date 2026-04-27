# OpenLess 使用说明

面向普通用户。开发者和架构信息见 [README.md](README.md) 与 [CLAUDE.md](CLAUDE.md)。

---

## 1. 下载与解除隔离

到 [Releases](../../releases) 下载最新的 `OpenLess-1.0.0.zip`，解压会得到 `OpenLess.app`。把它拖到 `应用程序`。

由于 1.0 是 ad-hoc 签名构建（没有付费 Apple Developer ID），macOS Gatekeeper 会拦下提示「无法验证开发者」。在终端中执行一次：

```bash
xattr -dr com.apple.quarantine /Applications/OpenLess.app
```

之后双击就能启动。

> 这一步只需要做一次。下次升级版本，覆盖 `OpenLess.app` 后再执行一次同样的命令即可。

## 2. 授权

OpenLess 需要两个系统权限：

| 权限 | 在哪里授权 | 用来做什么 |
| --- | --- | --- |
| 麦克风 | 系统设置 → 隐私与安全 → 麦克风 | 录音 |
| 辅助功能 | 系统设置 → 隐私与安全 → 辅助功能 | 监听全局快捷键 + 把文本写入当前输入框 |

**授权辅助功能后必须退出 OpenLess 并重新打开。** macOS 不会把新授权同步给已经在跑的进程，全局快捷键监听需要进程重启才能生效。

## 3. 配置 ASR 和润色凭据

OpenLess 不内置任何云端 Key，需要你自己提供：

- **火山引擎流式 ASR**：APP ID、Access Token、Resource ID。在火山引擎控制台开通「语音技术 → 流式语音识别」后获取。
- **Ark / DeepSeek 兼容 Chat Completions**：API Key、Model ID、Endpoint。Ark 默认 endpoint 是 `https://ark.cn-beijing.volces.com/api/v3/chat/completions`。

在 OpenLess 主窗口的「设置」标签页填入即可。凭据保存在系统 Keychain（service = `com.openless.app`），不会上传也不会写入仓库。

> 如果不填 Ark：OpenLess 会跳过润色，直接插入 ASR 原文。
>
> 如果不填火山：OpenLess 会跑一段 mock 流程，并把占位文本复制到剪贴板（不会插入到输入框）。

## 4. 日常使用

1. 把光标停在任意输入框（聊天框、邮件、代码编辑器、浏览器地址栏……）。
2. 按一次右 `Option`（默认快捷键）开始录音。底部胶囊会变成红色音量条。
3. 说话。
4. 再按一次右 `Option` 结束录音。胶囊会进入「转写 → 润色」状态。
5. 润色完的文字会自动插入到光标所在位置。如果当前应用拒绝写入，会复制到剪贴板，请手动 `Cmd+V`。
6. 按 `Esc` 在录音过程中取消，原始音频不会发送到 ASR。

> **录音方式可在「设置」里切换：**
> - **切换式**（默认）：按一次开始，再按一次结束。适合长口述。
> - **按住说话**（hold-to-talk）：按住快捷键说话，松开立即结束。适合短句、IM 消息、连续多次输入。

每一次会话都会保存到「历史记录」标签页，包含：录音时长、原始转写、润色后文本、采用的模式。

## 5. 输出模式

在主窗口顶部切换：

| 模式 | 适合场景 |
| --- | --- |
| 原文 | 不想做任何修改，直接拿 ASR 结果。 |
| 轻度润色 | 去口癖、补标点。最常用。 |
| 清晰结构 | 把连贯口语拆成短句、列表。适合需求/任务描述。 |
| 正式表达 | 用更书面的语气重写。适合邮件、公告。 |

模式只影响润色 prompt，不会让模型「回答你说的话」。详见 README 的「提示词处理原则」。

## 6. 词典

「词典」标签页用来教模型识别你的专有名词、产品名、人名和新词。

- 每个词条只需要填正确写法、分类（可选）、备注（可选）。
- 启用的词条会作为火山 ASR 的 `context.hotwords` 提交，识别阶段就尽量正确。
- 同时会注入润色阶段，让模型根据上下文判断是否需要把同音词修正成你的词。例如词典里有 `Claude`，模型听到 `Cloud` 时会根据语境决定要不要改成 `Claude`。

## 7. 排查

- **按快捷键无反应**：辅助功能没授权，或授权后未重启 OpenLess。
- **录音时胶囊一直是灰色**：麦克风没授权，或被其他应用独占。
- **转写一直在转圈**：火山凭据填错，或网络无法访问火山服务。看日志确认。
- **文字没插入但被复制了**：当前应用拒绝 AX 写入和 Cmd+V，按 `Cmd+V` 手动粘贴。
- **看日志**：

  ```bash
  tail -f ~/Library/Logs/OpenLess/OpenLess.log
  ```

## 8. 卸载

```bash
rm -rf /Applications/OpenLess.app
rm -rf ~/Library/Application\ Support/OpenLess
rm -rf ~/Library/Logs/OpenLess
rm -rf ~/.openless
```

Keychain 里的凭据可以用「钥匙串访问.app」搜索 `com.openless.app` 删除。
