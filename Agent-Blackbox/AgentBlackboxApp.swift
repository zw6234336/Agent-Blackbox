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

    // Local scroll-wheel monitor.
    //
    // Workaround for a known SwiftUI-on-macOS bug: after the app has been
    // idle for a long time, trackpad / scroll-wheel events stop being
    // dispatched to SwiftUI ScrollViews (clicking the scrollbar thumb
    // still works, because that path doesn't go through SwiftUI's wheel
    // dispatcher). Installing a local `.scrollWheel` event monitor that
    // simply returns the event unchanged keeps the scroll-wheel dispatch
    // path registered in the run loop's common modes so it can't fall
    // dormant. We hold the monitor token for the app lifetime.
    private var scrollWheelMonitor: Any?
    private var mouseMovedMonitor: Any?
    private var scrollKeepAliveTimer: Timer?

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

        // Install a smart local monitor for scroll-wheel events.
        // SwiftUI on macOS has a bug where after the app is idle or focus changes,
        // it stops dispatching scroll events to ScrollViews.
        // By intercepting scroll-wheel events globally, hit-testing to find the view
        // under the cursor, walking up to find its NSScrollView, and forwarding the
        // event directly, we bypass SwiftUI's buggy event router completely.
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let window = event.window,
                  let contentView = window.contentView else {
                return event
            }
            
            // contentView.hitTest expects a point in its superview's coordinate system.
            // Since contentView is the root view of the window, its superview's coordinate
            // system is the window's coordinate system. Therefore, we pass locationInWindow directly.
            if let hitView = contentView.hitTest(event.locationInWindow) {
                var candidate: NSView? = hitView
                while let view = candidate {
                    if let scrollView = view as? NSScrollView {
                        scrollView.scrollWheel(with: event)
                        return nil // Consume event to prevent SwiftUI's buggy dispatcher from ignoring/swallowing it
                    }
                    candidate = view.superview
                }
            }
            return event
        }
        mouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited]) { event in
            return event
        }

        // Periodically post a zero-delta synthetic scroll event to keep
        // SwiftUI's internal scroll-wheel handler "hot".  Without this,
        // the handler can go dormant after long idle, ignoring real
        // scroll-wheel events until the user clicks inside the window.
        // The event is invisible (deltaY = 0) and fires every 15 s.
        //
        // IMPORTANT: We intentionally do NOT gate this on `NSApp.isActive`.
        // The previous code skipped the synthetic event when the app was
        // inactive, which meant that after an overnight idle the scroll
        // dispatcher was completely dormant by the time the user returned.
        // Sending the event even while inactive keeps the dispatch path
        // registered in the run loop.
        scrollKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.sendSyntheticScrollEvent()
        }
        // Make sure the timer fires even when tracking menus / modal panels.
        if let timer = scrollKeepAliveTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

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

    // MARK: - Scroll Wake-Up on App Activation

    /// Called every time the app transitions from inactive/background to
    /// active foreground.  This is the critical moment after an overnight
    /// idle: SwiftUI's scroll-wheel dispatcher is dormant, so we send a
    /// rapid burst of synthetic scroll events to force it back to life.
    func applicationDidBecomeActive(_ notification: Notification) {
        // Send a burst of 3 synthetic scroll events spaced 50 ms apart.
        // A single event sometimes isn't enough to re-register the dispatch
        // path if SwiftUI has been dormant for many hours.
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in
                self?.sendSyntheticScrollEvent()
            }
        }
    }

    // MARK: - Synthetic Scroll Event

    /// Sends a zero-delta scroll event to all visible windows.  The event
    /// has no visual effect but keeps SwiftUI's internal scroll-wheel
    /// handler registered in the run loop.
    private func sendSyntheticScrollEvent() {
        guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil,
                                     units: .pixel,
                                     wheelCount: 1,
                                     wheel1: 0, wheel2: 0, wheel3: 0) else { return }
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return }

        // Send to ALL visible windows, not just mainWindow.
        // After idle, the mainWindow reference might be stale or nil.
        for window in NSApp.windows where window.isVisible {
            window.sendEvent(nsEvent)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }
        if let monitor = scrollWheelMonitor {
            NSEvent.removeMonitor(monitor)
            scrollWheelMonitor = nil
        }
        if let monitor = mouseMovedMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMovedMonitor = nil
        }
        scrollKeepAliveTimer?.invalidate()
        scrollKeepAliveTimer = nil
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
                .frame(minWidth: 1000, minHeight: 600)
                .task {
                    database.initializeIfNeeded()
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
