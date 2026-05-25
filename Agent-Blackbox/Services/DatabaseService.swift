import Foundation
@preconcurrency import SQLite

@MainActor
final class DatabaseService: ObservableObject {
    @Published var logs: [ParsedLog] = []
    @Published private(set) var totalLogCount: Int = 0
    @Published private(set) var errorLogCount: Int = 0
    @Published private(set) var bookmarkedCount: Int = 0
    @Published var collections: [LogCollection] = []
    @Published var dashboardStats: DashboardStats = DashboardStats()
    private var lastDashboardDays: Int? = 0

    nonisolated(unsafe) private var db: Connection?

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
            
            // Enable WAL mode for high-concurrency writes
            try db?.execute("PRAGMA journal_mode = WAL;")

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

        // Clean up historically misclassified Pi logs from other tools' folders
        do {
            let cleanupQuery = """
                DELETE FROM logs 
                WHERE provider = 'pi' 
                  AND (
                    source_file LIKE '%/Code/logs/%' 
                    OR source_file LIKE '%/Cursor/logs/%' 
                    OR source_file LIKE '%/saoudrizwan.claude-dev/%' 
                    OR source_file LIKE '%/dev.warp.Warp-Stable/%'
                  )
            """
            try db?.run(cleanupQuery)
        } catch {
            Logger.shared.error("历史误判日志清理失败: \(error.localizedDescription)")
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
                                          estimatedCost <- nil,
                                          duration <- log.duration,
                                          statusCode <- log.statusCode,
                                          errorMessage <- log.errorMessage,
                                          isBookmarked <- log.isBookmarked,
                                          tagsJSON <- tags,
                                          notes <- log.notes,
                                          conversationId <- log.conversationId,
                                          metadataJSON <- metadata)
            try db.run(insert)
            // 轻量更新：仅当新行被成功插入时更新内存状态（避免全量 reloadLogs）
            guard db.changes > 0 else { return }
            var updated = logs
            updated.insert(log, at: 0)
            if updated.count > 100 { updated.removeLast() }
            logs = updated
            totalLogCount += 1
            if let err = log.errorMessage, !err.isEmpty { errorLogCount += 1 }
            if log.isBookmarked { bookmarkedCount += 1 }
            refreshDashboardStats()
        } catch {
            Logger.shared.error("日志保存失败: \(error.localizedDescription)")
        }
    }

    /// 批量插入日志（使用事务），完成后仅做一次全量 reload。
    /// 用于初始扫描等批量写入场景，避免每条日志触发一次 reload。
    func saveLogs(_ logsToSave: [ParsedLog]) async {
        guard let db, !logsToSave.isEmpty else { return }
        do {
            var insertedCount = 0
            try db.transaction {
                for log in logsToSave {
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
                                                  estimatedCost <- nil,
                                                  duration <- log.duration,
                                                  statusCode <- log.statusCode,
                                                  errorMessage <- log.errorMessage,
                                                  isBookmarked <- log.isBookmarked,
                                                  tagsJSON <- tags,
                                                  notes <- log.notes,
                                                  conversationId <- log.conversationId,
                                                  metadataJSON <- metadata)
                    try db.run(insert)
                    if db.changes > 0 {
                        insertedCount += 1
                    }
                }
            }
            if insertedCount > 0 {
                await reloadLogs()
                refreshDashboardStats()
            }
        } catch {
            Logger.shared.error("批量日志保存失败: \(error.localizedDescription)")
        }
    }

    func reloadLogs(limit: Int = 100, offset: Int = 0) async {
        guard let dbConnection = self.db else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fetched = try dbConnection.prepare(self.logsTable.order(self.timestamp.desc).limit(limit, offset: offset)).map { self.rowToParsedLog($0) }
                
                let total = try dbConnection.scalar(self.logsTable.count)
                let errors = try dbConnection.scalar(
                    self.logsTable.filter(self.errorMessage != nil && (self.errorMessage ?? "") != "").count
                )
                let bookmarked = try dbConnection.scalar(self.logsTable.filter(self.isBookmarked == true).count)
                
                Task { @MainActor in
                    self.logs = fetched
                    self.totalLogCount = total
                    self.errorLogCount = errors
                    self.bookmarkedCount = bookmarked
                }
            } catch {
                Logger.shared.error("日志加载或计数更新失败: \(error.localizedDescription)")
            }
        }
    }

    func fetchLogs(limit: Int = 100, offset: Int = 0) -> [ParsedLog] {
        guard let db else { return [] }

        do {
            return try db.prepare(logsTable.order(timestamp.desc).limit(limit, offset: offset)).map { self.rowToParsedLog($0) }
        } catch {
            Logger.shared.error("日志查询失败: \(error.localizedDescription)")
            return []
        }
    }

    func searchLogs(query: String) async -> [ParsedLog] {
        guard let dbConnection = self.db else { return [] }
        let like = "%\(query)%"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let queryTable = self.logsTable
                        .filter(
                            self.sourceFile.like(like) ||
                            (self.modelName ?? "").like(like) ||
                            (self.prompt ?? "").like(like) ||
                            (self.response ?? "").like(like) ||
                            (self.providerRaw ?? "").like(like)
                        )
                        .order(self.timestamp.desc)
                    let results = try dbConnection.prepare(queryTable).map { self.rowToParsedLog($0) }
                    continuation.resume(returning: results)
                } catch {
                    Logger.shared.error("日志搜索失败: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func filterLogs(
        provider: LLMProvider? = nil,
        model: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        hasError: Bool? = nil,
        bookmarkedOnly: Bool = false
    ) async -> [ParsedLog] {
        guard let dbConnection = self.db else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var query = self.logsTable.order(self.timestamp.desc)

                    if let provider {
                        query = query.filter(self.providerRaw == provider.rawValue)
                    }
                    if let model, !model.isEmpty {
                        query = query.filter(self.modelName == model)
                    }
                    if let startDate {
                        query = query.filter(self.timestamp >= startDate.timeIntervalSince1970)
                    }
                    if let endDate {
                        query = query.filter(self.timestamp <= endDate.timeIntervalSince1970)
                    }
                    if let hasError {
                        if hasError {
                            query = query.filter(self.errorMessage != nil && (self.errorMessage ?? "") != "")
                        } else {
                            query = query.filter(self.errorMessage == nil || (self.errorMessage ?? "") == "")
                        }
                    }
                    if bookmarkedOnly {
                        query = query.filter(self.isBookmarked == true)
                    }

                    let results = try dbConnection.prepare(query.limit(500)).map { self.rowToParsedLog($0) }
                    continuation.resume(returning: results)
                } catch {
                    Logger.shared.error("日志过滤失败: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
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

    func refreshDashboardStats(days: Int? = nil) {
        guard let dbConnection = self.db else { return }

        let daysToUse: Int?
        if let days = days {
            self.lastDashboardDays = days
            daysToUse = days
        } else {
            daysToUse = self.lastDashboardDays
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var stats = DashboardStats()

            do {
                let filterTable: Table
                let startTimestamp: Double?
                if let days = daysToUse {
                    let limitDate: Double
                    if days == 0 {
                        limitDate = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
                    } else {
                        limitDate = Date().addingTimeInterval(-Double(days) * 24 * 3600).timeIntervalSince1970
                    }
                    filterTable = self.logsTable.filter(self.timestamp >= limitDate)
                    startTimestamp = limitDate
                } else {
                    filterTable = self.logsTable
                    startTimestamp = nil
                }

                // Total calls
                stats.totalCalls = try dbConnection.scalar(filterTable.count)

                // Token sums
                stats.totalPromptTokens = try dbConnection.scalar(filterTable.select(self.promptTokens.sum)) ?? 0
                stats.totalCompletionTokens = try dbConnection.scalar(filterTable.select(self.completionTokens.sum)) ?? 0
                stats.totalTokens = try dbConnection.scalar(filterTable.select(self.totalTokens.sum)) ?? 0
                if stats.totalTokens == 0 {
                    stats.totalTokens = stats.totalPromptTokens + stats.totalCompletionTokens
                }

                // Cost sum (Removed)

                // Error count
                stats.errorCount = try dbConnection.scalar(
                    filterTable.filter(self.errorMessage != nil && (self.errorMessage ?? "") != "").count
                )

                // Average response time
                stats.avgResponseTime = try dbConnection.scalar(filterTable.select(self.duration.average)) ?? 0.0

                // Calls and stats by provider
                var providerQuery = """
                    SELECT provider,
                           COUNT(*) as cnt,
                           COALESCE(SUM(total_tokens), 0) as tokens,
                           COALESCE(AVG(duration), 0.0) as avg_dur
                    FROM logs
                    WHERE provider IS NOT NULL
                """
                if let start = startTimestamp {
                    providerQuery += " AND timestamp >= \(start)"
                }
                providerQuery += " GROUP BY provider ORDER BY cnt DESC"
                
                for row in try dbConnection.prepare(providerQuery) {
                    if let pStr = row[0] as? String, let provider = LLMProvider(rawValue: pStr) {
                        let count = Int(row[1] as? Int64 ?? 0)
                        let tokens = Int(row[2] as? Int64 ?? 0)
                        
                        let avgDurVal = row[3]
                        let avgDur = avgDurVal as? Double ?? Double(avgDurVal as? Int64 ?? 0)
                        
                        stats.callsByProvider[provider] = count
                        stats.providerStats[provider] = ProviderStat(
                            provider: provider,
                            count: count,
                            tokens: tokens,
                            avgDuration: avgDur
                        )
                    }
                }

                // Calls by model
                var modelQuery = "SELECT model_name, COUNT(*) as cnt FROM logs WHERE model_name IS NOT NULL "
                if let start = startTimestamp {
                    modelQuery += "AND timestamp >= \(start) "
                }
                modelQuery += "GROUP BY model_name ORDER BY cnt DESC LIMIT 20"
                for row in try dbConnection.prepare(modelQuery) {
                    if let mName = row[0] as? String, let count = row[1] as? Int64 {
                        stats.callsByModel[mName] = Int(count)
                    }
                }

                // Tokens by day / hour
                let daysLimit = daysToUse ?? 90
                let limitVal: Double
                let dayQuery: String
                let modelDayQuery: String
                let formatter = DateFormatter()
                
                if daysLimit == 0 {
                    limitVal = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
                    dayQuery = """
                        SELECT strftime('%Y-%m-%d %H:00:00', timestamp, 'unixepoch', 'localtime') as hour_bucket,
                               COALESCE(SUM(prompt_tokens), 0) as pt,
                               COALESCE(SUM(completion_tokens), 0) as ct
                        FROM logs
                        WHERE timestamp >= \(limitVal)
                        GROUP BY hour_bucket
                        ORDER BY hour_bucket ASC
                    """
                    modelDayQuery = """
                        SELECT strftime('%Y-%m-%d %H:00:00', timestamp, 'unixepoch', 'localtime') as hour_bucket,
                               model_name,
                               COALESCE(SUM(prompt_tokens), 0) as pt,
                               COALESCE(SUM(completion_tokens), 0) as ct
                        FROM logs
                        WHERE timestamp >= \(limitVal) AND model_name IS NOT NULL AND model_name != ''
                        GROUP BY hour_bucket, model_name
                        ORDER BY hour_bucket ASC
                    """
                    formatter.dateFormat = "yyyy-MM-dd HH:00:00"
                } else {
                    limitVal = Date().addingTimeInterval(-Double(daysLimit) * 24 * 3600).timeIntervalSince1970
                    dayQuery = """
                        SELECT date(timestamp, 'unixepoch', 'localtime') as day_bucket,
                               COALESCE(SUM(prompt_tokens), 0) as pt,
                               COALESCE(SUM(completion_tokens), 0) as ct
                        FROM logs
                        WHERE timestamp >= \(limitVal)
                        GROUP BY day_bucket
                        ORDER BY day_bucket ASC
                    """
                    modelDayQuery = """
                        SELECT date(timestamp, 'unixepoch', 'localtime') as day_bucket,
                               model_name,
                               COALESCE(SUM(prompt_tokens), 0) as pt,
                               COALESCE(SUM(completion_tokens), 0) as ct
                        FROM logs
                        WHERE timestamp >= \(limitVal) AND model_name IS NOT NULL AND model_name != ''
                        GROUP BY day_bucket, model_name
                        ORDER BY day_bucket ASC
                    """
                    formatter.dateFormat = "yyyy-MM-dd"
                }
                
                for row in try dbConnection.prepare(dayQuery) {
                    if let bucketStr = row[0] as? String,
                       let pt = row[1] as? Int64,
                       let ct = row[2] as? Int64 {
                        if let date = formatter.date(from: bucketStr) {
                            stats.tokensByDay.append(DayTokens(
                                date: date,
                                promptTokens: Int(pt),
                                completionTokens: Int(ct)
                            ))
                        }
                    }
                }

                // Query and aggregate model-specific token usage
                struct RawModelTokenPoint {
                    let date: Date
                    let modelName: String
                    let promptTokens: Int
                    let completionTokens: Int
                }
                var rawPoints: [RawModelTokenPoint] = []
                var modelTotalTokens: [String: Int] = [:]

                for row in try dbConnection.prepare(modelDayQuery) {
                    if let bucketStr = row[0] as? String,
                       let mName = row[1] as? String,
                       let pt = row[2] as? Int64,
                       let ct = row[3] as? Int64 {
                        if let date = formatter.date(from: bucketStr) {
                            let ptInt = Int(pt)
                            let ctInt = Int(ct)
                            rawPoints.append(RawModelTokenPoint(
                                date: date,
                                modelName: mName,
                                promptTokens: ptInt,
                                completionTokens: ctInt
                            ))
                            modelTotalTokens[mName, default: 0] += (ptInt + ctInt)
                        }
                    }
                }

                // Determine top 5 models
                let topModels = modelTotalTokens.sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { $0.key }
                let topModelsSet = Set(topModels)

                // Group points by (date, simplifiedModelName) and sum tokens
                var groupedPoints: [Date: [String: (prompt: Int, completion: Int)]] = [:]
                for point in rawPoints {
                    let modelKey = topModelsSet.contains(point.modelName) ? point.modelName : "其他"
                    if groupedPoints[point.date] == nil {
                        groupedPoints[point.date] = [:]
                    }
                    let current = groupedPoints[point.date]?[modelKey] ?? (0, 0)
                    groupedPoints[point.date]?[modelKey] = (current.0 + point.promptTokens, current.1 + point.completionTokens)
                }

                // Convert to final [ModelDayTokens] sorted by date and model name
                var modelTokensByDayResult: [ModelDayTokens] = []
                for (date, modelsData) in groupedPoints {
                    for (modelName, tokens) in modelsData {
                        modelTokensByDayResult.append(ModelDayTokens(
                            date: date,
                            modelName: modelName,
                            promptTokens: tokens.prompt,
                            completionTokens: tokens.completion
                        ))
                    }
                }
                // Sort by date, then by model name (so lines render predictably)
                modelTokensByDayResult.sort {
                    if $0.date == $1.date {
                        return $0.modelName < $1.modelName
                    }
                    return $0.date < $1.date
                }
                stats.modelTokensByDay = modelTokensByDayResult

                // Recent logs
                let recentLogsRows = try dbConnection.prepare(self.logsTable.order(self.timestamp.desc).limit(10))
                stats.recentLogs = recentLogsRows.map { self.rowToParsedLog($0) }

                // Anomaly Spotlights within the filtered time window
                if let slowestRow = try dbConnection.pluck(filterTable.filter(self.duration != nil).order(self.duration.desc)) {
                    stats.slowestLog = self.rowToParsedLog(slowestRow)
                }
                
                // Expensive spotlight removed
                
                if let largestRow = try dbConnection.pluck(filterTable.filter(self.totalTokens != nil).order(self.totalTokens.desc)) {
                    stats.largestPayloadLog = self.rowToParsedLog(largestRow)
                }
                
                stats.localCallsCount = try dbConnection.scalar(
                    filterTable.filter(self.providerRaw == LLMProvider.ollama.rawValue).count
                )

                Task { @MainActor in
                    self.dashboardStats = stats
                }
            } catch {
                Logger.shared.error("Dashboard 统计刷新失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Rate Limit Aggregations

    /// 区间内的所有日志（按时间正序），用于滑动窗口/并发计算
    func fetchLogs(provider: LLMProvider?, since: Date, until: Date = Date()) async -> [ParsedLog] {
        guard let dbConnection = self.db else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var q = self.logsTable
                        .filter(self.timestamp >= since.timeIntervalSince1970 && self.timestamp <= until.timeIntervalSince1970)
                        .order(self.timestamp.asc)
                    if let provider {
                        q = q.filter(self.providerRaw == provider.rawValue)
                    }
                    let results = try dbConnection.prepare(q).map { self.rowToParsedLog($0) }
                    continuation.resume(returning: results)
                } catch {
                    Logger.shared.error("区间日志查询失败: \(error.localizedDescription)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// 区间内的聚合（请求数 / token / 平均时长），不分 provider 也支持
    struct UsageAggregate {
        var requestCount: Int = 0
        var totalTokens: Int = 0
        var avgDuration: Double = 0
    }

    func aggregateUsage(provider: LLMProvider?, since: Date, until: Date = Date()) async -> UsageAggregate {
        guard let dbConnection = self.db else { return UsageAggregate() }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var q = self.logsTable.filter(self.timestamp >= since.timeIntervalSince1970 && self.timestamp <= until.timeIntervalSince1970)
                    if let provider {
                        q = q.filter(self.providerRaw == provider.rawValue)
                    }
                    var agg = UsageAggregate()
                    agg.requestCount = try dbConnection.scalar(q.count)
                    agg.totalTokens = try dbConnection.scalar(q.select(self.totalTokens.sum)) ?? 0
                    if agg.totalTokens == 0 {
                        let pt = try dbConnection.scalar(q.select(self.promptTokens.sum)) ?? 0
                        let ct = try dbConnection.scalar(q.select(self.completionTokens.sum)) ?? 0
                        agg.totalTokens = pt + ct
                    }
                    agg.avgDuration = try dbConnection.scalar(q.select(self.duration.average)) ?? 0.0
                    continuation.resume(returning: agg)
                } catch {
                    Logger.shared.error("区间聚合失败: \(error.localizedDescription)")
                    continuation.resume(returning: UsageAggregate())
                }
            }
        }
    }

    func fetchDistinctModels() async -> [String] {
        guard let dbConnection = self.db else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try dbConnection.prepare(self.logsTable.select(distinct: self.modelName).filter(self.modelName != nil)).compactMap { $0[self.modelName] }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchDistinctProviders() async -> [LLMProvider] {
        guard let dbConnection = self.db else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try dbConnection.prepare(self.logsTable.select(distinct: self.providerRaw).filter(self.providerRaw != nil)).compactMap { row -> LLMProvider? in
                        guard let raw = row[self.providerRaw] else { return nil }
                        return LLMProvider(rawValue: raw)
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    func fetchHourlyChartData(provider: LLMProvider) async -> (buckets: [(hour: Int, count: Int)], topModel: String) {
        guard let dbConnection = self.db else { return ([], "—") }
        let now = Date()
        let since = now.addingTimeInterval(-24 * 3600)
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var q = self.logsTable
                        .filter(self.timestamp >= since.timeIntervalSince1970 && self.timestamp <= now.timeIntervalSince1970)
                        .order(self.timestamp.asc)
                    if let rawValue = provider.rawValue as String? {
                        q = q.filter(self.providerRaw == rawValue)
                    }
                    let logs = try dbConnection.prepare(q).map { self.rowToParsedLog($0) }
                    
                    let calendar = Calendar.current
                    var counts = [Int: Int]()
                    for i in 0..<24 { counts[i] = 0 }
                    var modelCounts = [String: Int]()
                    
                    for log in logs {
                        let hour = calendar.component(.hour, from: log.timestamp)
                        counts[hour, default: 0] += 1
                        if let model = log.modelName {
                            modelCounts[model, default: 0] += 1
                        }
                    }
                    
                    let buckets = counts.map { (hour: $0.key, count: $0.value) }
                        .sorted { $0.hour < $1.hour }
                    let topModel = modelCounts.max(by: { $0.value < $1.value })?.key ?? "—"
                    
                    continuation.resume(returning: (buckets, topModel))
                } catch {
                    continuation.resume(returning: ([], "—"))
                }
            }
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
                try handle.write(contentsOf: Data("id,timestamp,provider,model,promptTokens,completionTokens,totalTokens,duration,error\n".utf8))
                for row in rows {
                    let log = rowToParsedLog(row)
                    let line = "\(log.id.uuidString),\(log.timestamp.timeIntervalSince1970),\(escapeCSV(log.provider?.displayName ?? "")),\(escapeCSV(log.modelName ?? "")),\(log.promptTokens.map(String.init) ?? ""),\(log.completionTokens.map(String.init) ?? ""),\(log.totalTokens.map(String.init) ?? ""),\(log.duration.map { String(format: "%.3f", $0) } ?? ""),\(escapeCSV(log.errorMessage ?? ""))\n"
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

    nonisolated private func rowToParsedLog(_ row: Row) -> ParsedLog {
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
