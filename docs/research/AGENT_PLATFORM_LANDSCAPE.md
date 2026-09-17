<!-- Copyright (c) 2026 FanXeon@Poemcoder with Codex -->

# 调研：人机 · Agent · IoT · 工作流协作平台的市场现状

[桌面控制台计划](../AGENT_DESK_PLAN.md) · [路线图](../ROADMAP.md)

**调研日期：2026-09-17。** 目标：米遥想从"遥控器 → Codex 桥"长成一个 **人（实体输入设备）、AI agent、IoT 硬件、工作流** 四方协作的本地平台。先看清市面上谁已经做了哪一块、做到什么程度，再决定自研什么、接入什么。

结论先行：

1. **没有人同时做了四方。** 市面分成三块：agent 仪表盘派（AgentDeck、Stream Deck 插件、厂商键盘）、IoT 派（Home Assistant + ESPHome）、agent 网关派（OpenClaw）。工作流引擎（n8n、Node-RED）两边都不感知。
2. **AgentDeck 比预想成熟得多**，已经把"agent 状态 → 多表面（含 12 种 ESP32 板、墨水屏）→ 审批 / 语音"做完，并发布了 Surface Protocol v1 和一份很讲究的墨水屏合同。米遥原计划自研的副屏协议与它高度重叠。
3. **米遥独有的一截**是：消费级 BLE 语音遥控器（离开键盘、整屋可用、¥100 级、买来即用）+ 向任意终端里的 agent 注入 + 按键审批闭环。这一截没人有。
4. 策略上应该 **复用两边、只做中间**：IoT 那半边接 Home Assistant，agent 表面那半边优先对接 AgentDeck，米遥集中做"输入设备 + 注入 + 闭环 + 工作流粘合"，自研协议降级为无依赖的轻量后备。

## 1. 范围与方法

- 范围：能把 AI coding agent 状态外显到实体设备、能从实体设备控制 agent、能把 IoT 设备与 agent 串进工作流的产品或项目。
- 方法：官网、GitHub 仓库与文档（AgentDeck 的 `docs/surface-protocol.md`、`docs/eink-surface-contract.md`、`docs/protocol.md` 直接读了源文件）、发布新闻。价格为 2026-09 官方标价。
- 不在范围：纯 IDE 插件、纯云端 agent 平台、消费级 AI 随身设备（Rabbit / Humane 类）。

## 2. 一句话画像

| 项目 | 类型 | 一句话 |
| --- | --- | --- |
| **AgentDeck**（MIT，2026-02 起，238★） | agent 仪表盘 + 实体控制平台 | 一个本地 daemon 汇聚 Claude Code / Codex / OpenCode / Kiro / OpenClaw 的会话状态，广播到 29 种表面：Stream Deck、Ulanzi、iOS / Android、macOS、TUI、12 种 ESP32 板、TRMNL 等墨水屏、Pixoo 像素灯；支持 PTT / 唤醒词、YES / NO / ALWAYS 审批、模式切换、快捷 prompt |
| **Home Assistant**（Apache-2.0） | IoT 中枢 | 一切皆 entity + 自动化规则；官方 MCP Server 让 agent 读写已暴露的设备；Assist 本地语音管线；Voice Preview Edition 硬件（$59，ESPHome，双麦 + LED 环 + 物理静音） |
| **ESPHome** | IoT 固件 | YAML 配 ESP32 固件，含墨水屏 / LCD 驱动、`online_image` 拉图、HTTP 请求；HA 生态默认固件 |
| **OpenClaw**（前 Clawdbot / Moltbot，100k+★） | 个人 agent 网关 | 一个 Gateway 把 WhatsApp / Telegram / Slack 等消息渠道路由给 agent；手机 / Mac / Linux 作为 **node** 经 WebSocket 接入，暴露 `camera.* / canvas.* / device.* / notifications.* / system.*` 命令面；设备配对需 owner 批准 |
| **TRMNL**（硬件 $139 / $229，固件与 BYOS 开源） | 墨水屏产品 | 纯 pull：设备深睡眠醒来拉一张 800×480 1-bit 图贴上再睡；服务端渲染，900+ 插件；自建服务器（BYOS）免费，自带设备（BYOD）一次性 $50 |
| **OpenAI Codex Micro**（$230，2026-07） | 厂商实体键盘 | 6 个 Agent 键 RGB 状态灯、接受 / 拒绝 / 分支 / PTT / 新会话、摇杆、推理旋钮、6 层 |
| **Logitech MX Keypad**（$99，2026-09） | 通用 LCD 键盘 | 9 个 LCD 键按前台 App 切配置，Logi Actions SDK，社区 Claude Code / Codex 插件 |
| **Stream Deck 插件**（ClaudeButtons、streamdeck-claude-monitor、agentsd） | agent 状态插件 | hooks → 会话状态 → 键面；一键 approve / deny；上下文用量环 |
| **Claude Code 语音模式 / Remote Control** | 官方能力 | 终端里按住空格说话；手机远程起会话 |
| **n8n / Node-RED** | 工作流引擎 | 通用触发-处理-动作；n8n 有 AI agent 节点，Node-RED 是 IoT 常客；都不感知 coding agent 会话状态，也不接实体输入设备 |

