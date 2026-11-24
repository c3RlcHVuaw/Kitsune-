package com.kitsune.vpn.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import com.kitsune.vpn.data.Accent

/** Dark Material 3 scheme generated from the copper seed #FF801A: the same tokens as the Figma page "Android". */
private val copper = darkColorScheme(
    primary = Color(0xFFFFB783), onPrimary = Color(0xFF4F2500), primaryContainer = Color(0xFF713700), onPrimaryContainer = Color(0xFFFFDCC5),
    secondary = Color(0xFFE4BFA8), onSecondary = Color(0xFF422B1B), secondaryContainer = Color(0xFF5B4130), onSecondaryContainer = Color(0xFFFFDCC5),
    tertiary = Color(0xFFC9CA93), tertiaryContainer = Color(0xFF48491C), onTertiaryContainer = Color(0xFFE6E6AD),
    error = Color(0xFFFFB4AB), onError = Color(0xFF690005), errorContainer = Color(0xFF93000A), onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF19120D), surface = Color(0xFF19120D), onBackground = Color(0xFFF0DFD7), onSurface = Color(0xFFF0DFD7),
    surfaceVariant = Color(0xFF52443B), onSurfaceVariant = Color(0xFFD7C3B7),
    surfaceContainerLowest = Color(0xFF140D08), surfaceContainerLow = Color(0xFF221A15), surfaceContainer = Color(0xFF261E19),
    surfaceContainerHigh = Color(0xFF312823), surfaceContainerHighest = Color(0xFF3D332D),
    outline = Color(0xFF9F8D83), outlineVariant = Color(0xFF52443B), inverseSurface = Color(0xFFF0DFD7), inverseOnSurface = Color(0xFF382E29), scrim = Color.Black,
)

private fun ColorScheme.accented(primary: Long, onPrimary: Long, container: Long, onContainer: Long, secondaryContainer: Long, onSecondaryContainer: Long) = copy(
    primary = Color(primary), onPrimary = Color(onPrimary), primaryContainer = Color(container), onPrimaryContainer = Color(onContainer),
    secondaryContainer = Color(secondaryContainer), onSecondaryContainer = Color(onSecondaryContainer),
)

private fun scheme(accent: Accent): ColorScheme = when (accent) {
    Accent.Copper -> copper
    Accent.Moon -> copper.accented(0xFFAFC6FF, 0xFF132F60, 0xFF2D4678, 0xFFD9E2FF, 0xFF3F4759, 0xFFDBE2F9)
    Accent.Neon -> copper.accented(0xFF6FDDB0, 0xFF003826, 0xFF005138, 0xFF8CF9CB, 0xFF3B4B42, 0xFFD2E8DB)
}

val Accent.swatch: Color get() = when (this) { Accent.Copper -> Color(0xFFFF801A); Accent.Moon -> Color(0xFF8FA6FF); Accent.Neon -> Color(0xFF4FE3B0) }

@Composable
fun KitsuneTheme(accent: Accent, dynamicColor: Boolean, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val colors = when {
        dynamicColor && Build.VERSION.SDK_INT >= 31 -> if (isSystemInDarkTheme()) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        else -> scheme(accent)
    }
    MaterialTheme(colorScheme = colors, content = content)
}
