package com.example.typing_assistant

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.typing_assistant/multicast"
    private var multicastLock: MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        multicastLock = wifiManager.createMulticastLock("typing_assistant_multicast")
                        multicastLock?.setReferenceCounted(true)
                        multicastLock?.acquire()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_ERROR", "Failed to acquire multicast lock: ${e.message}", null)
                    }
                }
                "releaseMulticastLock" -> {
                    try {
                        multicastLock?.release()
                        multicastLock = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_ERROR", "Failed to release multicast lock: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            multicastLock?.release()
            multicastLock = null
        } catch (e: Exception) {
            // Ignore
        }
    }
}
