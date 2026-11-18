import Foundation

/// Finished connections (server, when, how long, how much traffic), newest last, kept to the last 200.
@MainActor enum History {
    struct Session: Codable, Identifiable { var id = UUID(); let server: String; var country: String? = nil; let start: Date; var end: Date; var down: Int64; var up: Int64
        var duration: TimeInterval { end.timeIntervalSince(start) } }

    private static let key = "connectionHistory"
    private static var current: (server: String, country: String?, start: Date)?
    static var sessions: [Session] = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([Session].self, from: $0) } ?? []

    /// Whole days since the previous connection, when it was a week or more ago; the home screen greets the comeback.
    private(set) static var comeback: Int?
    /// Set when this connection exits in another country than the previous one did.
    private(set) static var countryChange: (from: String, to: String)?

    static func begin(server: String, country: String? = nil) {
        guard current == nil else { return }
        current = (server, country, .now)
        let days = sessions.last.map { Calendar.current.dateComponents([.day], from: $0.end, to: .now).day ?? 0 } ?? 0
        comeback = days >= 7 ? days : nil
        if let before = sessions.last?.country, let now = country, before != now { countryChange = (before, now) } else { countryChange = nil }
    }

    static var totalHours: Int { Int(sessions.reduce(0) { $0 + $1.duration } / 3600) }

    /// 0 Лисёнок … 4 Ёкай, the same steps as `rank`.
    static var rankLevel: Int {
        if totalHours >= 100 { return 4 }
        let s = streak
        if s >= 30 { return 3 }
        if s >= 7 { return 2 }
        return sessions.count >= 5 ? 1 : 0
    }
    /// The highest rank ever reached: a broken streak never takes an opened theme away.
    static var bestRankLevel: Int { max(rankLevel, UserDefaults.standard.integer(forKey: "bestRank")) }
    /// Fox tails for the rank: 1, 2, 3, 4 and nine for «Ёкай».
    static var tails: Int { [1, 2, 3, 4, 9][min(bestRankLevel, 4)] }
    static let rankTitles = [L("Лисёнок"), L("Любопытная лиса"), L("Тихая лиса"), L("Лис-хранитель"), L("Ёкай")]

    static func end(down: Int64, up: Int64) {
        guard let current else { return }
        self.current = nil
        comeback = nil
        countryChange = nil
        guard Date.now.timeIntervalSince(current.start) >= 5 else { return } // failed attempts aren't history
        if let c = current.country, !c.isEmpty { stamp(c, current.start) } // before `sessions` grows, so a first-run rebuild doesn't count it twice
        sessions = Array((sessions + [Session(server: current.server, country: current.country, start: current.start, end: .now, down: down, up: up)]).suffix(200))
        UserDefaults.standard.set(try? JSONEncoder().encode(sessions), forKey: key)
        UserDefaults.standard.set(bestRankLevel, forKey: "bestRank")
    }

    // MARK: Passport stamps

    static func flag(_ code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
    }

    struct Stamp: Codable, Identifiable { let country: String; let first: Date; var visits: Int; var seconds: Double; var id: String { country } }
    private static let stampKey = "passportStamps"
    /// One stamp per exit country, kept apart from the 200-session history so old trips never fall off.
    static var stamps: [Stamp] {
        var saved = (UserDefaults.standard.data(forKey: stampKey)).flatMap { try? JSONDecoder().decode([Stamp].self, from: $0) } ?? []
        // first launch after the update: rebuild from the sessions we still have
        if saved.isEmpty && !sessions.isEmpty {
            for s in sessions { if let c = s.country, !c.isEmpty { merge(&saved, c, s.start, s.duration) } }
            UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: stampKey)
        }
        return saved.sorted { $0.first < $1.first }
    }
    private static func merge(_ list: inout [Stamp], _ c: String, _ date: Date, _ seconds: TimeInterval) {
        if let i = list.firstIndex(where: { $0.country == c }) { list[i].visits += 1; list[i].seconds += seconds }
        else { list.append(Stamp(country: c, first: date, visits: 1, seconds: seconds)) }
    }
    private static func stamp(_ c: String, _ start: Date) {
        var list = stamps
        merge(&list, c, start, Date.now.timeIntervalSince(start))
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: stampKey)
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
        if totalHours >= 100 { return (L("Ёкай"), L("100 часов под защитой. Выше только легенды.")) }
        if s >= 30 { return (L("Лис-хранитель"), String(format: L("До «Ёкая» ещё %lld ч под защитой"), 100 - totalHours)) }
        if s >= 7 { return (L("Тихая лиса"), String(format: L("До «Лиса-хранителя» ещё %lld дн. подряд"), 30 - s)) }
        if sessions.count >= 5 { return (L("Любопытная лиса"), String(format: L("До «Тихой лисы» ещё %lld дн. подряд"), 7 - s)) }
        return (L("Лисёнок"), L("Подключайтесь каждый день, и звание вырастет."))
    }

    /// Small achievements shown next to the rank: (icon, title, hint).
    static var badges: [(icon: String, title: String)] {
        var result: [(String, String)] = []
        let cal = Calendar.current
        if sessions.contains(where: { (2..<5).contains(cal.component(.hour, from: $0.start)) }) { result.append(("moon.stars.fill", L("Ночная сова"))) }
        if UserDefaults.standard.string(forKey: "firstVersion") == "early" { result.append(("seal.fill", L("Первый релиз"))) }
        if sessions.contains(where: { (5..<7).contains(cal.component(.hour, from: $0.start)) }) { result.append(("sunrise.fill", L("Ранняя пташка"))) }
        if Set(sessions.compactMap(\.country)).count >= 5 { result.append(("airplane", L("Путешественник"))) }
        if sessions.contains(where: { $0.duration >= 86_400 }) { result.append(("flame.fill", L("Марафонец"))) }
        return result
    }

    static func clear() { sessions = []; UserDefaults.standard.removeObject(forKey: key) }
}
