import Foundation

/// A single parsed LLM interaction record.
struct LogEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let platform: LLMPlatform
    let timestamp: Date
    var prompt: String?
    var response: String?
    var model: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var rawContent: String
    var filePath: String
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        platform: LLMPlatform,
        timestamp: Date = Date(),
        prompt: String? = nil,
        response: String? = nil,
        model: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        rawContent: String,
        filePath: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.platform = platform
        self.timestamp = timestamp
        self.prompt = prompt
        self.response = response
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.rawContent = rawContent
        self.filePath = filePath
        self.metadata = metadata
    }

    // MARK: - Equatable / Hashable (identity-based)

    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Helpers

    var tokenSummary: String {
        if let total = totalTokens {
            return "\(total) tokens"
        }
        if let input = inputTokens, let output = outputTokens {
            return "\(input + output) tokens (\(input)↑ \(output)↓)"
        }
        if let input = inputTokens { return "\(input) input tokens" }
        if let output = outputTokens { return "\(output) output tokens" }
        return ""
    }

    var promptPreview: String {
        if let p = prompt, !p.isEmpty { return String(p.prefix(120)) }
        return String(rawContent.prefix(120))
    }

    /// Builds a deterministic UUID from a file path + raw content so that re-scanning
    /// the same log line never creates a duplicate database row.
    /// The first 256 characters of `rawContent` are used as a key — long enough to
    /// distinguish nearly all distinct log lines while keeping hashing fast.
    static func stableID(filePath: String, rawContent: String) -> UUID {
        let key = "\(filePath):\(rawContent.prefix(256))"
        var h1 = UInt64(14695981039346656037)
        for byte in key.utf8 {
            h1 ^= UInt64(byte)
            h1 &*= 1099511628211
        }
        var h2 = h1 ^ 0xDEAD_BEEF_CAFE_BABE
        h2 ^= (h2 >> 33); h2 &*= 0xFF51AFD7ED558CCD
        h2 ^= (h2 >> 33); h2 &*= 0xC4CEB9FE1A85EC53
        h2 ^= (h2 >> 33)

        var bytes = withUnsafeBytes(of: h1.bigEndian, Array.init)
            + withUnsafeBytes(of: h2.bigEndian, Array.init)
        // Stamp as UUID version 4, variant 1
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