## 3. 多维对比矩阵

图例：● 完整 ◐ 部分 ○ 无 —— 不适用

| 维度 | AgentDeck | Home Assistant | OpenClaw | TRMNL | Codex Micro | MX Keypad | Stream Deck 插件 | n8n / Node-RED | **米遥（现状）** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **人：实体按键输入** | ● Stream Deck / Ulanzi / ESP32 板键 | ◐ 任意 HA 按钮实体 | ○ | ◐ 单键 | ● | ● | ● | ○ | ● 12 键遥控器（BLE，整屋） |
| **人：语音输入** | ● PTT + 唤醒词（Apple SFSpeech，绑在 Mac 麦） | ● Assist + Voice PE 硬件 | ◐ 手机 node | ○ | ● PTT 键（调用 Codex App） | ○ | ○ | ○ | ● 遥控器自带麦，本地 Whisper |
| **人：手机 / 网页表面** | ● iOS / Android / macOS | ● 官方 App | ● iOS / Android node | ○ | ○ | ○ | ○ | ◐ 自带 UI | ◐ 向导（Mac） |
| **Agent 感知：支持的 agent** | ● Claude Code、Codex CLI / App、OpenCode、Kiro、Antigravity、OpenClaw | ○（agent 是客户端，不是被观察对象） | —— 自身即 agent | ○ | ◐ 仅 Codex | ◐ 社区插件 | ◐ 仅 Claude Code | ○ | ◐ Codex App / Codex CLI |
| **Agent 感知：状态来源** | ● hooks + rollout JSONL + SSE + 进程观察；6 态状态机 | —— | —— | ○ | ● 厂商私有 | ◐ 插件 hooks | ● hooks | ○ | ○（待做：hooks） |
| **Agent 控制：注入 / 审批** | ● YES / NO / ALWAYS、STOP、模式切换、快捷 prompt、PTY 管理会话 | ○ | ● 完整对话 | ○ | ● | ◐ 宏 | ● approve / deny | ○ | ● 转写注入（tmux / 终端 tab 精确定位）；◐ 审批待做 |
| **IoT：显示设备** | ● 12 种 ESP32、TRMNL、LilyGo EPD47、Android 墨水屏、Pixoo | ● 任何 HA 显示实体 / ESPHome 屏 | ◐ canvas 推到手机 | ● 自家墨水屏 | ○ | ○ | ○ | ◐ 经 HA / MQTT | ○（计划中） |
| **IoT：传感器 / 执行器** | ○ | ● 事实标准 | ◐ 手机传感器 | ○ | ○ | ○ | ○ | ● | ○ |
| **工作流 / 规则引擎** | ◐ 有限（睡眠同步、配额、模板） | ● 自动化 + 蓝图 | ◐ skills / 定时 | ○ | ○ | ◐ 宏 | ○ | ● | ○ |
| **本地优先** | ● 全本地，可跨机 | ● | ● 自托管 | ◐ 需 BYOS 才本地 | ◐ 依赖 Codex 账号 | ◐ Logi Options+ | ● | ◐ n8n 可自托管 | ● 全本地 Whisper |
| **开放协议 / 可扩展** | ● Surface Protocol v1 + 合规等级 + 墨水屏合同 | ● REST / WS / MQTT / MCP | ● node 协议 + 配对 | ● BYOS 协议开源 | ○ 封闭 | ◐ SDK | ◐ | ● | ◐ 自定义预设、CLI 参数 |
| **多 agent / 多会话** | ● 会话 roster，一键一会话 | —— | ● 多会话 | —— | ● 6 线程 | ◐ | ◐ | —— | ◐ 多实例定位 + 切 Tab |
| **平台** | macOS 15+ / Windows 11 / Linux；原生 macOS 26 App | 全平台 | macOS / Linux / VPS | 硬件 | 硬件 | 硬件 | Stream Deck | 全平台 | macOS 14+ |
| **入门成本** | ¥0（TUI）～ 已有 Stream Deck | ¥0 软件 + 设备 | ¥0 + 模型 key | ¥1000+ | ¥1600+ | ¥700 | 已有设备 | ¥0 | ¥100 遥控器 |
| **成熟度** | 7 个月 2000+ 提交、App Store / Play 上架、CI 合规套件 | 十年级 | 一年内爆发，100k★ | 成熟产品 | 新品 | 新品 | 小项目 | 成熟 | 0.2.x beta |

