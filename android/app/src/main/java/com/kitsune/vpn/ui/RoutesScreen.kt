package com.kitsune.vpn.ui

import android.content.Intent
import android.content.pm.PackageManager
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.AltRoute
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.kitsune.vpn.AppViewModel
import com.kitsune.vpn.R
import com.kitsune.vpn.core.DnsProvider
import com.kitsune.vpn.core.RouteEntry
import com.kitsune.vpn.core.RoutePreset
import com.kitsune.vpn.core.RouteProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private enum class Dialog { None, Dns, DirectApps, ProxyApps, EntryServer, AddDirect, AddProxy }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun RoutesScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val routing by vm.library.routing.collectAsState()
    val servers by vm.library.servers.collectAsState()
    var dialog by remember { mutableStateOf(Dialog.None) }
    fun update(new: com.kitsune.vpn.core.RoutingSettings) { vm.library.setRouting(new); vm.reloadIfConnected() }

    Column(modifier.fillMaxSize()) {
        TopAppBar(title = { Text(stringResource(R.string.tab_routes)) })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val profiles = listOf(RouteProfile.RussiaDirect to R.string.profile_russia, RouteProfile.AllVPN to R.string.profile_all_short, RouteProfile.Custom to R.string.profile_custom)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                profiles.forEachIndexed { index, (profile, label) ->
                    SegmentedButton(routing.profile == profile, { update(routing.copy(profile = profile)) }, SegmentedButtonDefaults.itemShape(index, profiles.size),
                        icon = { SegmentedButtonDefaults.Icon(routing.profile == profile) { Icon(Icons.Outlined.Check, null, Modifier.size(SegmentedButtonDefaults.IconSize)) } }) { Text(stringResource(label), maxLines = 1) }
                }
            }
            Text(stringResource(when (routing.profile) { RouteProfile.RussiaDirect -> R.string.profile_russia_hint; RouteProfile.AllVPN -> R.string.profile_all_hint; RouteProfile.Custom -> R.string.profile_custom_hint }),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp))

            Group {
                Item(stringResource(R.string.block_ads), subtitle = stringResource(R.string.block_ads_hint), leading = { Icon(Icons.Outlined.Block, null) },
                    trailing = { Switch(routing.blockAds, { update(routing.copy(blockAds = it)) }) }, onClick = { update(routing.copy(blockAds = !routing.blockAds)) })
                Item(stringResource(R.string.block_ipv6), subtitle = stringResource(R.string.block_ipv6_hint), leading = { Icon(Icons.Outlined.Public, null) },
                    trailing = { Switch(routing.blockIPv6, { update(routing.copy(blockIPv6 = it)) }) }, onClick = { update(routing.copy(blockIPv6 = !routing.blockIPv6)) })
                Item(stringResource(R.string.secure_dns), subtitle = routing.dns.title, leading = { Icon(Icons.Outlined.Dns, null) },
                    trailing = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null) }, onClick = { dialog = Dialog.Dns })
                Item(stringResource(R.string.double_hop), subtitle = servers.firstOrNull { it.id == routing.entryServerId }?.displayName ?: stringResource(R.string.off),
                    leading = { Icon(Icons.AutoMirrored.Outlined.AltRoute, null) }, trailing = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null) }, onClick = { dialog = Dialog.EntryServer })
            }

            SectionHeader(stringResource(R.string.quick_sets))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RoutePreset.entries.forEach { preset ->
                    val on = preset in routing.presets
                    FilterChip(on, { update(routing.copy(presets = if (on) routing.presets - preset else routing.presets + preset)) },
                        { Text(stringResource(when (preset) { RoutePreset.Streaming -> R.string.preset_streaming; RoutePreset.Games -> R.string.preset_games; RoutePreset.Messengers -> R.string.preset_messengers })) },
                        leadingIcon = if (on) ({ Icon(Icons.Outlined.Check, null, Modifier.size(18.dp)) }) else null)
                }
            }

            SectionHeader(stringResource(R.string.apps))
            Group {
                Item(stringResource(R.string.apps_direct), subtitle = appsSummary(routing.directApps), leading = { Icon(Icons.Outlined.Apps, null) },
                    trailing = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null) }, onClick = { dialog = Dialog.DirectApps })
                Item(stringResource(R.string.apps_vpn), subtitle = appsSummary(routing.proxyApps), leading = { Icon(Icons.Outlined.Lock, null) },
                    trailing = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, null) }, onClick = { dialog = Dialog.ProxyApps })
            }

            SectionHeader(stringResource(R.string.sites_vpn))
            EntryChips(routing.proxy, { update(routing.copy(proxy = routing.proxy - it)) }, { dialog = Dialog.AddProxy })
            SectionHeader(stringResource(R.string.sites_direct))
            EntryChips(routing.direct, { update(routing.copy(direct = routing.direct - it)) }, { dialog = Dialog.AddDirect })
            Text(stringResource(R.string.sites_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp))
        }
    }

    when (dialog) {
        Dialog.None -> {}
        Dialog.Dns -> ChoiceDialog(stringResource(R.string.secure_dns), DnsProvider.entries, routing.dns, { "${it.title} · ${it.address}" }, { dialog = Dialog.None }) { update(routing.copy(dns = it)); dialog = Dialog.None }
        Dialog.EntryServer -> {
            val options = listOf<com.kitsune.vpn.core.ServerConfig?>(null) + servers
            ChoiceDialog(stringResource(R.string.double_hop), options, servers.firstOrNull { it.id == routing.entryServerId }, { it?.displayName ?: stringResource(R.string.off) }, { dialog = Dialog.None }) { update(routing.copy(entryServerId = it?.id)); dialog = Dialog.None }
        }
        Dialog.DirectApps -> AppPicker(stringResource(R.string.apps_direct), routing.directApps, { dialog = Dialog.None }) { update(routing.copy(directApps = it, proxyApps = routing.proxyApps - it.toSet())); dialog = Dialog.None }
        Dialog.ProxyApps -> AppPicker(stringResource(R.string.apps_vpn), routing.proxyApps, { dialog = Dialog.None }) { update(routing.copy(proxyApps = it, directApps = routing.directApps - it.toSet())); dialog = Dialog.None }
        Dialog.AddDirect -> EntryDialog({ dialog = Dialog.None }) { update(routing.copy(direct = routing.direct + it)); dialog = Dialog.None }
        Dialog.AddProxy -> EntryDialog({ dialog = Dialog.None }) { update(routing.copy(proxy = routing.proxy + it)); dialog = Dialog.None }
    }
}

