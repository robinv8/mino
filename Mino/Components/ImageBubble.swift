import SwiftUI

struct ImageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let urlString = message.imageURL {
                    imageContent(urlString)
                }

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(6)
            .background(MinoTheme.agentBubble)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: MinoTheme.bubbleShadowRadius, y: 2)

            Spacer(minLength: 60)
        }
    }

    @ViewBuilder
    private func imageContent(_ urlString: String) -> some View {
        if urlString.hasPrefix("data:") {
            if let nsImage = loadBase64Image(urlString) {
                imageView(nsImage)
            } else {
                imagePlaceholder("Failed to decode image")
            }
        } else if urlString.hasPrefix("/") || urlString.hasPrefix("file://") {
            // Local file path
            if let nsImage = loadLocalImage(urlString) {
                imageView(nsImage)
            } else {
                imagePlaceholder("File not found")
            }
        } else if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 360, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                case .failure:
                    imagePlaceholder("Failed to load image")
                case .empty:
                    ProgressView()
                        .frame(width: 120, height: 80)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            imagePlaceholder("Invalid image URL")
        }
    }

    private func imageView(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 360, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
    }

    private func imagePlaceholder(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(width: 200, height: 60)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
    }

    private func loadLocalImage(_ path: String) -> NSImage? {
        let filePath: String
        if path.hasPrefix("file://") {
            filePath = URL(string: path)?.path ?? path
        } else {
            filePath = (path as NSString).expandingTildeInPath
        }
        return NSImage(contentsOfFile: filePath)
    }

    private func loadBase64Image(_ dataURL: String) -> NSImage? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64String = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64String) else { return nil }
        return NSImage(data: data)
    }
}
