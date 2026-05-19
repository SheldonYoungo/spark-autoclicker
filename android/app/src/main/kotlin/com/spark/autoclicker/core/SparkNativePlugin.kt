package com.spark.autoclicker.core

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine

class SparkNativePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    companion object {
        private const val TAG = "SparkNativePlugin"
        const val CHANNEL_NAME = "com.spark.autoclicker/core"
        
        // Mantener una lista de canales activos para enviar logs a todos los motores (Main y Overlay)
        private val activeChannels = mutableListOf<MethodChannel>()
        
        // Referencia al canal principal para que MainActivity pueda acceder
        var mainChannel: MethodChannel? = null
            private set

        fun sendLogToAll(message: String) {
            activeChannels.forEach { it.invokeMethod("nativeLog", message) }
        }
        
        // Compatibilidad con MainActivity.configureFlutterEngine
        fun getChannelForEngine(engine: FlutterEngine): MethodChannel? {
            return mainChannel
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        activeChannels.add(channel)
        // El primer canal vinculado es el del Main engine
        if (mainChannel == null) {
            mainChannel = channel
        }
        Log.d(TAG, "SparkNativePlugin vinculado al motor. Canales activos: ${activeChannels.size}")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        activeChannels.remove(channel)
        if (mainChannel == channel) {
            mainChannel = null
        }
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isServiceEnabled" -> {
                val enabled = SparkAccessibilityService.instance != null
                result.success(enabled)
            }
            "openSettings" -> {
                context?.let {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    it.startActivity(intent)
                    result.success(true)
                } ?: result.error("NO_CONTEXT", "Context is null", null)
            }
            "updateBotConfiguration" -> {
                val isActive = call.argument<Boolean>("isActive") ?: false
                val minPrice = call.argument<Double>("minPrice") ?: 0.0
                val maxDistance = call.argument<Double>("maxDistance") ?: 99.0
                val storeId = call.argument<String>("storeId") ?: ""
                val orderType = call.argument<String>("orderType") ?: ""
                
                Log.d(TAG, "📱 Android recibió orden de activación: $isActive")
                
                val service = SparkAccessibilityService.instance
                if (service != null) {
                    service.updateConfig(
                        isActive, minPrice, maxDistance, storeId, orderType
                    )
                    result.success(true)
                } else {
                    Log.e(TAG, "❌ Error: El servicio de accesibilidad no está activo")
                    result.error("SERVICE_NOT_RUNNING", "El servicio de accesibilidad no está habilitado", null)
                }
            }
            "moveToBackground" -> {
                // Esta acción requiere una Activity, no se puede hacer desde el plugin fácilmente sin ActivityBinding
                // Pero podemos delegarla o ignorarla si viene del overlay
                result.success(true)
            }
            "clickAt" -> {
                val x = call.argument<Double>("x")?.toFloat() ?: 0f
                val y = call.argument<Double>("y")?.toFloat() ?: 0f
                val service = SparkAccessibilityService.instance
                if (service != null) {
                    service.clickAt(x, y)
                    result.success(true)
                } else {
                    result.error("SERVICE_NOT_RUNNING", "Service not running", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
}
