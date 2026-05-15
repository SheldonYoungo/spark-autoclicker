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

class SparkAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SparkAccessibility"
        var instance: SparkAccessibilityService? = null
    }

    // Configuración del bot
    private var isBotActive = false
    private var minPrice = 0.0
    private var maxDistance = 99.9
    private var storeId = ""
    private var orderType = ""

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Service Connected")
        instance = this
    }

    /**
     * Actualiza la configuración del bot desde Flutter
     */
    fun updateConfig(active: Boolean, price: Double, distance: Double, store: String, type: String) {
        isBotActive = active
        minPrice = price
        maxDistance = distance
        storeId = store
        orderType = type
        Log.d(TAG, "Config actualizada: Active=$isBotActive, MinPrice=$minPrice, Store=$storeId")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isBotActive) return

        val packageName = event.packageName?.toString() ?: return
        if (packageName.contains("walmart", ignoreCase = true) || packageName.contains("spark", ignoreCase = true)) {
            val rootNode = rootInActiveWindow ?: return
            scanForOffers(rootNode)
        }
    }

    private fun scanForOffers(node: AccessibilityNodeInfo) {
        if (!isBotActive) return

        // Buscamos patrones en el texto de los nodos
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        
        if (text.isNotEmpty()) {
            // 1. Extraer Monto ($)
            val priceRegex = Regex("""\$(\d+\.?\d*)""")
            val priceMatch = priceRegex.find(text)
            val currentPrice = priceMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0

            // 2. Extraer Distancia (miles)
            val distanceRegex = Regex("""(\d+\.?\d*)\s*miles""")
            val distanceMatch = distanceRegex.find(text)
            val currentDistance = distanceMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 99.0

            // 3. Extraer Tienda (#)
            val storeRegex = Regex("""#(\d{4})""")
            val storeMatch = storeRegex.find(text)
            val currentStore = storeMatch?.groupValues?.get(1) ?: ""

            // Lógica de Decisión:
            // Si detectamos un monto y este supera nuestro mínimo...
            if (currentPrice >= minPrice && currentPrice > 0) {
                // ...y la distancia es aceptable
                if (currentDistance <= maxDistance) {
                    // ...y si hay filtro de tienda, que coincida
                    if (storeId.isEmpty() || storeId == currentStore) {
                        Log.d(TAG, "¡OFERTA ENCONTRADA! Precio: \$$currentPrice, Distancia: $currentDistance miles")
                        
                        // Buscamos el botón de aceptar en la ventana actual
                        val acceptButtons = findNodesByText("Accept")
                        if (acceptButtons.isNotEmpty()) {
                            val button = acceptButtons[0]
                            val rect = android.graphics.Rect()
                            button.getBoundsInScreen(rect)
                            
                            Log.d(TAG, "Intentando aceptar oferta en (${rect.centerX()}, ${rect.centerY()})")
                            clickAt(rect.centerX().toFloat(), rect.centerY().toFloat())
                        }
                    }
                }
            }
        }

        // Continuar búsqueda en hijos
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
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
        if (!isBotActive) return

        // Anti-ban: Añadimos un pequeño jitter aleatorio a las coordenadas (+/- 8 píxeles)
        val jitterX = x + Random.nextInt(-8, 8).toFloat()
        val jitterY = y + Random.nextInt(-8, 8).toFloat()

        // Anti-ban: Añadimos un delay aleatorio para simular tiempo de reacción humana (150ms a 450ms)
        val humanDelay = Random.nextLong(150, 450)

        Handler(Looper.getMainLooper()).postDelayed({
            val path = Path()
            path.moveTo(jitterX, jitterY)
            val builder = GestureDescription.Builder()
            builder.addStroke(GestureDescription.StrokeDescription(path, 0, 80))
            
            try {
                dispatchGesture(builder.build(), object : GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        super.onCompleted(gestureDescription)
                        Log.d(TAG, "Clic ejecutado en ($jitterX, $jitterY) tras ${humanDelay}ms")
                    }
                }, null)
            } catch (e: Exception) {
                Log.e(TAG, "Error al ejecutar gesto: ${e.message}")
            }
        }, humanDelay)
    }

    fun findNodesByText(text: String): List<AccessibilityNodeInfo> {
        val rootNode = rootInActiveWindow ?: return emptyList()
        return rootNode.findAccessibilityNodeInfosByText(text)
    }
}
