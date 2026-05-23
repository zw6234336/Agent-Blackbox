import Foundation
import SQLite

@MainActor
final class DatabaseService: ObservableObject {
    @Published var logs: [ParsedLog] = []

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
        logs = fetchLogs(limit: limit, offset: offset)
    }

    func fetchLogs(limit: Int = 100, offset: Int = 0) -> [ParsedLog] {
        guard let db else { return [] }

        do {
            return try db.prepare(logsTable.order(timestamp.desc).limit(limit, offset: offset)).compactMap { row in
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
        } catch {
            Logger.shared.error("日志查询失败: \(error.localizedDescription)")
            return []
        }
    }

    func searchLogs(query: String) -> [ParsedLog] {
        fetchLogs(limit: 10_000, offset: 0).filter { log in
            log.modelName?.localizedCaseInsensitiveContains(query) == true ||
            log.prompt?.localizedCaseInsensitiveContains(query) == true ||
            log.response?.localizedCaseInsensitiveContains(query) == true ||
            log.sourceFile.localizedCaseInsensitiveContains(query)
        }
    }

    func exportLogs(format: ExportFormat) -> URL? {
        let logs = fetchLogs(limit: 10_000, offset: 0)
        guard !logs.isEmpty else { return nil }

        let fileManager = FileManager.default
        let exportFolder = Self.defaultDatabaseURL.deletingLastPathComponent().appendingPathComponent("Exports", isDirectory: true)
        try? fileManager.createDirectory(at: exportFolder, withIntermediateDirectories: true, attributes: nil)

        let filename = "logs-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
        let fileURL = exportFolder.appendingPathComponent(filename)

        do {
            let data: Data
            switch format {
            case .json:
                data = try JSONEncoder.pretty.encode(logs)
            case .csv:
                var csv = "id,timestamp,sourceFile,modelName,tokensUsed,errorMessage\n"
                for log in logs {
                    csv += "\(log.id.uuidString),\(log.timestamp.timeIntervalSince1970),\(escapeCSV(log.sourceFile)),\(escapeCSV(log.modelName ?? "")),\(log.tokensUsed.map(String.init) ?? ""),\(escapeCSV(log.errorMessage ?? ""))\n"
                }
                data = Data(csv.utf8)
            }
            try data.write(to: fileURL, options: .atomic)
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

    static var defaultDatabaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
