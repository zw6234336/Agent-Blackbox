import Combine
import Foundation
import CoreServices

@MainActor
final class FileMonitorService: ObservableObject {
    @Published var isMonitoring: Bool = false
    @Published var monitoredPaths: [String] = []
    @Published var detectedLogs: [URL] = []

    private var eventStream: FSEventStreamRef?
    private let parser = LogParserService()
    private weak var database: DatabaseService?
    private var filePatterns: [String] = ["*.log", "*.txt", "*llm*.json"]
    private var detectedLogSet: Set<URL> = []

    func bind(database: DatabaseService) {
        self.database = database
    }

    func updateFilePatterns(_ patterns: [String]) {
        filePatterns = patterns.isEmpty ? ["*.log", "*.txt", "*llm*.json"] : patterns
    }

    func startMonitoring(paths: [String]) {
        stopMonitoring()

        let normalizedPaths = paths.filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
        guard !normalizedPaths.isEmpty else { return }

        monitoredPaths = normalizedPaths
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, flags, _ in
            guard let info else { return }
            let service = Unmanaged<FileMonitorService>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: CFArray?.self) as? [String] else { return }

            for i in 0..<count {
                let path = paths[Int(i)]
                let flag = flags[Int(i)]
                Task { @MainActor in
                    service.handleFileEvent(path: path, flags: flag)
                }
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            monitoredPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes |
                   kFSEventStreamCreateFlagFileEvents |
                   kFSEventStreamCreateFlagNoDefer)
        )

        guard let eventStream else { return }

        FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.main)
        isMonitoring = FSEventStreamStart(eventStream)
        Logger.shared.info("开始监控: \(monitoredPaths.count) 个目录")
        
        Task(priority: .background) {
            let patterns = filePatterns
            await performInitialScan(paths: normalizedPaths, filePatterns: patterns)
        }
    }

    func stopMonitoring() {
        guard let eventStream else {
            isMonitoring = false
            return
        }

        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
        isMonitoring = false
        detectedLogSet.removeAll(keepingCapacity: true)
    }

    private func handleFileEvent(path: String, flags: FSEventStreamEventFlags) {
        // Exclude removed events
        if flags.containsOne(of: [FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)]) {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard matchesPattern(url) else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return
        }

        if detectedLogSet.insert(url).inserted {
            detectedLogs.insert(url, at: 0)
            if detectedLogs.count > 200 {
                let removed = detectedLogs.suffix(detectedLogs.count - 200)
                detectedLogs.removeLast(detectedLogs.count - 200)
                for item in removed {
                    detectedLogSet.remove(item)
                }
            }
        }

        Task {
            let results = await parser.parseAllEntries(at: url)
            if !results.isEmpty {
                await database?.saveLogs(results)
            }
        }
    }

    /// 兼容旧 API；优先使用 `matchesPattern(url:)`
    private func matchesPattern(_ fileName: String) -> Bool {
        filePatterns.contains { pattern in
            fileName.wildcardMatch(pattern)
        }
    }

    /// pattern 含 `/` → 全路径匹配；否则 lastPathComponent 匹配
    private func matchesPattern(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let path = url.path
        return filePatterns.contains { pattern in
            if pattern.contains("/") {
                return path.wildcardMatch(pattern)
            } else {
                return name.wildcardMatch(pattern)
            }
        }
    }
    
    nonisolated private func performInitialScan(paths: [String], filePatterns: [String]) async {
        Logger.shared.info("开始扫描监控目录中的历史日志...")
        let fm = FileManager.default
        var urlsToProcess: [URL] = []
        
        let matches: @Sendable (URL) -> Bool = { url in
            let name = url.lastPathComponent
            let path = url.path
            return filePatterns.contains { pattern in
                if pattern.contains("/") {
                    return path.wildcardMatch(pattern)
                } else {
                    return name.wildcardMatch(pattern)
                }
            }
        }
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            
            if isDir.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey]
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsPackageDescendants, .skipsHiddenFiles]
                ) else { continue }
                
                while let fileURL = enumerator.nextObject() as? URL {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)),
                          resourceValues.isRegularFile ?? false else { continue }
                    
                    if matches(fileURL) {
                        urlsToProcess.append(fileURL)
                    }
                }
            } else {
                if matches(url) {
                    urlsToProcess.append(url)
                }
            }
        }
        
        Logger.shared.info("找到 \(urlsToProcess.count) 个历史日志文件，开始解析...")
        
        var parsedCount = 0
        for fileURL in urlsToProcess {
            let results = await parser.parseAllEntries(at: fileURL)
            if !results.isEmpty {
                // 批量保存：每个文件的所有日志在一次事务中写入，仅触发一次 reloadLogs
                await database?.saveLogs(results)
                parsedCount += results.count
            }
        }
        
        Logger.shared.info("历史日志扫描完成！解析并保存了 \(parsedCount) 条历史记录。")
        
        // 扫描全部完成后统一刷新 Dashboard 统计（昂贵的聚合查询仅执行一次）
        await database?.refreshDashboardStats()
    }
}
