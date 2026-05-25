import SwiftUI

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
                    contentSection(title: "Prompt", content: prompt, icon: "text.bubble", color: .infoBlue)
                }

                // Response
                if let response = log.response {
                    contentSection(title: "Response", content: response, icon: "text.bubble.fill", color: .successGreen)
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
                }
                .help("添加到收藏夹")

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
    
    private func contentSection(title: String, content: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(color)
                    
                    Spacer()
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("复制")
                }
                
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
