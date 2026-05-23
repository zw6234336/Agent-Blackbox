import Foundation
import SQLite

// MARK: - Detected Plan

/// 从本地凭证 / Provider API 自动检测到的套餐信息
struct DetectedPlan: Equatable, Identifiable {
    var id: String { provider.rawValue }
    let provider: LLMProvider
    /// 可读套餐名称，例如 "Copilot Pro"、"Cursor Pro"
    let planName: String
    /// 对应的限额配置（仅含已知字段，其余为 nil）
    let rateLimit: ProviderRateLimit
    /// 数据来源描述，例如 "GitHub API"、"本地凭证"
    let source: String
    let detectedAt: Date
}

// MARK: - Plan Detection Service

/// 从当前电脑上的本地凭证检测各 Provider 的套餐授权
///
/// 检测策略：
///  - GitHub Copilot → 读取 ~/.config/gh/hosts.yml 或 VS Code state.vscdb 中的 OAuth Token
///                     → 调用 GitHub API 获取 Copilot 套餐
///  - Cursor         → 读取 Cursor 的 storage.db 中的 accessToken
///                     → 调用 Cursor API 获取套餐
///  - Claude Desktop → 检查应用是否安装，读取配置判断是 API Key 还是消费套餐
@MainActor
final class PlanDetectionService: ObservableObject {

    @Published private(set) var detectedPlans: [LLMProvider: DetectedPlan] = [:]
    @Published private(set) var isDetecting: Bool = false
    @Published private(set) var lastDetectedAt: Date?
    @Published private(set) var statusMessage: String = ""

    // MARK: - Public API

    func detectAll() async {
        isDetecting = true
        statusMessage = "正在检测本地授权信息..."
        defer { isDetecting = false }

        var results: [LLMProvider: DetectedPlan] = [:]

        async let copilot = detectCopilot()
        async let cursor  = detectCursor()
        async let claude  = detectClaudeDesktop()

        if let plan = await copilot { results[.copilot]       = plan }
        if let plan = await cursor  { results[.cursor]        = plan }
        if let plan = await claude  { results[.claudeDesktop] = plan }

        detectedPlans = results
        lastDetectedAt = Date()

        if results.isEmpty {
            statusMessage = "未找到本地授权信息。请确保已安装并登录 GitHub CLI（gh）、Cursor 或 Claude Desktop，并授予本应用完整磁盘访问权限。"
        } else {
            let names = results.values
                .map { "\($0.provider.displayName): \($0.planName)" }
                .sorted()
                .joined(separator: "，")
            statusMessage = "已检测到 \(results.count) 个套餐：\(names)"
        }
    }

    /// 将检测结果写入配置（只覆盖检测到的 provider，不影响其他 provider 的手动配置）
    func applyToConfig(_ configService: ConfigService) {
        for (provider, plan) in detectedPlans {
            configService.config.providerRateLimits[provider.rawValue] = plan.rateLimit
        }
        configService.save()
    }

    // MARK: - GitHub Copilot

    private func detectCopilot() async -> DetectedPlan? {
        guard let token = readGitHubToken() else { return nil }
        return await fetchCopilotPlan(token: token)
    }

