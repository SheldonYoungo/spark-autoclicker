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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * Servicio de Accesibilidad para automatizar la captura de ofertas en Spark.
 * Cumple con latencia < 100ms y simulación de comportamiento humano (Jitter).
 * Implementa Arquitectura "SharedPreferences Source of Truth" para sincronización Isolate-Proof.
 */
class SparkAccessibilityService : AccessibilityService(), SharedPreferences.OnSharedPreferenceChangeListener {

    companion object {
        private const val TAG = "SparkAccessibility"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        var instance: SparkAccessibilityService? = null

        // Regex pre-compilados (se crean UNA sola vez, no en cada nodo)
        private val PRICE_REGEX = Regex("""\$\s*(\d+[\.,]\d+|\d+)""")
        private val DISTANCE_REGEX = Regex("""(\d+[\.,]\d+|\d+)\s*(?:mi|mile|miles|millas|m)\b""", RegexOption.IGNORE_CASE)
        private val STORE_REGEX = Regex("""#\s*(\d+)""")
    }

    var isBotActive = false
        private set
        
    private var minPrice = 0.0
    private var maxDistance = 99.9
    private var storeId = ""
    private var orderType = "" 
    
    private var lastClickTime = 0L
    private val clickDebounce = 500L 
    
    // Kept for backward compatibility with Flutter configs, but no longer blocks scanning.
    private var scanSpeed = 500L 

    private var prefs: SharedPreferences? = null
    
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private val acceptKeywords = listOf(
        "accept", "aceptar", "confirm", "confirmar", "tomar", "take it"
    )

