import SwiftUI
import MarkdownUI

/// Renders a single ContentBlock
struct ContentBlockView: View {
    let block: ContentBlock
    var onAction: ((String) -> Void)?

    var body: some View {
        switch block {
        case .text(let b): TextBlockView(block: b)
        case .image(let b): ImageBlockView(block: b)
        case .code(let b): CodeBlockView(block: b)
        case .link(let b): LinkBlockView(block: b)
        case .file(let b): FileBlockView(block: b)
        case .table(let b): TableBlockView(block: b)
        case .action(let b): ActionBlockView(block: b, onAction: onAction)
        case .radio(let b): RadioBlockView(block: b, onAction: onAction)
        case .checkbox(let b): CheckboxBlockView(block: b, onAction: onAction)
        case .dropdown(let b): DropdownBlockView(block: b, onAction: onAction)
        case .audio(let b): AudioBlockView(block: b)
        case .video(let b): VideoBlockView(block: b)
        case .callout(let b): CalloutBlockView(block: b)
        case .unknown: EmptyView()
        }
    }
}

/// Container for rendering multiple blocks, grouping consecutive images into a grid
struct ContentBlocksView: View {
    let blocks: [ContentBlock]
    var onAction: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedBlocks, id: \.id) { group in
                switch group {
                case .single(let block):
                    ContentBlockView(block: block, onAction: onAction)
                case .imageGrid(let images):
                    ImageGridView(images: images)
                }
            }
        }
    }

    private var groupedBlocks: [BlockGroup] {
        var groups: [BlockGroup] = []
        var imageBuffer: [ImageBlock] = []

        func flushImages() {
            guard !imageBuffer.isEmpty else { return }
            if imageBuffer.count == 1 {
                groups.append(.single(.image(imageBuffer[0])))
            } else {
                groups.append(.imageGrid(imageBuffer))
            }
            imageBuffer = []
        }

        for block in blocks {
            if case .image(let img) = block {
                imageBuffer.append(img)
            } else {
                flushImages()
                groups.append(.single(block))
            }
        }
        flushImages()
        return groups
    }
}

private enum BlockGroup {
    case single(ContentBlock)
    case imageGrid([ImageBlock])

    var id: String {
        switch self {
        case .single(let block): block.id
        case .imageGrid(let images): "grid-" + images.map(\.id).joined(separator: "-")
        }
    }
}

private struct ImageGridView: View {
    let images: [ImageBlock]

    private let spacing: CGFloat = 4
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(images, id: \.id) { img in
                ImageGridCell(block: img)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
    }
}

private struct ImageGridCell: View {
    let block: ImageBlock

