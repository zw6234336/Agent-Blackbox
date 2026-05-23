import Foundation

/// 解析 Google Antigravity IDE 的语言服务器日志：
///
/// 两种日志源：
/// 1. 原生日志 ~/Library/Logs/Antigravity/language_server.log
///    格式: I0523 19:56:51.945296 98911 http_helpers.go:182] URL: https://...streamGenerateContent...
///
/// 2. VSCode 扩展内嵌日志 .../logs/<ts>/window*/exthost/google.antigravity/Antigravity*.log
///    格式: 2026-04-08 04:11:48.440 [info] I0408 04:11:48.440202 44484 http_helpers.go] URL: ...
///
/// 可提取的信息：
/// - API 调用时间戳
/// - 调用类型（streamGenerateContent = 对话, generateContent = 后台）
/// - 当前使用的模型（从 ~/.antigravity_cockpit/cache/available_models.json + antigravity_state.pbtxt 读取）

struct AntigravityParser: LogParser {
    let supportedProvider: LLMProvider = .antigravity

    func canParse(url: URL, content: String) -> Bool {
        let path = url.path
        let name = url.lastPathComponent.lowercased()

        // 原生日志: ~/Library/Logs/Antigravity/language_server.log
        if path.contains("/Logs/Antigravity/") && name == "language_server.log" {
            return true
        }
        // VSCode 扩展内嵌日志: .../exthost/google.antigravity/Antigravity*.log
        if path.contains("google.antigravity") && name.hasPrefix("antigravity") && name.hasSuffix(".log") {
            return true
        }
        // Antigravity Gemini 自身会话日志: ~/.gemini/antigravity/brain/<conv-id>/.system_generated/logs/transcript.jsonl
        if path.contains("/.gemini/antigravity/brain/") && name == "transcript.jsonl" {
            return true
        }
        return false
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        if url.lastPathComponent.lowercased() == "transcript.jsonl" {
            return parseTranscriptJSONL(url: url, content: content)
        }

        let path = url.path
        let isEmbedded = path.contains("google.antigravity")
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        let availableModels = loadAvailableModels()
        let modelName = resolveModelNameFromState(availableModels: availableModels) ?? "gemini-pro-agent"
        let provider = providerFor(model: modelName)

        var callTimestamps: [Date] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            // 只关心 streamGenerateContent (对话请求)，跳过后台调用
            guard line.contains("streamGenerateContent") else { continue }
            guard line.contains("URL:") else { continue }

            let ts: Date?
            if isEmbedded {
                ts = parseEmbeddedTimestamp(line) ?? fileDate
            } else {
                ts = parseNativeTimestamp(line, fileDate: fileDate) ?? fileDate
            }
            if let ts {
                callTimestamps.append(ts)
            }
        }

        guard !callTimestamps.isEmpty else { return [] }

        // 将相邻 ≤5 秒的调用归为同一次对话轮次
        let groups = groupByProximity(callTimestamps, threshold: 5.0)

