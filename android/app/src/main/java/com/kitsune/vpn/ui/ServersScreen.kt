package com.kitsune.vpn.ui

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.kitsune.vpn.AppViewModel
import com.kitsune.vpn.R
import com.kitsune.vpn.core.ServerConfig
import com.kitsune.vpn.data.Subscription
import com.kitsune.vpn.vpn.Format
import java.text.DateFormat
import java.util.Date

private enum class Filter { All, Pinned, Fast }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServersScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val servers by vm.library.servers.collectAsState()
    val subscriptions by vm.library.subscriptions.collectAsState()
    val selectedId by vm.library.selectedId.collectAsState()
    val auto by vm.library.auto.collectAsState()
    val pinned by vm.library.pinned.collectAsState()
    val pings by vm.library.pings.collectAsState()
    val busy by vm.busy.collectAsState()
    var filter by rememberSaveable { mutableStateOf(Filter.All) }
    var query by rememberSaveable { mutableStateOf("") }
    var searching by rememberSaveable { mutableStateOf(false) }
    var sortByPing by rememberSaveable { mutableStateOf(false) }
    var adding by rememberSaveable { mutableStateOf(false) }

    fun visible(list: List<ServerConfig>): List<ServerConfig> {
        var result = list.filter { query.isBlank() || it.name.contains(query, ignoreCase = true) || it.host.contains(query, ignoreCase = true) }
        result = when (filter) {
            Filter.All -> result
            Filter.Pinned -> result.filter { it.id in pinned }
            Filter.Fast -> result.filter { (pings[it.id]?.milliseconds ?: Int.MAX_VALUE) < 100 }
        }
        return if (sortByPing || filter == Filter.Fast) result.sortedBy { pings[it.id]?.milliseconds ?: Int.MAX_VALUE } else result
    }

    Scaffold(
        modifier = modifier,
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
        topBar = {
            TopAppBar(
                title = {
                    if (searching) OutlinedTextField(query, { query = it }, singleLine = true, modifier = Modifier.fillMaxWidth(), placeholder = { Text(stringResource(R.string.search)) })
                    else Text(stringResource(R.string.tab_servers))
                },
                actions = {
                    IconButton(onClick = { searching = !searching; if (!searching) query = "" }) { Icon(if (searching) Icons.Outlined.Close else Icons.Outlined.Search, stringResource(R.string.search)) }
                    IconButton(onClick = { sortByPing = !sortByPing; vm.ping() }) { Icon(Icons.AutoMirrored.Outlined.Sort, stringResource(R.string.sort_by_ping)) }
                },
            )
        },
        floatingActionButton = { ExtendedFloatingActionButton(onClick = { adding = true }, icon = { Icon(Icons.Outlined.Add, null) }, text = { Text(stringResource(R.string.add)) }) },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            item {
                androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(filter == Filter.All, { filter = Filter.All }, { Text(stringResource(R.string.filter_all, servers.size)) }, leadingIcon = if (filter == Filter.All) ({ Icon(Icons.Outlined.Check, null, Modifier.size(18.dp)) }) else null)
                    FilterChip(filter == Filter.Pinned, { filter = Filter.Pinned }, { Text(stringResource(R.string.filter_pinned)) }, leadingIcon = if (filter == Filter.Pinned) ({ Icon(Icons.Outlined.Check, null, Modifier.size(18.dp)) }) else null)
                    FilterChip(filter == Filter.Fast, { filter = Filter.Fast; vm.ping() }, { Text(stringResource(R.string.filter_fast)) }, leadingIcon = { Icon(if (filter == Filter.Fast) Icons.Outlined.Check else Icons.Outlined.Bolt, null, Modifier.size(18.dp)) })
                }
            }
            if (servers.isEmpty()) item { Text(stringResource(R.string.servers_empty), color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp)) }
            if (servers.size > 1) item {
                Group { Item(stringResource(R.string.auto_fastest), subtitle = stringResource(R.string.auto_hint), selected = auto, leading = { Icon(Icons.Outlined.Bolt, null, tint = MaterialTheme.colorScheme.primary) }, onClick = { vm.library.setAuto(!auto) }) }
            }
            subscriptions.forEach { sub ->
                val list = visible(vm.library.servers(sub))
                if (list.isNotEmpty() || (query.isBlank() && filter == Filter.All)) {
                    item(key = "sub-${sub.id}") { SubscriptionHeader(sub, vm.library.servers(sub).size, vm) }
                    if (list.isNotEmpty()) item(key = "list-${sub.id}") { ServerGroup(list, selectedId, auto, pinned, pings, vm) }
                }
            }
            val manual = visible(vm.library.manual)
            if (manual.isNotEmpty()) {
                item(key = "manual-title") { SectionHeader(stringResource(R.string.own_servers)) }
                item(key = "manual") { ServerGroup(manual, selectedId, auto, pinned, pings, vm) }
            }
        }
    }
    if (adding) AddSheet(vm) { adding = false }
}

