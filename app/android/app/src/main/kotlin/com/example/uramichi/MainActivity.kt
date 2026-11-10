package com.example.uramichi

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 地図のキーが入っているかをアプリに伝え、キーがあるときだけ Google マップを表示させる
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uramichi/config")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mapsApiKeyConfigured" -> result.success(mapsApiKey().isNotBlank())
                    else -> result.notImplemented()
                }
            }
        // 祝う演出の振動。Flutter の HapticFeedback では強さと長さを決められないため、端末の振動の機能を直接使う
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uramichi/haptics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pattern" -> {
                        val timings = (call.argument<List<Number>>("timings") ?: emptyList()).map { it.toLong() }
                        val amplitudes = (call.argument<List<Number>>("amplitudes") ?: emptyList()).map { it.toInt() }
                        result.success(vibrate(timings, amplitudes))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** timings は「止める・振動する」を交互に並べた長さ（ms）、amplitudes はそれぞれの強さ（0〜255）。振動できれば true */
    private fun vibrate(timings: List<Long>, amplitudes: List<Int>): Boolean {
        if (timings.isEmpty() || timings.size != amplitudes.size || timings.size > 40) return false
        val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return false
        val t = timings.map { it.coerceIn(0L, 1000L) }.toLongArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val a = amplitudes.map { it.coerceIn(0, 255) }.toIntArray()
            // 強さを変えられない端末では、強さを決めずに長さだけで振動させる
            val effect = if (vibrator.hasAmplitudeControl()) {
                VibrationEffect.createWaveform(t, a, -1)
            } else {
                VibrationEffect.createWaveform(t, -1)
            }
            vibrator.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(t, -1)
        }
        return true
    }

    private fun mapsApiKey(): String {
        val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        return info.metaData?.getString("com.google.android.geo.API_KEY") ?: ""
    }
}
