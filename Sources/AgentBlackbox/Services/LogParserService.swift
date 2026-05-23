import Foundation

/// Parses log file content into `LogEntry` records for each supported LLM platform.
final class LogParserService {

    func parse(content: String, platform: LLMPlatform, filePath: String) -> [LogEntry] {
        switch platform {
        case .ollama:
            return parseOllama(content: content, filePath: filePath)
        case .copilot:
            return parseCopilot(content: content, filePath: filePath)
        default:
            return parseGeneric(content: content, platform: platform, filePath: filePath)
        }
    }

    // MARK: - Ollama

    private func parseOllama(content: String, filePath: String) -> [LogEntry] {
        var entries: [LogEntry] = []
        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }

            // Ollama API response payloads contain {"model":...}
            guard let jsonStart = line.range(of: "{\"model\""),
                  let data = String(line[jsonStart...]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let raw = String(line[jsonStart...])
            let entry = LogEntry(
                id: LogEntry.stableID(filePath: filePath, rawContent: raw),
                platform: .ollama,
                timestamp: parseTimestamp(json["created_at"] as? String ?? "") ?? Date(),
                prompt: extractPrompt(from: json),
                response: extractOllamaResponse(from: json),
                model: json["model"] as? String,
                inputTokens: json["prompt_eval_count"] as? Int,
                outputTokens: json["eval_count"] as? Int,
                rawContent: raw,
                filePath: filePath,
                metadata: extractOllamaMeta(from: json)
            )
            entries.append(entry)
        }
        return entries
    }

    // MARK: - GitHub Copilot

    private func parseCopilot(content: String, filePath: String) -> [LogEntry] {
        var entries: [LogEntry] = []
        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty, line.hasPrefix("{"),
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let typeStr = (json["type"] as? String ?? "").lowercased()
            guard typeStr.contains("completion") || typeStr.contains("chat")
               || typeStr.contains("request") || typeStr.contains("response") else {
                continue
            }
            let entry = LogEntry(
                id: LogEntry.stableID(filePath: filePath, rawContent: line),
                platform: .copilot,
                timestamp: parseTimestamp(json["timestamp"] as? String ?? "") ?? Date(),
                prompt: json["prompt"] as? String ?? json["prefix"] as? String,
                response: json["completion"] as? String ?? json["text"] as? String,
                model: json["model"] as? String ?? json["engine"] as? String,
                rawContent: line,
                filePath: filePath
            )
            entries.append(entry)
        }
        return entries
    }

    // MARK: - Generic (JSON, JSON array, NDJSON, plain-text)

    private func parseGeneric(content: String, platform: LLMPlatform, filePath: String) -> [LogEntry] {
        guard let data = content.data(using: .utf8) else { return [] }

        // Single JSON object
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return [jsonToEntry(json, platform: platform, filePath: filePath, raw: content)]
        }

        // JSON array
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.map { jsonToEntry($0, platform: platform, filePath: filePath, raw: content) }
        }

        // NDJSON
        var entries: [LogEntry] = []
        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty, line.hasPrefix("{"),
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            entries.append(jsonToEntry(json, platform: platform, filePath: filePath, raw: line))
        }

        // Fallback: store entire file as a single raw entry
        if entries.isEmpty && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entries.append(LogEntry(
                id: LogEntry.stableID(filePath: filePath, rawContent: content),
                platform: platform,
                rawContent: content,
                filePath: filePath
            ))
        }
        return entries
    }

    // MARK: - JSON → LogEntry

    private func jsonToEntry(
        _ json: [String: Any],
        platform: LLMPlatform,
        filePath: String,
        raw: String
    ) -> LogEntry {
        let promptKeys   = ["prompt", "input", "question", "query", "user_message", "content"]
        let responseKeys = ["response", "output", "answer", "completion", "result",
                            "assistant_message", "generated_text", "text"]
        let modelKeys    = ["model", "engine", "model_name", "model_id"]

        let prompt   = promptKeys.compactMap { json[$0] as? String }.first
                    ?? messagesContent(from: json, role: "user")
        let response = responseKeys.compactMap { json[$0] as? String }.first
                    ?? messagesContent(from: json, role: "assistant")
                    ?? choiceText(from: json)
        let model    = modelKeys.compactMap { json[$0] as? String }.first

        var inputTokens: Int?
        var outputTokens: Int?
        var totalTokens: Int?
        if let usage = json["usage"] as? [String: Any] {
            inputTokens  = usage["input_tokens"]  as? Int ?? usage["prompt_tokens"]     as? Int
            outputTokens = usage["output_tokens"] as? Int ?? usage["completion_tokens"] as? Int
            totalTokens  = usage["total_tokens"]  as? Int
        }

        let tsString = json["timestamp"] as? String
                    ?? json["created_at"] as? String
                    ?? json["time"] as? String
                    ?? ""
        let timestamp = parseTimestamp(tsString) ?? Date()

        var metadata: [String: String] = [:]
        for key in ["stop_reason", "finish_reason", "done_reason", "total_duration"] {
            if let v = json[key] { metadata[key] = "\(v)" }
        }

        return LogEntry(
            id: LogEntry.stableID(filePath: filePath, rawContent: raw),
            platform: platform,
            timestamp: timestamp,
            prompt: prompt,
            response: response,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            rawContent: raw,
            filePath: filePath,
            metadata: metadata
        )
    }

    // MARK: - Helpers

    private func messagesContent(from json: [String: Any], role: String) -> String? {
        guard let messages = json["messages"] as? [[String: Any]] else { return nil }
        let texts = messages
            .filter { ($0["role"] as? String) == role }
            .compactMap { $0["content"] as? String }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private func choiceText(from json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else { return nil }
        if let text = first["text"] as? String { return text }
        if let msg = first["message"] as? [String: Any] { return msg["content"] as? String }
        if let delta = first["delta"] as? [String: Any] { return delta["content"] as? String }
        return nil
    }

    private func extractPrompt(from json: [String: Any]) -> String? {
        if let p = json["prompt"] as? String { return p }
        return messagesContent(from: json, role: "user")
    }

    private func extractOllamaResponse(from json: [String: Any]) -> String? {
        if let r = json["response"] as? String { return r }
        if let msg = json["message"] as? [String: Any] { return msg["content"] as? String }
        return nil
    }

    private func extractOllamaMeta(from json: [String: Any]) -> [String: String] {
        var meta: [String: String] = [:]
        for key in ["done_reason", "total_duration", "load_duration", "eval_duration"] {
            if let v = json[key] { meta[key] = "\(v)" }
        }
        return meta
    }

    private func parseTimestamp(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }

        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss"
        ]
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let d = df.date(from: string) { return d }
        }

        // Try to extract an ISO-like substring from a longer log line.
        // Matches timestamps of the form YYYY-MM-DD<T or space>HH:MM:SS
        let pattern = #"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"#
        if let range = string.range(of: pattern, options: .regularExpression) {
            return parseTimestamp(String(string[range]))
        }
        return nil
    }
}
