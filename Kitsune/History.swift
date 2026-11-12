import Foundation

/// Finished connections (server, when, how long, how much traffic), newest last, kept to the last 200.
@MainActor enum History {
    struct Session: Codable, Identifiable { var id = UUID(); let server: String; var country: String? = nil; let start: Date; var end: Date; var down: Int64; var up: Int64
        var duration: TimeInterval { end.timeIntervalSince(start) } }

    private static let key = "connectionHistory"
    private static var current: (server: String, country: String?, start: Date)?
    static var sessions: [Session] = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []

    static func begin(server: String, country: String? = nil) { if current == nil { current = (server, country, .now) } }

    static func end(down: Int64, up: Int64) {
        guard let current else { return }
        self.current = nil
        guard Date.now.timeIntervalSince(current.start) >= 5 else { return } // failed attempts aren't history
        sessions = Array((sessions + [Session(server: current.server, country: current.country, start: current.start, end: .now, down: down, up: up)]).suffix(200))
        UserDefaults.standard.set(try? JSONEncoder().encode(sessions), forKey: key)
    }

    /// Consecutive days with at least one connection, counting back from today (or yesterday, if today has none yet).
    static var streak: Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.start) })
        var day = cal.startOfDay(for: .now)
        if !days.contains(day), let yesterday = cal.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var count = 0
        while days.contains(day), let previous = cal.date(byAdding: .day, value: -1, to: day) { count += 1; day = previous }
        return count
    }

    /// A playful title for how long and how regularly the app has been used, plus a hint about the next one.
    static var rank: (title: String, hint: String) {
        let s = streak
        if s >= 30 { return (L("Лис-хранитель"), L("Больше месяца подряд. Выше только небо.")) }
        if s >= 7 { return (L("Тихая лиса"), String(format: L("До «Лиса-хранителя» ещё %lld дн. подряд"), 30 - s)) }
        if sessions.count >= 5 { return (L("Любопытная лиса"), String(format: L("До «Тихой лисы» ещё %lld дн. подряд"), 7 - s)) }
        return (L("Лисёнок"), L("Подключайтесь каждый день, и звание вырастет."))
    }

    /// Small achievements shown next to the rank: (icon, title, hint).
    static var badges: [(icon: String, title: String)] {
        var result: [(String, String)] = []
        let cal = Calendar.current
        if sessions.contains(where: { (2..<6).contains(cal.component(.hour, from: $0.start)) }) { result.append(("moon.stars.fill", L("Ночная сова"))) }
        if Set(sessions.compactMap(\.country)).count >= 5 { result.append(("airplane", L("Путешественник"))) }
        if sessions.contains(where: { $0.duration >= 86_400 }) { result.append(("flame.fill", L("Марафонец"))) }
        return result
    }

    static func clear() { sessions = []; UserDefaults.standard.removeObject(forKey: key) }
}
