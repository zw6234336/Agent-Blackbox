import SwiftUI
import AppKit
import Charts

struct TokenFlowPoint: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let tokenCount: Int
    let cost: Double
    let client: String
}

enum ChartMetric: String, CaseIterable, Identifiable {
    case tokens = "Token 吞吐"
    case cost = "资费消耗"
    var id: String { rawValue }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case payload = "传输载荷"
    case loop = "死循环分析"
    case sandbox = "沙盒测试"
    var id: String { rawValue }
}

struct ProxyDashboardView: View {
    @EnvironmentObject var proxyServer: ProxyServerService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var clientInterception: ClientInterceptionService
    @EnvironmentObject var database: DatabaseService
    
    @State private var selectedRequest: ProxyRequestLog? = nil
    @State private var isCopying = false
    @State private var tokenFlowPoints: [TokenFlowPoint] = []
    @State private var currentRate: Int = 0
    @State private var peakRate: Int = 0
    @State private var lastProcessedTime: Date = Date()
    @State private var todayTokens: Int = 0
    @State private var todayCost: Double = 0.0
    
    // New UI State Properties
    @State private var chartMetric: ChartMetric = .tokens
    @State private var isChartFrozen = false
    @State private var isShowingGuide = false
    @State private var searchText = ""
    @State private var selectedClientFilter: String = "All"
    @State private var inspectorTab: InspectorTab = .payload
    
    // Sandbox State
    @State private var replayingRequest = false
    @State private var replayResult: String? = nil
    
