import Testing
@testable import Shared

struct RoutingCheckTests {
    @Test func russianDomainGoesDirect() throws {
        let decision = try RoutingSettings().decide("https://www.example.ru/page")
        #expect(decision == RouteDecision(direct: true, reason: .russianDomain))
    }

    @Test func otherSiteGoesThroughVPN() throws {
        #expect(try RoutingSettings().decide("example.com") == RouteDecision(direct: false, reason: .otherwise))
    }

    @Test func userDirectBeatsUserProxyAndSubdomainsMatch() throws {
        let routing = RoutingSettings(direct: ["example.com"], proxy: ["example.com"])
        #expect(try routing.decide("a.example.com") == RouteDecision(direct: true, reason: .userDirect))
    }

    @Test func userProxyBeatsRussianDomain() throws {
        let routing = RoutingSettings(proxy: ["example.ru"])
        #expect(try routing.decide("example.ru") == RouteDecision(direct: false, reason: .userProxy))
    }

    @Test func localNetworkIsAlwaysDirect() throws {
        let routing = RoutingSettings(profile: .allVPN)
        #expect(try routing.decide("192.168.1.10") == RouteDecision(direct: true, reason: .localNetwork))
    }

    @Test func allVPNIgnoresRussianDomains() throws {
        #expect(try RoutingSettings(profile: .allVPN).decide("example.ru") == RouteDecision(direct: false, reason: .allThroughVPN))
    }

    @Test func ipRangeInUserList() throws {
        let routing = RoutingSettings(direct: ["8.8.0.0/16"])
        #expect(try routing.decide("8.8.4.4") == RouteDecision(direct: true, reason: .userDirect))
        #expect(try routing.decide("9.9.9.9") == RouteDecision(direct: false, reason: .otherwise))
    }

    @Test func garbageThrows() {
        #expect(throws: RouteEntry.ParseError.self) { try RoutingSettings().decide("") }
    }
}
