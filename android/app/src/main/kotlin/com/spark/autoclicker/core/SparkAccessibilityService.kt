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

    private fun logToFlutter(message: String) {
        Log.d(TAG, message)
        Handler(Looper.getMainLooper()).post {
            try {
                com.spark.autoclicker.MainActivity.methodChannel?.invokeMethod("nativeLog", message)
            } catch (e: Exception) {
                // Ignore
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        logToFlutter("Service Connected")
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
        logToFlutter("Config actualizada: Active=$isBotActive, MinPrice=$minPrice, Store=$storeId")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isBotActive) return

        val packageName = event.packageName?.toString() ?: return
        // Permitimos walmart, spark y nuestro propio paquete para el Sandbox
        if (packageName.contains("walmart", ignoreCase = true) || 
            packageName.contains("spark", ignoreCase = true) ||
            packageName == "com.spark.autoclicker") {
            val rootNode = rootInActiveWindow ?: return
            scanForOffers(rootNode)
        }
    }

    private fun scanForOffers(node: AccessibilityNodeInfo) {
        if (!isBotActive) return

        // Buscamos patrones en el texto de los nodos
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        
        if (text.isNotEmpty()) {
            // Log para debug (solo en sandbox o con prefijo Monto/Distancia para no saturar)
            if (text.contains("Monto") || text.contains("miles") || text.contains("#")) {
                logToFlutter("Analizando nodo: $text")
            }

            // 1. Extraer Monto ($)
            val priceRegex = Regex("""\$(\d+\.?\d*)""")
            val priceMatch = priceRegex.find(text)
            val currentPrice = priceMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0

            // 2. Extraer Distancia (miles)
            val distanceRegex = Regex("""(\d+\.?\d*)\s*miles""")
            val distanceMatch = distanceRegex.find(text)
            val currentDistance = distanceMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 99.0

            // 3. Extraer Tienda (#)
            val storeRegex = Regex("""#(\d+)""")
            val storeMatch = storeRegex.find(text)
            val currentStore = storeMatch?.groupValues?.get(1) ?: ""

            if (currentPrice > 0) {
                logToFlutter("Lectura: \$$currentPrice | $currentDistance mi | Store: #${if(currentStore.isEmpty()) "???" else currentStore}")
            }

            // Lógica de Decisión:
            // Si detectamos un monto y este supera nuestro mínimo...
            if (currentPrice >= minPrice && currentPrice > 0) {
                // ...y la distancia es aceptable
                if (currentDistance <= maxDistance) {
                    // ...y si hay filtro de tienda, que coincida
                    if (storeId.isEmpty() || storeId == currentStore) {
                        logToFlutter("¡CRITERIOS CUMPLIDOS! Evaluando clic...")
                        
                        // Buscamos el botón de aceptar en la ventana actual
                        val acceptButtons = findNodesByText("Accept")
                        var targetNode: AccessibilityNodeInfo? = if (acceptButtons.isNotEmpty()) acceptButtons[0] else null

                        // Fallback: Búsqueda manual si la búsqueda nativa falla (típico en Flutter)
                        if (targetNode == null) {
                            logToFlutter("Búsqueda nativa falló, intentando búsqueda manual profunda...")
                            rootInActiveWindow?.let { root ->
                                targetNode = findNodeByTextManually(root, "Accept")
                            }
                        }

                        if (targetNode != null) {
                            val rect = android.graphics.Rect()
                            targetNode!!.getBoundsInScreen(rect)
                            
                            logToFlutter("BOTÓN ENCONTRADO en (${rect.centerX()}, ${rect.centerY()}). Ejecutando clic...")
                            clickAt(rect.centerX().toFloat(), rect.centerY().toFloat())
                        } else {
                            logToFlutter("Error: Botón 'Accept' no detectado. Volcando nodos...")
                            rootInActiveWindow?.let { dumpAllNodes(it) }
                        }
                    } else {
                        logToFlutter("Descartado: Store $currentStore != $storeId")
                    }
                } else {
                    logToFlutter("Descartado: Distancia $currentDistance > $maxDistance")
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
        logToFlutter("Service Interrupted")
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        logToFlutter("Service Destroyed")
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
                        logToFlutter("Clic ejecutado en ($jitterX, $jitterY) tras ${humanDelay}ms")
                    }
                }, null)
            } catch (e: Exception) {
                logToFlutter("Error al ejecutar gesto: ${e.message}")
            }
        }, humanDelay)
    }

    fun findNodesByText(text: String): List<AccessibilityNodeInfo> {
        val rootNode = rootInActiveWindow ?: return emptyList()
        return rootNode.findAccessibilityNodeInfosByText(text)
    }

    private fun findNodeByTextManually(node: AccessibilityNodeInfo, targetText: String): AccessibilityNodeInfo? {
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        if (text.contains(targetText, ignoreCase = true)) {
            return node
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findNodeByTextManually(child, targetText)
            if (found != null) {
                return found
            }
            child.recycle()
        }
        return null
    }

    private fun dumpAllNodes(node: AccessibilityNodeInfo) {
        val text = node.text?.toString() ?: node.contentDescription?.toString() ?: ""
        if (text.isNotEmpty()) {
            logToFlutter("Nodo visible: [$text] - clickable: ${node.isClickable}")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            dumpAllNodes(child)
            child.recycle()
        }
    }
}
