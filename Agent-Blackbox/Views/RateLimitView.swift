import SwiftUI
import Charts

// MARK: - Tab Enum

/// 选中的 Tab：Overview 或某个具体 Provider
enum RateLimitTab: Hashable {
    case overview
    case provider(LLMProvider)
}

// MARK: - Main View

struct RateLimitView: View {
    @EnvironmentObject var tracker: RateLimitTrackerService
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var database: DatabaseService
    @EnvironmentObject var planDetector: PlanDetectionService

    @State private var showingApplyConfirm = false
    @State private var selectedTab: RateLimitTab = .overview

    private var riskCount: Int {
        tracker.snapshots.filter { $0.overallSeverity != .normal }.count
    }

    private var configuredWindowCount: Int {
        tracker.snapshots.reduce(0) { $0 + $1.windows.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Provider Tab Bar ──────────────────────────────────
            providerTabBar

            Divider()
                .opacity(0.5)

            // ── Content ──────────────────────────────────────────
            NativeScrollView {
                VStack(spacing: 0) {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .provider(let p):
                        if let snap = tracker.snapshots.first(where: { $0.provider == p }) {
                            ProviderDetailView(
                                snapshot: snap,
                                detectedPlan: planDetector.detectedPlans[p],
                                onEdit: { NotificationCenter.default.post(name: Notification.Name("ShowRateLimitEditorSheet"), object: p) }
                            )
                            .id(p) // force rebuild on tab switch
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        } else {
                            emptyProviderState(p)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: selectedTab)
            }
        }
        .background(Color.dashboardBackground)
        .onAppear {
            tracker.bind(database: database, config: configService)
            tracker.start()
        }
        .onDisappear {
            Task {
                await tracker.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NavigateToRateLimits"))) { notification in
            if let provider = notification.object as? LLMProvider {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = .provider(provider)
                }
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = .overview
                }
            }
        }
    }

    // MARK: - Provider Tab Bar

    private var providerTabBar: some View {
        VStack(spacing: 0) {
            // Main tab row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Overview tab
                    tabButton(
                        icon: "rectangle.grid.2x2",
                        label: "Overview",
                        isSelected: selectedTab == .overview,
                        color: .accentGradientStart
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = .overview
                        }
                    }

                    // Provider tabs
                    ForEach(tracker.snapshots) { snap in
                        tabButton(
                            icon: snap.provider.iconName,
                            label: snap.provider.shortName,
                            isSelected: selectedTab == .provider(snap.provider),
                            color: snap.provider.brandColor,
                            severity: snap.overallSeverity
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = .provider(snap.provider)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 64)
            .background(.ultraThinMaterial)
        }
    }

    private func tabButton(
        icon: String,
        label: String,
        isSelected: Bool,
        color: Color,
        severity: RateWindow.Severity = .normal,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? color : .secondary)
                        .frame(width: 28, height: 28)

