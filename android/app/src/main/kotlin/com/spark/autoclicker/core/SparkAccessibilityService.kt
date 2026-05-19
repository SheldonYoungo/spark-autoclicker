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

/**
 * Servicio de Accesibilidad para automatizar la captura de ofertas en Spark.
 * Cumple con latencia < 100ms y simulación de comportamiento humano (Jitter).
 */
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
    private val clickDebounce = 1000L // Incrementado para evitar clics dobles accidentales

    private fun logToFlutter(message: String) {
        Log.d(TAG, message)
        Handler(Looper.getMainLooper()).post {
            try {
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
        
        // Solo procesamos si estamos en la App de Spark o en nuestro panel
        if (packageName.contains("walmart", ignoreCase = true) || 
            packageName.contains("spark", ignoreCase = true) ||
            packageName == "com.spark.autoclicker") {
            
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastClickTime < clickDebounce) return

            val rootNode = rootInActiveWindow ?: return
            try {
                scanForOffers(rootNode)
            } finally {
                rootNode.recycle()
            }
        }
    }

    private fun scanForOffers(node: AccessibilityNodeInfo?): Boolean {
        if (node == null || !isBotActive) return false

        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        
        if (text.isNotBlank()) {
            // Detección de precio
            val priceRegex = Regex("""\$(\d+[\.,]?\d*)""")
            val priceMatch = priceRegex.find(text)
            
            if (priceMatch != null) {
                val currentPrice = priceMatch.groupValues[1].replace(",", ".").toDoubleOrNull() ?: 0.0

                // Detección de distancia
                val distanceRegex = Regex("""(\d+[\.,]?\d*)\s*miles""")
                val currentDistance = distanceRegex.find(text)?.groupValues?.get(1)?.replace(",", ".")?.toDoubleOrNull() ?: 999.0

                // Detección de tienda (opcional)
                val storeRegex = Regex("""#(\d+)""")
                val currentStore = storeRegex.find(text)?.groupValues?.get(1) ?: ""

                // Lógica de filtrado
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

        // Recursión con gestión estricta de memoria
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
        
        try {
            for (targetText in targetTexts) {
                val buttonNode = findNodeByTextManually(rootNode, targetText)
                if (buttonNode != null) {
                    val rect = Rect()
                    buttonNode.getBoundsInScreen(rect)
                    
                    logToFlutter("🔍 Botón '$targetText' localizado en [${rect.centerX()}, ${rect.centerY()}]")
                    
                    lastClickTime = System.currentTimeMillis()

                    // Intento de performAction directo para latencia < 100ms (Regla 3)
                    var clicked = false
                    if (buttonNode.isClickable) {
                        clicked = buttonNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                    
                    if (!clicked) {
                        // Buscar contenedor clickeable hacia arriba en el árbol
                        var parent = buttonNode.parent
                        while (parent != null) {
                            if (parent.isClickable && !clicked) {
                                clicked = parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            }
                            val nextParent = parent.parent
                            parent.recycle()
                            if (clicked) {
                                nextParent?.recycle()
                                break
                            }
                            parent = nextParent
                        }
                    }

                    if (clicked) {
                        logToFlutter("⚡ Clic instantáneo ejecutado vía performAction")
                    } else {
                        // Fallback a GestureDescription con jitter (Regla 3: < 100ms latencia)
                        clickAt(rect)
                    }
                    
                    buttonNode.recycle()
                    return true
                }
            }
        } finally {
            rootNode.recycle()
        }

        logToFlutter("⚠️ Oferta compatible vista pero botón 'Accept' no detectado")
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

    /**
     * Sobrecarga para clics por coordenadas directas (usado en Sandbox o pruebas manuales).
     */
    fun clickAt(x: Float, y: Float) {
        val rect = Rect(x.toInt() - 5, y.toInt() - 5, x.toInt() + 5, y.toInt() + 5)
        clickAt(rect)
    }

    /**
     * Ejecuta un clic programático con simulación humana (Jitter espacial y temporal).
     * Mantiene latencia por debajo de 100ms según requisitos del sistema.
     */
    fun clickAt(rect: Rect) {
        if (!isBotActive) return

        // Latencia controlada: < 100ms (Core Rule). 
        // Se usa un retraso mínimo (10-80ms) para permitir que el SO procese el layout.
        val delayMs = Random.nextLong(10, 80)

        Handler(Looper.getMainLooper()).postDelayed({
            if (!isBotActive) return@postDelayed

            // Jitter espacial (+/- 10px) acotado al tamaño del botón para evitar clics fuera de objetivo
            val width = rect.width()
            val height = rect.height()
            val maxJitterX = minOf(10, maxOf(1, (width * 0.25).toInt()))
            val maxJitterY = minOf(10, maxOf(1, (height * 0.25).toInt()))
            
            val jitterX = rect.centerX() + Random.nextInt(-maxJitterX, maxJitterX + 1).toFloat()
            val jitterY = rect.centerY() + Random.nextInt(-maxJitterY, maxJitterY + 1).toFloat()

            // Duración de la pulsación aleatoria para simular interacción humana
            val strokeDuration = Random.nextLong(30, 70)

            logToFlutter("🖱️ Gesto en ($jitterX, $jitterY) | Latencia: ${delayMs}ms")

            val path = Path()
            path.moveTo(jitterX, jitterY)
            val gestureBuilder = GestureDescription.Builder()
            gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, strokeDuration))

            dispatchGesture(gestureBuilder.build(), object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    logToFlutter("⚡ Gesto completado (Antiban Jitter)")
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    logToFlutter("❌ Gesto cancelado por el sistema")
                }
            }, null)
        }, delayMs)
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
