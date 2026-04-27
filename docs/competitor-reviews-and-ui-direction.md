# OpenLess 竞品评论、产品基调与 UI 方向调研

生成日期：2026-04-26

## 1. 本轮结论

当前项目根目录为 `openless`，因此本文把我们的产品名暂定为 **OpenLess**。OpenLess 的直接竞品不是单一产品，而是一组 AI 语音输入工具：Typeless、Wispr Flow、Aqua Voice、Superwhisper、Willow Voice、TalkTastic、MacWhisper，以及本机正在使用的 LazyTyper。

这类产品的核心竞争已经从“语音转文字准确率”升级为“全局输入体验”：

- 用户想要的是说完就能用，而不是拿到一段原始 transcript。
- 用户最在意的是速度、稳定、插入成功率、润色质量、隐私和价格。
- 用户最不满的是移动端键盘体验差、录音中断、结果丢失、插入失败、订阅太贵、隐私解释不透明。
- 对 OpenLess 来说，第一轮最值得打的差异点是：Mac 原生底部微型状态胶囊、本地优先/可选云增强、稳定兜底、轻量 UI、不过度 AI 化的润色，以及中英混输和开发者 prompt 体验。

## 2. 竞品到底在做什么

| 产品 | 正在做什么 | 用户方向 | 解决痛点 |
|---|---|---|---|
| Typeless | 全平台 AI voice keyboard，把自然语音变成 polished text | 普通知识工作者、移动端用户、AI 工具重度用户 | 手机/电脑打字慢、语音转写太生硬、长 prompt 难打 |
| Wispr Flow | 跨设备语音输入层，强调 auto edits、styles、dictionary、command mode | 高强度办公、销售、写作者、开发者、团队 | 在所有 app 里快速输入，语气按 app 自动调整 |
| Aqua Voice | 开发者和技术写作导向的高速 dictation，强调 context 和 Avalon 模型 | 开发者、vibe coding 用户、技术写作者 | 技术词、文件名、代码场景识别差，普通 dictation 不懂上下文 |
| Superwhisper | 可配置、本地/云混合、模式系统强的 power-user 工具 | 隐私敏感用户、Mac/iOS power users、需要自定义 prompt 的人 | 需要本地模型、BYOK、自定义模式、历史重处理 |
| Willow Voice | iOS/Mac 语音键盘和 AI rewrite，强调编辑能力和格式化 | 移动端办公用户、邮件/聊天/文档用户 | iOS 原生听写不够准，跨 app 输入难编辑 |
| TalkTastic | macOS context-aware voice keyboard，强调 screen context 和 rewrite | Mac 办公用户、非英语母语、ADHD/无障碍用户 | 用户说的是乱的，但需要输出符合当前屏幕上下文 |
| MacWhisper | 以本地转写为核心，附带 dictation 和 AI prompt | 会议/音频转写用户、隐私敏感 Mac 用户 | 音频文件转写、离线、一次性付费 |
| LazyTyper | 免费/轻量/多模型语音输入，支持本地和云端模型 | 中英混输用户、开发者、免费工具用户 | 不想订阅 Typeless/Wispr，想要多模型和本地模型 |

## 3. 评论内容与不足总结

### 3.1 Typeless

