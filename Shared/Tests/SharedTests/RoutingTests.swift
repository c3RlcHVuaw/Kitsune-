import Foundation
import Testing
@testable import Shared

@Test(arguments: [
    ("example.com", RouteEntry.domain("example.com")),
    ("  *.Example.COM ", .domain("example.com")),
    (".example.com", .domain("example.com")),
    ("https://shop.example.com:8443/cart?x=1", .domain("shop.example.com")),
    ("1.2.3.4", .cidr("1.2.3.4/32")),
    ("10.0.0.0/8", .cidr("10.0.0.0/8")),
    ("2001:db8::/32", .cidr("2001:db8::/32")),
    ("2001:db8::1", .cidr("2001:db8::1/128")),
])
func parsesRouteEntries(raw: String, expected: RouteEntry) throws {
    #expect(try RouteEntry(raw) == expected)
}

@Test func rejectsBadRouteEntries() {
    #expect(throws: RouteEntry.ParseError.empty) { try RouteEntry("  ") }
    #expect(throws: RouteEntry.ParseError.invalid) { try RouteEntry("exa mple.com") }
    #expect(throws: RouteEntry.ParseError.invalid) { try RouteEntry("-bad-.com") }
    #expect(throws: RouteEntry.ParseError.invalid) { try RouteEntry("10.0.0.0/33") }
    #expect(throws: RouteEntry.ParseError.invalid) { try RouteEntry("10.0.0") }
}

@Test func encodesInternationalDomains() throws {
    #expect(try RouteEntry("пример.рф") == .domain("xn--e1afmkfd.xn--p1ai"))
    #expect(try RouteEntry("https://Яндекс.рф/путь") == .domain("xn--d1acpjx3f.xn--p1ai"))
    #expect(try RouteEntry("münchen.de") == .domain("xn--mnchen-3ya.de"))
}

/// Outbound of each route rule after the fixed prefix (sniff, dns, private), in order.
private func routeOutbounds(_ routing: RoutingSettings) throws -> [String] {
    let json = try ConfigBuilder.build(ProxyLink.parse(sampleLink), routing: routing)
    let config = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let route = try #require(config["route"] as? [String: Any])
    let rules = try #require(route["rules"] as? [[String: Any]])
    #expect(rules[0]["action"] as? String == "sniff")
    #expect(rules[1]["action"] as? String == "hijack-dns")
    #expect(rules[2]["outbound"] as? String == "direct")
    #expect(route["final"] as? String == "proxy")
    return rules.dropFirst(3).map { rule in
        let what = rule["rule_set"] != nil ? "lists" : "user"
        return "\(what)->\(rule["outbound"] as? String ?? "?")"
    }
}

@Test func ruleOrderRussiaDirect() throws {
    let routing = RoutingSettings(profile: .russiaDirect, direct: ["bank.example"], proxy: ["news.ru"])
    // User "always VPN" must beat the Russian lists (news.ru would otherwise match .ru).
    #expect(try routeOutbounds(routing) == ["user->direct", "user->proxy", "lists->direct", "lists->direct"])
}

@Test func ruleOrderAllVPNIgnoresUserLists() throws {
    let routing = RoutingSettings(profile: .allVPN, direct: ["bank.example"], proxy: ["news.ru"])
    #expect(try routeOutbounds(routing) == [])
}

@Test func ruleOrderCustomHasNoRussianLists() throws {
    let routing = RoutingSettings(profile: .custom, direct: ["10.1.0.0/16", "bank.example"], proxy: [])
    #expect(try routeOutbounds(routing) == ["user->direct"])
}

@Test func bundledSnapshotIsTheFallbackForEveryList() throws {
    let json = try ConfigBuilder.build(ProxyLink.parse(sampleLink), routing: RoutingSettings(), bundledRuleSets: "/app/RuleSets")
    let config = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let ruleSets = try #require((config["route"] as? [String: Any])?["rule_set"] as? [[String: Any]])
    #expect(ruleSets.count == 4)
    for ruleSet in ruleSets {
        #expect(ruleSet["initial_path"] as? String == "/app/RuleSets/\(ruleSet["tag"] as! String).srs")
        #expect(ruleSet["download_detour"] == nil) // deprecated in sing-box 1.14
    }
}

@Test func selectorHoldsEveryServerAndDefaultsToTheChosenOne() throws {
    let chosen = try ProxyLink.parse(sampleLink)
    let other = try ProxyLink.parse("hy2://pw@h2.example:443#Two")
    let json = try ConfigBuilder.build(chosen, servers: [other, chosen], controller: .init(port: 19090, secret: "s3cret"))
    let config = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let outbounds = try #require(config["outbounds"] as? [[String: Any]])
    let selector = try #require(outbounds.first { $0["tag"] as? String == "proxy" })
    #expect(selector["type"] as? String == "selector")
    #expect(selector["default"] as? String == ConfigBuilder.tag(for: chosen))
    #expect(selector["outbounds"] as? [String] == [ConfigBuilder.tag(for: chosen), ConfigBuilder.tag(for: other)]) // deduplicated
    let api = try #require((config["experimental"] as? [String: Any])?["clash_api"] as? [String: String])
    #expect(api["external_controller"] == "127.0.0.1:19090") // never on a public interface
    #expect(api["secret"] == "s3cret")
}

