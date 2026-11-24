package com.kitsune.vpn

import android.app.Application
import com.kitsune.vpn.data.Library

class KitsuneApplication : Application() {
    /** One library for the app, the quick-settings tile and the VPN service. */
    val library by lazy { Library(this) }
}
