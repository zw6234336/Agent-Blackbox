import Foundation

/// Pi (Inflection AI) 数据采集器。
///
/// 支持三种日志源：
/// 1. JSON/JSONL 对话导出文件（Pi 网页版导出、API 调用记录）
///    - 标准 chat completion 格式: {"messages": [{"role":"user","content":"..."}, ...]}
///    - JSONL 逐行记录: {"role":"user","content":"...","timestamp":"..."}
/// 2. Pi API 日志（text 格式）
///    - 包含请求/响应、token 用量、耗时等信息
/// 3. 本地缓存对话数据（browser local storage dump）
///
/// Pi 的模型名称通常是: inflection-3, inflection-3-pi, inflection-2.5 等
struct PiParser: LogParser {
    let supportedProvider: LLMProvider = .pi

    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()

        // Pi 专属目录下的文件
        if path.contains("/.pi/") || path.contains("/com.inflection.pi/") {
            return true
        }
        // Pi Application Support / Logs 目录
        if (path.contains("/application support/pi/") || path.contains("/logs/pi/"))
            && (name.hasSuffix(".json") || name.hasSuffix(".jsonl") || name.hasSuffix(".log")) {
            return true
        }
        // 文件名包含 pi 且包含 Inflection 特征内容
        if name.contains("pi") && name.hasSuffix(".json") {
            return content.contains("inflection") || content.contains("\"pi\"")
        }
        // 内容特征检测：Inflection API 响应或对话格式
        if content.contains("inflection-3") || content.contains("inflection-2") || content.contains("pi.ai") {
            // 排除其他客户端/编辑器的私有日志路径，防止误判通用日志（例如 LSP 索引、VSCode 插件日志）
            if path.contains("/code/") || path.contains("/cursor/") || path.contains("/claude/") || path.contains("/warp/") || path.contains("/saoudrizwan.claude-dev/") {
                return false
            }
            return true
        }

