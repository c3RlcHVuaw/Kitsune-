package com.kitsune.vpn

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.automirrored.outlined.AltRoute
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import com.kitsune.vpn.ui.HomeScreen
import com.kitsune.vpn.ui.KitsuneTheme
import com.kitsune.vpn.ui.RoutesScreen
import com.kitsune.vpn.ui.ServersScreen
import com.kitsune.vpn.ui.SettingsScreen
import com.kitsune.vpn.vpn.Tunnel
import com.kitsune.vpn.vpn.TunnelStatus

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) {
            if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                registerForActivityResult(ActivityResultContracts.RequestPermission()) {}.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
            vm.refreshAll() // subscriptions stay fresh: a quiet refresh on every launch
        }
        setContent {
            val accent by vm.settings.accent.collectAsState()
            val dynamic by vm.settings.dynamicColor.collectAsState()
            KitsuneTheme(accent, dynamic) { AppRoot(vm, autoConnectOnLaunch = savedInstanceState == null) }
        }
    }
}

private enum class Tab(val label: Int) { Home(R.string.tab_home), Servers(R.string.tab_servers), Routes(R.string.tab_routes), Settings(R.string.tab_settings) }

@Composable
private fun AppRoot(vm: AppViewModel, autoConnectOnLaunch: Boolean) {
    val context = LocalContext.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val snackbar = remember { SnackbarHostState() }
    val message by vm.message.collectAsState()
    val noServers = stringResource(R.string.add_server_hint)

    val consent = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { if (it.resultCode == Activity.RESULT_OK) vm.connect() }
    fun connectWithConsent() {
        val intent = VpnService.prepare(context)
        if (intent != null) consent.launch(intent) else vm.connect()
    }
    val toggle = {
        when (Tunnel.status.value) {
            TunnelStatus.Connected, TunnelStatus.Connecting -> vm.disconnect()
            TunnelStatus.Disconnecting -> {}
            TunnelStatus.Disconnected -> if (vm.library.servers.value.isEmpty()) tab = Tab.Servers.ordinal else connectWithConsent()
        }
    }

    LaunchedEffect(Unit) {
        if (autoConnectOnLaunch && vm.settings.autoConnect.value && vm.library.servers.value.isNotEmpty() && VpnService.prepare(context) == null && Tunnel.status.value == TunnelStatus.Disconnected) vm.connect()
    }
    LaunchedEffect(message) {
        message?.let { snackbar.showSnackbar(if (it == "no_servers") noServers else it); vm.consumeMessage() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t.ordinal, onClick = { tab = t.ordinal }, label = { Text(stringResource(t.label)) },
                        icon = { Icon(when (t) { Tab.Home -> Icons.Outlined.Shield; Tab.Servers -> Icons.Outlined.Dns; Tab.Routes -> Icons.AutoMirrored.Outlined.AltRoute; Tab.Settings -> Icons.Outlined.Settings }, null) },
                    )
                }
            }
        },
    ) { padding ->
        val modifier = Modifier.fillMaxSize().padding(padding)
        when (Tab.entries[tab]) {
            Tab.Home -> HomeScreen(vm, toggle, { tab = Tab.Servers.ordinal }, { tab = Tab.Routes.ordinal }, modifier)
            Tab.Servers -> ServersScreen(vm, modifier)
            Tab.Routes -> RoutesScreen(vm, modifier)
            Tab.Settings -> SettingsScreen(vm, modifier)
        }
    }
}
