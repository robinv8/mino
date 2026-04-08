import SwiftUI

struct DiffView: View {
    let toolName: String
    let arguments: String
    @State private var isCollapsed = false

    private var parsed: DiffData? {
        DiffData.parse(toolName: toolName, arguments: arguments)
    }

    var body: some View {
        if let data = parsed {
            VStack(alignment: .leading, spacing: 0) {
                header(data: data)

                if !isCollapsed {
                    Divider()
                    diffContent(data: data)
                }
            }
            .background(Color(.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )
        }
    }

    private func header(data: DiffData) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))

            Image(systemName: toolName == "Write" ? "doc.badge.plus" : "doc.badge.arrow.up")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(data.filePath.components(separatedBy: "/").last ?? data.filePath)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            if !data.removedLines.isEmpty || !data.addedLines.isEmpty {
                HStack(spacing: 4) {
                    if !data.removedLines.isEmpty {
                        Text("-\(data.removedLines.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    if !data.addedLines.isEmpty {
                        Text("+\(data.addedLines.count)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
            }

            Button {
                if let url = URL(string: "vscode://file\(data.filePath)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in VS Code")

            Button {
                let text = data.diffLines.map(\.text).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy diff")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCollapsed.toggle()
            }
        }
    }

    private func diffContent(data: DiffData) -> some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(data.diffLines.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 0) {
                            // Line number gutter
                            Text("\(idx + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .frame(width: 32, alignment: .trailing)
                                .padding(.trailing, 6)

                            // Diff marker
                            Text(line.marker)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.markerColor)
                                .frame(width: 12)

                            // Content
                            Text(line.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(line.backgroundColor)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: 400)
    }
}

// MARK: - Data Models

private struct DiffLine {
    enum Kind { case removed, added, context }
    let kind: Kind
    let text: String

    var marker: String {
        switch kind {
        case .removed: return "-"
        case .added: return "+"
        case .context: return " "
        }
    }

    var markerColor: Color {
        switch kind {
        case .removed: return .red
        case .added: return .green
        case .context: return .clear
        }
    }

    var backgroundColor: Color {
        switch kind {
        case .removed: return Color.red.opacity(0.06)
        case .added: return Color.green.opacity(0.06)
        case .context: return .clear
        }
    }
}

private struct DiffData {
    let filePath: String
    let diffLines: [DiffLine]

    var removedLines: [DiffLine] { diffLines.filter { $0.kind == .removed } }
    var addedLines: [DiffLine] { diffLines.filter { $0.kind == .added } }

    static func parse(toolName: String, arguments: String) -> DiffData? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let filePath = json["file_path"] as? String ?? "unknown"

        if toolName == "Write" {
            let content = json["content"] as? String ?? ""
            let lines = content.components(separatedBy: "\n").map {
                DiffLine(kind: .added, text: $0)
            }
            return DiffData(filePath: filePath, diffLines: lines)
        }

        // Edit tool
        let oldString = json["old_string"] as? String ?? ""
        let newString = json["new_string"] as? String ?? ""

        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")

        var diffLines: [DiffLine] = []
        for line in oldLines {
            diffLines.append(DiffLine(kind: .removed, text: line))
        }
        for line in newLines {
            diffLines.append(DiffLine(kind: .added, text: line))
        }

        return DiffData(filePath: filePath, diffLines: diffLines)
    }
}
