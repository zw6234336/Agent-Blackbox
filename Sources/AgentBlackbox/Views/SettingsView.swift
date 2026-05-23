import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlatform: LLMPlatform = .claude

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            TabView {
                platformsTab
                    .tabItem { Label("Platforms", systemImage: "cpu") }

                watchPathsTab
                    .tabItem { Label("Watch Paths", systemImage: "folder") }

                generalTab
                    .tabItem { Label("General", systemImage: "gear") }
            }
            .padding()
        }
        .frame(width: 540, height: 500)
    }

    // MARK: - Platforms tab

    private var platformsTab: some View {
        Form {
            Section("Enabled Platforms") {
                ForEach(LLMPlatform.allCases) { platform in
                    Toggle(isOn: Binding(
                        get: { appState.selectedPlatforms.contains(platform) },
                        set: { on in
                            if on { appState.selectedPlatforms.insert(platform) }
                            else  { appState.selectedPlatforms.remove(platform) }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: platform.iconName)
                                .frame(width: 20)
                            Text(platform.displayName)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Watch paths tab

    private var watchPathsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Platform", selection: $selectedPlatform) {
                ForEach(LLMPlatform.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.menu)

            let paths = appState.customWatchPaths[selectedPlatform]
                     ?? selectedPlatform.defaultWatchPaths

            List {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        let exists = FileManager.default.fileExists(atPath: path)
                        Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(exists ? .green : .secondary)
                            .help(exists ? "Directory exists" : "Directory not found")
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Text("Green ✓ = directory found on this system")
                .font(.caption2)
                .foregroundColor(.tertiary)
        }
    }

    // MARK: - General tab

    private var generalTab: some View {
        Form {
            Section("Data Management") {
                LabeledContent("Total Log Entries") {
                    Text("\(appState.logEntries.count)")
                        .foregroundColor(.secondary)
                }
                LabeledContent("Supported Platforms") {
                    Text("\(LLMPlatform.allCases.count - 1)")  // exclude .custom
                        .foregroundColor(.secondary)
                }

                Button("Export All Logs…", action: appState.exportLogs)

                Button("Clear All Logs", role: .destructive) {
                    appState.clearAllLogs()
                    dismiss()
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                LabeledContent("Minimum macOS") {
                    Text("13.0 Ventura")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
