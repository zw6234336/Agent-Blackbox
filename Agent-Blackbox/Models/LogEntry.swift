import Foundation

struct ParsedLog: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let sourceFile: String
    let modelName: String?
    let prompt: String?
    let response: String?
    let tokensUsed: Int?
    let errorMessage: String?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sourceFile: String,
        modelName: String? = nil,
        prompt: String? = nil,
        response: String? = nil,
        tokensUsed: Int? = nil,
        errorMessage: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceFile = sourceFile
        self.modelName = modelName
        self.prompt = prompt
        self.response = response
        self.tokensUsed = tokensUsed
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}
