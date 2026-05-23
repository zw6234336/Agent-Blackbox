import Foundation

struct DashboardStats {
    var totalCalls: Int = 0
    var totalTokens: Int = 0
    var totalPromptTokens: Int = 0
    var totalCompletionTokens: Int = 0
    var totalCost: Double = 0.0
    var errorCount: Int = 0
    var avgResponseTime: Double = 0.0
    var callsByProvider: [LLMProvider: Int] = [:]
    var callsByModel: [String: Int] = [:]
    var tokensByDay: [DayTokens] = []
    var recentLogs: [ParsedLog] = []
    
    var errorRate: Double {
        guard totalCalls > 0 else { return 0 }
        return Double(errorCount) / Double(totalCalls) * 100.0
    }
    
    var successRate: Double {
        guard totalCalls > 0 else { return 0 }
        return 100.0 - errorRate
    }
}

struct DayTokens: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let promptTokens: Int
    let completionTokens: Int
    
    var totalTokens: Int { promptTokens + completionTokens }
}

struct ProviderStat: Identifiable {
    let id = UUID()
    let provider: LLMProvider
    let count: Int
    let tokens: Int
    let cost: Double
}

struct ModelStat: Identifiable {
    let id = UUID()
    let modelName: String
    let count: Int
    let tokens: Int
}