    private fun logToFlutter(message: String) {
        Log.d(TAG, message)
        
        // Filtrar logs para no saturar el hilo de UI en Flutter
        val isCritical = message.startsWith("STATUS:") || 
                         message.startsWith("✅") ||
                         message.startsWith("🤖") ||
                         message.startsWith("🛑") ||
                         message.startsWith("🎯") ||
                         message.startsWith("🔍") ||
                         message.startsWith("⚡") ||
                         message.startsWith("💀")
                         
        if (isCritical) {
            Handler(Looper.getMainLooper()).post {
                try {
                    SparkNativePlugin.sendLogToAll(message)
                } catch (e: Exception) {
                    Log.e(TAG, "Error enviando log: ${e.message}")
                }
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        
        // Limitar el servicio a Spark y a nuestra propia app (para el Sandbox)
        try {
            val info = serviceInfo
            info.packageNames = arrayOf("com.walmart.spark.driver", "com.spark.autoclicker")
            serviceInfo = info
            Log.d(TAG, "📦 packageNames configurados para Accesibilidad")
        } catch (e: Exception) {
            Log.e(TAG, "Error configurando packageNames: ${e.message}")
        }

        instance = this
        
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs?.registerOnSharedPreferenceChangeListener(this)
        
        // Carga inicial
        syncWithPrefs()
        
        logToFlutter("✅ Servicio de Accesibilidad Vinculado (Sync Nativa OK)")
    }

    /**
     * Listener SEGURO de SharedPreferences.
     */
    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) {
        if (key != "flutter.is_bot_active_state" && key != "flutter.bot_filters_config") return
        
        val p = prefs ?: return
        val newActive = p.getBoolean("flutter.is_bot_active_state", false)
        
        // Solo actuar si el estado REALMENTE cambió
        if (newActive == isBotActive && key == "flutter.is_bot_active_state") {
            Log.d(TAG, "🔄 Prefs cambió ($key) pero estado idéntico ($newActive). Ignorando.")
            return
        }
        
        Log.d(TAG, "🔄 Cambio detectado en Prefs: $key. isBotActive: $isBotActive -> $newActive")
        syncWithPrefs()
    }

    private fun syncWithPrefs() {
        val p = prefs ?: return
        
        val active = p.getBoolean("flutter.is_bot_active_state", false)
        val filtersJson = p.getString("flutter.bot_filters_config", null)
        
        if (filtersJson != null) {
            try {
                val json = JSONObject(filtersJson)
                val price = json.optDouble("minPay", 0.0)
                val distance = json.optDouble("maxDistance", 99.0)
                val store = json.optString("storeCode", "")
                val speed = json.optInt("scanSpeed", 500)
                
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
            updateConfig(active, 0.0, 99.0, "", "Any", 500)
        }
        
        if (active) {
            logToFlutter("STATUS:ACTIVE")
        }
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
        
        if (!(packageName.contains("walmart", ignoreCase = true) || 
              packageName.contains("spark", ignoreCase = true) ||
              packageName == "com.spark.autoclicker")) {
            return
        }

        val currentTime = System.currentTimeMillis()
        if (currentTime - lastClickTime < clickDebounce) return

        val allRoots = mutableListOf<AccessibilityNodeInfo>()
        try {
            windows?.forEach { w -> w.root?.let { allRoots.add(it) } }
        } catch (_: Exception) {}
        if (allRoots.isEmpty()) rootInActiveWindow?.let { allRoots.add(it) }
        
        if (allRoots.isEmpty()) return

        var offerFound = false
        var targetRoot: AccessibilityNodeInfo? = null

        // Evaluación síncrona, ventana por ventana, nodo por nodo
        for (root in allRoots) {
            if (searchOfferInNode(root)) {
                offerFound = true
                targetRoot = root
                break
            }
        }

        if (offerFound && targetRoot != null) {
            val rootToProcess = AccessibilityNodeInfo.obtain(targetRoot)
            logToFlutter("🎯 Match de oferta encontrado. Aplicando Greedy Accept...")
            greedyAccept(rootToProcess)
        }

        // Liberar todos los roots obtenidos de allRoots
        allRoots.forEach { it.recycle() }
    }

    /**
     * Recorrido recursivo que evalúa el texto de CADA NODO de forma independiente.
     */
    private fun searchOfferInNode(node: AccessibilityNodeInfo?): Boolean {
        if (node == null) return false

        val text = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        val combined = "$text $cd".trim()

        if (combined.isNotBlank()) {
            val priceMatches = PRICE_REGEX.findAll(combined).toList()
            val distMatches = DISTANCE_REGEX.findAll(combined).toList()

            // Solo verificamos si encontramos precio en ESTE nodo
            if (priceMatches.isNotEmpty()) {
                val maxPrice = priceMatches.maxOfOrNull {
                    it.groupValues[1].replace(",", ".").toDoubleOrNull() ?: 0.0
                } ?: 0.0

                // Si hay distancia, obtenemos la máxima. Si no hay, asignamos un valor alto para que no pase el filtro (por seguridad)
                val maxDist = if (distMatches.isNotEmpty()) {
                    distMatches.maxOfOrNull {
                        it.groupValues[1].replace(",", ".").toDoubleOrNull() ?: 0.0
                    } ?: 0.0
                } else {
                    999.0
                }

                if (maxPrice >= minPrice && maxPrice > 0 && maxDist <= maxDistance) {
                    val currentStore = STORE_REGEX.find(combined)?.groupValues?.get(1)
                    val storeOk = if (storeId.isEmpty()) {
                        true
                    } else {
                        val acceptedStores = storeId.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                        acceptedStores.isEmpty() || (currentStore != null && acceptedStores.contains(currentStore))
                    }
                    
                    val typeOk = if (orderType.isBlank() || orderType.equals("Any", ignoreCase = true)) {
                        true
                    } else {
                        val kws = orderType.split(",").map { it.trim() }.filter { it.isNotBlank() }
                        kws.isEmpty() || kws.any { combined.contains(it, ignoreCase = true) }
                    }

                    if (storeOk && typeOk) {
                        Log.d(TAG, "✅ Oferta detectada en nodo único: $$maxPrice, $maxDist mi. Texto: $combined")
                        return true
                    }
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val found = searchOfferInNode(child)
            child?.recycle()
            if (found) return true
        }

        return false
    }

    /**
     * Greedy Accept: Una vez hallada la oferta, busca a nivel del Root el botón "Accept" y le da clic lo más rápido posible.
     */
    private fun greedyAccept(root: AccessibilityNodeInfo) {
        var clicked = false
        for (kw in acceptKeywords) {
            val nodes = root.findAccessibilityNodeInfosByText(kw)
            if (nodes.isNotEmpty()) {
                Log.d(TAG, "🔍 Buscando '$kw': ${nodes.size} nodos encontrados.")
                val validNode = nodes.firstOrNull { node ->
                    val rect = Rect().also { node.getBoundsInScreen(it) }
                    Log.d(TAG, "   -> Evaluando nodo: bounds=$rect, className=${node.className}")
                    val isNotTooGiant = rect.width() < 2000 && rect.height() < 500
                    val hasBounds = !rect.isEmpty
                    isNotTooGiant && hasBounds
                }
                if (validNode != null) {
                    val finalRect = Rect().also { validNode.getBoundsInScreen(it) }
                    Log.d(TAG, "🔍 [Greedy Accept NATIVO] Botón '$kw' válido encontrado en bounds: $finalRect")
                    
                    val nodeToClick = AccessibilityNodeInfo.obtain(validNode)
                    serviceScope.launch {
                        val result = clickNode(nodeToClick, finalRect)
                        nodeToClick.recycle()
                        if (result) logToFlutter("✅ ¡Greedy Accept completado!")
                    }
                    clicked = true
                    nodes.forEach { it.recycle() }
                    break
                } else {
                    Log.d(TAG, "❌ Ningún nodo de '$kw' pasó la validación de tamaño/bounds.")
                    nodes.forEach { it.recycle() }
                }
            }
        }
        
        // Fallback: Búsqueda manual recursiva (Flutter a veces oculta el texto a la API nativa de Android)
        if (!clicked) {
            Log.d(TAG, "⚠️ La búsqueda nativa falló. Intentando búsqueda manual recursiva...")
            val manualNode = findAcceptNodeManually(root)
            if (manualNode != null) {
                val finalRect = Rect().also { manualNode.getBoundsInScreen(it) }
                Log.d(TAG, "🔍 [Greedy Accept MANUAL] Botón encontrado en bounds: $finalRect")
                serviceScope.launch {
                    val result = clickNode(manualNode, finalRect)
                    manualNode.recycle()
                    if (result) logToFlutter("✅ ¡Greedy Accept completado!")
                }
                clicked = true
            } else {
                Log.d(TAG, "❌ La búsqueda manual también falló. No se encontró el botón Accept en la pantalla.")
            }
        }
        
        root.recycle()
    }

    private fun findAcceptNodeManually(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        
        val text = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        val combined = "$text $cd".trim()
        
        if (combined.isNotBlank() && acceptKeywords.any { combined.contains(it, ignoreCase = true) }) {
            val rect = Rect().also { node.getBoundsInScreen(it) }
            val isNotTooGiant = rect.width() < 2000 && rect.height() < 500
            if (!rect.isEmpty && isNotTooGiant) {
                // Prioridad a nodos cliqueables o botones si es posible
                if (node.isClickable || node.className?.toString()?.contains("Button", ignoreCase = true) == true) {
                    return AccessibilityNodeInfo.obtain(node)
                }
                // Si no, igual lo retornamos porque en Flutter a veces el semántico "button" es solo texto
                return AccessibilityNodeInfo.obtain(node)
            }
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            val found = findAcceptNodeManually(child)
            child?.recycle()
            if (found != null) return found
        }
        return null
    }

    private suspend fun clickNode(node: AccessibilityNodeInfo, fallbackRect: Rect?): Boolean {
        return withContext(Dispatchers.Main) {
            lastClickTime = System.currentTimeMillis()

            val rect = fallbackRect ?: Rect().also { node.getBoundsInScreen(it) }
            
            // Intento 1: PRIORIDAD GESTO EN COORDENADAS (Evita falsos positivos de ACTION_CLICK)
            if (!rect.isEmpty) {
                Log.d(TAG, "🎯 Intentando Gesto en coordenadas: $rect")
                val gestureOk = clickAt(rect)
                if (gestureOk) return@withContext true
            }

            // Intento 2: clic directo (Fallback)
            if (node.isClickable) {
                if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    Log.d(TAG, "⚡ ACTION_CLICK directo OK")
                    return@withContext true
                }
            }

            // Intento 3: escalar a padres (Fallback)
            var parent = node.parent
            var d = 0
            while (parent != null && d < 10) {
                if (parent.isClickable) {
                    val ok = parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    parent.recycle()
                    if (ok) {
                        Log.d(TAG, "⚡ ACTION_CLICK padre (d=$d) OK")
                        return@withContext true
                    }
                }
                val next = parent.parent
                parent.recycle()
                parent = next
                d++
            }
            parent?.recycle()

            false
        }
    }

    suspend fun clickAt(x: Float, y: Float): Boolean {
        val rect = Rect(x.toInt() - 5, y.toInt() - 5, x.toInt() + 5, y.toInt() + 5)
        return clickAt(rect)
    }

    suspend fun clickAt(rect: Rect): Boolean {
        if (!isBotActive) return false
        val delayMs = Random.nextLong(10, 80)
        delay(delayMs)
        
        if (!isBotActive) return false
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

        return suspendCoroutine { continuation ->
            val dispatched = dispatchGesture(gestureBuilder.build(), object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    Log.d(TAG, "⚡ Gesto completado (Jitter)")
                    continuation.resume(true)
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    Log.d(TAG, "❌ Gesto cancelado")
                    continuation.resume(false)
                }
            }, null)
            
            if (!dispatched) {
                continuation.resume(false)
            }
        }
    }

    override fun onInterrupt() {
        logToFlutter("🛑 Servicio interrumpido")
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        prefs?.unregisterOnSharedPreferenceChangeListener(this)
        // Marcar el bot como inactivo en SharedPrefs para evitar estado zombie
        prefs?.edit()?.putBoolean("flutter.is_bot_active_state", false)?.apply()
        logToFlutter("💀 Servicio destruido")
        instance = null
    }
}

