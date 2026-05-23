import Foundation
import CoreServices

extension FSEventStreamEventFlags {
    func containsOne(of flags: [FSEventStreamEventFlags]) -> Bool {
        flags.contains { contains($0) }
    }
}

extension String {
    func wildcardMatch(_ pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        let regexPattern = "^\(escaped)$"
        return range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
