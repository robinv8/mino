import SwiftUI
import Charts

struct TaskPanel: View {
    @Environment(AppState.self) var appState

    @State private var isEnvironmentExpanded: Bool = false
    @State private var isTimelineExpanded: Bool = false

    private var agentId: String? { appState.activeAgentId }

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

    private var activeAgent: Agent? {
        guard let agentId else { return nil }
        return appState.agents.first { $0.id == agentId }
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
                    statsGrid
                    if !data.toolUsageData.isEmpty {
                        toolUsageChart
                    }
                    messageStatsSection
                    activityTimeline
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Dashboard")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            statusPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusPill: some View {
        if let agentId {
            let isGenerating = appState.generatingAgentIds.contains(agentId)
            if isGenerating {
                HStack(spacing: 4) {
                    PulsingDot(color: Color.accentColor, size: 6)
                    Text("Generating...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Idle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.08))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Environment Section

    private func environmentSection(_ info: EnvironmentInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        if model.count > 16 {
            return String(model.prefix(16))
        }
        return model
    }

    // MARK: - Stats Grid (2×2)

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            StatCard(
                title: "Tool Calls",
                value: "\(data.completedCount)/\(data.taskItems.count)",
                icon: "checkmark.circle",
                color: .secondary
            )
            StatCard(
                title: "Success Rate",
                value: data.successRate.map { "\(Int($0 * 100))%" } ?? "—",
                icon: "chart.pie",
                color: .green
            )
            StatCard(
                title: "Cost",
                value: costText,
                icon: "dollarsign.circle",
                color: .orange
            )
            StatCard(
                title: "Duration",
                value: durationText,
                icon: "clock",
                color: .blue
            )
        }
    }

    private var costText: String {
        guard let s = stats, s.totalCost > 0 else { return "—" }
        return String(format: "$%.2f", s.totalCost)
    }

    private var durationText: String {
        guard let s = stats, s.totalDurationMs > 0 else { return "—" }
        let seconds = Double(s.totalDurationMs) / 1000
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        return String(format: "%.1fm", seconds / 60)
    }

    // MARK: - Tool Usage Chart

    private var toolUsageChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tool Usage")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                chartLegend
            }

            let entries = data.toolUsageData
            Chart(entries) { entry in
                BarMark(
                    x: .value("Count", entry.count),
                    y: .value("Tool", entry.toolName)
                )
                .foregroundStyle(entry.chartColor)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel()
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                }
            }
            .frame(height: max(80, CGFloat(Set(entries.map(\.toolName)).count) * 24))
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var chartLegend: some View {
        HStack(spacing: 8) {
            LegendDot(color: .green, label: "Completed")
            LegendDot(color: .red, label: "Failed")
            LegendDot(color: .orange, label: "Running")
        }
    }

    // MARK: - Message Stats

    @ViewBuilder
    private var messageStatsSection: some View {
        if data.userMessageCount > 0 || data.agentMessageCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Messages")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(data.userMessageCount) sent")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())

                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(data.agentMessageCount) received")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Activity Timeline

    private var activityTimeline: some View {
        let items = data.taskItems
        let hasItems = !items.isEmpty
        let displayItems = isTimelineExpanded ? items : Array(items.suffix(5))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasItems {
                    Text("\(items.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                }
            }

            if !hasItems {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayItems.reversed().enumerated()), id: \.element.id) { index, item in
                        TimelineRow(
                            item: item,
                            isLast: index == displayItems.count - 1
                        )
                    }
                }

                if items.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTimelineExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isTimelineExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isTimelineExpanded ? "Collapse" : "Show All (\(items.count))")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 20))
                .foregroundStyle(.quaternary)
            Text("No activity yet")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Timeline Row

private struct TimelineRow: View {
    let item: TaskItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timeline column: dot + line
            VStack(spacing: 0) {
                statusDot
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            // Time
            Text(item.timestamp, style: .time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)

            // Content
            if let info = item.toolCallInfo {
                let formatted = ToolCallFormatter.summary(toolName: info.toolName, arguments: info.arguments)
                Image(systemName: formatted.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(formatted.text)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusDot: some View {
        if let info = item.toolCallInfo {
            switch info.status {
            case .completed:
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            case .failed:
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            case .running:
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            }
        } else {
            Circle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Legend Dot

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
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
    var toolCallInfo: ToolCallInfo?
    let thinkingContent: String?
    let timestamp: Date

    enum TaskItemKind {
        case toolCall
        case thinking
    }
}

// MARK: - Task Row (kept for potential detail expansion)

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
                    // Rich detail views based on tool type
                    if info.toolName == "Edit" || info.toolName == "Write" {
                        DiffView(toolName: info.toolName, arguments: info.arguments)
                    } else if info.toolName == "Bash", let result = info.result, !result.isEmpty {
                        TerminalOutputView(output: result)
                    } else {
                        // Fallback: show raw arguments and result
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
                                    .lineLimit(10)
                            }
                        }
                        if let result = info.result, !result.isEmpty {
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
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
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
