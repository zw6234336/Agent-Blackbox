import Foundation

struct LogCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    let createdAt: Date
    var logIds: [UUID]
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        createdAt: Date = Date(),
        logIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.logIds = logIds
    }
}
