import Foundation
import SQLite

struct VSCodeCopilotParser: LogParser {
    let supportedProvider: LLMProvider = .copilot
    
    func canParse(url: URL, content: String) -> Bool {
        return url.pathExtension.lowercased() == "db" && url.path.contains("github.copilot-chat")
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        var results: [ParsedLog] = []
        
        do {
            let db = try Connection(url.path, readonly: true)
            
            let turnsTable = Table("turns")
            let sessionIdCol = Expression<String>("session_id")
            let userMessageCol = Expression<String?>("user_message")
            let assistantResponseCol = Expression<String?>("assistant_response")
            let timestampCol = Expression<String?>("timestamp")
            
            let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            
            for row in try db.prepare(turnsTable) {
                let prompt = row[userMessageCol] ?? ""
                let response = row[assistantResponseCol] ?? ""
                let sessionId = row[sessionIdCol]
                let tsString = row[timestampCol]
                
                var timestamp = fileDate
                if let tsStr = tsString {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let parsed = formatter.date(from: tsStr) {
                        timestamp = parsed
                    } else {
                        let fallback = ISO8601DateFormatter()
                        if let parsed2 = fallback.date(from: tsStr) {
                            timestamp = parsed2
                        }
                    }
                }
                
                if !prompt.isEmpty || !response.isEmpty {
                    results.append(ParsedLog(
                        timestamp: timestamp,
                        sourceFile: url.path,
                        provider: .copilot,
                        modelName: "copilot-chat",
                        prompt: prompt,
                        response: response,
                        conversationId: sessionId,
                        metadata: ["format": "copilot_db", "client": "vscode"]
                    ))
                }
            }
        } catch {
            print("Failed to parse VSCode Copilot DB at \(url.path): \(error)")
        }
        
        return results
    }
}
