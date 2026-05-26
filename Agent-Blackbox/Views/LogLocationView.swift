import SwiftUI

// MARK: - Main View

struct LogLocationView: View {
    @EnvironmentObject var database: DatabaseService
    @State private var selectedFilePath: String?
    @State private var selectedLog: ParsedLog?

    // Group logs by directory → files
    private var directoryGroups: [(directory: String, files: [(path: String, logs: [ParsedLog])])] {
        let byDir = Dictionary(grouping: database.logs) { log in
            URL(fileURLWithPath: log.sourceFile).deletingLastPathComponent().path
        }
        return byDir
            .sorted { $0.key < $1.key }
            .map { dir, logs in
                let byFile = Dictionary(grouping: logs, by: \.sourceFile)
                let files = byFile
                    .sorted { $0.key < $1.key }
                    .map { (path: $0.key, logs: $0.value.sorted { $0.timestamp > $1.timestamp }) }
                return (directory: dir, files: files)
            }
    }

    private var logsForSelectedFile: [ParsedLog] {
        guard let file = selectedFilePath else { return [] }
        return database.logs
            .filter { $0.sourceFile == file }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationSplitView {
            // Column 1: directory / file tree
            List(selection: $selectedFilePath) {
                if directoryGroups.isEmpty {
                    Text("暂无日志文件")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(directoryGroups, id: \.directory) { group in
                        Section {
                            ForEach(group.files, id: \.path) { file in
                                FileLocationRow(
                                    filePath: file.path,
                                    logCount: file.logs.count,
                                    latestDate: file.logs.first?.timestamp
                                )
                                .tag(file.path)
                            }
                        } header: {
                            Label(
                                URL(fileURLWithPath: group.directory).lastPathComponent,
                                systemImage: "folder"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("日志位置")
        } content: {
            // Column 2: log timeline for selected file
            if logsForSelectedFile.isEmpty {
                LocationPlaceholder(icon: "doc.text.magnifyingglass", message: "从左侧选择日志文件")
            } else {
                List(logsForSelectedFile, selection: $selectedLog) { log in
                    LogTimelineRow(log: log)
                        .tag(log)
                }
                .navigationTitle(
                    selectedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                )
            }
        } detail: {
            // Column 3: interaction detail (chat bubbles)
            if let log = selectedLog {
                InteractionView(log: log)
            } else {
                LocationPlaceholder(icon: "bubble.left.and.bubble.right", message: "选择日志查看 AI 交互")
            }
        }
        .task {
            await database.reloadLogs()
        }
        .onChange(of: selectedFilePath) {
            selectedLog = nil
        }
    }
}

// MARK: - Placeholder

private struct LocationPlaceholder: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Location Row

struct FileLocationRow: View {
    let filePath: String
    let logCount: Int
    let latestDate: Date?

    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    private var fileIcon: String {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "json": return "doc.text.fill"
        case "log":  return "text.alignleft"
        default:     return "doc"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon)
                .foregroundColor(.accentColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.body)
                    .lineLimit(1)
                if let date = latestDate {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("\(logCount)")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log Timeline Row

struct LogTimelineRow: View {
    let log: ParsedLog

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: log.errorMessage != nil ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(log.errorMessage != nil ? .red : .green)
                    .font(.caption)
                Text(log.modelName ?? "Unknown Model")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(log.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let prompt = log.prompt {
                Text(prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            if let tokens = log.tokensUsed {
                Text("Tokens: \(tokens)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Interaction View

struct InteractionView: View {
    let log: ParsedLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.modelName ?? "Unknown Model")
                            .font(.headline)
                        Text(log.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let tokens = log.tokensUsed {
                        Label("\(tokens) tokens", systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()

                Divider()
                    .padding(.horizontal)

                // Chat bubbles
                VStack(spacing: 16) {
                    if let prompt = log.prompt {
                        ChatBubbleView(text: prompt, role: .user)
                    }
                    if let response = log.response {
                        ChatBubbleView(text: response, role: .assistant)
                    }
                    if let error = log.errorMessage {
                        ErrorBubbleView(message: error)
                    }
                    if log.prompt == nil && log.response == nil && log.errorMessage == nil {
                        Text("无交互内容")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding()
            }
        }
        .scrollWheelKeepAlive()
        .navigationTitle("交互详情")
    }
}

// MARK: - Chat Bubble

/// Identifies which participant sent a message in an AI conversation.
/// Use `.user` for the human prompt and `.assistant` for the AI response.
enum ChatRole {
    case user, assistant
}

struct ChatBubbleView: View {
    let text: String
    let role: ChatRole

    private var isUser: Bool { role == .user }
    private var alignment: HorizontalAlignment { isUser ? .trailing : .leading }
    private var frameAlignment: Alignment { isUser ? .trailing : .leading }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 4) {
                if !isUser {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(isUser ? "用户" : "AI 助手")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isUser {
                    Image(systemName: "person.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)

            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? Color.blue.opacity(0.12)
                        : Color(NSColor.controlBackgroundColor)
                )
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isUser
                                ? Color.blue.opacity(0.25)
                                : Color.secondary.opacity(0.2)
                        )
                )
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }
}

// MARK: - Error Bubble

struct ErrorBubbleView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                Text("错误")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Text(message)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red.opacity(0.3))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
