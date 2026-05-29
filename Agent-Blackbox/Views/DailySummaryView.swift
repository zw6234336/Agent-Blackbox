import SwiftUI
import UniformTypeIdentifiers

struct DailySummaryView: View {
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var service: DailySummaryService
    
    // Configurations stored in UserDefaults via AppStorage (grouped by provider)
    @AppStorage("summary_provider") private var provider = "ollama"
    
    @AppStorage("summary_model_ollama") private var modelOllama = "llama3"
    @AppStorage("summary_baseurl_ollama") private var baseUrlOllama = "http://127.0.0.1:11434"
    
    @AppStorage("summary_model_lmstudio") private var modelLMStudio = "meta-llama-3-8b-instruct"
    @AppStorage("summary_baseurl_lmstudio") private var baseUrlLMStudio = "http://127.0.0.1:1234"
    
    @AppStorage("summary_model_vllm") private var modelVLLM = "Qwen/Qwen2.5-7B-Instruct"
    @AppStorage("summary_baseurl_vllm") private var baseUrlVLLM = "http://127.0.0.1:8000"
    
    @AppStorage("summary_model_deepseek") private var modelDeepSeek = "deepseek-chat"
    @AppStorage("summary_baseurl_deepseek") private var baseUrlDeepSeek = "https://api.deepseek.com"
    @AppStorage("summary_apikey_deepseek") private var apiKeyDeepSeek = ""
    
    @AppStorage("summary_model_openai") private var modelOpenAI = "gpt-4o-mini"
    @AppStorage("summary_baseurl_openai") private var baseUrlOpenAI = "https://api.openai.com"
    @AppStorage("summary_apikey_openai") private var apiKeyOpenAI = ""
    
    @AppStorage("summary_model_anthropic") private var modelAnthropic = "claude-3-5-sonnet-20241022"
    @AppStorage("summary_baseurl_anthropic") private var baseUrlAnthropic = "https://api.anthropic.com"
    @AppStorage("summary_apikey_anthropic") private var apiKeyAnthropic = ""
    
    @AppStorage("summary_model_custom") private var modelCustom = ""
    @AppStorage("summary_baseurl_custom") private var baseUrlCustom = ""
    @AppStorage("summary_apikey_custom") private var apiKeyCustom = ""
    
    private var activeBaseUrlBinding: Binding<String> {
        Binding(
            get: {
                switch provider {
                case "ollama": return baseUrlOllama
                case "lmstudio": return baseUrlLMStudio
                case "vllm": return baseUrlVLLM
                case "deepseek": return baseUrlDeepSeek
                case "openai": return baseUrlOpenAI
                case "anthropic": return baseUrlAnthropic
                default: return baseUrlCustom
                }
            },
            set: { baseUrlSet($0) }
        )
    }
    
    private var activeModelBinding: Binding<String> {
        Binding(
            get: {
                switch provider {
                case "ollama": return modelOllama
                case "lmstudio": return modelLMStudio
                case "vllm": return modelVLLM
                case "deepseek": return modelDeepSeek
                case "openai": return modelOpenAI
                case "anthropic": return modelAnthropic
                default: return modelCustom
                }
            },
            set: { modelSet($0) }
        )
    }
    
    private var activeApiKeyBinding: Binding<String> {
        Binding(
            get: {
                switch provider {
                case "deepseek": return apiKeyDeepSeek
                case "openai": return apiKeyOpenAI
                case "anthropic": return apiKeyAnthropic
                default: return apiKeyCustom
                }
            },
            set: { apiKeySet($0) }
        )
    }
    
    private func baseUrlSet(_ val: String) {
        switch provider {
        case "ollama": baseUrlOllama = val
        case "lmstudio": baseUrlLMStudio = val
        case "vllm": baseUrlVLLM = val
        case "deepseek": baseUrlDeepSeek = val
        case "openai": baseUrlOpenAI = val
        case "anthropic": baseUrlAnthropic = val
        default: baseUrlCustom = val
        }
    }
    
    private func modelSet(_ val: String) {
        switch provider {
        case "ollama": modelOllama = val
        case "lmstudio": modelLMStudio = val
        case "vllm": modelVLLM = val
        case "deepseek": modelDeepSeek = val
        case "openai": modelOpenAI = val
        case "anthropic": modelAnthropic = val
        default: modelCustom = val
        }
    }
    
