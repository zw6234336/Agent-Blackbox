import Foundation
import AppKit

enum InterceptClient: String, CaseIterable, Identifiable {
    case vscodeCline = "vscode_cline"
    case vscodeRooCline = "vscode_roo_cline"
    case cursorCline = "cursor_cline"
    case cursorRooCline = "cursor_roo_cline"
    case claudeCode = "claude_code"
    case pi = "pi"
    case vscodeCopilot = "vscode_copilot"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .vscodeCline: return "VS Code Cline"
        case .vscodeRooCline: return "VS Code Roo-Cline"
        case .cursorCline: return "Cursor Cline"
        case .cursorRooCline: return "Cursor Roo-Cline"
        case .claudeCode: return "Claude Code"
        case .pi: return "Pi Agent"
        case .vscodeCopilot: return "VS Code GitHub Copilot"
        }
    }
    
    var settingsURL: URL {
        let home = NSHomeDirectory()
        switch self {
        case .vscodeCline:
            return URL(fileURLWithPath: home + "/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_settings.json")
        case .vscodeRooCline:
            return URL(fileURLWithPath: home + "/Library/Application Support/Code/User/globalStorage/roovet.roo-cline/settings/roo_cline_settings.json")
        case .cursorCline:
            return URL(fileURLWithPath: home + "/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/cline_settings.json")
        case .cursorRooCline:
            return URL(fileURLWithPath: home + "/Library/Application Support/Cursor/User/globalStorage/roovet.roo-cline/settings/roo_cline_settings.json")
        case .claudeCode:
            return URL(fileURLWithPath: home + "/.claude/settings.json")
        case .pi:
            return URL(fileURLWithPath: home + "/.pi/agent/models.json")
        case .vscodeCopilot:
            return URL(fileURLWithPath: home + "/Library/Application Support/Code/User/settings.json")
        }
    }
    
    var backupURL: URL {
        return settingsURL.deletingPathExtension().appendingPathExtension("json.backup")
    }
}

@MainActor
final class ClientInterceptionService: ObservableObject {
    @Published var activeStates: [InterceptClient: Bool] = [:]
    @Published var errors: [InterceptClient: String] = [:]
    @Published var existsStates: [InterceptClient: Bool] = [:]
    
    private var configService: ConfigService?
    
