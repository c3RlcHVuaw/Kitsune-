package com.kitsune.vpn.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import com.kitsune.vpn.MainActivity
import com.kitsune.vpn.R
import com.kitsune.vpn.core.ConfigBuilder
import com.kitsune.vpn.core.ErrorHint
import com.kitsune.vpn.core.Json
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.URL
import java.net.NetworkInterface as JavaInterface

/** Runs sing-box (libbox) inside an Android VpnService: the tun fd comes from [openTun], sockets are protected from looping. */
class KitsuneVpnService : VpnService(), PlatformInterface, CommandServerHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var server: CommandServer? = null
    private var trafficJob: Job? = null
    private var tun: ParcelFileDescriptor? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stop()
            else -> start(intent?.getStringExtra("server")) // null intent: the system restarted the always-on VPN
        }
        return START_STICKY
    }

    override fun onRevoke() = stop() // the user turned the VPN off in system settings

    override fun onDestroy() { scope.cancel(); super.onDestroy() }

    private fun start(serverId: String?) {
        val config = Tunnel.config(this)
        if (config == null) { stopSelf(); return }
        showForeground()
        val reloading = Tunnel.status.value == TunnelStatus.Connected
        if (!reloading) Tunnel.set(TunnelStatus.Connecting)
        scope.launch {
            try {
                copyRuleSets()
                val running = server ?: run {
                    setup()
                    Libbox.newCommandServer(this@KitsuneVpnService, this@KitsuneVpnService).also { it.start(); server = it }
                }
                running.startOrReloadService(config, OverrideOptions())
                Tunnel.setActive(serverId)
                if (!reloading) { Tunnel.set(TunnelStatus.Connected); trafficJob = launch { pollTraffic() } }
            } catch (e: Exception) {
                val raw = e.message ?: e.toString()
                Tunnel.set(TunnelStatus.Disconnected, ErrorHint.explain(raw) ?: raw)
                teardown()
            }
        }
    }

    private fun stop() {
        if (Tunnel.status.value == TunnelStatus.Disconnected && server == null) { stopSelf(); return }
        Tunnel.set(TunnelStatus.Disconnecting)
        scope.launch { teardown(); Tunnel.set(TunnelStatus.Disconnected) }
    }

    private fun teardown() {
        trafficJob?.cancel(); trafficJob = null
        try { server?.closeService() } catch (_: Exception) {}
        try { server?.close() } catch (_: Exception) {}
        server = null
        tun?.close(); tun = null
        if (Tunnel.status.value != TunnelStatus.Disconnected) Tunnel.set(TunnelStatus.Disconnected)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun setup() {
        val options = SetupOptions()
        options.basePath = filesDir.path
        options.workingPath = File(filesDir, "work").apply { mkdirs() }.path
        options.tempPath = cacheDir.path
        options.logMaxLines = 3000
        options.fixAndroidStack = Build.VERSION.SDK_INT < 29
        options.crashReportSource = "Kitsune"
        Libbox.setup(options)
    }

    /** The bundled rule-set snapshots the config points at: used until the first successful download. */
    private fun copyRuleSets() {
        val target = File(filesDir, "rulesets").apply { mkdirs() }
        for (name in assets.list("rulesets").orEmpty()) {
            val file = File(target, name)
            if (!file.exists()) assets.open("rulesets/$name").use { input -> file.outputStream().use { input.copyTo(it) } }
        }
    }

    // MARK: traffic and notification

    private suspend fun pollTraffic() {
        var down = 0L; var up = 0L
        while (scope.isActive) {
            try {
                val connection = URL("http://127.0.0.1:${ConfigBuilder.CONTROLLER_PORT}/traffic").openConnection() as HttpURLConnection
                connection.setRequestProperty("Authorization", "Bearer ${Tunnel.secret}")
                connection.connectTimeout = 3000
                connection.inputStream.bufferedReader().use { reader ->
                    while (true) {
                        val map = Json.obj(reader.readLine() ?: break) ?: continue
                        val d = (map["down"] as? Number)?.toLong() ?: 0; val u = (map["up"] as? Number)?.toLong() ?: 0
                        down += d; up += u
                        Tunnel.setSpeed(Speed(d, u), Speed(down, up))
                        updateNotification(d, u)
                    }
                }
            } catch (_: Exception) { delay(1000) }
        }
    }

    private fun channel(): String {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.notification_channel), NotificationManager.IMPORTANCE_LOW))
        }
        return CHANNEL
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, KitsuneVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, channel())
            .setSmallIcon(R.drawable.ic_fox).setContentTitle(getString(R.string.status_connected)).setContentText(text)
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.action_disconnect), stop).build()).build()
    }

    private fun showForeground() {
        val n = notification(getString(R.string.status_connecting))
        if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED)
        else startForeground(NOTIFICATION_ID, n)
    }

    private fun updateNotification(down: Long, up: Long) {
        if (!getSharedPreferences("settings", MODE_PRIVATE).getBoolean("speedInNotification", true)) return
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification("↓ ${Format.speed(down)}  ↑ ${Format.speed(up)}"))
    }

    // MARK: PlatformInterface

    override fun usePlatformAutoDetectInterfaceControl() = true
    override fun autoDetectInterfaceControl(fd: Int) { protect(fd) }

    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) throw IllegalStateException("android: missing vpn permission")
        val builder = Builder().setSession("Kitsune").setMtu(options.mtu)
        options.inet4Address.each { builder.addAddress(it.address(), it.prefix()) }
        options.inet6Address.each { builder.addAddress(it.address(), it.prefix()) }
        if (options.autoRoute) {
            options.dnsServerAddress.eachString { builder.addDnsServer(it) }
            var v4 = false; var v6 = false
            options.inet4RouteRange.each { builder.addRoute(it.address(), it.prefix()); v4 = true }
            options.inet6RouteRange.each { builder.addRoute(it.address(), it.prefix()); v6 = true }
            if (!v4) builder.addRoute("0.0.0.0", 0)
            if (!v6) builder.addRoute("::", 0)
            options.includePackage.eachString { builder.addAllowedApplication(it) }
            options.excludePackage.eachString { try { builder.addDisallowedApplication(it) } catch (_: Exception) {} }
        }
        val fd = builder.establish() ?: throw IllegalStateException("android: the system refused to create the VPN")
        tun = fd
        return fd.detachFd()
    }

    private fun io.nekohasekai.libbox.RoutePrefixIterator.each(block: (io.nekohasekai.libbox.RoutePrefix) -> Unit) { while (hasNext()) block(next()) }
    private fun StringIterator.eachString(block: (String) -> Unit) { while (hasNext()) block(next()) }

    override fun findConnectionOwner(ipProtocol: Int, sourceAddress: String, sourcePort: Int, destinationAddress: String, destinationPort: Int): ConnectionOwner {
        val manager = getSystemService(ConnectivityManager::class.java)
        val uid = manager.getConnectionOwnerUid(ipProtocol, InetSocketAddress(sourceAddress, sourcePort), InetSocketAddress(destinationAddress, destinationPort))
        if (uid == android.os.Process.INVALID_UID) throw IllegalStateException("android: connection owner not found")
        val packages = packageManager.getPackagesForUid(uid).orEmpty().toList()
        return ConnectionOwner().also {
            it.userId = uid
            it.processPath = packages.firstOrNull().orEmpty()
            it.setAndroidPackageNames(StringArray(packages))
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val manager = getSystemService(ConnectivityManager::class.java)
        val update = { _: Network? ->
            val best = bestNetwork(manager)
            if (best == null) listener.updateDefaultInterface("", -1, false, false)
            else {
                val name = manager.getLinkProperties(best)?.interfaceName
                val index = name?.let { JavaInterface.getByName(it)?.index }
                val metered = manager.getNetworkCapabilities(best)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
                if (name != null && index != null) listener.updateDefaultInterface(name, index, metered, false)
            }
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = update(network)
            override fun onLost(network: Network) = update(network)
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = update(network)
            override fun onLinkPropertiesChanged(network: Network, linkProperties: android.net.LinkProperties) = update(network)
        }
        val request = NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN).build()
        manager.registerNetworkCallback(request, callback)
        networkCallback = callback
        update(null)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let { try { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } catch (_: Exception) {} }
        networkCallback = null
    }

    /** The physical network traffic should leave through: Wi-Fi and Ethernet first, then cellular; never the VPN itself. */
    private fun bestNetwork(manager: ConnectivityManager): Network? {
        val rank = { n: Network ->
            val c = manager.getNetworkCapabilities(n)
            when {
                c == null || c.hasTransport(NetworkCapabilities.TRANSPORT_VPN) || !c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> -1
                c.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 3
                c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 2
                c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 1
                else -> 0
            }
        }
        @Suppress("DEPRECATION") // allNetworks is the only synchronous list; the callback keeps it fresh
        return manager.allNetworks.filter { rank(it) >= 0 }.maxByOrNull(rank)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val manager = getSystemService(ConnectivityManager::class.java)
        val result = mutableListOf<NetworkInterface>()
        @Suppress("DEPRECATION")
        for (network in manager.allNetworks) {
            val properties = manager.getLinkProperties(network) ?: continue
            val capabilities = manager.getNetworkCapabilities(network) ?: continue
            val java = JavaInterface.getByName(properties.interfaceName ?: continue) ?: continue
            result += NetworkInterface().also {
                it.index = java.index
                it.mtu = runCatching { java.mtu }.getOrDefault(1500)
                it.name = java.name
                it.addresses = StringArray(java.interfaceAddresses.map { a -> "${a.address.hostAddress?.substringBefore('%')}/${a.networkPrefixLength}" })
                it.dnsServer = StringArray(properties.dnsServers.mapNotNull { d -> d.hostAddress })
                it.type = when {
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                it.metered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            }
        }
        return object : NetworkInterfaceIterator {
            private val items = result.iterator()
            override fun hasNext() = items.hasNext()
            override fun next(): NetworkInterface = items.next()
        }
    }

    override fun underNetworkExtension() = false
    override fun includeAllNetworks() = false
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun registerMyInterface(name: String) {}
    override fun tailscaleHostname() = ""
    override fun usePlatformShell() = false
    override fun usePlatformBridge() = false

    // Features Kitsune doesn't use: notifications from the core, SSH, bridges, neighbours.
    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {}
    override fun cancelNotification(identifier: String, typeId: Int) {}
    override fun startNeighborMonitor(listener: io.nekohasekai.libbox.NeighborUpdateListener) {}
    override fun closeNeighborMonitor(listener: io.nekohasekai.libbox.NeighborUpdateListener) {}
    override fun checkPlatformShell() = throw UnsupportedOperationException()
    override fun openShellSession(user: io.nekohasekai.libbox.PlatformUser, command: String, environ: StringIterator, term: String, rows: Int, cols: Int): io.nekohasekai.libbox.ShellSession = throw UnsupportedOperationException()
    override fun lookupUser(username: String): io.nekohasekai.libbox.PlatformUser = throw UnsupportedOperationException()
    override fun lookupSFTPServer(): String = throw UnsupportedOperationException()
    override fun readSystemSSHHostKey(): String = throw UnsupportedOperationException()
    override fun createBridge(options: io.nekohasekai.libbox.BridgeOptions): io.nekohasekai.libbox.BridgeSession = throw UnsupportedOperationException()

    // MARK: CommandServerHandler

    override fun serviceStop() = stop()
    override fun serviceReload() {}
    override fun getSystemProxyStatus() = SystemProxyStatus()
    override fun setSystemProxyEnabled(enabled: Boolean) {}
    override fun triggerNativeCrash() {}
    override fun writeDebugMessage(message: String) {}
    override fun connectSSHAgent(): Int = throw UnsupportedOperationException()

    companion object {
        const val ACTION_START = "com.kitsune.vpn.START"
        const val ACTION_STOP = "com.kitsune.vpn.STOP"
        private const val CHANNEL = "vpn"
        private const val NOTIFICATION_ID = 1
    }
}

/** libbox wants its own iterator type for string lists. */
class StringArray(private val items: List<String>) : StringIterator {
    private var index = 0
    override fun hasNext() = index < items.size
    override fun len() = items.size
    override fun next(): String = items[index++]
}

object Format {
    fun speed(bytes: Long): String = "${size(bytes)}/с"

    fun size(bytes: Long): String = when {
        bytes >= 1L shl 30 -> "%.1f ГБ".format(bytes / (1L shl 30).toDouble())
        bytes >= 1L shl 20 -> "%.1f МБ".format(bytes / (1L shl 20).toDouble())
        bytes >= 1L shl 10 -> "%d КБ".format(bytes shr 10)
        else -> "$bytes Б"
    }
}
