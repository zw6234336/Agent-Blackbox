import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var proxyServer: ProxyServerService
    @EnvironmentObject var clientInterception: ClientInterceptionService
    
    @State private var showClearConfirmation = false
    @State private var cleanupResult: String? = nil

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            directorySettings
                .tabItem {
                    Label("监控目录", systemImage: "folder")
                }

            proxySettings
                .tabItem {
                    Label("网关代理", systemImage: "network")
                }

            clientInterceptionSettings
                .tabItem {
                    Label("客户端接管", systemImage: "app.badge.checkmark")
                }

            dataSettings
                .tabItem {
                    Label("数据管理", systemImage: "externaldrive")
                }
        }
        .frame(width: 650, height: 500)
    }

    private var generalSettings: some View {
        Form {
            Section("监控设置") {
                Toggle("开机自动启动", isOn: $configService.config.autoStart)
                Toggle("启用通知", isOn: $configService.config.enableNotifications)
                Toggle("递归监控子目录", isOn: $configService.config.isRecursive)
            }

            Section("文件类型") {
                ForEach(configService.config.filePatterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            configService.config.filePatterns.removeAll { $0 == pattern }
                        }) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("常用格式已预设")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("数据保留") {
                Stepper("保留 \(configService.config.dataRetentionDays) 天",
                        value: $configService.config.dataRetentionDays,
                        in: 7...365, step: 7)
            }
        }
        .formStyle(.grouped)
        .onChange(of: configService.config) {
            configService.save()
        }
    }

    private var proxySettings: some View {
        Form {
            Section("网关设置") {
                Toggle("启用本地网关代理", isOn: $configService.config.enableProxy)
                
                HStack {
                    Text("监听端口")
                    Spacer()
                    TextField("", value: $configService.config.proxyPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section("上游 API 地址") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI 上游地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $configService.config.openaiUpstreamUrl)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Anthropic 上游地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $configService.config.anthropicUpstreamUrl)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("配置说明：")
                        .font(.headline)
                    Text("1. 请在您的 AI 客户端中将 Base URL 设置为：")
                    Text("   http://127.0.0.1:\(String(configService.config.proxyPort))/v1")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.accentGradientStart)
                    Text("2. 网关会自动转发请求到上述上游 API 地址，并记录精确的 Token 消耗、提示词和耗时。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .onChange(of: configService.config.enableProxy) { oldValue, newValue in
            if newValue {
                proxyServer.start()
            } else {
                proxyServer.stop()
            }
        }
        .onChange(of: configService.config.proxyPort) { oldValue, newValue in
            if proxyServer.isRunning {
                proxyServer.stop()
                proxyServer.start()
            }
        }
        .onChange(of: configService.config) { oldValue, newValue in
            configService.save()
        }
    }

    private var directorySettings: some View {
        Form {
            Section("当前监控目录") {
                ForEach(configService.config.monitoredDirectories, id: \.self) { dir in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.accentGradientStart)
                        Text(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.subheadline)
                        Spacer()
                        Button(action: {
                            configService.config.monitoredDirectories.removeAll { $0 == dir }
                            configService.save()
                        }) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("添加目录") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        let path = url.path
                        if !configService.config.monitoredDirectories.contains(path) {
                            configService.config.monitoredDirectories.append(path)
                            configService.save()
                        }
                    }
                }
            }

            Section("快速添加 LLM 工具目录") {
                ForEach(LLMProvider.allCases) { provider in
                    if !provider.defaultLogPaths.isEmpty {
                        DisclosureGroup {
                            ForEach(provider.defaultLogPaths, id: \.self) { path in
                                let exists = FileManager.default.fileExists(atPath: path)
                                let added = configService.config.monitoredDirectories.contains(path)
                                HStack {
                                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.caption)
                                        .foregroundStyle(exists ? .primary : .tertiary)
                                    Spacer()
                                    if added {
                                        Text("已添加")
                                            .font(.caption2)
                                            .foregroundStyle(Color.successGreen)
                                    } else if exists {
                                        Button("添加") {
                                            configService.config.monitoredDirectories.append(path)
                                            configService.save()
                                        }
                                        .font(.caption)
                                    } else {
                                        Text("未安装")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: provider.iconName)
                                    .foregroundStyle(provider.brandColor)
                                Text(provider.displayName)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dataSettings: some View {
        Form {
            Section("数据库") {
                HStack {
                    Text("路径")
                        .foregroundStyle(.secondary)
                    Text(configService.config.databasePath)
                        .font(.caption)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("总日志数")
                        .foregroundStyle(.secondary)
                    Text("\(database.totalLogCount)")
                }

                HStack {
                    Text("收藏数")
                        .foregroundStyle(.secondary)
                    Text("\(database.bookmarkedCount)")
                }

                Button("清空数据库") {
                    showClearConfirmation = true
                }
                .foregroundColor(.red)
                .confirmationDialog("确定要清空所有数据吗？", isPresented: $showClearConfirmation) {
                    Button("清空所有数据", role: .destructive) {
                        Task { await database.clearAllLogs() }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("此操作将删除所有日志数据，无法恢复。")
                }
            }

            Section("数据质量") {
                Text("清理由旧版本解析器写入的脏数据：模型名为 n_ctx / 7.27 / FileNotFoundError 等的污染条目，以及缺失 token 的 claude-code 历史行。下次启动监控时新版解析器会自动重新提取。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("清理脏数据") {
                        Task {
                            let n = await database.cleanupGarbageLogs()
                            cleanupResult = "已删除 \(n) 条脏数据"
                        }
                    }
                    if let r = cleanupResult {
                        Text(r).font(.caption).foregroundStyle(.green)
                    }
                }
            }

            Section("导出") {
                HStack {
                    Text("导出目录")
                        .foregroundStyle(.secondary)
                    Text(configService.config.exportDirectory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                }

                HStack {
                    Button("导出 JSON") {
                        if let url = database.exportLogs(format: .json) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Button("导出 CSV") {
                        if let url = database.exportLogs(format: .csv) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var clientInterceptionSettings: some View {
        Form {
            Section("自动接管配置") {
                Text("开启后，本应用将自动修改目标插件配置文件，使其路由经过本地网关代理。关闭或退出本程序时将自动还原为原始配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                
                Toggle(isOn: $configService.config.enableVSCodeClineInterception) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VS Code - Cline")
                        clientInterceptionStatus(for: .vscodeCline)
                    }
                }
                
                Toggle(isOn: $configService.config.enableVSCodeRooClineInterception) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VS Code - Roo-Cline")
                        clientInterceptionStatus(for: .vscodeRooCline)
                    }
                }
                
                Toggle(isOn: $configService.config.enableCursorClineInterception) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor - Cline")
                        clientInterceptionStatus(for: .cursorCline)
                    }
                }
                
                Toggle(isOn: $configService.config.enableCursorRooClineInterception) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cursor - Roo-Cline")
                        clientInterceptionStatus(for: .cursorRooCline)
                    }
                }
                
                Toggle(isOn: $configService.config.enableClaudeCodeInterception) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code")
                        clientInterceptionStatus(for: .claudeCode)
                    }
                }
                
                Toggle(isOn: $configService.config.enablePiInterception) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pi Agent")
                        clientInterceptionStatus(for: .pi)
                    }
                }
            }
            
            Section("Cursor 核心设置 (说明)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("对于 Cursor 自带的 AI 模型调用，为保证软件稳定性，请在 Cursor 内手动覆盖 Base URL：")
                    Text("1. 打开 Cursor Settings -> Models")
                    Text("2. 在 OpenAI 或 Anthropic 处展开 \"Override Base URL\"")
                    Text("3. 填写：http://127.0.0.1:\(String(configService.config.proxyPort))/v1")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.accentGradientStart)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            
            Section("沙盒与文件权限说明") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("若开关提示“写入失败”，可能是因为系统 Sandbox (沙盒模式) 开启，禁止本软件读写其他应用的目录。")
                    Text("请确保在 Xcode / Entitlements 中关闭沙盒，或赋予了完整磁盘访问权限。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
    
    @ViewBuilder
    private func clientInterceptionStatus(for client: InterceptClient) -> some View {
        if let error = clientInterception.errors[client] {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
        } else if clientInterception.activeStates[client] == true {
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("已接管 (已备份原始设置)")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        } else {
            let pathExists = FileManager.default.fileExists(atPath: client.settingsURL.path)
            Text(pathExists ? "就绪 (未接管)" : "未检测到该插件配置文件")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

