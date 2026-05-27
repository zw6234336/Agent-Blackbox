import SwiftUI
import Charts

enum DashboardTimeRange: String, CaseIterable {
    case today = "当天"
    case week = "7天"
    case month = "30天"
    case all = "全部"
    
    var dayValue: Int? {
        switch self {
        case .today: return 0
        case .week: return 7
        case .month: return 30
        case .all: return nil
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var proxyServer: ProxyServerService
    @EnvironmentObject var clientInterception: ClientInterceptionService

    @AppStorage("dashboardTimeRange") private var timeRange: DashboardTimeRange = .today
    @State private var isRefreshing = false
    @State private var showPosterSheet = false

    enum DistributionViewMode: String, CaseIterable, Identifiable {
        case donut = "饼图"
        case list = "排行"
        var id: String { self.rawValue }
    }

    @State private var viewMode: DistributionViewMode = .donut
    @State private var selectedProvider: LLMProvider? = nil

    var stats: DashboardStats { database.dashboardStats }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            // 外层主 ScrollView：看板整体滚动容器
            VStack(spacing: 20) {
                // Header with refresh
                headerSection

                // Safety Interception Status Center
                safetyGuardBanner

                // Redesigned Top metrics grid (focus on technical throughput and latency)
                metricsGrid

                // Anomaly & Heavyweight Spotlights (vulnerabilities slowest/heaviest)
                performanceSpotlightRow

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
        .scrollWheelKeepAlive()
        .background(Color.dashboardBackground)
        .task {
            database.refreshDashboardStats(days: timeRange.dayValue)
        }
        .onChange(of: timeRange) { oldValue, newValue in
            database.refreshDashboardStats(days: newValue.dayValue)
        }
        .sheet(isPresented: $showPosterSheet) {
            SharePosterView()
                .environmentObject(database)
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
                ForEach(DashboardTimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isRefreshing = true
                }
                database.refreshDashboardStats(days: timeRange.dayValue)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { isRefreshing = false }
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
            }
            .buttonStyle(.plain)
            
            Spacer().frame(width: 8)
            
            Button(action: { showPosterSheet = true }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("生成并分享用量海报")
        }
    }

    // MARK: - Safety Control & Guard Banner

    private var safetyGuardBanner: some View {
        let isRunning = proxyServer.isRunning
        let errorRate = stats.errorRate
        let hasPotentialLoop = stats.recentLogs.count >= 5 && stats.errorCount > 0 && errorRate > 15.0
        
        return HStack(spacing: 16) {
            // Pulsing status shield icon
            ZStack {
                Circle()
                    .fill(isRunning ? (hasPotentialLoop ? Color.warningOrange.opacity(0.15) : Color.successGreen.opacity(0.15)) : Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isRunning ? "shield.fill" : "shield.slash.fill")
                    .font(.title2)
                    .foregroundStyle(isRunning ? (hasPotentialLoop ? Color.warningOrange : Color.successGreen) : Color.gray)
            }
            .padding(.leading, 8)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(isRunning ? "网关拦截防御罩已开启" : "网关拦截防御罩已关闭")
                        .font(.headline)
                    
                    if isRunning {
                        Text("运行中")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.successGreen.opacity(0.15))
                            .foregroundStyle(Color.successGreen)
                            .clipShape(Capsule())
                    } else {
                        Text("未启动")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    
                    if hasPotentialLoop {
                        Text("🚨 异常率偏高 · 请注意死循环风险")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.errorRed.opacity(0.15))
                            .foregroundStyle(Color.errorRed)
                            .clipShape(Capsule())
                    } else if isRunning {
                        Text("🛡️ 防护状态：安全")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.infoBlue.opacity(0.15))
                            .foregroundStyle(Color.infoBlue)
                            .clipShape(Capsule())
                    }
                }
                
                Text(isRunning 
                     ? "本地代理拦截器处于监听状态。AI 代理发送的 API 请求将被安全分发与限流拦截，防止高频重复调用死循环。" 
                     : "当前处于网关直连或旁路模式，无法实时拦截代理死循环和统计最新速率配额。建议开启网关。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Switch toggle or buttons for emergency actions
            VStack(alignment: .trailing, spacing: 6) {
                Button(action: {
                    if isRunning {
                        proxyServer.stop()
                    } else {
                        proxyServer.start()
                    }
                }) {
                    Label(isRunning ? "紧急关闭网关" : "快速启动网关", systemImage: isRunning ? "power" : "play.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? Color.errorRed : Color.successGreen)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isRunning ? (hasPotentialLoop ? Color.warningOrange.opacity(0.3) : Color.successGreen.opacity(0.2)) : Color.gray.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Redesigned Metrics Grid

    private var metricsGrid: some View {
        HStack(spacing: 16) {
            MetricCardView(
                title: "总调用次数 (Calls)",
                value: stats.totalCalls.formattedCompact,
                icon: "bolt.fill",
                color: .infoBlue,
                subtitle: "异常率: \(stats.errorRate.formattedPercent) (\(stats.errorCount)个)"
            )

            MetricCardView(
                title: "Token 吞吐 (Tokens)",
                value: stats.totalTokens.formattedCompact,
                icon: "textformat.abc",
                color: .accentGradientStart,
                subtitle: "P: \(stats.totalPromptTokens.formattedCompact) / C: \(stats.totalCompletionTokens.formattedCompact)"
            )

            MetricCardView(
                title: "平均延迟 (Latency)",
                value: stats.avgResponseTime.formattedDuration,
                icon: "timer",
                color: .warningOrange,
                subtitle: "LLM 平均响应耗时"
            )

            MetricCardView(
                title: "本地调用 (Local)",
                value: stats.localCallsCount.formattedCompact,
                icon: "cpu",
                color: .successGreen,
                subtitle: "本地模型 (Ollama/LM Studio) 调用"
            )
        }
    }

    // MARK: - Vulnerability & Anomaly Spotlights

    private var performanceSpotlightRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("性能瓶颈与异常监控 (Anomaly & Performance Spotlights)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("过滤窗口内性能及用量极值分析")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 16) {
                // Card 1: Slowest Latency Call
                spotlightCard(
                    title: "⏱️ 最慢延迟调用",
                    log: stats.slowestLog,
                    metricLabel: "耗时",
                    metricValue: stats.slowestLog?.duration?.formattedDuration ?? "—",
                    color: .warningOrange,
                    emptyText: "暂无慢调用记录"
                )
                
                // Card 2: Largest Context Payload
                spotlightCard(
                    title: "📦 最大上下文 Payload",
                    log: stats.largestPayloadLog,
                    metricLabel: "大小",
                    metricValue: stats.largestPayloadLog?.totalTokens.map { "\($0.formattedCompact) tok" } ?? "—",
                    color: .infoBlue,
                    emptyText: "暂无上下文日志"
                )
            }
        }
    }
    
    @ViewBuilder
    private func spotlightCard(
        title: String,
        log: ParsedLog?,
        metricLabel: String,
        metricValue: String,
        color: Color,
        emptyText: String
    ) -> some View {
        Button(action: {
            if let log = log {
                NotificationCenter.default.post(name: Notification.Name("ShowLogDetailSheet"), object: log)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                
                if let log = log {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.modelName ?? "Unknown Model")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(color)
                                .lineLimit(1)
                            
                            Text("来源: \(log.sourceFile.split(separator: "/").last.map(String.init) ?? log.sourceFile)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(metricValue)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(metricLabel)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Divider().opacity(0.3)
                    
                    if let prompt = log.prompt, !prompt.isEmpty {
                        Text(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("无 prompt 详情")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "circle.slash")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text(emptyText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(log != nil ? 0.25 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(log == nil)
    }

    private func deterministicHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }

    private func colorForModel(_ modelName: String) -> Color {
        let lower = modelName.lowercased()
        if lower.contains("gpt-4") || lower.contains("gpt-3") || lower.contains("gpt-") || lower.hasPrefix("o1") || lower.hasPrefix("o3") {
            return Color(red: 0.1, green: 0.65, blue: 0.45) // 翡翠绿 (OpenAI)
        } else if lower.contains("claude") || lower.contains("anthropic") {
            return Color(red: 0.95, green: 0.45, blue: 0.2) // 珊瑚橙 (Anthropic)
        } else if lower.contains("gemini") {
            return Color(red: 0.4, green: 0.3, blue: 0.9) // 极光紫 (Google)
        } else if lower.contains("deepseek") {
            return Color(red: 0.12, green: 0.45, blue: 0.9) // 科技蓝 (DeepSeek)
        } else if lower.contains("llama") || lower.contains("ollama") {
            return Color(red: 0.85, green: 0.65, blue: 0.1) // 金黄色 (Llama)
        } else if lower.contains("glm") || lower.contains("zhipu") || lower.contains("chatglm") {
            return Color(red: 0.0, green: 0.62, blue: 0.86) // 青蓝色 (智谱清言 GLM)
        } else if lower.contains("qwen") || lower.contains("tongyi") || lower.contains("aliyun") {
            return Color(red: 0.35, green: 0.25, blue: 0.85) // 智海蓝 (阿里通义千问)
        } else if lower.contains("kimi") || lower.contains("moonshot") {
            return Color(red: 0.9, green: 0.3, blue: 0.15) // 橙红色 (Moonshot Kimi)
        } else if lower.contains("doubao") || lower.contains("bytedance") {
            return Color(red: 0.0, green: 0.5, blue: 1.0) // 字节蓝色 (豆包)
        } else if lower.contains("minimax") {
            return Color(red: 0.8, green: 0.1, blue: 0.4) // 紫红色 (MiniMax)
        } else if lower.contains("grok") || lower.contains("xai") {
            return Color(red: 0.45, green: 0.45, blue: 0.45) // 白灰色/玄铁黑 (xAI Grok)
        } else if lower.contains("ernie") || lower.contains("wenxin") || lower.contains("yiyan") {
            return Color(red: 0.05, green: 0.4, blue: 0.9) // 百度科技蓝 (文心一言)
        } else if lower.contains("baichuan") {
            return Color(red: 0.85, green: 0.15, blue: 0.15) // 红橙色 (百川)
        } else if lower == "other" || lower == "其它" || lower == "其他" {
            return Color.secondary
        } else {
            let hash = deterministicHash(modelName)
            let colors: [Color] = [
                .teal, .indigo, .pink, .cyan, .mint, .orange, .purple,
                .blue, .green, .red, .yellow
            ]
            return colors[hash % colors.count]
        }
    }

    private var tokenTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token 使用趋势")
                .font(.headline)

            if stats.modelTokensByDay.isEmpty {
                emptyChartPlaceholder("暂无数据")
            } else {
                let uniqueModels = Array(Set(stats.modelTokensByDay.map { $0.modelName })).sorted()
                Chart(stats.modelTokensByDay) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("Tokens", point.totalTokens)
                    )
                    .foregroundStyle(by: .value("模型", point.modelName))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("Tokens", point.totalTokens)
                    )
                    .foregroundStyle(by: .value("模型", point.modelName))
                    .opacity(0.08)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("时间", point.date),
                        y: .value("Tokens", point.totalTokens)
                    )
                    .foregroundStyle(by: .value("模型", point.modelName))
                    .symbolSize(18)
                }
                .chartForegroundStyleScale(domain: uniqueModels, range: uniqueModels.map { colorForModel($0) })
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
                    if timeRange == .today {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                            AxisGridLine()
                        }
                    } else {
                        let uniqueDaysCount = Set(stats.modelTokensByDay.map { $0.date }).count
                        AxisMarks(values: .stride(by: .day, count: uniqueDaysCount > 10 ? 7 : 1)) { value in
                            AxisValueLabel(format: .dateTime.month().day())
                            AxisGridLine()
                        }
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
                    avgDuration: 0.0,
                    displayValue: Double(count),
                    percentage: pct
                )
            }.sorted { $0.count > $1.count }
        }

        let totalVal = Double(allStats.values.map { $0.count }.reduce(0, +))

        return allStats.map { provider, stat in
            let displayVal = Double(stat.count)
            let pct = totalVal > 0 ? displayVal / totalVal : 0.0
            return ProviderDisplayData(
                provider: provider,
                count: stat.count,
                tokens: stat.tokens,
                avgDuration: stat.avgDuration,
                displayValue: displayVal,
                percentage: pct
            )
        }.sorted { $0.count > $1.count }
    }

    private var providerDistribution: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title + Mode Toggle + Metric Toggle
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("提供商分布")
                        .font(.headline)
                    Text("按调用次数统计")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
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

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(data.prefix(5)) { item in
                                    legendRow(item: item)
                                }
                            }
                            .padding(.trailing, 2)
                        }
                        .frame(height: 110)
                    } else {
                        VStack(spacing: 5) {
                            ForEach(data.prefix(4)) { item in
                                providerBarRow(item: item)
                            }
                        }
                        .padding(.trailing, 4)
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
        return "\(item.count)次"
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

                    VStack(spacing: 10) {
                        ForEach(Array(modelData.prefix(6).enumerated()), id: \.element.id) { index, item in
                            ModelRankingRow(
                                rank: index + 1,
                                item: item,
                                maxCount: maxCount,
                                totalCalls: totalCalls,
                                color: colorForModel(item.name)
                            )
                        }
                    }
                    .padding(.bottom, 4)
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
                VStack(spacing: 8) {
                    ForEach(stats.recentLogs.prefix(6)) { log in
                        LiveFeedRow(log: log) {
                            NotificationCenter.default.post(name: Notification.Name("ShowLogDetailSheet"), object: log)
                        }
                        .contextMenu {
                            Button {
                                if let prompt = log.prompt {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(prompt, forType: .string)
                                }
                            } label: {
                                Label("复制 Prompt / 输入", systemImage: "doc.on.doc")
                            }
                            .disabled(log.prompt == nil)

                            Button {
                                if let response = log.response {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(response, forType: .string)
                                }
                            } label: {
                                Label("复制 Response / 输出", systemImage: "doc.on.doc.fill")
                            }
                            .disabled(log.response == nil)

                            Divider()

                            Button {
                                Task { await database.toggleBookmark(logId: log.id) }
                            } label: {
                                Label(log.isBookmarked ? "取消收藏" : "加入收藏", systemImage: log.isBookmarked ? "star.slash" : "star")
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
        .buttonStyle(.plain)
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
    let color: Color

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
            HStack(alignment: .center, spacing: 8) {
                Text("#\(rank)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

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
                        .fill(color.opacity(0.12))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.75)],
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
                .fill(color.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.08), lineWidth: 1)
        )
    }
}