        return groups.map { group in
            ParsedLog(
                timestamp: group.first!,
                sourceFile: url.path,
                provider: provider,
                modelName: modelName,
                metadata: [
                    "format": "antigravity_server_log",
                    "client": "antigravity",
                    "call_count": "\(group.count)"
                ]
            )
        }
    }

    // MARK: - Transcript Parsing

    private func parseTranscriptJSONL(url: URL, content: String) -> [ParsedLog] {
        var results: [ParsedLog] = []
        let lines = content.components(separatedBy: .newlines)
        
        let conversationId = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        
        var lastUserPrompt: String? = nil
        var currentModelName = "Gemini 3.5 Flash" // Default fallback
        
        let availableModels = loadAvailableModels()
        if let initialModel = resolveModelNameFromState(availableModels: availableModels) {
            currentModelName = initialModel
        }
        
        let isoFormatter = ISO8601DateFormatter()
        let isoFormatterWithFractional = ISO8601DateFormatter()
        isoFormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            
            let source = obj["source"] as? String ?? ""
            let type = obj["type"] as? String ?? ""
            let stepContent = obj["content"] as? String ?? ""
            
            // 1. If user input, track the prompt and check for settings/model changes
            if type == "USER_INPUT" || source == "USER_EXPLICIT" {
                if !stepContent.isEmpty {
                    lastUserPrompt = cleanPrompt(stepContent)
                }
                
                if stepContent.contains("<USER_SETTINGS_CHANGE>") {
                    if let modelMatch = firstMatch(in: stepContent, pattern: #"Model Selection` from .* to ([^.\n`]+)"#) {
                        currentModelName = modelMatch.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            
            // 2. If model step, count as LLM execution
            if source == "MODEL" {
                let createdStr = obj["created_at"] as? String ?? ""
                let timestamp = isoFormatter.date(from: createdStr) 
                    ?? isoFormatterWithFractional.date(from: createdStr)
                    ?? Date()
                
                var stepModelName = currentModelName
                if let modelVal = obj["model"] as? String {
                    if let displayName = availableModels[modelVal] {
                        stepModelName = displayName
                    } else {
                        stepModelName = modelVal
                    }
                }
                
                var responseParts: [String] = []
                
                if let thinking = obj["thinking"] as? String, !thinking.isEmpty {
                    responseParts.append("[Thinking]\n\(thinking)")
                }
                
                if !stepContent.isEmpty {
                    responseParts.append("[Output]\n\(stepContent)")
                }
                
                if let toolCalls = obj["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                    var toolDesc = "[Tool Calls]"
                    for tool in toolCalls {
                        if let name = tool["name"] as? String {
                            toolDesc += "\n- \(name)"
                            if let args = tool["args"] as? [String: Any] {
                                if let argsData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]),
                                   let argsStr = String(data: argsData, encoding: .utf8) {
                                    toolDesc += " (args: \(argsStr))"
                                }
                            }
                        }
                    }
                    responseParts.append(toolDesc)
                }
                
                let responseText = responseParts.joined(separator: "\n\n")
                
                // Estimate tokens
                let promptLength = lastUserPrompt?.count ?? 0
                let responseLength = responseText.count
                let estimatedPromptTokens = max(1, promptLength / 4)
                let estimatedCompletionTokens = max(1, responseLength / 4)
                let totalTokens = estimatedPromptTokens + estimatedCompletionTokens
                
                // Estimate Cost
                let provider = providerFor(model: stepModelName)
                let estimatedCost = estimateCostFor(model: stepModelName, promptTokens: estimatedPromptTokens, completionTokens: estimatedCompletionTokens)
                
                let errorMessage = obj["status"] as? String == "ERROR" ? (obj["error"] as? String ?? "Error occurred during step execution") : nil
                
                results.append(ParsedLog(
                    timestamp: timestamp,
                    sourceFile: url.path,
                    provider: provider,
                    modelName: stepModelName,
                    prompt: lastUserPrompt,
                    response: responseText,
                    promptTokens: estimatedPromptTokens,
                    completionTokens: estimatedCompletionTokens,
                    totalTokens: totalTokens,
                    estimatedCost: estimatedCost,
                    errorMessage: errorMessage,
                    conversationId: conversationId,
                    metadata: [
                        "format": "antigravity_transcript",
                        "step_index": "\(obj["step_index"] as? Int ?? -1)",
                        "step_type": type,
                        "client": "antigravity"
                    ]
                ))
            }
        }
        
        return results
    }

    private func cleanPrompt(_ prompt: String) -> String {
        var clean = prompt
        clean = clean.replacingOccurrences(of: "<USER_REQUEST>", with: "")
        clean = clean.replacingOccurrences(of: "</USER_REQUEST>", with: "")
        if let startRange = clean.range(of: "<ADDITIONAL_METADATA>"),
           let endRange = clean.range(of: "</ADDITIONAL_METADATA>") {
            clean.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        if let startRange = clean.range(of: "<USER_SETTINGS_CHANGE>"),
           let endRange = clean.range(of: "</USER_SETTINGS_CHANGE>") {
            clean.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func estimateCostFor(model: String, promptTokens: Int, completionTokens: Int) -> Double {
        let modelLower = model.lowercased()
        
        var inputPer1K = 0.0005
        var outputPer1K = 0.0015
        
        if modelLower.contains("gpt-4o-mini") {
            inputPer1K = 0.00015
            outputPer1K = 0.0006
        } else if modelLower.contains("gpt-4o") {
            inputPer1K = 0.005
            outputPer1K = 0.015
        } else if modelLower.contains("gpt-4-turbo") {
            inputPer1K = 0.01
            outputPer1K = 0.03
        } else if modelLower.contains("gpt-4") {
            inputPer1K = 0.03
            outputPer1K = 0.06
        } else if modelLower.contains("claude-3-opus") || modelLower.contains("claude-opus") {
            inputPer1K = 0.015
            outputPer1K = 0.075
        } else if modelLower.contains("claude-3.5-sonnet") || modelLower.contains("claude-sonnet") {
            inputPer1K = 0.003
            outputPer1K = 0.015
        } else if modelLower.contains("claude-3-haiku") || modelLower.contains("claude-haiku") {
            inputPer1K = 0.00025
            outputPer1K = 0.00125
        } else if modelLower.contains("gemini-1.5-flash") || modelLower.contains("flash") {
            inputPer1K = 0.000075
            outputPer1K = 0.0003
        } else if modelLower.contains("gemini-1.5-pro") || modelLower.contains("pro") {
            inputPer1K = 0.00125
            outputPer1K = 0.005
        }
        
        let inputCost = Double(promptTokens) / 1000.0 * inputPer1K
        let outputCost = Double(completionTokens) / 1000.0 * outputPer1K
        return inputCost + outputCost
    }

    // MARK: - Timestamp Parsing

    /// 原生格式: I0523 19:56:51.945296 ...
    private func parseNativeTimestamp(_ line: String, fileDate: Date) -> Date? {
        // Pattern: [IEWF]MMDD HH:MM:SS
        let pattern = #"^[IEWF](\d{2})(\d{2}) (\d{2}:\d{2}:\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        let month = Int((line as NSString).substring(with: match.range(at: 1))) ?? 1
        let day   = Int((line as NSString).substring(with: match.range(at: 2))) ?? 1
        let timeStr = (line as NSString).substring(with: match.range(at: 3))

        // 用文件修改时间的年份
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let year = cal.component(.year, from: fileDate)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = String(format: "%04d-%02d-%02d %@", year, month, day, timeStr)
        return formatter.date(from: dateStr)
    }

    /// 内嵌格式: 2026-04-08 04:11:48.440 [info] ...
    private func parseEmbeddedTimestamp(_ line: String) -> Date? {
        let pattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        let dateStr = (line as NSString).substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr)
    }

    // MARK: - Grouping

    private func groupByProximity(_ timestamps: [Date], threshold: TimeInterval) -> [[Date]] {
        guard !timestamps.isEmpty else { return [] }
        let sorted = timestamps.sorted()
        var groups: [[Date]] = []
        var current: [Date] = [sorted[0]]

        for i in 1..<sorted.count {
            if sorted[i].timeIntervalSince(current.last!) <= threshold {
                current.append(sorted[i])
            } else {
                groups.append(current)
                current = [sorted[i]]
            }
        }
        groups.append(current)
        return groups
    }

    // MARK: - Model Resolution

    private func loadAvailableModels() -> [String: String] {
        var dict: [String: String] = [:]
        let home = NSHomeDirectory()
        let modelsFile = home + "/.antigravity_cockpit/cache/available_models.json"
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: modelsFile)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            return dict
        }
        
        for model in models {
            if let mc = model["modelConstant"] as? String,
               let displayName = model["displayName"] as? String {
                dict[mc] = displayName
            }
            if let id = model["id"] as? String,
               let displayName = model["displayName"] as? String {
                dict[id] = displayName
            }
        }
        return dict
    }

    private func resolveModelNameFromState(availableModels: [String: String]) -> String? {
        let home = NSHomeDirectory()
        let stateFile = home + "/.gemini/antigravity/antigravity_state.pbtxt"
        
        guard let stateText = try? String(contentsOfFile: stateFile, encoding: .utf8) else {
            return nil
        }
        
        for line in stateText.components(separatedBy: .newlines) {
            if line.contains("last_selected_agent_model:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    let constant = parts[1].trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return availableModels[constant] ?? constant
                }
            }
        }
        return nil
    }

    // MARK: - Provider

    private func providerFor(model: String?) -> LLMProvider {
        guard let m = model?.lowercased() else { return .antigravity }
        if m.contains("claude")  { return .anthropic }
        if m.contains("gpt") || m.contains("openai") { return .openai }
        if m.contains("gemini") || m.contains("g3") || m.contains("g2") { return .google }
        return .antigravity
    }
}
