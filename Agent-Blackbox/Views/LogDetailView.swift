import SwiftUI
import UniformTypeIdentifiers


struct LogDetailView: View {
    let log: ParsedLog
    var isModal: Bool = false
    @EnvironmentObject var database: DatabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var editingNotes = false
    @State private var notesText = ""
    @State private var newTag = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with actions
                headerSection
                
                // Info card
                infoSection
                
                // Token breakdown
                if log.promptTokens != nil || log.completionTokens != nil || log.totalTokens != nil {
                    tokenSection
                }

                // Prompt
                if let prompt = log.prompt {
                    LogContentSectionView(title: "Prompt", content: prompt, icon: "text.bubble", color: .infoBlue)
                }

                // Response with thinking extraction
                if let response = log.response {
                    let parsed = parseThinkingAndResponse(text: response)
                    
                    if let thinking = parsed.thinking {
                        LogContentSectionView(
                            title: "AI 深度思考过程 (Thinking)",
                            content: thinking,
                            icon: "brain",
                            color: .orange,
                            isCollapsible: true
                        )
                    }
                    
                    if !parsed.cleanResponse.isEmpty {
                        LogContentSectionView(
                            title: "Response / 输出",
                            content: parsed.cleanResponse,
                            icon: "text.bubble.fill",
                            color: .successGreen
                        )
                    }
                }

