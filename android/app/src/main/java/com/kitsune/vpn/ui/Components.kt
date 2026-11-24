package com.kitsune.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.kitsune.vpn.core.ServerConfig
import com.kitsune.vpn.data.Ping
import java.util.Locale

/** Section header: Title Small in the primary colour. */
@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = modifier.padding(start = 16.dp, top = 8.dp))
}

/** A rounded surfaceContainer card that groups list items (Material 3 "grouped list"). */
@Composable
fun Group(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(vertical = 4.dp)) { content() }
}

@Composable
fun Item(
    title: String, modifier: Modifier = Modifier, subtitle: String? = null, leading: @Composable (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null, selected: Boolean = false, onClick: (() -> Unit)? = null,
) {
    val container = if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = subtitle?.let { { Text(it) } },
        leadingContent = leading, trailingContent = trailing,
        colors = ListItemDefaults.colors(containerColor = container),
        modifier = modifier.then(if (selected) Modifier.clip(RoundedCornerShape(16.dp)) else Modifier).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
    )
}

/** Round avatar with the country code of the server. */
@Composable
fun CountryAvatar(server: ServerConfig, selected: Boolean = false) {
    val colors = MaterialTheme.colorScheme
    Box(Modifier.size(40.dp).clip(CircleShape).background(if (selected) colors.primary else colors.tertiaryContainer), contentAlignment = Alignment.Center) {
        Text(server.countryCode ?: server.displayName.take(2).uppercase(), style = MaterialTheme.typography.titleSmall,
            color = if (selected) colors.onPrimary else colors.onTertiaryContainer, textAlign = TextAlign.Center)
    }
}

/** Latency label: green-ish primary when fast, plain when slow, a dash on failure. */
@Composable
fun PingLabel(ping: Ping?) {
    val ms = ping?.milliseconds
    val text = when { ping == null -> ""; ms == null -> "—"; else -> "$ms мс" }
    val color = when { ms == null -> MaterialTheme.colorScheme.error; ms < 100 -> MaterialTheme.colorScheme.primary; else -> MaterialTheme.colorScheme.onSurfaceVariant }
    Text(text, style = MaterialTheme.typography.labelLarge, color = color)
}

@Composable
fun ScreenColumn(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
}

@Composable
fun SpacedRow(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { content() }
}

fun countryName(server: ServerConfig): String? = server.countryCode?.let { Locale("", it).displayCountry.takeIf { name -> name.isNotEmpty() } }
