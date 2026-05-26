import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@MainActor
final class DesktopWidgetService: ObservableObject {
    @Published var isShowing = false
    private var window: NSPanel?
    
    func toggle(proxyServer: ProxyServerService) {
        if isShowing {
            hide()
        } else {
            show(proxyServer: proxyServer)
        }
    }
    
    func show(proxyServer: ProxyServerService) {
        guard window == nil else { return }
        
        let contentView = DesktopWidgetView(proxyServer: proxyServer)
        let hostingController = NSHostingController(rootView: contentView)
        
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 220, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingController.view
        
        // Position at the top right of the main screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - 240
            let y = screenRect.maxY - 90
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.orderFrontRegardless()
        self.window = panel
        self.isShowing = true
    }
    
    func hide() {
        window?.orderOut(nil)
        window = nil
        self.isShowing = false
    }
}

struct DesktopWidgetView: View {
    @ObservedObject var proxyServer: ProxyServerService
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        HStack(spacing: 12) {
            // Client Icon
            let lastClient = proxyServer.liveRequests.first?.client ?? "other"
            let clColor = clientColor(lastClient)
            
            ZStack {
                Circle()
                    .fill(clColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                
                Image(systemName: clientIcon(lastClient))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(clColor)
            }
            
            // Stats
            VStack(alignment: .leading, spacing: 2) {
                Text(clientDisplayName(lastClient))
                    .font(.system(size: 11, weight: .bold))
                
                HStack(spacing: 8) {
                    Text(liveRateString)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(rateColor)
                    
                    Text(todayRequestsString)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Heartbeat Pulse Wave (mini version)
            MiniPulseWaveView(isActive: proxyServer.liveRequests.contains(where: \.isPending))
                .frame(width: 50, height: 28)
        }
        .padding(.horizontal, 14)
        .frame(width: 220, height: 72)
        .background(VisualEffectView())
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
        )
    }
    
    private var liveRateString: String {
        // Calculate rate based on last 5 seconds
        let now = Date()
        let recent = proxyServer.liveRequests.filter { 
            !$0.isPending && $0.timestamp >= now.addingTimeInterval(-5) 
        }
        let totalTokens = recent.reduce(0) { $0 + ($1.promptTokens ?? 0) + ($1.completionTokens ?? 0) }
        let rate = Double(totalTokens) / 5.0
        
        if rate > 0 {
            return String(format: "%.0f T/s", rate)
        } else {
            return "待命中"
        }
    }
    
    private var rateColor: Color {
        let now = Date()
        let recent = proxyServer.liveRequests.filter { 
            !$0.isPending && $0.timestamp >= now.addingTimeInterval(-5) 
        }
        let totalTokens = recent.reduce(0) { $0 + ($1.promptTokens ?? 0) + ($1.completionTokens ?? 0) }
        return totalTokens > 0 ? Color.blue : Color.secondary
    }
    
    private var todayRequestsString: String {
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        
        // Sum tokens from liveRequests for today (fallback aggregation)
        let todayRequests = proxyServer.liveRequests.filter { 
            $0.timestamp >= startOfDay 
        }
        let totalTokens = todayRequests.reduce(0) { $0 + ($1.promptTokens ?? 0) + ($1.completionTokens ?? 0) }
        return "\(todayRequests.count)次 | \(totalTokens.formattedCompact) T"
    }
    
    private func clientIcon(_ client: String) -> String {
        switch client.lowercased() {
        case "pi": return "bubble.left.and.bubble.right.fill"
        case "cline": return "terminal.fill"
        case "claude-code": return "apple.terminal.fill"
        case "cursor": return "cursorarrow.rays"
        case "copilot": return "airplane"
        default: return "network"
        }
    }
    
    private func clientDisplayName(_ client: String) -> String {
        switch client.lowercased() {
        case "pi": return "Pi Agent"
        case "cline": return "Cline"
        case "claude-code": return "Claude Code"
        case "cursor": return "Cursor"
        case "copilot": return "Copilot"
        default: return "AI 网关"
        }
    }
    
    private func clientColor(_ client: String) -> Color {
        switch client.lowercased() {
        case "pi": return Color.pink
        case "cline": return Color.orange
        case "claude-code": return Color.green
        case "cursor": return Color.purple
        case "copilot": return Color.blue
        default: return Color.gray
        }
    }
}

struct MiniPulseWaveView: View {
    let isActive: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // See PulseWaveView for the rationale: a long-running
        // `TimelineView(.animation)` mounted in the app for hours can
        // break trackpad/scroll-wheel event delivery to SwiftUI
        // ScrollViews app-wide. Throttle to 24 Hz when active and
        // render a static frame otherwise.
        if isActive && scenePhase == .active {
            TimelineView(.periodic(from: Date(), by: 1.0 / 24.0)) { timeline in
                waveCanvas(date: timeline.date)
            }
        } else {
            waveCanvas(date: Date(timeIntervalSinceReferenceDate: 0))
        }
    }
    
    private func waveCanvas(date: Date) -> some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let midY = height / 2.0
            
            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))
            
            let time = date.timeIntervalSinceReferenceDate
            let freq: CGFloat = isActive ? 0.15 : 0.04
            let amp: CGFloat = isActive ? 6.0 : 1.0
            let speed: CGFloat = isActive ? 12.0 : 2.0
            
            for x in stride(from: 0, to: width, by: 1.5) {
                let relativeX = x / width
                let fade = sin(relativeX * .pi)
                let y = midY + sin(x * freq - CGFloat(time) * speed) * amp * fade
                path.addLine(to: CGPoint(x: x, y: y))
            }
            
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: isActive ? [.blue, .purple, .pink] : [.secondary.opacity(0.2)]),
                    startPoint: CGPoint(x: 0, y: midY),
                    endPoint: CGPoint(x: width, y: midY)
                ),
                style: StrokeStyle(lineWidth: isActive ? 1.5 : 0.8, lineCap: .round)
            )
        }
    }
}