                    // Risk dot
                    if severity != .normal {
                        Circle()
                            .fill(severity == .critical ? Color.errorRed : Color.warningOrange)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 52)
            .overlay(alignment: .bottom) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(height: 3)
                        .padding(.horizontal, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overview Content

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("速率与配额")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    HStack(spacing: 6) {
                        Circle().fill(Color.successGreen).frame(width: 6, height: 6)
                        Text("更新于 \(tracker.updatedAt.formattedRelative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { await planDetector.detectAll() }
                    } label: {
                        if planDetector.isDetecting {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.65)
                                Text("检测中...")
                                    .font(.caption)
                            }
                        } else {
                            Label("检测套餐", systemImage: "person.badge.key.fill")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(planDetector.isDetecting)

                    Button {
                        Task {
                            await tracker.refresh()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Overview metric strip
            overviewMetricStrip
                .padding(.horizontal, 20)

            // Detected plans banner
            detectedPlansBanner
                .padding(.horizontal, 20)

            // Provider list (sorted by severity then usage)
            if tracker.snapshots.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 1) {
                    ForEach(sortedSnapshots) { snap in
                        ProviderRowCard(snapshot: snap,
                                       detectedPlan: planDetector.detectedPlans[snap.provider]) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = .provider(snap.provider)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    /// Sorted: critical first, then warning, then normal; within same severity by calls desc
    private var sortedSnapshots: [ProviderUsageSnapshot] {
        tracker.snapshots.sorted { a, b in
            let aSev = severityOrder(a.overallSeverity)
            let bSev = severityOrder(b.overallSeverity)
            if aSev != bSev { return aSev > bSev }
            return a.totalCalls1h > b.totalCalls1h
        }
    }

    private func severityOrder(_ s: RateWindow.Severity) -> Int {
        switch s {
        case .critical: return 2
        case .warning: return 1
        case .normal: return 0
        }
    }

    // MARK: - Overview Metric Strip

    private var overviewMetricStrip: some View {
        HStack(spacing: 10) {
            compactMetric(
                value: "\(tracker.snapshots.count)",
                label: "Provider",
                icon: "shippingbox.fill",
                color: .accentGradientStart
            )
            compactMetric(
                value: "\(riskCount)",
                label: "风险项",
                icon: riskCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                color: riskCount > 0 ? .warningOrange : .successGreen
            )
            compactMetric(
                value: "\(configuredWindowCount)",
                label: "限额窗口",
                icon: "slider.horizontal.3",
                color: .infoBlue
            )
            compactMetric(
                value: "\(tracker.globalSnapshot?.concurrency.currentInFlight ?? 0)",
                label: "并发",
                icon: "arrow.triangle.branch",
                color: .accentGradientEnd
            )
        }
    }

    private func compactMetric(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Detected Plans Banner

    @ViewBuilder
    private var detectedPlansBanner: some View {
        if !planDetector.detectedPlans.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.successGreen)
                        .font(.caption)
                    Text("已检测 \(planDetector.detectedPlans.count) 个套餐")
                        .font(.caption.bold())
                    Spacer()
                    Button {
                        planDetector.applyToConfig(configService)
                        Task {
                            await tracker.refresh()
                        }
                        showingApplyConfirm = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showingApplyConfirm = false }
                    } label: {
                        Text(showingApplyConfirm ? "已应用 ✓" : "应用到配置")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(showingApplyConfirm)
                }

                if !planDetector.statusMessage.isEmpty {
                    Text(planDetector.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Compact plan pills
                FlowLayout(spacing: 6) {
                    ForEach(Array(planDetector.detectedPlans.values)) { plan in
                        HStack(spacing: 4) {
                            Image(systemName: plan.provider.iconName)
                                .font(.system(size: 9))
                                .foregroundStyle(plan.provider.brandColor)
                            Text(plan.planName)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(plan.provider.brandColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(12)
            .background(Color.successGreen.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.successGreen.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("暂无可统计的调用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("启动监控后，这里会显示实时速率与配额。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .cardStyle()
    }

    private func emptyProviderState(_ provider: LLMProvider) -> some View {
        VStack(spacing: 10) {
            Image(systemName: provider.iconName)
                .font(.system(size: 36))
                .foregroundStyle(provider.brandColor.opacity(0.4))
            Text("\(provider.displayName) 暂无数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("捕获到该 Provider 的日志后，数据将在此显示。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(20)
    }
}

// MARK: - Provider Row Card (Overview List)

private struct ProviderRowCard: View {
    let snapshot: ProviderUsageSnapshot
    let detectedPlan: DetectedPlan?
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Provider icon
                Image(systemName: snapshot.provider.iconName)
                    .font(.title3)
                    .foregroundStyle(snapshot.provider.brandColor)
                    .frame(width: 32)

                // Name + plan
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(snapshot.provider.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        if let plan = detectedPlan {
                            Text(plan.planName)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    Text("1h: \(snapshot.totalCalls1h) 调用 · \(snapshot.totalTokens1h.formattedCompact) tok")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Primary window mini bar
                if let primary = snapshot.windows.first {
                    HStack(spacing: 8) {
                        // Mini progress indicator
                        MiniProgressRing(percent: primary.usedPercent, color: progressColor(primary.severity))
                            .frame(width: 28, height: 28)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(String(format: "%.0f", primary.usedPercent))%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(progressColor(primary.severity))
                            Text(primary.kind.displayName)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Severity + chevron
                SeverityDot(severity: snapshot.overallSeverity)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(isHovered ? 0.08 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func progressColor(_ severity: RateWindow.Severity) -> Color {
        switch severity {
        case .critical: return .errorRed
        case .warning: return .warningOrange
        case .normal: return .successGreen
        }
    }
}

// MARK: - Mini Progress Ring

private struct MiniProgressRing: View {
    let percent: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(percent / 100, 1.0))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Severity Dot

private struct SeverityDot: View {
    let severity: RateWindow.Severity

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch severity {
        case .critical: return .errorRed
        case .warning: return .warningOrange
        case .normal: return .successGreen
        }
    }
}

// MARK: - Provider Detail View (Single Provider Page)

private struct ProviderDetailView: View {
    @EnvironmentObject var tracker: RateLimitTrackerService
    @EnvironmentObject var database: DatabaseService
    let snapshot: ProviderUsageSnapshot
    let detectedPlan: DetectedPlan?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ─────────────────────────
            providerHeader
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().padding(.horizontal, 20).opacity(0.4)

            // ── Rate Windows (Progress Bars) ───
            if !snapshot.windows.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(snapshot.windows) { window in
                        CompactRateBar(
                            window: window,
                            pace: snapshot.pace.flatMap { window.kind == primaryKind ? $0 : nil }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("此 Provider 未配置限额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // ── Stats Grid ─────────────────────
            statsGrid
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Divider().padding(.horizontal, 20).padding(.top, 16).opacity(0.4)

            // ── Concurrency ────────────────────
            concurrencySection
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Divider().padding(.horizontal, 20).padding(.top, 12).opacity(0.4)

            // ── Hourly Usage Chart ─────────────
            hourlyUsageSection
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Divider().padding(.horizontal, 20).padding(.top, 12).opacity(0.4)

            // ── Quick Actions ──────────────────
            quickActions
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Provider Header

    private var providerHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.provider.iconName)
                .font(.system(size: 20))
                .foregroundStyle(snapshot.provider.brandColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.provider.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if let plan = detectedPlan {
                        DetectedPlanBadge(planName: plan.planName, source: plan.source)
                    }
                }
                Text("更新于 \(snapshot.updatedAt.formattedRelative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SeverityBadge(severity: snapshot.overallSeverity)

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("编辑限额")
        }
    }

    /// 与 RateLimitTrackerService 内一致的主窗口优先级
    private var primaryKind: RateWindow.WindowKind? {
        let order: [RateWindow.WindowKind] = [.dailyTokens, .tokens1h, .requests1h, .tpm1m, .rpm1m]
        for k in order where snapshot.windows.contains(where: { $0.kind == k }) {
            return k
        }
        return snapshot.windows.first?.kind
    }

    // MARK: - Stats Grid (2x2 like CodexBar)

    private var statsGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            statCell(
                label: "24h tokens",
                value: snapshot.totalTokens1h.formattedCompact,
                subValue: nil
            )
            statCell(
                label: "Latest hour",
                value: "\(snapshot.totalCalls1h)",
                subValue: "调用"
            )
            statCell(
                label: "Peak hour",
                value: "\(snapshot.concurrency.peakLastHour)",
                subValue: "并发"
            )
            statCell(
                label: "Avg duration",
                value: snapshot.concurrency.avgDurationSeconds.formattedDuration,
                subValue: nil
            )
        }
    }

    private func statCell(label: String, value: String, subValue: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textCase(.none)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if let sub = subValue {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Concurrency Section

    private var concurrencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("并发概览")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                concurrencyPill("当前", value: "\(snapshot.concurrency.currentInFlight)", icon: "arrow.triangle.branch")
                concurrencyPill("1m峰值", value: "\(snapshot.concurrency.peakLastMinute)", icon: "waveform.path.ecg")
                concurrencyPill("1h峰值", value: "\(snapshot.concurrency.peakLastHour)", icon: "chart.line.uptrend.xyaxis")
                concurrencyPill("平均", value: snapshot.concurrency.avgDurationSeconds.formattedDuration, icon: "clock")
            }
        }
    }

    private func concurrencyPill(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Hourly Usage Mini Chart

    private var hourlyUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hourly Usage")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            // Mini bar chart using hourly data
            HourlyMiniChart(provider: snapshot.provider, database: database)
                .frame(height: 48)
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 0) {
            actionRow(icon: "chart.bar.fill", label: "Usage Dashboard", color: .infoBlue) {}
            Divider().padding(.leading, 32).opacity(0.3)
            actionRow(icon: "arrow.clockwise", label: "Refresh", color: .primary, shortcut: "⌘R") {
                Task {
                    await tracker.refresh()
                }
            }
            Divider().padding(.leading, 32).opacity(0.3)
            actionRow(icon: "gearshape", label: "Settings…", color: .primary, shortcut: "⌘,") {
                onEdit()
            }
        }
    }

    private func actionRow(
        icon: String,
        label: String,
        color: Color,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(label)
                    .font(.subheadline)
                Spacer()
                if let key = shortcut {
                    Text(key)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Rate Bar (CodexBar style)

struct CompactRateBar: View {
    let window: RateWindow
    let pace: UsagePace?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack {
                Text(window.kind.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let resetDesc = window.resetDescription {
                    Text(resetDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar (CodexBar style — thicker with gradient)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))

                    // Fill bar with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: barGradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, geo.size.width * CGFloat(window.usedPercent / 100)))

                    // Pace tick
                    if let pace, pace.expectedPercent > 0, pace.expectedPercent < 100 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * CGFloat(pace.expectedPercent / 100) - 1)
                    }
                }
            }
            .frame(height: 8)

            // Bottom info row
            HStack {
                Text("\(String(format: "%.0f", window.remainingPercent))% left")
                    .font(.caption)
                    .foregroundStyle(barColor)
                    .fontWeight(.medium)

                Spacer()

                Text(formatUsed())
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let pace {
                    paceTag(pace)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var barGradientColors: [Color] {
        switch window.severity {
        case .critical:
            return [Color.errorRed.opacity(0.8), Color.errorRed]
        case .warning:
            return [Color.warningOrange.opacity(0.8), Color.warningOrange]
        case .normal:
            return [Color.successGreen.opacity(0.7), Color.successGreen]
        }
    }

    private var barColor: Color {
        switch window.severity {
        case .critical: return .errorRed
        case .warning: return .warningOrange
        case .normal: return .successGreen
        }
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

// MARK: - Hourly Mini Chart

private struct HourlyMiniChart: View {
    let provider: LLMProvider
    @ObservedObject var database: DatabaseService

    private struct HourlyBucket: Identifiable {
        let id: Int
        let hour: Int
        let count: Int
    }

    @State private var buckets: [HourlyBucket] = []
    @State private var topModel: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Hour", bucket.hour),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(provider.brandColor.gradient)
                .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(max(10, buckets.map(\.count).max() ?? 10)))

            Text("Top model: \(topModel)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .task(id: provider) {
            let data = await database.fetchHourlyChartData(provider: provider)
            self.buckets = data.buckets.map { HourlyBucket(id: $0.hour, hour: $0.hour, count: $0.count) }
            self.topModel = data.topModel
        }
    }
}


// MARK: - Detected Plan Badge

private struct DetectedPlanBadge: View {
    let planName: String
    let source: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 8))
            Text(planName)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
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

// MARK: - LLMProvider Short Name

extension LLMProvider {
    var shortName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthro…"
        case .google: return "Google"
        case .warp: return "Warp"
        case .ollama: return "Ollama"
        case .cursor: return "Cursor"
        case .copilot: return "Copilot"
        case .claudeDesktop: return "Claude"
        case .cline: return "Cline"
        case .lmstudio: return "LMStudio"
        case .continuedev: return "Continue"
        case .deepseek: return "DeepSeek"
        case .qwen: return "Qwen"
        case .kimi: return "Kimi"
        case .zhipu: return "GLM"
        case .amp: return "Amp"
        case .antigravity: return "Antigra…"
        case .pi: return "Pi"
        case .codex: return "Codex"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Editor Sheet (preserved)

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
    @State private var req5hStr: String = ""
    @State private var mReqStr: String = ""

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
                    field("5 小时请求数上限",         $req5hStr, placeholder: "如 50 (Claude Pro)")
                    field("月度请求数上限",          $mReqStr, placeholder: "如 300 (Copilot Pro)")
                }
            }
            .formStyle(.grouped)

            Text("留空表示不限制。修改后立即生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            load()
        }
    }

    private func field(_ title: String, _ binding: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title).frame(width: 180, alignment: .leading)
            AppKitTextField(
                placeholder: placeholder,
                    text: binding
            )
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
        req5hStr = current.fiveHourRequestLimit.map(String.init) ?? ""
        mReqStr = current.monthlyRequestLimit.map(String.init) ?? ""
    }

    private func save() {
        let new = ProviderRateLimit(
            rpmLimit: Int(rpmStr),
            tpmLimit: Int(tpmStr),
            requestsPerHourLimit: Int(rphStr),
            tokensPerHourLimit: Int(tphStr),
            dailyTokenLimit: Int(dTokStr),
            monthlyRequestLimit: Int(mReqStr),
            fiveHourRequestLimit: Int(req5hStr)
        )
        configService.config.providerRateLimits[provider.rawValue] = new
        configService.save()
        Task {
            await tracker.refresh()
        }
        dismiss()
    }
}

// 让 LLMProvider 可作为 .sheet(item:) 的 Identifiable 已在原始定义中提供
