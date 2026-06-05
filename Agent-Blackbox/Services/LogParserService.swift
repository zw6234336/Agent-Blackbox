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
        OpenAICodexParser(),
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

        // 优先匹配特定工具的解析器（非 GenericLLMParser）
        for parser in parsers {
            if !(parser is GenericLLMParser) {
                if parser.canParse(url: url, content: content) {
                    // 如果特定解析器匹配了，不管解析出几条（哪怕是0条），都直接返回其结果
                    // 避免 fallback 到 GenericLLMParser 提取出噪声数据
                    return parser.parse(url: url, content: content)
                }
            }
        }
        
        // 没有特定解析器匹配时，才使用 GenericLLMParser 进行兜底
        if let fallback = parsers.first(where: { $0 is GenericLLMParser }),
           fallback.canParse(url: url, content: content) {
            return fallback.parse(url: url, content: content)
        }
        
        return []
    }
}
