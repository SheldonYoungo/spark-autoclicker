package com.spark.autoclicker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.spark.autoclicker.core.SparkNativePlugin
import android.util.Log

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        const val CHANNEL = "com.spark.autoclicker/core"
        var methodChannel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Registrar SparkNativePlugin como plugin real del engine.
        // Esto garantiza que el MethodChannel esté disponible tanto en el Main engine
        // como en el Overlay engine, y sobreviva hot-restarts.
        flutterEngine.plugins.add(SparkNativePlugin())
        
        // Guardar referencia al canal del plugin para uso externo (ej: AccessibilityService → nativeLog)
        methodChannel = SparkNativePlugin.getChannelForEngine(flutterEngine)
        
        Log.d(TAG, "SparkNativePlugin registrado como plugin del FlutterEngine")
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        methodChannel = null
    }
}
