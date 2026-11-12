import Foundation

/// What the internet sees right now: exit IP and country, and which DNS resolver answers our queries.
@MainActor @Observable final class LeakCheck {
    struct Result: Equatable { let ip: String; let country: String; let dns: String? }
    enum State { case idle, running, done(Result), failed }
    private(set) var state = State.idle

    func run() async {
        state = .running
        if let result = await Self.probe() { state = .done(result) } else { state = .failed }
    }

    /// One look from the outside: exit address and the resolver that really answers. nil when there is no network.
    nonisolated static func probe() async -> Result? {
        struct Ip: Decodable { let ip: String; let country: String }
        struct Edns: Decodable { struct D: Decodable { let geo: String?; let ip: String? }; let dns: D }
        var request = URLRequest(url: URL(string: "https://api.country.is/")!, timeoutInterval: 6)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request), let ip = try? JSONDecoder().decode(Ip.self, from: data) else { return nil }
        // The DNS test needs a unique host name, so the resolver that really answers shows up.
        let host = "\(UUID().uuidString.prefix(12).lowercased()).edns.ip-api.com"
        var dnsRequest = URLRequest(url: URL(string: "http://\(host)/edns.json")!, timeoutInterval: 6)
        dnsRequest.cachePolicy = .reloadIgnoringLocalCacheData
        let resolver = (try? await URLSession.shared.data(for: dnsRequest)).flatMap { try? JSONDecoder().decode(Edns.self, from: $0.0) }?.dns
        let dns = resolver.map { [$0.ip, $0.geo].compactMap { $0 }.joined(separator: " · ") }
        return Result(ip: ip.ip, country: ip.country, dns: dns)
    }
}
