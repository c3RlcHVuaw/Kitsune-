import Foundation

/// Builds the sing-box JSON config the PacketTunnel extension runs.
///
/// Route order (ТЗ 4.3): sniff → DNS → private nets direct → user "always direct" → user "always VPN"
/// → Russian domain lists → Russian IP list → everything else through the proxy.
public enum ConfigBuilder {
    /// Local-only control API the app uses to measure real latency through each server.
    public struct Controller: Sendable {
        public var port: Int
        public var secret: String
        public init(port: Int, secret: String) { self.port = port; self.secret = secret }
    }

    /// Outbound tag of a server inside the config.
    public static func tag(for server: ServerConfig) -> String { "s-\(server.id)" }

    /// - Parameters:
    ///   - server: the server traffic goes through.
    ///   - servers: every other server, added to the `proxy` selector so they can be latency-tested.
    ///   - bundledRuleSets: folder with `<tag>.srs` snapshots, used until the first successful download.
    ///   - controller: enables the local control API.
    public static func build(_ server: ServerConfig, servers: [ServerConfig] = [], routing: RoutingSettings = RoutingSettings(),
                             bundledRuleSets: String? = nil, controller: Controller? = nil, share: LANShare? = nil, findProcess: Bool = false) throws -> String {
        var routeRules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
            ["ip_is_private": true, "outbound": "direct"],
        ]
        var dnsRules: [[String: Any]] = []

        if routing.usesUserLists {
            // Per-app rules first (macOS core only; harmless elsewhere): they win over site lists.
            let known = Set(([server] + servers).map(\.id))
            for (app, id) in routing.appServers.sorted(by: { $0.key < $1.key }) where known.contains(id) {
                routeRules.append(["process_name": [app], "outbound": "s-\(id)"])
            }
            if !routing.directApps.isEmpty { routeRules.append(["process_name": routing.directApps, "outbound": "direct"]) }
            if !routing.proxyApps.isEmpty { routeRules.append(["process_name": routing.proxyApps, "outbound": "proxy"]) }
            if let rule = match(routing.direct) {
                routeRules.append(rule.merging(["outbound": "direct"]) { $1 })
                if let domains = rule["domain_suffix"] { dnsRules.append(["domain_suffix": domains, "server": "russia"]) }
            }
            if let rule = match(routing.effectiveProxy) {
                routeRules.append(rule.merging(["outbound": "proxy"]) { $1 })
                if let domains = rule["domain_suffix"] { dnsRules.append(["domain_suffix": domains, "server": "remote"]) }
            }
        }

        var ruleSets: [[String: Any]] = []
        if routing.profile == .russiaDirect {
            let domainTags = RuleSources.domainSets.map(\.0)
            let ipTags = RuleSources.ipSets.map(\.0)
            routeRules.append(["domain_suffix": RuleSources.russianTLDs, "rule_set": domainTags, "outbound": "direct"])
            routeRules.append(["rule_set": ipTags, "outbound": "direct"])
            dnsRules.append(["domain_suffix": RuleSources.russianTLDs, "rule_set": domainTags, "server": "russia"])
            // Load order in sing-box: cached download → bundled snapshot (initial_path) → fresh download.
            ruleSets = (RuleSources.domainSets + RuleSources.ipSets).map { tag, path in
                var ruleSet: [String: Any] = [
                    "type": "remote",
                    "tag": tag,
                    "format": "binary",
                    "url": "\(RuleSources.base)/\(path)",
                    "http_client": ["detour": "proxy"], // GitHub may be unreachable directly from Russia
                    "update_interval": "24h",
                ]
                if let bundledRuleSets { ruleSet["initial_path"] = "\(bundledRuleSets)/\(tag).srs" }
                return ruleSet
            }
        }

