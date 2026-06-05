import Foundation

// MARK: - Rate Window (借鉴 CodexBar UsageFetcher.RateWindow)

/// 一个限额窗口：从用量 / 限制 计算出的 0–100 百分比 + 重置时刻
struct RateWindow: Identifiable, Hashable, Codable {
    let kind: WindowKind
    /// 0..100 已用百分比
    let usedPercent: Double
    /// 窗口长度（分钟）；nil 表示连续不重置
    let windowMinutes: Int?
    /// 下一次重置的绝对时间
    let resetsAt: Date?
    /// 实际计数 / 限额（用于副标题显示）
    let usedAmount: Double
    let limitAmount: Double
    /// 单位（"req" / "tokens"）
    let unit: String

    var id: String { kind.rawValue }
    var remainingPercent: Double { max(0, 100 - usedPercent) }
    var remainingAmount: Double { max(0, limitAmount - usedAmount) }

    /// 重置倒计时描述（"还剩 2小时14分"）
    var resetDescription: String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "即将重置" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 { return "重置于 \(hours)h\(minutes)m" }
        if minutes > 0 { return "重置于 \(minutes)m\(seconds)s" }
        return "重置于 \(seconds)s"
    }

    /// 状态颜色阈值
    var severity: Severity {
        switch usedPercent {
        case 90...:  return .critical
        case 70..<90: return .warning
        default:      return .normal
        }
    }

    enum Severity { case normal, warning, critical }

    enum WindowKind: String, Codable, CaseIterable {
        case rpm1m          // 每分钟请求数
        case tpm1m          // 每分钟 token 数
        case requests1h     // 1 小时请求
        case tokens1h       // 1 小时 token
        case requests5h     // 5 小时请求（Kimi 等消费套餐）
        case dailyTokens    // 今日 token
        case monthlyRequests // 月度请求数（Copilot Pro 等）

        var displayName: String {
            switch self {
            case .rpm1m:           return "RPM (每分钟请求)"
            case .tpm1m:           return "TPM (每分钟 Token)"
            case .requests1h:      return "1 小时请求"
            case .tokens1h:        return "1 小时 Token"
            case .requests5h:      return "5 小时请求"
            case .dailyTokens:     return "今日 Token"
            case .monthlyRequests: return "月度请求数"
            }
        }
    }
}

// MARK: - Usage Pace (借鉴 CodexBar UsagePace)

/// 用量节奏：判断当前用得太快 / 太慢 / 正常
struct UsagePace: Codable, Hashable {
    /// 当前已用 %
    let actualPercent: Double
    /// 线性期望 %（基于已经过窗口 of the proportion）
    let expectedPercent: Double
    /// 距离窗口结束剩余秒数
    let secondsUntilReset: TimeInterval
    /// 按当前速率，预计耗尽窗口的秒数（nil = 不会耗尽）
    let etaSeconds: TimeInterval?

    var deltaPercent: Double { actualPercent - expectedPercent }
    var willExhaust: Bool {
        guard let etaSeconds else { return false }
        return etaSeconds < secondsUntilReset
    }

    var stage: Stage {
        let d = deltaPercent
        if d <= -12 { return .farBehind }
        if d <= -6  { return .behind }
        if d <= -2  { return .slightlyBehind }
        if d <= 2   { return .onTrack }
        if d <= 6   { return .slightlyAhead }
        if d <= 12  { return .ahead }
        return .farAhead
    }

    enum Stage: String, Codable {
        case farBehind, behind, slightlyBehind, onTrack, slightlyAhead, ahead, farAhead

        var label: String {
            switch self {
            case .farBehind:      return "远低于预期"
            case .behind:         return "低于预期"
            case .slightlyBehind: return "略低于预期"
            case .onTrack:        return "进度正常"
            case .slightlyAhead:  return "略高于预期"
            case .ahead:          return "高于预期"
            case .farAhead:       return "远高于预期"
            }
        }
    }

