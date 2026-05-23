import Foundation

/// 解析 Amp (Sourcegraph) 的本地 thread JSON：
///   ~/.local/share/amp/threads/T-<uuid>.json
///
/// 结构：
/// { id, title, messages: [
///     { role: "user", content: [{type:"text", text:"..."}] },
///     { role: "assistant", content: [{type:"thinking"|"tool_use"|"text", ...}],
///       usage: { model, inputTokens, outputTokens,
///                cacheCreationInputTokens, cacheReadInputTokens,
///                totalInputTokens, timestamp } }
/// ]}
struct AmpThreadParser: LogParser {
    let supportedProvider: LLMProvider = .amp

    func canParse(url: URL, content: String) -> Bool {
        let path = url.path
        let name = url.lastPathComponent
        return path.contains("/amp/threads/") && name.hasPrefix("T-") && name.hasSuffix(".json")
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let threadId = obj["id"] as? String ?? url.deletingPathExtension().lastPathComponent
        let title = obj["title"] as? String
        guard let messages = obj["messages"] as? [[String: Any]] else { return [] }

        var results: [ParsedLog] = []
        var pendingPrompt: String? = nil
        var pendingPromptTimestamp: Date? = nil

        for message in messages {
            let role = message["role"] as? String ?? ""
            let contentText = extractText(from: message["content"])

            switch role {
            case "user":
                if let t = contentText, !t.isEmpty {
                    pendingPrompt = t
                    // user 消息没显式时间戳，等下条 assistant.usage.timestamp 比对
                }

            case "assistant":
                let usage = message["usage"] as? [String: Any]
                guard let usage else { continue }

                let model = usage["model"] as? String
                let inputTokens = (usage["inputTokens"] as? Int) ?? 0
                let outputTokens = (usage["outputTokens"] as? Int) ?? 0
                let cacheCreation = (usage["cacheCreationInputTokens"] as? Int) ?? 0
                let cacheRead = (usage["cacheReadInputTokens"] as? Int) ?? 0
                let totalInput = (usage["totalInputTokens"] as? Int) ?? (inputTokens + cacheCreation + cacheRead)
                let timestamp = parseTimestamp(usage["timestamp"]) ?? Date()

                // 跳过纯空段
                if totalInput == 0 && outputTokens == 0 && (contentText?.isEmpty ?? true) {
                    continue
                }

                let duration: TimeInterval? = pendingPromptTimestamp.map {
                    max(0.001, timestamp.timeIntervalSince($0))
                }

                let log = ParsedLog(
                    timestamp: timestamp,
                    sourceFile: url.path,
                    provider: providerFor(model: model),
                    modelName: model,
                    prompt: pendingPrompt,
                    response: contentText,
                    promptTokens: totalInput > 0 ? totalInput : nil,
                    completionTokens: outputTokens > 0 ? outputTokens : nil,
                    totalTokens: (totalInput + outputTokens) > 0 ? totalInput + outputTokens : nil,
                    duration: duration,
                    conversationId: threadId,
                    metadata: [
                        "format": "amp_thread",
                        "client": "amp",
                        "thread_title": title ?? "",
                        "cache_creation_tokens": "\(cacheCreation)",
                        "cache_read_tokens": "\(cacheRead)"
                    ]
                )
                results.append(log)
                pendingPromptTimestamp = timestamp
                pendingPrompt = nil

            default:
                continue
            }
        }
        return results
    }

    // MARK: - Helpers

    private func extractText(from value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        if let arr = value as? [[String: Any]] {
            let parts: [String] = arr.compactMap { item in
                let type = item["type"] as? String
                switch type {
                case "text":     return item["text"] as? String
                case "thinking": return (item["thinking"] as? String).map { "[thinking] \($0)" }
                case "tool_use":
                    let name = item["name"] as? String ?? "tool"
                    return "[tool_use: \(name)]"
                case "tool_result":
                    if let c = item["content"] as? String { return "[tool_result] \(c)" }
                    if let c = item["content"] as? [[String: Any]] {
                        let texts = c.compactMap { $0["text"] as? String }
                        return "[tool_result] \(texts.joined(separator: "\n"))"
                    }
                    return nil
                default: return nil
                }
            }
            let joined = parts.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private func parseTimestamp(_ value: Any?) -> Date? {
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            return iso2.date(from: s)
        }
        if let d = value as? Double {
            return d > 10_000_000_000 ? Date(timeIntervalSince1970: d / 1000.0) : Date(timeIntervalSince1970: d)
        }
        return nil
    }

    /// Amp 默认走 Anthropic 但允许其它，以 model 名识别
    private func providerFor(model: String?) -> LLMProvider {
        guard let m = model?.lowercased() else { return .amp }
        if m.contains("claude")   { return .anthropic }
        if m.contains("gpt") || m.contains("o1") || m.contains("o3") || m.contains("o4") { return .openai }
        if m.contains("gemini") || m.contains("palm") { return .google }
        if m.contains("deepseek") { return .deepseek }
        if m.contains("qwen")     { return .qwen }
        if m.contains("kimi") || m.contains("moonshot") { return .kimi }
        if m.contains("glm")      { return .zhipu }
        return .amp
    }
}
