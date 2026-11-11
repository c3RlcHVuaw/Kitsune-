import Foundation

/// Bytes through the tunnel per day, kept for a month. Written to UserDefaults every few seconds, not every tick.
@MainActor enum TrafficStats {
    struct Day: Identifiable { let date: Date; let down: Int64; let up: Int64; var id: Date { date } }

    private static let key = "trafficDays"
    private static var days: [String: [Int64]] = (UserDefaults.standard.dictionary(forKey: key) as? [String: [Int64]]) ?? [:]
    private static var ticks = 0

    private static func name(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func record(down: Int64, up: Int64) {
        let today = name(.now)
        var entry = days[today] ?? [0, 0]
        entry[0] += down
        entry[1] += up
        days[today] = entry
        ticks += 1
        if ticks % 10 == 0 { save() }
    }

    static func save() {
        let cutoff = name(Calendar.current.date(byAdding: .day, value: -31, to: .now) ?? .now)
        days = days.filter { $0.key >= cutoff }
        UserDefaults.standard.set(days, forKey: key)
    }

    static func reset() { days = [:]; UserDefaults.standard.removeObject(forKey: key) }

    /// The last `count` days, oldest first, including empty ones.
    static func last(_ count: Int) -> [Day] {
        (0..<count).reversed().compactMap { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: .now)) else { return nil }
            let entry = days[name(date)] ?? [0, 0]
            return Day(date: date, down: entry[0], up: entry[1])
        }
    }
}