    /// 计算节奏：给定当前用量、窗口起点、窗口长度
    static func compute(usedPercent: Double, windowStart: Date, windowMinutes: Int, ratePerSecond: Double, now: Date = Date()) -> UsagePace? {
        guard windowMinutes > 0 else { return nil }
        let duration = TimeInterval(windowMinutes) * 60
        let elapsed = max(0, now.timeIntervalSince(windowStart))
        let progress = min(1.0, elapsed / duration)
        let expected = progress * 100.0
        let secondsUntilReset = max(0, duration - elapsed)

        // 按当前每秒速率，剩下的 % 还要多久耗尽
        let remainingPercent = max(0, 100 - usedPercent)
        let eta: TimeInterval? = ratePerSecond > 0 ? (remainingPercent / ratePerSecond) : nil

        return UsagePace(
            actualPercent: usedPercent,
            expectedPercent: expected,
            secondsUntilReset: secondsUntilReset,
            etaSeconds: eta
        )
    }
}

// MARK: - Concurrency Metric

struct ConcurrencyMetric: Codable, Hashable {
    /// 当前正在进行（estimated based on overlapping start+duration）
    let currentInFlight: Int
    /// 最近 1 分钟内的峰值并发
    let peakLastMinute: Int
    /// 最近 1 小时内的峰值并发
    let peakLastHour: Int
    /// 平均响应时间（秒）
    let avgDurationSeconds: Double
}

// MARK: - Provider Usage Snapshot (借鉴 CodexBar UsageSnapshot)

struct ProviderUsageSnapshot: Identifiable, Hashable {
    let provider: LLMProvider
    let windows: [RateWindow]
    let concurrency: ConcurrencyMetric
    let pace: UsagePace?           // 主窗口的节奏
    let totalCalls1h: Int
    let totalTokens1h: Int
    let updatedAt: Date

    var id: String { provider.rawValue }

    /// 取最严重的状态作为整体 badge
    var overallSeverity: RateWindow.Severity {
        let sevs = windows.map { $0.severity }
        if sevs.contains(.critical) { return .critical }
        if sevs.contains(.warning)  { return .warning }
        return .normal
    }
}

// MARK: - Provider Rate Limit Config

/// 用户配置的限额（按 provider 维度；无值表示不限制）
struct ProviderRateLimit: Codable, Hashable {
    /// 每分钟请求数上限
    var rpmLimit: Int? = nil
    /// 每分钟 token 上限（对应 Anthropic ITPM / OpenAI TPM）
    var tpmLimit: Int? = nil
    /// 1 小时请求上限
    var requestsPerHourLimit: Int? = nil
    /// 1 小时 token 上限
    var tokensPerHourLimit: Int? = nil
    /// 今日 token 上限
    var dailyTokenLimit: Int? = nil
    /// 月度请求数上限（适用于 Copilot Pro 等按月请求计费的套餐）
    var monthlyRequestLimit: Int? = nil
    /// 5 小时请求数上限（适用于 Kimi 等消费套餐 of sliding window）
    var fiveHourRequestLimit: Int? = nil

    // MARK: - 官方套餐默认值（基于各厂商公开文档）

    /// OpenAI API Tier 1（$5 充值后）
    /// GPT-4o: RPM 500, TPM 30,000
    static let defaultOpenAITier1 = ProviderRateLimit(
        rpmLimit: 500,
        tpmLimit: 30_000,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// Anthropic Claude API Tier 1
    /// Claude Sonnet 4.x: RPM 50, ITPM 30,000
    static let defaultAnthropicTier1 = ProviderRateLimit(
        rpmLimit: 50,
        tpmLimit: 30_000,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// GitHub Copilot Pro（$10/用户/月）
    /// Pro: 300 premium requests/month；无 RPM/TPM 限制
    static let defaultCopilotPro = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil,
        monthlyRequestLimit: 300
    )

    /// Cursor Pro（$20/月）
    static let defaultCursorPro = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// Claude Desktop / Claude Code 消费套餐
    static let defaultClaudeConsumer = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// Claude Pro (订阅会员) 网页/客户端消费套餐
    /// 5小时50次限制
    static let defaultClaudePro = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil,
        monthlyRequestLimit: nil,
        fiveHourRequestLimit: 50
    )

