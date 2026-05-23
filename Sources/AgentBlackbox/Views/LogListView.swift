import SwiftUI

struct LogListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.filteredEntries.isEmpty {
                emptyState
            } else {
                List(appState.filteredEntries, selection: $appState.selectedEntry) { entry in
                    LogRowView(entry: entry)
                        .tag(entry)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $appState.searchQuery, prompt: "Search prompts, responses, models…")
        .navigationTitle("Logs (\(appState.filteredEntries.count))")
        .frame(minWidth: 300)
    }

    private var emptyState: some View {
        let hasSearch = !appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let message: String
        let detail: String

        if !appState.isMonitoring {
            message = "No log entries"
            detail  = "Press Start to begin monitoring LLM directories"
        } else if hasSearch {
            message = "No matching entries"
            detail  = "Try a different search term or platform filter"
        } else {
            message = "Waiting for activity…"
            detail  = "Agent Blackbox will record entries as LLM tools write to their log directories"
        }

        return VStack(spacing: 14) {
            Image(systemName: hasSearch ? "magnifyingglass" : "tray")
                .font(.system(size: 46))
                .foregroundColor(.secondary)
            Text(message)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundColor(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct LogRowView: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Platform + model + relative time
            HStack(spacing: 4) {
                Image(systemName: entry.platform.iconName)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(entry.platform.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                if let model = entry.model, !model.isEmpty {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(model)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }

            // Prompt preview
            Text(entry.promptPreview)
                .font(.body)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Token summary
            if !entry.tokenSummary.isEmpty {
                Label(entry.tokenSummary, systemImage: "number.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
