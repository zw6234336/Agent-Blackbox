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

    func bind(database: DatabaseService) {
        self.database = database
    }

    func updateFilePatterns(_ patterns: [String]) {
        filePatterns = patterns.isEmpty ? ["*.log", "*.txt", "*llm*.json"] : patterns
    }

    func startMonitoring(paths: [String]) {
        stopMonitoring()

        let normalizedPaths = paths.filter { !$0.isEmpty }
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

        FSEventStreamScheduleWithRunLoop(eventStream, CFRunLoopGetMain(), kCFRunLoopDefaultMode)
        isMonitoring = FSEventStreamStart(eventStream)
        Logger.shared.info("开始监控: \(monitoredPaths.joined(separator: ", "))")
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
    }

    private func handleFileEvent(path: String, flags: FSEventStreamEventFlags) {
        guard flags.containsOne(of: [
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        ]) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard matchesPattern(url.lastPathComponent) else { return }

        if !detectedLogs.contains(url) {
            detectedLogs.insert(url, at: 0)
            if detectedLogs.count > 200 {
                detectedLogs.removeLast(detectedLogs.count - 200)
            }
        }

        Task {
            guard let parsed = await parser.parseLogFile(at: url) else { return }
            await database?.saveLog(parsed)
        }
    }

    private func matchesPattern(_ fileName: String) -> Bool {
        filePatterns.contains { pattern in
            fileName.wildcardMatch(pattern)
        }
    }
}
