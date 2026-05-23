import SwiftUI

struct LogListView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var searchText = ""
    @State private var selectedLog: ParsedLog?
    @State private var searchResults: [ParsedLog] = []

    private var filteredLogs: [ParsedLog] {
        if searchText.isEmpty {
            return database.logs
        }
        return searchResults
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
            refreshSearchResults()
        }
        .onChange(of: searchText) { _ in
            refreshSearchResults()
        }
        .onChange(of: database.logs) { _ in
            refreshSearchResults()
        }
    }

    private func refreshSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        searchResults = database.searchLogs(query: searchText)
    }
}
