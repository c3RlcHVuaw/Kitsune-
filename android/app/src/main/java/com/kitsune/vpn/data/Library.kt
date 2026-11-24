package com.kitsune.vpn.data

import android.content.Context
import com.kitsune.vpn.core.Json
import com.kitsune.vpn.core.ParseException
import com.kitsune.vpn.core.ProxyLink
import com.kitsune.vpn.core.RoutingSettings
import com.kitsune.vpn.core.ServerConfig
import com.kitsune.vpn.core.SubscriptionInfo
import com.kitsune.vpn.core.SubscriptionParser
import com.kitsune.vpn.vpn.Tunnel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.UUID

data class Subscription(
    val id: String, val url: String, val title: String, val serverIds: List<String>,
    val info: SubscriptionInfo? = null, val updatedAt: Long = 0,
)

/** Latency of one server: through the running tunnel, by a direct TCP connect, or failed. */
sealed class Ping {
    data class Tunnel(val ms: Int) : Ping()
    data class Direct(val ms: Int) : Ping()
    data object Failed : Ping()
    val milliseconds: Int? get() = when (this) { is Tunnel -> ms; is Direct -> ms; Failed -> null }
}

class LibraryError(message: String) : Exception(message)

/** Servers, subscriptions, the chosen server and routing settings; kept in SharedPreferences as one JSON document. */
class Library(context: Context) {
    private val prefs = context.getSharedPreferences("library", Context.MODE_PRIVATE)

    private val _servers = MutableStateFlow<List<ServerConfig>>(emptyList())
    val servers: StateFlow<List<ServerConfig>> = _servers
    private val _subscriptions = MutableStateFlow<List<Subscription>>(emptyList())
    val subscriptions: StateFlow<List<Subscription>> = _subscriptions
    private val _selectedId = MutableStateFlow<String?>(null)
    val selectedId: StateFlow<String?> = _selectedId
    private val _pinned = MutableStateFlow<Set<String>>(emptySet())
    val pinned: StateFlow<Set<String>> = _pinned
    private val _routing = MutableStateFlow(RoutingSettings())
    val routing: StateFlow<RoutingSettings> = _routing
    /** "Auto · fastest": before every connect the best server is picked by ping. */
    private val _auto = MutableStateFlow(true)
    val auto: StateFlow<Boolean> = _auto
    private val _pings = MutableStateFlow<Map<String, Ping>>(emptyMap())
    val pings: StateFlow<Map<String, Ping>> = _pings

    init { load() }

    val selected: ServerConfig? get() = _servers.value.firstOrNull { it.id == _selectedId.value } ?: _servers.value.firstOrNull()

    /** Servers that belong to no subscription: added by hand. */
    val manual: List<ServerConfig>
        get() { val owned = _subscriptions.value.flatMap { it.serverIds }.toSet(); return _servers.value.filter { it.id !in owned } }

    fun servers(of: Subscription): List<ServerConfig> = of.serverIds.mapNotNull { id -> _servers.value.firstOrNull { it.id == id } }

    // MARK: adding

    /** A subscription URL, one share link, or several links (one per line) in any text. */
    suspend fun add(text: String) {
        val trimmed = text.trim()
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return addSubscription(trimmed)
        val result = SubscriptionParser.servers(trimmed)
        if (result.servers.isEmpty()) throw LibraryError(if (result.skipped > 0) "Эта ссылка пока не поддерживается" else "Не нашёл сервер в этом тексте")
        _servers.update { old -> old + result.servers.filter { s -> old.none { it.id == s.id } } }
        if (_selectedId.value == null) _selectedId.value = result.servers.first().id
        save()
    }

    fun replace(old: ServerConfig, link: String) {
        val new = try { ProxyLink.parse(link) } catch (e: ParseException) { throw LibraryError("Не удалось разобрать ссылку: ${e.message}") }
        _servers.update { list -> list.map { if (it.id == old.id) new else it } }
        _subscriptions.update { subs -> subs.map { s -> s.copy(serverIds = s.serverIds.map { if (it == old.id) new.id else it }) } }
        if (_selectedId.value == old.id) _selectedId.value = new.id
        save()
    }

