import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Holds an "activity assertion" that keeps macOS from putting the app into
    // App Nap. Without this, after the user leaves the app idle for a while
    // macOS throttles the run loop; when the user returns to the window,
    // scroll/gesture events appear to be ignored on every page until the
    // run loop fully wakes back up. Retaining this token across the entire
    // app lifetime prevents that "frozen scroll after idle" symptom.
    private var appNapActivity: NSObjectProtocol?



    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opt-out of App Nap so the UI keeps responding to scroll/gesture
        // events even after long periods without user interaction. This is a
        // developer/monitoring tool that is expected to keep refreshing
        // dashboards in the background, so suspension is undesirable.
        // Use both .userInitiated and .idleSystemSleepDisabled to maximise
        // the chance that macOS keeps our run loop responsive.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Agent Blackbox keeps proxy gateway and dashboards responsive"
        )

        // Force the app to become the active foreground application.
        // Without this, launching from Xcode often leaves Xcode as the active
        // app, and key events never reach our windows even though mouse clicks
        // do (sheets show focus rings but typing does nothing).
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Bring the main window forward and make it key once it exists.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.canBecomeKey && $0.title == "Agent Blackbox" }?
                .makeKeyAndOrderFront(nil)
        }
    }



    func applicationDidBecomeActive(_ notification: Notification) {
        // After a long idle period (display sleep, App Nap, or just no user
        // interaction for hours) scroll-wheel events stop working on ALL pages.
        //
        // There are three interacting causes:
        //   1. SwiftUI's private NSWindow subclass intercepts scrollWheel events
        //      in sendEvent and routes them to its internal gesture system; after
        //      idle this routing layer becomes dormant.
        //   2. macOS responsive scrolling (Mavericks+) decouples scroll event
        //      handling into a secondary event loop that can be suspended by the
        //      system during idle.
        //   3. Momentum-phase / inertia scroll events may be routed through the
        //      first-responder rather than hit-testing.
        //
        // This handler addresses all three layers:
        DispatchQueue.main.async {
            // Step 1: Re-make the main window key. This forces SwiftUI's
            // private NSWindow subclass to re-initialise its event-routing
            // state, unblocking the scrollWheel dispatch path.
            if let window = NSApp.windows
                .first(where: { $0.canBecomeKey && $0.title == "Agent Blackbox" }) {
                window.makeKey()
            }

            // Step 2: Walk ALL visible windows and nudge every NSScrollView
            // (including those hidden inside SwiftUI List/ScrollView) back to
            // life.  Calling reflectScrolledClipView re-engages the responsive
            // scrolling pipeline; the layout pass clears stale geometry.
            for window in NSApp.windows where window.isVisible {
                self.wakeUpScrollViews(in: window.contentView)
                window.contentView?.needsLayout = true
                window.contentView?.layoutSubtreeIfNeeded()
            }
        }
    }

    /// Recursively walks the view hierarchy and re-syncs every NSScrollView
    /// found (including those buried inside SwiftUI's private NSView tree).
    private func wakeUpScrollViews(in view: NSView?) {
        guard let view = view else { return }
        if let scrollView = view as? NSScrollView {
            // Don't call reflectScrolledClipView on ResponsiveScrollView
            // instances — they already handle themselves via notifications.
            // But do call it for plain NSScrollView instances that SwiftUI
            // List / ScrollView create internally.
            if !(scrollView is ResponsiveScrollView) {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        for subview in view.subviews {
            wakeUpScrollViews(in: subview)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }
    }

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
    @StateObject private var clientInterception = ClientInterceptionService()
    @StateObject private var desktopWidget = DesktopWidgetService()
    @StateObject private var gitIntegration = GitIntegrationService()
    @StateObject private var dailySummaryService = DailySummaryService()

    @Environment(\.openWindow) private var openWindow

    init() {
        setbuf(stdout, nil)
        setbuf(stderr, nil)
    }

    var body: some Scene {
        Window("Agent Blackbox", id: "main") {
            ContentView()
                .environmentObject(fileMonitor)
                .environmentObject(database)
                .environmentObject(configService)
                .environmentObject(rateTracker)
                .environmentObject(compilationService)
                .environmentObject(planDetector)
                .environmentObject(proxyServer)
                .environmentObject(clientInterception)
                .environmentObject(desktopWidget)
                .environmentObject(gitIntegration)
                .environmentObject(dailySummaryService)
                .frame(minWidth: 1000, minHeight: 600)
                .task {
                    database.initializeIfNeeded()
                    Task {
                        await database.performStartupMaintenance(configService: configService)
                    }
                    gitIntegration.bind(database: database)
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

                    // Bind Client Interception Service
                    clientInterception.bind(config: configService)

                    // 后台自动检测本地套餐授权（首次启动）
                    await planDetector.detectAll()
                }
                .onChange(of: configService.config) { oldValue, newValue in
                    clientInterception.syncWithConfig()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)

        Settings {
            SettingsView()
                .environmentObject(configService)
                .environmentObject(database)
                .environmentObject(proxyServer)
                .environmentObject(clientInterception)
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
            
            Button(desktopWidget.isShowing ? "隐藏桌面悬浮小窗" : "显示桌面悬浮小窗") {
                desktopWidget.toggle(proxyServer: proxyServer)
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