@Composable
private fun SubscriptionHeader(sub: Subscription, count: Int, vm: AppViewModel) {
    var menu by remember { mutableStateOf(false) }
    val info = sub.info
    val usage = info?.total?.takeIf { it > 0 }?.let { total -> "${Format.size(info.used ?: 0)} / ${Format.size(total)}" }
    val expire = info?.expire?.let { stringResource(R.string.until_date, DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(it * 1000))) }
    Column {
        androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
            SectionHeader(stringResource(R.string.subscription_title, sub.title, count), Modifier.weight(1f))
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, null) }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text(stringResource(R.string.refresh)) }, { menu = false; vm.refresh(sub.id) }, leadingIcon = { Icon(Icons.Outlined.Refresh, null) })
                    DropdownMenuItem({ Text(stringResource(R.string.delete)) }, { menu = false; vm.library.remove(sub) }, leadingIcon = { Icon(Icons.Outlined.Delete, null) })
                }
            }
        }
        val line = listOfNotNull(usage, expire).joinToString(" · ")
        if (line.isNotEmpty()) Text(line, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 16.dp))
    }
}

@Composable
private fun ServerGroup(list: List<ServerConfig>, selectedId: String?, auto: Boolean, pinned: Set<String>, pings: Map<String, com.kitsune.vpn.data.Ping>, vm: AppViewModel) {
    Group {
        list.forEach { server ->
            var menu by remember { mutableStateOf(false) }
            val isSelected = server.id == selectedId && !auto
            Item(
                server.displayName, subtitle = "${server.summary} · ${server.host}", selected = isSelected,
                leading = { CountryAvatar(server, isSelected) },
                trailing = {
                    androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                        PingLabel(pings[server.id])
                        IconButton(onClick = { vm.library.togglePinned(server.id) }) { Icon(if (server.id in pinned) Icons.Outlined.Star else Icons.Outlined.StarBorder, stringResource(R.string.filter_pinned), tint = if (server.id in pinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, null) }
                            DropdownMenu(menu, { menu = false }) {
                                DropdownMenuItem({ Text(stringResource(R.string.delete)) }, { menu = false; vm.library.remove(server) }, leadingIcon = { Icon(Icons.Outlined.Delete, null) })
                            }
                        }
                    }
                },
                onClick = { vm.library.setAuto(false); vm.select(server) },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddSheet(vm: AppViewModel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var text by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.add_server), style = MaterialTheme.typography.titleLarge)
            OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.link_or_subscription)) }, minLines = 2, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
            androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                TextButton(onClick = {
                    val clip = (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
                    clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.let { text = it.toString() }
                }) { Text(stringResource(R.string.paste)) }
                Button(onClick = { vm.add(text, onDismiss) }, enabled = text.isNotBlank()) { Text(stringResource(R.string.add)) }
            }
        }
    }
}
