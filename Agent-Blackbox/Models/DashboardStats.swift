import Foundation

struct DashboardStats {
    var totalCalls: Int = 0
    var totalTokens: Int = 0
    var totalPromptTokens: Int = 0
    var totalCompletionTokens: Int = 0
    var errorCount: Int = 0
    var avgResponseTime: Double = 0.0
    var callsByProvider: [LLMProvider: Int] = [:]
    var providerStats: [LLMProvider: ProviderStat] = [:]
    var callsByModel: [String: Int] = [:]
    var tokensByDay: [DayTokens] = []
    var modelTokensByDay: [ModelDayTokens] = []
    var recentLogs: [ParsedLog] = []
    
    var slowestLog: ParsedLog? = nil
    var largestPayloadLog: ParsedLog? = nil
    var localCallsCount: Int = 0
    var trainingPairCount: Int = 0
    var uniqueModelCount: Int = 0
    var uniqueProviderCount: Int = 0
    
    var errorRate: Double {
        guard totalCalls > 0 else { return 0 }
        return Double(errorCount) / Double(totalCalls) * 100.0
    }
    
    var successRate: Double {
        guard totalCalls > 0 else { return 0 }
        return 100.0 - errorRate
    }

    var promptCompletionRatio: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(totalPromptTokens) / Double(totalTokens)
    }
}

struct DayTokens: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let promptTokens: Int
    let completionTokens: Int
    
    var totalTokens: Int { promptTokens + completionTokens }
}

struct ModelDayTokens: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let modelName: String
    let promptTokens: Int
    let completionTokens: Int
    
    var totalTokens: Int { promptTokens + completionTokens }
}


struct ProviderStat: Identifiable, Hashable {
    let id = UUID()
    let provider: LLMProvider
    let count: Int
    let tokens: Int
    let avgDuration: Double
}

struct ModelStat: Identifiable {
    let id = UUID()
    let modelName: String
    let count: Int
    let tokens: Int
}
