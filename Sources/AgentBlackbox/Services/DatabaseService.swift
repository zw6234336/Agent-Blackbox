import Foundation
import SQLite3

/// Persists `LogEntry` records in a local SQLite database.
actor DatabaseService {
    private var db: OpaquePointer?

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentBlackbox")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("logs.db").path
        sqlite3_open(path, &db)
        createSchema()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS log_entries (
            id            TEXT PRIMARY KEY,
            platform      TEXT NOT NULL,
            timestamp     REAL NOT NULL,
            prompt        TEXT,
            response      TEXT,
            model         TEXT,
            input_tokens  INTEGER,
            output_tokens INTEGER,
            total_tokens  INTEGER,
            raw_content   TEXT NOT NULL,
            file_path     TEXT NOT NULL,
            metadata      TEXT NOT NULL DEFAULT '{}'
        );
        CREATE INDEX IF NOT EXISTS idx_ts  ON log_entries(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_plt ON log_entries(platform);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Write

    func insert(entry: LogEntry) {
        let sql = """
        INSERT OR IGNORE INTO log_entries
          (id, platform, timestamp, prompt, response, model,
           input_tokens, output_tokens, total_tokens, raw_content, file_path, metadata)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let metaJSON = (try? JSONEncoder().encode(entry.metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        sqlite3_bind_text(stmt,  1, entry.id.uuidString,         -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt,  2, entry.platform.rawValue,     -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt,  4, entry.prompt ?? "",          -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt,  5, entry.response ?? "",        -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt,  6, entry.model ?? "",           -1, SQLITE_TRANSIENT)
        bindOptionalInt(stmt, 7, entry.inputTokens)
        bindOptionalInt(stmt, 8, entry.outputTokens)
        bindOptionalInt(stmt, 9, entry.totalTokens)
        sqlite3_bind_text(stmt, 10, entry.rawContent,            -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 11, entry.filePath,              -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 12, metaJSON,                    -1, SQLITE_TRANSIENT)

        sqlite3_step(stmt)
    }

    // MARK: - Read

    func fetchAllEntries() -> [LogEntry] {
        let sql = """
        SELECT id, platform, timestamp, prompt, response, model,
               input_tokens, output_tokens, total_tokens, raw_content, file_path, metadata
        FROM log_entries ORDER BY timestamp DESC LIMIT 10000;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var entries: [LogEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id        = UUID(uuidString: str(stmt, 0)) ?? UUID()
            let platform  = LLMPlatform(rawValue: str(stmt, 1)) ?? .custom
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
            let prompt    = nilIfEmpty(str(stmt, 3))
            let response  = nilIfEmpty(str(stmt, 4))
            let model     = nilIfEmpty(str(stmt, 5))
            let inputTok  = optionalInt(stmt, 6)
            let outputTok = optionalInt(stmt, 7)
            let totalTok  = optionalInt(stmt, 8)
            let raw       = str(stmt, 9)
            let filePath  = str(stmt, 10)
            let metaStr   = str(stmt, 11)
            let metadata  = (metaStr.data(using: .utf8)
                .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }) ?? [:]

            entries.append(LogEntry(
                id: id, platform: platform, timestamp: timestamp,
                prompt: prompt, response: response, model: model,
                inputTokens: inputTok, outputTokens: outputTok, totalTokens: totalTok,
                rawContent: raw, filePath: filePath, metadata: metadata
            ))
        }
        return entries
    }

    // MARK: - Delete

    func deleteAll() {
        sqlite3_exec(db, "DELETE FROM log_entries;", nil, nil, nil)
    }

    // MARK: - Private helpers

    private func str(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    private func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    private func optionalInt(_ stmt: OpaquePointer?, _ col: Int32) -> Int? {
        sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, col))
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ col: Int32, _ value: Int?) {
        if let v = value { sqlite3_bind_int(stmt, col, Int32(v)) }
        else { sqlite3_bind_null(stmt, col) }
    }
}
