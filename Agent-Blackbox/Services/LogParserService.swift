import Foundation

final class LogParserService {
    func parseLogFile(at url: URL) async -> ParsedLog? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        let chunk = (try? handle.read(upToCount: 512 * 1024)) ?? Data()
        guard let content = String(data: chunk, encoding: .utf8), !content.isEmpty else {
            return nil
        }

        if url.pathExtension.lowercased() == "json" {
            return parseJSONLog(content, sourceFile: url.path)
        }
        return parseTextLog(content, sourceFile: url.path)
    }

    func parseJSONLog(_ content: String, sourceFile: String) -> ParsedLog? {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let prompt = maskAPIKey(object["prompt"] as? String)
        let response = maskAPIKey(object["response"] as? String)
        let errorMessage = maskAPIKey(object["error"] as? String)

        return ParsedLog(
            sourceFile: sourceFile,
            modelName: object["model"] as? String,
            prompt: prompt,
            response: response,
            tokensUsed: object["tokens"] as? Int,
            errorMessage: errorMessage,
            metadata: ["format": "json"]
        )
    }

    func parseTextLog(_ content: String, sourceFile: String) -> ParsedLog? {
        let model = firstMatch(in: content, pattern: #"model\s*[:=]\s*([\w\-.]+)"#)
        let tokenText = firstMatch(in: content, pattern: #"tokens?\s*[:=]\s*(\d+)"#)
        let prompt = maskAPIKey(firstMatch(in: content, pattern: #"prompt\s*[:=]\s*(.+)"#))
        let response = maskAPIKey(firstMatch(in: content, pattern: #"response\s*[:=]\s*(.+)"#))
        let error = maskAPIKey(firstMatch(in: content, pattern: #"error\s*[:=]\s*(.+)"#))

        return ParsedLog(
            sourceFile: sourceFile,
            modelName: model,
            prompt: prompt,
            response: response,
            tokensUsed: tokenText.flatMap(Int.init),
            errorMessage: error,
            metadata: ["format": "text"]
        )
    }

    func maskAPIKey(_ text: String?) -> String? {
        guard let text else { return nil }
        let pattern = #"\b(sk|rk)-[A-Za-z0-9_-]{8,}\b"#
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

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else {
            return nil
        }

        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
