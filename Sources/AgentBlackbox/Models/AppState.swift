import Foundation
import AppKit
import Combine

/// Central observable store: owns monitoring, filtering, and export logic.
@MainActor
final class AppState: ObservableObject {
    @Published var logEntries: [LogEntry] = []
    @Published var selectedPlatforms: Set<LLMPlatform> = Set(LLMPlatform.allCases)
    @Published var selectedEntry: LogEntry?
    @Published var searchQuery: String = ""
    @Published var isMonitoring: Bool = false
    @Published var statusMessage: String = "Ready"

    /// Per-platform custom override paths; if empty the platform's defaults are used.
    @Published var customWatchPaths: [LLMPlatform: [String]] = [:]

    // Internal services
    private let fileWatcher = FileWatcherService()
    private let logParser   = LogParserService()
    private let database    = DatabaseService()

    /// Set of file-path+content hashes already seen this session to avoid duplicate scans.
    private var seenIDs: Set<UUID> = []

    init() {
        loadStoredEntries()
        fileWatcher.onFileChanged = { [weak self] path in
            guard let self else { return }
            Task { await self.processChangedFile(at: path) }
        }
    }

    // MARK: - Persistence

    private func loadStoredEntries() {
        Task {
            let entries = await database.fetchAllEntries()
            self.logEntries = entries.sorted { $0.timestamp > $1.timestamp }
            self.seenIDs = Set(entries.map(\.id))
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        var paths: [String] = []
        for platform in LLMPlatform.allCases where platform != .custom {
            paths += (customWatchPaths[platform] ?? platform.defaultWatchPaths)
        }
        paths += (customWatchPaths[.custom] ?? [])

        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }

        guard !existing.isEmpty else {
            statusMessage = "No monitored directories found on this system"
            return
        }

        fileWatcher.startWatching(paths: existing)
        isMonitoring = true
        statusMessage = "Monitoring \(existing.count) director\(existing.count == 1 ? "y" : "ies")"

        Task { await scanExistingFiles(in: existing) }
    }

    func stopMonitoring() {
        fileWatcher.stopWatching()
        isMonitoring = false
        statusMessage = "Monitoring stopped"
    }

    // MARK: - File Processing

    private func scanExistingFiles(in directories: [String]) async {
        let fm = FileManager.default
        for dir in directories {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let full = (dir as NSString).appendingPathComponent(item)
                await processChangedFile(at: full)
            }
        }
    }

    private func processChangedFile(at path: String) async {
        let ext = (path as NSString).pathExtension.lowercased()
        guard LLMPlatform.watchedExtensions.contains(ext) else { return }

        let platform = detectPlatform(for: path)
        guard selectedPlatforms.contains(platform) else { return }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let entries = logParser.parse(content: content, platform: platform, filePath: path)
        var newEntries: [LogEntry] = []

        for entry in entries where !seenIDs.contains(entry.id) {
            seenIDs.insert(entry.id)
            newEntries.append(entry)
            await database.insert(entry: entry)
        }

        guard !newEntries.isEmpty else { return }

        logEntries.insert(contentsOf: newEntries, at: 0)
        logEntries.sort { $0.timestamp > $1.timestamp }
        statusMessage = "Found \(newEntries.count) new log entr\(newEntries.count == 1 ? "y" : "ies")"
    }

    private func detectPlatform(for path: String) -> LLMPlatform {
        let lower = path.lowercased()
        for platform in LLMPlatform.allCases where platform != .custom {
            let watchPaths = customWatchPaths[platform] ?? platform.defaultWatchPaths
            if watchPaths.contains(where: { lower.contains($0.lowercased()) }) {
                return platform
            }
            if lower.contains(platform.rawValue.lowercased().replacingOccurrences(of: " ", with: "")) {
                return platform
            }
        }
        return .custom
    }

    // MARK: - Filtered View

    var filteredEntries: [LogEntry] {
        var entries = logEntries.filter { selectedPlatforms.contains($0.platform) }
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        entries = entries.filter {
            ($0.prompt?.lowercased().contains(q) ?? false) ||
            ($0.response?.lowercased().contains(q) ?? false) ||
            ($0.model?.lowercased().contains(q) ?? false) ||
            $0.rawContent.lowercased().contains(q) ||
            $0.platform.rawValue.lowercased().contains(q)
        }
        return entries
    }

    // MARK: - Export

    func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "llm-logs-\(Date().ISO8601Format())"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(self.filteredEntries)
                try data.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Clear

    func clearAllLogs() {
        Task {
            await database.deleteAll()
            logEntries = []
            seenIDs = []
            selectedEntry = nil
            statusMessage = "All logs cleared"
        }
    }
}
