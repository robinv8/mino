# Product Marketing Context

*Last updated: 2026-03-14*

## Product Overview
**One-liner:** Mino — OpenClaw 的富交互客户端，让 Agent 输出从纯文本变成原生 UI 组件。
**What it does:** Mino 是一个 macOS 原生客户端，连接 OpenClaw Agent 平台，将 Agent 返回的结构化内容（代码、表格、图片、操作按钮、表单等）渲染为原生 UI 组件，而非纯文本。用户像发消息一样与 Agent 协作完成工作。
**Product category:** Agent 交互客户端 / AI Chat Client
**Product type:** 开源桌面应用
**Business model:** 开源免费（MIT），未来可能通过增值功能或企业版盈利

## Target Audience
**Target companies:** 使用 OpenClaw 平台的开发者和团队
**Decision-makers:** 开发者个人（自主选择工具）
**Primary use case:** 通过对话驱动 Agent 完成工作，同时以富格式查看 Agent 的输出
**Jobs to be done:**
- 与 OpenClaw Agent 对话完成自动化任务，看到清晰的结构化结果
- 看懂 Agent 正在做什么（工具调用可视化、执行进度）
- 管理多个 Agent，像管理联系人一样简单
**Use cases:**
- Agent 查数据库返回结果 → 原生表格展示，而非 JSON 文本
- Agent 执行代码修改 → 工具调用可视化，一眼看出在读/写哪个文件
- Agent 需要用户确认 → 原生按钮交互，而非要求用户输入 yes/no
- Agent 返回多张图片 → 自动排列为图片网格

## Problems & Pain Points
**Core problem:** OpenClaw Agent 能力强大，但现有交互方式（CLI/简单 Web）显示的内容格式有限，用户难以理解和使用 Agent 的输出。
**Why alternatives fall short:**
- OpenClaw 自身界面：内容格式有限，Agent 输出的结构化信息被压成纯文本
- ChatGPT/Claude 官方 app：只支持自家模型，不支持 OpenClaw
- LobeChat/Open WebUI 等开源项目：Web 端，消息格式本质还是 Markdown，没有真正的交互组件
- 终端/CLI：纯文本，开发者能用但体验差
**What it costs them:** 阅读效率低、操作繁琐、Agent 输出的价值被打折——Agent 能力到位了，但呈现没到位
**Emotional tension:** "Agent 明明做了很多事，但我看不懂它在干什么"

## Competitive Landscape
**Direct:** OpenClaw 自带的交互界面 — 内容格式有限，结构化信息被压成纯文本
**Secondary:** LobeChat / Open WebUI / ChatBox — 通用 AI 聊天 UI，但不支持 OpenClaw 的 ACP 协议，消息格式本质是 Markdown
**Indirect:** ChatGPT app / Claude app — 体验好但只支持自家模型；Cursor/Windsurf — 开发者在 IDE 里完成 AI 交互

## Differentiation
**Key differentiators:**
- 结构化消息协议（Content Spec）：13 种原生 UI 组件，远超纯文本/Markdown
- 能力协商：客户端告诉 Agent "我能渲染什么"，Agent 按需输出最佳格式
- macOS 原生体验：SwiftUI 构建，不是 Electron 套壳
- 工具调用可视化：一眼看出 Agent 在做什么（Reading UserList.swift），而非原始 JSON
**How we do it differently:** 定义了 Content Spec 协议，Agent 可以返回 blocks 数组（text/image/code/table/action/radio/checkbox 等），客户端将其渲染为原生 UI 组件
**Why that's better:** 用户不再需要从一坨文本中解析信息，Agent 的输出直接变成可交互的界面
**Why customers choose us:** OpenClaw 用户需要一个体验友好的客户端，Mino 是目前唯一专门为 OpenClaw 优化且支持富交互的选择

## Objections & Anti-Personas
| Objection | Response |
|-----------|----------|
| "ChatGPT/Claude 官方 app 不够用吗？" | 它们只支持自家模型。如果你用 OpenClaw，需要一个专门的客户端 |
| "为什么不用 Web 端？" | Web 端能解决连通性，但原生 app 的渲染性能和交互体验是 Web 做不到的 |
| "只支持 macOS，用户太少" | 先在 macOS 上打磨体验，验证产品后再做移动端和跨平台 |

**Anti-persona:** 不使用 OpenClaw 的纯 ChatGPT/Claude 用户；对 Agent 交互没有需求的普通用户

## Switching Dynamics
**Push:** OpenClaw 自带界面显示格式有限，Agent 输出看不懂，操作不方便
**Pull:** 原生 UI 组件渲染让 Agent 输出可读、可交互；工具调用可视化让过程透明
**Habit:** 用户已经习惯了现有的交互方式（CLI、Web），切换需要安装新 app
**Anxiety:** 担心开源项目维护不持续；担心 macOS only 限制了使用场景

## Customer Language
**How they describe the problem:**
- "Agent 返回一大段文字，看不懂在说什么"
- "工具调用显示一堆 JSON，不知道它在干什么"
- "想让 Agent 帮我确认一下再执行，但交互方式太原始了"
**How they describe us:**
- "OpenClaw 的好用客户端"
- "让 Agent 输出变好看了"
**Words to use:** Agent、对话、联系人、结构化、富交互、原生
**Words to avoid:** AI 聊天机器人、chatbot、wrapper（暗示只是套壳）
**Glossary:**
| Term | Meaning |
|------|---------|
| Content Spec | Mino 定义的结构化消息协议，消息 = blocks 数组 |
| ACP | Agent Communication Protocol，OpenClaw 的通信协议 |
| Block | Content Spec 中的单个内容组件（text/image/code/table 等） |
| 能力协商 | 客户端在连接时告知 Agent 支持渲染哪些组件类型 |

## Brand Voice
**Tone:** 简洁、技术范、不废话
**Style:** 直接说结论，用示例而非描述
**Personality:** 开发者友好、务实、开源精神

## Proof Points
**Metrics:** 暂无（MVP 阶段）
**Customers:** OpenClaw 社区早期用户
**Testimonials:** 暂无
**Value themes:**
| Theme | Proof |
|-------|-------|
| Agent 输出可读性 | 13 种原生 UI 组件 vs 纯文本 |
| 过程透明 | 工具调用摘要显示（"Reading UserList.swift"而非 JSON） |
| 交互效率 | 按钮确认/表单选择 vs 手动输入 yes/no |

## Goals
**Business goal:** 成为 OpenClaw 用户的默认客户端
**Conversion action:** 下载并连接到 OpenClaw Agent
**Current metrics:** MVP 阶段，暂无公开数据
