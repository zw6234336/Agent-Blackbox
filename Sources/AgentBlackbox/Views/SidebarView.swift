import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: Binding<Set<LLMPlatform>>(
            get: { appState.selectedPlatforms },
            set: { appState.selectedPlatforms = $0 }
        )) {
            Section("Platforms") {
                ForEach(LLMPlatform.allCases) { platform in
                    HStack(spacing: 8) {
                        Image(systemName: platform.iconName)
                            .foregroundColor(color(for: platform))
                            .frame(width: 18)
                        Text(platform.displayName)
                        Spacer()
                        let count = appState.logEntries.filter { $0.platform == platform }.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption)
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .tag(platform)
                }
            }

            Section {
                Button {
                    appState.exportLogs()
                } label: {
                    Label("Export Logs…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    appState.clearAllLogs()
                } label: {
                    Label("Clear All Logs", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 190)
    }

    private func color(for platform: LLMPlatform) -> Color {
        switch platform.colorName {
        case "orange":  return .orange
        case "blue":    return .blue
        case "green":   return .green
        case "indigo":  return .indigo
        case "purple":  return .purple
        case "pink":    return .pink
        case "gray":    return .gray
        case "cyan":    return .cyan
        case "red":     return .red
        case "teal":    return .teal
        default:        return .secondary
        }
    }
}