    private func readGitHubToken() -> String? {
        // 方案 1：GitHub CLI — ~/.config/gh/hosts.yml
        let hostsPath = NSHomeDirectory() + "/.config/gh/hosts.yml"
        if let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) {
            var inGitHubSection = false
            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("github.com:") {
                    inGitHubSection = true
                    continue
                }
                // 子项以 2+ 个空格 / tab 开头；否则退出 github.com section
                if inGitHubSection && !line.hasPrefix("  ") && !line.hasPrefix("\t") {
                    inGitHubSection = false
                }
                if inGitHubSection {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("oauth_token:") {
                        let v = String(t.dropFirst("oauth_token:".count)).trimmingCharacters(in: .whitespaces)
                        if !v.isEmpty { return v }
                    }
                }
            }
        }

        // 方案 2：VS Code / Cursor 的 state.vscdb 中 Copilot 扩展存储的 token
        let vscdbPaths = [
            NSHomeDirectory() + "/Library/Application Support/Code/User/globalStorage/state.vscdb",
            NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
        ]
        for path in vscdbPaths {
            if let token = readCopilotTokenFromVSCDB(path: path) { return token }
        }

        return nil
    }

    private func readCopilotTokenFromVSCDB(path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let db     = try Connection(path, readonly: true)
            let table  = Table("ItemTable")
            let keyCol = Expression<String>("key")
            let valCol = Expression<String>("value")
            // GitHub Copilot 扩展将 session token 存储在此 key
            for keyName in ["github.copilot.openai.token", "github.copilot-chat.openaiToken"] {
                guard let row = try? db.pluck(table.filter(keyCol == keyName)) else { continue }
                // 值格式：{"token":"ghu_xxx","expires_at":1234567890,"refresh_in":1200}
                let json = row[valCol]
                if let data = json.data(using: .utf8),
                   let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tok  = obj["token"] as? String {
                    return tok
                }
            }
        } catch {}
        return nil
    }

    private func fetchCopilotPlan(token: String) async -> DetectedPlan? {
        // GitHub 官方端点（需要对应 scope；CLI token 通常有 repo+gist scope）
        let endpoints = [
            "https://api.github.com/user/copilot",
            "https://api.github.com/copilot_internal/user",
        ]

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let planType = obj["plan_type"] as? String ?? ""
            let seatType = obj["seat_type"] as? String ?? ""
            let (planName, monthlyReq) = copilotPlanInfo(planType: planType, seatType: seatType)

            return DetectedPlan(
                provider: .copilot,
                planName: planName,
                rateLimit: ProviderRateLimit(monthlyRequestLimit: monthlyReq),
                source: "GitHub API",
                detectedAt: Date()
            )
        }

        // API 无权限，但本地有凭证 → 按 Pro 默认处理
        return DetectedPlan(
            provider: .copilot,
            planName: "Copilot (已授权)",
            rateLimit: ProviderRateLimit.defaultCopilotPro,
            source: "本地凭证",
            detectedAt: Date()
        )
    }

    private func copilotPlanInfo(planType: String, seatType: String) -> (String, Int?) {
        switch planType {
        case "copilot_pro_plus":  return ("Copilot Pro+", 1_500)
        case "copilot_pro":       return ("Copilot Pro",  300)
        case "copilot_free":      return ("Copilot Free", 50)
        default:
            if seatType.contains("business") || seatType.contains("enterprise") {
                return ("Copilot Business/Enterprise", nil)  // 组织管理，无固定月度上限
            }
            return ("Copilot Pro", 300)
        }
    }

    // MARK: - Cursor

    private func detectCursor() async -> DetectedPlan? {
        guard let token = readCursorToken() else { return nil }
        return await fetchCursorPlan(token: token)
    }

    private func readCursorToken() -> String? {
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/storage.db"
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        do {
            let db     = try Connection(dbPath, readonly: true)
            let table  = Table("ItemTable")
            let keyCol = Expression<String>("key")
            let valCol = Expression<String>("value")
            // Cursor 将 auth token 存储在这两个 key 中（优先 accessToken）
            for keyName in ["cursorAuth/accessToken", "cursorAuth/refreshToken"] {
                if let row = try? db.pluck(table.filter(keyCol == keyName)) {
                    let v = row[valCol].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
        } catch {}
        return nil
    }

    private func readCursorEmail() -> String? {
        let dbPath = NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/storage.db"
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        do {
            let db     = try Connection(dbPath, readonly: true)
            let table  = Table("ItemTable")
            let keyCol = Expression<String>("key")
            let valCol = Expression<String>("value")
            if let row = try? db.pluck(table.filter(keyCol == "cursorAuth/cachedEmail")) {
                return row[valCol].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {}
        return nil
    }

    private func fetchCursorPlan(token: String) async -> DetectedPlan? {
        let endpoints = [
            "https://www.cursor.com/api/auth/me",
            "https://cursor.sh/api/auth/me",
        ]

        for urlStr in endpoints {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let planStr = (obj["plan"]               as? String
                        ?? obj["tier"]               as? String
                        ?? obj["subscriptionType"]   as? String
                        ?? "pro").lowercased()

            let (planName, costLimit) = cursorPlanInfo(plan: planStr)
            return DetectedPlan(
                provider: .cursor,
                planName: planName,
                rateLimit: ProviderRateLimit(monthlyCostLimit: costLimit),
                source: "Cursor API",
                detectedAt: Date()
            )
        }

        // API 无法访问，但本地有登录凭证 → 按 Pro 默认处理
        let email = readCursorEmail()
        let planName = email != nil ? "Cursor Pro (\(email!))" : "Cursor (已授权)"
        return DetectedPlan(
            provider: .cursor,
            planName: planName,
            rateLimit: ProviderRateLimit.defaultCursorPro,
            source: "本地凭证",
            detectedAt: Date()
        )
    }

    private func cursorPlanInfo(plan: String) -> (String, Double?) {
        switch plan {
        case "pro":                        return ("Cursor Pro",      20.0)
        case "pro_plus", "pro+":           return ("Cursor Pro+",     40.0)
        case "ultra":                      return ("Cursor Ultra",   200.0)
        case "free", "hobby", "starter":   return ("Cursor Free",     nil)
        case "business", "team":           return ("Cursor Business", nil)
        default:                           return ("Cursor Pro",      20.0)
        }
    }

    // MARK: - Claude Desktop

    private func detectClaudeDesktop() async -> DetectedPlan? {
        let claudeAppPaths = [
            "/Applications/Claude.app",
            NSHomeDirectory() + "/Applications/Claude.app",
        ]
        guard claudeAppPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }

        // 检查 claude_desktop_config.json 中是否配置了 API Key → 走 API 计费
        let configPath = NSHomeDirectory() + "/Library/Application Support/Claude/claude_desktop_config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let apiKey: String? = obj["apiKey"] as? String
                ?? (obj["anthropic"] as? [String: Any])?["apiKey"] as? String
            if let key = apiKey, key.hasPrefix("sk-ant-") {
                return DetectedPlan(
                    provider: .claudeDesktop,
                    planName: "Claude (API Key 模式)",
                    rateLimit: ProviderRateLimit.defaultAnthropicTier1,
                    source: "Claude Desktop 配置",
                    detectedAt: Date()
                )
            }
        }

        // 应用已安装（消费套餐 Free / Pro，无法区分）→ 按 Pro 处理
        return DetectedPlan(
            provider: .claudeDesktop,
            planName: "Claude Desktop (已安装)",
            rateLimit: ProviderRateLimit.defaultClaudeConsumer,
            source: "本地应用",
            detectedAt: Date()
        )
    }
}
