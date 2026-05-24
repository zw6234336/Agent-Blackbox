import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var timeRange: TimeRange = .week
    @State private var isRefreshing = false

    enum DistributionViewMode: String, CaseIterable, Identifiable {
        case donut = "饼图"
        case list = "排行"
        var id: String { self.rawValue }
    }

    enum MetricType: String, CaseIterable, Identifiable {
        case calls = "次数"
        case cost = "费用"
        var id: String { self.rawValue }
    }

    @State private var viewMode: DistributionViewMode = .donut
    @State private var metricType: MetricType = .calls
    @State private var selectedProvider: LLMProvider? = nil

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
                .frame(minHeight: 330)

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

    private var providerDisplayList: [ProviderDisplayData] {
        let allStats = stats.providerStats
        if allStats.isEmpty {
            let totalCalls = stats.callsByProvider.values.reduce(0, +)
            return stats.callsByProvider.map { provider, count in
                let pct = totalCalls > 0 ? Double(count) / Double(totalCalls) : 0.0
                return ProviderDisplayData(
                    provider: provider,
                    count: count,
                    tokens: 0,
                    cost: 0.0,
                    avgDuration: 0.0,
                    displayValue: metricType == .calls ? Double(count) : 0.0,
                    percentage: pct
                )
            }.sorted { $0.count > $1.count }
        }
        
        let totalVal: Double
        if metricType == .calls {
            totalVal = Double(allStats.values.map { $0.count }.reduce(0, +))
        } else {
            totalVal = allStats.values.map { $0.cost }.reduce(0.0, +)
        }
        
        return allStats.map { provider, stat in
            let displayVal = metricType == .calls ? Double(stat.count) : stat.cost
            let pct = totalVal > 0 ? displayVal / totalVal : 0.0
            return ProviderDisplayData(
                provider: provider,
                count: stat.count,
                tokens: stat.tokens,
                cost: stat.cost,
                avgDuration: stat.avgDuration,
                displayValue: displayVal,
                percentage: pct
            )
        }.sorted { a, b in
            if metricType == .calls {
                return a.count > b.count
            } else {
                return a.cost > b.cost
            }
        }
    }

    private var providerDistribution: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title + Mode Toggle + Metric Toggle
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("提供商分布")
                        .font(.headline)
                    Text(metricType == .calls ? "按调用次数统计" : "按预估费用统计")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Picker("指标", selection: $metricType) {
                        ForEach(MetricType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                    
                    Picker("模式", selection: $viewMode) {
                        ForEach(DistributionViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }
            }
            
            let data = providerDisplayList
            
            if data.isEmpty {
                emptyChartPlaceholder("暂无数据")
            } else {
                VStack(spacing: 8) {
                    // Content based on View Mode
                    if viewMode == .donut {
                        HStack(spacing: 12) {
                            donutChartView(data: data)
                                .frame(width: 110, height: 110)
                                .padding(.leading, 4)
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(data) { item in
                                        legendRow(item: item)
                                    }
                                }
                                .padding(.trailing, 2)
                            }
                        }
                        .frame(height: 110)
                    } else {
                        ScrollView {
                            VStack(spacing: 5) {
                                ForEach(data) { item in
                                    providerBarRow(item: item)
                                }
                            }
                            .padding(.trailing, 4)
                        }
                        .frame(height: 110)
                    }
                    
                    // Spotlight Details Box (Shows details of selected provider, or the top provider by default)
                    let activeProvider = selectedProvider ?? data.first?.provider
                    if let activeProvider, let activeData = data.first(where: { $0.provider == activeProvider }) {
                        spotlightDetailsBox(item: activeData)
                    }
                }
            }
        }
        .frame(minWidth: 320)
        .cardStyle()
    }

    private func donutChartView(data: [ProviderDisplayData]) -> some View {
        Chart(data) { item in
            SectorMark(
                angle: .value("数值", item.displayValue),
                innerRadius: .ratio(0.55),
                angularInset: 1.5
            )
            .foregroundStyle(item.provider.brandColor)
            .cornerRadius(4)
            .opacity(selectedProvider == nil || selectedProvider == item.provider ? 1.0 : 0.35)
        }
        .chartLegend(.hidden)
    }

    private func legendRow(item: ProviderDisplayData) -> some View {
        let isSelected = selectedProvider == item.provider
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                if selectedProvider == item.provider {
                    selectedProvider = nil
                } else {
                    selectedProvider = item.provider
                }
            }
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(item.provider.brandColor)
                    .frame(width: 6, height: 6)
                
                Text(item.provider.displayName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Spacer(minLength: 4)
                
                Text(metricText(item: item))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Text(String(format: "%.0f%%", item.percentage * 100.0))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? item.provider.brandColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func metricText(item: ProviderDisplayData) -> String {
        if metricType == .calls {
            return "\(item.count)次"
        } else {
            return item.cost.formattedCurrency
        }
    }

    private func providerBarRow(item: ProviderDisplayData) -> some View {
        let isSelected = selectedProvider == item.provider
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                if selectedProvider == item.provider {
                    selectedProvider = nil
                } else {
                    selectedProvider = item.provider
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: item.provider.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(item.provider.brandColor)
                        
                        Text(item.provider.displayName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    
                    Spacer()
                    
                    Text(metricText(item: item))
                        .font(.system(size: 9).monospacedDigit())
                    
                    Text(String(format: "%.1f%%", item.percentage * 100.0))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                GeometryReader { geo in
                    let fillWidth = max(geo.size.width * CGFloat(item.percentage), 6)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.04))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.provider.brandColor.gradient)
                            .frame(width: fillWidth)
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? item.provider.brandColor.opacity(0.1) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(item.provider.brandColor.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func spotlightDetailsBox(item: ProviderDisplayData) -> some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: item.provider.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(item.provider.brandColor)
                        .clipShape(Circle())
                    
                    Text(item.provider.displayName)
                        .font(.system(size: 11, weight: .semibold))
                }
                
                Spacer()
                
                Button(action: {
                    NotificationCenter.default.post(
                        name: Notification.Name("NavigateToRateLimits"),
                        object: item.provider
                    )
                }) {
                    HStack(spacing: 2) {
                        Text("速率与配额")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 6) {
                spotlightMetricTile(
                    title: "调用次数",
                    value: "\(item.count)",
                    subValue: String(format: "%.1f%% 占比", item.percentage * 100.0),
                    color: item.provider.brandColor
                )
                
                spotlightMetricTile(
                    title: "估算费用",
                    value: item.cost.formattedCurrency,
                    subValue: item.count > 0 ? "\((item.cost / Double(item.count)).formattedCurrency)/次" : "$0.00/次",
                    color: .successGreen
                )
                
                spotlightMetricTile(
                    title: "总 Token",
                    value: item.tokens.formattedCompact,
                    subValue: item.count > 0 ? "\(item.tokens / item.count) avg" : "0 avg",
                    color: .accentGradientStart
                )
                
                spotlightMetricTile(
                    title: "平均耗时",
                    value: item.avgDuration.formattedDuration,
                    subValue: "响应耗时",
                    color: .warningOrange
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(item.provider.brandColor.opacity(0.18), lineWidth: 1)
        )
    }

    private func spotlightMetricTile(title: String, value: String, subValue: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Text(subValue)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.05))
        )
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

struct ProviderDisplayData: Identifiable {
    let id = UUID()
    let provider: LLMProvider
    let count: Int
    let tokens: Int
    let cost: Double
    let avgDuration: Double
    let displayValue: Double
    let percentage: Double
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
