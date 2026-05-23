import Foundation

@MainActor
final class ConfigService: ObservableObject {
    @Published var config: MonitorConfig = .init()

    private let configURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Agent-Blackbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true, attributes: nil)
        configURL = appFolder.appendingPathComponent("config.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        do {
            config = try JSONDecoder().decode(MonitorConfig.self, from: data)
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
