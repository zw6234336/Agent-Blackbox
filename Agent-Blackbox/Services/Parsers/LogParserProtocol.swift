import Foundation

protocol LogParser: Sendable {
    var supportedProvider: LLMProvider { get }
    func canParse(url: URL, content: String) -> Bool
    func parse(url: URL, content: String) -> [ParsedLog]
}

extension LogParser {
    /// Helper to mask API keys in text
    func maskAPIKey(_ text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"\b(sk|rk|api|key|token)-[A-Za-z0-9_\-]{8,}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        var masked = text
        for match in matches {
            let full = ns.substring(with: match.range)
            let prefix = full.prefix(5)
            let replacement = "\(prefix)***"
            if let range = Range(match.range, in: masked) {
                masked.replaceSubrange(range, with: replacement)
            }
        }
        return masked
    }
    
    /// Helper to extract first regex match
    func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Parse standard date formats
    func parseDate(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }
        
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: trimmed) {
                return date
            }
        }
        
        return nil
    }
    
    /// Extract timestamp from the beginning of a log line
    func extractTimestamp(from line: String) -> Date? {
        let pattern = #"^\[?(\d{4}[-/]\d{2}[-/]\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?)\]?"#
        guard let dateStr = firstMatch(in: line, pattern: pattern) else {
            return nil
        }
        return parseDate(from: dateStr)
    }
    
    /// Detect actual LLM provider based on model name, content, or source file
    func detectProvider(model: String?, content: String?, sourceFile: String? = nil) -> LLMProvider {
        if let sourceFile = sourceFile?.lowercased() {
            if sourceFile.contains("copilot") { return .copilot }
            if sourceFile.contains("cursor") && sourceFile.hasSuffix(".vscdb") { return .cursor }
            if sourceFile.contains("antigravity") { return .antigravity }
            if sourceFile.contains("/.pi/") || sourceFile.contains("/com.inflection.pi/") { return .pi }
            if sourceFile.contains("dev.warp.warp-stable") || sourceFile.contains("/.warp/") { return .warp }
            if sourceFile.contains("/.codex/sessions/") { return .codex }
        }
        
        guard let model = model?.lowercased() else {
            if let content = content?.lowercased() {
                if content.contains("openai") { return .openai }
                if content.contains("anthropic") || content.contains("claude") { return .anthropic }
                if content.contains("google") || content.contains("gemini") { return .google }
                if content.contains("deepseek") { return .deepseek }
                if content.contains("qwen") { return .qwen }
                if content.contains("kimi") || content.contains("moonshot") { return .kimi }
                if content.contains("glm") || content.contains("chatglm") || content.contains("zhipu") { return .zhipu }
                if content.contains("inflection") || content.contains("pi.ai") { return .pi }
            }
            return .custom
        }
        
        let isLocalModel = model.contains("gguf") ||
                           model.contains("mlx") ||
                           model.contains("local") ||
                           (model.contains("/") && !model.hasPrefix("ft:"))
        
        if isLocalModel {
            if model.contains("ollama") { return .ollama }
            return .lmstudio
        }
        
        if model.contains("codex") { return .codex }
        if model.contains("gpt") || model.contains("o1") || model.contains("o3") || model.contains("o4") { return .openai }
        if model.contains("claude") { return .anthropic }
        if model.contains("gemini") || model.contains("palm") { return .google }
        if model.contains("warp") { return .warp }
        if model.contains("deepseek") { return .deepseek }
        if model.contains("qwen") { return .qwen }
        if model.contains("kimi") || model.contains("moonshot") { return .kimi }
        if model.contains("glm") || model.contains("chatglm") || model.contains("zhipu") { return .zhipu }
        if model.contains("llama") || model.contains("mistral") || model.contains("gemma") { return .ollama }
        if model.contains("copilot") { return .copilot }
        if model.contains("cursor") { return .cursor }
        if model.contains("inflection") || model.contains("pi-") { return .pi }
        
        return .custom
    }
}

