import Foundation
import CoreServices

/// Wraps FSEventStream to deliver file-level change notifications.
final class FileWatcherService {
    var onFileChanged: ((String) -> Void)?

    private var streamRef: FSEventStreamRef?

    func startWatching(paths: [String]) {
        stopWatching()
        guard !paths.isEmpty else { return }

        let cfPaths = paths as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes
        )

        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileEventCallback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,   // coalescing latency in seconds – 0.5 s balances responsiveness vs. CPU churn
            flags
        )

        guard let stream = streamRef else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stopWatching() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    deinit { stopWatching() }
}

// MARK: - FSEvents C callback

private let fileEventCallback: FSEventStreamCallback = {
    _, clientInfo, numEvents, eventPaths, eventFlags, _ in
    guard let info = clientInfo else { return }
    let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()

    guard let paths = eventPaths as? [String] else { return }

    let createdFlag  = UInt32(kFSEventStreamEventFlagItemCreated)
    let modifiedFlag = UInt32(kFSEventStreamEventFlagItemModified)

    for i in 0..<numEvents {
        let flag = eventFlags[i]
        if flag & createdFlag != 0 || flag & modifiedFlag != 0 {
            watcher.onFileChanged?(paths[i])
        }
    }
}