参考来源：[Typeless 官网](https://www.typeless.com/)、[Typeless App Store 评论](https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650)、[Reddit 讨论](https://www.reddit.com/r/macapps/comments/1qwn64o/looking_at_dictation_apps_typeless_clear_winner/)

用户喜欢：

- 输出不是机械转写，而是能把粗糙想法变成更清楚的文本。
- punctuation 和 inference 被多次提到，尤其是能根据说话方式补标点和引号。
- 对 AI 对话、长 prompt、长文档很有帮助，用户觉得“思考速度不再被键盘卡住”。
- 学习成本低，有用户说大概一分钟就能上手。
- 移动端和桌面都有，跨设备覆盖强。

用户抱怨：

- iOS 键盘交互还不够稳定，尤其是进入语音键盘、保持语音界面激活、滑动切换等细节。
- 有用户反馈长语音会提前结束录音，导致长内容体验不可靠。
- 有评论提出移动端语音键盘高度太大，想要横向低矮的 mini mode，以减少屏幕占用。
- Reddit 上有隐私担忧，尤其是用户不清楚上下文和历史到底如何被使用。
- 对价格和长期订阅也有抵触，尤其是想要 lifetime license 的用户。

对 OpenLess 的启发：

- 不要只做 ASR，要把“粗糙想法变成可用文本”作为主卖点。
- 必须提供长语音防丢机制：录音中断也能找回片段。
- macOS 端第一轮可以避开 iOS 第三方键盘限制，先把桌面体验做到极稳。
- UI 要比移动键盘更轻，底部胶囊要小、可隐藏、不挡内容。
- 隐私说明要前置，不要让用户猜产品是否读取屏幕或保存音频。

### 3.2 Wispr Flow

参考来源：[Wispr Flow 官网](https://wisprflow.ai/)、[Wispr Flow Features](https://wisprflow.ai/features)、[Wispr Flow Auto Cleanup](https://docs.wisprflow.ai/articles/4136931124-how-to-use-auto-cleanup-beta)、[Wispr Flow Styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles)、[Wispr Flow App Store 评论](https://apps.apple.com/us/app/wispr-flow-ai-voice-dictation/id6497229487?see-all=reviews)、[Reddit 价格讨论](https://www.reddit.com/r/SaaSy/comments/1srmzu9/wispr_flow_pricing_is_it_actually_worth_paying/)

用户喜欢：

- 准确率、速度、低打扰度是核心好评。
- 用户觉得它在邮件、聊天、文档里比原生 dictation 更像“写出来的文字”。
- Flow Styles 和 Auto Cleanup 是很强的差异点：用户可以按 Formal、Casual、Very Casual、Excited 等风格调整输出。
- Command Mode 能处理选中文本，用户可以用语音让它改短、翻译、搜索。
- 个人词典、snippets、跨设备同步对高频用户有价值。

用户抱怨：

- 价格被大量讨论，典型抱怨是“不确定每月订阅是否值得”，或者免费额度/试用边界不够清楚。
- Reddit 上有用户认为营销强调免费，但“完整语音 dictation 是 limited time”这类表述容易让人失望。
- 隐私争议集中在屏幕上下文、截图/上下文采集、云端处理、权限范围是否足够透明。
- 有用户反馈质量波动，某段时间准确率下降后导致自己又回去打字。
- iOS 长文本体验不稳定，有人抱怨几分钟长 dictation 崩溃或退出后内容丢失。
- 官方文档中也承认 Android Flow Bubble / desktop Flow Bar 可能出现不显示、消失、闪烁、文本落到错误输入框、waveform 不响应等问题。

对 OpenLess 的启发：

- 自动润色要提供可控强度，而不是只有“开/关”。
- 免费/付费边界必须简单透明，避免“看起来免费，实际核心被限”的落差。
- 上下文读取必须有明显开关和清楚说明，最好默认只读必要上下文。
- 录音失败、插入失败、字段失焦时必须自动保存在历史和剪贴板。
- Flow 的最大机会点是“强但复杂”，OpenLess 可以主打“更安静、更可控、更透明”。

### 3.3 Aqua Voice

参考来源：[Aqua 官网](https://aquavoice.com/)、[Aqua Product Hunt 评论](https://www.producthunt.com/products/aqua/reviews)、[Aqua App Store 评论](https://apps.apple.com/us/app/6759074969?platform=iphone&see-all=reviews)、[Aqua Guide](https://aquavoice.com/guide/)、[Aqua History](https://aquavoice.com/guide/history)、[Aqua Replacements](https://aquavoice.com/guide/replacements)、[Reddit 讨论](https://www.reddit.com/r/macapps/comments/1qg73sx/wispr_flow_vs_aqua_voice/)

用户喜欢：

- 高频好评是快、准、技术词识别强。
- 开发者尤其喜欢它能利用屏幕上下文，在 Cursor、Windsurf、代码编辑器里识别术语、文件名、变量。
- Product Hunt 上用户反复提到它比其他工具更适合 coding、Slack、Notion、email。
- Replacements 和 Dictionary 对重复 prompt、邮箱、链接、术语很实用。
- History 支持本地保存音频、重跑转写、复制到剪贴板，这是强兜底。

用户抱怨：

- Product Hunt 总结里提到偶尔会错过 transcript 或 paste，需要重试。
- 需要网络访问仍然是隐私和可用性顾虑。
- 用户要求 iOS、移动端、Linux、offline 支持。
- Reddit 上有人说 Aqua 输出有时像一整段，没有足够分行或格式化。
- 有用户想要更好的 whisper/quiet dictation，因为公共环境讲话仍然尴尬。

对 OpenLess 的启发：

- 开发者模式值得做，但第一轮不必直接挑战 Aqua 的深度代码上下文。
- OpenLess 可以把“结构化分段”和“不过度一段流”做成默认优势。
- History 要像 Aqua 一样成为安全网，但默认更隐私：原始音频是否保存应由用户选择。
- Replacements 适合第一轮做，因为它实现成本低、用户感知强。

### 3.4 Superwhisper

参考来源：[Superwhisper 官网文档](https://superwhisper.com/docs)、[Superwhisper Recording Window](https://superwhisper.com/docs/get-started/interface-rec-window)、[Superwhisper History](https://superwhisper.com/docs/get-started/interface-history)、[Superwhisper Modes](https://superwhisper.com/docs/modes)、[Superwhisper App Store 评论](https://apps.apple.com/us/app/superwhisper/id6471464415?platform=ipad&see-all=reviews)、[Reddit iOS 反馈](https://www.reddit.com/r/superwhisper/comments/1s6ul36/ios_app_is_barely_useable/)

用户喜欢：

- 本地模型和隐私是它的核心好评。
- 模式系统强：Voice to Text、Message、Email、Note、Super、Meeting、Custom。
- 支持本地/云模型、BYOK、自定义 prompt、上下文感知，适合 power users。
- Recording Window 有实时 waveform、状态点、当前模式、context capture 指示、stop/cancel。
- History 很完整：可搜索、重处理、查看 Voice 原始转写和 AI 处理结果、复制、查看 prompt 和 metadata。

用户抱怨：

- iOS 键盘体验被多次批评：切回原 app 失败、不自动粘贴、崩溃、录音丢失。
- 有用户说桌面不错，但移动端差。
- 有用户反馈“no voice recording found”导致内容丢失。
- 某些用户认为支持响应慢，问题长期未解决。
- 自定义模式强但也复杂，如果 prompt 没写好，产品可能把用户语音当成命令去执行，而不是转写。
- lifetime 价格较高，部分用户对价格敏感。

对 OpenLess 的启发：

- History 面板非常值得借鉴，但 OpenLess 第一轮应该更简单，只保留原始转写、润色结果、复制、重跑模式。
- 不要把 mode 系统做得太复杂，第一轮固定 4 个模式即可。
- 要避免“AI 执行命令而非转写”的问题：默认润色 prompt 必须明确只整理文本，不回答、不执行。
- 底部状态胶囊可以借鉴 Superwhisper 的 waveform 和状态点，但要比它更小、更轻，只做提醒，不做大控制台。

### 3.5 Willow Voice

参考来源：[Willow 官网](https://willowvoice.com/)、[Willow App Store 评论](https://apps.apple.com/us/app/willow-ai-voice-dictation/id6753057525)、[Willow 自动格式化指南](https://help.willowvoice.com/en/articles/13183983-voice-commands-and-automatic-formatting-guide)、[TechCrunch 报道](https://techcrunch.com/2025/11/12/willows-voice-keyboard-lets-you-type-across-all-your-ios-apps-and-actually-edit-what-you-said/)、[Willow 故障排查](https://help.willowvoice.com/en/articles/12279120-dictation-quality-or-transcription-issues)

用户喜欢：

- iOS 端提供完整键盘，比只有数字键盘的竞品更便于临时修改。
- 自动格式化能力强：标点、段落、列表、引号、邮件结构。
- 支持 rewrite suggestions，适合发消息前调整 tone、grammar、length。
- 支持 100+ languages、个人词汇、不同 app category 的 writing styles。

用户抱怨：

- App Store 有用户明确抱怨键盘高度太高：下方增加全局快捷键行，上方又有较高的 dictation UI，导致空间被挤占。
- 后台持续录音让用户有隐私和电量担忧。
- 如果关闭后台录音，每次使用又要跳转到 dictation app，打断体验。
- 官方故障排查提到会遇到 dictation quality drop 或 transcription failure，常见原因包括蓝牙麦克风、网络、背景噪音、输入音量、说话太轻等。

对 OpenLess 的启发：

- macOS 底部胶囊一定要控制高度，不要占据太多阅读空间。
- 录音状态要非常明确，不能让用户觉得“它是不是一直在听”。
- 不要默认后台持续录音；OpenLess 应该是明确 push-to-talk 或 toggle-to-talk。
- 自动格式化值得借鉴，但 voice commands 要作为高级能力，不应成为第一轮使用门槛。

### 3.6 TalkTastic

参考来源：[TalkTastic Start Here](https://help.talktastic.com/en/articles/9554689-new-to-talktastic-start-here)、[TalkTastic Components](https://help.talktastic.com/en/articles/9654601-talktastic-components)、[TalkTastic Product Hunt 评论](https://www.producthunt.com/products/talktastic/reviews)

用户喜欢：

- 它不只是转写，而是会根据屏幕上下文进行 rewrite。
- Product Hunt 评论总体把它看作 polished voice-writing tool，适合 thinking out loud、draft emails、posts、notes。
- 用户喜欢 quick access、OS integration、summaries、rewrites，以及用 iPhone 当麦克风。
- TalkTastic 的 transcript windows 同时展示 cleaned transcript 和 AI rewrite，增强信任感。

用户抱怨或潜在风险：

- 上下文依赖 snapshot/screenshot，会触发隐私敏感。
- TalkTastic 文档提到 snapshot 可保存、删除或关闭，这说明默认上下文能力虽然强，但用户必须理解它。
- UI 上有 Active Microphone Bubble、transcript windows、menu bar、多种快捷方式，能力强但可能略重。
- macOS-only，跨平台不足。

对 OpenLess 的启发：

- “原始转写 + 润色结果”双结果非常值得做，能降低用户对 AI 改写的不信任。
- 上下文功能第一轮只做轻量：active app 类型、输入框文本、选中文本，不默认截图。
- 上下文提示不应常驻挤在胶囊里，可以在胶囊展开态或设置页显示。

### 3.7 MacWhisper

参考来源：[MacWhisper Dictation](https://macwhisper.helpscoutdocs.com/article/14-how-to-use-the-dictation-feature)、[MacWhisper 版本差异](https://macwhisper.helpscoutdocs.com/article/40-macwhisper-whisper-transcription-difference)、[Product Hunt 评论](https://www.producthunt.com/products/macwhisper/reviews)、[Reddit 讨论](https://www.reddit.com/r/MacWhisper/comments/1kw3qcn)、[Reddit 近期反馈](https://www.reddit.com/r/MacWhisper/comments/1stvuxm/macwhisper_is_the_best_tool_i_cant_fully_rely_on/)

用户喜欢：

- 本地转写、准确、便宜/一次性付费是主要优势。
- 对音频文件、会议、YouTube、字幕、批量转写这类任务更强。
- 直接下载版支持在任意文本框 dictation。
- 支持 AI prompt 处理 dictation，比如清理错误、翻译、扩写成客服邮件。

用户抱怨：

- 作为 dictation 工具，实时性不如专门的 voice input 工具。
- Reddit 有用户反馈 34 秒才完成转写，对日常输入太慢。
- 有用户遇到 AI prompt 把口述当成给 ChatGPT 的指令，而不是返回原文。
- 有近期用户说它很好但不能完全依赖：转写挂住、summary 忽略语言和 prompt、auto-export 静默失败。
- 历史和 dictation 的查找/恢复体验对部分用户不够直观。

对 OpenLess 的启发：

- OpenLess 不应该第一轮做会议/文件转写，避免和 MacWhisper 主战场重叠。
- 核心要做“实时输入”和“插入稳定”，而不是复杂音频工作台。
- AI prompt 要强约束：只整理用户语音，不回答、不扩写、不执行。

### 3.8 LazyTyper

参考来源：[LazyTyper 官网](https://lazytyper.com/)、[LazyTyper Reddit 发布帖](https://www.reddit.com/r/macapps/comments/1mt8z2x/couldnt_find_a_good_free_voicecoding_tool_so_i/)、本机 `/Applications/LazyTyper.app` 包信息与本地配置观察。

公开资料显示：

- LazyTyper 主打免费、轻量、多模型、Windows/macOS/Linux。
- 支持 12 个 speech models，其中包含 5 个本地/offline 选项。
- 官网强调中英混输、技术词、3x typing speed、90% accuracy、无广告。
- Reddit 发布帖强调 global hotkey、push-to-talk、写入任意 editor 或 terminal。

本机观察到：

- 安装版本为 1.8.7，bundle id 为 `com.lazytyper.desktop`。
- 这是一个 `LSUIElement` 菜单栏型应用，不默认显示 Dock 主窗口。
- 权限说明包括麦克风和 Accessibility，用于语音输入和在光标处输入文字。
- 默认快捷键配置显示：反引号用于按住录音，`Control+Command+V` 用于粘贴上一条结果，鼠标中键可作为录音并回车动作。
- 本地功能痕迹包括 AI polishing、history、audio_history、local-models、styles、text replacement、floating bubble、local preview、audio level to bubble、transcript to bubble。
- 本地模型目录显示它已下载多种模型，例如 Paraformer、Parakeet、SenseVoice、Whisper.cpp、Qwen ASR 等。

用户/产品不足推断：

- 它的优势是免费和模型多，但 UI 可能偏工具型，不是 Typeless/Wispr 那种极简消费级体验。
- 多模型选择对 power users 有吸引力，但普通用户容易困惑。
- 本地 `audio_history` 存在大量音频文件，说明“历史是否保存音频”必须在 OpenLess 里做成明确设置。
- 日志显示它会进行 post-edit learning / focus 检测 / text injection，这类能力强，但也会带来隐私解释压力。

对 OpenLess 的启发：

- 可以借鉴 LazyTyper 的快捷键哲学：录音、粘贴上一条、录音后回车，三件事都很高频。
- 不要在第一屏暴露太多模型名。OpenLess 默认只给用户“快 / 准 / 私密”这类选择。
- 底部状态胶囊要比 LazyTyper 更像产品化输入层，而不是开发者工具面板。

## 4. 我们相比竞品能做得更好的地方

### 4.1 更透明的隐私模型

竞品普遍需要麦克风、Accessibility、上下文读取，甚至截图或屏幕上下文。用户真实担忧不是“完全不能读”，而是“不知道你读了什么、存了什么、什么时候读”。

OpenLess 应做到：

- 麦克风只在用户明确按键时开启。
- 底部胶囊显示明确录音状态。
- 默认不保存原始音频，或首次使用时明确询问。
- 如果保存历史，默认只保存文本，音频保存另设开关。
- 上下文分级：无上下文、仅 active app、输入框文本、选中文本、截图，逐级授权。
- 每次使用上下文时，可以在胶囊展开态或菜单栏里显示小标签，例如 `Context: App`、`Context: Selection`；默认胶囊不常驻标签。

### 4.2 更小、更安静的 macOS 状态胶囊

用户对 Willow/Typeless iOS 键盘高度的抱怨说明：语音输入 UI 不能抢屏幕。Mac 上的机会是做一个底部居中的微型 glass capsule。

OpenLess 应做到：

- 默认高度控制在 32-38px。
- 不遮挡主内容，贴近屏幕底部，类似 macOS 系统提示和录音控制条的混合体。
- 只在录音、处理、结果短暂停留时出现。
- 空闲时完全消失，或收成一个 8-12px 的极淡小点。

### 4.3 更强的失败兜底

竞品评论反复出现：录音中断、插入失败、字段失焦、app 崩溃、长语音丢失。

OpenLess 第一轮必须把“失败时不丢内容”作为基本体验：

- 录音结束后先进入最近记录，再尝试插入。
- 插入失败时自动复制到剪贴板并提示。
- 最近记录同时保存原始转写和润色结果。
- 支持“粘贴上一条结果”快捷键。
- 处理超过一定时长时，底部胶囊展示可取消但不丢数据的状态。

### 4.4 不过度 AI 化的润色

竞品的 polish 很强，但用户会反感模板腔、过度正式、擅自扩写。

OpenLess 的基调应是：

- 像用户认真打出来的文字，不像 AI 替用户写的文章。
- 默认清晰，但克制。
- 提供轻度润色，服务聊天、微信、内部 IM。
- 正式模式只在用户选择或邮件场景中增强。
- 保留中英混输和用户常用短句。

### 4.5 更适合中文和中英混输

很多竞品的 style 功能主要面向英文。LazyTyper 官网强调中文输入比拼音更快，说明中文用户有很大需求。

OpenLess 应把中文和中英混输作为第一轮核心，而不是“也支持”：

- 中文口癖清理：嗯、啊、那个、就是、然后、对吧。
- 中英技术词保留：feature、merge、schema migration、PR、Cursor、Supabase。
- 中文标点习惯：中文句号、顿号、冒号、列表。
- 英文单词大小写和品牌名修正。

### 4.6 更清楚的价格和定位

Wispr/Typeless 最大付费阻力是订阅。OpenLess 可以用更亲民策略建立初期口碑：

- 免费版给足基础使用，不做 misleading “limited time”。
- Pro 提供本地模型、高级润色、历史、词典、更多字数。
- 可考虑买断或 BYOK，吸引反订阅用户。

## 5. 竞品功能实现方式与最终效果

### 5.1 通用实现方式

这类产品的共同链路大致是：

1. 全局快捷键或悬浮按钮启动录音。
2. 音频进入 ASR，可能是云端模型、本地 Whisper/Parakeet/Paraformer/SenseVoice，或自研模型。
3. 转写结果进入 LLM/规则层，做去口癖、标点、结构化、语气、词典、片段替换。
4. 读取上下文：active app、输入框文本、选中文本、剪贴板、屏幕截图或文件名。
5. 将结果插入当前光标位置，失败则复制到剪贴板。
6. 保存历史，用于找回、重跑、复制、反馈。

### 5.2 最终效果基准

OpenLess 第一轮的效果基准应是：

- 用户按住快捷键，说一句自然口语。
- 底部胶囊出现，显示正在录音和实时音量反馈。
- 松开后进入处理中状态。
- 1-3 秒内把润色结果插入当前输入框。
- 如果不能插入，复制到剪贴板，并在底部胶囊提示。
- 用户可以打开最近记录，看到原始转写和润色文本。

### 5.3 动画和状态效果参考

竞品可参考的 UI/动画效果：

- Wispr Flow：Flow Bar / Flow Bubble；Android 上文本框出现时显示浮动 bubble；录音后可 checkmark 插入；失败/阻塞用通知提示；新版本强调更平滑、不打扰的 notification UI。
- Superwhisper：主录音窗口有 waveform、状态点、模式显示、context capture 指示、stop/cancel；mini window hover 后展开控制；录音时 waveform 动态响应音量。
- TalkTastic：Active Microphone Bubble 表示录音；transcript windows 展示 cleaned transcript 和 AI rewrite；menu bar 控制 snapshot/context/auto-paste。
- Aqua：强调 streaming mode 和 history；历史中可重跑转写、复制、反馈 thumbs up/down。
- LazyTyper：本机包和配置显示它有 floating bubble、audio level to bubble、transcript to bubble、local preview、paste last result 等能力。

OpenLess 的动画基调应是：

- 轻，不要炫。
- 录音时有音量波动，让用户知道正在听。
- 处理时有明确但短暂的进度反馈。
- 成功插入时给一个小 check，不要大弹窗。
- 失败时出现可操作提示：已复制、查看最近记录、重试插入。
- 底部胶囊出现和消失使用 macOS 风格 spring motion，不要 web 弹窗感。

## 6. UI 与设计参考

### 6.1 当前产品与竞品名称

当前产品暂定名：**OpenLess**。

OpenLess 的含义可以解释为：

- Less typing。
- Less friction。
- Less keyboard。
- Open your thoughts, less effort。

当前对标竞品：

- 主对标：Typeless、Wispr Flow。
- 技术/开发者对标：Aqua Voice。
- 隐私/本地对标：Superwhisper、MacWhisper、LazyTyper。
- 上下文 UI 对标：TalkTastic、Wispr Flow、Superwhisper。

### 6.2 LazyTyper 浮层观察

公开网页没有展示足够清楚的底部浮层细节，但本机安装的 LazyTyper 可以确认其产品形态：

- 菜单栏常驻，不占 Dock。
- 通过全局快捷键启动录音。
- 使用 Accessibility 在当前光标处插入文本。
- 有浮动气泡/预览相关能力。
- 支持上一条结果粘贴。
- 支持本地模型和云端 provider。
- 支持 AI polishing、styles、text replacement、history。

可借鉴点：

- 快捷键设计要直接，不需要每次打开窗口。
- 上一条结果要有快捷恢复。
- 本地模型和云端模型可以共存。
- 浮动气泡要显示状态，但不应变成复杂控制台。

需要避免：

- 模型/provider 暴露太多，普通用户会困惑。
- 历史中默认保存大量音频，容易造成隐私疑虑。
- 工具感过强，缺少 Typeless/Wispr 那种顺滑的产品完成度。

### 6.3 OpenLess macOS 底部状态胶囊方案

底部状态胶囊是 OpenLess 第一轮的核心视觉锚点。它应该像一个“系统级语音输入提示”，而不是一个独立聊天框，也不是一整条输入栏。

默认结构：

| 区域 | 内容 | 说明 |
|---|---|---|
| 左侧 | 叉号 | 取消本次录音或处理 |
| 中间 | 3-5 根白色动态条 / 极短状态文案 | 提醒用户正在听、正在整理 |
| 右侧 | 勾号 | 确认完成或显示成功状态 |
| 展开态 | 原始转写 / 润色结果 / 复制 / 重试 | 默认不出现，只在失败或用户点击时展开 |

视觉要求：

- 底部居中，Listening 状态约 128-180px 宽、32-38px 高。
- 空闲时隐藏，或只保留极淡的小点。
- 只有录音、处理中、成功、失败时才从屏幕底部轻微弹出。
- 使用 macOS glass / material 质感，背景半透明但可读。
- 圆角接近胶囊，阴影轻，边框 1px。
- 不使用大面积紫蓝渐变，不做强营销色。
- 字体使用系统字体，状态文案只保留 2-4 个字。
- 状态色克制：录音用白色动态条或蓝绿色微光，错误用小红点。
- 不默认展示完整转写内容。

状态规划：

| 状态 | 显示 | 动画 |
|---|---|---|
| Idle | 隐藏，或极淡小点 | 无动画 |
| Listening | 叉号 + 动态白色条 + 勾号 | 胶囊从底部弹出，动态条轻微跳动 |
| Processing | 叉号 + “整理中” + 勾号/小 spinner | 胶囊略微变宽 |
| Inserted | 勾号高亮 | 0.8 秒后自动收起 |
| Cancelled | 叉号高亮 | 快速淡出 |
| Clipboard fallback | “已复制” | 保持 2-3 秒 |
| Error | 红点或“失败” | 点击后再展开详情 |
| Expanded | 显示原始转写和润色结果 | 只由用户主动点击或失败状态触发 |

### 6.4 OpenLess 页面基调

OpenLess 不应做成营销型 landing page。第一屏应该是产品可用体验：

- 主窗口：设置、历史、词典、片段、隐私。
- 常驻体验：底部微型状态胶囊。
- 菜单栏：开始录音、粘贴上一条、打开历史、设置、退出。

主窗口应低调、密集、工具化：

- 左侧导航：Overview、History、Dictionary、Snippets、Modes、Privacy、Settings。
- Overview 只展示快捷键、当前模式、麦克风、隐私状态。
- History 支持原文/润色切换。
- Dictionary 和 Snippets 直接表格编辑。
- Privacy 页明确显示本地/云端/历史/音频保存状态。

## 7. 第一轮产品基调

OpenLess 的产品基调应是：

- 安静：不打扰用户工作流。
- 可靠：失败也不丢内容。
- 透明：知道何时录音、何时处理、是否保存、是否读上下文。
- 克制：润色自然，不把用户变成 AI 腔。
- Mac 原生：底部状态胶囊像系统提示组件，而不是网页浮层。
- 对中文友好：中文口癖、中英混输、技术词是核心能力。

一句话定位：

> OpenLess 是一个本地优先、低打扰、可控润色的 macOS AI 语音输入层，让你在任何地方说话，得到像自己认真打出来的文字。

## 8. 信息汇总：市场痛点

用户真实痛点可以归纳为 8 类：

1. 打字慢，尤其是长 prompt、长邮件、长想法。
2. 原生 dictation 不准，标点差，专有名词差。
3. 普通 ASR 太机械，保留口癖和重复，后期编辑成本高。
4. AI dictation 价格越来越贵，订阅疲劳明显。
5. 移动端键盘限制多，高度、切换、粘贴、后台录音都容易差。
6. 隐私不透明，用户害怕录音、文本、截图、上下文被保存或训练。
7. 稳定性不足，录音崩溃或插入失败会立刻破坏信任。
8. 开发者场景特殊，代码名、变量、文件、英文术语很难被通用工具处理好。

OpenLess 第一轮不需要把所有都做满，但必须把第 1、2、3、6、7 类痛点解决到“日常可用”。

## 9. 建议加入第一轮需求的补充项

建议补充到第一轮 PRD：

- 底部微型状态胶囊作为核心 UI。
- 默认不保存音频，只保存文本历史；音频保存必须显式开启。
- 最近记录必须支持“粘贴上一条结果”的快捷键。
- 润色处理必须保存原始转写和最终结果。
- 上下文读取必须分级显示和开关控制。
- 录音中断时保留已录音片段或至少提示没有保存。
- 每次插入失败时自动复制到剪贴板。
- 模式从模型选择中抽象，不让用户第一屏面对 provider/model 名。
- 第一轮主打中文、中英混输、AI prompt 和工作 IM。

## 10. 调研来源

- [Typeless 官网](https://www.typeless.com/)
- [Typeless App Store](https://apps.apple.com/us/app/typeless-ai-voice-keyboard/id6749257650)
- [Typeless Reddit 讨论](https://www.reddit.com/r/macapps/comments/1qwn64o/looking_at_dictation_apps_typeless_clear_winner/)
- [Wispr Flow 官网](https://wisprflow.ai/)
- [Wispr Flow Features](https://wisprflow.ai/features)
- [Wispr Flow Auto Cleanup](https://docs.wisprflow.ai/articles/4136931124-how-to-use-auto-cleanup-beta)
- [Wispr Flow Styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles)
- [Wispr Flow Command Mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode)
- [Wispr Flow App Store](https://apps.apple.com/us/app/wispr-flow-ai-voice-dictation/id6497229487?see-all=reviews)
- [Aqua Voice 官网](https://aquavoice.com/)
- [Aqua Product Hunt 评论](https://www.producthunt.com/products/aqua/reviews)
- [Aqua User Guide](https://aquavoice.com/guide/)
- [Aqua History](https://aquavoice.com/guide/history)
- [Superwhisper 文档](https://superwhisper.com/docs)
- [Superwhisper Recording Window](https://superwhisper.com/docs/get-started/interface-rec-window)
- [Superwhisper History](https://superwhisper.com/docs/get-started/interface-history)
- [Superwhisper App Store](https://apps.apple.com/us/app/superwhisper/id6471464415?platform=ipad&see-all=reviews)
- [Willow Voice 官网](https://willowvoice.com/)
- [Willow App Store](https://apps.apple.com/us/app/willow-ai-voice-dictation/id6753057525)
- [Willow 自动格式化指南](https://help.willowvoice.com/en/articles/13183983-voice-commands-and-automatic-formatting-guide)
- [TalkTastic Start Here](https://help.talktastic.com/en/articles/9554689-new-to-talktastic-start-here)
- [TalkTastic Components](https://help.talktastic.com/en/articles/9654601-talktastic-components)
- [TalkTastic Product Hunt 评论](https://www.producthunt.com/products/talktastic/reviews)
- [MacWhisper Dictation](https://macwhisper.helpscoutdocs.com/article/14-how-to-use-the-dictation-feature)
- [MacWhisper Product Hunt 评论](https://www.producthunt.com/products/macwhisper/reviews)
- [LazyTyper 官网](https://lazytyper.com/)
- [LazyTyper Reddit 发布帖](https://www.reddit.com/r/macapps/comments/1mt8z2x/couldnt_find_a_good_free_voicecoding_tool_so_i/)
