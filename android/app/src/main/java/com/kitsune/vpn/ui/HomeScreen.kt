package com.kitsune.vpn.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowDownward
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.PowerSettingsNew
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kitsune.vpn.AppViewModel
import com.kitsune.vpn.R
import com.kitsune.vpn.core.RouteProfile
import com.kitsune.vpn.vpn.Format
import com.kitsune.vpn.vpn.Tunnel
import com.kitsune.vpn.vpn.TunnelStatus
import kotlinx.coroutines.delay

@Composable
fun HomeScreen(vm: AppViewModel, onToggle: () -> Unit, openServers: () -> Unit, openRoutes: () -> Unit, modifier: Modifier = Modifier) {
    val status by Tunnel.status.collectAsState()
    val error by Tunnel.error.collectAsState()
    val speed by Tunnel.speed.collectAsState()
    val totals by Tunnel.totals.collectAsState()
    val connectedAt by Tunnel.connectedAt.collectAsState()
    val servers by vm.library.servers.collectAsState()
    val selectedId by vm.library.selectedId.collectAsState()
    val auto by vm.library.auto.collectAsState()
    val pings by vm.library.pings.collectAsState()
    val routing by vm.library.routing.collectAsState()
    val server = servers.firstOrNull { it.id == selectedId } ?: servers.firstOrNull()
    val connected = status == TunnelStatus.Connected
    val colors = MaterialTheme.colorScheme

    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f, fill = false).size(if (connected) 8.dp else 48.dp))
        ConnectButton(status, onToggle)
        Spacer(Modifier.size(20.dp))
        Text(
            when (status) {
                TunnelStatus.Connected -> stringResource(R.string.status_connected)
                TunnelStatus.Connecting -> stringResource(R.string.status_connecting)
                TunnelStatus.Disconnecting -> stringResource(R.string.status_disconnecting)
                TunnelStatus.Disconnected -> if (error != null) stringResource(R.string.status_error) else stringResource(R.string.status_disconnected)
            },
            style = MaterialTheme.typography.headlineSmall, color = if (connected) colors.primary else if (error != null && status == TunnelStatus.Disconnected) colors.error else colors.onSurface,
        )
        Text(
            when {
                connected -> "${Uptime(connectedAt)} · ${stringResource(R.string.today_protected)}"
                status == TunnelStatus.Disconnected && error != null -> error.orEmpty()
                server == null -> stringResource(R.string.add_server_hint)
                else -> stringResource(R.string.tap_to_protect)
            },
            style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp),
        )
        Spacer(Modifier.size(20.dp))

        if (connected) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SpeedCard(Icons.Outlined.ArrowDownward, speed.down, totals.down, stringResource(R.string.download), Modifier.weight(1f))
                SpeedCard(Icons.Outlined.ArrowUpward, speed.up, totals.up, stringResource(R.string.upload), Modifier.weight(1f))
            }
            Spacer(Modifier.size(8.dp))
            if (server != null) AddressCard(server.host, countryName(server))
            Spacer(Modifier.size(8.dp))
        }
        Spacer(Modifier.weight(1f, fill = false).size(16.dp))

        if (server != null) {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surfaceContainerHigh).clickable(onClick = openServers).padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 8.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                CountryAvatar(server)
                Column(Modifier.weight(1f)) {
                    Text(if (auto) stringResource(R.string.auto_fastest) else server.displayName, style = MaterialTheme.typography.titleMedium)
                    Text(listOfNotNull(server.displayName.takeIf { auto }, server.summary, pings[server.id]?.milliseconds?.let { "$it мс" }).joinToString(" · "),
                        style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                }
                IconButton(onClick = openServers) { Icon(Icons.Outlined.UnfoldMore, null, tint = colors.onSurfaceVariant) }
            }
        } else {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surfaceContainerHigh).clickable(onClick = openServers).padding(16.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(Icons.Outlined.Dns, null, tint = colors.primary)
                Text(stringResource(R.string.add_server), style = MaterialTheme.typography.titleMedium)
            }
        }
        Spacer(Modifier.size(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = routing.profile == RouteProfile.RussiaDirect, onClick = openRoutes,
                label = { Text(stringResource(when (routing.profile) { RouteProfile.RussiaDirect -> R.string.profile_russia; RouteProfile.AllVPN -> R.string.profile_all; RouteProfile.Custom -> R.string.profile_custom })) },
                leadingIcon = { Icon(Icons.Outlined.Check, null, Modifier.size(18.dp)) },
            )
            FilterChip(
                selected = routing.blockAds, onClick = { vm.library.setRouting(routing.copy(blockAds = !routing.blockAds)); vm.reloadIfConnected() },
                label = { Text(stringResource(R.string.block_ads_short)) },
                leadingIcon = { Icon(if (routing.blockAds) Icons.Outlined.Check else Icons.Outlined.Block, null, Modifier.size(18.dp)) },
            )
        }
    }
}

@Composable
private fun ConnectButton(status: TunnelStatus, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    val on = status == TunnelStatus.Connected
    val busy = status == TunnelStatus.Connecting || status == TunnelStatus.Disconnecting
    val ring by animateColorAsState(if (on) colors.primary else colors.outlineVariant, label = "ring")
    val fill by animateColorAsState(if (on) colors.primaryContainer else colors.surfaceContainerHigh, label = "fill")
    Box(Modifier.size(232.dp).border(if (on) 4.dp else 1.dp, ring, CircleShape), contentAlignment = Alignment.Center) {
        Box(Modifier.size(200.dp).clip(CircleShape).background(fill).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.PowerSettingsNew, stringResource(R.string.connect_button), Modifier.size(72.dp), tint = if (on) colors.onPrimaryContainer else colors.primary)
        }
        if (busy) CircularProgressIndicator(Modifier.size(232.dp), strokeWidth = 4.dp)
    }
}

@Composable
private fun SpeedCard(icon: androidx.compose.ui.graphics.vector.ImageVector, speed: Long, total: Long, label: String, modifier: Modifier) {
    val colors = MaterialTheme.colorScheme
    Column(modifier.clip(RoundedCornerShape(16.dp)).background(colors.surfaceContainerHigh).padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(icon, null, Modifier.size(20.dp), tint = colors.primary)
            Text(Format.speed(speed), style = MaterialTheme.typography.titleLarge)
        }
        Text("$label · ${Format.size(total)}", style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
    }
}

@Composable
private fun AddressCard(host: String, country: String?) {
    val colors = MaterialTheme.colorScheme
    val clipboard = LocalClipboardManager.current
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surfaceContainerHigh).padding(start = 16.dp, top = 12.dp, bottom = 12.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(host, style = MaterialTheme.typography.titleMedium)
            Text(country?.let { stringResource(R.string.exit_country, it) } ?: stringResource(R.string.server_address), style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
        }
        IconButton(onClick = { clipboard.setText(AnnotatedString(host)) }) { Icon(Icons.Outlined.ContentCopy, stringResource(R.string.copy), tint = colors.onSurfaceVariant) }
    }
}

/** mm:ss (h:mm:ss) since the tunnel came up, ticking every second. */
@Composable
private fun Uptime(since: Long?): String {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(since) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    val seconds = since?.let { ((now - it) / 1000).coerceAtLeast(0) } ?: 0
    return if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60) else "%02d:%02d".format(seconds / 60, seconds % 60)
}

