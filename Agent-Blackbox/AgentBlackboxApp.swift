import SwiftUI

@main
struct AgentBlackboxApp: App {
    @StateObject private var fileMonitor = FileMonitorService()
    @StateObject private var database = DatabaseService()
    @StateObject private var configService = ConfigService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fileMonitor)
                .environmentObject(database)
                .environmentObject(configService)
                .task {
                    database.initializeIfNeeded()
                }
        }

        Settings {
            SettingsView()
                .environmentObject(configService)
                .environmentObject(database)
        }
    }
}
