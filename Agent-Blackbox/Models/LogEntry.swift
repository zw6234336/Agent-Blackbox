import Foundation

struct ParsedLog: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let sourceFile: String
    let provider: LLMProvider?
    let modelName: String?
    let prompt: String?
    let response: String?
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let duration: TimeInterval?
    let statusCode: Int?
    let errorMessage: String?
    var isBookmarked: Bool
    var tags: [String]
    var notes: String?
    let conversationId: String?
    let metadata: [String: String]

    init(
        id: UUID? = nil,
        timestamp: Date = Date(),
        sourceFile: String,
        provider: LLMProvider? = nil,
        modelName: String? = nil,
        prompt: String? = nil,
        response: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        duration: TimeInterval? = nil,
        statusCode: Int? = nil,
        errorMessage: String? = nil,
        isBookmarked: Bool = false,
        tags: [String] = [],
        notes: String? = nil,
        conversationId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        if let id = id {
            self.id = id
        } else {
            let components = "\(provider?.rawValue ?? "")-\(modelName ?? "")-\(timestamp.timeIntervalSince1970)-\(prompt ?? "")-\(response ?? "")-\(errorMessage ?? "")"
            self.id = UUID.deterministic(from: components)
        }
        self.timestamp = timestamp
        self.sourceFile = sourceFile
        self.provider = provider
        self.modelName = modelName
        self.prompt = prompt
        self.response = response
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.duration = duration
        self.statusCode = statusCode
        self.errorMessage = errorMessage
        self.isBookmarked = isBookmarked
        self.tags = tags
        self.notes = notes
        self.conversationId = conversationId
        self.metadata = metadata
    }
    
    /// Legacy compatibility: returns totalTokens
    var tokensUsed: Int? { totalTokens }

    /// 验证模型名是否像真实模型名，剔除 `default`、`unknown`、`n_ctx`、`FileNotFoundError` 等污染和默认值
    static func isValidModelName(_ raw: String?) -> Bool {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return false }
        if s.count < 3 { return false }
        if s.rangeOfCharacter(from: .letters) == nil { return false }
        
        let blocklist: Set<String> = [
            "default", "unknown", "synthetic", "<synthetic>", "n_ctx", "n_batch", "n_gpu_layers", "n_threads",
            "rope_freq_base", "rope_freq_scale", "filenotfounderror", "valueerror", "typeerror",
            "runtimeerror", "indexerror", "keyerror", "modulenotfounderror", "permissionerror",
            "true", "false", "none", "null", "nil", "openaichatmodel.builder"
        ]
        if blocklist.contains(s.lowercased()) { return false }
        if s.range(of: #"^[\d\.]+$"#, options: .regularExpression) != nil { return false }
        if s.contains(".") {
            let parts = s.split(separator: ".")
            if parts.count >= 2, parts.allSatisfy({ $0.first?.isUppercase ?? false }) {
                return false
            }
        }
        return true
    }
}
