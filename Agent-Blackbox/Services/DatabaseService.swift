import Foundation
import SQLite

@MainActor
final class DatabaseService: ObservableObject {
    @Published var logs: [ParsedLog] = []
    @Published private(set) var totalLogCount: Int = 0
    @Published private(set) var errorLogCount: Int = 0
    @Published private(set) var bookmarkedCount: Int = 0
    @Published var collections: [LogCollection] = []
    @Published var dashboardStats: DashboardStats = DashboardStats()

    private var db: Connection?

    // MARK: - Table Definitions
    private let logsTable = Table("logs")
    private let id = SQLite.Expression<String>("id")
    private let timestamp = SQLite.Expression<Double>("timestamp")
    private let sourceFile = SQLite.Expression<String>("source_file")
    private let providerRaw = SQLite.Expression<String?>("provider")
    private let modelName = SQLite.Expression<String?>("model_name")
    private let prompt = SQLite.Expression<String?>("prompt")
    private let response = SQLite.Expression<String?>("response")
    private let promptTokens = SQLite.Expression<Int?>("prompt_tokens")
    private let completionTokens = SQLite.Expression<Int?>("completion_tokens")
    private let totalTokens = SQLite.Expression<Int?>("total_tokens")
    private let estimatedCost = SQLite.Expression<Double?>("estimated_cost")
    private let duration = SQLite.Expression<Double?>("duration")
    private let statusCode = SQLite.Expression<Int?>("status_code")
    private let errorMessage = SQLite.Expression<String?>("error_message")
    private let isBookmarked = SQLite.Expression<Bool>("is_bookmarked")
    private let tagsJSON = SQLite.Expression<String>("tags_json")
    private let notes = SQLite.Expression<String?>("notes")
    private let conversationId = SQLite.Expression<String?>("conversation_id")
    private let metadataJSON = SQLite.Expression<String>("metadata_json")

    // Collections table
    private let collectionsTable = Table("collections")
    private let collectionId = SQLite.Expression<String>("id")
    private let collectionName = SQLite.Expression<String>("name")
    private let collectionDesc = SQLite.Expression<String>("description")
    private let collectionCreatedAt = SQLite.Expression<Double>("created_at")

    // Collection-Logs junction table
    private let collectionLogsTable = Table("collection_logs")
    private let clCollectionId = SQLite.Expression<String>("collection_id")
    private let clLogId = SQLite.Expression<String>("log_id")

    // MARK: - Initialization

