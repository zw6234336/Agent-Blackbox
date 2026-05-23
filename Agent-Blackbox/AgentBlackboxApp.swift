import SwiftUI

@main
struct AgentBlackboxApp: App {
    @StateObject private var fileMonitor = FileMonitorService()
    @StateObject private var database = DatabaseService()
    @StateObject private var configService = ConfigService()
    @StateObject private var rateTracker = RateLimitTrackerService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileMonitor)
                .environmentObject(database)
                .environmentObject(configService)
                .environmentObject(rateTracker)
                .frame(minWidth: 1000, minHeight: 600)
                .task {
                    database.initializeIfNeeded()
                    rateTracker.bind(database: database, config: configService)
                    rateTracker.start()

                    // Auto-start monitoring if configured
                    if configService.config.autoStart {
                        let paths = configService.config.monitoredDirectories
                        fileMonitor.bind(database: database)
                        fileMonitor.updateFilePatterns(configService.config.filePatterns)
                        fileMonitor.startMonitoring(paths: paths)
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)

        Settings {
            SettingsView()
                .environmentObject(configService)
                .environmentObject(database)
        }
    }
}
