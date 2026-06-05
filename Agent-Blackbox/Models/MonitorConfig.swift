import Foundation

struct MonitorConfig: Codable, Equatable {
    var monitoredDirectories: [String] = MonitorConfig.defaultTargetedDirectories()
    
    static func defaultTargetedDirectories() -> [String] {
        var paths: [String] = []
        let fm = FileManager.default
        let home = NSHomeDirectory()
        
        let candidates = [
            // Claude Desktop / Anthropic / Claude Code CLI
            home + "/Library/Logs/Claude/",
            home + "/Library/Application Support/Claude/",
            home + "/.claude/",
            
            // Cursor
            home + "/Library/Application Support/Cursor/User/workspaceStorage/",
            home + "/Library/Application Support/Cursor/User/globalStorage/",
            home + "/Library/Application Support/Cursor/logs/",
            
            // Ollama
            home + "/.ollama/logs/",
            
            // Copilot (VS Code, Cursor, Xcode)
            home + "/Library/Application Support/Code/logs/",
            home + "/Library/Application Support/Code/User/workspaceStorage/",
            home + "/Library/Application Support/Code/User/globalStorage/github.copilot-chat/",
            home + "/Library/Application Support/Cursor/User/workspaceStorage/",
            home + "/Library/Logs/CopilotForXcode/",
            home + "/Library/Application Support/CopilotForXcode/",
            
            // OpenAI (ChatGPT Desktop)
            home + "/Library/Application Support/com.openai.chat/",
            home + "/Library/Group Containers/group.com.openai.chat/",
            home + "/.codex/sessions/",
            
            // Gemini (GCloud CLI logs)
            home + "/.config/gcloud/logs/",

            // Antigravity (Google)
            home + "/.gemini/antigravity/brain/",

            // Warp
            home + "/Library/Application Support/dev.warp.Warp-Stable/",
            home + "/Library/Logs/warp.log",
            home + "/.warp/",
            
            // Cline (VS Code & Cursor)
            home + "/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks/",
            home + "/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks/",
            
            // LM Studio
            home + "/.lmstudio/",
            home + "/.cache/lm-studio/",
            
            // Continue.dev
            home + "/.continue/logs/",
            home + "/.continue/sessions/",

            // Amp (Sourcegraph)
            home + "/.local/share/amp/threads/",
            home + "/.local/share/amp/",
            home + "/.cache/amp/logs/",

            // Pi (Inflection AI)
            home + "/.pi/logs/",
            home + "/.pi/",
            home + "/Library/Application Support/Pi/",
            home + "/Library/Application Support/com.inflection.pi/",
            home + "/Library/Logs/Pi/"
        ]
        
        for path in candidates {
            if fm.fileExists(atPath: path) {
                paths.append(path)
            }
        }
        
        // Fallback to standard logs if no specific LLM tool folders exist yet
        if paths.isEmpty {
            let standardLogs = home + "/Library/Logs/"
            if fm.fileExists(atPath: standardLogs) {
                paths.append(standardLogs)
            }
        }
        
        return paths
    }
    /// 文件匹配 patterns。含 `/` 的对完整路径匹配，不含的对文件名匹配。
    var filePatterns: [String] = [
        "*.log", "*.txt", "*llm*.json", "*.jsonl",
        "state.vscdb", "session-store.db", "*.db",
        "api_conversation_history.json",
        "warp_network.log",
        "T-*.json",                       // Amp threads
        "*/chatSessions/*.json",          // VSCode Copilot chat sessions
        "*/threads/T-*.json",             // Amp threads (path-scoped, redundant safety)
        "*/dev.warp.Warp-Stable/mcp/*.log", // Warp MCP logs
        "*/.pi/*.json",                     // Pi conversation exports (path-scoped)
        "*/.pi/*.jsonl",                    // Pi JSONL logs (path-scoped)
        "*/com.inflection.pi/*.json",      // Pi desktop app logs (path-scoped)
        "pi-conversation-*.json"            // Pi explicit export filename
    ]
    var isRecursive: Bool = true
    var refreshInterval: TimeInterval = 1.0
    var databasePath: String = NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/logs.db"
    var enableNotifications: Bool = true
    var autoStart: Bool = true
    var enabledProviders: [String] = LLMProvider.allCases.map { $0.rawValue }
    var dataRetentionDays: Int = 90
    var exportDirectory: String = NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/Exports/"
    
    // Backup and Pruning Settings
    var enableAutoBackup: Bool = true
    var backupIntervalDays: Int = 7
    var maxBackupFiles: Int = 5
    var backupDirectory: String = NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/Backups/"
    var backupDirectoryBookmark: String? = nil
    var lastBackupTimestamp: Double = 0
    var enableAutoPrune: Bool = true
    
    // Proxy Settings
    var enableProxy: Bool = true
    var proxyPort: Int = 9999
    var openaiUpstreamUrl: String = "https://api.openai.com"
    var anthropicUpstreamUrl: String = "https://api.anthropic.com"
    
    // Automated Interception Settings
    var enableVSCodeClineInterception: Bool = false
    var enableVSCodeRooClineInterception: Bool = false
    var enableCursorClineInterception: Bool = false
    var enableCursorRooClineInterception: Bool = false
    var enableClaudeCodeInterception: Bool = false
    var enablePiInterception: Bool = false
    var enableVSCodeCopilotInterception: Bool = false
    
