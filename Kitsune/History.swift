import Foundation

/// Finished connections (server, when, how long, how much traffic), newest last, kept to the last 200.
@MainActor enum History {
    struct Session: Codable, Identifiable { var id = UUID(); let server: String; let start: Date; var end: Date; var down: Int64; var up: Int64
        var duration: TimeInterval { end.timeIntervalSince(start) } }

    private static let key = "connectionHistory"
    private static var current: (server: String, start: Date)?
    static var sessions: [Session] = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []

    static func begin(server: String) { if current == nil { current = (server, .now) } }

    static func end(down: Int64, up: Int64) {
        guard let current else { return }
        self.current = nil
        guard Date.now.timeIntervalSince(current.start) >= 5 else { return } // failed attempts aren't history
        sessions = Array((sessions + [Session(server: current.server, start: current.start, end: .now, down: down, up: up)]).suffix(200))
        UserDefaults.standard.set(try? JSONEncoder().encode(sessions), forKey: key)
    }

    static func clear() { sessions = []; UserDefaults.standard.removeObject(forKey: key) }
}
