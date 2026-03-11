import SwiftUI

struct ResourcePanel: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: ResourceCategory?
    @State private var selectedResource: ResourceItem?

    private var resources: [ResourceItem] {
        guard let agentId = appState.activeAgentId else { return [] }
        return appState.resources[agentId] ?? []
    }

    private var categories: [ResourceCategory] {
        let present = Set(resources.map(\.category))
        return ResourceCategory.allCases.filter { present.contains($0) }
    }

    private var filteredResources: [ResourceItem] {
        if let cat = selectedCategory {
            return resources.filter { $0.category == cat }
        }
        return resources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if resources.isEmpty {
                emptyState
            } else {
                categoryBar
                resourceList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Resources")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(resources.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Category Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(nil, label: "All", count: resources.count)
                ForEach(categories, id: \.self) { cat in
                    categoryChip(cat, label: cat.label, count: resources.filter { $0.category == cat }.count)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(_ category: ResourceCategory?, label: String, count: Int) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.icon)
                        .font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? MinoTheme.accent : Color.primary.opacity(0.04))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resource List

    private var resourceList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredResources) { resource in
                    ResourceRow(resource: resource, isSelected: selectedResource?.id == resource.id)
                        .onTapGesture {
                            selectedResource = resource
                        }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No resources yet")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Images, code, and links from\nconversations appear here")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Resource Row

struct ResourceRow: View {
    let resource: ResourceItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            resourceIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(resource.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(resource.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? MinoTheme.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(resource.content, forType: .string)
            }
            if resource.category == .link, let url = URL(string: resource.content) {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private var resourceIcon: some View {
        Group {
            switch resource.category {
            case .image:
                if resource.content.hasPrefix("data:") {
                    // Base64 thumbnail
                    if let nsImage = loadBase64Thumbnail(resource.content) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        iconPlaceholder
                    }
                } else if let url = URL(string: resource.content) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            iconPlaceholder
                        }
                    }
                } else {
                    iconPlaceholder
                }
            case .code:
                iconPlaceholder
            case .link:
                iconPlaceholder
            case .file:
                iconPlaceholder
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var iconPlaceholder: some View {
        ZStack {
            Color.primary.opacity(0.04)
            Image(systemName: resource.category.icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func loadBase64Thumbnail(_ dataURL: String) -> NSImage? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
