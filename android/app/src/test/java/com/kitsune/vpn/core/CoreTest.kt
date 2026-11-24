package com.kitsune.vpn.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class CoreTest {
    private val pbk = "7UyqvDf3r3S6ZX0nKqX7Dq1m8XvZ2kYb1hQwP0aBcDe"
    private val vless = "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=reality&sni=www.microsoft.com&pbk=$pbk&sid=ab12&fp=chrome&flow=xtls-rprx-vision&type=tcp#%F0%9F%87%B3%F0%9F%87%B1%20Amsterdam"

    @Test fun vlessRealityParses() {
        val s = ProxyLink.parse(vless)
        assertEquals("example.com", s.host); assertEquals(443, s.port)
        assertEquals("VLESS · TCP · Reality", s.summary)
        assertEquals("🇳🇱 Amsterdam", s.name); assertEquals("NL", s.countryCode); assertEquals("Amsterdam", s.displayName)
        val out = Json.obj(s.outbound)!!
        assertEquals("vless", out["type"]); assertEquals("xtls-rprx-vision", out["flow"])
        assertEquals(12 * 2, s.id.length)
        assertEquals(s.id, ProxyLink.parse(vless).id) // stable
    }

    @Test fun vlessMissingPieces() {
        for (bad in listOf("vless://@example.com:443", "vless://u@:443", "vless://u@example.com", "vless://u@example.com:443?security=reality&sni=a", "vless://u@e.com:443?type=quic")) {
            try { ProxyLink.parse(bad); fail(bad) } catch (_: ParseException) {}
        }
        try { ProxyLink.parse("ss://abc"); fail() } catch (_: ParseException) {}
    }

    @Test fun hysteria2Parses() {
        val s = ProxyLink.parse("hy2://pass%20word@h.example.com:8443?sni=cdn.example.com&obfs=salamander&obfs-password=x#H")
        val out = Json.obj(s.outbound)!!
        assertEquals("hysteria2", out["type"]); assertEquals("pass word", out["password"]); assertTrue(s.isUDP)
        assertEquals("salamander", (out["obfs"] as Map<*, *>)["type"])
    }

    @Test fun base64Subscription() {
        val links = "$vless\nhy2://p@h.example.com:443#B\nbad://x"
        val body = java.util.Base64.getEncoder().encodeToString(links.toByteArray())
        val result = SubscriptionParser.servers(body)
        assertEquals(2, result.servers.size)
        assertEquals(1, SubscriptionParser.servers(links).skipped)
    }

    @Test fun subscriptionHeaders() {
        val info = SubscriptionInfo.parse(mapOf("Subscription-Userinfo" to "upload=1; download=2; total=10; expire=1767225600", "Profile-Title" to "base64:S2l0c3VuZQ==", "Support-Url" to "https://t.me/x"))
        assertEquals(3L, info.used); assertEquals(10L, info.total); assertEquals("Kitsune", info.title); assertEquals(listOf("https://t.me/x"), info.links)
    }

    @Test fun routeEntries() {
        assertEquals(RouteEntry.Domain("example.com"), RouteEntry.parse("https://*.Example.com:8443/path"))
        assertEquals(RouteEntry.Domain("xn--e1afmkfd.xn--p1ai"), RouteEntry.parse("пример.рф"))
        assertEquals(RouteEntry.Cidr("10.0.0.0/8"), RouteEntry.parse("10.0.0.0/8"))
        assertEquals(RouteEntry.Cidr("1.2.3.4/32"), RouteEntry.parse("1.2.3.4"))
        assertEquals(RouteEntry.Cidr("2001:db8::/32"), RouteEntry.parse("2001:db8::/32"))
        for (bad in listOf("", "1.2.3.4/33", "999.1.1.1", "-a.com", "a..com", "1.2.3")) assertNull(bad, RouteEntry.parse(bad))
    }

    @Test fun routingSettingsRoundTripAndOldFormat() {
        val s = RoutingSettings(profile = RouteProfile.Custom, blockAds = true, direct = listOf("a.com"), presets = setOf(RoutePreset.Games), directApps = listOf("org.x"))
        assertEquals(s, RoutingSettings.fromJson(s.toJson()))
        assertEquals(RoutingSettings(), RoutingSettings.fromJson("""{"profile":"RussiaDirect"}"""))
        assertEquals(RoutingSettings(), RoutingSettings.fromJson(null))
    }

    @Test fun configRussiaDirectOrder() {
        val server = ProxyLink.parse(vless)
        val config = Json.obj(ConfigBuilder.build(server, routing = RoutingSettings(direct = listOf("bank.example"), proxy = listOf("youtube.com")), secret = "s"))!!
        @Suppress("UNCHECKED_CAST") val rules = (config["route"] as Map<String, Any?>)["rules"] as List<Map<String, Any?>>
        assertEquals("sniff", rules[0]["action"]); assertEquals("hijack-dns", rules[1]["action"]); assertEquals(true, rules[2]["ip_is_private"])
        assertEquals("direct", rules[3]["outbound"]); assertEquals("proxy", rules[4]["outbound"])
        assertEquals(listOf("ru", "xn--p1ai", "su"), rules[5]["domain_suffix"]); assertEquals("direct", rules[6]["outbound"])
        @Suppress("UNCHECKED_CAST") val route = config["route"] as Map<String, Any?>
        assertEquals("proxy", route["final"]); assertEquals(4, (route["rule_set"] as List<*>).size)
        @Suppress("UNCHECKED_CAST") val experimental = config["experimental"] as Map<String, Any?>
        assertTrue(experimental.containsKey("clash_api") && experimental.containsKey("cache_file"))
    }

    @Test fun configAllVpnHasNoUserListsOrRuleSets() {
        val config = ConfigBuilder.build(ProxyLink.parse(vless), routing = RoutingSettings(profile = RouteProfile.AllVPN, direct = listOf("a.com"), directApps = listOf("org.x")))
        assertFalse(config.contains("rule_set")); assertFalse(config.contains("a.com")); assertFalse(config.contains("exclude_package"))
    }

    @Test fun configAndroidPackagesAndAdsAndDoubleHop() {
        val a = ProxyLink.parse(vless); val b = ProxyLink.parse("hy2://p@h.example.com:443#B")
        val config = ConfigBuilder.build(a, listOf(b), RoutingSettings(blockAds = true, blockIPv6 = true, directApps = listOf("org.direct"), proxyApps = listOf("org.vpn"), entryServerId = b.id))
        assertTrue(config.contains("\"exclude_package\": [\n"))
        assertTrue(config.contains("\"package_name\"")); assertTrue(config.contains("\"find_process\": true"))
        assertTrue(config.contains("geosite-category-ads-all")); assertTrue(config.contains("ipv4_only"))
        assertNotNull(Json.obj(config))
        @Suppress("UNCHECKED_CAST") val outs = Json.obj(config)!!["outbounds"] as List<Map<String, Any?>>
        assertEquals("s-${b.id}", outs.first { it["tag"] == "s-${a.id}" }["detour"] ?: "")
    }

    @Test fun errorHints() {
        assertEquals("Сервер не отвечает. Выберите другой.", ErrorHint.explain("dial tcp: i/o timeout"))
        assertNull(ErrorHint.explain("something odd"))
    }
}
