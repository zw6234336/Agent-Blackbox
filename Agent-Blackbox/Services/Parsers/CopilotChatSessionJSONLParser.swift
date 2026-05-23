import Foundation

/// 解析 VS Code GitHub Copilot Chat 的增量格式会话文件：
///   ~/Library/Application Support/Code/User/workspaceStorage/<hash>/chatSessions/<uuid>.jsonl
///
/// 格式为 JSONL（每行一个 JSON 对象），采用增量补丁模式：
///   kind=0: 初始 session 状态（sessionId、inputState.selectedModel 等）
///   kind=1: 对某个路径做局部更新（键路径 k, 值 v）
///   kind=2: 对某个路径做整体替换（键路径 k, 值 v）
///
/// 关键字段（相比旧版 .json 的优势）：
///   - 每条 request 含独立的 modelId（如 "copilot/claude-sonnet-4.6"）
///   - result.timings.totalElapsed 提供实际响应耗时
///   - response 拆分为 parts（thinking / markdown / text 等 kind）
///   - 支持多轮对话（同一 sessionId 下多个 request）
struct CopilotChatSessionJSONLParser: LogParser {
    let supportedProvider: LLMProvider = .copilot

    func canParse(url: URL, content: String) -> Bool {
        url.path.contains("/chatSessions/") && url.pathExtension.lowercased() == "jsonl"
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        var sessionId: String?
        // 最后一次 kind=2 k=["requests"] 快照即为完整 requests 列表
        var latestRequests: [[String: Any]] = []
        // kind=2 k=["requests", N, "response"] 按 index 存储
        var responses: [Int: [[String: Any]]] = [:]

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let kind = obj["kind"] as? Int ?? -1
            let k = obj["k"] as? [Any]

            switch kind {
            case 0:
                // 初始状态
                if let v = obj["v"] as? [String: Any] {
                    sessionId = v["sessionId"] as? String
                }

            case 2:
                if k == nil || k!.isEmpty {
                    // kind=2, k=[] 或无 k → 整体替换，读 sessionId
                    if let v = obj["v"] as? [String: Any] {
                        if let sid = v["sessionId"] as? String { sessionId = sid }
                    }
                } else if let keys = k, keys.count == 1,
                          let key = keys[0] as? String, key == "requests" {
                    // kind=2, k=["requests"] → requests 整体快照
                    latestRequests = obj["v"] as? [[String: Any]] ?? []
                } else if let keys = k, keys.count == 3,
                          let key0 = keys[0] as? String, key0 == "requests",
                          let idx = keys[1] as? Int,
                          let key2 = keys[2] as? String, key2 == "response" {
                    // kind=2, k=["requests", N, "response"] → 某条 request 的 response
                    responses[idx] = obj["v"] as? [[String: Any]] ?? []
                }

            default:
                break
            }
        }

        guard !latestRequests.isEmpty else { return [] }

        let finalSessionId = sessionId ?? url.deletingPathExtension().lastPathComponent
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        var results: [ParsedLog] = []

        for (i, req) in latestRequests.enumerated() {
            let messageText = extractMessageText(req["message"])
            let requestId = req["requestId"] as? String

            // modelId 格式示例："copilot/claude-sonnet-4.6"、"copilot/gpt-4o"
            let rawModelId = req["modelId"] as? String
            let cleanModelName = rawModelId.map { id -> String in
                if id.hasPrefix("copilot/") { return String(id.dropFirst("copilot/".count)) }
                return id
            }

            let timestamp: Date = {
                if let ms = req["timestamp"] as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
                if let ms = req["timestamp"] as? Int    { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
                return fileDate
            }()

            // 组装 response：跳过 thinking 部分，只保留用户可见内容
            let responseParts = responses[i] ?? []
            let responseText: String? = {
                let parts = responseParts
                    .filter { ($0["kind"] as? String) != "thinking" }
                    .compactMap { $0["value"] as? String }
                    .joined(separator: "\n")
                return parts.isEmpty ? nil : parts
            }()

            // 耗时：result.timings.totalElapsed（单位 ms）
            let elapsed = (req["result"] as? [String: Any])
                .flatMap { $0["timings"] as? [String: Any] }
                .flatMap { ($0["totalElapsed"] as? Double) ?? ($0["totalElapsed"] as? Int).map(Double.init) }
                .map { $0 / 1000.0 }

            let agentInfo = req["agent"] as? [String: Any]
            let agentName = agentInfo?["name"] as? String ?? "copilot"

            // 没有 prompt 也没有 response，跳过
            guard messageText != nil || responseText != nil else { continue }

            let log = ParsedLog(
                timestamp: timestamp,
                sourceFile: url.path,
                provider: .copilot,
                modelName: cleanModelName ?? "copilot-chat",
                prompt: messageText,
                response: responseText,
                duration: elapsed,
                conversationId: finalSessionId,
                metadata: [
                    "format": "copilot_chat_jsonl",
                    "client": "vscode",
                    "request_id": requestId ?? "",
                    "model_id": rawModelId ?? "",
                    "agent": agentName
                ]
            )
            results.append(log)
        }

        return results
    }

    // MARK: - Helpers

    /// 从 message 字段中提取用户输入文字。
    /// message 可能是：
    ///   String、{ text: "...", parts: [...] }、nil
    private func extractMessageText(_ value: Any?) -> String? {
        if let s = value as? String {
            return s.isEmpty ? nil : s
        }
        if let obj = value as? [String: Any] {
            if let text = obj["text"] as? String, !text.isEmpty { return text }
            if let parts = obj["parts"] as? [[String: Any]] {
                let joined = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
                return joined.isEmpty ? nil : joined
            }
        }
        return nil
    }
}
