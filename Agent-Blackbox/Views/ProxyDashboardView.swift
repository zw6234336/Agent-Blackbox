import SwiftUI
import AppKit

struct ProxyDashboardView: View {
    @EnvironmentObject var proxyServer: ProxyServerService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var clientInterception: ClientInterceptionService
    
    @State private var selectedRequest: ProxyRequestLog? = nil
    @State private var isCopying = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Left Column: Main Dashboard
            VStack(spacing: 16) {
                headerSection
                metricsAndInterceptionRow
                liveRequestsList
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Details Inspector
            if let request = selectedRequest {
                detailInspectorPanel(for: request)
                    .frame(width: 380)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(Color.dashboardBackground)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedRequest)
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
                    Text("本地网关监控")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(proxyServer.isRunning ? "监听端口: \(proxyServer.port) | 拦截出网模型流量" : "网关代理未启动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
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
    
    // MARK: - Metrics & Interception
    
    private var metricsAndInterceptionRow: some View {
        HStack(spacing: 16) {
            // Metrics (Left)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                proxyMetricCard(
                    title: "拦截次数",
                    value: "\(proxyServer.capturedCount)",
                    icon: "bolt.fill",
                    color: .infoBlue
                )
                proxyMetricCard(
                    title: "活跃请求",
                    value: "\(proxyServer.liveRequests.filter(\.isPending).count)",
                    icon: "arrow.triangle.2.circlepath.circle",
                    color: .warningOrange
                )
                
                let tokens = proxyServer.liveRequests.compactMap { ($0.promptTokens ?? 0) + ($0.completionTokens ?? 0) }.reduce(0, +)
                proxyMetricCard(
                    title: "网关 Token",
                    value: tokens.formattedCompact,
                    icon: "textformat.abc",
                    color: .accentGradientStart
                )
                
                let duration = proxyServer.liveRequests.compactMap { $0.duration }.reduce(0.0, +)
                let count = proxyServer.liveRequests.filter { !$0.isPending }.count
                let avgDuration = count > 0 ? duration / Double(count) : 0.0
                proxyMetricCard(
                    title: "平均耗时",
                    value: avgDuration.formattedDuration,
                    icon: "clock.fill",
                    color: .successGreen
                )
            }
            .frame(maxWidth: .infinity)
            
            // Interception Config Toggles (Right)
            VStack(alignment: .leading, spacing: 8) {
                Text("快捷接管控制 (Cline)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("开启后自动劫持本电脑的插件设置，退出本软件时自动还原：")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    VStack(spacing: 6) {
                        interceptionToggle(for: .vscodeCline, binding: $configService.config.enableVSCodeClineInterception)
                        interceptionToggle(for: .vscodeRooCline, binding: $configService.config.enableVSCodeRooClineInterception)
                        interceptionToggle(for: .cursorCline, binding: $configService.config.enableCursorClineInterception)
                        interceptionToggle(for: .cursorRooCline, binding: $configService.config.enableCursorRooClineInterception)
                    }
                }
            }
            .padding(10)
            .frame(width: 260, height: 160)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
    
    private func proxyMetricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))
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
    
    // MARK: - Live Requests List
    
    private var liveRequestsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时连接流水 (Real-time Gateway Logs)")
                    .font(.headline)
                Spacer()
                Button("清空流水") {
                    proxyServer.clearLiveRequests()
                    selectedRequest = nil
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            
            if proxyServer.liveRequests.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "network")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("暂无代理调用流水")
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
                    ForEach(proxyServer.liveRequests) { request in
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
    
    private func liveRequestRow(for request: ProxyRequestLog) -> some View {
        let isSelected = selectedRequest?.id == request.id
        let provider = detectProvider(model: request.model ?? "", path: request.path)
        
        return HStack(spacing: 12) {
            // Status Indicator
            if request.isPending {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 32, height: 32)
            } else {
                let code = request.statusCode ?? 200
                Text("\(code)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(code == 200 ? Color.green : Color.red)
                    .frame(width: 32, height: 32)
                    .background(code == 200 ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                    .clipShape(Circle())
            }
            
            // Method & Path
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(request.method)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)
                    
                    Text(request.path)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    Text(request.client.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Text(request.timestamp.formattedRelative)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
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
            
            // Token counts
            if let pt = request.promptTokens, let ct = request.completionTokens {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(pt + ct) tokens")
                        .font(.system(size: 9, weight: .bold))
                    Text("in:\(pt) out:\(ct)")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80, alignment: .trailing)
            }
            
            // Duration
            if let duration = request.duration {
                Text(duration.formattedDuration)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
            }
        }
    }
    
    // MARK: - Detail Inspector Panel
    
    private func detailInspectorPanel(for request: ProxyRequestLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("请求解析器 (Inspector)")
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
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Stats box
                    VStack(spacing: 6) {
                        detailMetaRow(label: "当前状态", content: request.isPending ? "Pending (接收流中)" : (request.statusCode.map { "\($0) OK" } ?? "处理完毕"))
                            .foregroundStyle(request.isPending ? .blue : (request.statusCode == 200 ? .green : .red))
                            .fontWeight(.bold)
                        
                        detailMetaRow(label: "出网客户端", content: request.client)
                        detailMetaRow(label: "请求模型", content: request.model ?? "未识别")
                        detailMetaRow(label: "上游路径", content: request.path)
                        
                        if let dur = request.duration {
                            detailMetaRow(label: "总耗时", content: dur.formattedDuration)
                        }
                        if let pt = request.promptTokens, let ct = request.completionTokens {
                            detailMetaRow(label: "总 Token", content: "\(pt + ct) (Input: \(pt) / Output: \(ct))")
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
}