    var body: some View {
        ZStack(alignment: .bottom) {
            imageContent
                .frame(minHeight: 120, maxHeight: 200)
                .clipped()

            if let caption = block.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    @ViewBuilder
    private var imageContent: some View {
        if block.url.hasPrefix("/") || block.url.hasPrefix("file://") {
            if let nsImage = loadLocalImage(block.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        } else if block.url.hasPrefix("data:") {
            if let nsImage = loadBase64(block.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        } else if let url = URL(string: block.url) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else if phase.error != nil {
                    placeholder
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.primary.opacity(0.04)
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
    }

    private func loadLocalImage(_ path: String) -> NSImage? {
        let p = path.hasPrefix("file://") ? (URL(string: path)?.path ?? path) : (path as NSString).expandingTildeInPath
        return NSImage(contentsOfFile: p)
    }

    private func loadBase64(_ dataURL: String) -> NSImage? {
        guard let i = dataURL.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: i)...])) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Text Block

private struct TextBlockView: View {
    let block: TextBlock

    var body: some View {
        MarkdownContent(content: block.content, role: .agent)
    }
}

// MARK: - Image Block

private struct ImageBlockView: View {
    let block: ImageBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            imageContent
            if let caption = block.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if block.url.hasPrefix("/") || block.url.hasPrefix("file://") {
            if let nsImage = loadLocalImage(block.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            } else {
                placeholder("File not found")
            }
        } else if block.url.hasPrefix("data:") {
            if let nsImage = loadBase64(block.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            } else {
                placeholder("Failed to decode")
            }
        } else if let url = URL(string: block.url) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                } else if phase.error != nil {
                    placeholder("Failed to load")
                } else {
                    ProgressView().frame(width: 80, height: 60)
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text(text)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func loadLocalImage(_ path: String) -> NSImage? {
        let p = path.hasPrefix("file://") ? (URL(string: path)?.path ?? path) : (path as NSString).expandingTildeInPath
        return NSImage(contentsOfFile: p)
    }

    private func loadBase64(_ dataURL: String) -> NSImage? {
        guard let i = dataURL.firstIndex(of: ",") else { return nil }
        guard let data = Data(base64Encoded: String(dataURL[dataURL.index(after: i)...])) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Code Block

private struct CodeBlockView: View {
    let block: CodeBlock
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            if block.filename != nil || block.language != nil {
                HStack(spacing: 6) {
                    if let filename = block.filename {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                        Text(filename)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    if let lang = block.language, block.filename == nil {
                        Text(lang)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(block.content, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.03))
            }

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(block.content)
                    .font(.system(size: MinoTheme.codeSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                .stroke(MinoTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Link Block

private struct LinkBlockView: View {
    let block: LinkBlock

    var body: some View {
        Button {
            if let url = URL(string: block.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                // Preview image
                if let imageURL = block.image {
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.primary.opacity(0.04)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    ZStack {
                        Color.primary.opacity(0.04)
                        Image(systemName: "link")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title ?? block.url)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let desc = block.description {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(URL(string: block.url)?.host ?? block.url)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(MinoTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Block

private struct FileBlockView: View {
    let block: FileBlock

    var body: some View {
        Button {
            NSWorkspace.shared.selectFile(block.path, inFileViewerRootedAtPath: "")
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Color.primary.opacity(0.04)
                    Image(systemName: fileIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(MinoTheme.accent)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name ?? URL(fileURLWithPath: block.path).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let size = block.size {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        if let mime = block.mimeType {
                            Text(mime)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .padding(10)
            .background(MinoTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var fileIcon: String {
        switch block.mimeType {
        case let m? where m.hasPrefix("image/"): "photo"
        case let m? where m.hasPrefix("video/"): "film"
        case let m? where m.hasPrefix("audio/"): "waveform"
        case let m? where m.contains("pdf"): "doc.richtext"
        case let m? where m.contains("zip") || m.contains("tar"): "archivebox"
        default: "doc"
        }
    }
}

// MARK: - Table Block

private struct TableBlockView: View {
    let block: TableBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let caption = block.caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(block.headers.indices, id: \.self) { i in
                            Text(block.headers[i])
                                .font(.system(size: 11, weight: .semibold))
                                .frame(minWidth: 80, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(Color.primary.opacity(0.04))

                    Divider()

                    // Data rows
                    ForEach(block.rows.indices, id: \.self) { rowIdx in
                        HStack(spacing: 0) {
                            ForEach(block.rows[rowIdx].indices, id: \.self) { colIdx in
                                Text(block.rows[rowIdx][colIdx])
                                    .font(.system(size: 11))
                                    .frame(minWidth: 80, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                            }
                        }
                        if rowIdx < block.rows.count - 1 {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Action Block

private struct ActionBlockView: View {
    let block: ActionBlock
    var onAction: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = block.prompt {
                Text(prompt)
                    .font(.system(size: 13))
            }
            HStack(spacing: 8) {
                ForEach(block.actions) { action in
                    actionButton(action)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: ActionItem) -> some View {
        switch action.style {
        case "primary":
            Button(action.label) { onAction?(action.id) }
                .buttonStyle(.borderedProminent)
                .tint(MinoTheme.accent)
                .controlSize(.small)
        case "danger":
            Button(action.label) { onAction?(action.id) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
        default:
            Button(action.label) { onAction?(action.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Radio Block (Single Select)

private struct RadioBlockView: View {
    let block: RadioBlock
    var onAction: ((String) -> Void)?
    @State private var selected: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = block.label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            ForEach(block.options) { option in
                Button {
                    selected = option.id
                    onAction?("radio:\(block.id):\(option.id)")
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(selected == option.id ? MinoTheme.accent : Color.primary.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                            if selected == option.id {
                                Circle()
                                    .fill(MinoTheme.accent)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                            if let desc = option.description {
                                Text(desc)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            selected = block.defaultValue ?? ""
        }
    }
}

// MARK: - Checkbox Block (Multi Select)

private struct CheckboxBlockView: View {
    let block: CheckboxBlock
    var onAction: ((String) -> Void)?
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = block.label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            ForEach(block.options) { option in
                Button {
                    if selected.contains(option.id) {
                        selected.remove(option.id)
                    } else {
                        selected.insert(option.id)
                    }
                    onAction?("checkbox:\(block.id):\(selected.sorted().joined(separator: ","))")
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(selected.contains(option.id) ? MinoTheme.accent : Color.primary.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                            if selected.contains(option.id) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(MinoTheme.accent)
                                    .frame(width: 16, height: 16)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                            if let desc = option.description {
                                Text(desc)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            selected = Set(block.defaultValues ?? [])
        }
    }
}

// MARK: - Dropdown Block

private struct DropdownBlockView: View {
    let block: DropdownBlock
    var onAction: ((String) -> Void)?
    @State private var selected: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = block.label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            Picker(selection: $selected) {
                if selected.isEmpty {
                    Text(block.placeholder ?? "Select...")
                        .tag("")
                }
                ForEach(block.options) { option in
                    Text(option.label).tag(option.id)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 240)
            .onChange(of: selected) { _, newValue in
                if !newValue.isEmpty {
                    onAction?("dropdown:\(block.id):\(newValue)")
                }
            }
        }
        .onAppear {
            selected = block.defaultValue ?? ""
        }
    }
}

// MARK: - Audio Block

private struct AudioBlockView: View {
    let block: AudioBlock
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                isPlaying.toggle()
                if isPlaying {
                    AudioPlayerService.shared.play(url: block.url)
                } else {
                    AudioPlayerService.shared.stop()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(MinoTheme.accent)
                        .frame(width: 36, height: 36)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title ?? audioFilename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let duration = block.duration {
                    Text(formatDuration(duration))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(MinoTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                .stroke(MinoTheme.border, lineWidth: 0.5)
        )
    }

    private var audioFilename: String {
        URL(string: block.url)?.lastPathComponent ?? "Audio"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Video Block

private struct VideoBlockView: View {
    let block: VideoBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            videoContent
            if let caption = block.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        if let url = resolvedURL {
            VideoPlayerView(url: url)
                .frame(maxWidth: 480, minHeight: 200, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "film")
                Text("Cannot load video")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var resolvedURL: URL? {
        if block.url.hasPrefix("/") {
            return URL(fileURLWithPath: block.url)
        } else if block.url.hasPrefix("file://") {
            return URL(string: block.url)
        } else {
            return URL(string: block.url)
        }
    }
}

// MARK: - Callout Block

private struct CalloutBlockView: View {
    let block: CalloutBlock

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundStyle(accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                if let title = block.title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text(block.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.85))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
    }

    private var iconName: String {
        switch block.style {
        case "warning": "exclamationmark.triangle.fill"
        case "error": "xmark.circle.fill"
        case "success": "checkmark.circle.fill"
        default: "info.circle.fill"
        }
    }

    private var accentColor: Color {
        switch block.style {
        case "warning": .orange
        case "error": .red
        case "success": .green
        default: .blue
        }
    }
}
