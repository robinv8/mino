# Contributing to Mino

Thanks for your interest in contributing to Mino!

## Getting Started

1. Fork the repo
2. Clone your fork
3. Open `Mino.xcodeproj` in Xcode 16+
4. Press `⌘R` to build and run

## Development

### Prerequisites

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for regenerating the Xcode project)

### Project Generation

If you add or remove source files, regenerate the Xcode project:

```bash
brew install xcodegen
xcodegen generate
```

### Preview Mode

Press `⌘⇧P` (Debug > Load Preview Bot) to load a mock agent with all component types for UI testing.

## Code Style

- Indent: 4 spaces
- Follow existing Swift conventions in the codebase
- Keep changes minimal and focused

## Pull Requests

1. Create a branch from `main`
2. Make your changes
3. Test with Preview Bot and a real OpenClaw connection if possible
4. Open a PR with a clear description of what changed and why

## Reporting Issues

Open a GitHub issue with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- macOS version and Xcode version

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