@Composable
private fun appsSummary(apps: List<String>) = if (apps.isEmpty()) stringResource(R.string.none) else stringResource(R.string.apps_count, apps.size)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun EntryChips(entries: List<String>, onRemove: (String) -> Unit, onAdd: () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        entries.forEach { InputChip(false, { onRemove(it) }, { Text(it) }, trailingIcon = { Icon(Icons.Outlined.Close, stringResource(R.string.delete), Modifier.size(18.dp)) }) }
        androidx.compose.material3.AssistChip(onClick = onAdd, label = { Text(stringResource(R.string.add)) }, leadingIcon = { Icon(Icons.Outlined.Add, null, Modifier.size(18.dp)) })
    }
}

@Composable
private fun <T> ChoiceDialog(title: String, options: List<T>, current: T, label: @Composable (T) -> String, onDismiss: () -> Unit, onPick: (T) -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title) },
        text = { LazyColumn { items(options) { option ->
            androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth().androidxClickable { onPick(option) }.padding(vertical = 4.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                RadioButton(option == current, { onPick(option) }); Text(label(option))
            }
        } } },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun EntryDialog(onDismiss: () -> Unit, onAdd: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    val entry = RouteEntry.parse(text)
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(stringResource(R.string.add_site)) },
        text = { OutlinedTextField(text, { text = it }, singleLine = true, label = { Text(stringResource(R.string.site_example)) }, isError = text.isNotBlank() && entry == null, supportingText = { if (text.isNotBlank() && entry == null) Text(stringResource(R.string.site_invalid)) }) },
        confirmButton = { TextButton(onClick = { entry?.let { onAdd(it.value) } }, enabled = entry != null) { Text(stringResource(R.string.add)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

private data class AppInfo(val label: String, val packageName: String)

@Composable
private fun AppPicker(title: String, selected: List<String>, onDismiss: () -> Unit, onDone: (List<String>) -> Unit) {
    val context = LocalContext.current
    var apps by remember { mutableStateOf<List<AppInfo>?>(null) }
    var chosen by remember { mutableStateOf(selected.toSet()) }
    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.IO) {
            val pm = context.packageManager
            pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), PackageManager.MATCH_ALL)
                .map { AppInfo(it.loadLabel(pm).toString(), it.activityInfo.packageName) }.filter { it.packageName != context.packageName }
                .distinctBy { it.packageName }.sortedBy { it.label.lowercase() }
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title) },
        text = {
            val list = apps
            if (list == null) androidx.compose.material3.CircularProgressIndicator()
            else LazyColumn { items(list, key = { it.packageName }) { app ->
                androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth().androidxClickable { chosen = if (app.packageName in chosen) chosen - app.packageName else chosen + app.packageName }, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Checkbox(app.packageName in chosen, { chosen = if (it) chosen + app.packageName else chosen - app.packageName })
                    Column { Text(app.label); Text(app.packageName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            } }
        },
        confirmButton = { TextButton(onClick = { onDone(chosen.toList().sorted()) }) { Text(stringResource(R.string.done)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

private fun Modifier.androidxClickable(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)
