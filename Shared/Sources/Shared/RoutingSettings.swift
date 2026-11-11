import Foundation
import Network

/// What goes direct and what goes through the tunnel.
public struct RoutingSettings: Codable, Equatable, Sendable {
    public enum Profile: String, Codable, CaseIterable, Sendable {
        /// Russian domains and IPs direct, the rest through VPN. Default.
        case russiaDirect
        /// Everything through VPN except the local network.
        case allVPN
        /// Only the user's own lists decide; the rest through VPN.
        case custom
    }

    public var profile: Profile
    /// "Always direct" entries: domains (`example.com`, `*.example.com`) or IPs/CIDRs.
    public var direct: [String]
    /// "Always through VPN" entries, same format.
    public var proxy: [String]
    /// Ready-made "through VPN" sets switched on with one tap.
    public var presets: Set<RoutePreset>
    /// macOS only: process names (e.g. `Telegram`) that always go direct / always through VPN.
    public var directApps: [String]
    public var proxyApps: [String]

    public init(profile: Profile = .russiaDirect, direct: [String] = [], proxy: [String] = [], presets: Set<RoutePreset> = [],
                directApps: [String] = [], proxyApps: [String] = []) {
        self.profile = profile
        self.direct = direct
        self.proxy = proxy
        self.presets = presets
        self.directApps = directApps
        self.proxyApps = proxyApps
    }

    // Settings saved by older versions have no presets or app rules.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(Profile.self, forKey: .profile)
        direct = try c.decode([String].self, forKey: .direct)
        proxy = try c.decode([String].self, forKey: .proxy)
        presets = try c.decodeIfPresent(Set<RoutePreset>.self, forKey: .presets) ?? []
        directApps = try c.decodeIfPresent([String].self, forKey: .directApps) ?? []
        proxyApps = try c.decodeIfPresent([String].self, forKey: .proxyApps) ?? []
    }

    /// The user's "through VPN" list plus the domains of every enabled preset.
    public var effectiveProxy: [String] { proxy + RoutePreset.allCases.filter(presets.contains).flatMap(\.domains) }

    /// User lists apply in every profile except "everything through VPN".
    public var usesUserLists: Bool { profile != .allVPN }
}

/// One user routing entry, normalised: a domain suffix or an IP range.
public enum RoutePreset: String, Codable, CaseIterable, Sendable {
    case streaming, games, messengers

    public var domains: [String] {
        switch self {
        case .streaming: ["netflix.com", "nflxvideo.net", "youtube.com", "googlevideo.com", "ytimg.com", "spotify.com", "scdn.co",
                          "twitch.tv", "ttvnw.net", "disneyplus.com", "hulu.com", "primevideo.com"]
        case .games: ["steampowered.com", "steamcommunity.com", "steamstatic.com", "epicgames.com", "riotgames.com",
                      "leagueoflegends.com", "ea.com", "battle.net", "blizzard.com", "ubisoft.com", "roblox.com"]
        case .messengers: ["telegram.org", "t.me", "telegra.ph", "whatsapp.com", "whatsapp.net", "signal.org",
                           "discord.com", "discord.gg", "discordapp.com", "viber.com"]
        }
    }
}

public enum RouteEntry: Equatable, Sendable {
    case domain(String)
    case cidr(String)

    public enum ParseError: Error, Equatable { case empty, invalid, nonASCII }

    /// Accepts `example.com`, `*.example.com`, `https://example.com/path`, `1.2.3.4`, `10.0.0.0/8`, `2001:db8::/32`.
    public init(_ raw: String) throws(ParseError) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { throw .empty }
        if let schemeEnd = text.range(of: "://") { text = String(text[schemeEnd.upperBound...]) }

        switch Self.parseCIDR(text) {
        case .some(.some(let cidr)): self = .cidr(cidr); return
        case .some(.none): throw .invalid // an IP with a bad prefix length
        case .none: break
        }

        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let colon = text.lastIndex(of: ":") { text = String(text[..<colon]) } // drop :port
        while text.hasPrefix("*.") || text.hasPrefix(".") { text.removeFirst(text.hasPrefix("*.") ? 2 : 1) }
        guard let ascii = Punycode.toASCII(text) else { throw .nonASCII } // пример.рф → xn--e1afmkfd.xn--p1ai
        text = ascii
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        let validLabel = { (label: Substring) in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        // A numeric last label means a malformed IP, not a domain.
        guard text.count <= 253, labels.allSatisfy(validLabel), labels.last?.allSatisfy(\.isNumber) == false else { throw .invalid }
        self = .domain(text)
    }

    /// nil: not an IP at all. `.some(nil)`: an IP with an invalid prefix.
    private static func parseCIDR(_ text: String) -> String?? {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        let address = parts[0]
        let isV4 = address.split(separator: ".").count == 4 && IPv4Address(address) != nil // IPv4Address accepts short forms like "10.0.0"
        let isV6 = !isV4 && IPv6Address(address) != nil
        guard isV4 || isV6 else { return nil }
        let maxPrefix = isV4 ? 32 : 128
        guard parts.count == 2 else { return .some("\(address)/\(maxPrefix)") }
        guard let prefix = Int(parts[1]), (0...maxPrefix).contains(prefix) else { return .some(nil) }
        return .some("\(address)/\(prefix)")
    }

    public var display: String {
        switch self {
        case .domain(let value), .cidr(let value): value
        }
    }
}