@Test func presetsAddDomainsAndOldSettingsStillLoad() throws {
    var routing = RoutingSettings(proxy: ["example.com"])
    routing.presets = [.messengers]
    #expect(routing.effectiveProxy.contains("telegram.org"))
    #expect(try routing.decide("web.telegram.org").direct == false)
    let old = #"{"profile":"russiaDirect","direct":["a.ru"],"proxy":[]}"#
    let decoded = try JSONDecoder().decode(RoutingSettings.self, from: Data(old.utf8))
    #expect(decoded.direct == ["a.ru"] && decoded.presets.isEmpty && decoded.directApps.isEmpty)
}

@Test func appRulesBecomeProcessNameRules() throws {
    let config = try ConfigBuilder.build(ProxyLink.parse(sampleLink), routing: RoutingSettings(directApps: ["Sber"], proxyApps: ["Telegram"]))
    #expect(config.contains("\"process_name\""))
    #expect(config.contains("Telegram") && config.contains("Sber"))
}

@Test func appServerRuleGoesToThatServersOutbound() throws {
    let chosen = try ProxyLink.parse(sampleLink)
    let other = try ProxyLink.parse("hy2://pw@h2.example:443#Two")
    var routing = RoutingSettings()
    routing.appServers = ["Safari": other.id, "Gone": "missing"] // unknown server ids are ignored
    let json = try ConfigBuilder.build(chosen, servers: [other], routing: routing)
    let config = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let route = try #require(config["route"] as? [String: Any])
    let rules = try #require(route["rules"] as? [[String: Any]])
    let appRules = rules.filter { $0["process_name"] != nil }
    #expect(appRules.count == 1)
    #expect(appRules.first?["outbound"] as? String == ConfigBuilder.tag(for: other))
    #expect(route["find_process"] as? Bool == true)
    let old = try JSONDecoder().decode(RoutingSettings.self, from: Data(#"{"profile":"russiaDirect","direct":[],"proxy":[]}"#.utf8))
    #expect(old.appServers.isEmpty)
}

@Test func lanShareAddsAnAuthenticatedInboundOnlyWhenSafe() throws {
    let server = try ProxyLink.parse(sampleLink)
    func inbounds(_ share: LANShare?) throws -> [[String: Any]] {
        let json = try ConfigBuilder.build(server, share: share)
        let config = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try #require(config["inbounds"] as? [[String: Any]])
    }
    #expect(try inbounds(nil).count == 1)
    #expect(try inbounds(LANShare(port: 7890, username: "kitsune", password: "short")).count == 1) // weak password: no proxy
    let open = try inbounds(LANShare(port: 7890, username: "kitsune", password: "correct-horse-battery"))
    #expect(open.count == 2)
    let lan = try #require(open.last)
    #expect(lan["type"] as? String == "mixed")
    #expect(lan["listen_port"] as? Int == 7890)
    #expect((lan["users"] as? [[String: String]])?.first?["password"] == "correct-horse-battery")
}

@Test func dnsChoiceAndAdBlockShapeTheConfig() throws {
    let server = try ProxyLink.parse("vless://11111111-1111-1111-1111-111111111111@example.com:443?security=reality&pbk=abc&sni=a.com&fp=chrome&type=tcp#t")
    func parse(_ routing: RoutingSettings, find: Bool = false) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(ConfigBuilder.build(server, routing: routing, findProcess: find).utf8)) as? [String: Any])
    }
    let plain = try parse(RoutingSettings())
    #expect(!(plain["route"] as! [String: Any]).keys.contains("find_process"))
    #expect(!String(describing: plain).contains("category-ads"))

    let config = try parse(RoutingSettings(dns: .quad9, blockAds: true), find: true)
    let route = config["route"] as! [String: Any]
    #expect(route["find_process"] as? Bool == true)
    let rules = route["rules"] as! [[String: Any]]
    #expect(rules[2]["action"] as? String == "reject") // ahead of all direct rules
    #expect(String(describing: config["dns"]!).contains("9.9.9.9"))
    // Settings saved before these options existed still load.
    let old = try JSONDecoder().decode(RoutingSettings.self, from: Data(#"{"profile":"allVPN","direct":[],"proxy":[]}"#.utf8))
    #expect(old.dns == .cloudflare && !old.blockAds)
}
