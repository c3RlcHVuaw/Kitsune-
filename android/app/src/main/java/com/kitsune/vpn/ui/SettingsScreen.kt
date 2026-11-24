package com.kitsune.vpn.ui

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon as GraphicsIcon
import android.os.Build
import android.provider.Settings as SystemSettings
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.VpnLock
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kitsune.vpn.AppViewModel
import com.kitsune.vpn.BuildConfig
import com.kitsune.vpn.R
import com.kitsune.vpn.data.Accent
import com.kitsune.vpn.vpn.KitsuneTile

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val settings = vm.settings
    val autoConnect by settings.autoConnect.collectAsState()
    val speedInNotification by settings.speedInNotification.collectAsState()
    val dynamicColor by settings.dynamicColor.collectAsState()
    val accent by settings.accent.collectAsState()
    val subscriptions by vm.library.subscriptions.collectAsState()

    Column(modifier.fillMaxSize()) {
        TopAppBar(title = { Text(stringResource(R.string.tab_settings)) })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionHeader(stringResource(R.string.settings_connection))
            Group {
                Item(stringResource(R.string.auto_connect), subtitle = stringResource(R.string.auto_connect_hint), leading = { Icon(Icons.Outlined.Bolt, null) },
                    trailing = { Switch(autoConnect, settings::setAutoConnect) }, onClick = { settings.setAutoConnect(!autoConnect) })
                Item(stringResource(R.string.always_on), subtitle = stringResource(R.string.always_on_hint), leading = { Icon(Icons.Outlined.VpnLock, null) },
                    trailing = { Icon(Icons.AutoMirrored.Outlined.OpenInNew, null) }, onClick = { context.startActivity(Intent(SystemSettings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) })
                Item(stringResource(R.string.speed_in_notification), leading = { Icon(Icons.Outlined.Notifications, null) },
                    trailing = { Switch(speedInNotification, settings::setSpeedInNotification) }, onClick = { settings.setSpeedInNotification(!speedInNotification) })
                Item(stringResource(R.string.quick_tile), subtitle = stringResource(R.string.quick_tile_hint), leading = { Icon(Icons.Outlined.GridView, null) }, onClick = { addTile(context) })
                if (subscriptions.isNotEmpty()) Item(stringResource(R.string.refresh_subscriptions), leading = { Icon(Icons.Outlined.Refresh, null) }, onClick = { vm.refreshAll() })
            }

            SectionHeader(stringResource(R.string.settings_look))
            Group {
                if (Build.VERSION.SDK_INT >= 31) Item(stringResource(R.string.dynamic_colors), subtitle = stringResource(R.string.dynamic_colors_hint), leading = { Icon(Icons.Outlined.Palette, null) },
                    trailing = { Switch(dynamicColor, settings::setDynamicColor) }, onClick = { settings.setDynamicColor(!dynamicColor) })
                Item(stringResource(R.string.accent), subtitle = stringResource(when (accent) { Accent.Copper -> R.string.accent_copper; Accent.Moon -> R.string.accent_moon; Accent.Neon -> R.string.accent_neon }),
                    leading = { Icon(Icons.Outlined.Palette, null) },
                    trailing = {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Accent.entries.forEach { a ->
                                androidx.compose.foundation.layout.Box(
                                    Modifier.size(24.dp).clip(CircleShape).background(a.swatch)
                                        .then(if (a == accent) Modifier.border(2.dp, MaterialTheme.colorScheme.onSurface, CircleShape) else Modifier)
                                        .clickable { settings.setAccent(a) },
                                )
                            }
                        }
                    })
            }

            SectionHeader(stringResource(R.string.settings_other))
            Group { Item(stringResource(R.string.about), subtitle = "Kitsune ${BuildConfig.VERSION_NAME} · sing-box", leading = { Icon(Icons.Outlined.Info, null) }) }
        }
    }
}

private fun addTile(context: android.content.Context) {
    if (Build.VERSION.SDK_INT >= 33) {
        context.getSystemService(StatusBarManager::class.java).requestAddTileService(
            ComponentName(context, KitsuneTile::class.java), context.getString(R.string.app_name), GraphicsIcon.createWithResource(context, R.drawable.ic_fox), context.mainExecutor,
        ) {}
    } else Toast.makeText(context, R.string.quick_tile_manual, Toast.LENGTH_LONG).show()
}
