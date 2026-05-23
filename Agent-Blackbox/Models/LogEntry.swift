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
    let estimatedCost: Double?
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
        estimatedCost: Double? = nil,
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
        self.estimatedCost = estimatedCost
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
}
