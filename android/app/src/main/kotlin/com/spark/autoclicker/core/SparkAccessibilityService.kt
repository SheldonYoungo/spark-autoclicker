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
import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Servicio de Accesibilidad para automatizar la captura de ofertas en Spark.
 * Cumple con latencia < 100ms y simulación de comportamiento humano (Jitter).
 * Implementa Arquitectura "SharedPreferences Source of Truth" para sincronización Isolate-Proof.
 */
class SparkAccessibilityService : AccessibilityService(), SharedPreferences.OnSharedPreferenceChangeListener {

    companion object {
        private const val TAG = "SparkAccessibility"
        private const val PREFS_NAME = "FlutterSharedPreferences" // Nombre estándar usado por SharedPreferences plugin
        var instance: SparkAccessibilityService? = null
    }

    var isBotActive = false
        private set
        
    private var minPrice = 0.0
    private var maxDistance = 99.9
    private var storeId = ""
    private var orderType = "" 
    
    private var lastClickTime = 0L
    private val clickDebounce = 1000L 
    
    private var scanSpeed = 500L // Delay dinámico entre escaneos (ms)
    private var lastScanTime = 0L

    private var prefs: SharedPreferences? = null

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
        
        // Inicializar escucha de preferencias para sincronización Isolate-agnostic
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs?.registerOnSharedPreferenceChangeListener(this)
        
        // Carga inicial
        syncWithPrefs()
        
        logToFlutter("✅ Servicio de Accesibilidad Vinculado (Sync Nativa OK)")
    }

    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) {
        // Las llaves del plugin SharedPreferences de Flutter suelen tener prefijo "flutter."
        if (key == "flutter.is_bot_active_state" || key == "flutter.bot_filters_config") {
            Log.d(TAG, "🔄 Cambio detectado en Prefs: $key. Sincronizando...")
            syncWithPrefs()
        }
    }

    private fun syncWithPrefs() {
        val p = prefs ?: return
        
        // 1. Cargar estado de activación
        val active = p.getBoolean("flutter.is_bot_active_state", false)
        
        // 2. Cargar filtros
        val filtersJson = p.getString("flutter.bot_filters_config", null)
        
        if (filtersJson != null) {
            try {
                val json = JSONObject(filtersJson)
                val price = json.optDouble("minPay", 0.0)
                val distance = json.optDouble("maxDistance", 99.0)
                val store = json.optString("storeCode", "")
                val speed = json.optInt("scanSpeed", 500)
                
                // Mapeo de tipos de orden
                val typesArray = json.optJSONArray("orderTypes")
                val typesList = mutableListOf<String>()
                if (typesArray != null) {
                    for (i in 0 until typesArray.length()) {
                        typesList.add(typesArray.getString(i))
                    }
                }
                val typesStr = if (typesList.isEmpty()) "Any" else typesList.joinToString(",")

                updateConfig(active, price, distance, store, typesStr, speed)
                
            } catch (e: Exception) {
                Log.e(TAG, "Error parseando filtros JSON: ${e.message}")
            }
        } else {
            // Si no hay filtros, solo actualizar estado activo con valores por defecto
            updateConfig(active, 0.0, 99.0, "", "Any", 500)
        }
        
        // Emitir estado actual para sincronizar UI de Isolates que podrían estar dormidos
        val statusEvent = if (active) "STATUS:ACTIVE" else "STATUS:INACTIVE"
        logToFlutter(statusEvent)
    }

    fun updateConfig(active: Boolean, price: Double, distance: Double, store: String, type: String, speed: Int) {
        isBotActive = active
        minPrice = price
        maxDistance = distance
        storeId = store
        orderType = type
        scanSpeed = speed.toLong()
        
        val statusText = if (active) "ON" else "OFF"
        logToFlutter("🤖 Motor Nativo: Sincronización Automática -> $statusText")
        Log.d(TAG, "⚙️ Config: MinPrice=$price, Distance=$distance, Store=$store, Type=$type, Speed=${scanSpeed}ms")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isBotActive) return

        val packageName = event.packageName?.toString() ?: return
        
        if (packageName.contains("walmart", ignoreCase = true) || 
            packageName.contains("spark", ignoreCase = true) ||
            packageName == "com.spark.autoclicker") {
            
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastClickTime < clickDebounce) return
            
            if (currentTime - lastScanTime < scanSpeed) return
            lastScanTime = currentTime

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
        
        try {
            for (targetText in targetTexts) {
                val buttonNode = findNodeByTextManually(rootNode, targetText)
                if (buttonNode != null) {
                    val rect = Rect()
                    buttonNode.getBoundsInScreen(rect)
                    logToFlutter("🔍 Botón '$targetText' localizado")
                    lastClickTime = System.currentTimeMillis()

                    var clicked = false
                    if (buttonNode.isClickable) {
                        clicked = buttonNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                    
                    if (!clicked) {
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
                        logToFlutter("⚡ Clic instantáneo ejecutado")
                    } else {
                        clickAt(rect)
                    }
                    
                    buttonNode.recycle()
                    return true
                }
            }
        } finally {
            rootNode.recycle()
        }
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
        val rect = Rect(x.toInt() - 5, y.toInt() - 5, x.toInt() + 5, y.toInt() + 5)
        clickAt(rect)
    }

    fun clickAt(rect: Rect) {
        if (!isBotActive) return
        val delayMs = Random.nextLong(10, 80)
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isBotActive) return@postDelayed
            val width = rect.width()
            val height = rect.height()
            val maxJitterX = minOf(10, maxOf(1, (width * 0.25).toInt()))
            val maxJitterY = minOf(10, maxOf(1, (height * 0.25).toInt()))
            val jitterX = rect.centerX() + Random.nextInt(-maxJitterX, maxJitterX + 1).toFloat()
            val jitterY = rect.centerY() + Random.nextInt(-maxJitterY, maxJitterY + 1).toFloat()
            val strokeDuration = Random.nextLong(30, 70)

            val path = Path()
            path.moveTo(jitterX, jitterY)
            val gestureBuilder = GestureDescription.Builder()
            gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, strokeDuration))

            dispatchGesture(gestureBuilder.build(), object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    logToFlutter("⚡ Gesto completado (Jitter)")
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    logToFlutter("❌ Gesto cancelado")
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
        prefs?.unregisterOnSharedPreferenceChangeListener(this)
        logToFlutter("💀 Servicio destruido")
        instance = null
    }
}
