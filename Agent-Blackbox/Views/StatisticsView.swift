import SwiftUI
import Charts

// MARK: - Time range

enum TimeRange: String, CaseIterable, Identifiable {
    case oneHour  = "1H"
    case sixHours = "6H"
    case oneDay   = "24H"
    case sevenDays  = "7D"
    case thirtyDays = "30D"

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .oneHour:    return 3_600
        case .sixHours:   return 21_600
        case .oneDay:     return 86_400
        case .sevenDays:  return 7 * 86_400
        case .thirtyDays: return 30 * 86_400
        }
    }

    /// Number of equal-width buckets for the trend chart
    var bucketCount: Int {
        switch self {
        case .oneHour:    return 12   // 5-min buckets
        case .sixHours:   return 12   // 30-min buckets
        case .oneDay:     return 24   // 1-hour buckets
        case .sevenDays:  return 28   // 6-hour buckets
        case .thirtyDays: return 30   // 1-day buckets
        }
    }
}

// MARK: - Main view

struct StatisticsView: View {
    @EnvironmentObject var database: DatabaseService

    @State private var selectedRange: TimeRange = .oneDay
    @State private var stats: LogStats = LogStats(totalCount: 0, errorCount: 0, totalTokens: 0, activeModels: 0)
    @State private var trend: [TrendPoint] = []
    @State private var lastRefresh: Date = Date()
    @State private var isVisible = false

    private let timer = Timer.publish(every: Self.refreshInterval, on: .main, in: .common).autoconnect()
    private static let refreshInterval: TimeInterval = 30
    private static let categoryNormal = "正常"
    private static let categoryError  = "错误"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerRow
                metricCards
                trendChart
                if stats.errorCount > 0 {
                    errorChart
                }
                refreshFooter
            }
            .padding()
        }
        .onAppear { isVisible = true; refresh() }
        .onDisappear { isVisible = false }
        .onChange(of: selectedRange) { _ in refresh() }
        .onReceive(timer) { _ in if isVisible { refresh() } }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text("日志趋势")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Picker("时间范围", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
    }

    private var metricCards: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
            spacing: 12
        ) {
            MetricCard(title: "总调用次数",  value: "\(stats.totalCount)",           icon: "list.bullet.rectangle", color: .blue)
            MetricCard(title: "错误次数",    value: "\(stats.errorCount)",            icon: "exclamationmark.triangle", color: .red)
            MetricCard(title: "Token 用量", value: formatTokens(stats.totalTokens), icon: "textformat.123", color: .purple)
            MetricCard(title: "活跃模型数",  value: "\(stats.activeModels)",          icon: "cpu", color: .green)
        }
    }

    private var trendChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("调用趋势")
                    .font(.headline)

                if trend.allSatisfy({ $0.count == 0 }) {
                    Text("暂无数据")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                } else {
                    Chart(trendChartData) { entry in
                        BarMark(
                            x: .value("时间", entry.date),
                            y: .value("次数", entry.value)
                        )
                        .foregroundStyle(by: .value("类型", entry.category))
                    }
                    .chartForegroundStyleScale([Self.categoryNormal: Color.blue.opacity(0.75), Self.categoryError: Color.red.opacity(0.8)])
                    .chartXAxis { dateAxisMarks }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .frame(minHeight: 200)
                }
            }
            .padding(8)
        }
    }

    private var errorChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("错误趋势")
                    .font(.headline)

                Chart(trend) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("错误", point.errorCount)
                    )
                    .foregroundStyle(Color.red)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("错误", point.errorCount)
                    )
                    .foregroundStyle(Color.red.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis { dateAxisMarks }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(minHeight: 120)
            }
            .padding(8)
        }
    }

    private var refreshFooter: some View {
        Text("最后更新：\(lastRefresh.formatted(.dateTime.hour().minute().second()))")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Chart helpers

    /// Flat data array used for the stacked bar chart
    private var trendChartData: [TrendChartEntry] {
        trend.flatMap { point in [
            TrendChartEntry(date: point.date, category: Self.categoryNormal, value: max(0, point.count - point.errorCount)),
            TrendChartEntry(date: point.date, category: Self.categoryError,  value: point.errorCount)
        ]}
    }

    @AxisContentBuilder
    private var dateAxisMarks: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 6)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    switch selectedRange {
                    case .oneHour, .sixHours:
                        Text(date, format: .dateTime.hour().minute())
                    case .oneDay:
                        Text(date, format: .dateTime.hour())
                    case .sevenDays, .thirtyDays:
                        Text(date, format: .dateTime.month().day())
                    }
                }
            }
        }
    }

    // MARK: - Data refresh

    private func refresh() {
        let end = Date()
        let start = end.addingTimeInterval(-selectedRange.duration)
        stats = database.fetchStats(from: start, to: end)
        trend = database.fetchTrend(from: start, to: end, bucketCount: selectedRange.bucketCount)
        lastRefresh = end
    }

    // MARK: - Formatting

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Supporting types

private struct TrendChartEntry: Identifiable {
    let id: UUID = UUID()
    let date: Date
    let category: String
    let value: Int
}

// MARK: - Metric card

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    Spacer()
                }
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(4)
        }
    }
}