    private func apiKeySet(_ val: String) {
        switch provider {
        case "deepseek": apiKeyDeepSeek = val
        case "openai": apiKeyOpenAI = val
        case "anthropic": apiKeyAnthropic = val
        default: apiKeyCustom = val
        }
    }
    
    private var activeBaseUrl: String {
        switch provider {
        case "ollama": return baseUrlOllama
        case "lmstudio": return baseUrlLMStudio
        case "vllm": return baseUrlVLLM
        case "deepseek": return baseUrlDeepSeek
        case "openai": return baseUrlOpenAI
        case "anthropic": return baseUrlAnthropic
        default: return baseUrlCustom
        }
    }
    
    private var activeModel: String {
        switch provider {
        case "ollama": return modelOllama
        case "lmstudio": return modelLMStudio
        case "vllm": return modelVLLM
        case "deepseek": return modelDeepSeek
        case "openai": return modelOpenAI
        case "anthropic": return modelAnthropic
        default: return modelCustom
        }
    }
    
    private var activeApiKey: String {
        switch provider {
        case "deepseek": return apiKeyDeepSeek
        case "openai": return apiKeyOpenAI
        case "anthropic": return apiKeyAnthropic
        default: return apiKeyCustom
        }
    }
    
    // UI Local state
    enum Period: String, CaseIterable, Identifiable {
        case today = "today"
        case yesterday = "yesterday"
        case last3Days = "last3days"
        case last7Days = "last7days"
        case custom = "custom"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .today: return "今天"
            case .yesterday: return "昨天"
            case .last3Days: return "最近 3 天"
            case .last7Days: return "最近 7 天"
            case .custom: return "自定义范围"
            }
        }
    }
    
    @State private var selectedPeriod: Period = .today
    @State private var customStartDate = Date().addingTimeInterval(-86400 * 3)
    @State private var customEndDate = Date()
    @State private var isConfigExpanded = false
    @State private var currentPeriodLogs: [ParsedLog] = []
    @State private var isEditMode = false // Switch between Preview (Markdown) and Edit (Raw text)
    
    // Connectivity test state
    @State private var connectionTestMessage = ""
    @State private var isTestingConnection = false
    @State private var connectionTestSuccess: Bool? = nil
    
    private let providersList = [
        ("ollama", "Ollama (本地)"),
        ("lmstudio", "LM Studio (本地)"),
        ("vllm", "vLLM (本地)"),
        ("deepseek", "DeepSeek (云端)"),
        ("openai", "OpenAI (云端)"),
        ("anthropic", "Anthropic (云端)"),
        ("custom", "自定义 OpenAI 接口")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Title Bar
            headerBar
            
            Divider()
            
            NativeScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Period Control and Actions card
                    controlPanelCard
                    
                    // LLM Configuration card (collapsible)
                    configCard
                    
                    // Local Quick Stats dashboard for current selection
                    statsDashboardCard
                    
                    // Report content panel
                    reportContentCard
                    
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dashboardBackground)
        .onAppear {
            loadLogsForSelectedPeriod()
        }
        .onChange(of: selectedPeriod) {
            loadLogsForSelectedPeriod()
        }
        .onChange(of: customStartDate) {
            loadLogsForSelectedPeriod()
        }
        .onChange(of: customEndDate) {
            loadLogsForSelectedPeriod()
        }
    }
    
    // MARK: - Subviews
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.title2)
                        .foregroundStyle(Color.accentGradientStart)
                    Text("今日复盘")
                        .font(.title)
                        .fontWeight(.bold)
                }
                Text("分析本地日志，智能生成工作报告与成果概览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.cardBackground.opacity(0.4))
    }
    
    private var controlPanelCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                // Period Picker
                Text("时段选择:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("", selection: $selectedPeriod) {
                    ForEach(Period.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                
                Spacer()
                
                // Toggle config expansion
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isConfigExpanded.toggle()
                    }
                }) {
                    Label(isConfigExpanded ? "隐藏配置" : "配置模型", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
            
            // Custom Date range controls
            if selectedPeriod == .custom {
                HStack(spacing: 12) {
                    DatePicker("开始日期:", selection: $customStartDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    DatePicker("结束日期:", selection: $customEndDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    Spacer()
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .cardStyle()
    }
    
    private var configCard: some View {
        Group {
            if isConfigExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("LLM 模型配置", systemImage: "cpu.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentGradientStart)
                        
                        Spacer()
                        
                        Text("为了您的隐私，首推使用本地 Ollama 或 LM Studio 运行")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("供应商")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $provider) {
                                ForEach(providersList, id: \.0) { id, name in
                                    Text(name).tag(id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        GridRow {
                            Text("Base URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("例如 http://127.0.0.1:11434", text: activeBaseUrlBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        GridRow {
                            Text("模型名称")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("例如 llama3", text: activeModelBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        if provider != "ollama" && provider != "lmstudio" && provider != "vllm" {
                            GridRow {
                                Text("API Key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                SecureField("服务商 API Key", text: activeApiKeyBinding)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Spacer()
                        
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("正在测试连通性...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let success = connectionTestSuccess {
                            Text(connectionTestMessage)
                                .font(.caption)
                                .foregroundStyle(success ? Color.successGreen : Color.errorRed)
                        }
                        
                        Button("测试连接") {
                            runConnectionTest()
                        }
                        .disabled(isTestingConnection)
                    }
                    .padding(.top, 4)
                }
                .cardStyle()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var statsDashboardCard: some View {
        GroupBox(label: Label("时段内活动指标", systemImage: "chart.bar.doc.horizontal")) {
            VStack(alignment: .leading, spacing: 10) {
                if currentPeriodLogs.isEmpty {
                    Text("当前选定时段内无有效模型交互日志")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        statItemCard(title: "交互总次数", value: "\(currentPeriodLogs.count)", icon: "bubble.left.and.bubble.right", color: .infoBlue)
                        
                        let tokensUsed = currentPeriodLogs.reduce(0) { $0 + ($1.totalTokens ?? 0) }
                        statItemCard(title: "总 Token 消耗", value: tokensUsed.formattedCompact, icon: "textformat.abc", color: .accentGradientStart)
                        
                        let activeModels = Set(currentPeriodLogs.compactMap { $0.modelName }).filter { !$0.isEmpty }
                        statItemCard(title: "活跃模型数", value: "\(activeModels.count)", icon: "cpu", color: .warningOrange)
                        
                        let activeClients = Set(currentPeriodLogs.compactMap { $0.metadata["client"] }).filter { !$0.isEmpty }
                        statItemCard(title: "活动客户端数", value: "\(activeClients.count)", icon: "terminal", color: .successGreen)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
    
    private var reportContentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("复盘报告预览", systemImage: "doc.text.image")
                    .font(.headline)
                
                Spacer()
                
                if !service.summaryText.isEmpty && !service.isGenerating {
                    // Preview vs Raw Text Editor Switch
                    Picker("", selection: $isEditMode) {
                        Text("报告预览").tag(false)
                        Text("源码编辑").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
            
            ZStack {
                // Case 1: Loading / Generating state
                if service.isGenerating {
                    generatingLoaderView
                }
                
                // Case 2: Empty/Initial State
                else if service.summaryText.isEmpty {
                    initialStatePlaceholderView
                }
                
                // Case 3: Output rendered report
                else {
                    if isEditMode {
                        TextEditor(text: $service.summaryText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 400)
                            .padding(6)
                            .background(Color.cardBackground.opacity(0.3))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    } else {
                        NativeScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(parseMarkdown(service.summaryText)) { block in
                                    MarkdownBlockView(block: block)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 400, maxHeight: 600)
                        .background(Color.cardBackground.opacity(0.3))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            
            // Footer Control Buttons
            if !service.isGenerating && !service.summaryText.isEmpty {
                HStack(spacing: 12) {
                    Button(action: startGeneratingSummary) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("重新生成")
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentGradientStart)
                    .disabled(currentPeriodLogs.isEmpty)
                    
                    Button(action: copyToClipboard) {
                        Label("复制报告", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: saveToFile) {
                        Label("保存到文件", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .cardStyle()
    }
    
    private var generatingLoaderView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(service.progressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("分析流程包括：")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("• 扫描所选时段的 SQLite 模型交互日志")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("• 清洗并截断超长上下文，压缩内容体积")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("• 路由并发送至选定的 LLM 生成 Markdown 复盘")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .background(Color.cardBackground.opacity(0.2))
        .cornerRadius(8)
    }
    
    private var initialStatePlaceholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("尚未生成复盘报告")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            if currentPeriodLogs.isEmpty {
                Text("当前时段内没有检测到模型交互记录，无法生成分析。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("模型将智能归纳您这期间做过的开发工作、技术沉淀与调试历程。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.bottom, 8)
                
                Button(action: startGeneratingSummary) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("开始分析并生成复盘")
                    }
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentGradientStart)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .background(Color.cardBackground.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func statItemCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.cardBackground.opacity(0.4))
        .cornerRadius(8)
    }
    
    // MARK: - Logic & Actions
    
    private func fetchLogs() async -> [ParsedLog] {
        let calendar = Calendar.current
        let now = Date()
        var startDate = calendar.startOfDay(for: now)
        var endDate = now
        
        switch selectedPeriod {
        case .today:
            startDate = calendar.startOfDay(for: now)
            endDate = now
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            startDate = calendar.startOfDay(for: yesterday)
            if let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: yesterday) {
                endDate = end
            } else {
                endDate = calendar.startOfDay(for: now).addingTimeInterval(-1)
            }
        case .last3Days:
            startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -2, to: now) ?? now)
            endDate = now
        case .last7Days:
            startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            endDate = now
        case .custom:
            startDate = calendar.startOfDay(for: customStartDate)
            if let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) {
                endDate = end
            } else {
                endDate = customEndDate
            }
        }
        
        return await database.filterLogs(startDate: startDate, endDate: endDate)
    }
    
    private func loadLogsForSelectedPeriod() {
        Task {
            let logs = await fetchLogs()
            // Filter only logs that have prompt and response, or are from warp/ollama (which are activity/metadata only)
            self.currentPeriodLogs = logs.filter { log in
                let promptEmpty = log.prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                let responseEmpty = log.response?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                let isActivityOnly = log.provider == .warp || log.provider == .ollama
                return (!promptEmpty || !responseEmpty) || isActivityOnly
            }
        }
    }
    
    private func startGeneratingSummary() {
        Task {
            await service.generateSummary(
                logs: currentPeriodLogs,
                provider: provider,
                baseUrl: activeBaseUrl,
                model: activeModel,
                apiKey: activeApiKey
            )
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.summaryText, forType: .string)
    }
    
    private func saveToFile() {
        let savePanel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            savePanel.allowedContentTypes = [markdownType]
        } else {
            savePanel.allowedContentTypes = [.plainText]
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "AI复盘报告-\(dateStr).md"
        savePanel.title = "导出今日复盘报告"
        savePanel.message = "请选择报告的保存位置"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                do {
                    try service.summaryText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    Logger.shared.error("保存复盘报告文件失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func runConnectionTest() {
        isTestingConnection = true
        connectionTestSuccess = nil
        connectionTestMessage = ""
        
        Task {
            let result = await service.testConnection(
                provider: provider,
                baseUrl: activeBaseUrl,
                model: activeModel,
                apiKey: activeApiKey
            )
            
            await MainActor.run {
                self.isTestingConnection = false
                self.connectionTestSuccess = result.success
                self.connectionTestMessage = result.message
            }
        }
    }
}

// Helper to make native AttributedString markdown parsing safe on older systems
extension AttributedString {
    init(fromMarkdown markdown: String) {
        do {
            try self.init(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            self.init(markdown)
        }
    }
}

// Preprocessor to insert spaces around markdown bold/italic/code markers when adjacent to CJK or other non-whitespace characters.
// This is required because SwiftUI's AttributedString Markdown parser (CommonMark-based) does not recognize emphasis runs
// when they flank directly with CJK characters without spacing.
// It also strips leading/trailing spaces directly inside formatting marks (e.g. "** text **" -> "**text**") to prevent parsing failures.
func preprocessMarkdownForChinese(_ text: String) -> String {
    var result = ""
    let chars = Array(text)
    var i = 0
    
    var inBoldAsterisk = false
    var inItalicAsterisk = false
    var inCode = false
    
    while i < chars.count {
        // 1. Inline code: `
        if chars[i] == "`" {
            if inCode {
                // Trim trailing spaces in result before appending closing `
                while !result.isEmpty && result.last?.isWhitespace == true {
                    result.removeLast()
                }
                result.append("`")
                inCode = false
                // If next character is non-whitespace, add a space
                if i + 1 < chars.count && !chars[i + 1].isWhitespace && chars[i + 1] != "`" {
                    result.append(" ")
                }
            } else {
                // If previous character in result was non-whitespace, add a space
                if let last = result.last, !last.isWhitespace && last != "`" {
                    result.append(" ")
                }
                result.append("`")
                inCode = true
                // Skip any leading spaces after opening `
                i += 1
                while i < chars.count && chars[i].isWhitespace {
                    i += 1
                }
                continue
            }
            i += 1
            continue
        }
        
        if inCode {
            result.append(chars[i])
            i += 1
            continue
        }
        
        // 2. Bold: **
        if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "*" {
            if inBoldAsterisk {
                // Trim trailing spaces in result before appending closing **
                while !result.isEmpty && result.last?.isWhitespace == true {
                    result.removeLast()
                }
                result.append("**")
                inBoldAsterisk = false
                if i + 2 < chars.count && !chars[i + 2].isWhitespace && chars[i + 2] != "*" {
                    result.append(" ")
                }
            } else {
                if let last = result.last, !last.isWhitespace && last != "*" {
                    result.append(" ")
                }
                result.append("**")
                inBoldAsterisk = true
                // Skip any leading spaces after opening **
                i += 2
                while i < chars.count && chars[i].isWhitespace {
                    i += 1
                }
                continue
            }
            i += 2
            continue
        }
        
        // 3. Italic: *
        if chars[i] == "*" {
            if inItalicAsterisk {
                while !result.isEmpty && result.last?.isWhitespace == true {
                    result.removeLast()
                }
                result.append("*")
                inItalicAsterisk = false
                if i + 1 < chars.count && !chars[i + 1].isWhitespace && chars[i + 1] != "*" {
                    result.append(" ")
                }
            } else {
                if let last = result.last, !last.isWhitespace && last != "*" {
                    result.append(" ")
                }
                result.append("*")
                inItalicAsterisk = true
                // Skip any leading spaces after opening *
                i += 1
                while i < chars.count && chars[i].isWhitespace {
                    i += 1
                }
                continue
            }
            i += 1
            continue
        }
        
        result.append(chars[i])
        i += 1
    }
    
    return result
}

// MARK: - Markdown Parser and Render Blocks

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let type: BlockType
    
    enum BlockType {
        case heading(String, level: Int)
        case bulletPoint(String)
        case codeBlock(String, language: String?)
        case paragraph(AttributedString)
        case table(headers: [String], rows: [[String]])
        case blockquote(AttributedString)
        case divider
    }
}

func parseMarkdown(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = text.components(separatedBy: "\n")
    var inCodeBlock = false
    var codeContent = ""
    var codeLang: String? = nil
    
    var i = 0
    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if line.hasPrefix("```") {
            if inCodeBlock {
                blocks.append(MarkdownBlock(type: .codeBlock(codeContent, language: codeLang)))
                codeContent = ""
                codeLang = nil
                inCodeBlock = false
            } else {
                inCodeBlock = true
                let lang = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                codeLang = lang.isEmpty ? nil : String(lang)
            }
            i += 1
            continue
        }
        
        if inCodeBlock {
            codeContent += line + "\n"
            i += 1
            continue
        }
        
        if trimmed.isEmpty {
            i += 1
            continue
        }
        
        // 1. Check Divider
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            blocks.append(MarkdownBlock(type: .divider))
            i += 1
            continue
        }
        
        // 2. Check Blockquote
        if trimmed.hasPrefix(">") {
            let content = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            let preprocessed = preprocessMarkdownForChinese(content)
            let attrString = AttributedString(fromMarkdown: preprocessed)
            blocks.append(MarkdownBlock(type: .blockquote(attrString)))
            i += 1
            continue
        }
        
        // 3. Check Table
        if trimmed.hasPrefix("|") {
            var tableLines: [String] = []
            var j = i
            while j < lines.count {
                let nextLine = lines[j]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if nextTrimmed.hasPrefix("|") {
                    tableLines.append(nextTrimmed)
                    j += 1
                } else {
                    break
                }
            }
            
            if tableLines.count >= 2 {
                let headerLine = tableLines[0]
                var cleanHeaders = headerLine.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if cleanHeaders.first == "" { cleanHeaders.removeFirst() }
                if cleanHeaders.last == "" { cleanHeaders.removeLast() }
                
                let separatorLine = tableLines[1]
                let isSeparator = separatorLine.replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                
                if isSeparator {
                    var rows: [[String]] = []
                    for rowIndex in 2..<tableLines.count {
                        var cols = tableLines[rowIndex].components(separatedBy: "|")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if cols.first == "" { cols.removeFirst() }
                        if cols.last == "" { cols.removeLast() }
                        rows.append(cols)
                    }
                    
                    blocks.append(MarkdownBlock(type: .table(headers: cleanHeaders, rows: rows)))
                    i = j
                    continue
                }
            }
        }
        
        // 4. Headers
        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if level >= 1 && level <= 6 {
                let content = trimmed.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(MarkdownBlock(type: .heading(content, level: level)))
                i += 1
                continue
            }
        }
        
        // 5. Bullet point
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(MarkdownBlock(type: .bulletPoint(content)))
            i += 1
            continue
        }
        
        // 6. Numbered list
        if let firstDotRange = trimmed.range(of: ". ") {
            let prefix = trimmed[..<firstDotRange.lowerBound]
            if prefix.allSatisfy({ $0.isNumber }) && !prefix.isEmpty {
                let content = trimmed[firstDotRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(MarkdownBlock(type: .bulletPoint("\(prefix). \(content)")))
                i += 1
                continue
            }
        }
        
        // 7. Normal paragraph
        let preprocessed = preprocessMarkdownForChinese(line)
        let attrString = AttributedString(fromMarkdown: preprocessed)
        blocks.append(MarkdownBlock(type: .paragraph(attrString)))
        i += 1
    }
    
    if inCodeBlock && !codeContent.isEmpty {
        blocks.append(MarkdownBlock(type: .codeBlock(codeContent, language: codeLang)))
    }
    
    return blocks
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    
    var body: some View {
        switch block.type {
        case .heading(let text, let level):
            Text(text)
                .font(headingFont(for: level))
                .fontWeight(.bold)
                .foregroundStyle(level == 1 ? Color.accentGradientStart : .primary)
                .padding(.top, level == 1 ? 16 : 8)
                .padding(.bottom, 4)
                
        case .bulletPoint(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(Color.accentGradientStart)
                Text(AttributedString(fromMarkdown: preprocessMarkdownForChinese(text)))
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(.leading, 12)
            
        case .codeBlock(let text, let lang):
            VStack(alignment: .leading, spacing: 0) {
                if let lang {
                    HStack {
                        Text(lang.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.cardBackground.opacity(0.8))
                }
                
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cardBackground.opacity(0.4))
            }
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            .padding(.vertical, 4)
            
        case .paragraph(let attrString):
            Text(attrString)
                .font(.body)
                .lineSpacing(4)
                .padding(.bottom, 2)
                .textSelection(.enabled)
                
        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)
            
        case .blockquote(let attrString):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.accentGradientStart)
                    .frame(width: 4)
                Text(attrString)
                    .font(.body)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
            .padding(.leading, 4)
            
        case .divider:
            Divider()
                .padding(.vertical, 12)
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 1) {
                // Header row
                GridRow {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .fontWeight(.bold)
                            .font(.subheadline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 100, alignment: .leading)
                            .background(Color.secondary.opacity(0.12))
                    }
                }
                .background(Color.secondary.opacity(0.08))
                
                // Data rows
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    GridRow {
                        ForEach(0..<headers.count, id: \.self) { colIndex in
                            let text = colIndex < row.count ? row[colIndex] : ""
                            let cleanText = text.replacingOccurrences(of: "<br>", with: "\n")
                                                .replacingOccurrences(of: "<br/>", with: "\n")
                                                .replacingOccurrences(of: "<br />", with: "\n")
                            Text(AttributedString(fromMarkdown: preprocessMarkdownForChinese(cleanText)))
                                .font(.caption)
                                .lineSpacing(4)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .frame(minWidth: 100, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.cardBackground.opacity(0.15) : Color.cardBackground.opacity(0.3))
                }
            }
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .padding(.vertical, 8)
    }
}
