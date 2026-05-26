import Foundation

struct OllamaLogParser: LogParser {
    let supportedProvider: LLMProvider = .ollama
    
    func canParse(url: URL, content: String) -> Bool {
        let path = url.path.lowercased()
        return path.contains(".ollama") || path.contains("ollama")
    }
    
    func parse(url: URL, content: String) -> [ParsedLog] {
        var results: [ParsedLog] = []
        let lines = content.components(separatedBy: .newlines)
        let fileDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Ollama server logs contain model loading, generation events
            if line.contains("model") || line.contains("generate") || line.contains("eval") {
                let model = firstMatch(in: line, pattern: #"model[=:\s]+["']?([\w\-.\/:@]+)"#)
                let totalDuration = firstMatch(in: line, pattern: #"total_duration[=:\s]+(\d+)"#)
                let evalCount = firstMatch(in: line, pattern: #"eval_count[=:\s]+(\d+)"#)
                let promptEvalCount = firstMatch(in: line, pattern: #"prompt_eval_count[=:\s]+(\d+)"#)
                let error = line.contains("error") || line.contains("ERROR") ? firstMatch(in: line, pattern: #"(?:error|ERROR)[:\s]+(.+)"#) : nil
                
                if model != nil || evalCount != nil {
                    let durationNs = totalDuration.flatMap(Double.init)
                    let timestamp = extractTimestamp(from: line) ?? fileDate
                    let detected = model.flatMap { detectProvider(model: $0, content: nil) } ?? .ollama
                    results.append(ParsedLog(
                        timestamp: timestamp,
                        sourceFile: url.path,
                        provider: detected == .custom ? .ollama : detected,
                        modelName: model,
                        promptTokens: promptEvalCount.flatMap(Int.init),
                        completionTokens: evalCount.flatMap(Int.init),
                        totalTokens: {
                            let p = promptEvalCount.flatMap(Int.init) ?? 0
                            let c = evalCount.flatMap(Int.init) ?? 0
                            return p + c > 0 ? p + c : nil
                        }(),
                        duration: durationNs.map { $0 / 1_000_000_000.0 },
                        errorMessage: error,
                        metadata: ["format": "ollama_log", "client": "ollama"]
                    ))
                }
            }
        }
        
        return results
    }
}
