package com.kitsune.vpn.vpn

import android.content.Context
import android.content.Intent
import android.os.Build
import com.kitsune.vpn.core.ConfigBuilder
import com.kitsune.vpn.core.RoutingSettings
import com.kitsune.vpn.core.ServerConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom

enum class TunnelStatus { Disconnected, Connecting, Connected, Disconnecting }

data class Speed(val down: Long = 0, val up: Long = 0)

/** What the UI sees of the VPN: one process-wide state, written by [KitsuneVpnService], read by the screens. */
object Tunnel {
    private val _status = MutableStateFlow(TunnelStatus.Disconnected)
    val status: StateFlow<TunnelStatus> = _status
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error
    private val _connectedAt = MutableStateFlow<Long?>(null)
    val connectedAt: StateFlow<Long?> = _connectedAt
    private val _speed = MutableStateFlow(Speed())
    val speed: StateFlow<Speed> = _speed
    private val _totals = MutableStateFlow(Speed())
    val totals: StateFlow<Speed> = _totals
    /** Id of the server the running tunnel was started with. */
    private val _activeId = MutableStateFlow<String?>(null)
    val activeId: StateFlow<String?> = _activeId

    /** Protects the local control API: only this app knows it. */
    val secret: String by lazy { ByteArray(16).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) } }

    internal fun set(status: TunnelStatus, error: String? = null) {
        _status.value = status
        if (status == TunnelStatus.Connecting) _error.value = null
        if (error != null) _error.value = error
        if (status == TunnelStatus.Connected) _connectedAt.value = System.currentTimeMillis()
        if (status == TunnelStatus.Disconnected) { _connectedAt.value = null; _speed.value = Speed(); _totals.value = Speed(); _activeId.value = null }
    }

    internal fun setActive(id: String?) { _activeId.value = id }
    internal fun setSpeed(speed: Speed, totals: Speed) { _speed.value = speed; _totals.value = totals }

    private fun configFile(context: Context) = File(context.filesDir, "config.json")

    /** Writes the config for [server] and starts or live-reloads the tunnel. */
    fun connect(context: Context, server: ServerConfig, servers: List<ServerConfig>, routing: RoutingSettings) {
        val rules = File(context.filesDir, "rulesets").path
        configFile(context).writeText(ConfigBuilder.build(server, servers, routing, bundledRuleSets = rules, secret = secret))
        val intent = Intent(context, KitsuneVpnService::class.java).setAction(KitsuneVpnService.ACTION_START).putExtra("server", server.id)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
    }

    fun disconnect(context: Context) {
        if (status.value == TunnelStatus.Disconnected) return
        context.startService(Intent(context, KitsuneVpnService::class.java).setAction(KitsuneVpnService.ACTION_STOP))
    }

    internal fun config(context: Context): String? = configFile(context).takeIf { it.exists() }?.readText()

    /** Real latency through each server in the running tunnel (an HTTPS request via every outbound, done by sing-box): id → ms. */
    fun delays(): Map<String, Int>? {
        if (status.value != TunnelStatus.Connected) return null
        return try {
            val url = URL("http://127.0.0.1:${ConfigBuilder.CONTROLLER_PORT}/group/proxy/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000")
            val connection = (url.openConnection() as HttpURLConnection).apply {
                setRequestProperty("Authorization", "Bearer $secret"); connectTimeout = 3000; readTimeout = 10000
            }
            if (connection.responseCode != 200) return null
            val body = connection.inputStream.bufferedReader().readText()
            val map = com.kitsune.vpn.core.Json.obj(body) ?: return null
            map.mapNotNull { (tag, ms) -> (ms as? Number)?.let { tag.removePrefix("s-") to it.toInt() } }.toMap()
        } catch (_: Exception) { null }
    }
}
