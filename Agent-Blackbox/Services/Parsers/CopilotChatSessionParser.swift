import Foundation

/// 解析 VSCode GitHub Copilot Chat 真正的对话文件：
///   ~/Library/Application Support/Code/User/workspaceStorage/<hash>/chatSessions/<uuid>.json
///
/// 结构：
/// {
///   requesterUsername, responderUsername,
///   requests: [
///     { requestId, responseId, timestamp,
///       message: { text: "...", parts: [...] },
///       response: [ { value: "...", supportHtml, supportThemeIcons } ],
///       agent: { extensionId, name, fullName, modes: ["edit"|"ask"|...] },
///       modelId: null,
///       result: { timings: { firstProgress, totalElapsed } }
///     }
///   ]
/// }
///
/// 注意：Copilot chatSessions 不包含 token 用量也不含真实 model 名，
/// 但有完整的 prompt / response / agent name / 耗时，能让 Copilot 出现在统计中。
struct CopilotChatSessionParser: LogParser {
    let supportedProvider: LLMProvider = .copilot

    func canParse(url: URL, content: String) -> Bool {
        url.path.contains("/chatSessions/") && url.pathExtension.lowercased() == "json"
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        guard let requests = obj["requests"] as? [[String: Any]] else { return [] }
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        // session id 用文件名（uuid）
        let sessionId = url.deletingPathExtension().lastPathComponent

        var results: [ParsedLog] = []
        for req in requests {
            let prompt = extractMessage(req["message"])
            let response = extractResponse(req["response"])
            let requestId = req["requestId"] as? String

            // 没 prompt 也没 response，丢弃
            guard prompt != nil || response != nil else { continue }

            let timestamp: Date = {
                if let ms = req["timestamp"] as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
                if let ms = req["timestamp"] as? Int    { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
                return fileDate
            }()

            let elapsed = (req["result"] as? [String: Any])
                .flatMap { $0["timings"] as? [String: Any] }
                .flatMap { $0["totalElapsed"] as? Double }
                .map { $0 / 1000.0 }

            let agent = req["agent"] as? [String: Any]
            let agentMode = (agent?["modes"] as? [String])?.first
            let agentFullName = agent?["fullName"] as? String ?? "GitHub Copilot Chat"
            let modelId = req["modelId"] as? String

            let log = ParsedLog(
                timestamp: timestamp,
                sourceFile: url.path,
                provider: .copilot,
                modelName: modelId ?? "copilot-chat",
                prompt: prompt,
                response: response,
                duration: elapsed,
                conversationId: sessionId,
                metadata: [
                    "format": "copilot_chat_session",
                    "client": "vscode",
                    "request_id": requestId ?? "",
                    "agent": agentFullName,
                    "mode": agentMode ?? ""
                ]
            )
            results.append(log)
        }
        return results
    }

    // MARK: - Helpers

    /// message 可能是 String 或 { text, parts:[{kind:"text", text:"..."}, ...] }
    private func extractMessage(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        if let obj = value as? [String: Any] {
            if let t = obj["text"] as? String, !t.isEmpty { return t }
            if let parts = obj["parts"] as? [[String: Any]] {
                let texts = parts.compactMap { $0["text"] as? String }
                let joined = texts.joined(separator: " ")
                return joined.isEmpty ? nil : joined
            }
        }
        return nil
    }

    /// response 通常是 [ { value: "...", ... } ]，按顺序拼接 value
    private func extractResponse(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        if let arr = value as? [[String: Any]] {
            let pieces: [String] = arr.compactMap { item in
                if let v = item["value"] as? String { return v }
                // 偶尔是嵌套对象（content references / code citations 等），忽略
                return nil
            }
            let joined = pieces.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }
}
