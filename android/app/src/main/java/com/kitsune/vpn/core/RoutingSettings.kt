package com.kitsune.vpn.core

import java.net.IDN
import java.net.InetAddress

enum class RouteProfile { RussiaDirect, AllVPN, Custom }

/** Resolver for everything that goes through the tunnel. */
enum class DnsProvider(val address: String, val title: String) {
    Cloudflare("1.1.1.1", "Cloudflare"), Google("8.8.8.8", "Google"), Quad9("9.9.9.9", "Quad9"), AdGuard("94.140.14.14", "AdGuard"),
}

enum class RoutePreset(val domains: List<String>) {
    Streaming(listOf("netflix.com", "nflxvideo.net", "youtube.com", "googlevideo.com", "ytimg.com", "spotify.com", "scdn.co",
        "twitch.tv", "ttvnw.net", "disneyplus.com", "hulu.com", "primevideo.com")),
    Games(listOf("steampowered.com", "steamcommunity.com", "steamstatic.com", "epicgames.com", "riotgames.com",
        "leagueoflegends.com", "ea.com", "battle.net", "blizzard.com", "ubisoft.com", "roblox.com")),
    Messengers(listOf("telegram.org", "t.me", "telegra.ph", "whatsapp.com", "whatsapp.net", "signal.org",
        "discord.com", "discord.gg", "discordapp.com", "viber.com")),
}

/** What goes direct and what goes through the tunnel. Saved as JSON; every field has a default so old settings still load. */
data class RoutingSettings(
    val profile: RouteProfile = RouteProfile.RussiaDirect,
    val dns: DnsProvider = DnsProvider.Cloudflare,
    val blockAds: Boolean = false,
    /** Rejects IPv6 traffic and IPv6 DNS answers: servers without IPv6 would otherwise leak it silently. */
    val blockIPv6: Boolean = false,
    /** "Always direct" entries: domains (`example.com`) or IPs/CIDRs. */
    val direct: List<String> = emptyList(),
    /** "Always through VPN" entries, same format. */
    val proxy: List<String> = emptyList(),
    val presets: Set<RoutePreset> = emptySet(),
    /** Android package names that bypass the tunnel / always use it. */
    val directApps: List<String> = emptyList(),
    val proxyApps: List<String> = emptyList(),
    /** Double hop: id of the entry server every other server is reached through (null: off). */
    val entryServerId: String? = null,
) {
    val effectiveProxy: List<String> get() = proxy + RoutePreset.entries.filter { it in presets }.flatMap { it.domains }

    /** User lists apply in every profile except "everything through VPN". */
    val usesUserLists: Boolean get() = profile != RouteProfile.AllVPN

    fun toJson(): String = Json.write(mapOf(
        "profile" to profile.name, "dns" to dns.name, "blockAds" to blockAds, "blockIPv6" to blockIPv6,
        "direct" to direct, "proxy" to proxy, "presets" to presets.map { it.name }, "directApps" to directApps,
        "proxyApps" to proxyApps, "entryServerId" to entryServerId,
    ))

    companion object {
        @Suppress("UNCHECKED_CAST")
        fun fromJson(text: String?): RoutingSettings {
            val m = text?.let(Json::obj) ?: return RoutingSettings()
            fun strings(key: String) = (m[key] as? List<Any?>)?.filterIsInstance<String>() ?: emptyList()
            return RoutingSettings(
                profile = RouteProfile.entries.firstOrNull { it.name == m["profile"] } ?: RouteProfile.RussiaDirect,
                dns = DnsProvider.entries.firstOrNull { it.name == m["dns"] } ?: DnsProvider.Cloudflare,
                blockAds = m["blockAds"] as? Boolean ?: false,
                blockIPv6 = m["blockIPv6"] as? Boolean ?: false,
                direct = strings("direct"), proxy = strings("proxy"),
                presets = strings("presets").mapNotNull { n -> RoutePreset.entries.firstOrNull { it.name == n } }.toSet(),
                directApps = strings("directApps"), proxyApps = strings("proxyApps"),
                entryServerId = m["entryServerId"] as? String,
            )
        }
    }
}

/** One user routing entry, normalised: a domain suffix or an IP range. */
sealed class RouteEntry {
    abstract val value: String
    data class Domain(override val value: String) : RouteEntry()
    data class Cidr(override val value: String) : RouteEntry()

    companion object {
        private val hexIp = Regex("^[0-9a-f:.]+$")

        /** Accepts `example.com`, `*.example.com`, `https://example.com/path`, `1.2.3.4`, `10.0.0.0/8`, `2001:db8::/32`. null: not valid. */
        fun parse(raw: String): RouteEntry? {
            var text = raw.trim().lowercase()
            if (text.isEmpty()) return null
            text.indexOf("://").takeIf { it >= 0 }?.let { text = text.substring(it + 3) }
            parseCidr(text)?.let { return it }
            if (isIpWithBadPrefix(text)) return null
            text = text.substringBefore('/')
            text.lastIndexOf(':').takeIf { it >= 0 }?.let { text = text.substring(0, it) } // drop :port
            while (text.startsWith("*.") || text.startsWith(".")) text = text.removePrefix("*.").removePrefix(".")
            val ascii = try { IDN.toASCII(text) } catch (_: IllegalArgumentException) { return null } // пример.рф → xn--e1afmkfd.xn--p1ai
            val labels = ascii.split('.')
            val valid = { l: String -> l.isNotEmpty() && l.length <= 63 && !l.startsWith("-") && !l.endsWith("-") && l.all { it.isLetterOrDigit() || it == '-' } }
            // A numeric last label means a malformed IP, not a domain.
            if (ascii.length > 253 || !labels.all(valid) || labels.last().all { it.isDigit() }) return null
            return Domain(ascii)
        }

        private fun isIp(address: String): Boolean {
            val v4 = address.split('.')
            if (v4.size == 4 && v4.all { it.isNotEmpty() && it.length <= 3 && it.all(Char::isDigit) && it.toInt() <= 255 }) return true
            return address.contains(':') && hexIp.matches(address) && try { InetAddress.getByName(address) is InetAddress } catch (_: Exception) { false }
        }

        private fun isIpWithBadPrefix(text: String): Boolean = text.contains('/') && isIp(text.substringBefore('/')) && parseCidr(text) == null

        private fun parseCidr(text: String): Cidr? {
            val parts = text.split('/', limit = 2)
            val address = parts[0]
            if (!isIp(address)) return null
            val max = if (address.contains(':')) 128 else 32
            if (parts.size == 1) return Cidr("$address/$max")
            val prefix = parts[1].toIntOrNull() ?: return null
            return if (prefix in 0..max) Cidr("$address/$prefix") else null
        }
    }
}
