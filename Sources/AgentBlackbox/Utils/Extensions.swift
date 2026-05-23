import Foundation

extension DateFormatter {
    /// Medium-date, medium-time formatter for display in the UI.
    static let logDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}

extension String {
    /// Returns nil if the string is empty, otherwise returns self.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