    func initializeIfNeeded() {
        guard db == nil else { return }

        do {
            let dbURL = Self.defaultDatabaseURL
            try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            db = try Connection(dbURL.path)

            // Create logs table with all fields
            try db?.run(logsTable.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(timestamp)
                t.column(sourceFile)
                t.column(providerRaw)
                t.column(modelName)
                t.column(prompt)
                t.column(response)
                t.column(promptTokens)
                t.column(completionTokens)
                t.column(totalTokens)
                t.column(estimatedCost)
                t.column(duration)
                t.column(statusCode)
                t.column(errorMessage)
                t.column(isBookmarked, defaultValue: false)
                t.column(tagsJSON, defaultValue: "[]")
                t.column(notes)
                t.column(conversationId)
                t.column(metadataJSON, defaultValue: "{}")
            })

            // Create indexes
            try db?.run(logsTable.createIndex(sourceFile, ifNotExists: true))
            try db?.run(logsTable.createIndex(timestamp, ifNotExists: true))
            try db?.run(logsTable.createIndex(isBookmarked, ifNotExists: true))

            // Migrate: add new columns if they don't exist (for existing DBs)
            migrateSchema()

            // Create collections table
            try db?.run(collectionsTable.create(ifNotExists: true) { t in
                t.column(collectionId, primaryKey: true)
                t.column(collectionName)
                t.column(collectionDesc, defaultValue: "")
                t.column(collectionCreatedAt)
            })

            // Create collection_logs junction table
            try db?.run(collectionLogsTable.create(ifNotExists: true) { t in
                t.column(clCollectionId)
                t.column(clLogId)
                t.primaryKey(clCollectionId, clLogId)
            })

            loadCollections()
        } catch {
            Logger.shared.error("数据库初始化失败: \(error.localizedDescription)")
        }
    }

    private func migrateSchema() {
        // Safely add columns that might not exist in older databases
        let columnsToAdd: [(String, String)] = [
            ("provider", "TEXT"),
            ("prompt_tokens", "INTEGER"),
            ("completion_tokens", "INTEGER"),
            ("total_tokens", "INTEGER"),
            ("estimated_cost", "REAL"),
            ("duration", "REAL"),
            ("status_code", "INTEGER"),
            ("is_bookmarked", "INTEGER DEFAULT 0"),
            ("tags_json", "TEXT DEFAULT '[]'"),
            ("notes", "TEXT"),
            ("conversation_id", "TEXT"),
        ]

        for (col, type) in columnsToAdd {
            do {
                try db?.run("ALTER TABLE logs ADD COLUMN \(col) \(type)")
            } catch {
                // Column likely already exists, ignore
            }
        }
    }

    // MARK: - Log CRUD

    func saveLog(_ log: ParsedLog) async {
        guard let db else { return }

        do {
            let metadata = (try? String(data: JSONSerialization.data(withJSONObject: log.metadata), encoding: .utf8)) ?? "{}"
            let tags = (try? String(data: JSONSerialization.data(withJSONObject: log.tags), encoding: .utf8)) ?? "[]"

            let insert = logsTable.insert(or: .ignore,
                                          id <- log.id.uuidString,
                                          timestamp <- log.timestamp.timeIntervalSince1970,
                                          sourceFile <- log.sourceFile,
                                          providerRaw <- log.provider?.rawValue,
                                          modelName <- log.modelName,
                                          prompt <- log.prompt,
                                          response <- log.response,
                                          promptTokens <- log.promptTokens,
                                          completionTokens <- log.completionTokens,
                                          totalTokens <- log.totalTokens,
                                          estimatedCost <- log.estimatedCost,
                                          duration <- log.duration,
                                          statusCode <- log.statusCode,
                                          errorMessage <- log.errorMessage,
                                          isBookmarked <- log.isBookmarked,
                                          tagsJSON <- tags,
                                          notes <- log.notes,
                                          conversationId <- log.conversationId,
                                          metadataJSON <- metadata)
            try db.run(insert)
            await reloadLogs()
        } catch {
            Logger.shared.error("日志保存失败: \(error.localizedDescription)")
        }
    }

    func reloadLogs(limit: Int = 100, offset: Int = 0) async {
        applySnapshot(fetchLogs(limit: limit, offset: offset))
        updateCountersFromDatabase()
        refreshDashboardStats()
    }

    func fetchLogs(limit: Int = 100, offset: Int = 0) -> [ParsedLog] {
        guard let db else { return [] }

        do {
            return try db.prepare(logsTable.order(timestamp.desc).limit(limit, offset: offset)).map(rowToParsedLog)
        } catch {
            Logger.shared.error("日志查询失败: \(error.localizedDescription)")
            return []
        }
    }

    func searchLogs(query: String) -> [ParsedLog] {
        guard let db else { return [] }
        let like = "%\(query)%"

        do {
            let queryTable = logsTable
                .filter(
                    sourceFile.like(like) ||
                    (modelName ?? "").like(like) ||
                    (prompt ?? "").like(like) ||
                    (response ?? "").like(like) ||
                    (providerRaw ?? "").like(like)
                )
                .order(timestamp.desc)
            return try db.prepare(queryTable).map(rowToParsedLog)
        } catch {
            Logger.shared.error("日志搜索失败: \(error.localizedDescription)")
            return []
        }
    }

    func filterLogs(
        provider: LLMProvider? = nil,
        model: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        hasError: Bool? = nil,
        bookmarkedOnly: Bool = false
    ) -> [ParsedLog] {
        guard let db else { return [] }

        do {
            var query = logsTable.order(timestamp.desc)

            if let provider {
                query = query.filter(providerRaw == provider.rawValue)
            }
            if let model, !model.isEmpty {
                query = query.filter(modelName == model)
            }
            if let startDate {
                query = query.filter(timestamp >= startDate.timeIntervalSince1970)
            }
            if let endDate {
                query = query.filter(timestamp <= endDate.timeIntervalSince1970)
            }
            if let hasError {
                if hasError {
                    query = query.filter(errorMessage != nil && (errorMessage ?? "") != "")
                } else {
                    query = query.filter(errorMessage == nil || (errorMessage ?? "") == "")
                }
            }
            if bookmarkedOnly {
                query = query.filter(isBookmarked == true)
            }

            return try db.prepare(query.limit(500)).map(rowToParsedLog)
        } catch {
            Logger.shared.error("日志过滤失败: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Bookmark Management

    func toggleBookmark(logId: UUID) async {
        guard let db else { return }
        do {
            let target = logsTable.filter(id == logId.uuidString)
            if let row = try db.pluck(target) {
                let current = row[isBookmarked]
                try db.run(target.update(isBookmarked <- !current))
                await reloadLogs()
            }
        } catch {
            Logger.shared.error("收藏切换失败: \(error.localizedDescription)")
        }
    }

    func updateNotes(logId: UUID, text: String) async {
        guard let db else { return }
        do {
            try db.run(logsTable.filter(id == logId.uuidString).update(notes <- text))
            await reloadLogs()
        } catch {
            Logger.shared.error("备注更新失败: \(error.localizedDescription)")
        }
    }

    func updateTags(logId: UUID, newTags: [String]) async {
        guard let db else { return }
        do {
            let tagsStr = (try? String(data: JSONSerialization.data(withJSONObject: newTags), encoding: .utf8)) ?? "[]"
            try db.run(logsTable.filter(id == logId.uuidString).update(tagsJSON <- tagsStr))
            await reloadLogs()
        } catch {
            Logger.shared.error("标签更新失败: \(error.localizedDescription)")
        }
    }

    func fetchBookmarkedLogs() -> [ParsedLog] {
        guard let db else { return [] }
        do {
            return try db.prepare(logsTable.filter(isBookmarked == true).order(timestamp.desc)).map(rowToParsedLog)
        } catch {
            Logger.shared.error("收藏查询失败: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Collection Management

    func createCollection(name: String, description: String = "") {
        guard let db else { return }
        let collection = LogCollection(name: name, description: description)
        do {
            try db.run(collectionsTable.insert(
                collectionId <- collection.id.uuidString,
                collectionName <- collection.name,
                collectionDesc <- collection.description,
                collectionCreatedAt <- collection.createdAt.timeIntervalSince1970
            ))
            loadCollections()
        } catch {
            Logger.shared.error("创建收藏集失败: \(error.localizedDescription)")
        }
    }

    func deleteCollection(id colId: UUID) {
        guard let db else { return }
        do {
            try db.run(collectionsTable.filter(collectionId == colId.uuidString).delete())
            try db.run(collectionLogsTable.filter(clCollectionId == colId.uuidString).delete())
            loadCollections()
        } catch {
            Logger.shared.error("删除收藏集失败: \(error.localizedDescription)")
        }
    }

    func addToCollection(logId: UUID, collectionId colId: UUID) {
        guard let db else { return }
        do {
            try db.run(collectionLogsTable.insert(or: .ignore,
                clCollectionId <- colId.uuidString,
                clLogId <- logId.uuidString
            ))
            loadCollections()
        } catch {
            Logger.shared.error("添加到收藏集失败: \(error.localizedDescription)")
        }
    }

    func removeFromCollection(logId: UUID, collectionId colId: UUID) {
        guard let db else { return }
        do {
            try db.run(collectionLogsTable
                .filter(clCollectionId == colId.uuidString && clLogId == logId.uuidString)
                .delete())
            loadCollections()
        } catch {
            Logger.shared.error("从收藏集移除失败: \(error.localizedDescription)")
        }
    }

    func fetchLogsInCollection(id colId: UUID) -> [ParsedLog] {
        guard let db else { return [] }
        do {
            let join = logsTable.join(collectionLogsTable,
                on: id == clLogId)
                .filter(clCollectionId == colId.uuidString)
                .order(timestamp.desc)
            return try db.prepare(join).map(rowToParsedLog)
        } catch {
            Logger.shared.error("收藏集查询失败: \(error.localizedDescription)")
            return []
        }
    }

    private func loadCollections() {
        guard let db else { return }
        do {
            collections = try db.prepare(collectionsTable.order(collectionCreatedAt.desc)).map { row in
                let cId = UUID(uuidString: row[collectionId]) ?? UUID()
                let logIds = (try? db.prepare(collectionLogsTable.filter(clCollectionId == row[collectionId])))?.compactMap { r in
                    UUID(uuidString: r[clLogId])
                } ?? []
                return LogCollection(
                    id: cId,
                    name: row[collectionName],
                    description: row[collectionDesc],
                    createdAt: Date(timeIntervalSince1970: row[collectionCreatedAt]),
                    logIds: logIds
                )
            }
        } catch {
            Logger.shared.error("加载收藏集失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Dashboard Statistics

    func refreshDashboardStats(days: Int? = 7) {
        guard let db else { return }

        var stats = DashboardStats()

        do {
            let filterTable: Table
            let startTimestamp: Double?
            if let days = days {
                let limitDate = Date().addingTimeInterval(-Double(days) * 24 * 3600).timeIntervalSince1970
                filterTable = logsTable.filter(timestamp >= limitDate)
                startTimestamp = limitDate
            } else {
                filterTable = logsTable
                startTimestamp = nil
            }

            // Total calls
            stats.totalCalls = try db.scalar(filterTable.count)

            // Token sums
            stats.totalPromptTokens = try db.scalar(filterTable.select(promptTokens.sum)) ?? 0
            stats.totalCompletionTokens = try db.scalar(filterTable.select(completionTokens.sum)) ?? 0
            stats.totalTokens = try db.scalar(filterTable.select(totalTokens.sum)) ?? 0
            if stats.totalTokens == 0 {
                stats.totalTokens = stats.totalPromptTokens + stats.totalCompletionTokens
            }

            // Cost sum
            stats.totalCost = try db.scalar(filterTable.select(estimatedCost.sum)) ?? 0.0

            // Error count
            stats.errorCount = try db.scalar(
                filterTable.filter(errorMessage != nil && (errorMessage ?? "") != "").count
            )

            // Average response time
            stats.avgResponseTime = try db.scalar(filterTable.select(duration.average)) ?? 0.0

            // Calls by provider
            var providerQuery = "SELECT provider, COUNT(*) as cnt FROM logs WHERE provider IS NOT NULL "
            if let start = startTimestamp {
                providerQuery += "AND timestamp >= \(start) "
            }
            providerQuery += "GROUP BY provider ORDER BY cnt DESC"
            for row in try db.prepare(providerQuery) {
                if let pStr = row[0] as? String, let provider = LLMProvider(rawValue: pStr),
                   let count = row[1] as? Int64 {
                    stats.callsByProvider[provider] = Int(count)
                }
            }

            // Calls by model
            var modelQuery = "SELECT model_name, COUNT(*) as cnt FROM logs WHERE model_name IS NOT NULL "
            if let start = startTimestamp {
                modelQuery += "AND timestamp >= \(start) "
            }
            modelQuery += "GROUP BY model_name ORDER BY cnt DESC LIMIT 20"
            for row in try db.prepare(modelQuery) {
                if let mName = row[0] as? String, let count = row[1] as? Int64 {
                    stats.callsByModel[mName] = Int(count)
                }
            }

            // Tokens by day
            let daysLimit = days ?? 90
            let limitVal = Date().addingTimeInterval(-Double(daysLimit) * 24 * 3600).timeIntervalSince1970
            let dayQuery = """
                SELECT date(timestamp, 'unixepoch', 'localtime') as day,
                       COALESCE(SUM(prompt_tokens), 0) as pt,
                       COALESCE(SUM(completion_tokens), 0) as ct
                FROM logs
                WHERE timestamp >= \(limitVal)
                GROUP BY day
                ORDER BY day ASC
            """
            for row in try db.prepare(dayQuery) {
                if let dayStr = row[0] as? String,
                   let pt = row[1] as? Int64,
                   let ct = row[2] as? Int64 {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let date = formatter.date(from: dayStr) {
                        stats.tokensByDay.append(DayTokens(
                            date: date,
                            promptTokens: Int(pt),
                            completionTokens: Int(ct)
                        ))
                    }
                }
            }

            // Recent logs
            stats.recentLogs = fetchLogs(limit: 10)

        } catch {
            Logger.shared.error("Dashboard 统计刷新失败: \(error.localizedDescription)")
        }

        dashboardStats = stats
    }

    // MARK: - Rate Limit Aggregations

    /// 区间内的所有日志（按时间正序），用于滑动窗口/并发计算
    func fetchLogs(provider: LLMProvider?, since: Date, until: Date = Date()) -> [ParsedLog] {
        guard let db else { return [] }
        do {
            var q = logsTable
                .filter(timestamp >= since.timeIntervalSince1970 && timestamp <= until.timeIntervalSince1970)
                .order(timestamp.asc)
            if let provider {
                q = q.filter(providerRaw == provider.rawValue)
            }
            return try db.prepare(q).map(rowToParsedLog)
        } catch {
            Logger.shared.error("区间日志查询失败: \(error.localizedDescription)")
            return []
        }
    }

    /// 区间内的聚合（请求数 / token / cost / 平均时长），不分 provider 也支持
    struct UsageAggregate {
        var requestCount: Int = 0
        var totalTokens: Int = 0
        var totalCost: Double = 0
        var avgDuration: Double = 0
    }

    func aggregateUsage(provider: LLMProvider?, since: Date, until: Date = Date()) -> UsageAggregate {
        guard let db else { return UsageAggregate() }
        do {
            var q = logsTable.filter(timestamp >= since.timeIntervalSince1970 && timestamp <= until.timeIntervalSince1970)
            if let provider {
                q = q.filter(providerRaw == provider.rawValue)
            }
            var agg = UsageAggregate()
            agg.requestCount = try db.scalar(q.count)
            agg.totalTokens = try db.scalar(q.select(totalTokens.sum)) ?? 0
            if agg.totalTokens == 0 {
                let pt = try db.scalar(q.select(promptTokens.sum)) ?? 0
                let ct = try db.scalar(q.select(completionTokens.sum)) ?? 0
                agg.totalTokens = pt + ct
            }
            agg.totalCost = try db.scalar(q.select(estimatedCost.sum)) ?? 0.0
            agg.avgDuration = try db.scalar(q.select(duration.average)) ?? 0.0
            return agg
        } catch {
            Logger.shared.error("区间聚合失败: \(error.localizedDescription)")
            return UsageAggregate()
        }
    }

    func fetchDistinctModels() -> [String] {
        guard let db else { return [] }
        do {
            return try db.prepare(logsTable.select(distinct: modelName).filter(modelName != nil)).compactMap { $0[modelName] }
        } catch {
            return []
        }
    }

    func fetchDistinctProviders() -> [LLMProvider] {
        guard let db else { return [] }
        do {
            return try db.prepare(logsTable.select(distinct: providerRaw).filter(providerRaw != nil)).compactMap {
                guard let raw = $0[providerRaw] else { return nil }
                return LLMProvider(rawValue: raw)
            }
        } catch {
            return []
        }
    }

    // MARK: - Export

    func exportLogs(format: ExportFormat) -> URL? {
        guard let db else { return nil }

        let fileManager = FileManager.default
        let exportFolder = Self.defaultDatabaseURL.deletingLastPathComponent().appendingPathComponent("Exports", isDirectory: true)
        try? fileManager.createDirectory(at: exportFolder, withIntermediateDirectories: true, attributes: nil)

        let filename = "logs-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let fileURL = exportFolder.appendingPathComponent(filename)

        do {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }

            let rows = try db.prepare(logsTable.order(timestamp.desc))
            switch format {
            case .json:
                try handle.write(contentsOf: Data("[".utf8))
                var first = true
                for row in rows {
                    let log = rowToParsedLog(row)
                    let encoded = try JSONEncoder.pretty.encode(log)
                    if first {
                        first = false
                    } else {
                        try handle.write(contentsOf: Data(",".utf8))
                    }
                    try handle.write(contentsOf: encoded)
                }
                try handle.write(contentsOf: Data("]".utf8))
            case .csv:
                try handle.write(contentsOf: Data("id,timestamp,provider,model,promptTokens,completionTokens,totalTokens,cost,duration,error\n".utf8))
                for row in rows {
                    let log = rowToParsedLog(row)
                    let line = "\(log.id.uuidString),\(log.timestamp.timeIntervalSince1970),\(escapeCSV(log.provider?.displayName ?? "")),\(escapeCSV(log.modelName ?? "")),\(log.promptTokens.map(String.init) ?? ""),\(log.completionTokens.map(String.init) ?? ""),\(log.totalTokens.map(String.init) ?? ""),\(log.estimatedCost.map { String(format: "%.6f", $0) } ?? ""),\(log.duration.map { String(format: "%.3f", $0) } ?? ""),\(escapeCSV(log.errorMessage ?? ""))\n"
                    try handle.write(contentsOf: Data(line.utf8))
                }
            }
            return fileURL
        } catch {
            Logger.shared.error("日志导出失败: \(error.localizedDescription)")
            return nil
        }
    }

    func exportCollection(id colId: UUID, format: ExportFormat) -> URL? {
        let collectionLogs = fetchLogsInCollection(id: colId)
        guard !collectionLogs.isEmpty else { return nil }

        let exportFolder = Self.defaultDatabaseURL.deletingLastPathComponent().appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true, attributes: nil)

        let collection = collections.first { $0.id == colId }
        let safeName = (collection?.name ?? "collection").replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeName)-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let fileURL = exportFolder.appendingPathComponent(filename)

        do {
            let encoded = try JSONEncoder.pretty.encode(collectionLogs)
            try encoded.write(to: fileURL)
            return fileURL
        } catch {
            Logger.shared.error("收藏集导出失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Clear

    func clearAllLogs() async {
        guard let db else { return }
        do {
            try db.run(logsTable.delete())
            await reloadLogs()
        } catch {
            Logger.shared.error("清空数据库失败: \(error.localizedDescription)")
        }
    }

    /// 删除已知由旧解析器写入的脏数据：
    ///   1. 模型名为 n_ctx / 7.27 / FileNotFoundError / OpenAiChatModel.builder 等污染条目
    ///   2. provider=anthropic 且 modelName="claude-code" 且无 token 的旧 history.jsonl 记录（重扫后会被新 parser 替换）
    @discardableResult
    func cleanupGarbageLogs() async -> Int {
        guard let db else { return 0 }
        var deleted = 0
        do {
            // 1) 模型名污染
            let blocklistSQL = """
                DELETE FROM logs WHERE
                  model_name IS NOT NULL AND (
                    LENGTH(model_name) < 3
                    OR LOWER(model_name) IN ('n_ctx','n_batch','n_gpu_layers','n_threads',
                        'rope_freq_base','rope_freq_scale','filenotfounderror','valueerror',
                        'typeerror','runtimeerror','indexerror','keyerror','modulenotfounderror',
                        'permissionerror','true','false','none','null','openaichatmodel.builder')
                    OR model_name GLOB '[0-9]*.[0-9]*'
                  )
            """
            try db.run(blocklistSQL)
            deleted += db.changes

            // 2) 老 claude-code 行（无 token，几千条）
            let claudeSQL = """
                DELETE FROM logs WHERE
                  provider='anthropic' AND model_name='claude-code'
                  AND (total_tokens IS NULL OR total_tokens = 0)
                  AND (prompt_tokens IS NULL OR prompt_tokens = 0)
            """
            try db.run(claudeSQL)
            deleted += db.changes

            await reloadLogs()
            Logger.shared.info("脏数据清理完成：删除 \(deleted) 条")
        } catch {
            Logger.shared.error("脏数据清理失败: \(error.localizedDescription)")
        }
        return deleted
    }

    // MARK: - Helpers

    private func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func rowToParsedLog(_ row: Row) -> ParsedLog {
        let metadataData = row[metadataJSON].data(using: .utf8) ?? Data("{}".utf8)
        let metadata = (try? JSONSerialization.jsonObject(with: metadataData) as? [String: String]) ?? [:]

        let tagsData = row[tagsJSON].data(using: .utf8) ?? Data("[]".utf8)
        let tags = (try? JSONSerialization.jsonObject(with: tagsData) as? [String]) ?? []

        let provider: LLMProvider? = row[providerRaw].flatMap { LLMProvider(rawValue: $0) }

        return ParsedLog(
            id: UUID(uuidString: row[id]) ?? UUID(),
            timestamp: Date(timeIntervalSince1970: row[timestamp]),
            sourceFile: row[sourceFile],
            provider: provider,
            modelName: row[modelName],
            prompt: row[prompt],
            response: row[response],
            promptTokens: row[promptTokens],
            completionTokens: row[completionTokens],
            totalTokens: row[totalTokens],
            estimatedCost: row[estimatedCost],
            duration: row[duration],
            statusCode: row[statusCode],
            errorMessage: row[errorMessage],
            isBookmarked: row[isBookmarked],
            tags: tags,
            notes: row[notes],
            conversationId: row[conversationId],
            metadata: metadata
        )
    }

    private func applySnapshot(_ newLogs: [ParsedLog]) {
        logs = newLogs
    }

    // MARK: - Trend / Stats queries

    func fetchStats(from startDate: Date, to endDate: Date) -> LogStats {
        guard let db else {
            return LogStats(totalCount: 0, errorCount: 0, totalTokens: 0, activeModels: 0)
        }
        let startTs = startDate.timeIntervalSince1970
        let endTs = endDate.timeIntervalSince1970
        let range = logsTable.filter(timestamp >= startTs && timestamp <= endTs)
        do {
            let total = try db.scalar(range.count)
            let errors = try db.scalar(
                range.filter(errorMessage != nil && (errorMessage ?? "") != "").count
            )
            let totalTokens = (try db.scalar(range.select(totalTokens.sum))) ?? 0
            let modelRows = try db.prepare(range.select(modelName).filter(modelName != nil))
            let models = Set(modelRows.compactMap { $0[modelName] })
            return LogStats(
                totalCount: total,
                errorCount: errors,
                totalTokens: totalTokens,
                activeModels: models.count
            )
        } catch {
            Logger.shared.error("统计数据查询失败: \(error.localizedDescription)")
            return LogStats(totalCount: 0, errorCount: 0, totalTokens: 0, activeModels: 0)
        }
    }

    func fetchTrend(from startDate: Date, to endDate: Date, bucketCount: Int = 24) -> [TrendPoint] {
        guard let db else { return [] }
        let startTs = startDate.timeIntervalSince1970
        let endTs = endDate.timeIntervalSince1970
        guard endTs > startTs, bucketCount > 0 else { return [] }
        let bucketInterval = (endTs - startTs) / Double(bucketCount)
        let range = logsTable.filter(timestamp >= startTs && timestamp <= endTs)
        do {
            let rows = try db.prepare(range.select(timestamp, errorMessage))
            var counts = Array(repeating: 0, count: bucketCount)
            var errorCounts = Array(repeating: 0, count: bucketCount)
            for row in rows {
                let t = row[timestamp]
                let idx = Int((t - startTs) / bucketInterval)
                guard idx >= 0 && idx < bucketCount else { continue }
                counts[idx] += 1
                if let err = row[errorMessage], !err.isEmpty {
                    errorCounts[idx] += 1
                }
            }
            return (0..<bucketCount).map { i in
                TrendPoint(
                    date: Date(timeIntervalSince1970: startTs + Double(i) * bucketInterval),
                    count: counts[i],
                    errorCount: errorCounts[i]
                )
            }
        } catch {
            Logger.shared.error("趋势数据查询失败: \(error.localizedDescription)")
            return []
        }
    }

    private func updateCountersFromDatabase() {
        guard let db else {
            totalLogCount = logs.count
            errorLogCount = logs.lazy.filter { $0.errorMessage != nil }.count
            bookmarkedCount = logs.lazy.filter { $0.isBookmarked }.count
            return
        }
        do {
            totalLogCount = try db.scalar(logsTable.count)
            errorLogCount = try db.scalar(
                logsTable
                    .filter(errorMessage != nil && (errorMessage ?? "") != "")
                    .count
            )
            bookmarkedCount = try db.scalar(
                logsTable.filter(isBookmarked == true).count
            )
        } catch {
            totalLogCount = logs.count
            errorLogCount = logs.lazy.filter { $0.errorMessage != nil }.count
            bookmarkedCount = logs.lazy.filter { $0.isBookmarked }.count
            Logger.shared.error("统计计数更新失败: \(error.localizedDescription)")
        }
    }

    static var defaultDatabaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Agent-Blackbox", isDirectory: true)
            .appendingPathComponent("logs.db")
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case json

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }
}

struct LogStats {
    let totalCount: Int
    let errorCount: Int
    let totalTokens: Int
    let activeModels: Int
}

struct TrendPoint: Identifiable {
    let id: UUID = UUID()
    let date: Date
    let count: Int
    let errorCount: Int

    var normalCount: Int { max(0, count - errorCount) }
}
