import SwiftUI

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case google
    case warp
    case ollama
    case cursor
    case copilot
    case claudeDesktop = "claude_desktop"
    case cline
    case lmstudio
    case continuedev
    case deepseek
    case qwen
    case kimi
    case zhipu
    case amp
    case antigravity
    case pi
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .warp: return "Warp"
        case .ollama: return "Ollama"
        case .cursor: return "Cursor"
        case .copilot: return "GitHub Copilot"
        case .claudeDesktop: return "Claude Desktop"
        case .cline: return "Cline"
        case .lmstudio: return "LM Studio"
        case .continuedev: return "Continue.dev"
        case .deepseek: return "DeepSeek"
        case .qwen: return "通义千问 Qwen"
        case .kimi: return "月之暗面 Kimi"
        case .zhipu: return "智谱清言 GLM"
        case .amp: return "Amp (Sourcegraph)"
        case .antigravity: return "Antigravity (Google)"
        case .pi: return "Pi (Inflection)"
        case .custom: return "自定义"
        }
    }
    
    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .anthropic: return "sparkle"
        case .google: return "globe"
        case .warp: return "terminal.fill"
        case .ollama: return "desktopcomputer"
        case .cursor: return "cursorarrow.rays"
        case .copilot: return "robot"
        case .claudeDesktop: return "bubble.left.fill"
        case .cline: return "terminal"
        case .lmstudio: return "cpu"
        case .continuedev: return "arrow.right.circle"
        case .deepseek: return "sparkles"
        case .qwen: return "aqi.medium"
        case .kimi: return "moon.fill"
        case .zhipu: return "network"
        case .amp: return "bolt.shield.fill"
        case .antigravity: return "arrow.up.circle.fill"
        case .pi: return "heart.circle"
        case .custom: return "gearshape"
        }
    }
    
    var brandColor: Color {
        switch self {
        case .openai: return Color(hue: 0.47, saturation: 0.85, brightness: 0.65)
        case .anthropic: return Color(hue: 0.08, saturation: 0.75, brightness: 0.85)
        case .google: return Color(hue: 0.6, saturation: 0.7, brightness: 0.8)
        case .warp: return Color(hue: 0.12, saturation: 0.85, brightness: 0.92)
        case .ollama: return Color(hue: 0.0, saturation: 0.0, brightness: 0.45)
        case .cursor: return Color(hue: 0.75, saturation: 0.6, brightness: 0.9)
        case .copilot: return Color(hue: 0.55, saturation: 0.6, brightness: 0.7)
        case .claudeDesktop: return Color(hue: 0.08, saturation: 0.75, brightness: 0.85)
        case .cline: return Color(hue: 0.35, saturation: 0.7, brightness: 0.7)
        case .lmstudio: return Color(hue: 0.85, saturation: 0.6, brightness: 0.8)
        case .continuedev: return Color(hue: 0.95, saturation: 0.7, brightness: 0.85)
        case .deepseek: return Color(hue: 0.6, saturation: 0.85, brightness: 0.9)
        case .qwen: return Color(hue: 0.72, saturation: 0.7, brightness: 0.8)
        case .kimi: return Color(hue: 0.05, saturation: 0.8, brightness: 0.85)
        case .zhipu: return Color(hue: 0.55, saturation: 0.8, brightness: 0.7)
        case .amp: return Color(hue: 0.85, saturation: 0.85, brightness: 0.85)
        case .antigravity: return Color(hue: 0.58, saturation: 0.9, brightness: 0.85)
        case .pi: return Color(hue: 0.02, saturation: 0.85, brightness: 0.75)
        case .custom: return Color(hue: 0.0, saturation: 0.0, brightness: 0.6)
        }
    }
    
    /// Known log paths on macOS for this provider
    var defaultLogPaths: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .openai:
            return [
                home + "/Library/Application Support/com.openai.chat/",
                home + "/Library/Group Containers/group.com.openai.chat/"
            ]
        case .anthropic:
            return [
                home + "/Library/Logs/Claude/",
                home + "/Library/Application Support/Claude/"
            ]
        case .google:
            return [
                home + "/.config/gcloud/logs/"
            ]
        case .warp:
            return [
                home + "/Library/Application Support/dev.warp.Warp-Stable/",
                home + "/Library/Logs/warp.log",
                home + "/.warp/"
            ]
        case .cursor:
            return [
                home + "/Library/Application Support/Cursor/User/workspaceStorage/",
                home + "/Library/Application Support/Cursor/User/globalStorage/",
                home + "/Library/Application Support/Cursor/logs/"
            ]
        case .claudeDesktop:
            return [
                home + "/Library/Logs/Claude/",
                home + "/Library/Application Support/Claude/"
            ]
        case .ollama:
            return [home + "/.ollama/logs/"]
        case .copilot:
            return [
                // chatSessions: .json（旧格式）和 .jsonl（新格式，含 modelId/耗时）
                home + "/Library/Application Support/Code/User/workspaceStorage/",
                // Cursor 中的 Copilot 会话
                home + "/Library/Application Support/Cursor/User/workspaceStorage/",
                // VS Code 全局 Copilot 存储（session-store.db 等）
                home + "/Library/Application Support/Code/User/globalStorage/github.copilot-chat/",
                // Copilot for Xcode
                home + "/Library/Logs/CopilotForXcode/",
                home + "/Library/Application Support/CopilotForXcode/"
            ]
        case .cline:
            return [
                home + "/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks/",
                home + "/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks/"
            ]
        case .lmstudio:
            return [
                home + "/.lmstudio/",
                home + "/.cache/lm-studio/"
            ]
        case .continuedev:
            return [
                home + "/.continue/logs/",
                home + "/.continue/sessions/",
                home + "/.continue/"
            ]
        case .amp:
            return [
                home + "/.local/share/amp/threads/",
                home + "/.local/share/amp/",
                home + "/.cache/amp/logs/"
            ]
        case .antigravity:
            return [
                home + "/.gemini/antigravity/brain/",
                home + "/Library/Logs/Antigravity/",
                home + "/Library/Application Support/Antigravity/logs/",
                home + "/Library/Application Support/Antigravity IDE/logs/"
            ]
        case .pi:
            return [
                // Pi API 日志
                home + "/.pi/logs/",
                home + "/.pi/",
                // 导出的对话记录
                home + "/Library/Application Support/Pi/",
                // Pi Desktop (如果存在)
                home + "/Library/Application Support/com.inflection.pi/",
                home + "/Library/Logs/Pi/"
            ]
        default:
            return []
        }
    }
}
