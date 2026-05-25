import SwiftUI

struct CompilationView: View {
    @EnvironmentObject var compilationService: CompilationService
    @EnvironmentObject var database: DatabaseService
    @State private var selectedCompilation: LogCompilation?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                .background(Color(nsColor: NSColor.windowBackgroundColor))
            
            Divider()
            
            Group {
                if let comp = selectedCompilation {
                    detailView(comp)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dashboardBackground)
        }
        .onAppear {
            compilationService.initializeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SelectCompilation"))) { notification in
            if let comp = notification.object as? LogCompilation {
                self.selectedCompilation = comp
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("日志编译")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            List(selection: Binding(
                get: { selectedCompilation?.id },
                set: { newId in
                    selectedCompilation = newId.flatMap { id in
                        compilationService.compilations.first { $0.id == id }
                    }
                }
            )) {
                Section("编译列表") {
                    ForEach(compilationService.compilations) { comp in
                        CompilationListRow(compilation: comp)
                            .tag(comp.id)
                            .contextMenu {
                                if comp.status == .completed {
                                    Button {
                                        compilationService.appendNewLogs(id: comp.id)
                                    } label: {
                                        Label("追加新日志", systemImage: "plus.circle")
                                    }

                                    Button {
                                        compilationService.revealInFinder(id: comp.id)
                                    } label: {
                                        Label("在 Finder 中显示", systemImage: "folder")
                                    }

                                    Button {
                                        compilationService.copyToClipboard(id: comp.id)
                                    } label: {
                                        Label("复制内容", systemImage: "doc.on.doc")
                                    }
                                }

                                if comp.status == .paused {
                                    Button {
                                        compilationService.resumeGeneration(id: comp.id)
                                    } label: {
                                        Label("恢复生成", systemImage: "play.fill")
                                    }
                                }

                                if comp.status == .generating {
                                    Button {
                                        compilationService.pauseGeneration(id: comp.id)
                                    } label: {
                                        Label("暂停", systemImage: "pause.fill")
                                    }

                                    Button(role: .destructive) {
                                        compilationService.cancelGeneration(id: comp.id)
                                    } label: {
                                        Label("取消", systemImage: "xmark.circle")
                                    }
                                }

                                Divider()

                                Button(role: .destructive) {
                                    compilationService.deleteCompilation(id: comp.id)
                                    if selectedCompilation?.id == comp.id {
                                        selectedCompilation = nil
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            Button(action: {
                Task {
                    let providers = await database.fetchDistinctProviders()
                    NotificationCenter.default.post(name: Notification.Name("ShowNewCompilationSheet"), object: providers)
                }
            }) {
                Label("新建编译", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.append")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("日志编译")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("将收集的日志按供应商和时间整理成可读文档\n支持 Markdown、JSON、纯文本格式")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("新建编译") {
                Task {
                    let providers = await database.fetchDistinctProviders()
                    NotificationCenter.default.post(name: Notification.Name("ShowNewCompilationSheet"), object: providers)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail View

    private func detailView(_ comp: LogCompilation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection(comp)

                // Status + Actions
                statusSection(comp)

                // Stats
                if comp.status == .completed {
                    statsSection(comp)
                }

                // Preview
                if comp.status == .completed && comp.outputFilePath != nil {
                    previewSection(comp)
                }
            }
            .padding()
        }
        .onChange(of: compilationService.compilations) {
            // Refresh selected when compilations update
            if let sel = selectedCompilation,
               let updated = compilationService.compilations.first(where: { $0.id == sel.id }) {
                selectedCompilation = updated
            }
        }
    }

    // MARK: - Header

    private func headerSection(_ comp: LogCompilation) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(comp.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if !comp.description.isEmpty {
                    Text(comp.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if !comp.providerFilters.isEmpty {
                        ForEach(comp.providerFilters, id: \.self) { raw in
                            if let provider = LLMProvider(rawValue: raw) {
                                Text(provider.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(provider.brandColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text("全部供应商")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    if let start = comp.startDate {
                        Text(start.formattedDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("至")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let end = comp.endDate {
                        Text(end.formattedDate)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if comp.bookmarkedOnly {
                        Text("仅收藏")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text("格式: \(comp.outputFormat.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Status + Actions

    private func statusSection(_ comp: LogCompilation) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    CompilationStatusBadge(status: comp.status)
                    Spacer()

                    if let msg = comp.progressMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress bar
                if comp.status == .generating || comp.status == .paused {
                    ProgressView(value: comp.progress, total: 1.0) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(Int(comp.progress * 100))%")
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .tint(comp.status == .paused ? .warningOrange : .infoBlue)
                }

                // Action buttons
                HStack(spacing: 10) {
                    if comp.status == .pending || comp.status == .paused {
                        Button {
                            compilationService.startGeneration(id: comp.id)
                        } label: {
                            Label(comp.status == .paused ? "恢复" : "开始生成", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if comp.status == .generating {
                        Button {
                            compilationService.pauseGeneration(id: comp.id)
                        } label: {
                            Label("暂停", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            compilationService.cancelGeneration(id: comp.id)
                        } label: {
                            Label("取消", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if comp.status == .completed {
                        Button {
                            compilationService.appendNewLogs(id: comp.id)
                        } label: {
                            Label("追加新日志", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            compilationService.revealInFinder(id: comp.id)
                        } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            compilationService.copyToClipboard(id: comp.id)
                        } label: {
                            Label("复制内容", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        compilationService.deleteCompilation(id: comp.id)
                        selectedCompilation = nil
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Stats

    private func statsSection(_ comp: LogCompilation) -> some View {
        let providerCount = comp.compiledProviders.compactMap { LLMProvider(rawValue: $0) }.count
        let modelCount = comp.compiledModels.count

        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("统计")
                    .font(.headline)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    CompilationStatCard(
                        title: "日志条数",
                        value: "\(comp.totalLogCount)",
                        icon: "doc.text",
                        color: .infoBlue
                    )
                    CompilationStatCard(
                        title: "总 Token",
                        value: comp.compiledTokenTotal.formattedCompact,
                        icon: "textformat.abc",
                        color: .accentGradientStart
                    )
                    CompilationStatCard(
                        title: "供应商 / 模型",
                        value: "\(providerCount) / \(modelCount)",
                        icon: "cpu",
                        color: .warningOrange
                    )
                }
            }
        }
    }

    // MARK: - Preview

    private func previewSection(_ comp: LogCompilation) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("内容预览", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)

                    Spacer()

                    if let size = comp.outputFileSize {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let content = compilationService.getOutputPreview(for: comp) {
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 400)
                } else {
                    Text("无法读取输出文件")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct NewCompilationDraft {
    var name = ""
    var description = ""
    var format: CompilationOutputFormat = .markdown
    var providers: Set<String> = []
    var hasStartDate = false
    var hasEndDate = false
    var startDate = Date().addingTimeInterval(-7 * 86400)
    var endDate = Date()
    var bookmarkedOnly = false
}

struct NewCompilationSheet: View {
    let availableProviders: [LLMProvider]
    let onCancel: () -> Void
    let onCreate: (NewCompilationDraft) -> Void

    @State private var draft = NewCompilationDraft()
    @State private var shouldFocusNameField = false

    var body: some View {
        VStack(spacing: 14) {
            Text("新建编译")
                .font(.headline)

            AppKitTextField(
                placeholder: "名称",
                text: $draft.name,
                shouldFocus: shouldFocusNameField
            )

            AppKitTextField(
                placeholder: "描述（可选）",
                text: $draft.description
            )

            HStack {
                Text("输出格式")
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: $draft.format) {
                    ForEach(CompilationOutputFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("供应商筛选")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                FlowLayout(spacing: 6) {
                    ForEach(availableProviders, id: \.rawValue) { provider in
                        FilterChip(
                            label: provider.displayName,
                            isSelected: draft.providers.contains(provider.rawValue),
                            color: provider.brandColor
                        ) {
                            if draft.providers.contains(provider.rawValue) {
                                draft.providers.remove(provider.rawValue)
                            } else {
                                draft.providers.insert(provider.rawValue)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Toggle("起始日期", isOn: $draft.hasStartDate)
                    .toggleStyle(.checkbox)
                if draft.hasStartDate {
                    DatePicker("", selection: $draft.startDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            HStack {
                Toggle("截止日期", isOn: $draft.hasEndDate)
                    .toggleStyle(.checkbox)
                if draft.hasEndDate {
                    DatePicker("", selection: $draft.endDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            Toggle("仅收藏日志", isOn: $draft.bookmarkedOnly)
                .toggleStyle(.checkbox)

            Spacer(minLength: 8)

            HStack {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("创建") {
                    onCreate(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 480)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                shouldFocusNameField = true
            }
        }
        .onDisappear {
            shouldFocusNameField = false
        }
    }
}
