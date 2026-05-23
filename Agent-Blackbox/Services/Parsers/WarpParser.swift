import Foundation

/// Warp 数据采集器。
///
/// 当前优先接入两个稳定的数据源：
/// 1. warp_network.log
///    - 解析 Warp AI / 配额 / 模型配置相关 GraphQL 操作
///    - 记录请求时间、响应状态、耗时、操作类型
/// 2. mcp/*.log
///    - 解析 Warp MCP 连接错误，补充集成侧异常观测
///
/// 说明：Warp 本地日志里暂未稳定暴露完整 prompt/response 正文，
/// 因此当前版本以“活动事件采集”为主，先把 Warp 纳入统一监控与统计。
struct WarpParser: LogParser {
    let supportedProvider: LLMProvider = .warp

    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()

        if path.contains("/dev.warp.warp-stable/") && name == "warp_network.log" {
            return true
        }
        if path.contains("/dev.warp.warp-stable/mcp/") && name.hasSuffix(".log") {
            return true
        }
        return false
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        let path = url.path.lowercased()
        if path.contains("/dev.warp.warp-stable/mcp/") {
            return parseMCPLog(url: url, content: content)
        }
        return parseNetworkLog(url: url, content: content)
    }

    private func parseNetworkLog(url: URL, content: String) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines)
        var pendingRequests: [String: [Date]] = [:]
        var results: [ParsedLog] = []

        for line in lines {
            if let request = parseNetworkRequest(line), isRelevantOperation(request.operation) {
                pendingRequests[request.operation, default: []].append(request.timestamp)
                continue
            }

            if let response = parseNetworkResponse(line), isRelevantOperation(response.operation) {
                var queue = pendingRequests[response.operation] ?? []
                let requestTimestamp = queue.isEmpty ? nil : queue.removeFirst()
                pendingRequests[response.operation] = queue
                let eventTimestamp = requestTimestamp ?? response.timestamp
                let duration = requestTimestamp.map { max(0, response.timestamp.timeIntervalSince($0)) }

                results.append(
                    ParsedLog(
                        timestamp: eventTimestamp,
                        sourceFile: url.path,
                        provider: .warp,
                        modelName: nil,
                        duration: duration,
                        statusCode: response.statusCode,
                        metadata: [
                            "format": "warp_network_log",
                            "client": "warp",
                            "operation": response.operation,
                            "category": category(for: response.operation),
                            "label": operationLabel(for: response.operation)
                        ]
                    )
                )
            }
        }

        return results
    }

    private func parseMCPLog(url: URL, content: String) -> [ParsedLog] {
        let lines = content.components(separatedBy: .newlines)
        var results: [ParsedLog] = []

        for line in lines {
            guard line.contains("[error]") || line.contains("MCP SSE:") else { continue }
            guard let timestamp = parseMCPTimestamp(line) else { continue }

            let sanitized = maskAPIKey(line.trimmingCharacters(in: .whitespacesAndNewlines)) ?? line
            results.append(
                ParsedLog(
                    timestamp: timestamp,
                    sourceFile: url.path,
                    provider: .warp,
                    modelName: nil,
                    errorMessage: String(sanitized.prefix(500)),
                    metadata: [
                        "format": "warp_mcp_log",
                        "client": "warp",
                        "category": "mcp",
                        "label": "Warp MCP"
                    ]
                )
            )
        }

        return results
    }

    private func isRelevantOperation(_ operation: String) -> Bool {
        let op = operation.lowercased()
        return op.contains("featuremodel")
            || op.contains("requestlimit")
            || op.contains("workspacesmetadata")
            || op.contains("codebasecontext")
            || op.contains("merkletree")
    }

    private func operationLabel(for operation: String) -> String {
        switch operation {
        case "GetFeatureModelChoices":
            return "Warp 模型配置"
        case "GetRequestLimitInfo":
            return "Warp 配额查询"
        case "GetWorkspacesMetadataForUser":
            return "Warp 工作区元数据"
        case "CodebaseContextConfigQuery":
            return "Warp Codebase Context"
        case "SyncMerkleTree":
            return "Warp Codebase Sync"
        default:
            return "Warp 活动"
        }
    }

    private func category(for operation: String) -> String {
        switch operation {
        case "GetFeatureModelChoices":
            return "model_config"
        case "GetRequestLimitInfo", "GetWorkspacesMetadataForUser":
            return "quota"
        case "CodebaseContextConfigQuery", "SyncMerkleTree":
            return "codebase_context"
        default:
            return "activity"
        }
    }

    private func parseNetworkRequest(_ line: String) -> (timestamp: Date, operation: String)? {
        let pattern = #"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\]: Request .*query: Some\("op=([^"]+)"\)"#
        guard let match = regexMatch(in: line, pattern: pattern),
              let timestamp = parseNetworkTimestamp(match[0]) else {
            return nil
        }
        return (timestamp, match[1])
    }

    private func parseNetworkResponse(_ line: String) -> (timestamp: Date, operation: String, statusCode: Int)? {
        let pattern = #"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\]: Response \{ url: \"https://app\.warp\.dev/graphql/v2\?op=([^\"]+)\", status: (\d+)"#
        guard let match = regexMatch(in: line, pattern: pattern),
              let timestamp = parseNetworkTimestamp(match[0]),
              let statusCode = Int(match[2]) else {
            return nil
        }
        return (timestamp, match[1], statusCode)
    }

    private func parseNetworkTimestamp(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return formatter.date(from: raw)
    }

    private func parseMCPTimestamp(_ line: String) -> Date? {
        let pattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \|"#
        guard let match = regexMatch(in: line, pattern: pattern) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.date(from: match[0])
    }

    private func regexMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        guard match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
    }
}