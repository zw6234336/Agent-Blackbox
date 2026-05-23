import Foundation

struct MonitorConfig: Codable, Equatable {
    var monitoredDirectories: [String] = [
        NSHomeDirectory() + "/Library/Logs/",
        NSHomeDirectory() + "/Library/Application Support/",
        NSHomeDirectory() + "/.cache/"
    ]
    var filePatterns: [String] = ["*.log", "*.txt", "*llm*.json"]
    var isRecursive: Bool = true
    var refreshInterval: TimeInterval = 1.0
    var databasePath: String = NSHomeDirectory() + "/Library/Application Support/Agent-Blackbox/logs.db"
    var enableNotifications: Bool = true
    var autoStart: Bool = false
}
