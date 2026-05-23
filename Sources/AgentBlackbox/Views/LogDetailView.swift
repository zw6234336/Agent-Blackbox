import SwiftUI

struct LogDetailView: View {
    let entry: LogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                if let prompt = entry.prompt, !prompt.isEmpty {
                    LogSection(title: "Prompt", icon: "text.bubble", content: prompt)
                }
                if let response = entry.response, !response.isEmpty {
                    LogSection(title: "Response", icon: "bubble.left.and.bubble.right", content: response)
                }
                sourceFile
                if !entry.metadata.isEmpty { metadataSection }
                rawSection
            }
            .padding()
        }
        .navigationTitle("Log Detail")
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: entry.platform.iconName)
                        .font(.title2)
                    Text(entry.platform.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if let model = entry.model, !model.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(model)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                Text(entry.timestamp.formatted(date: .complete, time: .complete))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !entry.tokenSummary.isEmpty {
                tokenBadge
            }
        }
    }

    private var tokenBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(entry.tokenSummary)
                .font(.caption)
                .fontWeight(.medium)
            if let input = entry.inputTokens, let output = entry.outputTokens {
                HStack(spacing: 8) {
                    Label("\(input)",  systemImage: "arrow.up.circle")
                    Label("\(output)", systemImage: "arrow.down.circle")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var sourceFile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Source File", systemImage: "doc")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(entry.filePath)
                .font(.caption)
                .textSelection(.enabled)
                .foregroundColor(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Metadata", systemImage: "info.circle")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            ForEach(entry.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 8) {
                    Text(key)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 120, alignment: .leading)
                    Text(value)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private var rawSection: some View {
        DisclosureGroup("Raw Content") {
            Text(entry.rawContent)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
        }
        .padding(.top, 4)
    }
}

// MARK: - Reusable section

struct LogSection: View {
    let title: String
    let icon: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07))
                .cornerRadius(8)
        }
    }
}