    init() {
        // Initial check of existences
        let fm = FileManager.default
        var states: [InterceptClient: Bool] = [:]
        for client in InterceptClient.allCases {
            states[client] = fm.fileExists(atPath: client.settingsURL.path)
        }
        self.existsStates = states
        
        // Register for app termination to restore all original settings automatically
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.restoreAll()
            }
        }
    }
    
    func bind(config: ConfigService) {
        self.configService = config
        syncWithConfig()
    }
    
    func syncWithConfig() {
        guard let config = configService?.config else { return }
        
        let fm = FileManager.default
        for client in InterceptClient.allCases {
            existsStates[client] = fm.fileExists(atPath: client.settingsURL.path)
        }
        
        updateInterceptionState(.vscodeCline, shouldIntercept: config.enableVSCodeClineInterception)
        updateInterceptionState(.vscodeRooCline, shouldIntercept: config.enableVSCodeRooClineInterception)
        updateInterceptionState(.cursorCline, shouldIntercept: config.enableCursorClineInterception)
        updateInterceptionState(.cursorRooCline, shouldIntercept: config.enableCursorRooClineInterception)
        updateInterceptionState(.claudeCode, shouldIntercept: config.enableClaudeCodeInterception)
        updateInterceptionState(.pi, shouldIntercept: config.enablePiInterception)
        updateInterceptionState(.vscodeCopilot, shouldIntercept: config.enableVSCodeCopilotInterception)
    }
    
    func updateInterceptionState(_ client: InterceptClient, shouldIntercept: Bool) {
        activeStates[client] = shouldIntercept
        
        let fileURL = client.settingsURL
        let fm = FileManager.default
        
        // If file doesn't exist, we just skip (client might not be installed/initialized)
        guard fm.fileExists(atPath: fileURL.path) else {
            if shouldIntercept {
                errors[client] = "找不到配置文件，请确认是否已安装并在编辑器中配置过该插件。"
            } else {
                errors[client] = nil
            }
            return
        }
        
        if shouldIntercept {
            do {
                try applyInterception(for: client)
                errors[client] = nil
            } catch {
                errors[client] = "写入失败: \(error.localizedDescription)。请检查沙盒限制或系统磁盘权限。"
                Logger.shared.error("自动接管 \(client.displayName) 失败: \(error.localizedDescription)")
            }
        } else {
            do {
                try restoreInterception(for: client)
                errors[client] = nil
            } catch {
                errors[client] = "恢复备份失败: \(error.localizedDescription)"
                Logger.shared.error("恢复 \(client.displayName) 备份失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func applyInterception(for client: InterceptClient) throws {
        let fm = FileManager.default
        let settingsURL = client.settingsURL
        let backupURL = client.backupURL
        
        let proxyPort = configService?.config.proxyPort ?? 9999
        
        // 1. Create directory for backup if needed and copy original settings
        if !fm.fileExists(atPath: backupURL.path) {
            try fm.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try fm.copyItem(at: settingsURL, to: backupURL)
        }
        
        // 2. Read and parse JSON
        let data = try Data(contentsOf: settingsURL)
        guard var json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
            throw NSError(domain: "ClientInterceptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }
        
        switch client {
        case .vscodeCline, .vscodeRooCline, .cursorCline, .cursorRooCline:
            // 3. Inject our proxy configurations
            json["apiProvider"] = "openai"
            json["openAiBaseUrl"] = "http://127.0.0.1:\(proxyPort)/v1"
            
            // Ensure standard fields are filled so Cline does not show error panels
            if (json["openAiModelId"] as? String)?.isEmpty ?? true {
                json["openAiModelId"] = "gpt-4o"
            }
            if (json["openAiApiKey"] as? String)?.isEmpty ?? true {
                json["openAiApiKey"] = "agent-blackbox-proxy"
            }
            
        case .claudeCode:
            var env = json["env"] as? [String: String] ?? [:]
            env["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:\(proxyPort)"
            json["env"] = env
            
        case .vscodeCopilot:
            var advanced = json["github.copilot.advanced"] as? [String: Any] ?? [:]
            advanced["debug.overrideProxyUrl"] = "http://127.0.0.1:\(proxyPort)"
            advanced["debug.testOverrideProxyUrl"] = "http://127.0.0.1:\(proxyPort)"
            json["github.copilot.advanced"] = advanced
            
        case .pi:
            guard var providers = json["providers"] as? [String: [String: Any]] else {
                throw NSError(domain: "ClientInterceptionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No providers object found"])
            }
            
            // If zai is not explicitly defined, we inject it to intercept built-in zai calls
            if providers["zai"] == nil {
                let authKey = getZaiAuthKey()
                providers["zai"] = [
                    "api": "openai-completions",
                    "apiKey": authKey ?? "zai_api_key",
                    "baseUrl": "http://127.0.0.1:\(proxyPort)/v1",
                    "headers": [
                        "x-upstream-url": "https://open.bigmodel.cn/api/paas/v4",
                        "x-client-identifier": "pi"
                    ],
                    "models": [
                        ["id": "glm-5.1", "name": "GLM-5.1", "contextWindow": 200000, "maxTokens": 4096, "input": ["text"]],
                        ["id": "glm-5", "name": "GLM-5", "contextWindow": 200000, "maxTokens": 4096, "input": ["text"]],
                        ["id": "glm-4.7", "name": "GLM-4.7", "contextWindow": 204800, "maxTokens": 4096, "input": ["text"]],
                        ["id": "glm-4.7-flash", "name": "GLM-4.7 Flash", "contextWindow": 204800, "maxTokens": 4096, "input": ["text"]]
                    ]
                ]
            }
            
            for (key, var provider) in providers {
                if let oldBaseUrl = provider["baseUrl"] as? String {
                    if oldBaseUrl.contains("127.0.0.1") && oldBaseUrl.contains("\(proxyPort)") {
                        continue
                    }
                    
                    var upstreamBase = oldBaseUrl
                    if upstreamBase.hasSuffix("/v1") {
                        upstreamBase = String(upstreamBase.dropLast(3))
                    } else if upstreamBase.hasSuffix("/v1/") {
                        upstreamBase = String(upstreamBase.dropLast(4))
                    }
                    
                    var headers = provider["headers"] as? [String: String] ?? [:]
                    headers["x-upstream-url"] = upstreamBase
                    headers["x-client-identifier"] = "pi"
                    provider["headers"] = headers
                    
                    provider["baseUrl"] = "http://127.0.0.1:\(proxyPort)/v1"
                    providers[key] = provider
                }
            }
            
            json["providers"] = providers
        }
        
        // 4. Write modified JSON back
        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: settingsURL, options: .atomic)
        Logger.shared.info("自动接管: 已将 \(client.displayName) 接管代理指向端口 \(proxyPort)")
    }
    
    private func restoreInterception(for client: InterceptClient) throws {
        let fm = FileManager.default
        let settingsURL = client.settingsURL
        let backupURL = client.backupURL
        
        guard fm.fileExists(atPath: backupURL.path) else {
            return
        }
        
        // Delete modified settings
        if fm.fileExists(atPath: settingsURL.path) {
            try fm.removeItem(at: settingsURL)
        }
        
        // Restore backup
        try fm.copyItem(at: backupURL, to: settingsURL)
        try fm.removeItem(at: backupURL)
        
        Logger.shared.info("自动接管: 已恢复 \(client.displayName) 原始配置并删除备份")
    }
    
    // ⚠️ 安全注意：此处读取用户真实 Z.AI API Key（明文）。
    // 禁止在任何日志中打印此函数的返回值，禁止将其写入 app.log 或 Console。
    // 该 Key 仅用于写入 Pi 的本地配置文件以实现代理拦截，不离开用户本机。
    private func getZaiAuthKey() -> String? {
        let authURL = NSHomeDirectory() + "/.pi/agent/auth.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authURL)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let zaiDict = json["zai"] as? [String: Any],
              let key = zaiDict["key"] as? String else {
            return nil
        }
        return key
    }
    
    func restoreAll() {
        for client in InterceptClient.allCases {
            if FileManager.default.fileExists(atPath: client.backupURL.path) {
                do {
                    try restoreInterception(for: client)
                } catch {
                    Logger.shared.error("清理时恢复 \(client.displayName) 失败: \(error.localizedDescription)")
                }
            }
        }
    }
}
