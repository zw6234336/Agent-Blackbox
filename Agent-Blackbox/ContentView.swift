import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fileMonitor: FileMonitorService
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var compilationService: CompilationService
    @EnvironmentObject var proxyServer: ProxyServerService
    @EnvironmentObject var tracker: RateLimitTrackerService
    @State private var selectedTab = 0

    // Sheet states
    @State private var showNewCompilationSheet = false
    @State private var availableProviders: [LLMProvider] = []
    
    @State private var showNewCollectionSheet = false
    
    @State private var editingProvider: LLMProvider? = nil
    
    @State private var selectedLogForDetail: ParsedLog? = nil

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

                Section("网关") {
                    Label("代理监控", systemImage: "bolt.shield")
                        .tag(7)
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
                case 7:
                    ProxyDashboardView()
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
                    Button(action: toggleProxy) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(proxyServer.isRunning ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(proxyServer.isRunning ? "网关运行中" : "网关未启动")
                                .font(.caption)
                        }
                    }
                    .help(proxyServer.isRunning ? "点击停止网关代理" : "点击启动网关代理")

                    Divider()

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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowNewCompilationSheet"))) { notification in
            if let providers = notification.object as? [LLMProvider] {
                self.availableProviders = providers
            }
            showNewCompilationSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowNewCollectionSheet"))) { _ in
            showNewCollectionSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLogDetailSheet"))) { notification in
            if let log = notification.object as? ParsedLog {
                selectedLogForDetail = log
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowRateLimitEditorSheet"))) { notification in
            if let provider = notification.object as? LLMProvider {
                editingProvider = provider
            }
        }
        .sheet(isPresented: $showNewCompilationSheet) {
            NewCompilationSheet(
                availableProviders: availableProviders,
                onCancel: {
                    showNewCompilationSheet = false
                },
                onCreate: { draft in
                    showNewCompilationSheet = false
                    compilationService.initializeIfNeeded()
                    let created = compilationService.createCompilation(
                        name: draft.name,
                        description: draft.description,
                        format: draft.format,
                        providers: draft.providers.compactMap { LLMProvider(rawValue: $0) },
                        startDate: draft.hasStartDate ? draft.startDate : nil,
                        endDate: draft.hasEndDate ? draft.endDate : nil,
                        bookmarkedOnly: draft.bookmarkedOnly
                    )
                    compilationService.startGeneration(id: created.id)
                    NotificationCenter.default.post(name: Notification.Name("SelectCompilation"), object: created)
                }
            )
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewCollectionSheet(
                onCancel: {
                    showNewCollectionSheet = false
                },
                onCreate: { name, desc in
                    database.createCollection(name: name, description: desc)
                    showNewCollectionSheet = false
                }
            )
        }
        .sheet(item: $editingProvider) { provider in
            RateLimitEditor(provider: provider)
                .environmentObject(configService)
                .environmentObject(tracker)
                .frame(minWidth: 460, minHeight: 520)
        }
        .sheet(item: $selectedLogForDetail) { log in
            LogDetailView(log: log, isModal: true)
                .environmentObject(database)
                .frame(minWidth: 600, minHeight: 650)
        }
    }

    private func toggleProxy() {
        if proxyServer.isRunning {
            proxyServer.stop()
        } else {
            proxyServer.start()
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
