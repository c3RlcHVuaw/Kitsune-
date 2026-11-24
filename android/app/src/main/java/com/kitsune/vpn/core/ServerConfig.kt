package com.kitsune.vpn.core

import java.security.MessageDigest

/** One connectable server, whatever it came from (a share link or a subscription). Same shape as the Mac app's ServerConfig. */
data class ServerConfig(
    /** Stable across subscription refreshes: derived from the outbound itself. */
    val id: String,
    val name: String,
    /** "VLESS · gRPC · Reality" */
    val summary: String,
    val host: String,
    val port: Int,
    /** sing-box outbound JSON, without a tag. */
    val outbound: String,
    /** The share link it was parsed from, kept so manual servers can be edited. */
    val link: String? = null,
) {
    /** Country flag emoji found in the name ("🇳🇱 Amsterdam" → "🇳🇱"). */
    val flag: String?
        get() {
            val points = name.codePoints().toArray()
            val regional = { p: Int -> p in 0x1F1E6..0x1F1FF }
            for (i in 0 until points.size - 1) if (regional(points[i]) && regional(points[i + 1])) return String(points, i, 2)
            return null
        }

    /** Two-letter country code from the flag ("🇳🇱" → "NL"). */
    val countryCode: String?
        get() = flag?.codePoints()?.toArray()?.map { (it - 0x1F1A5).toChar() }?.joinToString("")?.takeIf { it.length == 2 }

    /** Name without the flag and surrounding spaces. */
    val displayName: String
        get() {
            val f = flag ?: return name
            return name.replace(f, "").trim().ifEmpty { name }
        }

    /** TCP-based protocols can be pinged with a TCP connect; QUIC ones (Hysteria2, TUIC) cannot. */
    val isUDP: Boolean get() = outbound.contains("\"type\":\"hysteria2\"") || outbound.contains("\"type\":\"tuic\"")

    companion object {
        fun create(name: String, summary: String, outbound: Map<String, Any?>, link: String? = null): ServerConfig {
            val text = Json.write(outbound)
            val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
            return ServerConfig(
                id = digest.take(12).joinToString("") { "%02x".format(it) },
                name = name, summary = summary,
                host = outbound["server"] as? String ?: "",
                port = (outbound["server_port"] as? Number)?.toInt() ?: 0,
                outbound = text, link = link,
            )
        }
    }
}

class ParseException(message: String) : Exception(message)

/** The parts of a share link Kitsune needs; query values are percent-decoded, empty ones dropped, the last duplicate wins. */
internal class UrlParts(
    val scheme: String, val user: String?, val host: String, val port: Int?,
    val query: Map<String, String>, val fragment: String?,
) {
    companion object {
        fun parse(text: String): UrlParts? {
            val schemeEnd = text.indexOf("://")
            if (schemeEnd <= 0) return null
            val scheme = text.substring(0, schemeEnd).lowercase()
            var rest = text.substring(schemeEnd + 3)
            val hash = rest.indexOf('#')
            val fragment = if (hash >= 0) decode(rest.substring(hash + 1)).also { rest = rest.substring(0, hash) } else null
            val q = rest.indexOf('?')
            val query = LinkedHashMap<String, String>()
            if (q >= 0) {
                rest.substring(q + 1).split('&').forEach { pair ->
                    val eq = pair.indexOf('=')
                    if (eq > 0) decode(pair.substring(eq + 1)).takeIf { it.isNotEmpty() }?.let { query[decode(pair.substring(0, eq))] = it }
                }
                rest = rest.substring(0, q)
            }
            val slash = rest.indexOf('/')
            if (slash >= 0) rest = rest.substring(0, slash)
            val at = rest.lastIndexOf('@')
            val user = if (at >= 0) decode(rest.substring(0, at).substringBefore(':')) else null
            val authority = if (at >= 0) rest.substring(at + 1) else rest
            val host: String
            var port: Int? = null
            if (authority.startsWith("[")) {
                val close = authority.indexOf(']')
                if (close < 0) return null
                host = authority.substring(0, close + 1)
                port = authority.substring(close + 1).removePrefix(":").toIntOrNull()
            } else {
                host = authority.substringBeforeLast(':')
                if (authority.contains(':')) port = authority.substringAfterLast(':').toIntOrNull()
            }
            return UrlParts(scheme, user, host, port, query, fragment)
        }

        /** Percent-decoding that leaves '+' alone (it is a plus in a share link, not a space). */
        fun decode(text: String): String {
            if (!text.contains('%')) return text
            return try { java.net.URLDecoder.decode(text.replace("+", "%2B"), "UTF-8") } catch (_: IllegalArgumentException) { text }
        }
    }
}

