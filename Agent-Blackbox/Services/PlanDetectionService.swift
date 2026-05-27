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
///                     → 调用 /copilot_internal/v2/token 解析 SKU 字段获取套餐
///                     → 回退到 /copilot_internal/user 获取 plan_type
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

        async let copilot     = detectCopilot()
        async let cursor      = detectCursor()
        async let claudeApp   = detectClaudeDesktop()
        async let claudeCode  = detectClaudeCodeOrZAI()
        async let antigravity = detectAntigravity()
        async let zaiPi       = detectZAIViaPi()

        if let plan = await copilot     { results[.copilot]       = plan }
        if let plan = await cursor      { results[.cursor]        = plan }
        if let plan = await claudeApp   { results[.claudeDesktop] = plan }
        // claude-code 可能配的是真 Claude 也可能是 Z.AI，按检测出的 provider 入表
        if let plan = await claudeCode  { results[plan.provider]  = plan }
        if let plan = await antigravity { results[.antigravity]   = plan }
        // Pi 配置里的 Z.AI key 优先级最高（如果两边都有，覆盖 claude-code 的检测）
        if let plan = await zaiPi       { results[.zhipu]         = plan }

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
        // 优先读 VS Code/Cursor 的 Copilot token（含 copilot scope）
        // 其次读 gh CLI token（通常无 copilot scope）
        let tokens = readAllCopilotTokens()

        guard !tokens.isEmpty else {
            Logger.shared.info("Copilot 检测: 未找到任何 GitHub/Copilot token")
            return nil
        }

        // 策略 1: 用 Copilot token 调用 /copilot_internal/v2/token 解析 SKU
        for token in tokens {
            if let plan = await detectViaCopilotTokenAPI(token) {
                return plan
            }
        }

        // 策略 2: 用任意 token 调用 /copilot_internal/user
        for token in tokens {
            if let plan = await detectViaCopilotUserAPI(token) {
                return plan
            }
        }

        // 策略 3: 用 gh CLI token 调用 /user 获取 GitHub plan + Copilot 扩展判断
        if let ghToken = readGHCLIToken() {
            if let plan = await detectViaGitHubUserAPI(ghToken) {
                return plan
            }
        }

        // 最终回退：有 token 但 API 全部失败 → 仅标记"已授权"，不臆测套餐档位
        // 旧版本会默认回退到 Copilot Pro 并写入 300 次/月配额，这是错的：
        // 用户可能是 Free / Business / Enterprise，硬塞 Pro 会污染速率限制。
        Logger.shared.info("Copilot 检测: API 均失败，仅标记已授权（不假定套餐档位）")
        return DetectedPlan(
            provider: .copilot,
            planName: "Copilot (已授权，套餐档位未知)",
            rateLimit: ProviderRateLimit(), // 全 nil，避免污染配额
            source: "本地凭证（API 未响应）",
            detectedAt: Date()
        )
    }

    // MARK: Token 读取

    /// 读取所有可用的 Copilot 相关 token
    private func readAllCopilotTokens() -> [String] {
        var tokens: [String] = []

        // 1. VS Code / Cursor state.vscdb 中的 Copilot token（最可靠）
        let vscdbPaths = [
            NSHomeDirectory() + "/Library/Application Support/Code/User/globalStorage/state.vscdb",
            NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
        ]
        for path in vscdbPaths {
            if let token = readCopilotTokenFromVSCDB(path: path) {
                Logger.shared.info("Copilot 检测: 从 vscdb 读取到 token (prefix: \(token.prefix(4))...)")
                tokens.append(token)
            }
        }

        // 2. gh CLI token（可能无 copilot scope，但可尝试）
        if let ghToken = readGHCLIToken() {
            Logger.shared.info("Copilot 检测: 从 gh CLI 读取到 token (prefix: \(ghToken.prefix(4))...)")
            tokens.append(ghToken)
        }

        return tokens
    }

    /// 从 ~/.config/gh/hosts.yml 读取 gh CLI OAuth token
    private func readGHCLIToken() -> String? {
        let hostsPath = NSHomeDirectory() + "/.config/gh/hosts.yml"
        guard let content = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return nil }

        var inGitHubSection = false
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("github.com:") {
                inGitHubSection = true
                continue
            }
            if inGitHubSection && !line.hasPrefix("  ") && !line.hasPrefix("\t") && !line.isEmpty {
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
        return nil
    }

    /// 从 VS Code/Cursor 的 state.vscdb 读取 Copilot token
    private func readCopilotTokenFromVSCDB(path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let db     = try Connection(path, readonly: true)
            let table  = Table("ItemTable")
            let keyCol = Expression<String>("key")
            let valCol = Expression<String>("value")

            // 新旧版本的 key 名称都尝试
            let keyNames = [
                "github.copilot.openai.token",
                "github.copilot-chat.openaiToken",
                "github.copilot.token",
                "github.copilot-chat.token",
                "github.copilot.gh-token",
            ]

            for keyName in keyNames {
                guard let row = try? db.pluck(table.filter(keyCol == keyName)) else { continue }
                let json = row[valCol]
                // 格式1: JSON {"token":"ghu_xxx","expires_at":...,"refresh_in":...}
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tok = obj["token"] as? String, !tok.isEmpty {
                    return tok
                }
                // 格式2: 纯 token 字符串
                let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("ghu_") || trimmed.hasPrefix("gho_") || trimmed.hasPrefix("ghp_") {
                    return trimmed
                }
            }
        } catch {
            Logger.shared.info("Copilot 检测: 读取 vscdb 失败: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: 策略 1: /copilot_internal/v2/token

    /// 调用 Copilot 内部 token API，解析 SKU 字段获取套餐类型
    private func detectViaCopilotTokenAPI(_ token: String) async -> DetectedPlan? {
        guard let url = URL(string: "https://api.github.com/copilot_internal/v2/token") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else {
            Logger.shared.info("Copilot 检测: /copilot_internal/v2/token 请求失败")
            return nil
        }

        guard http.statusCode == 200 else {
            Logger.shared.info("Copilot 检测: /copilot_internal/v2/token 返回 \(http.statusCode)")
            return nil
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.shared.info("Copilot 检测: /copilot_internal/v2/token 响应非 JSON")
            return nil
        }

        // 方式 A: 解析 token 字符串中的 sku= 字段
        // token 格式: "tid=xxx;exp=1234567890;sku=copilot_pro;..."
        if let tokenStr = obj["token"] as? String {
            if let plan = parseSKUFromToken(tokenStr) {
                Logger.shared.info("Copilot 检测: 从 SKU 解析到套餐 \(plan.planName)")
                return plan
            }
        }

        // 方式 B: 响应中可能有直接的 plan 相关字段
        if let planType = obj["plan_type"] as? String ?? obj["sku"] as? String {
            let (planName, monthlyReq) = copilotPlanInfo(planType: planType, seatType: obj["seat_type"] as? String ?? "")
            Logger.shared.info("Copilot 检测: 从 API 字段解析到套餐 \(planName)")
            return DetectedPlan(
                provider: .copilot,
                planName: planName,
                rateLimit: copilotRateLimit(planName: planName, monthlyReq: monthlyReq),
                source: "GitHub API (token)",
                detectedAt: Date()
            )
        }

        Logger.shared.info("Copilot 检测: /copilot_internal/v2/token 响应中无套餐信息")
        return nil
    }

    /// 从 Copilot token 字符串解析 SKU
    private func parseSKUFromToken(_ tokenStr: String) -> DetectedPlan? {
        // token 格式: "tid=xxx;exp=1234567890;sku=copilot_pro;ct=copilot_chat"
        let parts = tokenStr.components(separatedBy: ";")
        var sku: String?
        for part in parts {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2 && kv[0].trimmingCharacters(in: .whitespaces) == "sku" {
                sku = kv[1].trimmingCharacters(in: .whitespaces)
            }
        }

        guard let sku else { return nil }

        let (planName, monthlyReq) = copilotPlanInfo(planType: sku, seatType: "")
        return DetectedPlan(
            provider: .copilot,
            planName: planName,
            rateLimit: copilotRateLimit(planName: planName, monthlyReq: monthlyReq),
            source: "GitHub API (SKU)",
            detectedAt: Date()
        )
    }

    // MARK: 策略 2: /copilot_internal/user

    /// 调用 Copilot 内部用户 API
    private func detectViaCopilotUserAPI(_ token: String) async -> DetectedPlan? {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.shared.info("Copilot 检测: /copilot_internal/user 失败")
            return nil
        }

        let planType = obj["plan_type"] as? String ?? ""
        let seatType = obj["seat_type"] as? String ?? ""

        guard !planType.isEmpty else {
            Logger.shared.info("Copilot 检测: /copilot_internal/user 返回空 plan_type")
            return nil
        }

        let (planName, monthlyReq) = copilotPlanInfo(planType: planType, seatType: seatType)
        Logger.shared.info("Copilot 检测: /copilot_internal/user 解析到套餐 \(planName)")
        return DetectedPlan(
            provider: .copilot,
            planName: planName,
            rateLimit: copilotRateLimit(planName: planName, monthlyReq: monthlyReq),
            source: "GitHub API (user)",
            detectedAt: Date()
        )
    }

    // MARK: 策略 3: /user (GitHub plan)

    /// 用 gh CLI token 调用标准 GitHub API，结合 Copilot 扩展存在性推断
    private func detectViaGitHubUserAPI(_ token: String) async -> DetectedPlan? {
        guard let url = URL(string: "https://api.github.com/user") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // /user 返回的是 GitHub 账户的 plan，不是 Copilot 的
        // 但结合 Copilot 扩展存在性可以推断
        let login = obj["login"] as? String ?? "unknown"
        let githubPlan = (obj["plan"] as? [String: Any])?["name"] as? String ?? "free"

        // 如果有 Copilot 扩展 token 存在（在 vscdb 中），说明已激活 Copilot
        let hasCopilotExtension = FileManager.default.fileExists(
            atPath: NSHomeDirectory() + "/Library/Application Support/Code/User/globalStorage/state.vscdb"
        ) || FileManager.default.fileExists(
            atPath: NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )

        if hasCopilotExtension {
            // 有扩展 → 至少是 Free 级别，按 Pro 估算（无法精确区分 Free/Pro/Business）
            Logger.shared.info("Copilot 检测: GitHub 用户 \(Self.maskString(login))，plan=\(githubPlan)，检测到 Copilot 扩展")
            return DetectedPlan(
                provider: .copilot,
                planName: "Copilot (已激活)",
                rateLimit: ProviderRateLimit.defaultCopilotPro,
                source: "GitHub API + 本地扩展",
                detectedAt: Date()
            )
        }

        Logger.shared.info("Copilot 检测: GitHub 用户 \(Self.maskString(login))，plan=\(githubPlan)，无 Copilot 扩展")
        return nil
    }

    // MARK: Copilot 套餐映射

    /// 根据 GitHub API 返回的 plan_type 和 seat_type 映射到套餐名和月度请求数
    ///
    /// 参考: https://docs.github.com/en/copilot/concepts/billing/copilot-requests
    /// - Free: 50 premium requests/month
    /// - Pro:  300 premium requests/month
    /// - Pro+: 1,500 premium requests/month
    /// - Business: 300/user/month
    /// - Enterprise: 1,000/user/month
    private func copilotPlanInfo(planType: String, seatType: String) -> (String, Int?) {
        let pt = planType.lowercased()
        let st = seatType.lowercased()

        switch pt {
        case "copilot_pro_plus", "copilot_pro+", "pro_plus", "pro+":
            return ("Copilot Pro+", 1_500)
        case "copilot_pro", "pro":
            return ("Copilot Pro", 300)
        case "copilot_free", "free":
            return ("Copilot Free", 50)
        case "copilot_business", "business":
            return ("Copilot Business", 300)
        case "copilot_enterprise", "enterprise":
            return ("Copilot Enterprise", 1_000)
        default:
            if st.contains("business") {
                return ("Copilot Business", 300)
            }
            if st.contains("enterprise") {
                return ("Copilot Enterprise", 1_000)
            }
            return ("Copilot Pro", 300)
        }
    }

    /// 创建 Copilot 对应的完整 ProviderRateLimit
    private func copilotRateLimit(planName: String, monthlyReq: Int?) -> ProviderRateLimit {
        var limit = ProviderRateLimit.defaultCopilotPro
        limit.monthlyRequestLimit = monthlyReq
        return limit
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

            let planName = cursorPlanInfo(plan: planStr)
            return DetectedPlan(
                provider: .cursor,
                planName: planName,
                rateLimit: ProviderRateLimit.defaultCursorPro,
                source: "Cursor API",
                detectedAt: Date()
            )
        }

        let email = readCursorEmail()
        let planName = email != nil ? "Cursor Pro (\(Self.maskEmail(email!)))" : "Cursor (已授权)"
        return DetectedPlan(
            provider: .cursor,
            planName: planName,
            rateLimit: ProviderRateLimit.defaultCursorPro,
            source: "本地凭证",
            detectedAt: Date()
        )
    }

    private func cursorPlanInfo(plan: String) -> String {
        switch plan {
        case "pro":                        return "Cursor Pro"
        case "pro_plus", "pro+":           return "Cursor Pro+"
        case "ultra":                      return "Cursor Ultra"
        case "free", "hobby", "starter":   return "Cursor Free"
        case "business", "team":           return "Cursor Business"
        default:                           return "Cursor Pro"
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

        return DetectedPlan(
            provider: .claudeDesktop,
            planName: "Claude Desktop (已安装)",
            rateLimit: ProviderRateLimit.defaultClaudeConsumer,
            source: "本地应用",
            detectedAt: Date()
        )
    }

    // MARK: - Claude Code (智能识别后端真正的 Provider)

    /// 读 ~/.claude/settings.json 的 env 配置，根据 token 格式 / baseURL / model 名
    /// 判断 Claude Code 当前实际接的是哪个后端：
    /// - sk-ant-* + 官方 base URL → 真 Anthropic API
    /// - sk-ant-* + 无 base URL（或默认）→ 真 Anthropic API
    /// - <32hex>.<16字符> 格式 → Z.AI (智谱) API key
    /// - base URL 含 bigmodel.cn / z.ai → Z.AI
    /// - 默认模型含 glm- → Z.AI（即使 token 格式无法判断）
    /// - 本地 127.0.0.1 + glm-* 模型 → Z.AI 经本地代理
    /// - 都不匹配但 token 非空 → Anthropic 订阅会员（最后回退）
    private func detectClaudeCodeOrZAI() async -> DetectedPlan? {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        guard FileManager.default.fileExists(atPath: settingsPath) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        } catch {
            Logger.shared.info("Claude Code 检测: 读取 settings.json 失败: \(error.localizedDescription)")
            return nil
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = obj["env"] as? [String: Any],
              let token = env["ANTHROPIC_AUTH_TOKEN"] as? String, !token.isEmpty
        else { return nil }

        let baseURL = (env["ANTHROPIC_BASE_URL"] as? String ?? "").lowercased()
        let modelHints: [String] = [
            (env["ANTHROPIC_DEFAULT_HAIKU_MODEL"]  as? String) ?? "",
            (env["ANTHROPIC_DEFAULT_SONNET_MODEL"] as? String) ?? "",
            (env["ANTHROPIC_DEFAULT_OPUS_MODEL"]   as? String) ?? "",
            (env["ANTHROPIC_MODEL"]                as? String) ?? "",
            (obj["model"]                          as? String) ?? "",
        ].map { $0.lowercased() }
        let anyModelGLM  = modelHints.contains { $0.contains("glm") || $0.contains("chatglm") || $0.contains("zhipu") }
        let baseIsZAI    = baseURL.contains("bigmodel.cn") || baseURL.contains("z.ai")
        let baseIsLocal  = baseURL.contains("127.0.0.1") || baseURL.contains("localhost")
        let baseIsAnthropic = baseURL.isEmpty || baseURL.contains("anthropic.com")
        let tokenLooksLikeZAI = isZAIKeyFormat(token)
        let tokenLooksLikeAnthropicAPI = token.hasPrefix("sk-ant-")

        // 判定为 Z.AI 的条件（任一即可）
        if baseIsZAI || anyModelGLM || tokenLooksLikeZAI {
            Logger.shared.info("Claude Code 检测: 实际后端为 Z.AI (baseURL=\(Self.sanitizeURL(baseURL)), models=\(modelHints), zaiKey=\(tokenLooksLikeZAI))")
            return DetectedPlan(
                provider: .zhipu,
                planName: "Z.AI Coding Plan (经 Claude Code)",
                rateLimit: ProviderRateLimit.defaultZAICoding,
                source: baseIsLocal ? "Claude Code → 本地代理 → Z.AI" : "Claude Code → Z.AI",
                detectedAt: Date()
            )
        }

        // 判定为真 Anthropic API
        if tokenLooksLikeAnthropicAPI && baseIsAnthropic {
            return DetectedPlan(
                provider: .anthropic,
                planName: "Claude Code (Anthropic API Key)",
                rateLimit: ProviderRateLimit.defaultAnthropicTier1,
                source: "Claude Code 配置",
                detectedAt: Date()
            )
        }

        // 真 Anthropic API + 非默认 URL（自建代理）
        if tokenLooksLikeAnthropicAPI {
            return DetectedPlan(
                provider: .anthropic,
                planName: "Claude Code (API Key, 经代理: \(Self.sanitizeURL(baseURL)))",
                rateLimit: ProviderRateLimit.defaultAnthropicTier1,
                source: "Claude Code 配置",
                detectedAt: Date()
            )
        }

        // Anthropic 订阅会员（OAuth session token）：只有在排除 Z.AI 后才能这样断言
        if baseIsAnthropic {
            return DetectedPlan(
                provider: .anthropic,
                planName: "Claude Pro/Max (订阅会员)",
                rateLimit: ProviderRateLimit.defaultClaudePro,
                source: "Claude Code 凭证",
                detectedAt: Date()
            )
        }

        // 既不像 Z.AI 也不像 Anthropic、又是非官方 base URL → 标为"未知后端"，不臆测配额
        Logger.shared.info("Claude Code 检测: 无法识别后端 (baseURL=\(Self.sanitizeURL(baseURL)))，标为未知")
        return DetectedPlan(
            provider: .custom,
            planName: "Claude Code (未知后端: \(Self.sanitizeURL(baseURL)))",
            rateLimit: ProviderRateLimit(),
            source: "Claude Code 配置",
            detectedAt: Date()
        )
    }

    /// 检查字符串是否符合 Z.AI API key 格式：32 位 hex + "." + 16 位字母数字
    /// 例如：00000000111111112222222233333333.AbCdEfGh12345678
    private func isZAIKeyFormat(_ s: String) -> Bool {
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let head = String(parts[0])
        let tail = String(parts[1])
        guard head.count == 32, tail.count == 16 else { return false }
        let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let alnumSet = CharacterSet.alphanumerics
        return head.unicodeScalars.allSatisfy(hexSet.contains)
            && tail.unicodeScalars.allSatisfy(alnumSet.contains)
    }

    // MARK: - Google Antigravity

    /// 读 ~/.antigravity_cockpit/credentials.json
    /// 里面是 Google OAuth Token，accounts.<email>.{accessToken,refreshToken,projectId}
    private func detectAntigravity() async -> DetectedPlan? {
        let credPath = NSHomeDirectory() + "/.antigravity_cockpit/credentials.json"
        guard FileManager.default.fileExists(atPath: credPath) else { return nil }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: credPath)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = obj["accounts"] as? [String: Any],
              let (email, accountObj) = accounts.first,
              let account = accountObj as? [String: Any]
        else {
            Logger.shared.info("Antigravity 检测: credentials.json 存在但格式不识别")
            return nil
        }

        let hasAccessToken = (account["accessToken"] as? String)?.isEmpty == false
        guard hasAccessToken else { return nil }

        let projectId = account["projectId"] as? String ?? ""
        let maskedEmail = Self.maskEmail(email)
        let displayName = projectId.isEmpty
            ? "Antigravity Preview (\(maskedEmail))"
            : "Antigravity Preview (\(maskedEmail) / \(projectId))"

        Logger.shared.info("Antigravity 检测: \(maskedEmail) 已登录")
        return DetectedPlan(
            provider: .antigravity,
            planName: displayName,
            rateLimit: ProviderRateLimit.defaultAntigravityPreview,
            source: "Antigravity Cockpit 凭证",
            detectedAt: Date()
        )
    }

    // MARK: - Z.AI via Pi config

    /// Pi Agent 在 ~/.pi/agent/auth.json 里也可能存了 Z.AI key
    /// 与 detectClaudeCodeOrZAI 互补：用户可能只在 Pi 配置 Z.AI 而没在 Claude Code 配
    private func detectZAIViaPi() async -> DetectedPlan? {
        let authPath = NSHomeDirectory() + "/.pi/agent/auth.json"
        guard FileManager.default.fileExists(atPath: authPath) else { return nil }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: authPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let zai = json["zai"] as? [String: Any],
              let key = zai["key"] as? String, !key.isEmpty
        else { return nil }

        Logger.shared.info("Z.AI 检测: 在 Pi 配置中找到 key (prefix=\(key.prefix(4))...)")
        return DetectedPlan(
            provider: .zhipu,
            planName: "Z.AI Coding Plan (经 Pi)",
            rateLimit: ProviderRateLimit.defaultZAICoding,
            source: "Pi Agent 配置",
            detectedAt: Date()
        )
    }

    // MARK: - 脱敏工具方法

    /// 邮箱脱敏：user@domain.com → u***@domain.com
    private static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return "***" }
        let local = parts[0]
        let domain = parts[1]
        if local.count <= 1 {
            return "*@\(domain)"
        }
        return "\(local.prefix(1))***@\(domain)"
    }

    /// 通用字符串脱敏：保留首尾各 1 字符，中间用 ***
    private static func maskString(_ s: String) -> String {
        guard s.count > 2 else { return "***" }
        return "\(s.prefix(1))***\(s.suffix(1))"
    }

    /// URL 脱敏：移除 userinfo（user:password@）部分
    static func sanitizeURL(_ urlStr: String) -> String {
        guard var components = URLComponents(string: urlStr) else { return urlStr }
        if components.user != nil || components.password != nil {
            components.user = nil
            components.password = nil
            return components.string ?? urlStr
        }
        return urlStr
    }
}
