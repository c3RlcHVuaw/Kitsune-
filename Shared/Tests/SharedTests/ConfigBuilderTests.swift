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
