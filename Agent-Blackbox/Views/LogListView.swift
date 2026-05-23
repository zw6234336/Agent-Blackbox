import SwiftUI

struct LogListView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var searchText = ""
    @State private var selectedLog: ParsedLog?
    @State private var searchResults: [ParsedLog] = []
    @State private var showFilters = false
    
    // Filter states
    @State private var filterProvider: LLMProvider? = nil
    @State private var filterModel: String? = nil
    @State private var filterHasError: Bool? = nil
    @State private var filterBookmarked = false
    @State private var availableModels: [String] = []
    @State private var availableProviders: [LLMProvider] = []

    private var filteredLogs: [ParsedLog] {
        if !searchText.isEmpty {
            return searchResults
        }
        if filterProvider != nil || filterModel != nil || filterHasError != nil || filterBookmarked {
            return database.filterLogs(
                provider: filterProvider,
                model: filterModel,
                hasError: filterHasError,
                bookmarkedOnly: filterBookmarked
            )
        }
        return database.logs
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Filter bar
                filterBar
                
                // Filter panel
                if showFilters {
                    filterPanel
                }
                
                // Log list
                List(filteredLogs, selection: $selectedLog) { log in
                    LogListRow(log: log) {
                        Task { await database.toggleBookmark(logId: log.id) }
                    }
                }
                .searchable(text: $searchText, prompt: "搜索日志...")
            }
        } detail: {
            if let log = selectedLog {
                LogDetailView(log: log)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("选择一条日志查看详情")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await database.reloadLogs()
            refreshSearchResults()
            availableModels = database.fetchDistinctModels()
            availableProviders = database.fetchDistinctProviders()
        }
        .onChange(of: searchText) {
            refreshSearchResults()
        }
        .onChange(of: database.logs) {
            refreshSearchResults()
        }
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        HStack {
            Button(action: { withAnimation { showFilters.toggle() } }) {
                Label("过滤", systemImage: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.plain)
            
            if filterProvider != nil || filterModel != nil || filterHasError != nil || filterBookmarked {
                Button("清除过滤") {
                    filterProvider = nil
                    filterModel = nil
                    filterHasError = nil
                    filterBookmarked = false
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentGradientStart)
            }
            
            Spacer()
            
            Text("\(filteredLogs.count) 条日志")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Filter Panel
    
    private var filterPanel: some View {
        VStack(spacing: 8) {
            HStack {
                // Provider filter
                Picker("提供商", selection: $filterProvider) {
                    Text("全部").tag(LLMProvider?.none)
                    ForEach(availableProviders) { provider in
                        Text(provider.displayName).tag(Optional(provider))
                    }
                }
                .frame(maxWidth: 150)
                
                // Model filter  
                Picker("模型", selection: $filterModel) {
                    Text("全部").tag(String?.none)
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(Optional(model))
                    }
                }
                .frame(maxWidth: 200)
                
                // Error filter
                Picker("错误", selection: $filterHasError) {
                    Text("全部").tag(Bool?.none)
                    Text("仅错误").tag(Optional(true))
                    Text("无错误").tag(Optional(false))
                }
                .frame(maxWidth: 120)
                
                Toggle("仅收藏", isOn: $filterBookmarked)
            }
            .padding(.horizontal)
            
            Divider()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func refreshSearchResults() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        searchResults = database.searchLogs(query: searchText)
    }
}

// MARK: - Log List Row

struct LogListRow: View {
    let log: ParsedLog
    let onBookmarkToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Provider icon
            Image(systemName: log.provider?.iconName ?? "doc.text")
                .font(.caption)
                .foregroundStyle(log.provider?.brandColor ?? .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(log.modelName ?? "Unknown Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let provider = log.provider {
                        Text(provider.displayName)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(provider.brandColor.opacity(0.15))
                            .foregroundStyle(provider.brandColor)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let tokens = log.totalTokens {
                        Label("\(tokens.formattedCompact)", systemImage: "textformat.abc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let cost = log.estimatedCost {
                        Text(cost.formattedCurrency)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if log.errorMessage != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Text(log.timestamp.formattedRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Bookmark button
            Button(action: onBookmarkToggle) {
                Image(systemName: log.isBookmarked ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(log.isBookmarked ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
