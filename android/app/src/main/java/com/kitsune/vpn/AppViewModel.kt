package com.kitsune.vpn

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.kitsune.vpn.core.ServerConfig
import com.kitsune.vpn.data.Library
import com.kitsune.vpn.data.LibraryError
import com.kitsune.vpn.data.Settings
import com.kitsune.vpn.vpn.Tunnel
import com.kitsune.vpn.vpn.TunnelStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class AppViewModel(app: Application) : AndroidViewModel(app) {
    val library: Library = (app as KitsuneApplication).library
    val settings = Settings(app)
    private val _message = MutableStateFlow<String?>(null)
    /** One-shot text for a snackbar (errors from adding servers and refreshing subscriptions). */
    val message: StateFlow<String?> = _message
    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy

    fun consumeMessage() { _message.value = null }

    /** Connects with the chosen server, or live-switches the running tunnel to it. */
    fun connect() {
        viewModelScope.launch {
            if (library.auto.value) {
                Tunnel.set(TunnelStatus.Connecting)
                library.ping()
                library.fastest()?.let { library.select(it.id, auto = true) }
            }
            val server = library.selected ?: return@launch run { Tunnel.set(TunnelStatus.Disconnected); _message.value = "no_servers" }
            start(server)
        }
    }

    private fun start(server: ServerConfig) {
        Tunnel.connect(getApplication(), server, library.servers.value, library.routing.value)
    }

    fun disconnect() = Tunnel.disconnect(getApplication())

    /** Picks a server; the running tunnel is reloaded onto it without dropping. */
    fun select(server: ServerConfig) {
        library.select(server.id)
        if (Tunnel.status.value == TunnelStatus.Connected) start(server)
    }

    /** Applies new routing settings; a running tunnel picks them up through a reload. */
    fun reloadIfConnected() {
        if (Tunnel.status.value == TunnelStatus.Connected) library.selected?.let(::start)
    }

    fun add(text: String, onDone: () -> Unit = {}) = run({ library.add(text) }, onDone)
    fun refresh(id: String) = run({ library.refresh(id) })
    fun refreshAll() = run({ library.refreshAll() })
    fun ping() = run({ library.ping() })

    private fun run(block: suspend () -> Unit, onDone: () -> Unit = {}) {
        viewModelScope.launch {
            _busy.value = true
            try { block(); onDone() } catch (e: LibraryError) { _message.value = e.message } finally { _busy.value = false }
        }
    }
}
