import Foundation

@MainActor
final class ConfigService: ObservableObject {
    @Published var config: MonitorConfig = .init()

    private let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let appFolder = appSupport.appendingPathComponent("Agent-Blackbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true, attributes: nil)
        configURL = appFolder.appendingPathComponent("config.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL) else {
            // First time launch: save the default configuration
            save()
            return
        }
        do {
            var loadedConfig = try JSONDecoder().decode(MonitorConfig.self, from: data)
            
            // Merge any missing default directories to ensure new tools (like Claude Desktop) are monitored
            let defaultDirs = MonitorConfig.defaultTargetedDirectories()
            var currentDirs = Set(loadedConfig.monitoredDirectories)
            var changed = false
            for d in defaultDirs {
                if !currentDirs.contains(d) {
                    loadedConfig.monitoredDirectories.append(d)
                    currentDirs.insert(d)
                    changed = true
                }
            }
            
            config = loadedConfig
            if changed {
                save()
            }
        } catch {
            Logger.shared.error("配置加载失败: \(error.localizedDescription)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder.pretty.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            Logger.shared.error("配置保存失败: \(error.localizedDescription)")
        }
    }
}
