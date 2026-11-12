import Foundation
import Testing
@testable import Shared

@Test func parsesHysteria2Link() throws {
    let server = try ProxyLink.parse("hysteria2://p%40ss@hy.example:8443/?sni=cdn.example&obfs=salamander&obfs-password=xyz&insecure=1#%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt")
    #expect(server.summary == "Hysteria2 · QUIC")
    #expect(server.host == "hy.example")
    #expect(server.port == 8443)
    #expect(server.flag == "🇩🇪")
    #expect(server.displayName == "Frankfurt")
    #expect(server.outbound.contains(#""password":"p@ss""#))
    #expect(server.outbound.contains(#""insecure":true"#))
    #expect(server.outbound.contains("salamander"))
}

@Test func rejectsUnknownScheme() {
    #expect(throws: ProxyLink.ParseError.unsupportedScheme("ss")) { try ProxyLink.parse("ss://abc@h:1") }
}

@Test func idIsStableAndNameIndependent() throws {
    let a = try ProxyLink.parse(sampleLink)
    let b = try ProxyLink.parse(sampleLink.replacingOccurrences(of: "#Test%20NL", with: "#Renamed"))
    #expect(a.id == b.id) // a provider renaming a server must not lose the user's selection
}

@Test func parsesBase64Subscription() throws {
    let body = [sampleLink, "hy2://pw@h2.example:443#Two", "ss://unsupported@h:1", ""].joined(separator: "\n")
    let encoded = Data(body.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") // unpadded, as many panels send
    let (servers, skipped) = SubscriptionParser.servers(from: Data(encoded.utf8))
    #expect(servers.map(\.name) == ["Test NL", "Two"])
    #expect(skipped == 1)
}

@Test func parsesPlainSubscriptionAndDedups() {
    let body = "\(sampleLink)\r\n\(sampleLink)\n"
    #expect(SubscriptionParser.servers(from: Data(body.utf8)).servers.count == 1)
}

@Test func parsesSingBoxJSONSubscription() throws {
    let json = """
    {"outbounds":[
      {"type":"selector","tag":"select","outbounds":["🇳🇱 NL"]},
      {"type":"vless","tag":"🇳🇱 NL","server":"nl.example","server_port":443,"uuid":"u","detour":"x",
       "tls":{"enabled":true,"server_name":"a.com","reality":{"enabled":true,"public_key":"k"}},"transport":{"type":"grpc"}},
      {"type":"direct","tag":"direct"}
    ]}
    """
    let (servers, skipped) = SubscriptionParser.servers(from: Data(json.utf8))
    let server = try #require(servers.first)
    #expect(servers.count == 1 && skipped == 0)
    #expect(server.flag == "🇳🇱")
    #expect(server.summary == "VLESS · gRPC · Reality")
    #expect(!server.outbound.contains("detour"))
    #expect(!server.outbound.contains("\"tag\""))
}

@Test func parsesSubscriptionHeaders() {
    let info = SubscriptionInfo.parse(headers: [
        "Subscription-Userinfo": "upload=100; download=900; total=0; expire=1767225600",
        "profile-title": "base64:" + Data("Лиса VPN".utf8).base64EncodedString(),
        "Profile-Update-Interval": "12",
        "announce": "Плановые работы в 03:00",
        "support-url": "https://t.me/support",
    ])
    #expect(info.title == "Лиса VPN")
    #expect(info.used == 1000)
    #expect(info.total == 0)
    #expect(info.expire == Date(timeIntervalSince1970: 1_767_225_600))
    #expect(info.updateIntervalHours == 12)
    #expect(info.announce == "Плановые работы в 03:00")
    #expect(info.supportURL?.absoluteString == "https://t.me/support")
    let more = SubscriptionInfo.parse(headers: ["support-url": "https://t.me/help", "profile-web-page-url": "https://example.com", "announce": "Канал https://t.me/news и https://t.me/help", "announce-url": "https://t.me/promo"])
    #expect(more.links.map(\.absoluteString) == ["https://t.me/help", "https://example.com", "https://t.me/promo", "https://t.me/news"])
}
