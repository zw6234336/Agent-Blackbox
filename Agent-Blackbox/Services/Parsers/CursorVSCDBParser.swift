import Foundation
import SQLite

struct CursorVSCDBParser: LogParser {
    let supportedProvider: LLMProvider = .cursor
    
    func canParse(url: URL, content: String) -> Bool {
        return url.pathExtension.lowercased() == "vscdb"
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        var results: [ParsedLog] = []
        
        do {
            let db = try Connection(url.path, readonly: true)
            // The table is `ItemTable`
            // Columns: key (TEXT), value (TEXT)
            let itemTable = Table("ItemTable")
            let keyColumn = Expression<String>("key")
            let valueColumn = Expression<String>("value")
            
            let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            
            // Look for workbench.panel.aichat.view.aichat.chatdata
            let query = itemTable.filter(keyColumn == "workbench.panel.aichat.view.aichat.chatdata")
            if let row = try db.pluck(query) {
                let jsonString = row[valueColumn]
                results.append(contentsOf: parseChatDataJSON(jsonString, url: url, fileDate: fileDate))
            }
            
            // We could also look for composer.composerData
            let composerQuery = itemTable.filter(keyColumn == "composer.composerData")
            if let row = try db.pluck(composerQuery) {
                let jsonString = row[valueColumn]
                results.append(contentsOf: parseComposerDataJSON(jsonString, url: url, fileDate: fileDate))
            }
            
        } catch {
            print("Failed to parse VSCDB at \(url.path): \(error)")
        }
        
        return results
    }
    
    private func parseChatDataJSON(_ jsonString: String, url: URL, fileDate: Date) -> [ParsedLog] {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tabs = obj["tabs"] as? [[String: Any]] else {
            return []
        }
        
        var logs: [ParsedLog] = []
        
        for tab in tabs {
            guard let bubbles = tab["bubbles"] as? [[String: Any]] else { continue }
            let tabId = tab["tabId"] as? String ?? UUID().uuidString
            
            var currentPrompt: String? = nil
            
            for bubble in bubbles {
                let type = bubble["type"] as? String
                let text = bubble["text"] as? String
                
                if type == "user" {
                    currentPrompt = text
                } else if type == "ai" {
                    let response = text
                    let rawModelType = bubble["modelType"] as? String
                    
                    let modelName = rawModelType ?? "cursor-model"
                    
                    if let prompt = currentPrompt, let response = response {
                        logs.append(ParsedLog(
                            timestamp: fileDate,
                            sourceFile: url.path,
                            provider: detectProvider(model: modelName, content: nil, sourceFile: url.path),
                            modelName: modelName,
                            prompt: prompt,
                            response: response,
                            conversationId: tabId,
                            metadata: ["format": "vscdb_chat", "client": "cursor"]
                        ))
                    }
                    currentPrompt = nil
                }
            }
        }
        
        return logs
    }
    
    private func parseComposerDataJSON(_ jsonString: String, url: URL, fileDate: Date) -> [ParsedLog] {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let allComposers = obj["allComposers"] as? [[String: Any]] else {
            return []
        }
        
        var logs: [ParsedLog] = []
        
        for composer in allComposers {
            let composerId = composer["composerId"] as? String ?? UUID().uuidString
            guard let conversation = composer["conversation"] as? [[String: Any]] else { continue }
            
            var currentPrompt: String? = nil
            
            for msg in conversation {
                let type = msg["type"] as? Int
                let text = msg["text"] as? String
                let modelType = msg["modelType"] as? String
                
                if type == 1 { // user
                    currentPrompt = text
                } else if type == 2 { // ai
                    let response = text
                    let modelName = modelType ?? "cursor-composer"
                    
                    if let prompt = currentPrompt, let response = response {
                        logs.append(ParsedLog(
                            timestamp: fileDate,
                            sourceFile: url.path,
                            provider: detectProvider(model: modelName, content: nil, sourceFile: url.path),
                            modelName: modelName,
                            prompt: prompt,
                            response: response,
                            conversationId: composerId,
                            metadata: ["format": "vscdb_composer", "client": "cursor"]
                        ))
                    }
                    currentPrompt = nil
                }
            }
        }
        
        return logs
    }
}
