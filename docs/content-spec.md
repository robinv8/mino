# Mino Content Spec v0.1

## Overview

Mino Content Spec 定义了 Mino 客户端支持渲染的结构化内容组件。Agent 在输出时可遵循此规范，使内容以最佳形式呈现。

## 设计原则

1. **渐进增强** — 纯文本永远可用，结构化内容是增强层
2. **客户端声明能力** — Mino 告诉 Agent "我能渲染什么"，Agent 按需输出
3. **单消息多块** — 一条消息可包含多个内容块，按序排列
4. **优雅降级** — 遇到不认识的类型，fallback 为纯文本或忽略

## 消息结构

```json
{
  "blocks": [
    { "type": "text", ... },
    { "type": "image", ... },
    { "type": "code", ... }
  ]
}
```

当消息内容是纯字符串时，等价于单个 `text` 块：
```json
{ "blocks": [{ "type": "text", "content": "Hello" }] }
```

---

## 组件清单

### text — 富文本

Markdown 格式的文本内容。

```json
{
  "type": "text",
  "content": "## Title\n\nSome **bold** text with `inline code`."
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| content | string | yes | Markdown 文本 |

### image — 图片

```json
{
  "type": "image",
  "url": "/path/to/image.png",
  "caption": "Screenshot of the app",
  "width": 800,
  "height": 600
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| url | string | yes | 图片来源：本地路径 / HTTP URL / data URI |
| caption | string | no | 图片说明 |
| width | number | no | 原始宽度（用于布局提示） |
| height | number | no | 原始高度 |

### code — 代码块

```json
{
  "type": "code",
  "language": "swift",
  "filename": "AppState.swift",
  "content": "func hello() {\n    print(\"world\")\n}",
  "startLine": 42
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| content | string | yes | 代码内容 |
| language | string | no | 语言标识 |
| filename | string | no | 文件名（展示用） |
| startLine | number | no | 起始行号 |

### link — 链接卡片

独立展示的链接，可附带预览信息。

```json
{
  "type": "link",
  "url": "https://example.com/article",
  "title": "Article Title",
  "description": "A brief description of the article.",
  "image": "https://example.com/og-image.png"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| url | string | yes | 链接地址 |
| title | string | no | 标题 |
| description | string | no | 描述文字 |
| image | string | no | 预览图 URL |

### file — 文件引用

指向本地文件或可下载资源。

```json
{
  "type": "file",
  "path": "/Users/robin/report.pdf",
  "name": "report.pdf",
  "size": 1048576,
  "mimeType": "application/pdf"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| path | string | yes | 文件路径或 URL |
| name | string | no | 显示名称（默认取文件名） |
| size | number | no | 文件大小（bytes） |
| mimeType | string | no | MIME 类型 |

### table — 表格

```json
{
  "type": "table",
  "headers": ["Name", "Type", "Description"],
  "rows": [
    ["id", "UUID", "Unique identifier"],
    ["name", "String", "Display name"]
  ],
  "caption": "Model fields"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| headers | string[] | yes | 列头 |
| rows | string[][] | yes | 行数据 |
| caption | string | no | 表格标题 |

### action — 可交互操作

用户可点击触发的操作按钮。

```json
{
  "type": "action",
  "actions": [
    { "id": "approve", "label": "Approve", "style": "primary" },
    { "id": "reject", "label": "Reject", "style": "danger" }
  ],
  "prompt": "Do you want to proceed with this change?"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| prompt | string | no | 操作提示文字 |
| actions | Action[] | yes | 操作列表 |
| actions[].id | string | yes | 操作标识 |
| actions[].label | string | yes | 按钮文字 |
| actions[].style | string | no | `primary` / `danger` / `default` |

### radio — 单选

单选列表，用户从多个选项中选择一个。

```json
{
  "type": "radio",
  "label": "Select a framework:",
  "options": [
    { "id": "swiftui", "label": "SwiftUI", "description": "Declarative UI framework" },
    { "id": "uikit", "label": "UIKit", "description": "Imperative UI framework" }
  ],
  "defaultValue": "swiftui"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| label | string | no | 选择提示文字 |
| options | Option[] | yes | 选项列表 |
| options[].id | string | yes | 选项标识 |
| options[].label | string | yes | 选项文字 |
| options[].description | string | no | 选项描述 |
| defaultValue | string | no | 默认选中项的 id |

### checkbox — 多选

多选列表，用户可选择多个选项。

```json
{
  "type": "checkbox",
  "label": "Select features to enable:",
  "options": [
    { "id": "dark", "label": "Dark Mode" },
    { "id": "sync", "label": "Cloud Sync" },
    { "id": "notify", "label": "Notifications" }
  ],
  "defaultValues": ["dark"]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| label | string | no | 选择提示文字 |
| options | Option[] | yes | 选项列表 |
| options[].id | string | yes | 选项标识 |
| options[].label | string | yes | 选项文字 |
| options[].description | string | no | 选项描述 |
| defaultValues | string[] | no | 默认选中项的 id 列表 |

### dropdown — 下拉选择

下拉菜单，适合选项较多时使用。

```json
{
  "type": "dropdown",
  "label": "Choose a language:",
  "placeholder": "Select language...",
  "options": [
    { "id": "swift", "label": "Swift" },
    { "id": "python", "label": "Python" },
    { "id": "rust", "label": "Rust" }
  ],
  "defaultValue": "swift"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| label | string | no | 选择提示文字 |
| placeholder | string | no | 未选择时的占位文字 |
| options | Option[] | yes | 选项列表 |
| options[].id | string | yes | 选项标识 |
| options[].label | string | yes | 选项文字 |
| options[].description | string | no | 选项描述 |
| defaultValue | string | no | 默认选中项的 id |

---

## 能力协商

Mino 在连接 Agent 时，可通过 `connect` 握手告知支持的组件：

```json
{
  "client": {
    "displayName": "Mino",
    "contentSpec": {
      "version": "0.1",
      "components": ["text", "image", "code", "link", "file", "table", "action", "radio", "checkbox", "dropdown"]
    }
  }
}
```

Agent 可根据此列表决定输出格式。如果 Agent 不感知此协议，输出纯文本/Markdown 仍然正常工作。

---

## 传输方式

结构化内容通过 ACP 的 agent stream 传输：

```json
{
  "type": "event",
  "event": "agent",
  "payload": {
    "stream": "content",
    "data": {
      "blocks": [...]
    }
  }
}
```

也可以在 `text` stream 的 delta 中嵌入，用特殊标记包裹：

```
Here is the result:

<mino-block type="image" url="/tmp/chart.png" caption="Revenue chart" />

The chart shows...
```

Mino 解析时识别 `<mino-block ... />` 标签并替换为对应组件渲染。

---

## 版本演进

| 版本 | 组件 |
|------|------|
| 0.1 | text, image, code, link, file, table, action, radio, checkbox, dropdown |
| 0.2 (planned) | chart, diagram, form, audio, video |
