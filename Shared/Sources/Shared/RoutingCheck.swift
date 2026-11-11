import Foundation
import Network

/// Where a site or IP would go under the current routing, as far as it can be known without the core's rule-sets.
public struct RouteDecision: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case localNetwork, userDirect, userProxy, russianDomain, allThroughVPN, otherwise
    }

    public let direct: Bool
    public let reason: Reason
}

extension RoutingSettings {
    /// Same order as the generated config: local network, user "direct", user "VPN", then the Russian rules, then VPN.
    /// The big Russian service lists (banks, marketplaces) live in the core's rule-sets and can't be checked here:
    /// only the `.ru` / `.рф` / `.su` domain rule is, so `.otherwise` may still go direct for a listed Russian service.
    public func decide(_ input: String) throws(RouteEntry.ParseError) -> RouteDecision {
        let entry = try RouteEntry(input)
        if case .cidr(let value) = entry, Self.isLocal(value) { return RouteDecision(direct: true, reason: .localNetwork) }
        if profile == .allVPN { return RouteDecision(direct: false, reason: .allThroughVPN) }
        if usesUserLists {
            if direct.contains(where: { Self.matches($0, entry) }) { return RouteDecision(direct: true, reason: .userDirect) }
            if effectiveProxy.contains(where: { Self.matches($0, entry) }) { return RouteDecision(direct: false, reason: .userProxy) }
        }
        if profile == .russiaDirect, case .domain(let host) = entry,
           ["ru", "su", "xn--p1ai"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return RouteDecision(direct: true, reason: .russianDomain)
        }
        return RouteDecision(direct: false, reason: .otherwise)
    }

    private static func matches(_ stored: String, _ entry: RouteEntry) -> Bool {
        guard let rule = try? RouteEntry(stored) else { return false }
        switch (rule, entry) {
        case (.domain(let suffix), .domain(let host)): return host == suffix || host.hasSuffix("." + suffix)
        case (.cidr(let range), .cidr(let address)): return contains(range, address)
        default: return false
        }
    }

    private static func isLocal(_ address: String) -> Bool {
        ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16"].contains { contains($0, address) }
            || address.hasPrefix("::1/") || address.lowercased().hasPrefix("fe80:")
    }

    /// IPv4 only; an IPv6 range matches just the identical address.
    private static func contains(_ range: String, _ address: String) -> Bool {
        let rangeParts = range.split(separator: "/"), addressHost = String(address.split(separator: "/")[0])
        guard rangeParts.count == 2, let prefix = Int(rangeParts[1]),
              let base = IPv4Address(String(rangeParts[0])), let target = IPv4Address(addressHost) else {
            return range == address
        }
        func value(_ ip: IPv4Address) -> UInt32 { ip.rawValue.reduce(0) { $0 << 8 | UInt32($1) } }
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        return value(base) & mask == value(target) & mask
    }
}
