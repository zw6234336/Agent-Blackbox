import SwiftUI

// MARK: - Status Badge

struct CompilationStatusBadge: View {
    let status: CompilationStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .pending:    return .secondary
        case .generating: return .infoBlue
        case .paused:     return .warningOrange
        case .completed:  return .successGreen
        case .cancelled:  return .errorRed
        }
    }
}

// MARK: - Compilation List Row

struct CompilationListRow: View {
    let compilation: LogCompilation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.append")
                .foregroundStyle(Color.accentGradientStart)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(compilation.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(compilation.totalLogCount) 条")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if compilation.appendCount > 0 {
                        Text("追加×\(compilation.appendCount)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !compilation.providerFilters.isEmpty {
                        let names = compilation.providerFilters.compactMap { LLMProvider(rawValue: $0)?.displayName }
                        Text(names.prefix(3).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            CompilationStatusBadge(status: compilation.status)

            if compilation.status == .generating {
                Text("\(Int(compilation.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(Color.infoBlue)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New Compilation Sheet

struct NewCompilationSheet: View {
    @EnvironmentObject var database: DatabaseService
    let onCreate: (LogCompilation) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var outputFormat: CompilationOutputFormat = .markdown
    @State private var selectedProviders: Set<String> = []
    @State private var startDate = Date().addingTimeInterval(-7 * 86400)
    @State private var endDate = Date()
    @State private var hasStartDate = false
    @State private var hasEndDate = false
    @State private var bookmarkedOnly = false
    @State private var availableProviders: [LLMProvider] = []
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, description
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("新建编译")
                .font(.headline)

            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)

            TextField("描述（可选）", text: $description)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .description)

            // Output format
            HStack {
                Text("输出格式")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $outputFormat) {
                    ForEach(CompilationOutputFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Provider filter
            VStack(alignment: .leading, spacing: 6) {
                Text("供应商筛选")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                FlowLayout(spacing: 6) {
                    ForEach(availableProviders, id: \.rawValue) { provider in
                        FilterChip(
                            label: provider.displayName,
                            isSelected: selectedProviders.contains(provider.rawValue),
                            color: provider.brandColor
                        ) {
                            if selectedProviders.contains(provider.rawValue) {
                                selectedProviders.remove(provider.rawValue)
                            } else {
                                selectedProviders.insert(provider.rawValue)
                            }
                        }
                    }
                }
            }

            // Date range
            HStack {
                Toggle("起始日期", isOn: $hasStartDate)
                    .toggleStyle(.checkbox)
                if hasStartDate {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            HStack {
                Toggle("截止日期", isOn: $hasEndDate)
                    .toggleStyle(.checkbox)
                if hasEndDate {
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }

            Toggle("仅收藏日志", isOn: $bookmarkedOnly)
                .toggleStyle(.checkbox)

            Spacer()

            HStack {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("创建") {
                    let comp = LogCompilation(
                        name: name,
                        description: description,
                        outputFormat: outputFormat,
                        providerFilters: selectedProviders.map { $0 },
                        startDate: hasStartDate ? startDate : nil,
                        endDate: hasEndDate ? endDate : nil,
                        bookmarkedOnly: bookmarkedOnly
                    )
                    onCreate(comp)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 480)
        .onAppear {
            availableProviders = database.fetchDistinctProviders()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .name
            }
        }
    }
}

// MARK: - Stat Card (reused for compilation detail)

struct CompilationStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15)))
    }
}
