# Mino 开发场景方案

## 核心定位

Mino 聚焦开发场景，作为 CLI Agent（如 Claude Code）的 GUI 伴侣客户端。CLI 做逻辑，Mino 做展示和交互。

## CLI 交互痛点分析

### 高痛点

- **代码变更审查**：纯文本 diff 无语法高亮、无 side-by-side 对比，多文件改动几乎无法有效审查
- **多文件变更全景**：改了 8 个文件只能线性滚动，缺少全局视图和文件间关系
- **图片/截图/图表**：终端里只有 `[image]` 占位符，完全不可见

### 中痛点

- **Tool Call 状态**：连续调用十几个工具，CLI 里只有日志刷屏，缺少结构化进度面板
- **审批/确认操作**：每次 Edit 都要按回车确认，无法批量审批或选择性接受/拒绝
- **搜索结果浏览**：Grep/Glob 返回的文件路径和匹配行难以快速定位，无法点击跳转

### 低痛点

- **对话历史管理**：上下文压缩后旧内容丢失，无法回溯
- **项目上下文可视化**：Agent 读了哪些文件、认知范围多大，无面板展示
- **输出格式化**：表格、列表排版不可控，宽表格折行变乱

## 对接方案：读 Claude Code 事件流

Mino 作为 Claude Code 的宿主进程，fork 子进程并带 `--output-format stream-json` 参数。

```
用户输入 → Mino UI → 写入 Claude Code stdin
Claude Code stdout → JSON 事件流 → Mino 解析 → Content Block 渲染
```

### 事件流类型

- **assistant/text** — Agent 文本回复
- **assistant/tool_use** — 工具调用（Read、Edit、Bash 等）
- **tool_result** — 工具执行结果
- **system** — 状态信息（token 用量、上下文压缩等）

### 渲染映射

| Claude Code 事件 | Mino 渲染 |
|---|---|
| assistant/text | Markdown 气泡 |
| tool_use: Edit | Diff 视图（语法高亮、side-by-side） |
| tool_use: Write | 新文件预览（完整代码 + 高亮） |
| tool_use: Read | 折叠面板，展示文件和行范围 |
| tool_use: Bash | 终端输出块，保留原始格式 |
| tool_use: Glob/Grep | 文件列表，可点击展开 |
| 多个 tool_use 连续 | Tool Call 时间线 |

### 用户操作回传

检测到 Claude Code 等待确认时，渲染为按钮（Accept / Reject），用户点击后写入对应字符到 stdin。

### 会话管理

- 一个 Mino 窗口对应一个 Claude Code 进程
- 进程生命周期跟随会话
- 工作目录：用户选择项目文件夹，作为 Claude Code 的 cwd
- Mino 侧持久化事件流，支持回溯浏览

### 风险点

1. stream-json 不是 Claude Code 的公开稳定 API，格式可能随版本变
2. stdin 审批交互的输入格式是否明确，是否有竞争条件
3. 大量 tool call 的实时解析和渲染性能

## 高价值 Block 设计

### P0: Diff 视图

开发场景的杀手级体验。

**渲染模式**：
- Inline diff（默认）— 红绿对比，适合小改动
- Side-by-side（可切换）— 适合大段重写
- 语法高亮按文件扩展名自动选择
- 行号对应原文件真实行号

**交互**：
- 单个 diff 可 Accept / Reject
- 多个 diff 支持 Accept All / Reject All

**数据来源**：
Edit 工具事件中的 `file_path`、`old_string`、`new_string`，无需自己做 diff 算法。

### P1: 变更全景面板

一轮对话中所有文件变更的聚合视图。

**布局**：
- 左侧：变更文件树，标注变更类型（修改/新增/删除）和行数变化
- 右侧：选中文件的 diff 详情
- 顶部：摘要（Agent 的意图描述）

**交互**：
- 点击文件跳转 diff
- 全局或按文件审批

### P2: Tool Call 时间线

**设计**：
- 纵向时间线，每节点一个 tool call
- 状态：进行中（spinner）/ 成功（绿勾）/ 失败（红叉）
- 信息收集类工具（Read/Glob/Grep）默认折叠
- 副作用类工具（Edit/Write/Bash）默认展开
- 失败的调用始终展开并高亮

### P3: 终端输出块

- 等宽字体，黑色背景
- 支持 ANSI 颜色码解析
- 长输出可折叠，默认显示前后各 10 行
- 可一键复制

### P4: 文件浏览面板

- Glob → 可折叠文件树
- Grep → 按文件分组，高亮匹配行
- Read → 代码片段 + 语法高亮 + 行号
- 点击文件路径可在系统编辑器中打开

## 实施路线

1. 跑通 Claude Code 进程管理 + 事件流解析
2. 实现 Diff 视图（P0）— 验证价值的最小单元
3. 变更全景面板（P1）— 形成完整审查体验
4. Tool Call 时间线（P2）+ 终端输出块（P3）
5. 文件浏览面板（P4）+ 打磨细节
