import SwiftUI

struct RateLimitView: View {
    @EnvironmentObject var tracker: RateLimitTrackerService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var planDetector: PlanDetectionService

    @State private var editingProvider: LLMProvider? = nil
    @State private var showingApplyConfirm = false

    private var riskCount: Int {
        tracker.snapshots.filter { $0.overallSeverity != .normal }.count
    }

    private var configuredWindowCount: Int {
        tracker.snapshots.reduce(0) { $0 + $1.windows.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                overviewStrip

                detectedPlansBanner

                if let g = tracker.globalSnapshot, !g.windows.isEmpty {
                    GlobalSummaryCard(snapshot: g)
                }

                if tracker.snapshots.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 460), spacing: 16)], spacing: 16) {
                        ForEach(tracker.snapshots) { snap in
                            ProviderUsageCard(snapshot: snap) {
                                editingProvider = snap.provider
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.dashboardBackground)
        .onAppear {
            tracker.bind(database: database, config: configService)
            tracker.start()
        }
        .onDisappear {
            tracker.refresh()
        }
        .sheet(item: $editingProvider) { provider in
            RateLimitEditor(provider: provider)
                .environmentObject(configService)
                .environmentObject(tracker)
                .frame(minWidth: 460, minHeight: 520)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("速率与配额")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("RPM、TPM、预算和并发集中展示，快速判断哪个 Provider 接近上限。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Color.successGreen).frame(width: 6, height: 6)
                    Text("更新于 \(tracker.updatedAt.formattedRelative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await planDetector.detectAll() }
                    } label: {
                        if planDetector.isDetecting {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.75)
                                Text("检测中...")
                            }
                        } else {
                            Label("检测套餐", systemImage: "person.badge.key.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(planDetector.isDetecting)
                    .help("从本地凭证（GitHub CLI、Cursor、Claude Desktop）自动检测当前套餐授权")

                    Button {
                        tracker.refresh()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var overviewStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            overviewCard(
                title: "Provider",
                value: "\(tracker.snapshots.count)",
                subtitle: "正在统计",
                icon: "shippingbox.fill",
                color: .accentGradientStart
            )
            overviewCard(
                title: "风险项",
                value: "\(riskCount)",
                subtitle: "接近或达到上限",
                icon: riskCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                color: riskCount > 0 ? .warningOrange : .successGreen
            )
            overviewCard(
                title: "限额窗口",
                value: "\(configuredWindowCount)",
                subtitle: "已配置总数",
                icon: "slider.horizontal.3",
                color: .infoBlue
            )
            overviewCard(
                title: "全局并发",
                value: "\(tracker.globalSnapshot?.concurrency.currentInFlight ?? 0)",
                subtitle: "当前进行中",
                icon: "arrow.triangle.branch",
                color: .accentGradientEnd
            )
        }
    }

    private func overviewCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardStyle()
    }

    // MARK: - Detected Plans Banner

    @ViewBuilder
    private var detectedPlansBanner: some View {
        if !planDetector.detectedPlans.isEmpty || !planDetector.statusMessage.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: planDetector.detectedPlans.isEmpty ? "info.circle" : "checkmark.seal.fill")
                        .foregroundStyle(planDetector.detectedPlans.isEmpty ? Color.secondary : Color.successGreen)
                    Text(planDetector.detectedPlans.isEmpty ? "套餐检测" : "已检测到 \(planDetector.detectedPlans.count) 个本地套餐")
                        .font(.subheadline.bold())
                    Spacer()
                    if !planDetector.detectedPlans.isEmpty {
                        Button {
                            planDetector.applyToConfig(configService)
                            tracker.refresh()
                            showingApplyConfirm = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showingApplyConfirm = false }
                        } label: {
                            Label(showingApplyConfirm ? "已应用 ✓" : "应用到配置", systemImage: showingApplyConfirm ? "checkmark" : "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(showingApplyConfirm)
                    }
                }

                if !planDetector.statusMessage.isEmpty {
                    Text(planDetector.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !planDetector.detectedPlans.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(Array(planDetector.detectedPlans.values)) { plan in
                            HStack(spacing: 10) {
                                Image(systemName: plan.provider.iconName)
                                    .foregroundStyle(plan.provider.brandColor)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plan.planName)
                                        .font(.caption.bold())
                                    Text(plan.source)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .cardStyle()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("暂无可统计的调用")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("启动监控并捕获到日志后，这里会显示每个 Provider 的实时速率与配额。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .cardStyle()
    }
}

// MARK: - Global Summary

private struct GlobalSummaryCard: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "globe")
                Text("全局汇总")
                    .font(.headline)
                Spacer()
                SeverityBadge(severity: snapshot.overallSeverity)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                summaryItem(title: "1小时请求", value: "\(snapshot.totalCalls1h)", icon: "paperplane.fill")
                summaryItem(title: "1小时 Token", value: snapshot.totalTokens1h.formattedCompact, icon: "textformat.abc")
                summaryItem(title: "今日费用", value: snapshot.totalCost24h.formattedCurrency, icon: "dollarsign.circle.fill")
                summaryItem(title: "当前并发", value: "\(snapshot.concurrency.currentInFlight)", icon: "arrow.triangle.branch")
                summaryItem(title: "1分钟峰值并发", value: "\(snapshot.concurrency.peakLastMinute)", icon: "waveform.path.ecg")
                summaryItem(title: "1小时峰值并发", value: "\(snapshot.concurrency.peakLastHour)", icon: "chart.line.uptrend.xyaxis")
            }

            ForEach(snapshot.windows) { w in
                RateWindowBar(window: w, pace: nil)
            }
        }
        .cardStyle()
    }

    private func summaryItem(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Provider Card

private struct ProviderUsageCard: View {
    @EnvironmentObject var planDetector: PlanDetectionService
    let snapshot: ProviderUsageSnapshot
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: snapshot.provider.iconName)
                    .foregroundStyle(snapshot.provider.brandColor)
                Text(snapshot.provider.displayName)
                    .font(.headline)
                if let plan = planDetector.detectedPlans[snapshot.provider] {
                    DetectedPlanBadge(planName: plan.planName, source: plan.source)
                }
                Spacer()
                SeverityBadge(severity: snapshot.overallSeverity)
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("编辑此 Provider 的限额")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("并发概览")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    concurrencyChip("当前并发", value: "\(snapshot.concurrency.currentInFlight)", systemImage: "arrow.triangle.branch")
                    concurrencyChip("1m 峰值", value: "\(snapshot.concurrency.peakLastMinute)", systemImage: "waveform.path.ecg")
                    concurrencyChip("1h 峰值", value: "\(snapshot.concurrency.peakLastHour)", systemImage: "chart.line.uptrend.xyaxis")
                    concurrencyChip("平均时长", value: snapshot.concurrency.avgDurationSeconds.formattedDuration, systemImage: "clock")
                }
            }

            Divider()

            if snapshot.windows.isEmpty {
                Text("此 Provider 未配置任何限额")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("限额进度")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("共 \(snapshot.windows.count) 项")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(snapshot.windows) { window in
                    RateWindowBar(
                        window: window,
                        pace: snapshot.pace.flatMap { window.kind == primaryKind ? $0 : nil }
                    )
                }
            }
        }
        .cardStyle()
    }

    /// 与 RateLimitTrackerService 内一致的主窗口优先级
    private var primaryKind: RateWindow.WindowKind? {
        let order: [RateWindow.WindowKind] = [.dailyCost, .dailyTokens, .tokens1h, .requests1h, .tpm1m, .rpm1m]
        for k in order where snapshot.windows.contains(where: { $0.kind == k }) {
            return k
        }
        return snapshot.windows.first?.kind
    }

    private func concurrencyChip(_ title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption2).foregroundStyle(.secondary)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - RateWindow Progress Bar (借鉴 CodexBar 的 used% + 节奏 tick)

