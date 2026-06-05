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
    @State private var scrollPosition: Date = Date()

    @State private var zoomLevelIndex: Int = 2

    private var zoomSteps: [TimeInterval] {
        switch timeRange {
        case .today:
            return [3600.0, 2.0 * 3600.0, 4.0 * 3600.0, 6.0 * 3600.0, 12.0 * 3600.0, 24.0 * 3600.0]
        case .week:
            return [12.0 * 3600.0, 24.0 * 3600.0, 2.0 * 24.0 * 3600.0, 4.0 * 24.0 * 3600.0, 7.0 * 24.0 * 3600.0]
        case .month:
            return [24.0 * 3600.0, 3.0 * 24.0 * 3600.0, 5.0 * 24.0 * 3600.0, 10.0 * 24.0 * 3600.0, 20.0 * 24.0 * 3600.0, 30.0 * 24.0 * 3600.0]
        case .all:
            let defaultSteps: [TimeInterval] = [2.0 * 24.0 * 3600.0, 5.0 * 24.0 * 3600.0, 7.0 * 24.0 * 3600.0, 14.0 * 24.0 * 3600.0, 30.0 * 24.0 * 3600.0, 90.0 * 24.0 * 3600.0]
            if let firstDate = stats.modelTokensByDay.first?.date,
               let lastDate = stats.modelTokensByDay.last?.date {
                let span = lastDate.timeIntervalSince(firstDate)
                var filtered = defaultSteps.filter { $0 < span }
                if filtered.isEmpty {
                    filtered.append(max(2.0 * 24.0 * 3600.0, span))
                } else if filtered.last != span {
                    filtered.append(span)
                }
                return filtered
            }
            return defaultSteps
        }
    }

    private func defaultZoomIndex(for range: DashboardTimeRange) -> Int {
        switch range {
        case .today: return 1 // 2 hours
        case .week: return 2  // 2 days
        case .month: return 2 // 5 days
        case .all: return 2   // 7 days
        }
    }

    private var xVisibleDomainLength: TimeInterval {
        let steps = zoomSteps
        if zoomLevelIndex >= 0 && zoomLevelIndex < steps.count {
            return steps[zoomLevelIndex]
        }
        return steps[min(2, steps.count - 1)]
    }

    private var xAxisDomain: ClosedRange<Date> {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        
        switch timeRange {
        case .today:
            let end = max(startOfToday.addingTimeInterval(24 * 3600), now)
            return startOfToday...end
        case .week:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            return start...now
        case .month:
            let start = Calendar.current.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
            return start...now
        case .all:
            if let firstDate = stats.modelTokensByDay.first?.date,
               let lastDate = stats.modelTokensByDay.last?.date {
                let span = lastDate.timeIntervalSince(firstDate)
                if span < 7 * 24 * 3600 {
                    let adjustedStart = Calendar.current.date(byAdding: .day, value: -7, to: lastDate) ?? firstDate
                    return adjustedStart...lastDate
                }
                return firstDate...lastDate
            }
            let start = Calendar.current.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            return start...now
        }
    }

    private var visibleMaxY: Double {
        let length = xVisibleDomainLength
        let start = scrollPosition
        let end = scrollPosition.addingTimeInterval(length)
        
        let visiblePoints = stats.modelTokensByDay.filter { point in
            point.date >= start && point.date <= end
        }
        
        let maxVal = visiblePoints.map { Double($0.totalTokens) }.max() ?? 100.0
        return maxVal * 1.15
    }

    private func clampScrollPosition(_ date: Date, length: TimeInterval) -> Date {
        let domain = xAxisDomain
        let minDate = domain.lowerBound
        let maxDate = domain.upperBound
        
        var start = max(date, minDate)
        if start.addingTimeInterval(length) > maxDate {
            start = maxDate.addingTimeInterval(-length)
        }
        return max(start, minDate)
    }

    private func resetScrollPosition(for data: [ModelDayTokens]? = nil) {
        let points = data ?? stats.modelTokensByDay
        let targetScroll: Date
        if let lastDate = points.last?.date {
            targetScroll = lastDate.addingTimeInterval(-xVisibleDomainLength)
        } else {
            targetScroll = Date().addingTimeInterval(-xVisibleDomainLength)
        }
        scrollPosition = clampScrollPosition(targetScroll, length: xVisibleDomainLength)
    }

    private var canZoomIn: Bool {
        zoomLevelIndex > 0
    }
    
    private var canZoomOut: Bool {
        zoomLevelIndex < zoomSteps.count - 1
    }
    
    private func zoomIn() {
        if zoomLevelIndex > 0 {
            let oldLength = xVisibleDomainLength
            let rightmostDate = scrollPosition.addingTimeInterval(oldLength)
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                zoomLevelIndex -= 1
                let newLength = xVisibleDomainLength
                let targetScroll = rightmostDate.addingTimeInterval(-newLength)
                scrollPosition = clampScrollPosition(targetScroll, length: newLength)
            }
        }
    }
    
    private func zoomOut() {
        let steps = zoomSteps
        if zoomLevelIndex < steps.count - 1 {
            let oldLength = xVisibleDomainLength
            let rightmostDate = scrollPosition.addingTimeInterval(oldLength)
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                zoomLevelIndex += 1
                let newLength = xVisibleDomainLength
                let targetScroll = rightmostDate.addingTimeInterval(-newLength)
                scrollPosition = clampScrollPosition(targetScroll, length: newLength)
            }
        }
    }

    private func triggerRefreshAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRefreshing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isRefreshing = false
            }
        }
    }

    private var visibleTimeRangeString: String {
        let length = xVisibleDomainLength
        let start = scrollPosition
        let end = scrollPosition.addingTimeInterval(length)
        
        let formatter = DateFormatter()
        if timeRange == .today {
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else {
            formatter.dateFormat = "MM-dd"
            return "\(formatter.string(from: start)) 至 \(formatter.string(from: end))"
        }
    }

    var stats: DashboardStats { database.dashboardStats }

    var body: some View {
        NativeScrollView {
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
                        .frame(maxHeight: .infinity)
                    providerDistribution
                        .frame(maxHeight: .infinity)
                }
                .frame(height: 480)

                // Bottom row: Model chart + Live feed
                HStack(spacing: 16) {
                    modelBarChart
                        .frame(maxHeight: .infinity)
                    liveFeedSection
                        .frame(maxHeight: .infinity)
                }
                .frame(height: 460)
            }
            .padding(20)
            .opacity(isRefreshing ? 0.75 : 1.0)
            .blur(radius: isRefreshing ? 0.8 : 0)
            .animation(.easeInOut(duration: 0.25), value: isRefreshing)
        }
        .background(Color.dashboardBackground)
        .task {
            database.refreshDashboardStats(days: timeRange.dayValue)
            zoomLevelIndex = defaultZoomIndex(for: timeRange)
            withAnimation(.easeInOut(duration: 0.35)) {
                resetScrollPosition()
            }
        }
        .onChange(of: timeRange) { oldValue, newValue in
            triggerRefreshAnimation()
            database.refreshDashboardStats(days: newValue.dayValue)
            zoomLevelIndex = defaultZoomIndex(for: newValue)
            withAnimation(.easeInOut(duration: 0.35)) {
                resetScrollPosition()
            }
        }
        .onChange(of: database.dashboardStats.modelTokensByDay) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.35)) {
                resetScrollPosition(for: newValue)
            }
        }
        .sheet(isPresented: $showPosterSheet) {
            SharePosterView()
                .environmentObject(database)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        let isRunning = proxyServer.isRunning
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("数字看板")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Button(action: {
                        withAnimation {
                            if isRunning {
                                proxyServer.stop()
                            } else {
                                proxyServer.start()
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isRunning ? Color.successGreen : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(isRunning ? "网关运行中" : "网关未启动")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isRunning ? .primary : .secondary)
                            Image(systemName: "power")
                                .font(.system(size: 10))
                                .foregroundStyle(isRunning ? Color.errorRed : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(isRunning ? "点击紧急关闭网关" : "点击快速启动网关")
                }
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

    @ViewBuilder
    private var safetyGuardBanner: some View {
        let isRunning = proxyServer.isRunning
        let errorRate = stats.errorRate
        let hasPotentialLoop = stats.recentLogs.count >= 5 && stats.errorCount > 0 && errorRate > 15.0
        
        if hasPotentialLoop && isRunning {
            HStack(spacing: 16) {
                // Pulsing status shield icon
                ZStack {
                    Circle()
                        .fill(Color.errorRed.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.errorRed)
                }
                .padding(.leading, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("死循环及高异常率风险告警")
                            .font(.headline)
                            .foregroundStyle(Color.errorRed)
                        
                        Text("🚨 疑似死循环风险")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.errorRed.opacity(0.15))
                            .foregroundStyle(Color.errorRed)
                            .clipShape(Capsule())
                    }
                    
                    Text("当前网关调用异常率高达 \(errorRate.formattedPercent)，已发现 \(stats.errorCount) 个异常。建议紧急检查 AI 代理客户端的重复请求，以防止死循环造成高额费用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Emergency Close Button
                Button(action: {
                    withAnimation {
                        proxyServer.stop()
                    }
                }) {
                    Label("紧急关闭网关", systemImage: "power")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.errorRed)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.errorRed.opacity(0.3), lineWidth: 1)
                    )
            )
        }
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
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: stats.totalCalls)
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
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: stats.slowestLog)
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
                    
                    Spacer(minLength: 0)
                    
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
            .frame(maxWidth: .infinity, minHeight: 110, maxHeight: .infinity)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Token 使用趋势")
                        .font(.headline)
                    Text("当前窗口: \(visibleTimeRangeString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Zoom Controls
                HStack(spacing: 8) {
                    Button(action: {
                        zoomOut()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: 11, weight: .bold))
                            Text("缩小")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .foregroundStyle(canZoomOut ? Color.blue : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canZoomOut)
                    .help("缩小：扩大时间范围，查看更长期的趋势")
                    
                    Button(action: {
                        zoomIn()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 11, weight: .bold))
                            Text("放大")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .foregroundStyle(canZoomIn ? Color.blue : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canZoomIn)
                    .help("放大：缩小时间范围，查看更细致的趋势")
                }
            }

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
                .chartScrollableAxes(.horizontal)
                .chartXScale(domain: xAxisDomain)
                .chartXVisibleDomain(length: xVisibleDomainLength)
                .chartScrollPosition(x: $scrollPosition)
                .chartYScale(domain: 0.0...(max(10.0, visibleMaxY)))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(Int(v).formattedCompact)
                                    .font(.caption2)
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    if timeRange == .today {
                        AxisMarks { value in
                            AxisValueLabel(DashboardView.formatTime(value.as(Date.self)))
                            AxisGridLine()
                        }
                    } else {
                        AxisMarks(values: .stride(by: .day, count: 1)) { value in
                            AxisValueLabel(format: .dateTime.month().day())
                            AxisGridLine()
                        }
                    }
                }
                .chartLegend(position: .top, alignment: .trailing)
                .frame(height: 290)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .cardStyle()
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stats.modelTokensByDay)
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

                    Spacer(minLength: 0)

                    // Spotlight Details Box (Shows details of selected provider, or the top provider by default)
                    let activeProvider = selectedProvider ?? data.first?.provider
                    if let activeProvider, let activeData = data.first(where: { $0.provider == activeProvider }) {
                        spotlightDetailsBox(item: activeData)
                    }
                }
            }
        }
        .frame(minWidth: 320, maxHeight: .infinity)
        .cardStyle()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedProvider)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: stats.providerStats)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewMode)
    }

    private func donutChartView(data: [ProviderDisplayData]) -> some View {
        let safeData = data.filter { $0.displayValue > 0 }
        
        // Compute cumulative slices for trim
        var slices: [(provider: LLMProvider, start: CGFloat, end: CGFloat)] = []
        var current: CGFloat = 0.0
        let total = safeData.reduce(0.0) { $0 + $1.displayValue }
        
        if total > 0 {
            for item in safeData {
                let pct = CGFloat(item.displayValue / total)
                let start = current
                let end = current + pct
                slices.append((provider: item.provider, start: start, end: end))
                current = end
            }
        }
        
        return Group {
            if safeData.isEmpty {
                emptyChartPlaceholder("暂无数据")
            } else {
                ZStack {
                    // Base background circle
                    Circle()
                        .inset(by: 7)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 14)
                        .frame(width: 80, height: 80)
                    
                    // Slices
                    ForEach(0..<slices.count, id: \.self) { idx in
                        let slice = slices[idx]
                        let isSelected = selectedProvider == nil || selectedProvider == slice.provider
                        Circle()
                            .inset(by: 7)
                            .trim(from: slice.start, to: slice.end)
                            .stroke(
                                slice.provider.brandColor.gradient,
                                style: StrokeStyle(lineWidth: 14, lineCap: .butt)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .opacity(isSelected ? 1.0 : 0.25)
                            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedProvider)
                    }
                }
            }
        }
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
                        ForEach(Array(modelData.prefix(8).enumerated()), id: \.element.id) { index, item in
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
        .frame(maxHeight: .infinity)
        .cardStyle()
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: stats.callsByModel)
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
                    ForEach(stats.recentLogs.prefix(8)) { log in
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
            
            Spacer(minLength: 0)
        }
        .frame(minWidth: 320, maxHeight: .infinity)
        .cardStyle()
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: stats.recentLogs)
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

    static func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
