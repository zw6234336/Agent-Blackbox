import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var selectedCollection: LogCollection?
    @State private var collectionLogs: [ParsedLog] = []

    var body: some View {
        HStack(spacing: 0) {
            collectionsSidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                .background(Color(nsColor: NSColor.windowBackgroundColor))
            
            Divider()
            
            Group {
                if let collection = selectedCollection {
                    collectionDetail(collection)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dashboardBackground)
        }
    }

    // MARK: - Sidebar

    private var collectionsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("收藏管理")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            List(selection: $selectedCollection) {
                Section("收藏夹") {
                    ForEach(database.collections) { collection in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentGradientStart)
                            VStack(alignment: .leading) {
                                Text(collection.name)
                                    .fontWeight(.medium)
                                Text("\(collection.logIds.count) 条日志")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(collection)
                        .contextMenu {
                            Button(role: .destructive) {
                                database.deleteCollection(id: collection.id)
                                if selectedCollection?.id == collection.id {
                                    selectedCollection = nil
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }

                Section("已收藏") {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("收藏的日志")
                        Spacer()
                        Text("\(database.bookmarkedCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("ShowNewCollectionSheet"), object: nil)
            }) {
                Label("新建收藏夹", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }

    // MARK: - Collection Detail

    private func collectionDetail(_ collection: LogCollection) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(collection.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    if !collection.description.isEmpty {
                        Text(collection.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        if let url = database.exportCollection(id: collection.id, format: .json) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Label("导出 JSON", systemImage: "doc.text")
                    }

                    Button {
                        if let url = database.exportCollection(id: collection.id, format: .csv) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } label: {
                        Label("导出 CSV", systemImage: "tablecells")
                    }
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
            }
            .padding()

            Divider()

            // Logs list
            List(collectionLogs) { log in
                CollectionLogRow(log: log) {
                    database.removeFromCollection(logId: log.id, collectionId: collection.id)
                    collectionLogs = database.fetchLogsInCollection(id: collection.id)
                }
            }
        }
        .onAppear {
            collectionLogs = database.fetchLogsInCollection(id: collection.id)
        }
        .onChange(of: selectedCollection) {
            if let col = selectedCollection {
                collectionLogs = database.fetchLogsInCollection(id: col.id)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("选择或创建收藏夹")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("在日志列表中点击 ⭐ 收藏日志，或将日志添加到收藏夹中")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NewCollectionSheet: View {
    let onCancel: () -> Void
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var description = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case description
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("新建收藏夹")
                .font(.headline)

            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)

            TextField("描述（可选）", text: $description)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .description)

            HStack {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("创建") {
                    guard !name.isEmpty else { return }
                    onCreate(name, description)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .name
            }
        }
    }
}

// MARK: - Collection Log Row

struct CollectionLogRow: View {
    let log: ParsedLog
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: log.provider?.iconName ?? "doc.text")
                .foregroundStyle(log.provider?.brandColor ?? .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.modelName ?? "Unknown Model")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if let provider = log.provider {
                        Text(provider.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(provider.brandColor.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if let tokens = log.totalTokens {
                        Text("\(tokens.formattedCompact) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(log.timestamp.formattedRelative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let prompt = log.prompt {
                Text(String(prompt.prefix(60)) + (prompt.count > 60 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 200, alignment: .leading)
            }

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Color.errorRed)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
