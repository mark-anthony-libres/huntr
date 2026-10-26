package com.marklibres.huntr

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
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

        // Notification sounds (Settings > Notifications > Sound): on Android
        // 8+ a channel's sound is fixed once it exists, so there's a channel
        // per sound and each push names the user's (the backend's
        // fcm_client.android_sound). "custom" starts with the phone's
        // default; the user picks its sound in Android's settings.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "huntr/notification_sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureChannels" -> {
                        ensureSoundChannels()
                        result.success(null)
                    }
                    "openSettings" -> {
                        val sound = call.argument<String>("sound") ?: "custom"
                        if (sound !in SOUNDS.keys) {
                            result.error("unknown_sound", "No such sound: $sound", null)
                        } else {
                            ensureSoundChannels()
                            openSoundSettings(sound)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun soundChannelId(sound: String) = "huntr_$sound"

    /** One channel per sound (no-op before Android 8, or when they exist). */
    private fun ensureSoundChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        for ((sound, name) in SOUNDS) {
            if (manager.getNotificationChannel(soundChannelId(sound)) != null) continue
            val channel = NotificationChannel(soundChannelId(sound), name, NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Taps, messages and story replies"
            when (sound) {
                "silent" -> channel.setSound(null, null)
                "chime", "pop", "ping" -> {
                    val raw = when (sound) {
                        "chime" -> R.raw.chime
                        "pop" -> R.raw.pop
                        else -> R.raw.ping
                    }
                    channel.setSound(Uri.parse("android.resource://$packageName/$raw"), attributes)
                }
                else -> channel.setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), attributes)
            }
            manager.createNotificationChannel(channel)
        }
    }

    /** Android's settings for [sound]'s channel (where its sound is picked),
     *  or the app's notification settings before Android 8. */
    private fun openSoundSettings(sound: String) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, soundChannelId(sound))
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
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
        // the sounds and their channels' names in Android's settings
        // (lib/services/notification_sound.dart lists them too)
        private val SOUNDS = linkedMapOf(
            "default" to "Notifications · Phone default",
            "chime" to "Notifications · Chime",
            "pop" to "Notifications · Pop",
            "ping" to "Notifications · Ping",
            "silent" to "Notifications · Silent",
            "custom" to "Notifications · Your sound",
        )
        // the manifest's `.Icon…` aliases (lib/services/app_icon.dart lists them too)
        private val ICONS = listOf(
            "orange", "blue", "purple", "pink", "green", "red", "gold", "peach",
            "magenta", "indigo", "sky", "teal", "lime", "mono", "notes", "weather", "clock",
        )
    }
}
