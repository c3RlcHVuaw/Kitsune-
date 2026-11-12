import Foundation

/// How much each program moved through the tunnel today. Kept on the device, only for the current day.
@MainActor enum AppTraffic {
    private static let key = "appTrafficToday"
    private struct Day: Codable { var day: String; var bytes: [String: Int64] }
    private static var today: Day = {
        let stored = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Day.self, from: $0) }
        return stored?.day == dayKey ? stored! : Day(day: dayKey, bytes: [:])
    }()

    private static var dayKey: String { Date.now.formatted(.iso8601.year().month().day()) }

    static func add(_ name: String, bytes: Int64) {
        if today.day != dayKey { today = Day(day: dayKey, bytes: [:]) }
        today.bytes[name, default: 0] += bytes
    }

    static func save() { UserDefaults.standard.set(try? JSONEncoder().encode(today), forKey: key) }

    /// The heaviest program of the day, if it moved a meaningful amount.
    static var top: (name: String, bytes: Int64)? {
        today.day == dayKey ? today.bytes.max { $0.value < $1.value }.flatMap { $0.value > 1_000_000 ? ($0.key, $0.value) : nil } : nil
    }
}