## 4. 分项深挖

### 4.1 AgentDeck：最接近的"已实现"

- **架构**：单 daemon（9120）汇聚全部会话，WebSocket 广播到所有表面；Session Bridge（9121+）管 PTY 托管会话与 hooks；可选远程 daemon 跨机接入。状态机 6 态：`DISCONNECTED / IDLE / PROCESSING / AWAITING_PERMISSION / AWAITING_OPTION / AWAITING_DIFF`，Claude / Codex 由 hooks 驱动，OpenCode / OpenClaw 由原生事件流归一。
- **Surface Protocol v1**（2026-08 定稳）：在同一认证 daemon 上划出三种 profile——`dashboard-live/v1`（WS，只读仪表盘）、`companion-control/v1`（WS，能力门控的会话控制，供 Bitfocus / 硬件控制集成）、`portable-reader/v1`（HTTP `GET /feed` + `POST /outbox`，醒来-同步-睡眠的离线阅读器）。无未认证路由，局域网需配对；`permission_decision` 必须带活的 `requestId`，`state: awaiting_*` 本身不构成授权。还定义了 Community / Verified Compatible / Official 三级兼容与合规套件。
- **墨水屏合同**：把内容分成 body（服务端权威的持久语义）和 band（设备上的一行瞬态）；五种 face `DECISION > ANSWER > DIGEST > GLANCE > ROSTER` 严格优先级；push / pull 决定可达 face 集合（睡眠的 pull 设备不承诺决策 / 回答，物理唤醒开 8 分钟交互租约）；物理动作持有当前 body 8 分钟。这套思考比我们草案深一代。
- **语音**：PTT 与唤醒词走 Apple SFSpeech，麦克风是 Mac 或手机——没有独立的房间级实体语音设备。
- **没有的**：IoT 传感器 / 执行器、通用规则引擎、Home Assistant / MQTT 集成（文档未见）。

### 4.2 Home Assistant：IoT 那半边不用再造

- 实体模型 + 自动化 + 蓝图 + 仪表盘，设备生态最大；ESPHome 让任意 ESP32 板 YAML 接入，墨水屏 / LCD / 按键 / 传感器都有现成组件。
- **MCP Server** 集成（`/api/mcp`，token 认证）把已暴露给 Assist 的实体开放给外部 agent 客户端；方向是"agent 控制家"，不是"家显示 agent"。
- **Assist + Voice PE**（$59）：双麦 + XMOS 降噪 + LED 环 + 物理静音，本地或 HA Cloud 处理；证明"开源硬件语音入口 + 本地管线"可行，但它面向家居意图，不面向 coding agent。
- 缺口：不知道什么是 coding agent 会话，没有审批语义。要接进去只需要米遥把 agent 状态发布成 `sensor.*`，把审批发布成 `switch.*` / `event.*`（MQTT discovery 一小时的活）。

