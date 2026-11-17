package com.bilingualprojector.bilingual_projector

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.graphics.Region
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.ColorDrawable
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The launcher icon. Android cuts every app's icon into the launcher's
 * shape and won't let an app give one per shape, so the app has a version
 * for each (beveled to fit that shape) as launcher aliases in the manifest,
 * and turns on the one chosen in Settings → App icon.
 *
 * Channel `bp/appicon`: `get` → the one on; `set` {icon}; `phoneShape` →
 * the shape this phone gives icons ("circle", "squircle", "rounded",
 * "square", or null when it can't tell).
 */
object AppIcon {
    private val icons = mapOf(
        "squircle" to "IconSquircle",
        "circle" to "IconCircle",
        "rounded" to "IconRounded",
        "square" to "IconSquare",
        "flat" to "IconFlat",
    )

    fun attach(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "bp/appicon")
            .setMethodCallHandler { call, result ->
                val pm = activity.packageManager
                // (The aliases' names are in the code's package, which can
                // differ from the app id.)
                val base = MainActivity::class.java.name.substringBeforeLast('.')
                fun component(alias: String) = ComponentName(activity.packageName, "$base.$alias")
                when (call.method) {
                    "get" -> result.success(
                        icons.entries.firstOrNull { (_, alias) ->
                            when (pm.getComponentEnabledSetting(component(alias))) {
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                                // Not changed yet: the manifest's default.
                                PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> alias == "IconSquircle"
                                else -> false
                            }
                        }?.key ?: "squircle"
                    )
                    "set" -> {
                        val chosen = icons[call.argument<String>("icon")]
                        if (chosen == null) {
                            result.error("bad", "Unknown icon", null)
                        } else {
                            // The new one on first, so there's always a
                            // launcher entry.
                            pm.setComponentEnabledSetting(
                                component(chosen),
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                PackageManager.DONT_KILL_APP,
                            )
                            for (alias in icons.values) {
                                if (alias == chosen) continue
                                pm.setComponentEnabledSetting(
                                    component(alias),
                                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP,
                                )
                            }
                            result.success(null)
                        }
                    }
                    "phoneShape" -> result.success(phoneShape())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The system's icon shape, sorted by how far its corner comes in along
     * the diagonal (a circle's ~15%, a squircle's ~8%, a rounded square's
     * ~5%, a square's 0).
     */
    private fun phoneShape(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val icon = AdaptiveIconDrawable(ColorDrawable(), ColorDrawable())
        val size = 1000
        icon.setBounds(0, 0, size, size)
        val region = Region()
        region.setPath(icon.iconMask, Region(0, 0, size, size))
        if (region.isEmpty) return null
        var inset = 0
        while (inset < size / 2 && !region.contains(inset, inset)) inset++
        val percent = inset * 100.0 / size
        return when {
            percent > 11 -> "circle"
            percent > 7 -> "squircle"
            percent > 2 -> "rounded"
            else -> "square"
        }
    }
}
