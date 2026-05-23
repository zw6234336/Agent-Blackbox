import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var timeRange: TimeRange = .week
    @State private var isRefreshing = false

    enum TimeRange: String, CaseIterable {
        case week = "7天"
        case month = "30天"
        case all = "全部"
    }

    var stats: DashboardStats { database.dashboardStats }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with refresh
                headerSection

                // Top metric cards
                metricsGrid

                // Charts row
                HStack(spacing: 16) {
                    tokenTrendChart
                    providerDistribution
                }
                .frame(minHeight: 260)

                // Bottom row: Model chart + Live feed
                HStack(spacing: 16) {
                    modelBarChart
                    liveFeedSection
                }
                .frame(minHeight: 280)
            }
            .padding(20)
        }
        .background(Color.dashboardBackground)
        .task {
            database.refreshDashboardStats(days: daysForRange(timeRange))
        }
        .onChange(of: timeRange) { oldValue, newValue in
            database.refreshDashboardStats(days: daysForRange(newValue))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("数字看板")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("LLM 调用监控总览")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("时间范围", selection: $timeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRefreshing = true
                }
                database.refreshDashboardStats(days: daysForRange(timeRange))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { isRefreshing = false }
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        HStack(spacing: 16) {
            MetricCardView(
                title: "总调用",
                value: stats.totalCalls.formattedCompact,
                icon: "bolt.fill",
                color: .infoBlue,
                subtitle: "次"
            )

            MetricCardView(
                title: "总 Token",
                value: stats.totalTokens.formattedCompact,
                icon: "textformat.abc",
                color: .accentGradientStart,
                subtitle: "prompt \(stats.totalPromptTokens.formattedCompact) + completion \(stats.totalCompletionTokens.formattedCompact)"
            )

            MetricCardView(
                title: "预估费用",
                value: stats.totalCost.formattedCurrency,
                icon: "dollarsign.circle.fill",
                color: .successGreen,
                subtitle: "美元"
            )

            MetricCardView(
                title: "平均响应",
                value: stats.avgResponseTime.formattedDuration,
                icon: "clock.fill",
                color: .warningOrange,
                subtitle: "响应时间"
            )

            MetricCardView(
                title: "错误率",
                value: stats.errorRate.formattedPercent,
                icon: "exclamationmark.triangle.fill",
                color: stats.errorRate > 10 ? .errorRed : .successGreen,
                subtitle: "\(stats.errorCount) 个错误"
            )
        }
    }

    // MARK: - Token Trend Chart

    private var tokenTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token 使用趋势")
                .font(.headline)

            if stats.tokensByDay.isEmpty {
                emptyChartPlaceholder("暂无数据")
            } else {
                Chart(stats.tokensByDay) { day in
                    BarMark(
                        x: .value("日期", day.date, unit: .day),
                        y: .value("Prompt", day.promptTokens)
                    )
                    .foregroundStyle(Color.infoBlue.gradient)

                    BarMark(
                        x: .value("日期", day.date, unit: .day),
                        y: .value("Completion", day.completionTokens)
                    )
                    .foregroundStyle(Color.accentGradientStart.gradient)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text(v.formattedCompact)
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisValueLabel(format: .dateTime.month().day())
                        AxisGridLine()
                    }
                }
                .chartLegend(position: .top, alignment: .trailing)
            }
        }
        .cardStyle()
    }

    // MARK: - Provider Distribution

    private var providerDistribution: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提供商分布")
                .font(.headline)

            if stats.callsByProvider.isEmpty {
                emptyChartPlaceholder("暂无数据")
            } else {
                let providerData = stats.callsByProvider.map { ProviderChartData(provider: $0.key, count: $0.value) }
                    .sorted { $0.count > $1.count }

                Chart(providerData) { item in
                    SectorMark(
                        angle: .value("调用次数", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(item.provider.brandColor)
                    .cornerRadius(4)
                    .annotation(position: .overlay) {
                        if item.count > 0 {
                            Text(item.provider.displayName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: 8) {
                    HStack(spacing: 12) {
                        ForEach(providerData) { item in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(item.provider.brandColor)
                                    .frame(width: 8, height: 8)
                                Text("\(item.provider.displayName): \(item.count)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280)
        .cardStyle()
    }

    // MARK: - Model Bar Chart

    private var modelBarChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("模型调用排行")
                    .font(.headline)
                Spacer()
                Text("全部模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if stats.callsByModel.isEmpty {
                emptyChartPlaceholder("暂无数据")
            } else {
                let modelData = stats.callsByModel.map { ModelChartData(name: $0.key, count: $0.value) }
                    .sorted { $0.count > $1.count }
                let maxCount = modelData.first?.count ?? 1
                let totalCalls = modelData.reduce(0) { $0 + $1.count }

                VStack(alignment: .leading, spacing: 10) {
                    Text("按调用次数降序展示，并保留小调用量模型，避免被头部模型压缩到不可见。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(modelData.enumerated()), id: \.element.id) { index, item in
                                ModelRankingRow(
                                    rank: index + 1,
                                    item: item,
                                    maxCount: maxCount,
                                    totalCalls: totalCalls
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Live Feed

    private var liveFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近日志")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(Color.successGreen)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.successGreen.opacity(0.3), lineWidth: 3)
                            .scaleEffect(1.5)
                    )
                Text("实时")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if stats.recentLogs.isEmpty {
                emptyChartPlaceholder("暂无日志")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(stats.recentLogs) { log in
                            LiveFeedRow(log: log)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 320)
        .cardStyle()
    }

    // MARK: - Helpers

    private func emptyChartPlaceholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func daysForRange(_ range: TimeRange) -> Int? {
        switch range {
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }
}

// MARK: - Supporting Views

struct MetricCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
                )
        )
        .shadow(color: color.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 4, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct LiveFeedRow: View {
    let log: ParsedLog

    var body: some View {
        HStack(spacing: 10) {
            // Provider icon
            Image(systemName: log.provider?.iconName ?? "questionmark.circle")
                .font(.caption)
                .foregroundStyle(log.provider?.brandColor ?? .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.modelName ?? "Unknown")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let tokens = log.totalTokens {
                    Text("\(tokens.formattedCompact) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if log.errorMessage != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.errorRed)
            }

            Text(log.timestamp.formattedRelative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Chart Data Models

struct ProviderChartData: Identifiable {
    let id = UUID()
    let provider: LLMProvider
    let count: Int
}

struct ModelChartData: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}

struct ModelRankingRow: View {
    let rank: Int
    let item: ModelChartData
    let maxCount: Int
    let totalCalls: Int

    private var fillRatio: Double {
        guard maxCount > 0 else { return 0 }
        return max(Double(item.count) / Double(maxCount), 0.04)
    }

    private var shareText: String {
        guard totalCalls > 0 else { return "0%" }
        return (Double(item.count) / Double(totalCalls)).formatted(.percent.precision(.fractionLength(1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(rank)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)

                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(item.count)")
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)

                Text(shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width * fillRatio, 8)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.accentGradientStart, .accentGradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width)
                }
            }
            .frame(height: 10)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
    }
}
