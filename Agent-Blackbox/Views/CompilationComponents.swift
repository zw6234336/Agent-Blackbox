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
        case .generating: return Color.infoBlue
        case .paused:     return Color.warningOrange
        case .completed:  return Color.successGreen
        case .cancelled:  return Color.errorRed
        }
    }
}

// MARK: - Compilation List Row

struct CompilationListRow: View {
    let compilation: LogCompilation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.append")
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

// MARK: - Stat Card

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
