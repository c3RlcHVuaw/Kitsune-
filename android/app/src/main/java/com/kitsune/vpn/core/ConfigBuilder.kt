package com.kitsune.vpn.core

/**
 * Builds the sing-box JSON config for Android. Route order mirrors the Mac app (Shared/ConfigBuilder):
 * sniff → DNS → private nets direct → user "always direct" → user "always VPN" → Russian domain lists → Russian IP list → proxy.
 * Differences: the tun inbound carries Android package lists, and per-app "always VPN" uses package_name rules.
 */
object ConfigBuilder {
    const val CONTROLLER_PORT = 19090
    const val BASE = "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box"
    private val domainSets = listOf("geosite-category-ru" to "geosite", "geosite-category-gov-ru" to "geosite", "geosite-ru-available-only-inside" to "geosite")
    private val ipSets = listOf("geoip-ru" to "geoip")
    private const val ADS = "geosite-category-ads-all"
    private val russianTlds = listOf("ru", "xn--p1ai", "su")
    private const val RUSSIAN_DNS = "77.88.8.8"

    fun tag(server: ServerConfig) = "s-${server.id}"

    private fun ruleSetUrl(tag: String, kind: String) = "$BASE/rule-set-$kind/$tag.srs"

    private fun remote(tag: String, kind: String, bundled: String?): Map<String, Any?> {
        val set = linkedMapOf<String, Any?>(
            "type" to "remote", "tag" to tag, "format" to "binary", "url" to ruleSetUrl(tag, kind),
            "http_client" to mapOf("detour" to "proxy"), // GitHub may be unreachable directly from Russia
            "update_interval" to "24h",
        )
        if (bundled != null) set["initial_path"] = "$bundled/$tag.srs"
        return set
    }

