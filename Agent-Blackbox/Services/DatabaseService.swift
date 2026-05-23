import Foundation
import SQLite

@MainActor
final class DatabaseService: ObservableObject {
    @Published var logs: [ParsedLog] = []
    @Published private(set) var totalLogCount: Int = 0
    @Published private(set) var errorLogCount: Int = 0

    private var db: Connection?

    private let logsTable = Table("logs")
    private let id = Expression<String>("id")
    private let timestamp = Expression<Double>("timestamp")
    private let sourceFile = Expression<String>("source_file")
    private let modelName = Expression<String?>("model_name")
    private let prompt = Expression<String?>("prompt")
    private let response = Expression<String?>("response")
    private let tokensUsed = Expression<Int?>("tokens_used")
    private let errorMessage = Expression<String?>("error_message")
    private let metadataJSON = Expression<String>("metadata_json")

    func initializeIfNeeded() {
        guard db == nil else { return }

        do {
            let dbURL = Self.defaultDatabaseURL
            try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            db = try Connection(dbURL.path)
            try db?.run(logsTable.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(timestamp)
                t.column(sourceFile)
                t.column(modelName)
                t.column(prompt)
                t.column(response)
                t.column(tokensUsed)
                t.column(errorMessage)
                t.column(metadataJSON)
            })
            try db?.run(logsTable.createIndex(sourceFile, ifNotExists: true))
            try db?.run(logsTable.createIndex(timestamp, ifNotExists: true))
        } catch {
            Logger.shared.error("数据库初始化失败: \(error.localizedDescription)")
        }
    }

    func saveLog(_ log: ParsedLog) async {
        guard let db else { return }

        do {
            let metadata = (try? String(data: JSONSerialization.data(withJSONObject: log.metadata), encoding: .utf8)) ?? "{}"
            let insert = logsTable.insert(or: .replace,
                                          id <- log.id.uuidString,
                                          timestamp <- log.timestamp.timeIntervalSince1970,
                                          sourceFile <- log.sourceFile,
                                          modelName <- log.modelName,
                                          prompt <- log.prompt,
                                          response <- log.response,
                                          tokensUsed <- log.tokensUsed,
                                          errorMessage <- log.errorMessage,
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
                    (response ?? "").like(like)
                )
                .order(timestamp.desc)
            return try db.prepare(queryTable).map(rowToParsedLog)
        } catch {
            Logger.shared.error("日志搜索失败: \(error.localizedDescription)")
            return []
        }
    }

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

                    func clearAllLogs() async {
                        guard let db else { return }
                        do {
                            try db.run(logsTable.delete())
                            await reloadLogs()
                        } catch {
                            Logger.shared.error("清空数据库失败: \(error.localizedDescription)")
                        }
                    }
                    try handle.write(contentsOf: encoded)
                }
                try handle.write(contentsOf: Data("]".utf8))
            case .csv:
                try handle.write(contentsOf: Data("id,timestamp,sourceFile,modelName,tokensUsed,errorMessage\n".utf8))
                for row in rows {
                    let log = rowToParsedLog(row)
                    let line = "\(log.id.uuidString),\(log.timestamp.timeIntervalSince1970),\(escapeCSV(log.sourceFile)),\(escapeCSV(log.modelName ?? "")),\(log.tokensUsed.map(String.init) ?? ""),\(escapeCSV(log.errorMessage ?? ""))\n"
                    try handle.write(contentsOf: Data(line.utf8))
                }
            }
            return fileURL
        } catch {
            Logger.shared.error("日志导出失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func rowToParsedLog(_ row: Row) -> ParsedLog {
        let metadataData = row[metadataJSON].data(using: .utf8) ?? Data("{}".utf8)
        let metadata = (try? JSONSerialization.jsonObject(with: metadataData) as? [String: String]) ?? [:]
        return ParsedLog(
            id: UUID(uuidString: row[id]) ?? UUID(),
            timestamp: Date(timeIntervalSince1970: row[timestamp]),
            sourceFile: row[sourceFile],
            modelName: row[modelName],
            prompt: row[prompt],
            response: row[response],
            tokensUsed: row[tokensUsed],
            errorMessage: row[errorMessage],
            metadata: metadata
        )
    }

    private func applySnapshot(_ newLogs: [ParsedLog]) {
        logs = newLogs
    }

    private func updateCountersFromDatabase() {
        guard let db else {
            totalLogCount = logs.count
            errorLogCount = logs.lazy.filter { $0.errorMessage != nil }.count
            return
        }
        do {
            totalLogCount = try db.scalar(logsTable.count)
            errorLogCount = try db.scalar(
                logsTable
                    .filter(errorMessage != nil && (errorMessage ?? "") != "")
                    .count
            )
        } catch {
            totalLogCount = logs.count
            errorLogCount = logs.lazy.filter { $0.errorMessage != nil }.count
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
