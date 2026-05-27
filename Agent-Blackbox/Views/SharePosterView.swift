import SwiftUI
import Charts
import AppKit

// MARK: - Poster Theme Definition
enum PosterTheme: String, CaseIterable, Identifiable {
    case spaceGray = "深空碳灰"
    case obsidian = "墨岩曜黑"
    case linearPurple = "幽玄极光"
    case nordicSteel = "北欧冷钢"
    case champagne = "香槟琥珀"
    
    var id: String { rawValue }
    
    var backgroundGradient: LinearGradient {
        switch self {
        case .spaceGray:
            return LinearGradient(
                colors: [Color(hex: "161617"), Color(hex: "242426"), Color(hex: "0D0D0E")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .obsidian:
            return LinearGradient(
                colors: [Color(hex: "0A0A0A"), Color(hex: "1C1C1C"), Color(hex: "020202")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .linearPurple:
            return LinearGradient(
                colors: [Color(hex: "0D0E12"), Color(hex: "1B1A24"), Color(hex: "070709")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .nordicSteel:
            return LinearGradient(
                colors: [Color(hex: "11161B"), Color(hex: "1E2833"), Color(hex: "090C0F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .champagne:
            return LinearGradient(
                colors: [Color(hex: "141311"), Color(hex: "26231E"), Color(hex: "0B0A09")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var highlightColor: Color {
        switch self {
        case .spaceGray: return Color(hex: "F5F5F7")
        case .obsidian: return Color(hex: "FFFFFF")
        case .linearPurple: return Color(hex: "B4B9E8")
        case .nordicSteel: return Color(hex: "A5C3D6")
        case .champagne: return Color(hex: "E6C280")
        }
    }
    
    var secondaryHighlightColor: Color {
        switch self {
        case .spaceGray: return Color(hex: "AEAEB2")
        case .obsidian: return Color(hex: "D1D1D6")
        case .linearPurple: return Color(hex: "A3A7CC")
        case .nordicSteel: return Color(hex: "8EACC0")
        case .champagne: return Color(hex: "C2AD86")
        }
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Poster Template View (Strictly 480x720)
struct PosterTemplateView: View {
    let stats: DashboardStats
    let timeRange: DashboardTimeRange
    let userName: String
    let userSubtitle: String
    let theme: PosterTheme
    
    var topModels: [(name: String, count: Int, percentage: Double)] {
        let total = stats.callsByModel.values.reduce(0, +)
        guard total > 0 else { return [] }
        let sorted = stats.callsByModel.sorted { $0.value > $1.value }
        return sorted.prefix(3).map { item in
            let pct = Double(item.value) / Double(total)
            return (name: item.key, count: item.value, percentage: pct)
        }
    }
    
    var activeHourRange: String {
        let calendar = Calendar.current
        let hourCounts = Dictionary(grouping: stats.recentLogs) { log in
            calendar.component(.hour, from: log.timestamp)
        }.mapValues { $0.count }
        
        if let maxHour = hourCounts.max(by: { $0.value < $1.value })?.key {
            return String(format: "%02d:00 - %02d:00", maxHour, (maxHour + 1) % 24)
        }
        return "19:00 - 22:00"
    }
    
    var activeHourValue: Int {
        let calendar = Calendar.current
        let hourCounts = Dictionary(grouping: stats.recentLogs) { log in
            calendar.component(.hour, from: log.timestamp)
        }.mapValues { $0.count }
        return hourCounts.max(by: { $0.value < $1.value })?.key ?? 19
    }
    
    var geekTitle: String {
        let hour = activeHourValue
        switch hour {
        case 0...4:
            return "深夜极客 (Midnight Magic)"
        case 5...8:
            return "晨曦极客 (Early Bird)"
        case 9...12:
            return "晨光开拓者 (Morning Pioneer)"
        case 13...17:
            return "黄金生产力 (Peak Performer)"
        case 18...22:
            return "极客黄金期 (Prime Builder)"
        default:
            return "全能开发者 (All-Rounder)"
        }
    }
    
    var estimatedValueSaved: String {
        let cost = Double(stats.totalTokens) * 0.000015 // average $15 per M tokens
        return String(format: "$%.2f", cost)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header Section
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.highlightColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.shield.fill")
                        .font(.title2)
                        .foregroundStyle(theme.highlightColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AGENT BLACKBOX")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .kerning(1.5)
                        .foregroundStyle(LinearGradient(
                            colors: [Color.white, theme.highlightColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    Text(userSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                
                // Time Range Badge
                Text(timeRange.rawValue + "用量总览")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.highlightColor.opacity(0.15))
                    .foregroundStyle(theme.highlightColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(theme.highlightColor.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            
            // Developer Greeting / Signature Card
            HStack(spacing: 12) {
                // Monogram Avatar for Personal IP
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [theme.highlightColor.opacity(0.85), theme.secondaryHighlightColor.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 38, height: 38)
                    
                    Text(userName.prefix(2).uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 协同探索者")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryHighlightColor)
                    Text(userName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            
            // Core Metrics Grid (2x2)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Metric 1: Total Calls
                VStack(alignment: .leading, spacing: 4) {
                    Text("大模型调用次数")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(stats.totalCalls)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("次")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    
                    Text("通过本地代理发起的 AI 请求总量")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                
                // Metric 2: Total Tokens
                VStack(alignment: .leading, spacing: 4) {
                    Text("Token 吞吐总量")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(stats.totalTokens.formattedCompact)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.highlightColor)
                        Text("tokens")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    
                    Text("模型处理与生成的上下文 Token 总量")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                
                // Metric 3: Avg Response Speed
                VStack(alignment: .leading, spacing: 4) {
                    Text("平均响应时延")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.2f", stats.avgResponseTime))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("秒")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    
                    Text("单次 API 调用的平均网络往返耗时")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                
                // Metric 4: Success Rate
                VStack(alignment: .leading, spacing: 4) {
                    Text("API 调用成功率")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f%%", stats.successRate))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(stats.successRate >= 95 ? Color.green : theme.secondaryHighlightColor)
                    }
                    
                    Text("代理转发且模型顺利响应的成功比例")
                        .font(.system(size: 7.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            
            // Model Preference Section
            VStack(alignment: .leading, spacing: 12) {
                Text("最常用大模型偏好")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.horizontal, 4)
                
                if topModels.isEmpty {
                    Text("暂无模型拦截记录")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 10) {
                        ForEach(topModels, id: \.name) { model in
                            VStack(spacing: 4) {
                                HStack {
                                    Text(model.name)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(model.count)次 (\(String(format: "%.0f%%", model.percentage * 100)))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(theme.secondaryHighlightColor)
                                }
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.04))
                                        Capsule()
                                            .fill(LinearGradient(
                                                colors: [theme.highlightColor, theme.secondaryHighlightColor],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ))
                                            .frame(width: geo.size.width * CGFloat(model.percentage))
                                            .shadow(color: theme.highlightColor.opacity(0.25), radius: 2, x: 0, y: 0)
                                    }
                                }
                                .frame(height: 3.5)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            
            // Developer Insight Panel
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.highlightColor)
                    Text("最活跃时段")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                    
                    // Dynamic Geek Title Badge
                    Text(geekTitle)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.highlightColor.opacity(0.15))
                        .foregroundStyle(theme.highlightColor)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4).stroke(theme.highlightColor.opacity(0.2), lineWidth: 0.5)
                        )
                    
                    Text(activeHourRange)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Divider().background(Color.white.opacity(0.08))
                
                HStack {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryHighlightColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("等效生产力产值")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text("AI 助力研发释放的估算等效价值")
                            .font(.system(size: 6.5))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    Spacer()
                    Text(estimatedValueSaved)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.02))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Bottom Tech Branding Footer
            HStack(spacing: 12) {
                // Pseudo Vector Tech QR-Code
                VStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<8, id: \.self) { col in
                                let isCorner = (row < 2 && col < 2) || (row < 2 && col > 5) || (row > 5 && col < 2)
                                let isRandomFill = ((row + col) % 3 == 0 || (row * col) % 5 == 1)
                                
                                Rectangle()
                                    .fill(isCorner ? theme.highlightColor : (isRandomFill ? Color.white.opacity(0.8) : Color.white.opacity(0.12)))
                                    .frame(width: 3, height: 3)
                            }
                        }
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AGENT BLACKBOX")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("本地大模型网关代理与调用监控总览")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text("github.com/zw6234336/Agent-Blackbox")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                
                Spacer()
                
                Text("CODE WITH AI")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .padding(4)
                    .border(Color.white.opacity(0.2), width: 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .frame(width: 480, height: 720)
        .background(theme.backgroundGradient)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Main Interactive Share Sheet Panel
struct SharePosterView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var database: DatabaseService
    
    @State private var userName: String = ""
    @State private var userSubtitle: String = "本地 AI 开发用量报告"
    @State private var selectedTheme: PosterTheme = .spaceGray
    @State private var selectedTimeRange: DashboardTimeRange = .week
    @State private var renderedImage: NSImage? = nil
    @State private var isCopySuccess = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Panel: Poster Image Preview
            VStack {
                if let image = renderedImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 480)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.4), radius: 15, x: 0, y: 8)
                } else {
                    ProgressView("海报渲染中...")
                        .frame(width: 320, height: 480)
                }
            }
            .frame(width: 380)
            .padding(24)
            .background(Color.black.opacity(0.25))
            
            Divider()
            
            // Right Panel: Form Controls & Customizations
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分享用量海报")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("以高清海报的形式分享您这段时间的大模型用量指标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Section 1: Data Source Settings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("数据源设置")
                                .font(.headline)
                            
                            Picker("分析时间维度", selection: $selectedTimeRange) {
                                ForEach(DashboardTimeRange.allCases, id: \.self) { range in
                                    Text(range.rawValue).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedTimeRange) { _, newValue in
                                triggerDataReload(range: newValue)
                            }
                        }
                        
                        // Section 2: Personalizations
                        VStack(alignment: .leading, spacing: 12) {
                            Text("海报文案设置")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("我的昵称")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("输入您的名字", text: $userName)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: userName) { _, _ in
                                        scheduleRender()
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("宣传副标题")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("例如：本地 AI 开发用量报告", text: $userSubtitle)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: userSubtitle) { _, _ in
                                        scheduleRender()
                                    }
                            }
                        }
                        
                        // Section 3: Color Themes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("海报视觉风格")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(PosterTheme.allCases) { theme in
                                    Button(action: {
                                        selectedTheme = theme
                                        scheduleRender()
                                    }) {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(theme.highlightColor)
                                                .frame(width: 12, height: 12)
                                            Text(theme.rawValue)
                                                .font(.body)
                                                .foregroundStyle(selectedTheme == theme ? .primary : .secondary)
                                            Spacer()
                                            if selectedTheme == theme {
                                                Image(systemName: "checkmark")
                                                    .font(.caption2)
                                                    .foregroundStyle(theme.highlightColor)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(selectedTheme == theme ? theme.highlightColor.opacity(0.1) : Color.white.opacity(0.04))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedTheme == theme ? theme.highlightColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
                
                Spacer()
                
                // Actions Area
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Copy Button
                        Button(action: copyToClipboard) {
                            HStack {
                                Image(systemName: isCopySuccess ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                Text(isCopySuccess ? "复制成功!" : "复制到剪贴板")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isCopySuccess ? Color.green : Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(renderedImage == nil)
                        
                        // Save Button
                        Button(action: saveImageToDisk) {
                            HStack {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("保存为图片")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.primary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(renderedImage == nil)
                    }
                    
                    Text("提示：海报将以 Retina (双倍缩放) 无损渲染，保证在微信/手机分享时依然保持完美的高清晰度。")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(width: 780, height: 520)
        .onAppear {
            // Default nickname to current login user or standard placeholder
            if userName.isEmpty {
                userName = NSFullUserName().isEmpty ? "AI 开发者" : NSFullUserName()
            }
            
            // Set initial range based on dashboard's range if active
            database.refreshDashboardStats(days: selectedTimeRange.dayValue)
            scheduleRender()
        }
    }
    
    // MARK: - Actions
    
    private func triggerDataReload(range: DashboardTimeRange) {
        database.refreshDashboardStats(days: range.dayValue)
        // Wait briefly for db stats update to publish before rendering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scheduleRender()
        }
    }
    
    private func scheduleRender() {
        renderedImage = nil
        // Debounce slightly to allow text field typing to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.renderPoster()
        }
    }
    
    @MainActor
    private func renderPoster() {
        let template = PosterTemplateView(
            stats: database.dashboardStats,
            timeRange: selectedTimeRange,
            userName: userName,
            userSubtitle: userSubtitle,
            theme: selectedTheme
        )
        
        let renderer = ImageRenderer(content: template)
        renderer.scale = 2.0 // High-DPI Retina scaling
        
        if let image = renderer.nsImage {
            self.renderedImage = image
        }
    }
    
    private func copyToClipboard() {
        guard let image = renderedImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        
        withAnimation {
            isCopySuccess = true
        }
        
        // Play standard success sound
        NSSound(named: "Glass")?.play()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopySuccess = false
            }
        }
    }
    
    private func saveImageToDisk() {
        guard let image = renderedImage else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Agent-Blackbox-\(selectedTimeRange.rawValue)-Poster.png"
        panel.title = "选择保存海报的位置"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        
        if panel.runModal() == .OK, let url = panel.url {
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try pngData.write(to: url)
                    NSSound(named: "Glass")?.play()
                } catch {
                    Logger.shared.error("海报图片保存失败: \(error.localizedDescription)")
                }
            }
        }
    }
}