    suspend fun addSubscription(url: String) {
        val fetched = fetch(url)
        if (fetched.servers.isEmpty()) throw LibraryError("В подписке нет поддерживаемых серверов")
        val sub = Subscription(UUID.randomUUID().toString(), url, fetched.info.title ?: URL(url).host, fetched.servers.map { it.id }, fetched.info, System.currentTimeMillis())
        _subscriptions.update { it + sub }
        merge(fetched.servers)
        if (_selectedId.value == null) _selectedId.value = fetched.servers.first().id
        save()
    }

    suspend fun refresh(id: String) {
        val sub = _subscriptions.value.firstOrNull { it.id == id } ?: return
        val fetched = fetch(sub.url)
        if (fetched.servers.isEmpty()) return
        _subscriptions.update { list -> list.map { if (it.id == id) it.copy(serverIds = fetched.servers.map { s -> s.id }, info = fetched.info, updatedAt = System.currentTimeMillis(), title = fetched.info.title ?: it.title) else it } }
        merge(fetched.servers)
        save()
    }

    suspend fun refreshAll() { _subscriptions.value.forEach { runCatching { refresh(it.id) } } }

    private fun merge(fresh: List<ServerConfig>) {
        val keep = _subscriptions.value.flatMap { it.serverIds }.toSet() + manual.map { it.id }
        _servers.update { old -> (old.filter { s -> fresh.none { it.id == s.id } } + fresh).filter { it.id in keep || it.id in fresh.map { f -> f.id } } }
    }

    class Fetched(val servers: List<ServerConfig>, val info: SubscriptionInfo)