        return false
    }

    /// Extract text from content field (handles String and [[String: Any]] content-blocks)
    private func extractContent(_ raw: Any?) -> String {
        if let str = raw as? String {
            return str
        }
        // Handle content-blocks array: [{"type":"text","text":"..."}]
        if let blocks = raw as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        let ext = url.pathExtension.lowercased()

        if ext == "jsonl" {
            return parseJSONL(url: url, content: content)
        }
        if ext == "json" {
            return parseJSON(url: url, content: content)
        }
        if ext == "log" || ext == "txt" {
            return parseTextLog(url: url, content: content)
        }

        // 尝试按 JSON 解析
        if content.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "{") {
            return parseJSON(url: url, content: content)
        }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "[") {
            return parseJSONArray(url: url, content: content)
        }

        return parseTextLog(url: url, content: content)
    }

    // MARK: - JSON Parsing

    /// 解析单条 JSON 对象（可能是完整对话或单条消息）
    private func parseJSON(url: URL, content: String) -> [ParsedLog] {
        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // 格式1: {"messages": [...]} — 完整对话
        if let messages = obj["messages"] as? [[String: Any]] {
            return parseConversationMessages(url: url, messages: messages, metadata: obj)
        }

        // 格式2: Chat completion 响应: {"choices": [{"message": {"role":"assistant","content":"..."}}], "usage": {...}}
        if let choices = obj["choices"] as? [[String: Any]] {
            return parseChatCompletionResponse(url: url, obj: obj, choices: choices)
        }

        // 格式3: 单条消息记录: {"role":"user", "content":"...", "timestamp":"..."}
        if let role = obj["role"] as? String {
            let msgContent = extractContent(obj["content"])
            if !msgContent.isEmpty {
                return [parseSingleMessage(url: url, obj: obj, role: role, content: msgContent)]
            }
        }

        // 格式4: Pi 导出格式: {"conversations": [{"id":"...", "messages":[...]}]}
        if let conversations = obj["conversations"] as? [[String: Any]] {
            return conversations.flatMap { conv -> [ParsedLog] in
                let convId = conv["id"] as? String
                let msgs = conv["messages"] as? [[String: Any]] ?? []
                return parseConversationMessages(url: url, messages: msgs, metadata: conv, conversationId: convId)
            }
        }

        return []
    }

    /// 解析 JSON 数组（多条消息/对话）
    private func parseJSONArray(url: URL, content: String) -> [ParsedLog] {
        guard let data = content.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        // 检查是否是对话数组
        if let first = array.first, first["messages"] != nil {
            return array.flatMap { conv -> [ParsedLog] in
                let convId = conv["id"] as? String
                let msgs = conv["messages"] as? [[String: Any]] ?? []
                return parseConversationMessages(url: url, messages: msgs, metadata: conv, conversationId: convId)
            }
        }

        // 否则作为消息数组处理
        return array.compactMap { obj -> ParsedLog? in
            guard let role = obj["role"] as? String else { return nil }
            let msgContent = extractContent(obj["content"])
            guard !msgContent.isEmpty else { return nil }
            return parseSingleMessage(url: url, obj: obj, role: role, content: msgContent)
        }
    }

    // MARK: - JSONL Parsing

    /// 解析 JSONL 格式（每行一条 JSON 记录）
    private func parseJSONL(url: URL, content: String) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines)
        var results: [ParsedLog] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // 单条消息格式
            if let role = obj["role"] as? String {
                let msgContent = extractContent(obj["content"])
                guard !msgContent.isEmpty else { continue }
                results.append(parseSingleMessage(url: url, obj: obj, role: role, content: msgContent))
                continue
            }

            // Chat completion 格式
            if let choices = obj["choices"] as? [[String: Any]] {
                results.append(contentsOf: parseChatCompletionResponse(url: url, obj: obj, choices: choices))
            }
        }

        return results
    }

    // MARK: - Text Log Parsing

    /// 解析文本格式日志（API 调用日志等）
    private func parseTextLog(url: URL, content: String) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines)
        var results: [ParsedLog] = []
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // 检测 API 调用行（必须明确包含 inflection 或 pi.ai，防止误判通用的 /v1/chat/completions）
            if trimmed.contains("inflection") || trimmed.contains("pi.ai") {
                let timestamp = extractTimestamp(from: trimmed) ?? fileDate
                let model = firstMatch(in: trimmed, pattern: #"inflection[\w\-.]+"#)
                    ?? firstMatch(in: trimmed, pattern: #"model["':\s]+([\w\-.]+)"#)

                let tokens = firstMatch(in: trimmed, pattern: #"tokens?[:\s]+(\d+)"#)
                let error = firstMatch(in: trimmed, pattern: #"(?:error|ERROR)[:\s]+(.+)"#)
                let duration = firstMatch(in: trimmed, pattern: #"(?:duration|elapsed|latency)[:\s]+([\d.]+)\s*(?:ms|s)"#)

                results.append(ParsedLog(
                    timestamp: timestamp,
                    sourceFile: url.path,
                    provider: .pi,
                    modelName: model,
                    totalTokens: tokens.flatMap(Int.init),
                    duration: duration.flatMap { parseDurationString($0) },
                    errorMessage: maskAPIKey(error),
                    metadata: ["format": "pi_text_log", "client": "pi"]
                ))
            }
        }

        return results
    }

    // MARK: - Helper Parsers

    /// 解析一组对话消息，合并相邻的 user/assistant 为 ParsedLog
    private func parseConversationMessages(
        url: URL,
        messages: [[String: Any]],
        metadata: [String: Any],
        conversationId: String? = nil
    ) -> [ParsedLog] {
        var results: [ParsedLog] = []
        var pendingUserPrompt: String?
        var pendingTimestamp: Date?

        let convId = conversationId ?? metadata["id"] as? String
        let model = metadata["model"] as? String ?? detectModel(from: metadata)

        for msg in messages {
            let role = msg["role"] as? String ?? ""
            let msgContent = extractContent(msg["content"])
            let timestamp = parseTimestamp(from: msg)

            if role == "user" || role == "human" {
                pendingUserPrompt = maskAPIKey(msgContent)
                pendingTimestamp = timestamp
            } else if role == "assistant" || role == "ai" || role == "bot" {
                let promptTokens = msg["prompt_tokens"] as? Int ?? msg["inputTokens"] as? Int
                let completionTokens = msg["completion_tokens"] as? Int ?? msg["outputTokens"] as? Int
                let tokenSum = (promptTokens ?? 0) + (completionTokens ?? 0)
                let totalTokens: Int? = tokenSum > 0 ? tokenSum : nil
                let cost = estimateCost(model: model, promptTokens: promptTokens, completionTokens: completionTokens)

                results.append(ParsedLog(
                    timestamp: pendingTimestamp ?? timestamp ?? Date(),
                    sourceFile: url.path,
                    provider: .pi,
                    modelName: model,
                    prompt: pendingUserPrompt,
                    response: maskAPIKey(msgContent),
                    promptTokens: promptTokens ?? estimateTokenCount(pendingUserPrompt),
                    completionTokens: completionTokens ?? estimateTokenCount(msgContent),
                    totalTokens: totalTokens,
                    estimatedCost: cost,
                    conversationId: convId,
                    metadata: ["format": "pi_conversation", "client": "pi"]
                ))
                pendingUserPrompt = nil
                pendingTimestamp = nil
            }
        }

        return results
    }

    /// 解析 chat completion API 响应
    private func parseChatCompletionResponse(
        url: URL,
        obj: [String: Any],
        choices: [[String: Any]]
    ) -> [ParsedLog] {
        guard let choice = choices.first,
              let message = choice["message"] as? [String: Any] else {
            return []
        }

        let role = message["role"] as? String ?? "assistant"
        let content = extractContent(message["content"])
        let model = obj["model"] as? String ?? "inflection-3-pi"

        let usage = obj["usage"] as? [String: Any]
        let promptTokens = usage?["prompt_tokens"] as? Int
        let completionTokens = usage?["completion_tokens"] as? Int
        let totalTokens = usage?["total_tokens"] as? Int
            ?? (promptTokens ?? 0) + (completionTokens ?? 0)
        let cost = estimateCost(model: model, promptTokens: promptTokens, completionTokens: completionTokens)

        let timestamp: Date = {
            if let created = obj["created"] as? Double {
                return Date(timeIntervalSince1970: created)
            }
            return (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        }()

        let errorMessage = (obj["error"] as? [String: Any])?["message"] as? String
            ?? obj["error"] as? String

        return [ParsedLog(
            timestamp: timestamp,
            sourceFile: url.path,
            provider: .pi,
            modelName: model,
            prompt: role == "user" && !content.isEmpty ? content : nil,
            response: role == "assistant" && !content.isEmpty ? maskAPIKey(content) : nil,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens > 0 ? totalTokens : nil,
            estimatedCost: cost,
            errorMessage: maskAPIKey(errorMessage),
            metadata: ["format": "pi_chat_completion", "client": "pi"]
        )]
    }

    /// 解析单条消息记录
    private func parseSingleMessage(url: URL, obj: [String: Any], role: String, content: String) -> ParsedLog {
        let timestamp = parseTimestamp(from: obj) ?? Date()
        let model = obj["model"] as? String ?? "inflection-3-pi"

        return ParsedLog(
            timestamp: timestamp,
            sourceFile: url.path,
            provider: .pi,
            modelName: model,
            prompt: (role == "user" || role == "human") ? maskAPIKey(content) : nil,
            response: (role == "assistant" || role == "ai") ? maskAPIKey(content) : nil,
            promptTokens: obj["prompt_tokens"] as? Int ?? ((role == "user" || role == "human") ? estimateTokenCount(content) : nil),
            completionTokens: obj["completion_tokens"] as? Int ?? ((role == "assistant" || role == "ai") ? estimateTokenCount(content) : nil),
            metadata: [
                "format": "pi_single_message",
                "client": "pi",
                "role": role
            ]
        )
    }

    // MARK: - Utilities

    private func parseTimestamp(from obj: [String: Any]) -> Date? {
        if let ts = obj["timestamp"] as? String {
            return parseDate(from: ts)
        }
        if let ts = obj["created_at"] as? String {
            return parseDate(from: ts)
        }
        if let ts = obj["ts"] as? Double {
            return ts > 1e12 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
        }
        if let ts = obj["timestamp"] as? Double {
            return ts > 1e12 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
        }
        return nil
    }

    private func detectModel(from obj: [String: Any]) -> String? {
        if let model = obj["model"] as? String { return model }
        if let engine = obj["engine"] as? String { return engine }
        return nil
    }

    /// 粗略估算 token 数量（中文约 1.5 token/字，英文约 0.25 token/字）
    private func estimateTokenCount(_ text: String?) -> Int {
        guard let text else { return 0 }
        var count = 0
        for char in text {
            count += char.isASCII ? 1 : 2
        }
        return max(1, count / 4)
    }

    /// 估算 Pi API 调用成本（Inflection API 定价）
    private func estimateCost(model: String?, promptTokens: Int?, completionTokens: Int?) -> Double? {
        guard let pt = promptTokens, let ct = completionTokens else { return nil }
        let modelLower = model?.lowercased() ?? ""

        // Inflection-3 定价（估算）: $2/M input, $8/M output
        let inputPer1K: Double
        let outputPer1K: Double

        if modelLower.contains("inflection-3") {
            inputPer1K = 0.002
            outputPer1K = 0.008
        } else if modelLower.contains("inflection-2.5") {
            inputPer1K = 0.001
            outputPer1K = 0.004
        } else {
            inputPer1K = 0.002
            outputPer1K = 0.008
        }

        return Double(pt) / 1000.0 * inputPer1K + Double(ct) / 1000.0 * outputPer1K
    }

    private func parseDurationString(_ s: String) -> TimeInterval? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("ms") {
            return Double(trimmed.replacingOccurrences(of: "ms", with: "")).map { $0 / 1000.0 }
        }
        if trimmed.hasSuffix("s") {
            return Double(trimmed.replacingOccurrences(of: "s", with: ""))
        }
        return Double(trimmed)
    }
}
