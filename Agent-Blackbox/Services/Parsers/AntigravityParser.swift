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
        return false
    }

    func parse(url: URL, content: String) -> [ParsedLog] {
        let path = url.path
        let isEmbedded = path.contains("google.antigravity")
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        let modelName = resolveModelName()
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
        var sorted = timestamps.sorted()
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

    /// 读取 ~/.antigravity_cockpit/cache/available_models.json 与
    /// ~/.gemini/antigravity/antigravity_state.pbtxt，解析当前选择的模型名称。
    private func resolveModelName() -> String {
        let home = NSHomeDirectory()
        let stateFile = home + "/.gemini/antigravity/antigravity_state.pbtxt"
        let modelsFile = home + "/.antigravity_cockpit/cache/available_models.json"

        // 1. 从 state 文件读取 last_selected_agent_model
        var modelConstant: String? = nil
        if let stateText = try? String(contentsOfFile: stateFile, encoding: .utf8) {
            for line in stateText.components(separatedBy: .newlines) {
                if line.contains("last_selected_agent_model:") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 {
                        modelConstant = parts[1].trimmingCharacters(in: .whitespaces)
                    }
                    break
                }
            }
        }

        guard let constant = modelConstant,
              let data = try? Data(contentsOf: URL(fileURLWithPath: modelsFile)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            return "gemini-pro-agent"
        }

        // 2. 在 available_models 中查找对应的 id
        for model in models {
            if let mc = model["modelConstant"] as? String, mc == constant {
                return (model["id"] as? String) ?? "gemini-pro-agent"
            }
        }
        return "gemini-pro-agent"
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
