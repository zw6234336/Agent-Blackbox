import Foundation
import Combine

/// 基于本地 ParsedLog 自计算滑动窗口的速率/配额/并发追踪器
@MainActor
final class RateLimitTrackerService: ObservableObject {
    @Published private(set) var snapshots: [ProviderUsageSnapshot] = []
    @Published private(set) var globalSnapshot: ProviderUsageSnapshot?
    @Published private(set) var updatedAt: Date = .distantPast

    private weak var database: DatabaseService?
    private weak var config: ConfigService?
    private var timer: Timer?

    // Cache to prevent CPU/database overhead when idle
    private var lastLogCount = -1
    private var lastRefreshDay = -1
    private var cachedActiveProviders: [LLMProvider] = []
    private var cachedLogs1h: [String: [ParsedLog]] = [:]
    private var cachedLogs5h: [String: [ParsedLog]] = [:]
    private var cachedDailyAgg: [String: DatabaseService.UsageAggregate] = [:]
    private var cachedMonthlyAgg: [String: DatabaseService.UsageAggregate] = [:]

    func bind(database: DatabaseService, config: ConfigService) {
        self.database = database
        self.config = config
    }

    func start() {
        stop()
        Task { @MainActor in
            await refresh()
        }
        let interval = config?.config.rateSamplingInterval ?? 5.0
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Refresh

    func refresh() async {
        guard let database, let config else { return }
        let now = Date()
        let limits = config.config.providerRateLimits

        let currentTotalCount = database.totalLogCount
        let currentDay = Calendar.current.component(.day, from: now)
        let dayOrCountChanged = (currentTotalCount != lastLogCount) || (currentDay != lastRefreshDay)

        // 仅显示出现过日志的 provider（避免 15 个空卡片）
        let activeProviders: [LLMProvider]
        if dayOrCountChanged {
            activeProviders = await database.fetchDistinctProviders()
            cachedActiveProviders = activeProviders
        } else {
            activeProviders = cachedActiveProviders
        }

        var newSnapshots: [ProviderUsageSnapshot] = []
        for provider in activeProviders {
            let limit = limits[provider.rawValue] ?? ProviderRateLimit.defaultLocal
            let snap = await computeSnapshot(provider: provider, limit: limit, now: now, database: database, dayOrCountChanged: dayOrCountChanged)
            newSnapshots.append(snap)
        }
        // 按 24h 调用量倒序
        newSnapshots.sort { $0.totalCalls1h > $1.totalCalls1h }

        // 全局汇总（不区分 provider，用合并后的最大 limit 总和）
        let aggregateLimit = aggregateGlobalLimit(from: limits, activeProviders: activeProviders)
        let global = await computeSnapshot(provider: nil, limit: aggregateLimit, now: now, database: database, dayOrCountChanged: dayOrCountChanged)

        snapshots = newSnapshots
        globalSnapshot = global
        updatedAt = now
        lastLogCount = currentTotalCount
        lastRefreshDay = currentDay
    }

    // MARK: - Snapshot Computation

    private func computeSnapshot(
        provider: LLMProvider?,
        limit: ProviderRateLimit,
        now: Date,
        database: DatabaseService,
        dayOrCountChanged: Bool
    ) async -> ProviderUsageSnapshot {
        let key = provider?.rawValue ?? "global"
        
        // 滑动窗口时间点
        let oneMinAgo  = now.addingTimeInterval(-60)
        let oneHourAgo = now.addingTimeInterval(-3600)
        let dayStart   = Calendar.current.startOfDay(for: now)
        let monthStart = startOfMonth(now)

        let logs1h: [ParsedLog]
        let dayAgg: DatabaseService.UsageAggregate
        let monthAgg: DatabaseService.UsageAggregate

        if !dayOrCountChanged,
           let prevLogs1h = cachedLogs1h[key],
           let prevDaily = cachedDailyAgg[key],
           let prevMonthly = cachedMonthlyAgg[key] {
            // In-memory filter of existing logs
            logs1h = prevLogs1h.filter { $0.timestamp >= oneHourAgo }
            dayAgg = prevDaily
            monthAgg = prevMonthly
        } else {
            // Pull from DB
            logs1h = await database.fetchLogs(provider: provider, since: oneHourAgo, until: now)
            dayAgg = await database.aggregateUsage(provider: provider, since: dayStart, until: now)
            monthAgg = await database.aggregateUsage(provider: provider, since: monthStart, until: now)
            
            cachedLogs1h[key] = logs1h
            cachedDailyAgg[key] = dayAgg
            cachedMonthlyAgg[key] = monthAgg
        }

        let logs1m = logs1h.filter { $0.timestamp >= oneMinAgo }

        // 1分钟聚合
        let req1m = logs1m.count
        let tok1m = logs1m.reduce(0) { $0 + ($1.totalTokens ?? (($1.promptTokens ?? 0) + ($1.completionTokens ?? 0))) }

        // 1小时聚合
        let req1h = logs1h.count
        let tok1h = logs1h.reduce(0) { $0 + ($1.totalTokens ?? (($1.promptTokens ?? 0) + ($1.completionTokens ?? 0))) }

        // 构造各窗口
        var windows: [RateWindow] = []

        if let rpm = limit.rpmLimit {
            windows.append(makeWindow(.rpm1m, used: Double(req1m), limit: Double(rpm),
                                      unit: "req", resetsAt: now.addingTimeInterval(60), windowMin: 1))
        }
        if let tpm = limit.tpmLimit {
            windows.append(makeWindow(.tpm1m, used: Double(tok1m), limit: Double(tpm),
                                      unit: "tok", resetsAt: now.addingTimeInterval(60), windowMin: 1))
        }
        if let rph = limit.requestsPerHourLimit {
            windows.append(makeWindow(.requests1h, used: Double(req1h), limit: Double(rph),
                                      unit: "req", resetsAt: now.addingTimeInterval(3600), windowMin: 60))
        }
        if let tph = limit.tokensPerHourLimit {
            windows.append(makeWindow(.tokens1h, used: Double(tok1h), limit: Double(tph),
                                      unit: "tok", resetsAt: now.addingTimeInterval(3600), windowMin: 60))
        }
        if let dTok = limit.dailyTokenLimit {
            windows.append(makeWindow(.dailyTokens, used: Double(dayAgg.totalTokens), limit: Double(dTok),
                                      unit: "tok", resetsAt: nextMidnight(now), windowMin: 24 * 60))
        }

        // 5 小时请求窗口（Kimi 等消费套餐的滑动窗口）
        if let req5h = limit.fiveHourRequestLimit {
            let fiveHourAgo = now.addingTimeInterval(-5 * 3600)
            let logs5h: [ParsedLog]
            if !dayOrCountChanged, let prevLogs5h = cachedLogs5h[key] {
                logs5h = prevLogs5h.filter { $0.timestamp >= fiveHourAgo }
            } else {
                logs5h = await database.fetchLogs(provider: provider, since: fiveHourAgo, until: now)
                cachedLogs5h[key] = logs5h
            }
            windows.append(makeWindow(.requests5h, used: Double(logs5h.count), limit: Double(req5h),
                                      unit: "req", resetsAt: now.addingTimeInterval(5 * 3600), windowMin: 5 * 60))
        }
        // 月度请求数窗口（GitHub Copilot Pro: 300 premium requests/month）
        if let mReq = limit.monthlyRequestLimit {
            let monthEnd = nextMonthStart(now)
            let monthMins = Int(monthEnd.timeIntervalSince(monthStart) / 60)
            windows.append(makeWindow(.monthlyRequests, used: Double(monthAgg.requestCount), limit: Double(mReq),
                                      unit: "req", resetsAt: monthEnd, windowMin: monthMins))
        }

        // 并发：扫描 logs1h，按 [t, t+duration] 区间扫线求最大重叠
        let concurrency = computeConcurrency(logs: logs1h, now: now)

        // 节奏：取主窗口（优先 dailyTokens > tokens1h > requests1h > tpm > rpm）
        let primary = windows.first(where: { $0.kind == .dailyTokens })
            ?? windows.first(where: { $0.kind == .tokens1h })
            ?? windows.first(where: { $0.kind == .requests1h })
            ?? windows.first(where: { $0.kind == .tpm1m })
            ?? windows.first
        let pace: UsagePace?
        if let p = primary, let mins = p.windowMinutes, let reset = p.resetsAt {
            let winStart = reset.addingTimeInterval(-TimeInterval(mins) * 60)
            let elapsed = max(1, now.timeIntervalSince(winStart))
            let rate = (p.usedPercent) / elapsed   // % per second
            pace = UsagePace.compute(usedPercent: p.usedPercent,
                                     windowStart: winStart,
                                     windowMinutes: mins,
                                     ratePerSecond: rate,
                                     now: now)
        } else {
            pace = nil
        }

        return ProviderUsageSnapshot(
            provider: provider ?? .custom,
            windows: windows,
            concurrency: concurrency,
            pace: pace,
            totalCalls1h: req1h,
            totalTokens1h: tok1h,
            updatedAt: now
        )
    }

    private func makeWindow(_ kind: RateWindow.WindowKind, used: Double, limit: Double,
                            unit: String, resetsAt: Date, windowMin: Int) -> RateWindow {
        let pct = limit > 0 ? min(100, max(0, used / limit * 100)) : 0
        return RateWindow(
            kind: kind, usedPercent: pct,
            windowMinutes: windowMin, resetsAt: resetsAt,
            usedAmount: used, limitAmount: limit, unit: unit
        )
    }

    // MARK: - Concurrency Scan

    /// 扫线法：将每条日志视为 [t, t+duration] 占用一个槽，求历史最大重叠
    private func computeConcurrency(logs: [ParsedLog], now: Date) -> ConcurrencyMetric {
        guard !logs.isEmpty else {
            return ConcurrencyMetric(currentInFlight: 0, peakLastMinute: 0, peakLastHour: 0, avgDurationSeconds: 0)
        }
        struct Event { let t: TimeInterval; let delta: Int; let timestamp: TimeInterval }
        var events: [Event] = []
        var durSum: Double = 0
        var durCount: Int = 0
        for log in logs {
            let dur = max(log.duration ?? 0, 0.001)
            let start = log.timestamp.timeIntervalSince1970
            let end = start + dur
            events.append(Event(t: start, delta: +1, timestamp: start))
            events.append(Event(t: end,   delta: -1, timestamp: start))
            durSum += dur
            durCount += 1
        }
        events.sort { $0.t < $1.t }

        let oneMinAgoTs = now.addingTimeInterval(-60).timeIntervalSince1970
        let nowTs = now.timeIntervalSince1970

        var current = 0
        var peakHour = 0
        var peakMin = 0
        var inflightNow = 0
        for e in events {
            current += e.delta
            if current > peakHour { peakHour = current }
            if e.t >= oneMinAgoTs && current > peakMin { peakMin = current }
            if e.t <= nowTs && current > inflightNow && e.t >= nowTs - 0.001 {
                // 仅当事件正好覆盖到当前时刻时计入
            }
        }
        // 当前 in-flight：start <= now <= start+dur
        inflightNow = logs.reduce(0) { acc, log in
            let dur = max(log.duration ?? 0, 0.001)
            let start = log.timestamp.timeIntervalSince1970
            return acc + ((start <= nowTs && nowTs <= start + dur) ? 1 : 0)
        }

        let avg = durCount > 0 ? durSum / Double(durCount) : 0
        return ConcurrencyMetric(
            currentInFlight: inflightNow,
            peakLastMinute: peakMin,
            peakLastHour: peakHour,
            avgDurationSeconds: avg
        )
    }

    // MARK: - Global Aggregation Limit

    private func aggregateGlobalLimit(from limits: [String: ProviderRateLimit], activeProviders: [LLMProvider]) -> ProviderRateLimit {
        func sum<T: AdditiveArithmetic>(_ key: KeyPath<ProviderRateLimit, T?>) -> T? {
            var total: T? = nil
            for p in activeProviders {
                guard let l = limits[p.rawValue], let v = l[keyPath: key] else { continue }
                total = (total ?? .zero) + v
            }
            return total
        }
        return ProviderRateLimit(
            rpmLimit: sum(\.rpmLimit),
            tpmLimit: sum(\.tpmLimit),
            requestsPerHourLimit: sum(\.requestsPerHourLimit),
            tokensPerHourLimit: sum(\.tokensPerHourLimit),
            dailyTokenLimit: sum(\.dailyTokenLimit),
            monthlyRequestLimit: sum(\.monthlyRequestLimit),
            fiveHourRequestLimit: sum(\.fiveHourRequestLimit)
        )
    }

    // MARK: - Calendar Helpers

    private func nextMidnight(_ date: Date) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
        return tomorrow
    }

    private func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func nextMonthStart(_ date: Date) -> Date {
        let cal = Calendar.current
        let s = startOfMonth(date)
        return cal.date(byAdding: .month, value: 1, to: s) ?? s
    }
}