    /**
     * @param servers every other server, added to the `proxy` selector so they can be latency-tested.
     * @param bundledRuleSets folder with `<tag>.srs` snapshots, used until the first successful download.
     */
    fun build(server: ServerConfig, servers: List<ServerConfig> = emptyList(), routing: RoutingSettings = RoutingSettings(),
              bundledRuleSets: String? = null, secret: String? = null): String {
        val routeRules = mutableListOf<Map<String, Any?>>(
            mapOf("action" to "sniff"),
            mapOf("protocol" to "dns", "action" to "hijack-dns"),
            mapOf("ip_is_private" to true, "outbound" to "direct"),
        )
        val dnsRules = mutableListOf<Map<String, Any?>>()

        if (routing.usesUserLists) {
            if (routing.proxyApps.isNotEmpty()) routeRules += mapOf("package_name" to routing.proxyApps, "outbound" to "proxy")
            match(routing.direct)?.let { rule ->
                routeRules += rule + ("outbound" to "direct")
                rule["domain_suffix"]?.let { dnsRules += mapOf("domain_suffix" to it, "server" to "russia") }
            }
            match(routing.effectiveProxy)?.let { rule ->
                routeRules += rule + ("outbound" to "proxy")
                rule["domain_suffix"]?.let { dnsRules += mapOf("domain_suffix" to it, "server" to "remote") }
            }
        }

        val ruleSets = mutableListOf<Map<String, Any?>>()
        if (routing.profile == RouteProfile.RussiaDirect) {
            val domainTags = domainSets.map { it.first }
            routeRules += mapOf("domain_suffix" to russianTlds, "rule_set" to domainTags, "outbound" to "direct")
            routeRules += mapOf("rule_set" to ipSets.map { it.first }, "outbound" to "direct")
            dnsRules += mapOf("domain_suffix" to russianTlds, "rule_set" to domainTags, "server" to "russia")
            (domainSets + ipSets).forEach { (tag, kind) -> ruleSets += remote(tag, kind, bundledRuleSets) }
        }
        if (routing.blockAds) {
            ruleSets += remote(ADS, "geosite", bundledRuleSets)
            routeRules.add(2, mapOf("rule_set" to listOf(ADS), "action" to "reject")) // before every direct/proxy rule
        }
        if (routing.blockIPv6) routeRules.add(2, mapOf("ip_version" to 6, "action" to "reject"))

        val route = linkedMapOf<String, Any?>(
            "rules" to routeRules, "final" to "proxy", "auto_detect_interface" to true,
            // Resolves the proxy server's own hostname outside the tunnel.
            "default_domain_resolver" to "russia",
        )
        if (ruleSets.isNotEmpty()) route["rule_set"] = ruleSets
        if (routing.usesUserLists && routing.proxyApps.isNotEmpty()) route["find_process"] = true // package_name needs the connection owner

        val dns = linkedMapOf<String, Any?>(
            "servers" to listOf(
                mapOf("type" to "https", "tag" to "remote", "server" to routing.dns.address, "detour" to "proxy"),
                // No detour: DNS servers without one dial directly, bound to the physical network.
                mapOf("type" to "udp", "tag" to "russia", "server" to RUSSIAN_DNS),
            ),
            "final" to "remote",
        )
        if (dnsRules.isNotEmpty()) dns["rules"] = dnsRules
        if (routing.blockIPv6) dns["strategy"] = "ipv4_only"

        val tun = linkedMapOf<String, Any?>(
            "type" to "tun", "tag" to "tun-in", "address" to listOf("172.19.0.1/30", "fdfe:dcba:9876::1/126"),
            "mtu" to 1500, "auto_route" to true, "strict_route" to true,
        )
        if (routing.usesUserLists && routing.directApps.isNotEmpty()) tun["exclude_package"] = routing.directApps // those apps never enter the tunnel

        val experimental = linkedMapOf<String, Any?>()
        // Keeps downloaded rule-sets between launches, so a failed update falls back to the last good copy.
        if (ruleSets.isNotEmpty()) experimental["cache_file"] = mapOf("enabled" to true)
        if (secret != null) experimental["clash_api"] = mapOf("external_controller" to "127.0.0.1:$CONTROLLER_PORT", "secret" to secret)

        val config = linkedMapOf<String, Any?>(
            "log" to mapOf("level" to "info"), "dns" to dns, "inbounds" to listOf(tun),
            "outbounds" to proxyOutbounds(server, servers, routing.entryServerId) + mapOf("type" to "direct", "tag" to "direct"),
            "route" to route,
        )
        if (experimental.isNotEmpty()) config["experimental"] = experimental
        return Json.write(config, pretty = true)
    }

    /**
     * Every server as its own outbound, plus a `proxy` selector defaulting to the chosen one.
     * With [entryId] (double hop) every other server is dialed through that entry server and leaves the selector.
     */
    private fun proxyOutbounds(selected: ServerConfig, others: List<ServerConfig>, entryId: String?): List<Map<String, Any?>> {
        val all = (listOf(selected) + others).distinctBy { it.id }
        val entry = all.firstOrNull { it.id == entryId && it.id != selected.id }
        val outbounds = all.map { server ->
            val outbound = (Json.obj(server.outbound) ?: throw ParseException("corrupt outbound")).toMutableMap()
            outbound["tag"] = tag(server)
            if (entry != null && server.id != entry.id) outbound["detour"] = tag(entry)
            outbound
        }
        return outbounds + mapOf<String, Any?>(
            "type" to "selector", "tag" to "proxy",
            "outbounds" to all.filter { it.id != entry?.id }.map(::tag), "default" to tag(selected),
        )
    }

    /** One sing-box rule matching any of the entries; invalid entries are skipped. */
    private fun match(entries: List<String>): Map<String, Any?>? {
        val parsed = entries.mapNotNull(RouteEntry::parse)
        val rule = linkedMapOf<String, Any?>()
        parsed.filterIsInstance<RouteEntry.Domain>().map { it.value }.takeIf { it.isNotEmpty() }?.let { rule["domain_suffix"] = it }
        parsed.filterIsInstance<RouteEntry.Cidr>().map { it.value }.takeIf { it.isNotEmpty() }?.let { rule["ip_cidr"] = it }
        return rule.takeIf { it.isNotEmpty() }
    }
}
