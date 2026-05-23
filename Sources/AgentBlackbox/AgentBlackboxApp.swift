import SwiftUI

@main
struct AgentBlackboxApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Export Logs…") {
                    appState.exportLogs()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Clear All Logs") {
                    appState.clearAllLogs()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