/** Share-link parser for everything Kitsune can connect to. */
object ProxyLink {
    fun parse(link: String): ServerConfig {
        val trimmed = link.trim()
        return when (val scheme = trimmed.substringBefore(':').lowercase()) {
            "vless" -> VlessLink.parse(trimmed)
            "hysteria2", "hy2" -> hysteria2(trimmed)
            else -> throw ParseException("unsupported scheme: $scheme")
        }
    }

    // shortcut: single port only; port ranges (mport) need sing-box server_ports, add when a provider uses them.
    private fun hysteria2(link: String): ServerConfig {
        val url = UrlParts.parse(link) ?: throw ParseException("hysteria2")
        val port = url.port
        val password = url.user
        if (url.host.isEmpty() || port == null || port !in 1..65535 || password.isNullOrEmpty()) throw ParseException("hysteria2")
        val host = url.host.trim('[', ']')
        val tls = linkedMapOf<String, Any?>("enabled" to true, "server_name" to (url.query["sni"] ?: host))
        if (url.query["insecure"] == "1") tls["insecure"] = true
        val outbound = linkedMapOf<String, Any?>("type" to "hysteria2", "server" to host, "server_port" to port, "password" to password, "tls" to tls)
        val obfs = url.query["obfs-password"]
        if (url.query["obfs"] == "salamander" && obfs != null) outbound["obfs"] = mapOf("type" to "salamander", "password" to obfs)
        return ServerConfig.create(url.fragment?.ifEmpty { null } ?: host, "Hysteria2 · QUIC", outbound, link)
    }
}

/** A `vless://` share link: TCP / gRPC / WebSocket transport over Reality, TLS or plain. */
object VlessLink {
    fun parse(link: String): ServerConfig {
        val url = UrlParts.parse(link)?.takeIf { it.scheme == "vless" } ?: throw ParseException("not vless")
        val q = url.query
        val uuid = url.user?.takeIf { it.isNotEmpty() } ?: throw ParseException("missing uuid")
        if (url.host.isEmpty()) throw ParseException("missing host")
        val port = url.port?.takeIf { it in 1..65535 } ?: throw ParseException("missing port")
        val security = q["security"] ?: "none"
        if (security !in listOf("reality", "tls", "none")) throw ParseException("unsupported security=$security")
        val transport = q["type"] ?: "tcp"
        if (transport !in listOf("tcp", "grpc", "ws")) throw ParseException("unsupported type=$transport")
        val host = url.host.trim('[', ']')
        var fingerprint = q["fp"]
        if (security == "reality") {
            if (q["sni"] == null) throw ParseException("missing sni")
            if (q["pbk"] == null) throw ParseException("missing pbk")
            if (fingerprint == null) fingerprint = "chrome" // Reality requires uTLS
        }
        val outbound = linkedMapOf<String, Any?>("type" to "vless", "server" to host, "server_port" to port, "uuid" to uuid)
        q["flow"]?.let { outbound["flow"] = it }
        if (security != "none") {
            val tls = linkedMapOf<String, Any?>("enabled" to true)
            q["sni"]?.let { tls["server_name"] = it }
            fingerprint?.let { tls["utls"] = mapOf("enabled" to true, "fingerprint" to it) }
            if (security == "reality") tls["reality"] = mapOf("enabled" to true, "public_key" to q["pbk"], "short_id" to (q["sid"] ?: ""))
            outbound["tls"] = tls
        }
        when (transport) {
            "grpc" -> outbound["transport"] = mapOf("type" to "grpc", "service_name" to (q["serviceName"] ?: ""))
            "ws" -> outbound["transport"] = linkedMapOf<String, Any?>("type" to "ws", "path" to (q["path"] ?: "/")).also { ws ->
                q["host"]?.let { ws["headers"] = mapOf("Host" to it) }
            }
        }
        val summary = listOfNotNull("VLESS", transport.uppercase().replace("GRPC", "gRPC"),
            when (security) { "none" -> null; "tls" -> "TLS"; else -> "Reality" }).joinToString(" · ")
        return ServerConfig.create(url.fragment?.ifEmpty { null } ?: host, summary, outbound, link)
    }
}
