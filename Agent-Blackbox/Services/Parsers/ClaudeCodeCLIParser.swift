import Foundation

/// 解析 Claude Code CLI 日志:
///   - ~/.claude/history.jsonl                — 用户 prompt 历史（无 token）
///   - ~/.claude/projects/<proj>/<sid>.jsonl  — 完整对话（含 message.model + usage tokens）
///
/// projects/*.jsonl 中关键行类型：
///   type=user      → message.content      （提示词）
///   type=assistant → message.model + message.content[*].text + message.usage.{input_tokens,output_tokens,cache_*_tokens}
struct ClaudeCodeCLIParser: LogParser {
    let supportedProvider: LLMProvider = .anthropic

    func canParse(url: URL, content: String) -> Bool {
        guard url.path.contains(".claude") else { return false }
        let name = url.lastPathComponent
        return name == "history.jsonl"
            || (url.pathExtension.lowercased() == "jsonl" && url.path.contains("/projects/"))
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        if url.lastPathComponent == "history.jsonl" {
            return parseHistory(url: url, content: content)
        }
        return parseSession(url: url, content: content)
    }

    // MARK: - history.jsonl

    private func parseHistory(url: URL, content: String) -> [ParsedLog] {
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var results: [ParsedLog] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            guard let prompt = obj["display"] as? String, !prompt.isEmpty else { continue }

            let sessionId = obj["sessionId"] as? String
            var timestamp = fileDate
            if let ts = obj["timestamp"] as? Double {
                timestamp = Date(timeIntervalSince1970: ts / 1000.0)
            }
            results.append(ParsedLog(
                timestamp: timestamp,
                sourceFile: url.path,
                provider: .anthropic,
                modelName: "claude-code",
                prompt: prompt,
                response: nil,
                conversationId: sessionId,
                metadata: ["format": "claude_history", "client": "claude-code-cli"]
            ))
        }
        return results
    }

    // MARK: - projects/<id>/<sid>.jsonl

    private func parseSession(url: URL, content: String) -> [ParsedLog] {
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var results: [ParsedLog] = []

        // 状态：最近一条 user 的内容作为接下来 assistant 的 prompt
        var pendingPrompt: String? = nil
        var pendingPromptTimestamp: Date? = nil
        let sessionId = url.deletingPathExtension().lastPathComponent

        for raw in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(raw).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = obj["type"] as? String
            let timestamp = parseTimestamp(obj["timestamp"]) ?? fileDate
            let message = obj["message"] as? [String: Any]

            switch type {
            case "user":
                if let text = extractText(from: message?["content"]) {
                    pendingPrompt = text
                    pendingPromptTimestamp = timestamp
                }

            case "assistant":
                guard let message else { continue }
                let modelName = message["model"] as? String
                if modelName == "<synthetic>" || modelName == "synthetic" {
                    continue
                }
                let responseText = extractText(from: message["content"])
                let usage = message["usage"] as? [String: Any]
                let inputTokens = (usage?["input_tokens"] as? Int) ?? 0
                let outputTokens = (usage?["output_tokens"] as? Int) ?? 0
                let cacheCreation = (usage?["cache_creation_input_tokens"] as? Int) ?? 0
                let cacheRead = (usage?["cache_read_input_tokens"] as? Int) ?? 0
                let totalInput = inputTokens + cacheCreation + cacheRead

                // 跳过纯空的 ack 行（无 token 又无内容）
                if (responseText?.isEmpty ?? true) && totalInput == 0 && outputTokens == 0 {
                    continue
                }

                let provider = providerForModel(modelName)
                let log = ParsedLog(
                    timestamp: timestamp,
                    sourceFile: url.path,
                    provider: provider,
                    modelName: modelName,
                    prompt: pendingPrompt,
                    response: responseText,
                    promptTokens: totalInput > 0 ? totalInput : nil,
                    completionTokens: outputTokens > 0 ? outputTokens : nil,
                    totalTokens: (totalInput + outputTokens) > 0 ? totalInput + outputTokens : nil,
                    duration: pendingPromptTimestamp.map { max(0.001, timestamp.timeIntervalSince($0)) },
                    conversationId: sessionId,
                    metadata: [
                        "format": "claude_code_session",
                        "client": "claude-code-cli",
                        "cache_creation_tokens": "\(cacheCreation)",
                        "cache_read_tokens": "\(cacheRead)"
                    ]
                )
                results.append(log)
                pendingPrompt = nil
                pendingPromptTimestamp = nil

            default:
                continue
            }
        }
        return results
    }

    // MARK: - Helpers

    /// content 可能是 String 或 [{ type:"text", text:"..." }] 数组
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
            // 兼容秒/毫秒
            return d > 10_000_000_000 ? Date(timeIntervalSince1970: d / 1000.0) : Date(timeIntervalSince1970: d)
        }
        return nil
    }

    /// 按实际 model 名识别 provider（Claude Code CLI 可代理多家模型）
    private func providerForModel(_ model: String?) -> LLMProvider {
        guard let m = model?.lowercased() else { return .anthropic }
        if m.contains("claude")    { return .anthropic }
        if m.contains("gpt") || m.contains("o1") || m.contains("o3") || m.contains("o4") || m.hasPrefix("openai/") {
            return .openai
        }
        if m.contains("gemini") || m.contains("palm") || m.hasPrefix("google/") { return .google }
        if m.contains("deepseek") { return .deepseek }
        if m.contains("qwen")     { return .qwen }
        if m.contains("kimi") || m.contains("moonshot") { return .kimi }
        if m.contains("glm") || m.contains("chatglm") || m.contains("zhipu") { return .zhipu }
        if m.contains("llama") || m.contains("mistral") || m.contains("gemma") { return .ollama }
        return .custom
    }
}
