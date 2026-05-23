import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var fileMonitor: FileMonitorService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var database: DatabaseService
    @State private var showPresets = false

    var body: some View {
        VStack(spacing: 0) {
            // Status header
            statusHeader
            
            Divider()
            
            HSplitView {
                // Left: Detected logs
                detectedLogsList
                    .frame(minWidth: 300)
                
                // Right: Monitored directories
                monitoredDirectories
                    .frame(minWidth: 300)
            }
        }
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        HStack(spacing: 16) {
            PulsingStatusIndicator(isActive: fileMonitor.isMonitoring)
            
            VStack(alignment: .leading) {
                Text(fileMonitor.isMonitoring ? "监控运行中" : "监控已停止")
                    .font(.headline)
                Text("已检测 \(fileMonitor.detectedLogs.count) 个日志文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: toggleMonitoring) {
                Label(
                    fileMonitor.isMonitoring ? "停止监控" : "开始监控",
                    systemImage: fileMonitor.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(fileMonitor.isMonitoring ? Color.errorRed : Color.successGreen)
        }
        .padding()
    }
    
    // MARK: - Detected Logs
    
    private var detectedLogsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("检测到的日志文件")
                .font(.headline)
                .padding()
            
            Divider()
            
            if fileMonitor.detectedLogs.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(fileMonitor.isMonitoring ? "等待日志文件变化..." : "开始监控以检测日志")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(fileMonitor.detectedLogs, id: \.self) { url in
                            LogEntryRow(url: url)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Monitored Directories
    
    private var monitoredDirectories: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("监控目录")
                    .font(.headline)
                Spacer()
                Button("添加预设") {
                    showPresets.toggle()
                }
                .popover(isPresented: $showPresets) {
                    presetDirectories
                }
            }
            .padding()
            
            Divider()
            
            List {
                ForEach(configService.config.monitoredDirectories, id: \.self) { dir in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.accentGradientStart)
                        VStack(alignment: .leading) {
                            Text(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.subheadline)
                            Text(FileManager.default.fileExists(atPath: dir) ? "有效" : "目录不存在")
                                .font(.caption2)
                                .foregroundStyle(FileManager.default.fileExists(atPath: dir) ? Color.successGreen : Color.errorRed)
                        }
                        Spacer()
                        Button(action: {
                            configService.config.monitoredDirectories.removeAll { $0 == dir }
                            configService.save()
                        }) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Color.errorRed)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    // MARK: - Preset Directories
    
    private var presetDirectories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快速添加 LLM 工具目录")
                .font(.headline)
                .padding(.bottom, 4)
            
            ForEach(LLMProvider.allCases, id: \.self) { provider in
                if !provider.defaultLogPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: provider.iconName)
                                .foregroundStyle(provider.brandColor)
                            Text(provider.displayName)
                                .fontWeight(.medium)
                        }
                        
                        ForEach(provider.defaultLogPaths, id: \.self) { path in
                            let alreadyAdded = configService.config.monitoredDirectories.contains(path)
                            let exists = FileManager.default.fileExists(atPath: path)
                            
                            HStack {
                                Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption)
                                    .foregroundStyle(exists ? .primary : .tertiary)
                                
                                Spacer()
                                
                                if alreadyAdded {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.successGreen)
                                        .font(.caption)
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
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding()
        .frame(width: 450)
    }
    
    private func toggleMonitoring() {
        if fileMonitor.isMonitoring {
            fileMonitor.stopMonitoring()
        } else {
            let paths = configService.config.monitoredDirectories
            fileMonitor.startMonitoring(paths: paths)
        }
    }
}

// MARK: - Pulsing Status Indicator

struct PulsingStatusIndicator: View {
    let isActive: Bool
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)
            }
            
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
        }
        .onAppear {
            if isActive { isPulsing = true }
        }
        .onChange(of: isActive) { oldValue, newValue in
            isPulsing = newValue
        }
    }
}
