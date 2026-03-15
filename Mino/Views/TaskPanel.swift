import SwiftUI
import Charts

struct TaskPanel: View {
    @EnvironmentObject var appState: AppState

    @State private var isEnvironmentExpanded: Bool = false

    private var agentId: String? { appState.activeAgentId }

    /// Read dashboard data directly from AppState (incrementally maintained).
    private var data: TaskData {
        guard let agentId else { return TaskData() }
        return appState.taskData[agentId] ?? TaskData()
    }

    private var envInfo: EnvironmentInfo? {
        guard let agentId else { return nil }
        let info = appState.environmentInfo[agentId]
        if let info, (!info.model.isEmpty || !info.tools.isEmpty || !info.mcpServers.isEmpty || !info.plugins.isEmpty) {
            return info
        }
        return nil
    }

    private var stats: SessionStats? {
        guard let agentId else { return nil }
        return appState.sessionStats[agentId]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let envInfo {
                        environmentSection(envInfo)
                    }
                    statsCards
                    if !data.toolUsageData.isEmpty {
                        toolUsageChart
                    }
                    taskListSection
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Dashboard")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Environment Section

    private func environmentSection(_ info: EnvironmentInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Compact pills row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEnvironmentExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if !info.model.isEmpty {
                        EnvironmentPill(icon: "cpu", text: formatModelName(info.model))
                    }
                    if !info.tools.isEmpty {
                        EnvironmentPill(icon: "wrench", text: "\(info.tools.count) tools")
                    }
                    if !info.mcpServers.isEmpty {
                        EnvironmentPill(icon: "server.rack", text: "\(info.mcpServers.count) MCP")
                    }
                    if !info.plugins.isEmpty {
                        EnvironmentPill(icon: "puzzlepiece", text: "\(info.plugins.count) plugins")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isEnvironmentExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Expandable detail
            if isEnvironmentExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !info.tools.isEmpty {
                        environmentDetailList(title: "Tools", items: info.tools, icon: "wrench")
                    }
                    if !info.mcpServers.isEmpty {
                        environmentDetailList(title: "MCP Servers", items: info.mcpServers, icon: "server.rack")
                    }
                    if !info.plugins.isEmpty {
                        environmentDetailList(title: "Plugins", items: info.plugins, icon: "puzzlepiece")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func environmentDetailList(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
    }

    /// Shorten model identifier for display (e.g. "claude-sonnet-4-5-20250514" → "Sonnet 4.5")
    private func formatModelName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") {
            if lower.contains("4-6") || lower.contains("4.6") { return "Opus 4.6" }
            if lower.contains("4-5") || lower.contains("4.5") { return "Opus 4.5" }
            if lower.contains("4-") || lower.contains("4.") { return "Opus 4" }
            return "Opus"
        }
        if lower.contains("sonnet") {
            if lower.contains("4-6") || lower.contains("4.6") { return "Sonnet 4.6" }
            if lower.contains("4-5") || lower.contains("4.5") { return "Sonnet 4.5" }
            if lower.contains("4-") || lower.contains("4.") { return "Sonnet 4" }
            return "Sonnet"
        }
        if lower.contains("haiku") {
            if lower.contains("4-5") || lower.contains("4.5") { return "Haiku 4.5" }
            return "Haiku"
        }
        // Fallback: return as-is but truncated
        if model.count > 16 {
            return String(model.prefix(16))
        }
        return model
    }

    // MARK: - Stats Cards

    private var statsCards: some View {
        HStack(spacing: 8) {
            StatCard(
                title: "Tasks",
                value: "\(data.completedCount)/\(data.taskItems.count)",
                icon: "checkmark.circle",
                color: .green
            )
            StatCard(
                title: "Success",
                value: data.successRate.map { "\(Int($0 * 100))%" } ?? "—",
                icon: "chart.pie",
                color: MinoTheme.accent,
                ringProgress: data.successRate
            )
            StatCard(
                title: stats?.totalCost ?? 0 > 0 ? "Cost" : "Duration",
                value: statsValueText,
                icon: stats?.totalCost ?? 0 > 0 ? "dollarsign.circle" : "clock",
                color: .orange
            )
        }
    }

    private var statsValueText: String {
        guard let s = stats else { return "—" }
        if s.totalCost > 0 {
            return String(format: "$%.2f", s.totalCost)
        }
        if s.totalDurationMs > 0 {
            let seconds = Double(s.totalDurationMs) / 1000
            if seconds < 60 { return String(format: "%.1fs", seconds) }
            return String(format: "%.1fm", seconds / 60)
        }
        return "—"
    }

    // MARK: - Tool Usage Chart

    private var toolUsageChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tool Usage")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Chart(data.toolUsageData) { entry in
                BarMark(
                    x: .value("Tool", entry.toolName),
                    y: .value("Count", entry.count)
                )
                .foregroundStyle(entry.chartColor)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .frame(height: 120)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Task List Section

    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tasks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(data.taskItems.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
            }

            if data.taskItems.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(data.taskItems.reversed()) { item in
                        TaskRow(item: item, isSelected: appState.selectedToolCallId == item.id)
                            .id(item.id)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    appState.selectedToolCallId = item.id
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 20))
                .foregroundStyle(.quaternary)
            Text("No tasks yet")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var ringProgress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let progress = ringProgress {
                    MiniRing(progress: progress, color: color)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Mini Ring

private struct MiniRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Tool Usage Entry

struct ToolUsageEntry: Identifiable {
    let toolName: String
    let status: ToolCallStatus
    let count: Int

    var id: String { "\(toolName)-\(status)" }

    var chartColor: Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .running: return .orange
        }
    }
}

// MARK: - Task Item Model

struct TaskItem: Identifiable {
    let id: String
    let kind: TaskItemKind
    let toolCallInfo: ToolCallInfo?
    let thinkingContent: String?
    let timestamp: Date

    enum TaskItemKind {
        case toolCall
        case thinking
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let item: TaskItem
    let isSelected: Bool

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let info = item.toolCallInfo {
                    ToolCallStatusIcon(status: info.status)
                    let formatted = ToolCallFormatter.summary(toolName: info.toolName, arguments: info.arguments)
                    Image(systemName: formatted.icon)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    Text(formatted.text)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Spacer()
                Text(item.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded, let info = item.toolCallInfo {
                VStack(alignment: .leading, spacing: 6) {
                    if !info.arguments.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Arguments")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(info.arguments)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if let result = info.result {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Result")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(result)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .lineLimit(20)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(isSelected ? MinoTheme.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

}

// MARK: - Environment Pill

private struct EnvironmentPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