        if routing.blockAds {
            var ads: [String: Any] = [
                "type": "remote", "tag": RuleSources.adsSet.0, "format": "binary",
                "url": "\(RuleSources.base)/\(RuleSources.adsSet.1)",
                "http_client": ["detour": "proxy"], "update_interval": "24h",
            ]
            if let bundledRuleSets { ads["initial_path"] = "\(bundledRuleSets)/\(RuleSources.adsSet.0).srs" }
            ruleSets.append(ads)
            routeRules.insert(["rule_set": [RuleSources.adsSet.0], "action": "reject"], at: 2) // before every direct/proxy rule
        }

        if routing.blockIPv6 { routeRules.insert(["ip_version": 6, "action": "reject"], at: 2) }

        var route: [String: Any] = [
            "rules": routeRules,
            "final": "proxy",
            "auto_detect_interface": true,
            // Resolves the proxy server's own hostname outside the tunnel.
            "default_domain_resolver": "russia",
        ]
        if !ruleSets.isEmpty { route["rule_set"] = ruleSets }
        // process_name rules need the core to look up which process owns each connection.
        if findProcess { route["find_process"] = true } // lets the app list which program uses the traffic
        if routing.usesUserLists, !(routing.directApps + routing.proxyApps).isEmpty || !routing.appServers.isEmpty { route["find_process"] = true }

        var dns: [String: Any] = [
            "servers": [
                ["type": "https", "tag": "remote", "server": routing.dns.address, "detour": "proxy"],
                // No detour: DNS servers without one dial directly, bound to the physical interface.
                ["type": "udp", "tag": "russia", "server": RuleSources.russianDNS],
            ],
            "final": "remote",
        ]
        if !dnsRules.isEmpty { dns["rules"] = dnsRules }
        if routing.blockIPv6 { dns["strategy"] = "ipv4_only" }

        var config: [String: Any] = [
            "log": ["level": "info"],
            "dns": dns,
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
                "strict_route": true,
            ]],
            "outbounds": try proxyOutbounds(selected: server, others: servers) + [["type": "direct", "tag": "direct"]],
            "route": route,
        ]
        if let share, share.isSafe, var inbounds = config["inbounds"] as? [[String: Any]] {
            inbounds.append([
                "type": "mixed", // HTTP and SOCKS5 on one port
                "tag": "lan-in",
                "listen": "0.0.0.0",
                "listen_port": share.port,
                "users": [["username": share.username, "password": share.password]],
            ])
            config["inbounds"] = inbounds
        }
        var experimental: [String: Any] = [:]
        // Keeps downloaded rule-sets between launches, so a failed update falls back to the last good copy.
        if !ruleSets.isEmpty { experimental["cache_file"] = ["enabled": true] }
        if let controller {
            experimental["clash_api"] = ["external_controller": "127.0.0.1:\(controller.port)", "secret": controller.secret]
        }
        if !experimental.isEmpty { config["experimental"] = experimental }

        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// Every server as its own outbound, plus a `proxy` selector defaulting to the chosen one.
    private static func proxyOutbounds(selected: ServerConfig, others: [ServerConfig]) throws -> [[String: Any]] {
        var seen = Set<String>()
        let all = ([selected] + others).filter { seen.insert($0.id).inserted }
        var outbounds: [[String: Any]] = try all.map { server in
            guard var outbound = try JSONSerialization.jsonObject(with: Data(server.outbound.utf8)) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            outbound["tag"] = tag(for: server)
            return outbound
        }
        outbounds.append([
            "type": "selector",
            "tag": "proxy",
            "outbounds": all.map(tag(for:)),
            "default": tag(for: selected),
        ])
        return outbounds
    }

    /// One sing-box rule matching any of the entries; invalid entries are skipped.
    private static func match(_ entries: [String]) -> [String: Any]? {
        let parsed = entries.compactMap { try? RouteEntry($0) }
        var rule: [String: Any] = [:]
        let domains = parsed.compactMap { if case .domain(let d) = $0 { d } else { nil } }
        let cidrs = parsed.compactMap { if case .cidr(let c) = $0 { c } else { nil } }
        if !domains.isEmpty { rule["domain_suffix"] = domains }
        if !cidrs.isEmpty { rule["ip_cidr"] = cidrs }
        return rule.isEmpty ? nil : rule
    }
}
