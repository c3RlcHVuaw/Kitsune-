package com.kitsune.vpn.vpn

import android.content.Intent
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.kitsune.vpn.KitsuneApplication
import com.kitsune.vpn.MainActivity
import com.kitsune.vpn.R

/** Quick-settings tile: one tap connects with the chosen server or disconnects. */
class KitsuneTile : TileService() {
    override fun onStartListening() = refresh()

    override fun onClick() {
        when (Tunnel.status.value) {
            TunnelStatus.Connected, TunnelStatus.Connecting -> Tunnel.disconnect(this)
            else -> {
                val library = (application as KitsuneApplication).library
                val server = library.selected
                // The first connect needs the system's VPN consent, which only an activity can ask for.
                if (server == null || VpnService.prepare(this) != null) {
                    val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    @Suppress("DEPRECATION") startActivityAndCollapse(open) // the PendingIntent overload needs API 34
                } else Tunnel.connect(this, server, library.servers.value, library.routing.value)
            }
        }
        refresh()
    }

    private fun refresh() {
        val tile = qsTile ?: return
        tile.state = if (Tunnel.status.value == TunnelStatus.Connected) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.app_name)
        tile.updateTile()
    }
}
