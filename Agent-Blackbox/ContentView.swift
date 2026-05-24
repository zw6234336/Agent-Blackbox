import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fileMonitor: FileMonitorService
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var compilationService: CompilationService
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("概览") {
                    Label("看板", systemImage: "chart.bar.doc.horizontal")
                        .tag(0)
                }

                Section("数据") {
                    Label("日志", systemImage: "doc.text.magnifyingglass")
                        .tag(1)
                    Label("收藏", systemImage: "star.fill")
                        .tag(2)
                    Label("编译", systemImage: "doc.append")
                        .tag(6)
                }

                Section("用量") {
                    Label("速率/配额", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .tag(4)
                }

                Section("系统") {
                    Label("监控", systemImage: "eye.circle")
                        .tag(3)
                    Label("设置", systemImage: "gear")
                        .tag(5)
                }
            }
            .navigationTitle("Agent Blackbox")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedTab {
                case 0:
                    DashboardView()
                case 1:
                    LogListView()
                case 2:
                    CollectionView()
                case 3:
                    MonitorView()
                case 4:
                    RateLimitView()
                case 5:
                    SettingsView()
                        .environmentObject(configService)
                        .environmentObject(database)
                case 6:
                    CompilationView()
                        .environmentObject(compilationService)
                        .environmentObject(database)
                default:
                    DashboardView()
                }
            }
            .onAppear {
                fileMonitor.bind(database: database)
                fileMonitor.updateFilePatterns(configService.config.filePatterns)
            }
            .onChange(of: configService.config.filePatterns) { oldValue, newValue in
                fileMonitor.updateFilePatterns(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToRateLimits"))) { _ in
                selectedTab = 4
            }
            .toolbar {
                ToolbarItemGroup {
                    Button(action: toggleMonitoring) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(fileMonitor.isMonitoring ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(fileMonitor.isMonitoring ? "监控中" : "未监控")
                                .font(.caption)
                        }
                    }
                    .help(fileMonitor.isMonitoring ? "点击停止监控" : "点击开始监控")

                    Divider()

                    HStack(spacing: 12) {
                        Label("\(database.totalLogCount)", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if database.dashboardStats.totalTokens > 0 {
                            Label("\(database.dashboardStats.totalTokens.formattedCompact) tokens", systemImage: "textformat.abc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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
