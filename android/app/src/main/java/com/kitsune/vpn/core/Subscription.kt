package com.kitsune.vpn.core

/** Metadata a subscription server sends in response headers (Marzban / Remnawave / 3x-ui conventions). */
data class SubscriptionInfo(
    val title: String? = null,
    val upload: Long? = null,
    val download: Long? = null,
    /** null or 0 means unlimited. */
    val total: Long? = null,
    /** Epoch seconds. */
    val expire: Long? = null,
    val updateIntervalHours: Int? = null,
    val announce: String? = null,
    val links: List<String> = emptyList(),
) {
    val used: Long? get() = if (upload == null && download == null) null else (upload ?: 0) + (download ?: 0)

    companion object {
        private val urlPattern = Regex("""https?://[^\s<>"]+""")

        /** Header names are matched case-insensitively. */
        fun parse(headers: Map<String, String>): SubscriptionInfo {
            val h = headers.mapKeys { it.key.lowercase() }
            val announce = h["announce"]?.let(::decodeText)
            val support = h["support-url"]?.let(::link)
            val site = h["profile-web-page-url"]?.let(::link)
            val others = h.filter { it.key.endsWith("url") && it.key !in listOf("support-url", "profile-web-page-url") }
                .toSortedMap().values.mapNotNull(::link) + (announce?.let { urlPattern.findAll(it).map { m -> m.value }.toList() } ?: emptyList())
            var upload: Long? = null; var download: Long? = null; var total: Long? = null; var expire: Long? = null
            h["subscription-userinfo"]?.split(';')?.forEach { pair ->
                val kv = pair.split('=', limit = 2).map { it.trim() }
                val value = kv.getOrNull(1)?.toLongOrNull() ?: return@forEach
                when (kv[0]) { "upload" -> upload = value; "download" -> download = value; "total" -> total = value; "expire" -> expire = value.takeIf { it > 0 } }
            }
            return SubscriptionInfo(
                title = h["profile-title"]?.let(::decodeText), upload = upload, download = download, total = total, expire = expire,
                updateIntervalHours = h["profile-update-interval"]?.trim()?.toIntOrNull(), announce = announce,
                links = (listOfNotNull(support, site) + others).distinct(),
            )
        }

        private fun link(value: String): String? =
            decodeText(value).trim().takeIf { it.startsWith("http://") || it.startsWith("https://") || it.startsWith("tg://") }

        /** Some panels send `base64:<data>` to carry non-ASCII text in headers. */
        private fun decodeText(value: String): String {
            if (!value.startsWith("base64:")) return value
            return Base64Lite.decode(value.removePrefix("base64:"))?.let { String(it, Charsets.UTF_8) } ?: value
        }
    }
}

/** Turns a subscription response body into servers. */
object SubscriptionParser {
    /** Outbound types Kitsune passes through from sing-box JSON subscriptions. */
    private val proxyTypes = setOf("vless", "vmess", "trojan", "shadowsocks", "hysteria2", "tuic", "wireguard")

    /** Parsed servers and how many entries were skipped as unsupported. */
    data class Result(val servers: List<ServerConfig>, val skipped: Int)

    @Suppress("UNCHECKED_CAST")
    fun servers(body: String): Result {
        val json = Json.obj(body)
        (json?.get("outbounds") as? List<Map<String, Any?>>)?.let { return fromSingBox(it) }
        var text = body.trim()
        if (!text.contains("://")) base64(text)?.let { text = it }
        var skipped = 0
        val servers = text.lines().map { it.trim() }.filter { it.isNotEmpty() }.mapNotNull {
            try { ProxyLink.parse(it) } catch (_: ParseException) { skipped++; null }
        }
        return Result(servers.distinctBy { it.id }, skipped)
    }

    private fun fromSingBox(outbounds: List<Map<String, Any?>>): Result {
        var skipped = 0
        val servers = outbounds.mapNotNull { source ->
            val type = source["type"] as? String
            if (type == null || type !in proxyTypes) return@mapNotNull null // selectors, direct, dns…
            val outbound = source.toMutableMap()
            val name = outbound.remove("tag") as? String ?: type
            outbound.remove("detour") // points at tags from the provider's config, not ours
            ServerConfig.create(name, summary(outbound), outbound).also { if (it.host.isEmpty()) skipped++ }
        }
        return Result(servers.distinctBy { it.id }, skipped)
    }

    @Suppress("UNCHECKED_CAST")
    private fun summary(outbound: Map<String, Any?>): String {
        val type = (outbound["type"] as? String ?: "").uppercase().replace("HYSTERIA2", "Hysteria2").replace("SHADOWSOCKS", "Shadowsocks").replace("WIREGUARD", "WireGuard")
        val transport = (outbound["transport"] as? Map<String, Any?>)?.get("type") as? String
        val tls = outbound["tls"] as? Map<String, Any?>
        val security = if (tls?.get("reality") != null) "Reality" else if (tls?.get("enabled") == true) "TLS" else null
        return listOfNotNull(type, transport?.let { if (it == "grpc") "gRPC" else it.uppercase() }, security).joinToString(" · ")
    }

    private fun base64(text: String): String? = Base64Lite.decode(text)?.let { String(it, Charsets.UTF_8) }
}

/** Base64 (standard or URL-safe alphabet, padding optional) without android.util, so it also runs in plain JVM tests. */
internal object Base64Lite {
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

    fun decode(text: String): ByteArray? {
        val clean = text.filter { !it.isWhitespace() }.replace('-', '+').replace('_', '/').trimEnd('=')
        if (clean.isEmpty() || clean.length % 4 == 1) return null
        val out = java.io.ByteArrayOutputStream()
        var buffer = 0; var bits = 0
        for (c in clean) {
            val v = ALPHABET.indexOf(c)
            if (v < 0) return null
            buffer = (buffer shl 6) or v; bits += 6
            if (bits >= 8) { bits -= 8; out.write((buffer shr bits) and 0xFF) }
        }
        return out.toByteArray()
    }
}

/** Turns the core's raw log lines into one plain sentence and a hint of what to do. null when the line isn't recognised. */
object ErrorHint {
    /** Checked in order, so the specific causes come before the generic timeout. */
    private val rules = listOf(
        listOf("invalid public_key", "invalid short_id", "short id", "reality verification failed") to "Сервер сменил ключ. Обновите подписку.",
        listOf("authentication failed", "unauthorized", "invalid user", "invalid uuid", "wrong password") to "Сервер не принял ключ. Обновите подписку.",
        listOf("address already in use") to "Порт занят другой программой.",
        listOf("x509", "certificate") to "Сервер предъявил неверный сертификат. Попробуйте другой сервер.",
        listOf("no such host", "lookup ") to "Не удалось найти адрес сервера. Проверьте интернет или выберите другой.",
        listOf("network is unreachable", "no route to host") to "Нет подключения к интернету.",
        listOf("connection refused") to "Сервер отклонил подключение. Выберите другой.",
        listOf("i/o timeout", "context deadline exceeded", "timeout") to "Сервер не отвечает. Выберите другой.",
        listOf("handshake", "tls:") to "Не удалось установить защищённое соединение. Попробуйте другой сервер.",
    )

    fun explain(raw: String): String? {
        val line = raw.lowercase()
        return rules.firstOrNull { (needles, _) -> needles.any { line.contains(it) } }?.second
    }
}
