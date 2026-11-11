import Foundation

/// What the internet sees right now: exit IP and country, and which DNS resolver answers our queries.
@MainActor @Observable final class LeakCheck {
    struct Result { let ip: String; let country: String; let dns: String? }
    enum State { case idle, running, done(Result), failed }
    private(set) var state = State.idle

    func run() async {
        state = .running
        struct Ip: Decodable { let ip: String; let country: String }
        struct Edns: Decodable { struct D: Decodable { let geo: String?; let ip: String? }; let dns: D }
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.country.is/")!)
            let ip = try JSONDecoder().decode(Ip.self, from: data)
            // The DNS test needs a unique host name, so the resolver that really answers shows up.
            let host = "\(UUID().uuidString.prefix(12).lowercased()).edns.ip-api.com"
            let dns = try? await URLSession.shared.data(from: URL(string: "http://\(host)/edns.json")!)
            let resolver = dns.flatMap { try? JSONDecoder().decode(Edns.self, from: $0.0) }?.dns
            state = .done(Result(ip: ip.ip, country: ip.country, dns: resolver.map { [$0.ip, $0.geo].compactMap { $0 }.joined(separator: " · ") }))
        } catch {
            state = .failed
        }
    }
}
