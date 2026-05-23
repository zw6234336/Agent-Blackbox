import Foundation
import AppKit
import SQLite

@MainActor
final class CompilationService: ObservableObject {
    @Published var compilations: [LogCompilation] = []
    @Published var isGenerating = false

    private var db: Connection?
    private var generationTask: Task<Void, Never>?

    // Table
    private let compilationsTable = Table("compilations")
    private let colId = SQLite.Expression<String>("id")
    private let colName = SQLite.Expression<String>("name")
    private let colDesc = SQLite.Expression<String>("description")
    private let colCreatedAt = SQLite.Expression<Double>("created_at")
    private let colUpdatedAt = SQLite.Expression<Double>("updated_at")
    private let colStatus = SQLite.Expression<String>("status")
    private let colOutputFormat = SQLite.Expression<String>("output_format")
    private let colProviderFilters = SQLite.Expression<String>("provider_filters")
    private let colStartDate = SQLite.Expression<Double?>("start_date")
    private let colEndDate = SQLite.Expression<Double?>("end_date")
    private let colBookmarkedOnly = SQLite.Expression<Bool>("bookmarked_only")
    private let colLastCompiledTs = SQLite.Expression<Double?>("last_compiled_ts")
    private let colTotalLogCount = SQLite.Expression<Int>("total_log_count")
    private let colAppendCount = SQLite.Expression<Int>("append_count")
    private let colProgress = SQLite.Expression<Double>("progress")
    private let colProgressMsg = SQLite.Expression<String?>("progress_message")
    private let colOutputPath = SQLite.Expression<String?>("output_path")
    private let colOutputSize = SQLite.Expression<Int64?>("output_size")
    private let colCompiledProviders = SQLite.Expression<String>("compiled_providers")
    private let colCompiledModels = SQLite.Expression<String>("compiled_models")
    private let colCompiledTokenTotal = SQLite.Expression<Int>("compiled_token_total")
    private let colCompiledCostTotal = SQLite.Expression<Double>("compiled_cost_total")

    // MARK: - Init

