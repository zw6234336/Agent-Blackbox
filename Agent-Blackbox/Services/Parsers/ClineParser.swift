import Foundation

struct ClineParser: LogParser {
    let supportedProvider: LLMProvider = .cline
    
    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        return (path.contains("claude-dev") || path.contains("roo-cline")) &&
               (path.contains("api_conversation_history") || path.hasSuffix(".json"))
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        guard let data = content.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var results: [ParsedLog] = []
        var currentPrompt: String? = nil
        let taskDir = url.deletingLastPathComponent()
        let conversationId = taskDir.lastPathComponent
        
        // 1. Try to read model name from task_metadata.json in the same folder
        var modelName: String? = nil
        let metadataURL = taskDir.appendingPathComponent("task_metadata.json")
        if let metaData = try? Data(contentsOf: metadataURL),
           let metaObj = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
           let modelUsage = metaObj["model_usage"] as? [[String: Any]],
           let firstUsage = modelUsage.first {
            modelName = firstUsage["model_id"] as? String
        }
        
        // 2. Try to read token usage, cost, and timestamp from taskHistory.json
        let globalStorageDir = taskDir.deletingLastPathComponent().deletingLastPathComponent()
        let taskHistoryURL = globalStorageDir.appendingPathComponent("state").appendingPathComponent("taskHistory.json")
        
        var tokensIn: Int? = nil
        var tokensOut: Int? = nil
        var totalCost: Double? = nil
        var taskTimestamp: Date? = nil
        
        if let historyData = try? Data(contentsOf: taskHistoryURL),
           let historyArray = try? JSONSerialization.jsonObject(with: historyData) as? [[String: Any]] {
            if let taskItem = historyArray.first(where: { ($0["id"] as? String) == conversationId }) {
                tokensIn = taskItem["tokensIn"] as? Int
                tokensOut = taskItem["tokensOut"] as? Int
                totalCost = taskItem["totalCost"] as? Double
                if let tsVal = taskItem["ts"] as? Double {
                    taskTimestamp = Date(timeIntervalSince1970: tsVal / 1000.0)
                }
            }
        }
        
        // Define base fallback timestamp
        let folderTimestamp = Double(conversationId).map { Date(timeIntervalSince1970: $0 / 1000.0) }
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let baseTimestamp = taskTimestamp ?? folderTimestamp ?? fileDate ?? Date()
        
        // Identify the last assistant message to avoid double-counting tokens and costs
        var lastAssistantIndex = -1
        for (index, msg) in array.enumerated() {
            if (msg["role"] as? String) == "assistant" {
                lastAssistantIndex = index
            }
        }
        
        for (index, msg) in array.enumerated() {
            let role = msg["role"] as? String ?? ""
            let contentValue = extractContent(from: msg)
            let ts = msg["ts"] as? Double
            let timestamp = ts.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? baseTimestamp
            
            if role == "user" {
                currentPrompt = maskAPIKey(contentValue)
            } else if role == "assistant" {
                let response = maskAPIKey(contentValue)
                
                let isLast = (index == lastAssistantIndex)
                let promptTokens = isLast ? tokensIn : nil
                let completionTokens = isLast ? tokensOut : nil
                let cost = isLast ? totalCost : nil
                let total = isLast ? ((tokensIn ?? 0) + (tokensOut ?? 0) > 0 ? (tokensIn ?? 0) + (tokensOut ?? 0) : nil) : nil
                
                results.append(ParsedLog(
                    timestamp: timestamp,
                    sourceFile: url.path,
                    provider: detectProvider(model: modelName, content: nil),
                    modelName: modelName,
                    prompt: currentPrompt,
                    response: String(response?.prefix(2000) ?? ""),
                    promptTokens: promptTokens,
                    completionTokens: completionTokens,
                    totalTokens: total,
                    estimatedCost: cost,
                    conversationId: conversationId,
                    metadata: ["format": "cline_json", "role": role, "client": "cline"]
                ))
                currentPrompt = nil
            }
        }
        
        return results
    }
    
    private func extractContent(from msg: [String: Any]) -> String? {
        if let text = msg["content"] as? String {
            return text
        }
        if let contentArray = msg["content"] as? [[String: Any]] {
            return contentArray.compactMap { block in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        }
        return nil
    }
}
