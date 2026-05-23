import SwiftUI

// MARK: - StatusIndicator (legacy compatibility)
struct StatusIndicator: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
            Text(isActive ? "监控中" : "未监控")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - LogEntryRow
struct LogEntryRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForFile(url))
                .font(.caption)
                .foregroundStyle(colorForFile(url))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // File size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iconForFile(_ url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("cursor") { return "cursorarrow.rays" }
        if path.contains("claude") { return "bubble.left.fill" }
        if path.contains("ollama") { return "desktopcomputer" }
        if path.contains("copilot") { return "airplane" }
        if path.contains("cline") || path.contains("claude-dev") { return "terminal" }
        return "doc.text"
    }

    private func colorForFile(_ url: URL) -> Color {
        let path = url.path.lowercased()
        if path.contains("cursor") { return LLMProvider.cursor.brandColor }
        if path.contains("claude") { return LLMProvider.claudeDesktop.brandColor }
        if path.contains("ollama") { return LLMProvider.ollama.brandColor }
        if path.contains("copilot") { return LLMProvider.copilot.brandColor }
        if path.contains("cline") { return LLMProvider.cline.brandColor }
        return .secondary
    }
}

// MARK: - InfoRow
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
                .font(.subheadline)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - FilterChip
struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.2) : Color.primary.opacity(0.05))
            .foregroundStyle(isSelected ? color : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
