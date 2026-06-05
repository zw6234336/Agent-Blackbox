import Foundation

struct OpenAICodexParser: LogParser {
    let supportedProvider: LLMProvider = .openai
    
    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/.codex/sessions/") && path.hasSuffix(".jsonl")
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines)
        var results: [ParsedLog] = []
        
        // Extract session ID from the filename if session_meta is missing,
        // e.g., rollout-timestamp-sessionid.jsonl
        var conversationId: String? = nil
        let fileName = url.deletingPathExtension().lastPathComponent
        if let lastDashIndex = fileName.lastIndex(of: "-") {
            let possibleId = String(fileName[fileName.index(after: lastDashIndex)...])
            if possibleId.contains("-") && possibleId.count >= 32 {
                conversationId = possibleId
            }
        }
        
        var currentModel = "gpt-5.5" // Default fallback
        
        struct PendingTurn {
            var timestamp: Date
            var prompt: String
            var response: String?
            var modelName: String
            var inputTokens: Int
            var outputTokens: Int
            var totalTokens: Int
        }
        
        var pendingTurn: PendingTurn? = nil
        
        let isoFormatter = ISO8601DateFormatter()
        let isoFormatterWithFractional = ISO8601DateFormatter()
        isoFormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let parseTimestamp: (String) -> Date = { tsStr in
            return isoFormatterWithFractional.date(from: tsStr)
                ?? isoFormatter.date(from: tsStr)
                ?? Date()
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            let timestampStr = obj["timestamp"] as? String ?? ""
            let timestamp = parseTimestamp(timestampStr)
            let type = obj["type"] as? String ?? ""
            let payload = obj["payload"] as? [String: Any] ?? [:]
            
            if type == "session_meta" {
                if let id = payload["id"] as? String {
                    conversationId = id
                }
            } else if type == "turn_context" {
                if let model = payload["model"] as? String {
                    currentModel = model
                }
            } else if type == "event_msg" {
                let payloadType = payload["type"] as? String ?? ""
                
                if payloadType == "user_message" {
                    let message = payload["message"] as? String ?? ""
                    let cleanedPrompt = maskAPIKey(message) ?? ""
                    
                    if var turn = pendingTurn {
                        if turn.response != nil {
                            // Finalize the previous turn first
                            results.append(ParsedLog(
                                timestamp: turn.timestamp,
                                sourceFile: url.path,
                                provider: detectProvider(model: turn.modelName, content: nil, sourceFile: url.path),
                                modelName: turn.modelName,
                                prompt: turn.prompt,
                                response: turn.response,
                                promptTokens: turn.inputTokens > 0 ? turn.inputTokens : nil,
                                completionTokens: turn.outputTokens > 0 ? turn.outputTokens : nil,
                                totalTokens: turn.totalTokens > 0 ? turn.totalTokens : nil,
                                conversationId: conversationId,
                                metadata: ["format": "codex_rollout", "client": "codex"]
                            ))
                            
                            // Start new turn
                            pendingTurn = PendingTurn(
                                timestamp: timestamp,
                                prompt: cleanedPrompt,
                                response: nil,
                                modelName: currentModel,
                                inputTokens: 0,
                                outputTokens: 0,
                                totalTokens: 0
                            )
                        } else {
                            // Append consecutive user prompts in the same turn
                            turn.prompt += "\n" + cleanedPrompt
                            pendingTurn = turn
                        }
                    } else {
                        // Start first turn
                        pendingTurn = PendingTurn(
                            timestamp: timestamp,
                            prompt: cleanedPrompt,
                            response: nil,
                            modelName: currentModel,
                            inputTokens: 0,
                            outputTokens: 0,
                            totalTokens: 0
                        )
                    }
                } else if payloadType == "agent_message" {
                    let phase = payload["phase"] as? String ?? ""
                    if phase == "final_answer" {
                        let message = payload["message"] as? String ?? ""
                        if var turn = pendingTurn {
                            turn.response = maskAPIKey(message)
                            pendingTurn = turn
                        }
                    }
                } else if payloadType == "token_count" {
                    if let info = payload["info"] as? [String: Any],
                       let lastUsage = info["last_token_usage"] as? [String: Any] {
                        let inTokens = lastUsage["input_tokens"] as? Int ?? 0
                        let outTokens = lastUsage["output_tokens"] as? Int ?? 0
                        let totTokens = lastUsage["total_tokens"] as? Int ?? 0
                        
                        if var turn = pendingTurn {
                            turn.inputTokens += inTokens
                            turn.outputTokens += outTokens
                            turn.totalTokens += totTokens
                            pendingTurn = turn
                        }
                    }
                }
            } else if type == "response_item" {
                let role = payload["role"] as? String ?? ""
                let phase = payload["phase"] as? String ?? ""
                if role == "assistant" && phase == "final_answer" {
                    if let contentArray = payload["content"] as? [[String: Any]],
                       let firstContent = contentArray.first,
                       let text = firstContent["text"] as? String {
                        if var turn = pendingTurn {
                            turn.response = maskAPIKey(text)
                            pendingTurn = turn
                        }
                    }
                }
            }
        }
        
        // Finalize any remaining pending turn at the end of the file
        if let turn = pendingTurn {
            results.append(ParsedLog(
                timestamp: turn.timestamp,
                sourceFile: url.path,
                provider: detectProvider(model: turn.modelName, content: nil, sourceFile: url.path),
                modelName: turn.modelName,
                prompt: turn.prompt,
                response: turn.response,
                promptTokens: turn.inputTokens > 0 ? turn.inputTokens : nil,
                completionTokens: turn.outputTokens > 0 ? turn.outputTokens : nil,
                totalTokens: turn.totalTokens > 0 ? turn.totalTokens : nil,
                conversationId: conversationId,
                metadata: ["format": "codex_rollout", "client": "codex"]
            ))
        }
        
        return results
    }
}
