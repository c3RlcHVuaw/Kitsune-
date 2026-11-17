import Foundation
import Testing
@testable import Shared

@Test(arguments: [
    ("vless-reality", RoutingSettings(profile: .allVPN)),
    ("russia-direct", RoutingSettings(profile: .russiaDirect, direct: ["*.bank.example", "203.0.113.0/24"], proxy: ["news.ru"])),
])
func matchesGoldenConfig(name: String, routing: RoutingSettings) throws {
    let config = try ConfigBuilder.build(ProxyLink.parse(sampleLink), routing: routing)
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Golden"))
    let golden = try String(contentsOf: url, encoding: .utf8)
    // Regenerate after an intentional change: copy the printed config into Golden/<name>.json.
    #expect(config == golden.trimmingCharacters(in: .whitespacesAndNewlines), "\(config)")
}

@Test func doubleHopChainsExitsThroughEntry() throws {
    let exit = try ProxyLink.parse(sampleLink)
    var entry = try ProxyLink.parse(sampleLink.replacingOccurrences(of: "#Test%20NL", with: "#Entry"))
    entry.id = "entry-id"
    let config = try ConfigBuilder.build(exit, servers: [entry], routing: RoutingSettings(entryServerID: entry.id))
    let json = try #require(JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any])
    let outbounds = try #require(json["outbounds"] as? [[String: Any]])
    #expect(outbounds.first { $0["tag"] as? String == ConfigBuilder.tag(for: exit) }?["detour"] as? String == ConfigBuilder.tag(for: entry))
    #expect(outbounds.first { $0["tag"] as? String == ConfigBuilder.tag(for: entry) }?["detour"] == nil)
    let selector = try #require(outbounds.first { $0["tag"] as? String == "proxy" })
    #expect(selector["outbounds"] as? [String] == [ConfigBuilder.tag(for: exit)])
}
