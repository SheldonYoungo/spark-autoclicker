package com.spark.autoclicker.core

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.util.Log
import kotlin.random.Random
import android.os.Handler
import android.os.Looper
import android.graphics.Rect

class SparkAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SparkAccessibility"
        var instance: SparkAccessibilityService? = null
    }

    private var isBotActive = false
    private var minPrice = 0.0
    private var maxDistance = 99.9
    private var storeId = ""
    private var orderType = "" 
    
    private var lastClickTime = 0L
    private val clickDebounce = 500L

    private fun logToFlutter(message: String) {
        Log.d(TAG, message)
        Handler(Looper.getMainLooper()).post {
            try {
                // Usamos el plugin para enviar a todos los motores activos
                SparkNativePlugin.sendLogToAll(message)
            } catch (e: Exception) {
                Log.e(TAG, "Error enviando log: ${e.message}")
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        logToFlutter("✅ Servicio de Accesibilidad Vinculado")
    }

    fun updateConfig(active: Boolean, price: Double, distance: Double, store: String, type: String) {
        isBotActive = active
        minPrice = price
        maxDistance = distance
        storeId = store
        orderType = type
        
        val statusText = if (active) "ON" else "OFF"
        logToFlutter("🤖 Motor Nativo: Estado cambiado a $statusText")
        logToFlutter("⚙️ Configuración: MinPrice=$price, Distance=$distance, Store=$store, Type=$type")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isBotActive) return

        val packageName = event.packageName?.toString() ?: return
        
        if (packageName.contains("walmart", ignoreCase = true) || 
            packageName.contains("spark", ignoreCase = true) ||
            packageName == "com.spark.autoclicker") {
            
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastClickTime < clickDebounce) return

            val rootNode = rootInActiveWindow ?: return
            scanForOffers(rootNode)
            rootNode.recycle()
        }
    }

    private fun scanForOffers(node: AccessibilityNodeInfo?): Boolean {
        if (node == null || !isBotActive) return false

        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        
        if (text.isNotBlank()) {
            val priceRegex = Regex("""\$(\d+[\.,]?\d*)""")
            val priceMatch = priceRegex.find(text)
            
            if (priceMatch != null) {
                val currentPrice = priceMatch.groupValues[1].replace(",", ".").toDoubleOrNull() ?: 0.0

                val distanceRegex = Regex("""(\d+[\.,]?\d*)\s*miles""")
                val currentDistance = distanceRegex.find(text)?.groupValues?.get(1)?.replace(",", ".")?.toDoubleOrNull() ?: 999.0

                val storeRegex = Regex("""#(\d+)""")
                val currentStore = storeRegex.find(text)?.groupValues?.get(1) ?: ""

                if (currentPrice >= minPrice && currentPrice > 0 && currentDistance <= maxDistance) {
                    if (storeId.isEmpty() || storeId == currentStore) {
                        
                        val isTypeMatch = if (orderType.isBlank() || orderType.equals("Any", ignoreCase = true)) {
                            true
                        } else {
                            val keywords = orderType.split(",").map { it.trim() }.filter { it.isNotBlank() }
                            keywords.isEmpty() || keywords.any { text.contains(it, ignoreCase = true) }
                        }

                        if (isTypeMatch) {
                            logToFlutter("🎯 Match detectado: \$$currentPrice | $currentDistance mi | Store: #$currentStore")
                            if (findAndClickAccept()) {
                                return true 
                            }
                        }
                    }
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                val found = scanForOffers(child)
                child.recycle()
                if (found) return true
            }
        }
        
        return false
    }

    private fun findAndClickAccept(): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        
        val targetTexts = listOf("Accept", "ACCEPT", "Accept offer", "Confirm")
        
        for (targetText in targetTexts) {
            val buttonNode = findNodeByTextManually(rootNode, targetText)
            if (buttonNode != null) {
                val rect = Rect()
                buttonNode.getBoundsInScreen(rect)
                
                logToFlutter("🔍 Botón '$targetText' localizado en [${rect.centerX()}, ${rect.centerY()}]")
                
                lastClickTime = System.currentTimeMillis()
                clickAt(rect.centerX().toFloat(), rect.centerY().toFloat())
                
                buttonNode.recycle()
                rootNode.recycle()
                return true
            }
        }

        logToFlutter("⚠️ Oferta compatible vista pero botón 'Accept' no detectado en pantalla")
        rootNode.recycle()
        return false
    }

    private fun findNodeByTextManually(node: AccessibilityNodeInfo?, target: String): AccessibilityNodeInfo? {
        if (node == null) return null
        
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        if (text.contains(target, ignoreCase = true)) {
            return AccessibilityNodeInfo.obtain(node)
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                val found = findNodeByTextManually(child, target)
                child.recycle()
                if (found != null) return found
            }
        }
        return null
    }

    fun clickAt(x: Float, y: Float) {
        if (!isBotActive) {
            logToFlutter("🚫 Intento de clic ignorado: Bot inactivo")
            return
        }

        val jitterX = x + Random.nextInt(-3, 3).toFloat()
        val jitterY = y + Random.nextInt(-3, 3).toFloat()
        
        logToFlutter("🖱️ Ejecutando clic en ($jitterX, $jitterY)...")

        val path = Path()
        path.moveTo(jitterX, jitterY)
        val gestureBuilder = GestureDescription.Builder()
        gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, 45)) 
        
        dispatchGesture(gestureBuilder.build(), object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                logToFlutter("⚡ Gesto completado con éxito")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                logToFlutter("❌ Gesto CANCELADO por el sistema")
            }
        }, null)
    }

    override fun onInterrupt() {
        logToFlutter("🛑 Servicio interrumpido")
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        logToFlutter("💀 Servicio destruido")
        instance = null
    }
}