### 4.3 OpenClaw：node 概念值得借

- 手机 / Mac / Linux 作为 node，`connect` 时带 `role: "node"` + caps / commands / permissions；owner 显式批准配对；`node.invoke` 调用 `camera.* / canvas.* / device.* / notifications.* / system.*`。
- 这就是"设备自报能力 + 配对 + 命令面"的成熟范式，和我们副屏协议草案的 `hello` 一致；可以直接对齐字段命名与配对流程。
- 缺口：重心是消息渠道 ↔ agent，对 coding agent 的会话状态、终端注入、审批不是它的事。

### 4.4 TRMNL：墨水屏"服务端渲染 + 纯 pull"的范本

- 固件极简：深睡眠 → 醒 → 拉一张 1-bit 位图 → 贴 → 睡；所有排版、字体、插件逻辑都在服务端；BYOS 协议开源，社区有 Go / TS 服务器实现。
- 验证了我们"渲染模式"的判断：把中文字体和布局留在 Mac，固件只贴图，换屏改尺寸。AgentDeck 也已把 TRMNL 7.5" 作为官方固件目标。

### 4.5 厂商键盘与 Stream Deck 插件

- Codex Micro 把"状态灯语义（白 / 蓝 / 绿 / 琥珀 / 红）+ 接受 / 拒绝 / PTT + 层"做成了行业默认词汇；封闭、只对 Codex。
- MX Keypad 是通用 LCD 键盘 + SDK，agent 支持靠社区插件；Stream Deck 插件同理。它们都在 **桌上、键盘旁**，解决不了"人不在键盘前"。

### 4.6 工作流引擎

- n8n / Node-RED 提供触发-条件-动作、可视化编排、海量集成；n8n 有 AI agent 节点（把 LLM 当工具编排），Node-RED 天然接 MQTT / HA。
- 但两者的"事件"不包括 coding agent 的会话状态，也没有实体输入设备节点。若米遥把状态与按键发布成 MQTT / webhook，它们立刻可用——不必自研规则引擎的高级形态。

## 5. 空白与米遥的位置

| 能力 | 谁做得最好 | 米遥是否该自研 |
| --- | --- | --- |
| 房间级实体语音 + 按键输入（离开键盘、¥100、买来即用） | **没有人**（AgentDeck 语音绑 Mac 麦；Voice PE 面向家居） | **是，这是核心** |
| 向任意终端里的 agent 注入文本（含 tmux、iTerm2 精确 tab） | 米遥 | 是，已有 |
| agent 状态感知（hooks、多 agent、6 态机） | AgentDeck | 否——要么接 AgentDeck，要么做最小 hooks 接收 |
| 多表面显示（墨水屏 / ESP32 / 手机 / Stream Deck） | AgentDeck | 否——优先当它的 companion；自研协议只做无依赖后备 |
| 墨水屏内容合同（face、push / pull、租约） | AgentDeck | 否——直接采用其语义 |
| IoT 传感器 / 执行器 / 自动化 | Home Assistant | 否——MQTT discovery 发布实体 |
| 通用工作流编排 | n8n / Node-RED / HA 自动化 | 否——提供 webhook / MQTT 事件源，自身只留几条内置规则 |
| 设备配对 / 能力自报范式 | OpenClaw、AgentDeck | 否——对齐字段 |

米遥独占的位置一句话：**一只 ¥100 的遥控器把人从键盘前解放出来，语音进 agent、按键做决定；状态显示交给 AgentDeck / 副屏，家居联动交给 Home Assistant。**

## 6. 策略选项