    private suspend fun fetch(url: String): Fetched = withContext(Dispatchers.IO) {
        try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000; connection.readTimeout = 20000
            connection.setRequestProperty("User-Agent", "Kitsune/0.1")
            if (connection.responseCode !in 200..299) throw LibraryError("Сервер подписки ответил ${connection.responseCode}")
            val headers = connection.headerFields.filterKeys { it != null }.mapValues { it.value.firstOrNull().orEmpty() }
            val body = connection.inputStream.bufferedReader().readText()
            Fetched(SubscriptionParser.servers(body).servers, SubscriptionInfo.parse(headers))
        } catch (e: LibraryError) { throw e } catch (e: java.io.IOException) { throw LibraryError("Не удалось загрузить подписку: ${e.message}") }
    }

    // MARK: editing

    fun select(id: String, auto: Boolean = false) { _selectedId.value = id; _auto.value = auto; save() }
    fun setAuto(on: Boolean) { _auto.value = on; save() }

    fun togglePinned(id: String) { _pinned.update { if (id in it) it - id else it + id }; save() }

    fun remove(server: ServerConfig) {
        _servers.update { list -> list.filter { it.id != server.id } }
        _subscriptions.update { subs -> subs.map { it.copy(serverIds = it.serverIds - server.id) } }
        _pinned.update { it - server.id }
        if (_selectedId.value == server.id) _selectedId.value = _servers.value.firstOrNull()?.id
        if (_routing.value.entryServerId == server.id) setRouting(_routing.value.copy(entryServerId = null))
        save()
    }

    fun remove(sub: Subscription) {
        _subscriptions.update { list -> list.filter { it.id != sub.id } }
        val keep = _subscriptions.value.flatMap { it.serverIds }.toSet() + manual.map { it.id }
        _servers.update { list -> list.filter { it.id in keep || it.id !in sub.serverIds } }
        if (_servers.value.none { it.id == _selectedId.value }) _selectedId.value = _servers.value.firstOrNull()?.id
        save()
    }

    fun setRouting(routing: RoutingSettings) { _routing.value = routing; save() }

    // MARK: ping

    /** Real latency through the running tunnel when it is up, otherwise a TCP connect (TCP-based protocols only). */
    suspend fun ping(servers: List<ServerConfig> = _servers.value) {
        val delays = withContext(Dispatchers.IO) { Tunnel.delays() }
        val result = if (delays != null) servers.associate { it.id to (delays[it.id]?.let { ms -> Ping.Tunnel(ms) } ?: Ping.Failed) }
        else coroutineScope { servers.map { s -> async { s.id to (tcpPing(s) ?: Ping.Failed) } }.awaitAll().toMap() }
        _pings.update { it + result }
    }

    private suspend fun tcpPing(server: ServerConfig): Ping? = withContext(Dispatchers.IO) {
        if (server.isUDP || server.host.isEmpty()) return@withContext null
        val start = System.nanoTime()
        try { Socket().use { it.connect(InetSocketAddress(server.host, server.port), 4000) }; Ping.Direct(((System.nanoTime() - start) / 1_000_000).toInt()) } catch (_: Exception) { null }
    }

    fun fastest(among: List<ServerConfig> = _servers.value): ServerConfig? =
        among.mapNotNull { s -> _pings.value[s.id]?.milliseconds?.let { s to it } }.minByOrNull { it.second }?.first

    // MARK: storage

    @Suppress("UNCHECKED_CAST")
    private fun load() {
        val m = prefs.getString("library", null)?.let(Json::obj) ?: return
        _servers.value = (m["servers"] as? List<Map<String, Any?>>).orEmpty().mapNotNull { s ->
            ServerConfig(s["id"] as? String ?: return@mapNotNull null, s["name"] as? String ?: "", s["summary"] as? String ?: "", s["host"] as? String ?: "",
                (s["port"] as? Number)?.toInt() ?: 0, s["outbound"] as? String ?: return@mapNotNull null, s["link"] as? String)
        }
        _subscriptions.value = (m["subscriptions"] as? List<Map<String, Any?>>).orEmpty().mapNotNull { s ->
            val info = s["info"] as? Map<String, Any?>
            Subscription(s["id"] as? String ?: return@mapNotNull null, s["url"] as? String ?: "", s["title"] as? String ?: "",
                (s["serverIds"] as? List<Any?>).orEmpty().filterIsInstance<String>(), info?.let(::infoFrom), (s["updatedAt"] as? Number)?.toLong() ?: 0)
        }
        _selectedId.value = m["selectedId"] as? String
        _pinned.value = (m["pinned"] as? List<Any?>).orEmpty().filterIsInstance<String>().toSet()
        _auto.value = m["auto"] as? Boolean ?: true
        _routing.value = RoutingSettings.fromJson((m["routing"] as? Map<String, Any?>)?.let { Json.write(it) })
    }

    @Suppress("UNCHECKED_CAST")
    private fun infoFrom(m: Map<String, Any?>) = SubscriptionInfo(
        m["title"] as? String, (m["upload"] as? Number)?.toLong(), (m["download"] as? Number)?.toLong(), (m["total"] as? Number)?.toLong(),
        (m["expire"] as? Number)?.toLong(), (m["updateIntervalHours"] as? Number)?.toInt(), m["announce"] as? String,
        (m["links"] as? List<Any?>).orEmpty().filterIsInstance<String>(),
    )

    private fun save() {
        val doc = mapOf(
            "servers" to _servers.value.map { mapOf("id" to it.id, "name" to it.name, "summary" to it.summary, "host" to it.host, "port" to it.port, "outbound" to it.outbound, "link" to it.link) },
            "subscriptions" to _subscriptions.value.map { s -> mapOf("id" to s.id, "url" to s.url, "title" to s.title, "serverIds" to s.serverIds, "updatedAt" to s.updatedAt,
                "info" to s.info?.let { i -> mapOf("title" to i.title, "upload" to i.upload, "download" to i.download, "total" to i.total, "expire" to i.expire,
                    "updateIntervalHours" to i.updateIntervalHours, "announce" to i.announce, "links" to i.links) }) },
            "selectedId" to _selectedId.value, "pinned" to _pinned.value.toList(), "auto" to _auto.value,
            "routing" to Json.obj(_routing.value.toJson()),
        )
        prefs.edit().putString("library", Json.write(doc)).apply()
    }
}
