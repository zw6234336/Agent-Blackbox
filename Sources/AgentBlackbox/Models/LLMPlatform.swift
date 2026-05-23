import Foundation

/// All LLM platforms that Agent Blackbox can monitor.
enum LLMPlatform: String, CaseIterable, Identifiable, Codable {
    case claude    = "Claude"
    case copilot   = "GitHub Copilot"
    case chatgpt   = "ChatGPT"
    case deepseek  = "DeepSeek"
    case glm       = "ChatGLM"
    case pi        = "Pi"
    case ollama    = "Ollama"
    case gemini    = "Gemini"
    case qwen      = "Qwen"
    case mistral   = "Mistral"
    case custom    = "Custom"

    var id: String { rawValue }

    var displayName: String { rawValue }

    // SF Symbol name used throughout the UI
    var iconName: String {
        switch self {
        case .claude:   return "brain.head.profile"
        case .copilot:  return "chevron.left.forwardslash.chevron.right"
        case .chatgpt:  return "bubble.left.and.bubble.right.fill"
        case .deepseek: return "magnifyingglass.circle.fill"
        case .glm:      return "sparkles"
        case .pi:       return "circle.hexagongrid.fill"
        case .ollama:   return "server.rack"
        case .gemini:   return "star.fill"
        case .qwen:     return "globe.asia.australia.fill"
        case .mistral:  return "wind"
        case .custom:   return "doc.text.fill"
        }
    }

    // Accent color name (resolved in SidebarView)
    var colorName: String {
        switch self {
        case .claude:   return "orange"
        case .copilot:  return "blue"
        case .chatgpt:  return "green"
        case .deepseek: return "indigo"
        case .glm:      return "purple"
        case .pi:       return "pink"
        case .ollama:   return "gray"
        case .gemini:   return "cyan"
        case .qwen:     return "red"
        case .mistral:  return "teal"
        case .custom:   return "secondary"
        }
    }

    /// Default directories that Agent Blackbox watches for each platform.
    var defaultWatchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .claude:
            return [
                "\(home)/Library/Application Support/Claude/logs",
                "\(home)/Library/Application Support/Claude",
                "\(home)/Library/Logs/Claude"
            ]
        case .copilot:
            return [
                "\(home)/Library/Application Support/GitHub Copilot",
                "\(home)/Library/Application Support/Code/logs",
                "\(home)/.config/github-copilot"
            ]
        case .chatgpt:
            return [
                "\(home)/Library/Application Support/ChatGPT",
                "\(home)/Library/Logs/ChatGPT"
            ]
        case .deepseek:
            return [
                "\(home)/Library/Application Support/DeepSeek",
                "\(home)/Library/Logs/DeepSeek",
                "\(home)/.deepseek"
            ]
        case .glm:
            return [
                "\(home)/.chatglm",
                "\(home)/Library/Application Support/ChatGLM",
                "\(home)/Library/Application Support/zhipuai"
            ]
        case .pi:
            return [
                "\(home)/Library/Application Support/Pi",
                "\(home)/Library/Logs/Pi"
            ]
        case .ollama:
            return [
                "\(home)/.ollama/logs",
                "/usr/local/var/log/ollama",
                "\(home)/Library/Logs/Ollama"
            ]
        case .gemini:
            return [
                "\(home)/Library/Application Support/Google/Gemini",
                "\(home)/Library/Logs/Google/Gemini"
            ]
        case .qwen:
            return [
                "\(home)/.qwen",
                "\(home)/Library/Application Support/Qwen",
                "\(home)/Library/Application Support/tongyi"
            ]
        case .mistral:
            return [
                "\(home)/.mistral",
                "\(home)/Library/Application Support/Mistral"
            ]
        case .custom:
            return []
        }
    }

    /// File extensions Agent Blackbox will attempt to parse within watched directories.
    static let watchedExtensions: Set<String> = ["log", "json", "jsonl", "txt", "ndjson"]
}
