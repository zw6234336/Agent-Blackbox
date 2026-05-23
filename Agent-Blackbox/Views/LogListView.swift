import SwiftUI

struct LogListView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var searchText = ""
    @State private var selectedLog: ParsedLog?

    private var filteredLogs: [ParsedLog] {
        if searchText.isEmpty {
            return database.logs
        }

        return database.logs.filter { log in
            log.prompt?.localizedCaseInsensitiveContains(searchText) ?? false ||
            log.response?.localizedCaseInsensitiveContains(searchText) ?? false ||
            log.modelName?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredLogs, selection: $selectedLog) { log in
                VStack(alignment: .leading) {
                    Text(log.modelName ?? "Unknown Model")
                        .font(.headline)
                    Text(log.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .searchable(text: $searchText)
        } detail: {
            if let log = selectedLog {
                LogDetailView(log: log)
            } else {
                Text("选择一条日志查看详情")
            }
        }
        .task {
            await database.reloadLogs()
        }
    }
}