| 选项 | 内容 | 优点 | 风险 |
| --- | --- | --- | --- |
| A. 独立 Hub，全部自研 | 按原计划做状态总线、副屏协议、固件、规则引擎 | 完全可控 | 与 AgentDeck 正面重叠，7 个月 2000 提交的差距追不上；精力离开核心 |
| B. 做 AgentDeck 的输入表面 | 米遥以 `companion-control/v1` 接入，语音转写与按键决定送进 AgentDeck；显示全交给它 | 立刻拥有 29 种表面、墨水屏合同、审批语义 | 依赖其 daemon（Node.js）与协议演进；IoT 仍无着落 |
| **C. 混合（推荐）** | 米遥核心 = 遥控器 + Whisper + 注入 + 审批闭环 + 最小 hooks 接收；**上游** 可选接 AgentDeck（companion-control）；**下游** 经 MQTT discovery 接 Home Assistant，同时把事件以 webhook / MQTT 暴露给 n8n / Node-RED；自研副屏协议保留为"不装任何东西也能用"的轻量后备，协议字段对齐 AgentDeck / OpenClaw | 每一块都用最好的现成件，米遥只做没人做的那截；无依赖路径仍在 | 要维护两个上游适配；产品叙事要讲清楚 |

## 7. 对现有计划的影响

对 [AGENT_DESK_PLAN](../AGENT_DESK_PLAN.md) 的修订建议：

1. **P0 状态回传**：hook 接收端保留，但状态机直接采用 AgentDeck 的 6 态命名，方便后续互通。
2. **第 4 节副屏协议**：降级为"轻量后备"；新增两节——"作为 AgentDeck companion 接入"（评估 `companion-control/v1` 能否承载语音转写 + 按键决策）和"Home Assistant / MQTT 桥"（agent 状态 → `sensor`，审批 → `event` / `switch`，遥控器按键 → `event`）。
3. **硬件采购**：LILYGO T5 4.7"（EPD47）同时是 AgentDeck 官方支持板，买它两条路都能验证；TRMNL 若想省固件可直接买成品走 BYOS。
4. **墨水屏内容**：不再自定义 face，采用 AgentDeck 的 `DECISION / ANSWER / DIGEST / GLANCE / ROSTER` 与 push / pull 租约语义。
5. **工作流**：不写规则引擎；先做事件出口（MQTT / webhook），规则交给 HA 自动化或 Node-RED；米遥内置的只有"审批闭环"这一条硬编码规则。

待用户拍板：选项 C 是否接受；是否先做一次 AgentDeck 的实机接入评估（半天）。

## 8. 来源

- AgentDeck：<https://github.com/puritysb/AgentDeck>（`docs/surface-protocol.md`、`docs/eink-surface-contract.md`、`docs/protocol.md`、`docs/architecture.md`）
- Home Assistant MCP Server：<https://www.home-assistant.io/integrations/mcp_server/>；Voice Preview Edition：<https://www.home-assistant.io/voice-pe/>；Voice chapter 10：<https://www.home-assistant.io/blog/2025/06/25/voice-chapter-10/>
- OpenClaw 架构：<https://docs.openclaw.ai/concepts/architecture>；nodes：<https://www.openclawplaybook.ai/blog/openclaw-nodes-physical-devices/>；iOS / Android node：<https://www.marktechpost.com/2026/06/29/openclaw-releases-ios-and-android-companion-node-apps-that-connect-a-phone-to-a-self-hosted-ai-agent-gateway/>
- TRMNL：<https://trmnl.com/>；BYOS：<https://github.com/usetrmnl/inker>、<https://github.com/gesellix/go-trmnl>；评测：<https://truenetlab.com/en/blog/trmnl-x-e-ink-information-screen-review/>
- Codex Micro：<https://www.explainx.ai/blog/openai-codex-micro-work-louder-keyboard-july-2026>
- Logitech MX Keypad：<https://news.logitech.com/press-releases/news-details/2026/Logitech-Unveils-MX-Keypad-for-Developers-The-Customizable-Multi-App-AI-Control-Center/default.aspx>
- Stream Deck 插件：<https://github.com/GlebYaltchik/streamdeck-claude-monitor>、<https://github.com/paultyng/agentsd>、<https://claudebuttons.com/>
- Claude Code hooks：<https://code.claude.com/docs/en/hooks-guide>；语音模式：<https://www.buildmvpfast.com/blog/claude-voice-mode-hands-free-programming>；Remote Control：<https://www.aibase.com/news/25659>
