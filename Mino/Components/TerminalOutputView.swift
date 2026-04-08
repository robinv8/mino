import SwiftUI

struct TerminalOutputView: View {
    let output: String
    @State private var isExpanded = false

    private let maxCollapsedLines = 20
    private let contextLines = 10

    private var lines: [TerminalLine] {
        output.components(separatedBy: "\n").map { TerminalLine.parse($0) }
    }

    private var needsTruncation: Bool {
        lines.count > maxCollapsedLines
    }

    private var displayLines: [TerminalLine] {
        if isExpanded || !needsTruncation {
            return lines
        }
        let head = Array(lines.prefix(contextLines))
        let tail = Array(lines.suffix(contextLines))
        return head + tail
    }

    private var hiddenCount: Int {
        guard needsTruncation, !isExpanded else { return 0 }
        return lines.count - maxCollapsedLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical) {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        let head = !isExpanded && needsTruncation ? Array(displayLines.prefix(contextLines)) : displayLines
                        ForEach(Array(head.enumerated()), id: \.offset) { idx, line in
                            terminalLine(line, lineNumber: idx + 1)
                        }

                        if hiddenCount > 0 {
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isExpanded = true
                                    }
                                } label: {
                                    Text("... \(hiddenCount) lines hidden — Show all")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.vertical, 4)

                            let tail = Array(displayLines.suffix(contextLines))
                            ForEach(Array(tail.enumerated()), id: \.offset) { idx, line in
                                terminalLine(line, lineNumber: lines.count - contextLines + idx + 1)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxHeight: isExpanded ? 600 : 300)
        }
        .background(Color(nsColor: .init(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Terminal")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            Text("\(lines.count) lines")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Copy output")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
    }

    private func terminalLine(_ line: TerminalLine, lineNumber: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 8)

            ForEach(Array(line.spans.enumerated()), id: \.offset) { _, span in
                Text(span.text)
                    .font(.system(size: 12, weight: span.isBold ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(span.color)
            }
        }
        .padding(.vertical, 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ANSI Parsing

private struct TerminalSpan {
    let text: String
    let color: Color
    let isBold: Bool
}

private struct TerminalLine {
    let spans: [TerminalSpan]

    static func parse(_ raw: String) -> TerminalLine {
        var spans: [TerminalSpan] = []
        var currentColor: Color = .white.opacity(0.9)
        var isBold = false
        var remaining = raw[...]

        while !remaining.isEmpty {
            if let escRange = remaining.range(of: "\u{1B}[") {
                // Text before escape
                let before = remaining[remaining.startIndex..<escRange.lowerBound]
                if !before.isEmpty {
                    spans.append(TerminalSpan(text: String(before), color: currentColor, isBold: isBold))
                }
                remaining = remaining[escRange.upperBound...]

                // Find the 'm' terminator
                if let mIdx = remaining.firstIndex(of: "m") {
                    let codes = remaining[remaining.startIndex..<mIdx]
                    remaining = remaining[remaining.index(after: mIdx)...]

                    for code in codes.split(separator: ";") {
                        switch code {
                        case "0": currentColor = .white.opacity(0.9); isBold = false
                        case "1": isBold = true
                        case "31": currentColor = Color(nsColor: .init(red: 1, green: 0.4, blue: 0.4, alpha: 1))
                        case "32": currentColor = Color(nsColor: .init(red: 0.4, green: 0.9, blue: 0.4, alpha: 1))
                        case "33": currentColor = Color(nsColor: .init(red: 1, green: 0.85, blue: 0.3, alpha: 1))
                        case "34": currentColor = Color(nsColor: .init(red: 0.4, green: 0.6, blue: 1, alpha: 1))
                        case "35": currentColor = Color(nsColor: .init(red: 0.8, green: 0.5, blue: 1, alpha: 1))
                        case "36": currentColor = Color(nsColor: .init(red: 0.4, green: 0.9, blue: 0.9, alpha: 1))
                        case "90": currentColor = .white.opacity(0.5)
                        default: break
                        }
                    }
                } else {
                    // Malformed escape, skip
                    break
                }
            } else {
                // No more escapes
                spans.append(TerminalSpan(text: String(remaining), color: currentColor, isBold: isBold))
                remaining = remaining[remaining.endIndex...]
            }
        }

        if spans.isEmpty {
            spans.append(TerminalSpan(text: "", color: .white.opacity(0.9), isBold: false))
        }

        return TerminalLine(spans: spans)
    }
}