    // 每个 provider 的限额配置（RPM / TPM / 日预算 / 月预算）
    var providerRateLimits: [String: ProviderRateLimit] = ProviderRateLimit.defaults()

    /// 速率统计采样间隔（秒）
    var rateSamplingInterval: TimeInterval = 5.0

    // MARK: - Decodable Custom Implementation
    
    enum CodingKeys: String, CodingKey {
        case monitoredDirectories
        case filePatterns
        case isRecursive
        case refreshInterval
        case databasePath
        case enableNotifications
        case autoStart
        case enabledProviders
        case dataRetentionDays
        case exportDirectory
        case enableAutoBackup
        case backupIntervalDays
        case maxBackupFiles
        case backupDirectory
        case backupDirectoryBookmark
        case lastBackupTimestamp
        case enableAutoPrune
        case enableProxy
        case proxyPort
        case openaiUpstreamUrl
        case anthropicUpstreamUrl
        case enableVSCodeClineInterception
        case enableVSCodeRooClineInterception
        case enableCursorClineInterception
        case enableCursorRooClineInterception
        case enableClaudeCodeInterception
        case enablePiInterception
        case enableVSCodeCopilotInterception
        case providerRateLimits
        case rateSamplingInterval
    }
    
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.monitoredDirectories = try container.decodeIfPresent([String].self, forKey: .monitoredDirectories) ?? MonitorConfig.defaultTargetedDirectories()
        
        self.filePatterns = try container.decodeIfPresent([String].self, forKey: .filePatterns) ?? [
            "*.log", "*.txt", "*llm*.json", "*.jsonl",
            "state.vscdb", "session-store.db", "*.db",
            "api_conversation_history.json",
            "warp_network.log",
            "T-*.json",
            "*/chatSessions/*.json",
            "*/threads/T-*.json",
            "*/dev.warp.Warp-Stable/mcp/*.log",
            "*/.pi/*.json",
            "*/.pi/*.jsonl",
            "*/com.inflection.pi/*.json",
            "pi-conversation-*.json"
        ]
        
        self.isRecursive = try container.decodeIfPresent(Bool.self, forKey: .isRecursive) ?? true
        self.refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 1.0
        self.databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath) ?? (NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/logs.db")
        self.enableNotifications = try container.decodeIfPresent(Bool.self, forKey: .enableNotifications) ?? true
        self.autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? true
        self.enabledProviders = try container.decodeIfPresent([String].self, forKey: .enabledProviders) ?? LLMProvider.allCases.map { $0.rawValue }
        self.dataRetentionDays = try container.decodeIfPresent(Int.self, forKey: .dataRetentionDays) ?? 90
        self.exportDirectory = try container.decodeIfPresent(String.self, forKey: .exportDirectory) ?? (NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/Exports/")
        
        self.enableAutoBackup = try container.decodeIfPresent(Bool.self, forKey: .enableAutoBackup) ?? true
        self.backupIntervalDays = try container.decodeIfPresent(Int.self, forKey: .backupIntervalDays) ?? 7
        self.maxBackupFiles = try container.decodeIfPresent(Int.self, forKey: .maxBackupFiles) ?? 5
        self.backupDirectory = try container.decodeIfPresent(String.self, forKey: .backupDirectory) ?? (NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/Backups/")
        self.backupDirectoryBookmark = try container.decodeIfPresent(String.self, forKey: .backupDirectoryBookmark)
        self.lastBackupTimestamp = try container.decodeIfPresent(Double.self, forKey: .lastBackupTimestamp) ?? 0
        self.enableAutoPrune = try container.decodeIfPresent(Bool.self, forKey: .enableAutoPrune) ?? true
        
        self.enableProxy = try container.decodeIfPresent(Bool.self, forKey: .enableProxy) ?? true
        self.proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort) ?? 9999
        self.openaiUpstreamUrl = try container.decodeIfPresent(String.self, forKey: .openaiUpstreamUrl) ?? "https://api.openai.com"
        self.anthropicUpstreamUrl = try container.decodeIfPresent(String.self, forKey: .anthropicUpstreamUrl) ?? "https://api.anthropic.com"
        
        self.enableVSCodeClineInterception = try container.decodeIfPresent(Bool.self, forKey: .enableVSCodeClineInterception) ?? false
        self.enableVSCodeRooClineInterception = try container.decodeIfPresent(Bool.self, forKey: .enableVSCodeRooClineInterception) ?? false
        self.enableCursorClineInterception = try container.decodeIfPresent(Bool.self, forKey: .enableCursorClineInterception) ?? false
        self.enableCursorRooClineInterception = try container.decodeIfPresent(Bool.self, forKey: .enableCursorRooClineInterception) ?? false
        self.enableClaudeCodeInterception = try container.decodeIfPresent(Bool.self, forKey: .enableClaudeCodeInterception) ?? false
        self.enablePiInterception = try container.decodeIfPresent(Bool.self, forKey: .enablePiInterception) ?? false
        self.enableVSCodeCopilotInterception = try container.decodeIfPresent(Bool.self, forKey: .enableVSCodeCopilotInterception) ?? false
        self.providerRateLimits = try container.decodeIfPresent([String: ProviderRateLimit].self, forKey: .providerRateLimits) ?? ProviderRateLimit.defaults()
        self.rateSamplingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .rateSamplingInterval) ?? 5.0
    }
}

