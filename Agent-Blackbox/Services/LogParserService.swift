import Foundation

final class LogParserService: Sendable {
    private let parsers: [any LogParser] = [
        WarpParser(),
        CursorLogParser(),
        ClaudeDesktopParser(),
        OllamaLogParser(),
        ClineParser(),
        ClaudeCodeCLIParser(),
        AmpThreadParser(),
        AntigravityParser(),
        PiParser(),
        CopilotChatSessionJSONLParser(), // .jsonl 格式（新版 VS Code，含 modelId/耗时）
        CopilotChatSessionParser(),      // .json 格式（旧版 VS Code）
        GenericLLMParser()  // fallback, always last
    ]
    
    /// 实时事件入口：文件被修改时调用，返回最新一条（jsonl 追加场景需要尾部）
    func parseLogFile(at url: URL) async -> ParsedLog? {
        let all = await parseAllEntries(at: url)
        // 取时间戳最大的一条作为最新
        return all.max(by: { $0.timestamp < $1.timestamp })
    }

    /// 初始扫描入口：解析全部条目
    func parseAllEntries(at url: URL) async -> [ParsedLog] {
        let ext = url.pathExtension.lowercased()

        if ext == "vscdb" {
            let p = CursorVSCDBParser()
            return p.canParse(url: url, content: "") ? p.parse(url: url, content: "") : []
        }

        if ext == "db" {
            let p = VSCodeCopilotParser()
            return p.canParse(url: url, content: "") ? p.parse(url: url, content: "") : []
        }

        // 文本/JSON/JSONL：读完整文件（旧实现只读 1MB 导致大 jsonl 静默丢数据）
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            return []
        }

        for parser in parsers {
            if parser.canParse(url: url, content: content) {
                let results = parser.parse(url: url, content: content)
                if !results.isEmpty {
                    return results
                }
            }
        }
        return []
    }
}
