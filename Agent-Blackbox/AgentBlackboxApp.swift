import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct AgentBlackboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var fileMonitor = FileMonitorService()
    @StateObject private var database = DatabaseService()
    @StateObject private var configService = ConfigService()
    @StateObject private var rateTracker = RateLimitTrackerService()
    @StateObject private var compilationService = CompilationService()
    @StateObject private var planDetector = PlanDetectionService()
    @StateObject private var proxyServer = ProxyServerService()

    @Environment(\.openWindow) private var openWindow

    init() {
        setbuf(stdout, nil)
        setbuf(stderr, nil)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(fileMonitor)
                .environmentObject(database)
                .environmentObject(configService)
                .environmentObject(rateTracker)
                .environmentObject(compilationService)
                .environmentObject(planDetector)
                .environmentObject(proxyServer)
                .frame(minWidth: 1000, minHeight: 600)
                .task {
                    database.initializeIfNeeded()
                    rateTracker.bind(database: database, config: configService)
                    rateTracker.start()

                    // Bind and start Local API Proxy
                    proxyServer.bind(database: database, config: configService)
                    if configService.config.enableProxy {
                        proxyServer.start()
                    }

                    // Auto-start monitoring if configured
                    if configService.config.autoStart {
                        let paths = configService.config.monitoredDirectories
                        fileMonitor.bind(database: database)
                        fileMonitor.updateFilePatterns(configService.config.filePatterns)
                        fileMonitor.startMonitoring(paths: paths)
                    }

                    // 后台自动检测本地套餐授权（首次启动）
                    await planDetector.detectAll()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)

        Settings {
            SettingsView()
                .environmentObject(configService)
                .environmentObject(database)
                .environmentObject(proxyServer)
        }
        
        MenuBarExtra("Agent Blackbox", systemImage: "bolt.shield.fill") {
            Text(proxyServer.isRunning ? "网关代理: 运行中 (端口 \(proxyServer.port))" : "网关代理: 未启动")
            Text(fileMonitor.isMonitoring ? "日志监控: 运行中" : "日志监控: 已停止")
            if database.dashboardStats.totalTokens > 0 {
                Text("累计用量: \(database.dashboardStats.totalTokens.formattedCompact) tokens")
            }
            
            Divider()
            
            Button(proxyServer.isRunning ? "停止网关" : "启动网关") {
                if proxyServer.isRunning {
                    proxyServer.stop()
                } else {
                    proxyServer.start()
                }
            }
            
            Button(fileMonitor.isMonitoring ? "停止日志监控" : "启动日志监控") {
                if fileMonitor.isMonitoring {
                    fileMonitor.stopMonitoring()
                } else {
                    let paths = configService.config.monitoredDirectories
                    fileMonitor.startMonitoring(paths: paths)
                }
            }
            
            Divider()
            
            Button("显示主窗口") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
