import Testing
@testable import Shared

let sampleLink = "vless://11111111-2222-3333-4444-555555555555@example.com:443?type=tcp&security=reality&pbk=PUBKEY&sid=abcd&sni=www.microsoft.com&fp=safari&flow=xtls-rprx-vision#Test%20NL"

@Test func parsesRealityLink() throws {
    let link = try VLESSLink(sampleLink)
    #expect(link.uuid == "11111111-2222-3333-4444-555555555555")
    #expect(link.host == "example.com")
    #expect(link.port == 443)
    #expect(link.flow == "xtls-rprx-vision")
    #expect(link.serverName == "www.microsoft.com")
    #expect(link.publicKey == "PUBKEY")
    #expect(link.shortID == "abcd")
    #expect(link.fingerprint == "safari")
    #expect(link.name == "Test NL")
}

@Test func stripsIPv6Brackets() throws {
    let link = try VLESSLink("vless://u@[2001:db8::1]:443?security=reality&pbk=k&sni=a.com")
    #expect(link.host == "2001:db8::1")
    #expect(link.fingerprint == "chrome")
    #expect(link.name == "2001:db8::1")
}

@Test func rejectsBadLinks() {
    #expect(throws: VLESSLink.ParseError.notVLESS) { try VLESSLink("trojan://x@h:1") }
    #expect(throws: VLESSLink.ParseError.unsupported("security=xtls")) { try VLESSLink("vless://u@h:443?security=xtls&sni=a") }
    #expect(throws: VLESSLink.ParseError.unsupported("type=kcp")) { try VLESSLink("vless://u@h:443?security=reality&type=kcp&pbk=k&sni=a") }
    #expect(throws: VLESSLink.ParseError.missing("pbk")) { try VLESSLink("vless://u@h:443?security=reality&sni=a") }
    #expect(throws: VLESSLink.ParseError.missing("port")) { try VLESSLink("vless://u@h?security=reality&pbk=k&sni=a") }
}

@Test func grpcRealityOutbound() throws {
    let link = try VLESSLink("vless://u@h.example:443?type=grpc&serviceName=svc&security=reality&pbk=k&sni=a.com#gRPC")
    #expect(link.summary == "VLESS · gRPC · Reality")
    #expect((link.outbound["transport"] as? [String: String]) == ["type": "grpc", "service_name": "svc"])
    #expect(link.flow == nil)
}

@Test func wsTLSOutbound() throws {
    let link = try VLESSLink("vless://u@h.example:443?type=ws&path=%2Fws&host=cdn.example&security=tls&sni=cdn.example")
    #expect(link.summary == "VLESS · WS · TLS")
    let transport = try #require(link.outbound["transport"] as? [String: Any])
    #expect(transport["path"] as? String == "/ws")
    #expect((transport["headers"] as? [String: String])?["Host"] == "cdn.example")
}
