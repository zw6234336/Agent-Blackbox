import SwiftUI

struct MonitorView: View {
    @EnvironmentObject var fileMonitor: FileMonitorService

    var body: some View {
        VStack(spacing: 20) {
            StatusIndicator(isActive: fileMonitor.isMonitoring)

            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(fileMonitor.detectedLogs, id: \.self) { url in
                        LogEntryRow(url: url)
                    }
                }
            }

            GroupBox("监控目录") {
                List(fileMonitor.monitoredPaths, id: \.self) { path in
                    Text(path)
                }
                .frame(minHeight: 120)
            }
        }
        .padding()
    }
}