struct RateWindowBar: View {
    let window: RateWindow
    let pace: UsagePace?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.kind.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(formatUsed())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", window.usedPercent))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.gradient)
                        .frame(width: max(2, geo.size.width * CGFloat(window.usedPercent / 100)))

                    // pace tick (借鉴 CodexBar 的预期进度刻度)
                    if let pace, pace.expectedPercent > 0, pace.expectedPercent < 100 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * CGFloat(pace.expectedPercent / 100) - 1)
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 6) {
                if let resetDesc = window.resetDescription {
                    Label(resetDesc, systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("剩余 \(formatRemaining())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let pace {
                    paceTag(pace)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatUsed() -> String {
        switch window.unit {
        case "USD":
            return "\(window.usedAmount.formattedCurrency) / \(window.limitAmount.formattedCurrency)"
        case "tok":
            return "\(Int(window.usedAmount).formattedCompact) / \(Int(window.limitAmount).formattedCompact) tok"
        default:
            return "\(Int(window.usedAmount)) / \(Int(window.limitAmount)) \(window.unit)"
        }
    }

    private func formatRemaining() -> String {
        switch window.unit {
        case "USD":
            return window.remainingAmount.formattedCurrency
        case "tok":
            return "\(Int(window.remainingAmount).formattedCompact) tok"
        default:
            return "\(Int(window.remainingAmount)) \(window.unit)"
        }
    }

    private var color: Color {
        switch window.severity {
        case .critical: return .errorRed
        case .warning:  return .warningOrange
        case .normal:   return .successGreen
        }
    }

    @ViewBuilder
    private func paceTag(_ pace: UsagePace) -> some View {
        let delta = pace.deltaPercent
        let sign = delta >= 0 ? "+" : ""
        Text("\(pace.stage.label) (\(sign)\(String(format: "%.1f", delta))%)")
            .font(.caption2)
            .foregroundStyle(paceColor(stage: pace.stage))
    }

    private func paceColor(stage: UsagePace.Stage) -> Color {
        switch stage {
        case .farAhead:        return .errorRed
        case .ahead:           return .warningOrange
        case .slightlyAhead:   return .warningOrange.opacity(0.7)
        case .onTrack:         return .secondary
        case .slightlyBehind, .behind, .farBehind: return .successGreen
        }
    }
}

// MARK: - Detected Plan Badge

private struct DetectedPlanBadge: View {
    let planName: String
    let source: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 9))
            Text(planName)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
        .help("套餐来源：\(source)")
    }
}

