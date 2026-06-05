import Foundation
import SQLite

struct VSCodeCopilotParser: LogParser {
    let supportedProvider: LLMProvider = .copilot
    
    func canParse(url: URL, content: String) -> Bool {
        return url.pathExtension.lowercased() == "db" && url.path.contains("github.copilot-chat")
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        var results: [ParsedLog] = []
        
        let fm = FileManager.default
        let tempId = UUID().uuidString
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempDBURL = tempDir.appendingPathComponent("copilot_state_\(tempId).db")
        
        let walURL = url.deletingPathExtension().appendingPathExtension("db-wal")
        let shmURL = url.deletingPathExtension().appendingPathExtension("db-shm")
        let tempWalURL = tempDBURL.deletingPathExtension().appendingPathExtension("db-wal")
        let tempShmURL = tempDBURL.deletingPathExtension().appendingPathExtension("db-shm")
        
        var copiedWal = false
        var copiedShm = false
        
        do {
            // Copy main db
            try fm.copyItem(at: url, to: tempDBURL)
            
            // Copy WAL/SHM files if they exist to capture latest changes
            if fm.fileExists(atPath: walURL.path) {
                try? fm.copyItem(at: walURL, to: tempWalURL)
                copiedWal = true
            }
            if fm.fileExists(atPath: shmURL.path) {
                try? fm.copyItem(at: shmURL, to: tempShmURL)
                copiedShm = true
            }
        } catch {
            Logger.shared.error("Failed to copy VSCode Copilot DB to temporary location: \(error.localizedDescription)")
            return []
        }
        
        defer {
            try? fm.removeItem(at: tempDBURL)
            if copiedWal { try? fm.removeItem(at: tempWalURL) }
            if copiedShm { try? fm.removeItem(at: tempShmURL) }
        }
        
        do {
            let db = try Connection(tempDBURL.path, readonly: false)
            
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
            Logger.shared.error("Failed to parse copied VSCode Copilot DB: \(error.localizedDescription)")
        }
        
        return results
    }
}