    var filteredRequests: [ProxyRequestLog] {
        proxyServer.liveRequests.filter { req in
            let matchesSearch = searchText.isEmpty || 
                (req.model ?? "").lowercased().contains(searchText.lowercased()) ||
                (req.prompt ?? "").lowercased().contains(searchText.lowercased()) ||
                (req.response ?? "").lowercased().contains(searchText.lowercased()) ||
                req.path.lowercased().contains(searchText.lowercased())
            
            let matchesClient = selectedClientFilter == "All" || 
                req.client.lowercased() == selectedClientFilter.lowercased()
            
            return matchesSearch && matchesClient
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Column: Main Dashboard
            VStack(spacing: 16) {
                headerSection
                
                // Network Wave pulse
                PulseWaveView(isActive: proxyServer.liveRequests.contains(where: \.isPending))
                    .frame(height: 24)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(6)
                    .padding(.horizontal, 4)
                
                metricsAndInterceptionRow
                tokenRealTimeChartSection
                liveRequestsList
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Details Inspector
            if let request = selectedRequest {
                detailInspectorPanel(for: request)
                    .frame(width: 420)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(Color.dashboardBackground)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedRequest)
        .task {
            initializeChartData()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                appendNewChartPoint()
            }
        }
        .onChange(of: proxyServer.liveRequests) { oldValue, newValue in
            if newValue.isEmpty {
                tokenFlowPoints.removeAll()
                currentRate = 0
                peakRate = 0
                todayTokens = 0
                todayCost = 0.0
                lastProcessedTime = Date()
                initializeChartData()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(proxyServer.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(proxyServer.isRunning ? Color.green.opacity(0.4) : Color.gray.opacity(0.3), lineWidth: 3)
                            .scaleEffect(proxyServer.isRunning ? 1.4 : 1.0)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("本地网关监控")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        
                        let activeClientCount = clientInterception.activeStates.values.filter { $0 }.count
                        if activeClientCount > 0 {
                            Text("\(activeClientCount) 客户端托管中")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .foregroundStyle(Color.green)
                                .cornerRadius(8)
                        }
                    }
                    Text(proxyServer.isRunning ? "监听端口: \(proxyServer.port) | 拦截出网模型流量" : "网关代理未启动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Integration Guide Button
            Button(action: { isShowingGuide.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                    Text("接入指引")
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingGuide, arrowEdge: .bottom) {
                IntegrationGuideView(port: proxyServer.port)
            }
            
            // Local Base URL copy field
            let baseUrl = "http://127.0.0.1:\(proxyServer.port)/v1"
            Button(action: {
                copyToClipboard(baseUrl)
                withAnimation {
                    isCopying = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { isCopying = false }
                }
            }) {
                HStack(spacing: 6) {
                    Text(baseUrl)
                        .font(.system(.caption, design: .monospaced))
                    Image(systemName: isCopying ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(isCopying ? .green : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("复制本地 API 基础地址")
            
            Button(action: {
                if proxyServer.isRunning {
                    proxyServer.stop()
                } else {
                    proxyServer.start()
                }
            }) {
                Text(proxyServer.isRunning ? "停止网关" : "启动网关")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(proxyServer.isRunning ? Color.red.gradient : Color.blue.gradient)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Real-time Token Chart
    
    private var tokenRealTimeChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader
            chartView
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    private var chartHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("实时网关吞吐")
                        .font(.headline)
                    
                    Text(isChartFrozen ? "⏸ 视图静止 (保留上次活动波动)" : "🔴 实时监控中")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(isChartFrozen ? Color.orange.opacity(0.12) : Color.red.opacity(0.12))
                        .foregroundStyle(isChartFrozen ? Color.orange : Color.red)
                        .cornerRadius(4)
                }
                Text("数据平滑缓冲刷新。如果 30 秒无请求，图表将自动暂停滚动以保留历史轨迹。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Picker("展示指标", selection: $chartMetric) {
                ForEach(ChartMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            
            Spacer().frame(width: 16)
            
            // Indicators
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("当前速率")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(currentRate.formattedCompact + " T/3s")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(currentRate > 0 ? Color.blue : Color.secondary)
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("历史峰值")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(peakRate.formattedCompact + " T/3s")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.purple)
                }
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var chartView: some View {
        Group {
            if tokenFlowPoints.isEmpty {
                VStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在载入网关性能曲线...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(Color.primary.opacity(0.01))
                .cornerRadius(10)
            } else {
                let valueKey = chartMetric == .tokens ? "Tokens" : "费用"
                Chart(tokenFlowPoints) { point in
                    let value: Double = chartMetric == .tokens ? Double(point.tokenCount) : point.cost
                    
                    AreaMark(
                        x: .value("时间", point.time),
                        y: .value(valueKey, value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            Gradient(colors: [clientColor(point.client).opacity(0.5), clientColor(point.client).opacity(0.05)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                    
                    LineMark(
                        x: .value("时间", point.time),
                        y: .value(valueKey, value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(clientColor(point.client))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .frame(height: 130)
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            chartYValueLabel(for: val)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 60)) { val in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let dateValue = val.as(Date.self) {
                                Text(formatRelativeTime(dateValue))
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartYScale(range: .plotDimension(padding: 5))
            }
        }
    }
    
    @ViewBuilder
    private func chartYValueLabel(for value: AxisValue) -> some View {
        if let doubleValue = value.as(Double.self) {
            if chartMetric == .tokens {
                Text(Int(doubleValue).formattedCompact)
                    .font(.system(size: 8))
            } else {
                Text(String(format: "$%.4f", doubleValue))
                    .font(.system(size: 8))
            }
        }
    }
    
    @MainActor
    private func updateTodayUsage() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let todayUsage = database.aggregateUsage(provider: nil, since: startOfDay)
        self.todayTokens = todayUsage.totalTokens
        self.todayCost = todayUsage.totalCost
    }
    
    @MainActor
    private func initializeChartData() {
        let now = Date()
        let binSize: TimeInterval = 3.0
        let binCount = 100 // 5 minutes of history
        var points: [TokenFlowPoint] = []
        let clients = ["pi", "cline", "claude-code", "cursor", "copilot", "other"]
        
        for i in (0..<binCount).reversed() {
            let startTime = now.addingTimeInterval(-Double(i) * binSize)
            let endTime = startTime.addingTimeInterval(binSize)
            
            for client in clients {
                let binRequests = proxyServer.liveRequests.filter { req in
                    guard !req.isPending else { return false }
                    let reqClient = req.client.lowercased()
                    let match: Bool
                    if client == "other" {
                        match = !["pi", "cline", "claude-code", "cursor", "copilot"].contains(reqClient)
                    } else {
                        match = reqClient == client
                    }
                    return match && req.timestamp >= startTime && req.timestamp < endTime
                }
                
                let tokensInBin = binRequests.reduce(0) { sum, req in
                    sum + (req.promptTokens ?? 0) + (req.completionTokens ?? 0)
                }
                let costInBin = binRequests.reduce(0.0) { sum, req in
                    sum + (req.estimatedCost ?? 0.0)
                }
                
                points.append(TokenFlowPoint(time: startTime, tokenCount: tokensInBin, cost: costInBin, client: client))
            }
        }
        
        self.tokenFlowPoints = points
        self.lastProcessedTime = now
        
        let lastBinTime = points.last?.time
        let lastBinTotal = points.filter { $0.time == lastBinTime }.map(\.tokenCount).reduce(0, +)
        self.currentRate = lastBinTotal
        
        var maxTotal = 0
        let groupedByTime = Dictionary(grouping: points, by: { $0.time })
        for (_, pts) in groupedByTime {
            let total = pts.map(\.tokenCount).reduce(0, +)
            if total > maxTotal {
                maxTotal = total
            }
        }
        self.peakRate = maxTotal
        
        updateTodayUsage()
    }
    
    @MainActor
    private func appendNewChartPoint() {
        let currentTime = Date()
        
        // Session-based Chart Freezing: Check if there has been no new request in the last 30 seconds
        let lastReqTime = proxyServer.liveRequests.first?.timestamp ?? Date.distantPast
        let timeSinceLastReq = currentTime.timeIntervalSince(lastReqTime)
        
        if timeSinceLastReq > 30.0 && !proxyServer.liveRequests.isEmpty {
            self.isChartFrozen = true
            updateTodayUsage()
            return
        }
        
        self.isChartFrozen = false
        let clients = ["pi", "cline", "claude-code", "cursor", "copilot", "other"]
        var newPoints: [TokenFlowPoint] = []
        
        for client in clients {
            let binRequests = proxyServer.liveRequests.filter { req in
                guard !req.isPending else { return false }
                let reqClient = req.client.lowercased()
                let match: Bool
                if client == "other" {
                    match = !["pi", "cline", "claude-code", "cursor", "copilot"].contains(reqClient)
                } else {
                    match = reqClient == client
                }
                return match && req.timestamp >= lastProcessedTime && req.timestamp < currentTime
            }
            
            let tokensInBin = binRequests.reduce(0) { sum, req in
                sum + (req.promptTokens ?? 0) + (req.completionTokens ?? 0)
            }
            let costInBin = binRequests.reduce(0.0) { sum, req in
                sum + (req.estimatedCost ?? 0.0)
            }
            
            newPoints.append(TokenFlowPoint(time: currentTime, tokenCount: tokensInBin, cost: costInBin, client: client))
        }
        
        tokenFlowPoints.append(contentsOf: newPoints)
        
        let maxPoints = 100 * clients.count
        if tokenFlowPoints.count > maxPoints {
            tokenFlowPoints.removeFirst(clients.count)
        }
        
        let totalInBin = newPoints.map(\.tokenCount).reduce(0, +)
        self.lastProcessedTime = currentTime
        self.currentRate = totalInBin
        self.peakRate = max(peakRate, totalInBin)
        
        updateTodayUsage()
    }
    
    // MARK: - Metrics & Interception
    
    private var metricsAndInterceptionRow: some View {
        HStack(spacing: 16) {
            // Left Content: Status & Budget
            HStack(spacing: 16) {
                gatewayStatusCard
                gatewayBudgetCard
            }
            .frame(maxWidth: .infinity)
            
            // Interception Config Toggles (Right)
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷接管控制")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("开启后自动修改对应插件的接口配置")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    VStack(spacing: 6) {
                        interceptionToggle(for: .vscodeCline, binding: $configService.config.enableVSCodeClineInterception)
                        interceptionToggle(for: .vscodeRooCline, binding: $configService.config.enableVSCodeRooClineInterception)
                        interceptionToggle(for: .cursorCline, binding: $configService.config.enableCursorClineInterception)
                        interceptionToggle(for: .cursorRooCline, binding: $configService.config.enableCursorRooClineInterception)
                        interceptionToggle(for: .claudeCode, binding: $configService.config.enableClaudeCodeInterception)
                        interceptionToggle(for: .pi, binding: $configService.config.enablePiInterception)
                    }
                }
            }
            .padding(12)
            .frame(width: 260, height: 160)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
    
    private var gatewayStatusCard: some View {
        let runaway = runawayClient
        let activeCount = proxyServer.liveRequests.filter(\.isPending).count
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if runaway != nil {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: .red, radius: 4, x: 0, y: 0)
                } else if activeCount > 0 {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .shadow(color: .blue, radius: 4, x: 0, y: 0)
                } else {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 4, x: 0, y: 0)
                }
                
                Text("网关安全诊断")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let client = runaway {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("🚨 死循环跑飞警报")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                        Spacer()
                        
                        Button(action: {
                            disableInterception(for: client)
                        }) {
                            Text("切断托管")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.12))
                                .foregroundStyle(.red)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("检测到 \(clientDisplayName(client)) 发生高频请求（15秒内 >5次），可能陷入死循环！点击“切断托管”可紧急恢复客户端默认配置。")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else if activeCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚡ AI 并发传输中")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("网关当前正在流式传输 \(activeCount) 个并发连接，实时拦截和解析流量。")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🟢 系统就绪 / 监听中")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                    Text("网关状态良好。当你的 AI 代理发送数据时，它的连接指标和扣费趋势将实时显示在此。")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: 160)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(runaway != nil ? Color.red.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var gatewayBudgetCard: some View {
        let budgetLimit = 5.0
        
        // Dynamic projection based on active requests
        let recentActiveRequests = proxyServer.liveRequests.filter { $0.timestamp >= Date().addingTimeInterval(-300) }
        let fiveMinCost = recentActiveRequests.reduce(0.0) { $0 + ($1.estimatedCost ?? 0.0) }
        let projectedDailyCost = todayCost + (fiveMinCost * 12 * 8) // scale up to 8 hours of usage
        
        // Sum up local Ollama calls (which are free, but show as saved budget)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let localRequestsCount = database.aggregateUsage(provider: .ollama, since: startOfDay).requestCount
        let savedCost = Double(localRequestsCount) * 0.015 // estimate $0.015 saved per local call
        
        return HStack(spacing: 12) {
            CircularBudgetGauge(cost: todayCost, limit: budgetLimit)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("出网资费预算")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                
                Text("今日用量: \(todayTokens.formattedCompact) Tokens")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                
                if savedCost > 0 {
                    Text("本地节省: $\(String(format: "%.2f", savedCost)) (Ollama)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                
                if fiveMinCost > 0 {
                    Text("预计日消费: $\(String(format: "%.2f", projectedDailyCost))")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else {
                    Text("消费速率: 暂无")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: 160)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    private func interceptionToggle(for client: InterceptClient, binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(client.displayName)
                    .font(.system(size: 11, weight: .medium))
                
                if let error = clientInterception.errors[client] {
                    Text("配置异常")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .help(error)
                } else if clientInterception.activeStates[client] == true {
                    Text("接管运行中")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                } else {
                    let exists = FileManager.default.fileExists(atPath: client.settingsURL.path)
                    Text(exists ? "已检测就绪" : "未安装插件")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 40)
                .disabled(!FileManager.default.fileExists(atPath: client.settingsURL.path))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(6)
    }
    
    private func disableInterception(for clientName: String) {
        switch clientName.lowercased() {
        case "pi":
            configService.config.enablePiInterception = false
        case "cline":
            configService.config.enableVSCodeClineInterception = false
            configService.config.enableCursorClineInterception = false
        case "claude-code":
            configService.config.enableClaudeCodeInterception = false
        case "cursor":
            configService.config.enableCursorClineInterception = false
            configService.config.enableCursorRooClineInterception = false
        default:
            break
        }
        clientInterception.syncWithConfig()
    }
    
    // MARK: - Live Requests List
    
    private var liveRequestsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Filters and Search Bar
            HStack(spacing: 12) {
                Text("实时连接流水")
                    .font(.headline)
                
                Spacer()
                
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("搜索模型、路径、日志内容...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .frame(width: 220)
                
                Button("清空流水") {
                    proxyServer.clearLiveRequests()
                    selectedRequest = nil
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            // Client filter chips
            HStack(spacing: 8) {
                filterChip(label: "全部", val: "All")
                filterChip(label: "Pi Agent", val: "pi")
                filterChip(label: "Cline", val: "cline")
                filterChip(label: "Claude Code", val: "claude-code")
                filterChip(label: "Cursor", val: "cursor")
                filterChip(label: "Copilot", val: "copilot")
            }
            
            if filteredRequests.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(proxyServer.liveRequests.isEmpty ? "暂无代理调用流水" : "无匹配筛选条件的流水")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("请在 AI 客户端中将 Base URL 配置为本机网关后进行对话。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cardStyle()
            } else {
                List(selection: $selectedRequest) {
                    ForEach(filteredRequests) { request in
                        liveRequestRow(for: request)
                            .tag(request)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func filterChip(label: String, val: String) -> some View {
        Button(action: { selectedClientFilter = val }) {
            Text(label)
                .font(.system(size: 9, weight: selectedClientFilter == val ? .bold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectedClientFilter == val ? Color.blue.opacity(0.12) : Color.primary.opacity(0.04))
                .foregroundStyle(selectedClientFilter == val ? Color.blue : .secondary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func liveRequestRow(for request: ProxyRequestLog) -> some View {
        let isSelected = selectedRequest?.id == request.id
        let provider = detectProvider(model: request.model ?? "", path: request.path)
        let clColor = clientColor(request.client)
        
        return HStack(spacing: 12) {
            // Colored Left Accent Strip
            Rectangle()
                .fill(clColor)
                .frame(width: 4)
                .cornerRadius(2)
            
            // Status Indicator with animation
            if request.isPending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 28, height: 28)
            } else {
                let code = request.statusCode ?? 200
                Text("\(code)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(code == 200 ? Color.green : Color.red)
                    .frame(width: 28, height: 28)
                    .background(code == 200 ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                    .clipShape(Circle())
            }
            
            // Path, Client and Live text ticker
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(request.method)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)
                    
                    Text(request.path)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    
                    Text(clientDisplayName(request.client))
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(clColor.opacity(0.12))
                        .foregroundStyle(clColor)
                        .cornerRadius(3)
                }
                
                // Live Content Preview Ticker
                HStack {
                    if request.isPending {
                        Text(request.response ?? request.prompt ?? "等待上游 API 响应...")
                            .font(.system(size: 9, design: .rounded))
                            .italic()
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    } else if let prompt = request.prompt, !prompt.isEmpty {
                        Text(prompt.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("无可用提示词内容")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Model Badge
            if let model = request.model, !model.isEmpty {
                Text(model)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(provider.brandColor.opacity(0.08))
                    .foregroundStyle(provider.brandColor)
                    .cornerRadius(4)
                    .lineLimit(1)
            }
            
            // Token break-down indicator bar
            if let pt = request.promptTokens, let ct = request.completionTokens {
                let total = pt + ct
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("\(total)")
                            .font(.system(size: 9, weight: .bold))
                        Text("T")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Small ratio bar
                    let ratio = CGFloat(pt) / CGFloat(max(total, 1))
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Color.blue.frame(width: geo.size.width * ratio)
                            Color.purple.frame(width: geo.size.width * (1.0 - ratio))
                        }
                    }
                    .frame(width: 45, height: 2.5)
                    .cornerRadius(1.5)
                }
                .frame(width: 50, alignment: .trailing)
            }
            
            // Cost & Saved Badge
            VStack(alignment: .trailing, spacing: 1) {
                if provider == .ollama {
                    Text("本地免费")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(3)
                } else if let cost = request.estimatedCost {
                    Text(String(format: "$%.4f", cost))
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(cost > 0.05 ? .orange : .primary)
                } else {
                    Text("--")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                
                if let duration = request.duration {
                    Text(duration.formattedDuration)
                        .font(.system(size: 7).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.primary.opacity(0.06) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedRequest = request
                self.replayResult = nil
                self.replayingRequest = false
            }
        }
    }
    
    // MARK: - Detail Inspector Panel
    
    private func detailInspectorPanel(for request: ProxyRequestLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("网关会话解析 (Inspector)")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button(action: {
                    withAnimation { selectedRequest = nil }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Picker("栏目", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            
            Divider()
            
            switch inspectorTab {
            case .payload:
                payloadView(for: request)
            case .loop:
                loopAnalysisView(for: request)
            case .sandbox:
                sandboxTestView(for: request)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
    
    private func payloadView(for request: ProxyRequestLog) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Info rows
                VStack(spacing: 6) {
                    detailMetaRow(label: "当前状态", content: request.isPending ? "Pending (传输中)" : (request.statusCode.map { "\($0) OK" } ?? "处理完毕"))
                        .foregroundStyle(request.isPending ? .blue : (request.statusCode == 200 ? .green : .red))
                        .fontWeight(.bold)
                    
                    detailMetaRow(label: "出网客户端", content: clientDisplayName(request.client))
                    detailMetaRow(label: "请求模型", content: request.model ?? "未识别")
                    detailMetaRow(label: "上游路径", content: request.path)
                    
                    if let dur = request.duration {
                        detailMetaRow(label: "总耗时", content: dur.formattedDuration)
                    }
                    if let pt = request.promptTokens, let ct = request.completionTokens {
                        detailMetaRow(label: "总 Token", content: "\(pt + ct) (Input: \(pt) / Output: \(ct))")
                    }
                    if let cost = request.estimatedCost {
                        detailMetaRow(label: "预估资费", content: String(format: "$%.4f", cost))
                            .foregroundStyle(.green)
                            .fontWeight(.bold)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
                
                // Prompt Content
                if let prompt = request.prompt, !prompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("提示词内容 (Decoded Prompt)")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Button(action: { copyToClipboard(prompt) }) {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Text(prompt)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }
                
                // Response Content
                if let response = request.response, !response.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("回答内容 (Decoded Response)")
                                .font(.system(size: 11, weight: .bold))
                            Spacer()
                            Button(action: { copyToClipboard(response) }) {
                                Label("复制", systemImage: "doc.on.doc")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Text(response)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }
                
                // Error Details
                if let error = request.errorMessage, !error.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("失败原因")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.red)
                        
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.05))
                            .foregroundStyle(.red)
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
    
    private func loopAnalysisView(for request: ProxyRequestLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("死循环检测与相似度比对")
                .font(.system(size: 12, weight: .bold))
            
            // Find prior request from same client
            let priorRequests = proxyServer.liveRequests.filter { 
                $0.client == request.client && $0.timestamp < request.timestamp 
            }
            
            if let prior = priorRequests.first {
                let similarity = computeSimilarity(request.prompt ?? "", prior.prompt ?? "")
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("上一条请求相似度")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f%%", similarity))
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(similarity > 85 ? Color.red : Color.green)
                    }
                    
                    if similarity > 85 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("死循环警告：相似度极高。AI 代理可能正处于异常编译器调试循环中，建议暂停接管该客户端。")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(6)
                    } else {
                        Text("健康状态：相似度在安全范围内。")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }
                    
                    Divider()
                    
                    Text("提示词差异比对 (Prompt Diff)")
                        .font(.system(size: 11, weight: .bold))
                    
                    SimpleDiffView(text1: prior.prompt ?? "", text2: request.prompt ?? "")
                        .frame(height: 280)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("该客户端尚无更早的连接流水，无法进行比对。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func sandboxTestView(for request: ProxyRequestLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地 API 重放调试")
                .font(.system(size: 12, weight: .bold))
            Text("在沙盒中一键重新发起该请求，用于测试网关转发可用性和上游服务器的响应延迟。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            
            Button(action: {
                replayRequest(request)
            }) {
                HStack {
                    if replayingRequest {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(replayingRequest ? "正在重试中..." : "重新发送此 API 请求")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(replayingRequest)
            
            Divider()
            
            Text("重放调试结果")
                .font(.system(size: 11, weight: .bold))
            
            if let result = replayResult {
                ScrollView {
                    Text(result)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "play.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("点击上方按钮发起重放测试")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func detailMetaRow(label: String, content: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }
    
    // MARK: - Utilities
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let diff = lastProcessedTime.timeIntervalSince(date)
        if diff < 6 { return "当前" }
        let mins = Int(diff / 60)
        if mins > 0 {
            return "-\(mins)分"
        } else {
            let secs = Int(diff)
            return "-\(secs)秒"
        }
    }
    
    private func detectProvider(model: String, path: String) -> LLMProvider {
        let isAnthropic = path.contains("messages")
        let modelLower = model.lowercased()
        
        if isAnthropic || modelLower.contains("claude") || modelLower.contains("anthropic") {
            return .anthropic
        } else if modelLower.contains("gpt") || modelLower.contains("o1") || modelLower.contains("o3") {
            return .openai
        } else if modelLower.contains("gemini") {
            return .google
        } else if modelLower.contains("deepseek") {
            return .deepseek
        } else if modelLower.contains("qwen") {
            return .qwen
        } else if modelLower.contains("ollama") {
            return .ollama
        } else if modelLower.contains("kimi") || modelLower.contains("moonshot") {
            return .kimi
        } else if modelLower.contains("glm") || modelLower.contains("zhipu") {
            return .zhipu
        } else {
            return .custom
        }
    }
    
    private var runawayClient: String? {
        let now = Date()
        let recentRequests = proxyServer.liveRequests.filter { $0.timestamp >= now.addingTimeInterval(-15) }
        
        // Group by client
        let groups = Dictionary(grouping: recentRequests, by: { $0.client })
        for (client, reqs) in groups {
            if reqs.count >= 5 {
                return client
            }
        }
        return nil
    }
    
    private func clientDisplayName(_ client: String) -> String {
        switch client.lowercased() {
        case "pi": return "Pi Agent"
        case "cline": return "Cline"
        case "claude-code": return "Claude Code"
        case "cursor": return "Cursor"
        case "copilot": return "GitHub Copilot"
        case "warp": return "Warp"
        case "python": return "Python SDK"
        case "node": return "NodeJS SDK"
        case "curl": return "cURL"
        default: return "其他客户端"
        }
    }
    
    private func clientColor(_ client: String) -> Color {
        switch client.lowercased() {
        case "pi": return Color.pink
        case "cline": return Color.orange
        case "claude-code": return Color.green
        case "cursor": return Color.purple
        case "copilot": return Color.blue
        case "warp": return Color.cyan
        default: return Color.gray
        }
    }
    
    private func computeSimilarity(_ s1: String, _ s2: String) -> Double {
        let words1 = Set(s1.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let words2 = Set(s2.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        return Double(intersection.count) / Double(union.count) * 100.0
    }
    
    private func replayRequest(_ request: ProxyRequestLog) {
        guard !replayingRequest else { return }
        replayingRequest = true
        replayResult = "正在发起沙盒重放测试..."
        
        Task {
            do {
                let urlString = "http://127.0.0.1:\(proxyServer.port)\(request.path)"
                guard let url = URL(string: urlString) else {
                    throw NSError(domain: "InvalidURL", code: 0, userInfo: [NSLocalizedDescriptionKey: "本地服务地址无效"])
                }
                
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = request.method
                
                // Copy standard headers
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("agent-blackbox-sandbox", forHTTPHeaderField: "x-client-identifier")
                
                if let prompt = request.prompt, let model = request.model {
                    let requestBody: [String: Any] = [
                        "model": model,
                        "messages": [
                            ["role": "user", "content": prompt]
                        ],
                        "stream": false
                    ]
                    urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
                }
                
                let startTime = Date()
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                let duration = Date().timeIntervalSince(startTime)
                let httpResponse = response as? HTTPURLResponse
                let status = httpResponse?.statusCode ?? 0
                
                let responseString = String(data: data, encoding: .utf8) ?? "解析响应内容失败"
                
                await MainActor.run {
                    self.replayResult = "状态码: \(status) OK\n耗时: \(String(format: "%.2f秒", duration))\n\n响应载荷:\n\(responseString)"
                    self.replayingRequest = false
                }
            } catch {
                await MainActor.run {
                    self.replayResult = "发送失败: \(error.localizedDescription)"
                    self.replayingRequest = false
                }
            }
        }
    }
}

// MARK: - Canvas-based Pulse Wave
struct PulseWaveView: View {
    let isActive: Bool
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2.0
                
                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))
                
                let time = timeline.date.timeIntervalSinceReferenceDate
                let freq: CGFloat = isActive ? 0.06 : 0.015
                let amp: CGFloat = isActive ? 8.0 : 1.2
                let speed: CGFloat = isActive ? 10.0 : 1.5
                
                for x in stride(from: 0, to: width, by: 2) {
                    let relativeX = x / width
                    let fade = sin(relativeX * .pi) // Fade out at boundaries
                    let y = midY + sin(x * freq - CGFloat(time) * speed) * amp * fade
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: isActive ? [.blue, .purple, .pink] : [.secondary.opacity(0.3), .secondary.opacity(0.1)]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: width, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: isActive ? 1.5 : 0.8, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Circular Cost Progress Gauge
struct CircularBudgetGauge: View {
    let cost: Double
    let limit: Double
    
    var percentage: Double {
        guard limit > 0 else { return 0 }
        return min(cost / limit, 1.0)
    }
    
    var barColor: Color {
        if percentage > 0.9 { return .red }
        if percentage > 0.6 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 8)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(percentage))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [barColor.opacity(0.7), barColor]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(360 * percentage - 90)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: percentage)
                
                VStack(spacing: 2) {
                    Text(String(format: "$%.2f", cost))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("/ $\(String(format: "%.0f", limit))")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            
            Text(String(format: "已用 %.1f%%", percentage * 100))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(barColor)
        }
    }
}

// MARK: - Local Integration Guide Popover View
struct IntegrationGuideView: View {
    let port: Int
    @State private var copiedItem = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💻 本地网关集成配置指引")
                .font(.headline)
            
            Text("开启网关代理后，通过将 Base URL 重定向至本机，网关即可截获所有出网流量进行统计。")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                guideRow(
                    title: "1. 终端命令行代理 (Python / cURL / Go)",
                    cmd: "export HTTPS_PROXY=http://127.0.0.1:\(port)\nexport HTTP_PROXY=http://127.0.0.1:\(port)"
                )
                
                guideRow(
                    title: "2. Node.js 绕过 TLS 证书校验",
                    cmd: "export NODE_TLS_REJECT_UNAUTHORIZED=0"
                )
                
                guideRow(
                    title: "3. OpenAI Python SDK 自定义 Base URL",
                    cmd: "openai.base_url = \"http://127.0.0.1:\(port)/v1\""
                )
            }
        }
        .padding(16)
        .frame(width: 380)
    }
    
    private func guideRow(title: String, cmd: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
            
            HStack(alignment: .center) {
                Text(cmd)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(4)
                
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(cmd, forType: .string)
                    withAnimation {
                        copiedItem = title
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedItem = ""
                    }
                }) {
                    Image(systemName: copiedItem == title ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copiedItem == title ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Line-by-line Diff Visualizer
struct SimpleDiffView: View {
    let text1: String
    let text2: String
    
    enum DiffType {
        case unchanged, added, deleted
    }
    
    var diffLines: [(type: DiffType, text: String)] {
        let lines1 = text1.components(separatedBy: .newlines)
        let lines2 = text2.components(separatedBy: .newlines)
        var result: [(type: DiffType, text: String)] = []
        
        let maxLines = max(lines1.count, lines2.count)
        for i in 0..<maxLines {
            if i < lines1.count && i < lines2.count {
                if lines1[i] == lines2[i] {
                    result.append((.unchanged, lines1[i]))
                } else {
                    result.append((.deleted, lines1[i]))
                    result.append((.added, lines2[i]))
                }
            } else if i < lines1.count {
                result.append((.deleted, lines1[i]))
            } else if i < lines2.count {
                result.append((.added, lines2[i]))
            }
        }
        return result
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<diffLines.count, id: \.self) { index in
                    let line = diffLines[index]
                    HStack(alignment: .top) {
                        Text(line.type == .added ? "+" : (line.type == .deleted ? "-" : " "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.type == .added ? .green : (line.type == .deleted ? .red : .secondary))
                            .frame(width: 15, alignment: .leading)
                        
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.type == .added ? .green : (line.type == .deleted ? .red : .primary))
                    }
                    .padding(.horizontal, 4)
                    .background(line.type == .added ? Color.green.opacity(0.08) : (line.type == .deleted ? Color.red.opacity(0.08) : Color.clear))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
    }
}
