import Foundation

struct CursorLogParser: LogParser {
    let supportedProvider: LLMProvider = .cursor
    
    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        return path.contains("cursor") && (
            path.hasSuffix(".log") ||
            path.hasSuffix(".json") ||
            path.contains("debug.log")
        )
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        var results: [ParsedLog] = []
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        
        if url.pathExtension.lowercased() == "json" {
            results.append(contentsOf: parseJSONContent(url: url, content: content, defaultTimestamp: fileDate))
        } else {
            results.append(contentsOf: parseLogContent(url: url, content: content, defaultTimestamp: fileDate))
        }
        
        return results
    }
    
    private func parseJSONContent(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        guard let data = content.data(using: .utf8) else { return [] }
        
        // Try parsing as JSON array
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { obj in
                extractLog(from: obj, sourceFile: url.path, defaultTimestamp: defaultTimestamp)
            }
        }
        
        // Try single JSON object
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let log = extractLog(from: obj, sourceFile: url.path, defaultTimestamp: defaultTimestamp) {
                return [log]
            }
        }
        
        return []
    }
    
    private func parseLogContent(url: URL, content: String, defaultTimestamp: Date) -> [ParsedLog] {
        var results: [ParsedLog] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Look for model/API call patterns in Cursor debug logs
            if line.contains("model") || line.contains("completion") || line.contains("chat") {
                let model = firstMatch(in: line, pattern: #"model["':\s]+([\w\-.]+)"#)
                let tokens = firstMatch(in: line, pattern: #"tokens?["':\s]+(\d+)"#)
                let timestamp = extractTimestamp(from: line) ?? defaultTimestamp
                
                let validatedModel = ParsedLog.isValidModelName(model) ? model : nil
                if validatedModel != nil || tokens != nil {
                    results.append(ParsedLog(
                        timestamp: timestamp,
                        sourceFile: url.path,
                        provider: detectProvider(model: validatedModel, content: nil, sourceFile: url.path),
                        modelName: validatedModel,
                        totalTokens: tokens.flatMap(Int.init),
                        metadata: ["format": "cursor_log", "source_line": String(line.prefix(200)), "client": "cursor"]
                    ))
                }
            }
        }
        
        return results
    }
    
    private func extractLog(from obj: [String: Any], sourceFile: String, defaultTimestamp: Date) -> ParsedLog? {
        let rawModel = obj["model"] as? String ?? obj["modelName"] as? String
        let model = ParsedLog.isValidModelName(rawModel) ? rawModel : nil
        let prompt = maskAPIKey(obj["prompt"] as? String ?? obj["message"] as? String)
        let response = maskAPIKey(obj["response"] as? String ?? obj["text"] as? String ?? obj["content"] as? String)
        
        let usage = obj["usage"] as? [String: Any]
        let promptTokens = usage?["prompt_tokens"] as? Int ?? obj["promptTokens"] as? Int
        let completionTokens = usage?["completion_tokens"] as? Int ?? obj["completionTokens"] as? Int
        let totalTokens = usage?["total_tokens"] as? Int ?? obj["totalTokens"] as? Int
            ?? obj["tokens"] as? Int
            
        let timestamp = (obj["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ?? (obj["ts"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000.0) }
            ?? defaultTimestamp
        
        guard model != nil || prompt != nil || response != nil else { return nil }
        
        let provider = detectProvider(model: model, content: nil, sourceFile: sourceFile)
        
        return ParsedLog(
            timestamp: timestamp,
            sourceFile: sourceFile,
            provider: provider,
            modelName: model,
            prompt: prompt,
            response: response,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens ?? ((promptTokens ?? 0) + (completionTokens ?? 0) > 0 ? (promptTokens ?? 0) + (completionTokens ?? 0) : nil),
            metadata: ["format": "cursor_json", "client": "cursor"]
        )
    }
}
