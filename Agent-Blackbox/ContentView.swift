import SwiftUI

struct ContentView: View {
    @EnvironmentObject var fileMonitor: FileMonitorService
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var configService: ConfigService
    @State private var selectedTab = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("监控", systemImage: "eye")
                    .tag(0)
                Label("位置与交互", systemImage: "map")
                    .tag(1)
                Label("日志", systemImage: "doc.text")
                    .tag(2)
                Label("统计", systemImage: "chart.bar")
                    .tag(3)
            }
            .navigationTitle("Agent Blackbox")
        } detail: {
            Group {
                switch selectedTab {
                case 0:
                    MonitorView()
                case 1:
                    LogLocationView()
                case 2:
                    LogListView()
                case 3:
                    StatisticsView()
                default:
                    Text("选择一个视图")
                }
            }
            .onAppear {
                fileMonitor.bind(database: database)
                fileMonitor.updateFilePatterns(configService.config.filePatterns)
            }
            .onChange(of: configService.config.filePatterns) { newValue in
                fileMonitor.updateFilePatterns(newValue)
            }
            .toolbar {
                ToolbarItem {
                    Button(action: toggleMonitoring) {
                        Label(
                            fileMonitor.isMonitoring ? "停止监控" : "开始监控",
                            systemImage: fileMonitor.isMonitoring ? "stop.circle" : "play.circle"
                        )
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
