import Foundation

/// Average latency per server by hour of the day, kept on the device: when is this server fastest?
@MainActor enum PingStats {
    private struct Bucket: Codable { var sum = 0, count = 0 }
    private static let key = "pingByHour"
    private static var data: [String: [Bucket]] = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: [Bucket]].self, from: $0) } ?? [:]

    static func record(_ id: String, _ ms: Int) {
        var hours = data[id] ?? Array(repeating: Bucket(), count: 24)
        let hour = Calendar.current.component(.hour, from: .now)
        hours[hour].sum += ms; hours[hour].count += 1
        data[id] = hours
        UserDefaults.standard.set(try? JSONEncoder().encode(data), forKey: key)
    }

    /// 24 averages in ms, nil for hours without samples.
    static func averages(_ id: String) -> [Int?] {
        (data[id] ?? []).map { $0.count > 0 ? $0.sum / $0.count : nil } + Array(repeating: nil, count: max(0, 24 - (data[id]?.count ?? 0)))
    }
}
