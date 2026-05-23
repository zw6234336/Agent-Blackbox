import Foundation

enum CompilationStatus: String, Codable {
    case pending
    case generating
    case paused
    case completed
    case cancelled

    var displayName: String {
        switch self {
        case .pending:    return "待生成"
        case .generating: return "生成中"
        case .paused:     return "已暂停"
        case .completed:  return "已完成"
        case .cancelled:  return "已取消"
        }
    }
}

enum CompilationOutputFormat: String, Codable, CaseIterable, Identifiable {
    case markdown
    case json
    case plainText = "plain_text"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown:  return "Markdown"
        case .json:      return "JSON"
        case .plainText: return "纯文本"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:  return "md"
        case .json:      return "json"
        case .plainText: return "txt"
        }
    }
}

struct LogCompilation: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    let createdAt: Date
    var updatedAt: Date

    var status: CompilationStatus
    var outputFormat: CompilationOutputFormat

    var providerFilters: [String]
    var startDate: Date?
    var endDate: Date?
    var bookmarkedOnly: Bool

    var lastCompiledTimestamp: Date?
    var totalLogCount: Int
    var appendCount: Int

    var progress: Double
    var progressMessage: String?

    var outputFilePath: String?
    var outputFileSize: Int64?

    var compiledProviders: [String]
    var compiledModels: [String]
    var compiledTokenTotal: Int
    var compiledCostTotal: Double

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: CompilationStatus = .pending,
        outputFormat: CompilationOutputFormat = .markdown,
        providerFilters: [String] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        bookmarkedOnly: Bool = false,
        lastCompiledTimestamp: Date? = nil,
        totalLogCount: Int = 0,
        appendCount: Int = 0,
        progress: Double = 0,
        progressMessage: String? = nil,
        outputFilePath: String? = nil,
        outputFileSize: Int64? = nil,
        compiledProviders: [String] = [],
        compiledModels: [String] = [],
        compiledTokenTotal: Int = 0,
        compiledCostTotal: Double = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.outputFormat = outputFormat
        self.providerFilters = providerFilters
        self.startDate = startDate
        self.endDate = endDate
        self.bookmarkedOnly = bookmarkedOnly
        self.lastCompiledTimestamp = lastCompiledTimestamp
        self.totalLogCount = totalLogCount
        self.appendCount = appendCount
        self.progress = progress
        self.progressMessage = progressMessage
        self.outputFilePath = outputFilePath
        self.outputFileSize = outputFileSize
        self.compiledProviders = compiledProviders
        self.compiledModels = compiledModels
        self.compiledTokenTotal = compiledTokenTotal
        self.compiledCostTotal = compiledCostTotal
    }
}
