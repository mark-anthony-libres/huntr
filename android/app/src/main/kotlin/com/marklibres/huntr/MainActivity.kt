package com.marklibres.huntr

import android.content.ComponentName
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Privacy: no screenshots or screen recordings of HUNTR (profiles,
        // chats, stories), and a blank preview in the recent-apps list.
        // Debug builds (flutter run) allow them, for development; release
        // builds are never debuggable, so users always get the protection.
        val debuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The launcher icon and name (Settings > App icon): one launcher
        // alias in AndroidManifest.xml enabled at a time.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "huntr/app_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(currentIcon())
                    "set" -> {
                        val icon = call.argument<String>("icon")
                        if (icon == null || icon !in ICONS) {
                            result.error("unknown_icon", "No such icon: $icon", null)
                        } else {
                            setIcon(icon)
                            result.success(icon)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun alias(icon: String) =
        ComponentName(packageName, "$packageName.Icon${icon.replaceFirstChar { it.uppercase() }}")

    /** The enabled alias (the manifest's default, Orange, until changed). */
    private fun currentIcon(): String = ICONS.firstOrNull { icon ->
        when (packageManager.getComponentEnabledSetting(alias(icon))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> icon == DEFAULT_ICON
            else -> false
        }
    } ?: DEFAULT_ICON

    /** Turns [icon]'s alias on first, then the others off (never none). */
    private fun setIcon(icon: String) {
        packageManager.setComponentEnabledSetting(
            alias(icon),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (other in ICONS) {
            if (other == icon) continue
            packageManager.setComponentEnabledSetting(
                alias(other),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    companion object {
        private const val DEFAULT_ICON = "orange"
        // the manifest's `.Icon…` aliases (lib/services/app_icon.dart lists them too)
        private val ICONS = listOf(
            "orange", "blue", "purple", "pink", "green", "red", "gold", "peach",
            "magenta", "indigo", "sky", "teal", "lime", "mono", "notes", "weather", "clock",
        )
    }
}