    /// Z.AI / 智谱 Coding Plan（$3~$15/月）
    /// 参考：https://docs.z.ai/devpack/overview
    /// Lite: 约 120 prompts/5h；Pro/Max 更高
    static let defaultZAICoding = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil,
        monthlyRequestLimit: nil,
        fiveHourRequestLimit: 120
    )

    /// Google Antigravity Preview（当前免费 Beta，无公开配额）
    static let defaultAntigravityPreview = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// 本地模型（Ollama / LM Studio）：理论无限制，仅监控吞吐
    static let defaultLocal = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// Warp AI
    static let defaultWarp = ProviderRateLimit(
        rpmLimit: nil,
        tpmLimit: nil,
        requestsPerHourLimit: nil,
        tokensPerHourLimit: nil,
        dailyTokenLimit: nil
    )

    /// 默认配置表（按 provider，基于各厂商公开套餐政策）
    static func defaults() -> [String: ProviderRateLimit] {
        var dict: [String: ProviderRateLimit] = [:]
        for p in LLMProvider.allCases {
            switch p {

            // ── OpenAI 直接 API / Codex ──────────────────────────────────
            case .openai, .codex:
                dict[p.rawValue] = .defaultOpenAITier1

            // ── GitHub Copilot Pro ──────────────────────────────────────
            case .copilot:
                dict[p.rawValue] = .defaultCopilotPro

            // ── Anthropic Claude API（Cline 直连 API）──────────────────
            case .anthropic, .cline:
                dict[p.rawValue] = .defaultAnthropicTier1

            // ── Claude Desktop / Claude Code 消费套餐 ──────────────────
            case .claudeDesktop:
                dict[p.rawValue] = .defaultClaudeConsumer

            // ── Cursor ─────────────────────────────────────────────────
            case .cursor:
                dict[p.rawValue] = .defaultCursorPro

            // ── DeepSeek API ───────────────────────────────────────────
            case .deepseek:
                dict[p.rawValue] = ProviderRateLimit(
                    rpmLimit: 60,
                    tpmLimit: nil,
                    requestsPerHourLimit: nil,
                    tokensPerHourLimit: nil,
                    dailyTokenLimit: nil
                )

            // ── 通义千问 Qwen API ──────────────────────────────────────
            case .qwen:
                dict[p.rawValue] = ProviderRateLimit(
                    rpmLimit: 120,
                    tpmLimit: 180_000,
                    requestsPerHourLimit: nil,
                    tokensPerHourLimit: nil,
                    dailyTokenLimit: nil
                )

            // ── Kimi（月之暗面消费套餐）────────────────────────────────
            case .kimi:
                dict[p.rawValue] = ProviderRateLimit(
                    rpmLimit: nil,
                    tpmLimit: nil,
                    requestsPerHourLimit: nil,
                    tokensPerHourLimit: nil,
                    dailyTokenLimit: nil,
                    monthlyRequestLimit: nil,
                    fiveHourRequestLimit: 50
                )

            // ── 智谱清言 GLM API ───────────────────────────────────────
            case .zhipu:
                dict[p.rawValue] = ProviderRateLimit(
                    rpmLimit: 200,
                    tpmLimit: 200_000,
                    requestsPerHourLimit: nil,
                    tokensPerHourLimit: nil,
                    dailyTokenLimit: nil
                )

            // ── Google Gemini API ──────────────────────────────────────
            case .google:
                dict[p.rawValue] = ProviderRateLimit(
                    rpmLimit: 15,
                    tpmLimit: 1_000_000,
                    requestsPerHourLimit: nil,
                    tokensPerHourLimit: nil,
                    dailyTokenLimit: nil
                )

            // ── Warp ───────────────────────────────────────────────────
            case .warp:
                dict[p.rawValue] = .defaultWarp

            // ── 本地模型（无外部限额）─────────────────────────────────
            case .ollama, .lmstudio:
                dict[p.rawValue] = .defaultLocal

            // ── 其余 provider（无已知配额，仅监控用量）────────────────
            default:
                dict[p.rawValue] = ProviderRateLimit()
            }
        }
        return dict
    }
}