    func initializeIfNeeded() {
        guard db == nil else { return }
        do {
            let dbURL = Self.defaultDatabaseURL
            try FileManager.default.createDirectory(
                at: dbURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            db = try Connection(dbURL.path)
            try createTableIfNeeded()
            try createCompilationsDir()
            loadCompilations()
        } catch {
            Logger.shared.error("CompilationService 初始化失败: \(error.localizedDescription)")
        }
    }

    private func createTableIfNeeded() throws {
        try db?.run(compilationsTable.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: true)
            t.column(colName)
            t.column(colDesc, defaultValue: "")
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
            t.column(colStatus, defaultValue: "pending")
            t.column(colOutputFormat, defaultValue: "markdown")
            t.column(colProviderFilters, defaultValue: "[]")
            t.column(colStartDate)
            t.column(colEndDate)
            t.column(colBookmarkedOnly, defaultValue: false)
            t.column(colLastCompiledTs)
            t.column(colTotalLogCount, defaultValue: 0)
            t.column(colAppendCount, defaultValue: 0)
            t.column(colProgress, defaultValue: 0)
            t.column(colProgressMsg)
            t.column(colOutputPath)
            t.column(colOutputSize)
            t.column(colCompiledProviders, defaultValue: "[]")
            t.column(colCompiledModels, defaultValue: "[]")
            t.column(colCompiledTokenTotal, defaultValue: 0)
            t.column(colCompiledCostTotal, defaultValue: 0.0)
        })
    }

    static var defaultDatabaseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Agent-Blackbox/logs.db", isDirectory: false)
    }

    private var compilationsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Agent-Blackbox/Compilations", isDirectory: true)
    }

    private func createCompilationsDir() throws {
        try FileManager.default.createDirectory(
            at: compilationsDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: - CRUD

    func createCompilation(
        name: String,
        description: String = "",
        format: CompilationOutputFormat = .markdown,
        providers: [LLMProvider] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        bookmarkedOnly: Bool = false
    ) -> LogCompilation {
        let compilation = LogCompilation(
            name: name,
            description: description,
            outputFormat: format,
            providerFilters: providers.map { $0.rawValue },
            startDate: startDate,
            endDate: endDate,
            bookmarkedOnly: bookmarkedOnly
        )
        saveCompilation(compilation)
        loadCompilations()
        return compilation
    }

    func deleteCompilation(id: UUID) {
        guard let db else { return }
        // Remove output file
        if let comp = compilations.first(where: { $0.id == id }),
           let path = comp.outputFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        do {
            try db.run(compilationsTable.filter(colId == id.uuidString).delete())
        } catch {
            Logger.shared.error("删除编译失败: \(error.localizedDescription)")
        }
        loadCompilations()
    }

    func loadCompilations() {
        guard let db else { return }
        do {
            compilations = try db.prepare(compilationsTable.order(colCreatedAt.desc)).map(rowToCompilation)
        } catch {
            Logger.shared.error("加载编译列表失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Generation Lifecycle

    func startGeneration(id: UUID) {
        guard var compilation = compilations.first(where: { $0.id == id }) else { return }
        compilation.status = .generating
        compilation.progress = 0
        compilation.progressMessage = "正在查询日志..."
        compilation.updatedAt = Date()
        saveCompilation(compilation)
        loadCompilations()
        isGenerating = true

        generationTask = Task {
            let logs = fetchLogsForCompilation(compilation)
            guard !Task.isCancelled else { return }

            if logs.isEmpty {
                var c = compilation
                c.status = .completed
                c.progress = 1.0
                c.progressMessage = "没有找到匹配的日志"
                c.updatedAt = Date()
                saveCompilation(c)
                loadCompilations()
                isGenerating = false
                return
            }

            let total = logs.count
            let batchSize = 50
            var rendered = renderHeader(compilation, logCount: total)
            var processed = 0

            // Group by provider then date
            let grouped = groupLogs(logs)

            for (provider, byDate) in grouped {
                guard !Task.isCancelled else { return }

                rendered += renderProviderHeader(provider, logs: byDate)

                for (date, dateLogs) in byDate {
                    guard !Task.isCancelled else { return }

                    rendered += renderDateHeader(date)
                    let conversations = groupByConversation(dateLogs)

                    for (convId, convLogs) in conversations {
                        guard !Task.isCancelled else { return }

                        rendered += renderConversation(convId, logs: convLogs, format: compilation.outputFormat)

                        processed += convLogs.count
                        let prog = Double(processed) / Double(total)

                        var c = compilation
                        c.progress = prog
                        c.progressMessage = "已处理 \(processed)/\(total) 条日志..."
                        c.updatedAt = Date()
                        saveCompilation(c)

                        if processed % batchSize == 0 {
                            loadCompilations()
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }

            // Statistics
            let stats = computeStats(logs)

            rendered += renderSummary(compilation, stats: stats, totalLogs: total)

            // Write output
            let url = writeOutput(compilation: compilation, content: rendered)

            var final = compilation
            final.status = .completed
            final.progress = 1.0
            final.progressMessage = "完成"
            final.totalLogCount = total
            final.lastCompiledTimestamp = logs.first?.timestamp ?? Date()
            final.outputFilePath = url?.path
            final.outputFileSize = url.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64) }
            final.compiledProviders = stats.providers
            final.compiledModels = stats.models
            final.compiledTokenTotal = stats.totalTokens
            final.compiledCostTotal = stats.totalCost
            final.updatedAt = Date()
            saveCompilation(final)
            loadCompilations()
            isGenerating = false
        }
    }

    func pauseGeneration(id: UUID) {
        generationTask?.cancel()
        generationTask = nil

        if var c = compilations.first(where: { $0.id == id }) {
            c.status = .paused
            c.progressMessage = "已暂停于 \(c.progress.formattedPercent)"
            c.updatedAt = Date()
            saveCompilation(c)
            loadCompilations()
        }
        isGenerating = false
    }

    func resumeGeneration(id: UUID) {
        startGeneration(id: id)
    }

    func cancelGeneration(id: UUID) {
        generationTask?.cancel()
        generationTask = nil

        if var c = compilations.first(where: { $0.id == id }) {
            c.status = .cancelled
            c.progressMessage = "已取消"
            c.updatedAt = Date()
            saveCompilation(c)
            loadCompilations()
        }
        isGenerating = false
    }

    func appendNewLogs(id: UUID) {
        guard var compilation = compilations.first(where: { $0.id == id }),
              compilation.status == .completed else { return }

        compilation.status = .generating
        compilation.progress = 0
        compilation.progressMessage = "正在追加新日志..."
        compilation.updatedAt = Date()
        saveCompilation(compilation)
        loadCompilations()
        isGenerating = true

        generationTask = Task {
            // Fetch only logs newer than lastCompiledTimestamp
            var appendComp = compilation
            appendComp.startDate = compilation.lastCompiledTimestamp
            let newLogs = fetchLogsForCompilation(appendComp)

            guard !Task.isCancelled else { return }

            if newLogs.isEmpty {
                var c = compilation
                c.progress = 1.0
                c.progressMessage = "没有新的日志需要追加"
                c.updatedAt = Date()
                saveCompilation(c)
                loadCompilations()
                isGenerating = false
                return
            }

            let existingContent: String
            if let path = compilation.outputFilePath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let str = String(data: data, encoding: .utf8) {
                existingContent = str
            } else {
                existingContent = ""
            }

            let newContent = renderAppendix(newLogs, format: compilation.outputFormat)
            let fullContent = existingContent + "\n\n" + newContent

            let url = writeOutput(compilation: compilation, content: fullContent)

            var final = compilation
            final.status = .completed
            final.progress = 1.0
            final.progressMessage = "已追加 \(newLogs.count) 条新日志"
            final.totalLogCount += newLogs.count
            final.appendCount += 1
            final.lastCompiledTimestamp = newLogs.first?.timestamp ?? final.lastCompiledTimestamp
            final.outputFilePath = url?.path
            final.outputFileSize = url.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64) }
            final.updatedAt = Date()

            // Update stats
            let allStats = computeStats(newLogs)
            var existingProviders = final.compiledProviders
            for p in allStats.providers where !existingProviders.contains(p) {
                existingProviders.append(p)
            }
            final.compiledProviders = existingProviders
            final.compiledTokenTotal += allStats.totalTokens
            final.compiledCostTotal += allStats.totalCost

            saveCompilation(final)
            loadCompilations()
            isGenerating = false
        }
    }

    // MARK: - Output Helpers

    func getOutputURL(for compilation: LogCompilation) -> URL? {
        guard let path = compilation.outputFilePath else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: path) ? url : nil
    }

    func getOutputContent(for compilation: LogCompilation) -> String? {
        guard let path = compilation.outputFilePath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    func revealInFinder(id: UUID) {
        guard let comp = compilations.first(where: { $0.id == id }),
              let url = getOutputURL(for: comp) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToClipboard(id: UUID) {
        guard let comp = compilations.first(where: { $0.id == id }),
              let content = getOutputContent(for: comp) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    // MARK: - Log Fetching (direct SQLite query, no 500 limit)

    private func fetchLogsForCompilation(_ compilation: LogCompilation) -> [ParsedLog] {
        guard let db else { return [] }

        do {
            let logsTable = Table("logs")
            let timestampCol = SQLite.Expression<Double>("timestamp")
            let idCol = SQLite.Expression<String>("id")
            let sourceFileCol = SQLite.Expression<String>("source_file")
            let providerCol = SQLite.Expression<String?>("provider")
            let modelNameCol = SQLite.Expression<String?>("model_name")
            let promptCol = SQLite.Expression<String?>("prompt")
            let responseCol = SQLite.Expression<String?>("response")
            let promptTokensCol = SQLite.Expression<Int?>("prompt_tokens")
            let completionTokensCol = SQLite.Expression<Int?>("completion_tokens")
            let totalTokensCol = SQLite.Expression<Int?>("total_tokens")
            let estimatedCostCol = SQLite.Expression<Double?>("estimated_cost")
            let durationCol = SQLite.Expression<Double?>("duration")
            let statusCodeCol = SQLite.Expression<Int?>("status_code")
            let errorMessageCol = SQLite.Expression<String?>("error_message")
            let isBookmarkedCol = SQLite.Expression<Bool>("is_bookmarked")
            let tagsJsonCol = SQLite.Expression<String>("tags_json")
            let notesCol = SQLite.Expression<String?>("notes")
            let conversationIdCol = SQLite.Expression<String?>("conversation_id")
            let metadataJsonCol = SQLite.Expression<String>("metadata_json")

            var query = logsTable.order(timestampCol.asc)

            // Provider filtering done in-memory after query
            if let start = compilation.startDate {
                query = query.filter(timestampCol >= start.timeIntervalSince1970)
            }
            if let end = compilation.endDate {
                query = query.filter(timestampCol <= end.timeIntervalSince1970)
            }
            if compilation.bookmarkedOnly {
                query = query.filter(isBookmarkedCol == true)
            }

            let allLogs = try db.prepare(query).map { row -> ParsedLog in
                let metadataStr = row[metadataJsonCol]
                let metadata = (try? JSONSerialization.jsonObject(with: Data(metadataStr.utf8))) as? [String: String] ?? [:]
                let tagsStr = row[tagsJsonCol]
                let tags = (try? JSONSerialization.jsonObject(with: Data(tagsStr.utf8))) as? [String] ?? []

                return ParsedLog(
                    id: UUID(uuidString: row[idCol]) ?? UUID(),
                    timestamp: Date(timeIntervalSince1970: row[timestampCol]),
                    sourceFile: row[sourceFileCol],
                    provider: row[providerCol].flatMap { LLMProvider(rawValue: $0) },
                    modelName: row[modelNameCol],
                    prompt: row[promptCol],
                    response: row[responseCol],
                    promptTokens: row[promptTokensCol],
                    completionTokens: row[completionTokensCol],
                    totalTokens: row[totalTokensCol],
                    estimatedCost: row[estimatedCostCol],
                    duration: row[durationCol],
                    statusCode: row[statusCodeCol],
                    errorMessage: row[errorMessageCol],
                    isBookmarked: row[isBookmarkedCol],
                    tags: tags,
                    notes: row[notesCol],
                    conversationId: row[conversationIdCol],
                    metadata: metadata
                )
            }

            // Provider filtering in-memory
            if !compilation.providerFilters.isEmpty {
                return allLogs.filter { log in
                    guard let p = log.provider?.rawValue else { return false }
                    return compilation.providerFilters.contains(p)
                }
            }
            return allLogs
        } catch {
            Logger.shared.error("查询编译日志失败: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Grouping

    private func groupLogs(_ logs: [ParsedLog]) -> [(LLMProvider, [(String, [ParsedLog])])] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "zh_CN")

        // Group by provider
        var byProvider: [LLMProvider: [ParsedLog]] = [:]
        for log in logs {
            let provider = log.provider ?? .custom
            byProvider[provider, default: []].append(log)
        }

        // Sort providers alphabetically by displayName
        let sortedProviders = byProvider.keys.sorted { $0.displayName < $1.displayName }

        return sortedProviders.map { provider in
            let providerLogs = byProvider[provider]!
            // Group by date
            var byDate: [String: [ParsedLog]] = [:]
            for log in providerLogs {
                let dateKey = df.string(from: log.timestamp)
                byDate[dateKey, default: []].append(log)
            }
            let sortedDates = byDate.keys.sorted().reversed() // newest first
            return (provider, sortedDates.map { ($0, byDate[$0]!) })
        }
    }

    private func groupByConversation(_ logs: [ParsedLog]) -> [(String?, [ParsedLog])] {
        var byConv: [String?: [ParsedLog]] = [:]
        for log in logs {
            byConv[log.conversationId, default: []].append(log)
        }
        var result: [(String?, [ParsedLog])] = []
        for (key, var logs) in byConv {
            logs.sort { $0.timestamp < $1.timestamp }
            result.append((key, logs))
        }
        result.sort { entry1, entry2 in
            let t1 = entry1.1.first?.timestamp ?? .distantPast
            let t2 = entry2.1.first?.timestamp ?? .distantPast
            return t1 > t2
        }
        return result
    }

    // MARK: - Rendering

    private func renderHeader(_ compilation: LogCompilation, logCount: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.locale = Locale(identifier: "zh_CN")

        let providerNames = compilation.providerFilters.compactMap { LLMProvider(rawValue: $0)?.displayName }
        let providersStr = providerNames.isEmpty ? "全部" : providerNames.joined(separator: ", ")

        return """
        # \(compilation.name)

        > \(compilation.description.isEmpty ? "" : compilation.description)
        > 生成时间: \(df.string(from: Date()))
        > 覆盖范围: \(compilation.startDate.map { df.string(from: $0) } ?? "起始") 至 \(compilation.endDate.map { df.string(from: $0) } ?? "现在")
        > 提供商: \(providersStr)
        > 日志数量: \(logCount) 条

        ---

        """
    }

    private func renderProviderHeader(_ provider: LLMProvider, logs: [(String, [ParsedLog])]) -> String {
        let count = logs.reduce(0) { $0 + $1.1.count }
        return "## \(provider.displayName) (\(count) 条)\n\n"
    }

    private func renderDateHeader(_ date: String) -> String {
        return "### \(date)\n\n"
    }

    private func renderConversation(_ convId: String?, logs: [ParsedLog], format: CompilationOutputFormat) -> String {
        switch format {
        case .markdown:
            return renderConversationMarkdown(convId, logs: logs)
        case .json:
            return renderConversationJSON(convId, logs: logs)
        case .plainText:
            return renderConversationPlainText(convId, logs: logs)
        }
    }

    private func renderConversationMarkdown(_ convId: String?, logs: [ParsedLog]) -> String {
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"

        var parts: [String] = []
        let label = convId.map { "对话 \($0.prefix(8))" } ?? "独立记录"
        parts.append("#### \(label) (\(logs.count) 条)\n")

        for log in logs {
            let time = tf.string(from: log.timestamp)
            let model = log.modelName ?? "unknown"
            let tokens = log.totalTokens.map { "\($0) tokens" } ?? ""
            let cost = log.estimatedCost.map { $0.formattedCurrency } ?? ""
            let duration = log.duration.map { $0.formattedDuration } ?? ""

            if let prompt = log.prompt, !prompt.isEmpty {
                let meta = [tokens, cost].filter { !$0.isEmpty }.joined(separator: " | ")
                parts.append("**[\(time)] User** (\(model)\(meta.isEmpty ? "" : " | \(meta)")):\n")
                parts.append("\(prompt.trimmingCharacters(in: .whitespacesAndNewlines))\n")
            }

            if let response = log.response, !response.isEmpty {
                let meta = [duration, tokens, cost].filter { !$0.isEmpty }.joined(separator: " | ")
                parts.append("**[\(time)] Assistant** (\(meta.isEmpty ? "" : "\(meta)")):\n")
                parts.append("\(response.trimmingCharacters(in: .whitespacesAndNewlines))\n")
            }

            if let error = log.errorMessage, !error.isEmpty {
                parts.append("**[\(time)] Error:** \(error)\n")
            }
        }

        parts.append("\n---\n\n")
        return parts.joined()
    }

    private func renderConversationJSON(_ convId: String?, logs: [ParsedLog]) -> String {
        let turns = logs.map { log -> String in
            let tf = DateFormatter()
            tf.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            var obj: [String: Any] = [
                "timestamp": tf.string(from: log.timestamp),
                "model": log.modelName ?? "unknown"
            ]
            if let p = log.prompt { obj["prompt"] = p }
            if let r = log.response { obj["response"] = r }
            if let t = log.totalTokens { obj["tokens"] = t }
            if let c = log.estimatedCost { obj["cost"] = c }
            if let d = log.duration { obj["duration"] = d }
            if let e = log.errorMessage { obj["error"] = e }

            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "{}"
        }
        let convLabel = convId ?? "standalone"
        return "\"conversation_\(convLabel.prefix(8))\": [\n\(turns.joined(separator: ",\n"))\n],\n"
    }

    private func renderConversationPlainText(_ convId: String?, logs: [ParsedLog]) -> String {
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"

        var parts: [String] = []
        let label = convId.map { "对话 \($0.prefix(8))" } ?? "独立记录"
        parts.append("[\(label) - \(logs.count) 条]\n")

        for log in logs {
            let time = tf.string(from: log.timestamp)
            if let prompt = log.prompt, !prompt.isEmpty {
                parts.append("[\(time)] User: \(prompt)\n")
            }
            if let response = log.response, !response.isEmpty {
                parts.append("[\(time)] Assistant: \(response)\n")
            }
            if let error = log.errorMessage, !error.isEmpty {
                parts.append("[\(time)] Error: \(error)\n")
            }
        }

        parts.append("\n---\n\n")
        return parts.joined()
    }

    private func renderAppendix(_ logs: [ParsedLog], format: CompilationOutputFormat) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        let header = "## 追加日志 (\(df.string(from: Date())))\n\n共 \(logs.count) 条新日志\n\n---\n\n"
        let grouped = groupLogs(logs)

        var content = header
        for (provider, byDate) in grouped {
            content += renderProviderHeader(provider, logs: byDate)
            for (date, dateLogs) in byDate {
                content += renderDateHeader(date)
                for (convId, convLogs) in groupByConversation(dateLogs) {
                    content += renderConversation(convId, logs: convLogs, format: format)
                }
            }
        }
        return content
    }

    private func renderSummary(_ compilation: LogCompilation, stats: CompilationStats, totalLogs: Int) -> String {
        switch compilation.outputFormat {
        case .markdown:
            return """

            ---

            ## 统计摘要

            | 指标 | 值 |
            |------|-----|
            | 总调用数 | \(totalLogs) |
            | 提供商数 | \(stats.providers.count) |
            | 模型数 | \(stats.models.count) |
            | 总 Token | \(stats.totalTokens.formattedCompact) |
            | 预估费用 | \(stats.totalCost.formattedCurrency) |
            | 错误数 | \(stats.errorCount) |

            _本文档由 Agent Blackbox 自动生成于 \(Date().formattedDate)_
            _共编译 \(totalLogs) 条日志，涵盖 \(stats.providers.count) 个提供商_

            """
        case .json:
            let footer = "\"summary\": {\n"
                + "  \"totalLogs\": \(totalLogs),\n"
                + "  \"providers\": \(stats.providers.count),\n"
                + "  \"models\": \(stats.models.count),\n"
                + "  \"totalTokens\": \(stats.totalTokens),\n"
                + "  \"totalCost\": \(stats.totalCost),\n"
                + "  \"errors\": \(stats.errorCount)\n"
                + "}\n}\n"
            return footer
        case .plainText:
            return """

            ---
            统计: \(totalLogs) 条日志 | \(stats.providers.count) 个提供商 | \(stats.totalTokens.formattedCompact) tokens | \(stats.totalCost.formattedCurrency) | \(stats.errorCount) 个错误
            生成于 \(Date().formattedDate)
            """
        }
    }

    // MARK: - Stats

    private struct CompilationStats {
        var providers: [String]
        var models: [String]
        var totalTokens: Int
        var totalCost: Double
        var errorCount: Int
    }

    private func computeStats(_ logs: [ParsedLog]) -> CompilationStats {
        var providers = Set<String>()
        var models = Set<String>()
        var totalTokens = 0
        var totalCost = 0.0
        var errorCount = 0

        for log in logs {
            if let p = log.provider { providers.insert(p.rawValue) }
            if let m = log.modelName { models.insert(m) }
            totalTokens += log.totalTokens ?? 0
            totalCost += log.estimatedCost ?? 0
            if log.errorMessage != nil { errorCount += 1 }
        }

        return CompilationStats(
            providers: providers.sorted(),
            models: models.sorted(),
            totalTokens: totalTokens,
            totalCost: totalCost,
            errorCount: errorCount
        )
    }

    // MARK: - File I/O

    private func writeOutput(compilation: LogCompilation, content: String) -> URL? {
        do {
            try createCompilationsDir()
            let safeName = compilation.name
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            let filename = "\(safeName)-\(compilation.id.uuidString.prefix(8)).\(compilation.outputFormat.fileExtension)"
            let url = compilationsDir.appendingPathComponent(filename)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            Logger.shared.error("写入编译输出失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Persistence

    private func saveCompilation(_ compilation: LogCompilation) {
        guard let db else { return }
        do {
            let filters = (try? String(data: JSONSerialization.data(withJSONObject: compilation.providerFilters), encoding: .utf8)) ?? "[]"
            let compProviders = (try? String(data: JSONSerialization.data(withJSONObject: compilation.compiledProviders), encoding: .utf8)) ?? "[]"
            let compModels = (try? String(data: JSONSerialization.data(withJSONObject: compilation.compiledModels), encoding: .utf8)) ?? "[]"

            let target = compilationsTable.filter(colId == compilation.id.uuidString)
            let count = try db.scalar(target.count)

            let values: [SQLite.Setter] = [
                colName <- compilation.name,
                colDesc <- compilation.description,
                colCreatedAt <- compilation.createdAt.timeIntervalSince1970,
                colUpdatedAt <- compilation.updatedAt.timeIntervalSince1970,
                colStatus <- compilation.status.rawValue,
                colOutputFormat <- compilation.outputFormat.rawValue,
                colProviderFilters <- filters,
                colStartDate <- compilation.startDate?.timeIntervalSince1970,
                colEndDate <- compilation.endDate?.timeIntervalSince1970,
                colBookmarkedOnly <- compilation.bookmarkedOnly,
                colLastCompiledTs <- compilation.lastCompiledTimestamp?.timeIntervalSince1970,
                colTotalLogCount <- compilation.totalLogCount,
                colAppendCount <- compilation.appendCount,
                colProgress <- compilation.progress,
                colProgressMsg <- compilation.progressMessage,
                colOutputPath <- compilation.outputFilePath,
                colOutputSize <- compilation.outputFileSize,
                colCompiledProviders <- compProviders,
                colCompiledModels <- compModels,
                colCompiledTokenTotal <- compilation.compiledTokenTotal,
                colCompiledCostTotal <- compilation.compiledCostTotal
            ]

            if count > 0 {
                try db.run(target.update(values))
            } else {
                try db.run(compilationsTable.insert(
                    colId <- compilation.id.uuidString,
                    colName <- compilation.name,
                    colDesc <- compilation.description,
                    colCreatedAt <- compilation.createdAt.timeIntervalSince1970,
                    colUpdatedAt <- compilation.updatedAt.timeIntervalSince1970,
                    colStatus <- compilation.status.rawValue,
                    colOutputFormat <- compilation.outputFormat.rawValue,
                    colProviderFilters <- filters,
                    colStartDate <- compilation.startDate?.timeIntervalSince1970,
                    colEndDate <- compilation.endDate?.timeIntervalSince1970,
                    colBookmarkedOnly <- compilation.bookmarkedOnly,
                    colLastCompiledTs <- compilation.lastCompiledTimestamp?.timeIntervalSince1970,
                    colTotalLogCount <- compilation.totalLogCount,
                    colAppendCount <- compilation.appendCount,
                    colProgress <- compilation.progress,
                    colProgressMsg <- compilation.progressMessage,
                    colOutputPath <- compilation.outputFilePath,
                    colOutputSize <- compilation.outputFileSize,
                    colCompiledProviders <- compProviders,
                    colCompiledModels <- compModels,
                    colCompiledTokenTotal <- compilation.compiledTokenTotal,
                    colCompiledCostTotal <- compilation.compiledCostTotal
                ))
            }
        } catch {
            Logger.shared.error("保存编译失败: \(error.localizedDescription)")
        }
    }

    private func rowToCompilation(_ row: Row) -> LogCompilation {
        let pFilters = (try? JSONSerialization.jsonObject(with: Data(row[colProviderFilters].utf8))) as? [String] ?? []
        let cProviders = (try? JSONSerialization.jsonObject(with: Data(row[colCompiledProviders].utf8))) as? [String] ?? []
        let cModels = (try? JSONSerialization.jsonObject(with: Data(row[colCompiledModels].utf8))) as? [String] ?? []

        return LogCompilation(
            id: UUID(uuidString: row[colId]) ?? UUID(),
            name: row[colName],
            description: row[colDesc],
            createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
            updatedAt: Date(timeIntervalSince1970: row[colUpdatedAt]),
            status: CompilationStatus(rawValue: row[colStatus]) ?? .pending,
            outputFormat: CompilationOutputFormat(rawValue: row[colOutputFormat]) ?? .markdown,
            providerFilters: pFilters,
            startDate: row[colStartDate].map { Date(timeIntervalSince1970: $0) },
            endDate: row[colEndDate].map { Date(timeIntervalSince1970: $0) },
            bookmarkedOnly: row[colBookmarkedOnly],
            lastCompiledTimestamp: row[colLastCompiledTs].map { Date(timeIntervalSince1970: $0) },
            totalLogCount: row[colTotalLogCount],
            appendCount: row[colAppendCount],
            progress: row[colProgress],
            progressMessage: row[colProgressMsg],
            outputFilePath: row[colOutputPath],
            outputFileSize: row[colOutputSize],
            compiledProviders: cProviders,
            compiledModels: cModels,
            compiledTokenTotal: row[colCompiledTokenTotal],
            compiledCostTotal: row[colCompiledCostTotal]
        )
    }
}

// MARK: - String Helper

private extension String {
    func prefix(_ maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(self[self.startIndex..<self.index(self.startIndex, offsetBy: maxLength)])
    }
}
