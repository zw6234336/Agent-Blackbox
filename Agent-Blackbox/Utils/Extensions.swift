import Foundation
import CoreServices
import SwiftUI

// MARK: - FSEventStreamEventFlags
extension FSEventStreamEventFlags {
    func containsOne(of flags: [FSEventStreamEventFlags]) -> Bool {
        flags.contains { (self & $0) != 0 }
    }
}

// MARK: - String
extension String {
    func wildcardMatch(_ pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        let regexPattern = "^\(escaped)$"
        return range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - JSONEncoder
extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Int Formatting
extension Int {
    /// Format as compact string: 1234 → "1.2K", 1234567 → "1.2M"
    var formattedCompact: String {
        if self >= 1_000_000_000 {
            return String(format: "%.1fB", Double(self) / 1_000_000_000.0)
        } else if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000.0)
        } else if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000.0)
        }
        return "\(self)"
    }
}

// MARK: - Double Formatting
extension Double {
    /// Format as currency: 1.234 → "$1.23"
    var formattedCurrency: String {
        if self >= 1000 {
            return String(format: "$%.0f", self)
        } else if self >= 100 {
            return String(format: "$%.1f", self)
        } else if self >= 1 {
            return String(format: "$%.2f", self)
        } else if self >= 0.01 {
            return String(format: "$%.3f", self)
        } else if self > 0 {
            return String(format: "$%.4f", self)
        }
        return "$0.00"
    }

    /// Format as duration: 1.234 → "1.23s"
    var formattedDuration: String {
        if self >= 60 {
            return String(format: "%.0fm", self / 60.0)
        } else if self >= 1 {
            return String(format: "%.1fs", self)
        } else {
            return String(format: "%.0fms", self * 1000.0)
        }
    }

    /// Format as percentage: 0.85 → "85%"
    var formattedPercent: String {
        String(format: "%.1f%%", self)
    }
}

// MARK: - Date Formatting
extension Date {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Relative time description: "2分钟前", "3小时前"
    var formattedRelative: String {
        Date.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short date+time
    var formattedShort: String {
        Date.shortDateFormatter.string(from: self)
    }

    /// Date only
    var formattedDate: String {
        Date.dateOnlyFormatter.string(from: self)
    }
}

// MARK: - Color Extensions
extension Color {
    static let dashboardBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let cardBackground = Color(nsColor: NSColor.controlBackgroundColor)

    static let accentGradientStart = Color(hue: 0.6, saturation: 0.8, brightness: 0.9)
    static let accentGradientEnd = Color(hue: 0.75, saturation: 0.7, brightness: 0.8)

    static let successGreen = Color(hue: 0.38, saturation: 0.7, brightness: 0.7)
    static let warningOrange = Color(hue: 0.08, saturation: 0.8, brightness: 0.9)
    static let errorRed = Color(hue: 0.0, saturation: 0.75, brightness: 0.8)
    static let infoBlue = Color(hue: 0.58, saturation: 0.65, brightness: 0.85)
}

// MARK: - View Modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - UUID
import CryptoKit
extension UUID {
    static func deterministic(from string: String) -> UUID {
        let inputData = Data(string.utf8)
        let hash = SHA256.hash(data: inputData)
        let bytes = Array(hash)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
