package com.kitsune.vpn.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class Accent { Copper, Moon, Neon }

/** App preferences, kept in SharedPreferences "settings" (the VPN service reads speedInNotification from there too). */
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _autoConnect = MutableStateFlow(prefs.getBoolean("autoConnect", false))
    val autoConnect: StateFlow<Boolean> = _autoConnect
    private val _speedInNotification = MutableStateFlow(prefs.getBoolean("speedInNotification", true))
    val speedInNotification: StateFlow<Boolean> = _speedInNotification
    private val _dynamicColor = MutableStateFlow(prefs.getBoolean("dynamicColor", false))
    val dynamicColor: StateFlow<Boolean> = _dynamicColor
    private val _accent = MutableStateFlow(Accent.entries.firstOrNull { it.name == prefs.getString("accent", null) } ?: Accent.Copper)
    val accent: StateFlow<Accent> = _accent

    fun setAutoConnect(on: Boolean) { _autoConnect.value = on; prefs.edit().putBoolean("autoConnect", on).apply() }
    fun setSpeedInNotification(on: Boolean) { _speedInNotification.value = on; prefs.edit().putBoolean("speedInNotification", on).apply() }
    fun setDynamicColor(on: Boolean) { _dynamicColor.value = on; prefs.edit().putBoolean("dynamicColor", on).apply() }
    fun setAccent(accent: Accent) { _accent.value = accent; prefs.edit().putString("accent", accent.name).apply() }
}
