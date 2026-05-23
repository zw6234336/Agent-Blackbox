import Foundation

struct Logger {
    static let shared = Logger()

    func info(_ message: String) {
        print("[INFO] \(message)")
    }

    func error(_ message: String) {
        print("[ERROR] \(message)")
    }
}