                // Error
                if let error = log.errorMessage {
                    GroupBox {
                        VStack(alignment: .leading) {
                            Label("错误信息", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.errorRed)
                                .font(.headline)
                            Text(error)
                                .textSelection(.enabled)
                                .foregroundColor(Color.errorRed)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // Tags
                tagsSection

                // Notes
                notesSection

                // Metadata
                if !log.metadata.isEmpty {
                    GroupBox("元数据") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(log.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack {
                                    Text(key)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text(value)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .scrollWheelKeepAlive()
        .textSelection(.enabled)
        .onAppear {
            if isModal {
                NSApp.activate(ignoringOtherApps: true)
            }
            notesText = log.notes ?? ""
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            if let provider = log.provider {
                Image(systemName: provider.iconName)
                    .font(.title2)
                    .foregroundStyle(provider.brandColor)
            }
            
            VStack(alignment: .leading) {
                Text(log.modelName ?? "Unknown Model")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(log.provider?.displayName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    Task { await database.toggleBookmark(logId: log.id) }
                }) {
                    Image(systemName: log.isBookmarked ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(log.isBookmarked ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(log.isBookmarked ? "取消收藏" : "收藏")
                
                // Add to collection menu
                Menu {
                    ForEach(database.collections) { collection in
                        Button(collection.name) {
                            database.addToCollection(logId: log.id, collectionId: collection.id)
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("添加到收藏夹")

                Button(action: exportMarkdownReport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("导出 AI 编程思维复盘报告 (.md)")

                if isModal {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭")
                }
            }
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        GroupBox("信息") {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "模型", value: log.modelName ?? "N/A")
                InfoRow(label: "提供商", value: log.provider?.displayName ?? "N/A")
                InfoRow(label: "时间", value: log.timestamp.formatted())
                InfoRow(label: "文件", value: log.sourceFile)
                if let duration = log.duration {
                    InfoRow(label: "耗时", value: duration.formattedDuration)
                }
                if let statusCode = log.statusCode {
                    InfoRow(label: "状态码", value: "\(statusCode)")
                }
                if let convId = log.conversationId {
                    InfoRow(label: "对话ID", value: convId)
                }
            }
        }
    }
    
    // MARK: - Token Section
    
    private var tokenSection: some View {
        GroupBox("Token 使用") {
            HStack(spacing: 20) {
                if let pt = log.promptTokens {
                    tokenMetric(label: "Input", value: pt, color: .infoBlue)
                }
                if let ct = log.completionTokens {
                    tokenMetric(label: "Output", value: ct, color: .accentGradientStart)
                }
                if let total = log.totalTokens {
                    tokenMetric(label: "总计", value: total, color: .primary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func tokenMetric(label: String, value: Int, color: Color) -> some View {
        VStack {
            Text(value.formattedCompact)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Content Section

    struct LogContentSectionView: View {
        let title: String
        let content: String
        let icon: String
        let color: Color
        var isCollapsible: Bool = false
        
        @State private var isCollapsed: Bool = true
        @State private var isCopied = false
        
        var body: some View {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Label(title, systemImage: icon)
                                .font(.headline)
                                .foregroundStyle(color)
                            
                            if isCollapsible {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isCollapsible {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isCollapsed.toggle()
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                            isCopied = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isCopied = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                                    .foregroundStyle(isCopied ? .green : .secondary)
                                if isCopied {
                                    Text("已复制")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("复制")
                    }
                    
                    if !isCollapsible || !isCollapsed {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Text("点击展开查看 \(content.count) 字符的完整内容...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isCollapsed = false
                                }
                            }
                    }
                }
            }
        }
    }
    
    // MARK: - Tags Section
    
    private var tagsSection: some View {
        GroupBox("标签") {
            VStack(alignment: .leading, spacing: 8) {
                FlowLayout(spacing: 6) {
                    ForEach(log.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.caption)
                            Button(action: {
                                let newTags = log.tags.filter { $0 != tag }
                                Task { await database.updateTags(logId: log.id, newTags: newTags) }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentGradientStart.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                
                HStack {
                    TextField("添加标签...", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit {
                            addTag()
                        }
                    Button("添加", action: addTag)
                        .disabled(newTag.isEmpty)
                }
            }
        }
    }
    
    private func addTag() {
        guard !newTag.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var newTags = log.tags
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        if !newTags.contains(tag) {
            newTags.append(tag)
            Task { await database.updateTags(logId: log.id, newTags: newTags) }
        }
        newTag = ""
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        GroupBox("备注") {
            VStack(alignment: .leading) {
                TextEditor(text: $notesText)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                if notesText != (log.notes ?? "") {
                    Button("保存备注") {
                        Task { await database.updateNotes(logId: log.id, text: notesText) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func parseThinkingAndResponse(text: String) -> (thinking: String?, cleanResponse: String) {
        if text.contains("<think>") {
            let parts = text.components(separatedBy: "<think>")
            if parts.count > 1 {
                let subParts = parts[1].components(separatedBy: "</think>")
                let thinking = subParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let remaining = subParts.dropFirst().joined(separator: "</think>").trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanResponse: String
                let prefix = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    cleanResponse = prefix + "\n\n" + remaining
                } else {
                    cleanResponse = remaining
                }
                return (thinking.isEmpty ? nil : thinking, cleanResponse)
            }
        }
        
        if text.contains("[Thinking]") || text.contains("[thinking]") {
            let keyword = text.contains("[Thinking]") ? "[Thinking]" : "[thinking]"
            let parts = text.components(separatedBy: keyword)
            if parts.count > 1 {
                let nextPart = parts[1]
                let responseKeyword = nextPart.contains("[Response]") ? "[Response]" : (nextPart.contains("[response]") ? "[response]" : nil)
                if let respKeyword = responseKeyword {
                    let subParts = nextPart.components(separatedBy: respKeyword)
                    let thinking = subParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let remaining = subParts.dropFirst().joined(separator: respKeyword).trimmingCharacters(in: .whitespacesAndNewlines)
                    let prefix = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanResponse = prefix.isEmpty ? remaining : (prefix + "\n\n" + remaining)
                    return (thinking.isEmpty ? nil : thinking, cleanResponse)
                } else {
                    let clean = text.replacingOccurrences(of: keyword, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return (clean.isEmpty ? nil : clean, "")
                }
            }
        }
        
        return (nil, text)
    }

    private func exportMarkdownReport() {
        let savePanel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            savePanel.allowedContentTypes = [markdownType]
        } else {
            savePanel.allowedContentTypes = [.plainText]
        }
        savePanel.nameFieldStringValue = "AI-Report-\(log.modelName ?? "Model")-\(log.timestamp.formattedFileSuffix).md"
        savePanel.title = "导出 AI 编程思维复盘报告"
        savePanel.message = "请选择报告的保存位置"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                let markdownContent = generateMarkdownReport()
                do {
                    try markdownContent.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    // Log error
                }
            }
        }
    }
    
    private func generateMarkdownReport() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        
        let parsed = parseThinkingAndResponse(text: log.response ?? "")
        
        var report = """
        # AI 编程思维复盘报告
        
        本报告由 **Agent-Blackbox** 自动生成，为您提取了 LLM 与机器对话中的核心思考过程与交互。
        
        ---
        
        ## 📊 基本元数据
        - **调用时间**: \(formatter.string(from: log.timestamp))
        - **大模型名称**: `\(log.modelName ?? "Unknown Model")`
        - **服务提供商**: \(log.provider?.displayName ?? "N/A")
        - **耗时**: \(log.duration.map { String(format: "%.2f 秒", $0) } ?? "N/A")
        - **Token 消耗**: 输入 `\(log.promptTokens ?? 0)` | 输出 `\(log.completionTokens ?? 0)` | 总计 `\(log.totalTokens ?? 0)`
        - **请求源文件/场景**: `\(log.sourceFile)`
        
        ---
        
        """
        
        if let prompt = log.prompt {
            report += """
            ## 📥 用户输入 (Prompt)
            ```text
            \(prompt)
            ```
            
            ---
            
            """
        }
        
        if let thinking = parsed.thinking {
            report += """
            ## 💡 AI 深度思考轨迹 (Thinking Process)
            > **提示**：以下是拦截并提取到的 AI 思维链，展现了模型在给出最终代码或回答前的内部逻辑演练、步骤分解与安全研判。
            
            ```text
            \(thinking)
            ```
            
            ---
            
            """
        }
        
        if !parsed.cleanResponse.isEmpty {
            report += """
            ## 📤 最终生成输出 (Response)
            
            \(parsed.cleanResponse)
            
            """
        }
        
        report += "\n---\n*报告生成工具：Agent-Blackbox — 为开发者保留最有价值的 AI 对话与思考足迹。*\n"
        return report
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxHeight = max(maxHeight, y + size.height)
        }
        
        return (CGSize(width: maxWidth, height: maxHeight), positions)
    }
}

// MARK: - Date Extension

extension Date {
    var formattedFileSuffix: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: self)
    }
}
