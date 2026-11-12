import CryptoKit
import Foundation

/// One connectable server, whatever it came from (a share link or a subscription).
public struct ServerConfig: Codable, Hashable, Sendable, Identifiable {
    /// Stable across subscription refreshes: derived from the outbound itself.
    public var id: String
    public var name: String
    /// "VLESS · gRPC · Reality"
    public var summary: String
    public var host: String
    public var port: Int
    /// sing-box outbound JSON, without a tag.
    public var outbound: String
    /// The share link it was parsed from, kept so manual servers can be edited.
    public var link: String?

    public init(name: String, summary: String, outbound: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: outbound, options: [.sortedKeys, .withoutEscapingSlashes])
        self.outbound = String(decoding: data, as: UTF8.self)
        self.id = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
        self.name = name
        self.summary = summary
        self.host = outbound["server"] as? String ?? ""
        self.port = outbound["server_port"] as? Int ?? 0
    }

    /// Country flag emoji found in the name ("🇳🇱 Amsterdam" → "🇳🇱").
    public var flag: String? {
        let scalars = Array(name.unicodeScalars)
        let isRegional = { (s: Unicode.Scalar) in (0x1F1E6...0x1F1FF).contains(s.value) }
        for i in scalars.indices.dropLast() where isRegional(scalars[i]) && isRegional(scalars[i + 1]) {
            return String(String.UnicodeScalarView(scalars[i...i + 1]))
        }
        return nil
    }

    /// Two-letter country code from the flag ("🇳🇱" → "NL").
    public var countryCode: String? {
        guard let flag else { return nil }
        let letters = flag.unicodeScalars.compactMap { Unicode.Scalar($0.value - 0x1F1A5) }.map { String($0) }.joined()
        return letters.count == 2 ? letters : nil
    }

    /// Name without the flag and surrounding spaces.
    /// TCP-based protocols can be pinged with a TCP connect; QUIC ones (Hysteria2, TUIC) cannot.
    public var isUDP: Bool { outbound.contains(#""type":"hysteria2""#) || outbound.contains(#""type":"tuic""#) }

    public var displayName: String {
        guard let flag else { return name }
        let trimmed = name.replacingOccurrences(of: flag, with: "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }
}

/// Share-link parser for everything Kitsune can connect to.
public enum ProxyLink {
    public enum ParseError: Error, Equatable {
        case unsupportedScheme(String)
        case invalid(String)
    }

    public static func parse(_ link: String) throws -> ServerConfig {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = trimmed.prefix { $0 != ":" }.lowercased()
        switch scheme {
        case "vless":
            let vless = try VLESSLink(trimmed)
            var server = try ServerConfig(name: vless.name, summary: vless.summary, outbound: vless.outbound)
            server.link = trimmed
            return server
        case "hysteria2", "hy2":
            var server = try hysteria2(trimmed)
            server.link = trimmed
            return server
        default:
            throw ParseError.unsupportedScheme(scheme)
        }
    }

    // shortcut: single port only; port ranges (mport) need sing-box server_ports, add when a provider uses them.
    private static func hysteria2(_ link: String) throws -> ServerConfig {
        guard let url = URLComponents(string: link), let host = url.host, !host.isEmpty,
              let port = url.port, (1...65535).contains(port),
              let password = url.user.flatMap({ $0.removingPercentEncoding }), !password.isEmpty
        else { throw ParseError.invalid("hysteria2") }
        let query = url.queryDictionary
        var tls: [String: Any] = ["enabled": true, "server_name": query["sni"] ?? host]
        if query["insecure"] == "1" { tls["insecure"] = true }
        var outbound: [String: Any] = [
            "type": "hysteria2",
            "server": host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
            "server_port": port,
            "password": password,
            "tls": tls,
        ]
        if query["obfs"] == "salamander", let obfsPassword = query["obfs-password"] {
            outbound["obfs"] = ["type": "salamander", "password": obfsPassword]
        }
        let name = url.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? host
        return try ServerConfig(name: name, summary: "Hysteria2 · QUIC", outbound: outbound)
    }
}
