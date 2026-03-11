import SwiftUI
import MarkdownUI

/// ImageProvider that supports local file paths and remote URLs
struct LocalImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if let url, let image = loadImage(from: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
        } else if let url, url.scheme == "https" || url.scheme == "http" {
            // Remote URL — use AsyncImage
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                case .failure:
                    imageFallback(url)
                case .empty:
                    ProgressView()
                        .frame(width: 80, height: 60)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            imageFallback(url)
        }
    }

    private func loadImage(from url: URL) -> NSImage? {
        // Handle file:// URLs
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }
        // Handle absolute paths passed as URL path
        let path = url.path
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            return NSImage(contentsOfFile: path)
        }
        // Try treating the full URL string as a path
        let str = url.absoluteString
        if str.hasPrefix("/"), FileManager.default.fileExists(atPath: str) {
            return NSImage(contentsOfFile: str)
        }
        return nil
    }

    private func imageFallback(_ url: URL?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text(url?.lastPathComponent ?? "Image")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
