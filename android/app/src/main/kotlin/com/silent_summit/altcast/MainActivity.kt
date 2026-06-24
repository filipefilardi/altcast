package com.silent_summit.altcast

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.silent_summit.altcast/android_background_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBatterySettings" -> result.success(openBackgroundSettings())
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBackgroundSettings(): Boolean {
        val packageUri = Uri.parse("package:$packageName")
        val intents = listOf(
            Intent("android.settings.APP_BATTERY_SETTINGS")
                .putExtra("android.provider.extra.APP_PACKAGE", packageName)
                .setData(packageUri),
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri),
        )

        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next best settings screen.
            } catch (_: SecurityException) {
                // Some Android skins expose the intent but block direct access.
            }
        }

        return false
    }
}
