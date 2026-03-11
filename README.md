# Mino

An open-source universal agent interaction client for macOS. Treat agents as contacts, drive everything through conversation.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

## What is Mino?

In the agent era, the interaction layer is missing. Existing IM clients have limited message formats. Mino bridges this gap — agents are contacts, and conversations support rich structured content beyond plain text.

## Features

- **Agent as Contact** — Add agents by URL, chat like messaging a friend
- **Streaming Output** — Real-time token streaming with thinking indicators
- **Rich Content Blocks** — 13 native UI components rendered inline:
  - `text` · `image` · `code` · `link` · `file` · `table`
  - `action` · `radio` · `checkbox` · `dropdown`
  - `audio` · `video` · `callout`
- **Image Grid** — Multiple images auto-grouped into a 2-column grid
- **Content Spec Auto-Injection** — Agents automatically learn available components
- **Tool Call Visualization** — See what tools agents are using
- **Local Persistence** — Chat history and agent configs stored locally

## Getting Started

### Prerequisites

- macOS 14.0+
- Xcode 16.0+

### Build & Run

```bash
git clone https://github.com/robinv8/mino.git
cd mino
open Mino.xcodeproj
```

Press `⌘R` to build and run.

### Preview Mode

Press `⌘⇧P` (Debug → Load Preview Bot) to load a mock agent with all component types for UI testing.

## Architecture

```
Mino/
├── MinoApp.swift              # App entry point
├── Models/                    # Data models (Agent, ChatMessage, ContentBlock)
├── Views/                     # Main views (Chat, Sidebar, Settings)
├── Components/                # UI components (MessageBubble, ContentBlockView)
├── Services/
│   ├── ACP/                   # Agent Communication Protocol (WebSocket)
│   ├── ContentBlockParser.swift
│   └── AudioPlayerService.swift
└── Theme/                     # Design tokens
```

## Protocol Support

| Protocol | Status | Use Case |
|----------|--------|----------|
| OpenClaw (ACP) | ✅ Supported | Agent communication |
| Claude Code | 🔜 Planned | AI coding assistant |
| Matrix | 🔜 Planned | Human-to-human messaging |

## Content Spec

Mino defines a lightweight content spec using `<mino-block />` tags. Agents can embed these tags in responses for richer display. See [docs/content-spec.md](docs/content-spec.md) for the full specification.

## License

MIT
