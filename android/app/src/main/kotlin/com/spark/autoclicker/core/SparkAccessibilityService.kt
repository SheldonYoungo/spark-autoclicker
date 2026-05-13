package com.spark.autoclicker.core

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.util.Log

class SparkAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SparkAccessibility"
        var instance: SparkAccessibilityService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Service Connected")
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        // Solo procesamos eventos de la app de Spark (Walmart)
        // Nota: Asegúrate de que el paquete sea correcto. 
        // Comúnmente es: com.walmart.android.delivery.driver
        val packageName = event.packageName?.toString() ?: return
        
        if (packageName.contains("walmart", ignoreCase = true) || packageName.contains("spark", ignoreCase = true)) {
            val rootNode = rootInActiveWindow ?: return
            scanForOffers(rootNode)
        }
    }

    private fun scanForOffers(node: AccessibilityNodeInfo) {
        // Recorrido recursivo para encontrar datos de la oferta
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            
            // Aquí buscaremos patrones como: "Accept", "$", "miles", etc.
            val text = child.text?.toString()
            if (text != null) {
                // Logueamos para depuración (esto lo quitaremos en producción)
                Log.d(TAG, "Nodo detectado: $text")
            }
            
            scanForOffers(child)
            child.recycle()
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service Interrupted")
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    fun clickAt(x: Float, y: Float) {
        val path = Path()
        path.moveTo(x, y)
        val builder = GestureDescription.Builder()
        builder.addStroke(GestureDescription.StrokeDescription(path, 0, 100))
        dispatchGesture(builder.build(), null, null)
    }

    fun findNodesByText(text: String): List<AccessibilityNodeInfo> {
        val rootNode = rootInActiveWindow ?: return emptyList()
        return rootNode.findAccessibilityNodeInfosByText(text)
    }
}
