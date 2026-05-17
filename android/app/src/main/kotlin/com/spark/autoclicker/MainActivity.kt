package com.spark.autoclicker

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.spark.autoclicker.core.SparkAccessibilityService

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.spark.autoclicker/core"
        var methodChannel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isServiceEnabled" -> {
                    result.success(SparkAccessibilityService.instance != null)
                }
                "openSettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "updateBotConfiguration" -> {
                    val isActive = call.argument<Boolean>("isActive") ?: false
                    val minPrice = call.argument<Double>("minPrice") ?: 0.0
                    val maxDistance = call.argument<Double>("maxDistance") ?: 99.0
                    val storeId = call.argument<String>("storeId") ?: ""
                    val orderType = call.argument<String>("orderType") ?: ""
                    
                    SparkAccessibilityService.instance?.updateConfig(
                        isActive, minPrice, maxDistance, storeId, orderType
                    )
                    result.success(true)
                }
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "clickAt" -> {
                    val x = call.argument<Double>("x")?.toFloat() ?: 0f
                    val y = call.argument<Double>("y")?.toFloat() ?: 0f
                    SparkAccessibilityService.instance?.clickAt(x, y)
                    result.success(true)
                }
                "getScreenNodes" -> {
                    val nodes = SparkAccessibilityService.instance?.rootInActiveWindow
                    if (nodes != null) {
                        val nodeList = mutableListOf<Map<String, Any>>()
                        serializeNodes(nodes, nodeList)
                        result.success(nodeList)
                    } else {
                        result.error("UNAVAILABLE", "Service not running or root nodes not accessible", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun serializeNodes(node: android.view.accessibility.AccessibilityNodeInfo, list: MutableList<Map<String, Any>>) {
        val map = mutableMapOf<String, Any>()
        map["text"] = node.text?.toString() ?: ""
        map["contentDescription"] = node.contentDescription?.toString() ?: ""
        map["className"] = node.className?.toString() ?: ""
        
        val rect = android.graphics.Rect()
        node.getBoundsInScreen(rect)
        map["left"] = rect.left
        map["top"] = rect.top
        map["right"] = rect.right
        map["bottom"] = rect.bottom
        
        list.add(map)

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                serializeNodes(child, list)
            }
        }
    }
}
