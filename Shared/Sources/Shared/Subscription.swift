import Foundation

/// Metadata a subscription server sends in response headers (Marzban / Remnawave / 3x-ui conventions).
public struct SubscriptionInfo: Codable, Equatable, Sendable {
    public var title: String?
    public var upload: Int64?
    public var download: Int64?
    /// nil or 0 means unlimited.
    public var total: Int64?
    public var expire: Date?
    public var updateIntervalHours: Int?
    public var announce: String?
    public var supportURL: URL?
    /// The provider's site (`profile-web-page-url`).
    public var webPageURL: URL?
    /// Any other links the panel sends: other URL headers and links written inside the announcement.
    public var extraLinks: [URL]?

    public init() {}

    public var used: Int64? {
        guard upload != nil || download != nil else { return nil }
        return (upload ?? 0) + (download ?? 0)
    }

    /// Header names are matched case-insensitively.
    public static func parse(headers: [String: String]) -> SubscriptionInfo {
        let h = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        var info = SubscriptionInfo()
        info.title = h["profile-title"].map(decodeText)
        info.announce = h["announce"].map(decodeText)
        info.updateIntervalHours = h["profile-update-interval"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        info.supportURL = h["support-url"].flatMap(link)
        info.webPageURL = h["profile-web-page-url"].flatMap(link)
        var extra: [URL] = (h.filter { $0.key.hasSuffix("url") && !["support-url", "profile-web-page-url"].contains($0.key) }
            .sorted { $0.key < $1.key }.compactMap { link($0.value) })
        if let announce = info.announce, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            extra += detector.matches(in: announce, range: NSRange(announce.startIndex..., in: announce)).compactMap(\.url)
        }
        let known = [info.supportURL, info.webPageURL].compactMap { $0 }
        info.extraLinks = extra.reduce(into: [URL]()) { if !known.contains($1) && !$0.contains($1) { $0.append($1) } }
        if info.extraLinks?.isEmpty == true { info.extraLinks = nil }
        if let userinfo = h["subscription-userinfo"] {
            // "upload=123; download=456; total=789; expire=1767225600"
            for pair in userinfo.split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2, let value = Int64(kv[1]) else { continue }
                switch kv[0] {
                case "upload": info.upload = value
                case "download": info.download = value
                case "total": info.total = value
                case "expire": info.expire = value > 0 ? Date(timeIntervalSince1970: TimeInterval(value)) : nil
                default: break
                }
            }
        }
        return info
    }

    private static func link(_ value: String) -> URL? {
        let text = decodeText(value).trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text), ["http", "https", "tg"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    /// Every link worth a button: support first, then the site, then the rest. Telegram links are the usual "channel" entry.
    public var links: [URL] { [supportURL, webPageURL].compactMap { $0 } + (extraLinks ?? []) }

    /// Some panels send `base64:<data>` to carry non-ASCII text in headers.
    private static func decodeText(_ value: String) -> String {
        guard value.hasPrefix("base64:"), let data = Data(base64Encoded: padded(String(value.dropFirst(7)))) else { return value }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Turns a subscription response body into servers.
public enum SubscriptionParser {
    /// Outbound types Kitsune passes through from sing-box JSON subscriptions.
    static let proxyTypes: Set<String> = ["vless", "vmess", "trojan", "shadowsocks", "hysteria2", "tuic", "wireguard"]

    /// Returns parsed servers and how many entries were skipped as unsupported.
    public static func servers(from body: Data) -> (servers: [ServerConfig], skipped: Int) {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let outbounds = json["outbounds"] as? [[String: Any]] {
            return fromSingBox(outbounds)
        }
        var text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://"), let decoded = base64(text) { text = decoded }
        var servers: [ServerConfig] = []
        var skipped = 0
        for line in text.split(whereSeparator: \.isNewline) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if let server = try? ProxyLink.parse(String(line)) { servers.append(server) } else { skipped += 1 }
        }
        return (dedup(servers), skipped)
    }

    private static func fromSingBox(_ outbounds: [[String: Any]]) -> ([ServerConfig], Int) {
        var servers: [ServerConfig] = []
        var skipped = 0
        for var outbound in outbounds {
            guard let type = outbound["type"] as? String, proxyTypes.contains(type) else { continue } // selectors, direct, dns…
            let name = outbound.removeValue(forKey: "tag") as? String ?? type
            outbound.removeValue(forKey: "detour") // points at tags from the provider's config, not ours
            if let server = try? ServerConfig(name: name, summary: summary(for: outbound), outbound: outbound) { servers.append(server) } else { skipped += 1 }
        }
        return (dedup(servers), skipped)
    }

    private static func summary(for outbound: [String: Any]) -> String {
        let type = (outbound["type"] as? String ?? "").uppercased()
            .replacingOccurrences(of: "HYSTERIA2", with: "Hysteria2").replacingOccurrences(of: "SHADOWSOCKS", with: "Shadowsocks")
            .replacingOccurrences(of: "WIREGUARD", with: "WireGuard")
        let transport = (outbound["transport"] as? [String: Any])?["type"] as? String
        let tls = outbound["tls"] as? [String: Any]
        let security = tls?["reality"] != nil ? "Reality" : tls?["enabled"] as? Bool == true ? "TLS" : nil
        return [type, transport.map { $0 == "grpc" ? "gRPC" : $0.uppercased() }, security].compactMap { $0 }.joined(separator: " · ")
    }

    private static func dedup(_ servers: [ServerConfig]) -> [ServerConfig] {
        var seen = Set<String>()
        return servers.filter { seen.insert($0.id).inserted }
    }

    private static func base64(_ text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            .filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: padded(normalized)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

func padded(_ base64: String) -> String {
    base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
}
