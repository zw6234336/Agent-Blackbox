import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            LogListView()
        } detail: {
            if let entry = appState.selectedEntry {
                LogDetailView(entry: entry)
            } else {
                emptyDetail
            }
        }
        .navigationTitle("Agent Blackbox")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("Open Settings")

                Button {
                    if appState.isMonitoring {
                        appState.stopMonitoring()
                    } else {
                        appState.startMonitoring()
                    }
                } label: {
                    Label(
                        appState.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                        systemImage: appState.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .foregroundColor(appState.isMonitoring ? .red : .green)
                }
                .help(appState.isMonitoring ? "Stop monitoring" : "Start monitoring")
            }

            ToolbarItem(placement: .status) {
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .frame(minWidth: 960, minHeight: 640)
    }

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("Select a log entry to view details")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
