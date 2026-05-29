import Foundation

struct GenericLLMParser: LogParser {
    let supportedProvider: LLMProvider = .custom
    
    func canParse(url: URL, content: String) -> Bool {
        // Fallback parser - always can attempt to parse EXCEPT for known paths we shouldn't touch
        let path = url.path.lowercased()
        if path.contains(".claude") || path.contains("/claude/") || path.contains("claude-3p") {
            return false
        }
        if path.contains("history.jsonl") {
            return false
        }
        return true
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        if url.pathExtension.lowercased() == "json" {
            return parseJSON(url: url, content: content, defaultTimestamp: fileDate)
        }
        if url.pathExtension.lowercased() == "jsonl" {
            return parseJSONL(url: url, content: content, defaultTimestamp: fileDate)
        }
        return parseText(url: url, content: content, defaultTimestamp: fileDate)
    }
    
    private func parseJSON(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        guard let data = content.data(using: .utf8) else { return [] }
        
        // Try array
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { extractFromJSON($0, url: url, defaultTimestamp: defaultTimestamp) }
        }
        
        // Try single object
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let log = extractFromJSON(obj, url: url, defaultTimestamp: defaultTimestamp) {
            return [log]
        }
        
        return []
    }
    
    private func parseJSONL(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        return content.components(separatedBy: .newlines).compactMap { line -> ParsedLog? in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return extractFromJSON(obj, url: url, defaultTimestamp: defaultTimestamp)
        }
    }
    
    /// 验证模型名是否像真实模型名，剔除 `n_ctx`、`7.27`、`FileNotFoundError`、`OpenAiChatModel.builder` 这类污染
    private func isValidModelName(_ raw: String?) -> Bool {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return false }
        // 太短直接拒
        if s.count < 3 { return false }
        // 必须含字母
        if s.rangeOfCharacter(from: .letters) == nil { return false }
        // 黑名单：常见 LM Studio / Python 配置项 / 异常类名
        let blocklist: Set<String> = [
            "n_ctx", "n_batch", "n_gpu_layers", "n_threads", "rope_freq_base", "rope_freq_scale",
            "filenotfounderror", "valueerror", "typeerror", "runtimeerror", "indexerror",
            "keyerror", "modulenotfounderror", "permissionerror", "true", "false", "none", "null",
            "openaichatmodel.builder"
        ]
        if blocklist.contains(s.lowercased()) { return false }
        // 纯版本号 / 纯数字 形如 7.27 / 1.0.0
        if s.range(of: #"^[\d\.]+$"#, options: .regularExpression) != nil { return false }
        // PascalCase 类名（含 . 且每段首字母大写）
        if s.contains(".") {
            let parts = s.split(separator: ".")
            if parts.count >= 2, parts.allSatisfy({ $0.first?.isUppercase ?? false }) {
                return false
            }
        }
        return true
    }

    private func parseText(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        let model = firstMatch(in: content, pattern: #"model\s*[:=]\s*([\w\-.\/:]+)"#)
        let tokenText = firstMatch(in: content, pattern: #"tokens?\s*[:=]\s*(\d+)"#)
        let prompt = maskAPIKey(firstMatch(in: content, pattern: #"prompt\s*[:=]\s*(.+)"#))
        let response = maskAPIKey(firstMatch(in: content, pattern: #"response\s*[:=]\s*(.+)"#))
        let error = maskAPIKey(firstMatch(in: content, pattern: #"error\s*[:=]\s*(.+)"#))
        let promptTokens = firstMatch(in: content, pattern: #"prompt.tokens?\s*[:=]\s*(\d+)"#)
        let completionTokens = firstMatch(in: content, pattern: #"completion.tokens?\s*[:=]\s*(\d+)"#)
        
        // 剔除明显不是模型名的污染（n_ctx、7.27、FileNotFoundError、OpenAiChatModel.builder 等）
        let validatedModel = isValidModelName(model) ? model : nil
        let hasModel = validatedModel != nil
        let hasPrompt = prompt != nil
        let hasResponse = response != nil
        let hasTokens = tokenText != nil
        let hasError = error != nil

        // 必须 (有合法模型名 + 至少一个 metric/prompt/response/error) 或者 (同时有 prompt 和 response)
        guard (hasModel && (hasPrompt || hasResponse || hasTokens || hasError)) || (hasPrompt && hasResponse) else {
            return []
        }

        let provider = detectProvider(model: validatedModel, content: content, sourceFile: url.path)
        let timestamp = extractTimestamp(from: content) ?? defaultTimestamp
        
        return [ParsedLog(
            timestamp: timestamp,
            sourceFile: url.path,
            provider: provider,
            modelName: validatedModel,
            prompt: prompt,
            response: response,
            promptTokens: promptTokens.flatMap(Int.init),
            completionTokens: completionTokens.flatMap(Int.init),
            totalTokens: tokenText.flatMap(Int.init),
            errorMessage: error,
            metadata: ["format": "text"]
        )]
    }
    
    private func extractFromJSON(_ obj: [String: Any], url: URL, defaultTimestamp: Date) -> ParsedLog? {
        let rawModel = obj["model"] as? String
        let model = isValidModelName(rawModel) ? rawModel : nil
        let prompt = maskAPIKey(
            obj["prompt"] as? String ??
            (obj["messages"] as? [[String: Any]])?.last(where: { ($0["role"] as? String) == "user" })?["content"] as? String
        )
        let choices = obj["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let response = maskAPIKey(
            obj["response"] as? String ??
            obj["content"] as? String ??
            obj["text"] as? String ??
            message?["content"] as? String
        )
        let error = obj["error"] as? String
        
        let usage = obj["usage"] as? [String: Any]
        let promptTokens = usage?["prompt_tokens"] as? Int ?? usage?["input_tokens"] as? Int
        let completionTokens = usage?["completion_tokens"] as? Int ?? usage?["output_tokens"] as? Int
        let totalTokens = usage?["total_tokens"] as? Int ?? obj["tokens"] as? Int
        
        let statusCode = obj["status"] as? Int ?? obj["status_code"] as? Int
        let duration = obj["duration"] as? Double ?? obj["latency"] as? Double
        let conversationId = obj["conversation_id"] as? String ?? obj["session_id"] as? String
        
        let timestamp = (obj["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? (obj["ts"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000.0) }
            ?? defaultTimestamp
        
        guard model != nil || prompt != nil || response != nil || error != nil else { return nil }
        
        let provider = detectProvider(model: model, content: nil, sourceFile: url.path)
        
        return ParsedLog(
            timestamp: timestamp,
            sourceFile: url.path,
            provider: provider,
            modelName: model,
            prompt: prompt,
            response: response,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens ?? ((promptTokens ?? 0) + (completionTokens ?? 0) > 0 ? (promptTokens ?? 0) + (completionTokens ?? 0) : nil),
            duration: duration,
            statusCode: statusCode,
            errorMessage: maskAPIKey(error),
            conversationId: conversationId,
            metadata: ["format": "json"]
        )
    }
}
