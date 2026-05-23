import Foundation

struct ClaudeDesktopParser: LogParser {
    let supportedProvider: LLMProvider = .claudeDesktop
    
    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        return (path.contains("/claude/") || path.contains("claude-3p")) && !path.contains("cursor")
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        if url.pathExtension.lowercased() == "json" || url.pathExtension.lowercased() == "jsonl" {
            return parseJSONLines(url: url, content: content, defaultTimestamp: fileDate)
        }
        return parseTextLog(url: url, content: content, defaultTimestamp: fileDate)
    }
    
    private func parseJSONLines(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines)
        var results: [ParsedLog] = []
        
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            let model = obj["model"] as? String
            let role = obj["role"] as? String
            let content = maskAPIKey(obj["content"] as? String)
            let usage = obj["usage"] as? [String: Any]
            let error = obj["error"] as? String
            
            let promptTokens = usage?["input_tokens"] as? Int
            let completionTokens = usage?["output_tokens"] as? Int
            
            let timestamp = (obj["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) }
                ?? (obj["ts"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000.0) }
                ?? defaultTimestamp
            
            results.append(ParsedLog(
                timestamp: timestamp,
                sourceFile: url.path,
                provider: model.flatMap { detectProvider(model: $0, content: nil) } ?? .anthropic,
                modelName: model,
                prompt: role == "user" ? content : nil,
                response: role == "assistant" ? content : nil,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: (promptTokens ?? 0) + (completionTokens ?? 0) > 0 ? (promptTokens ?? 0) + (completionTokens ?? 0) : nil,
                errorMessage: error,
                metadata: ["format": "claude_jsonl", "role": role ?? "unknown", "client": "claude_desktop"]
            ))
        }
        
        return results
    }
    
    private func parseTextLog(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        let model = firstMatch(in: content, pattern: #"model["':\s]+(claude[\w\-.]+)"#)
        let error = firstMatch(in: content, pattern: #"(?:error|ERROR)[:\s]+(.+)"#)
        let tokens = firstMatch(in: content, pattern: #"tokens?[:\s]+(\d+)"#)
        
        guard model != nil || error != nil else { return [] }
        
        let timestamp = extractTimestamp(from: content) ?? defaultTimestamp
        
        return [ParsedLog(
            timestamp: timestamp,
            sourceFile: url.path,
            provider: model.flatMap { detectProvider(model: $0, content: nil) } ?? .anthropic,
            modelName: model,
            totalTokens: tokens.flatMap(Int.init),
            errorMessage: maskAPIKey(error),
            metadata: ["format": "claude_text", "client": "claude_desktop"]
        )]
    }
}