// MARK: - Severity Badge

private struct SeverityBadge: View {
    let severity: RateWindow.Severity
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    private var color: Color {
        switch severity {
        case .critical: return .errorRed
        case .warning:  return .warningOrange
        case .normal:   return .successGreen
        }
    }
    private var label: String {
        switch severity {
        case .critical: return "超限风险"
        case .warning:  return "接近上限"
        case .normal:   return "正常"
        }
    }
}

// MARK: - Editor Sheet

struct RateLimitEditor: View {
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var tracker: RateLimitTrackerService
    @Environment(\.dismiss) var dismiss

    let provider: LLMProvider

    @State private var rpmStr: String = ""
    @State private var tpmStr: String = ""
    @State private var rphStr: String = ""
    @State private var tphStr: String = ""
    @State private var dTokStr: String = ""
    @State private var dCostStr: String = ""
    @State private var mCostStr: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: provider.iconName).foregroundStyle(provider.brandColor)
                Text("\(provider.displayName) 限额配置").font(.title3.bold())
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()

            Form {
                Section("速率限制") {
                    field("RPM (每分钟请求)",        $rpmStr,  placeholder: "如 500")
                    field("TPM (每分钟 token)",     $tpmStr,  placeholder: "如 30000")
                    field("每小时请求数",            $rphStr,  placeholder: "如 10000")
                    field("每小时 token 数",         $tphStr,  placeholder: "如 1000000")
                }
                Section("配额预算") {
                    field("每日 token 上限",         $dTokStr, placeholder: "如 5000000")
                    field("每日预算 (USD)",         $dCostStr, placeholder: "如 50")
                    field("每月预算 (USD)",         $mCostStr, placeholder: "如 500")
                }
            }
            .formStyle(.grouped)

            Text("留空表示不限制。修改后立即生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear(perform: load)
    }

    private func field(_ title: String, _ binding: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title).frame(width: 180, alignment: .leading)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func load() {
        let current = configService.config.providerRateLimits[provider.rawValue]
            ?? ProviderRateLimit.defaultLocal
        rpmStr = current.rpmLimit.map(String.init) ?? ""
        tpmStr = current.tpmLimit.map(String.init) ?? ""
        rphStr = current.requestsPerHourLimit.map(String.init) ?? ""
        tphStr = current.tokensPerHourLimit.map(String.init) ?? ""
        dTokStr = current.dailyTokenLimit.map(String.init) ?? ""
        dCostStr = current.dailyCostLimit.map { String($0) } ?? ""
        mCostStr = current.monthlyCostLimit.map { String($0) } ?? ""
    }

    private func save() {
        let new = ProviderRateLimit(
            rpmLimit: Int(rpmStr),
            tpmLimit: Int(tpmStr),
            requestsPerHourLimit: Int(rphStr),
            tokensPerHourLimit: Int(tphStr),
            dailyTokenLimit: Int(dTokStr),
            dailyCostLimit: Double(dCostStr),
            monthlyCostLimit: Double(mCostStr)
        )
        configService.config.providerRateLimits[provider.rawValue] = new
        configService.save()
        tracker.refresh()
        dismiss()
    }
}

// 让 LLMProvider 可作为 .sheet(item:) 的 Identifiable 已在原始定义中提供
