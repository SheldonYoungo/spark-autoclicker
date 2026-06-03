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
    private val clickDebounce = 1000L 
    
    private var scanSpeed = 500L // Delay dinámico entre escaneos (ms)
    private var lastScanTime = 0L

    private var prefs: SharedPreferences? = null
    
    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    @Volatile
    private var isScanning = false

    private var scanJob: kotlinx.coroutines.Job? = null

    private fun logToFlutter(message: String) {
        Log.d(TAG, message)
        
        // Filtrar logs para no saturar el hilo de UI en Flutter
        val isCritical = message.startsWith("STATUS:") || 
                         message.startsWith("✅") ||
                         message.startsWith("🤖") ||
                         message.startsWith("🛑") ||
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
        instance = this
        
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs?.registerOnSharedPreferenceChangeListener(this)
        
        // Carga inicial
        syncWithPrefs()
        
        logToFlutter("✅ Servicio de Accesibilidad Vinculado (Sync Nativa OK)")
    }

    /**
     * Listener SEGURO de SharedPreferences.
     * Solo reacciona a cambios REALES en is_bot_active_state.
     * NUNCA emite STATUS:INACTIVE (eso causaba la autodesactivación).
     * Solo sincroniza cuando el estado cambia genuinamente.
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
        
        // Solo emitir STATUS:ACTIVE si el bot realmente estaba ON (caso: service restart).
        // NUNCA emitir STATUS:INACTIVE aquí — causaría autodesactivación en Flutter.
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

        if (active) {
            startScanningLoop()
        } else {
            stopScanningLoop()
        }
    }

    private fun startScanningLoop() {
        scanJob?.cancel()
        scanJob = serviceScope.launch {
            Log.d(TAG, "⏰ Iniciando loop de escaneo periódico")
            while (isBotActive) {
                if (!isScanning) {
                    val allRoots = mutableListOf<AccessibilityNodeInfo>()
                    withContext(Dispatchers.Main) {
                        try {
                            windows?.forEach { w -> w.root?.let { allRoots.add(it) } }
                        } catch (_: Exception) {}
                        if (allRoots.isEmpty()) rootInActiveWindow?.let { allRoots.add(it) }
                    }

                    if (allRoots.isNotEmpty()) {
                        isScanning = true
                        try {
                            processAllWindows(allRoots)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error en loop de escaneo: ${e.message}")
                        } finally {
                            allRoots.forEach { it.recycle() }
                            isScanning = false
                        }
                    }
                }
                delay(scanSpeed)
            }
            Log.d(TAG, "⏰ Loop de escaneo periódico de bot detenido")
        }
    }

    private fun stopScanningLoop() {
        scanJob?.cancel()
        scanJob = null
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
            if (isScanning) return
            isScanning = true
            lastScanTime = currentTime

            val allRoots = mutableListOf<AccessibilityNodeInfo>()
            try {
                windows?.forEach { w -> w.root?.let { allRoots.add(it) } }
            } catch (_: Exception) {}
            if (allRoots.isEmpty()) rootInActiveWindow?.let { allRoots.add(it) }
            if (allRoots.isEmpty()) {
                isScanning = false
                return
            }

            serviceScope.launch {
                try {
                    processAllWindows(allRoots)
                } catch (e: Exception) {
                    Log.e(TAG, "Error escaneando: ${e.message}")
                } finally {
                    allRoots.forEach { it.recycle() }
                    isScanning = false
                }
            }
        }
    }

    // ── Resultado de un solo recorrido completo del árbol ──
    private class ScanResult {
        var matchFound = false
        var matchPrice = 0.0
        var matchDistance = 999.0
        var matchStore = ""
        var allTextCombined = ""
        var acceptNode: AccessibilityNodeInfo? = null
        var acceptRect: Rect? = null
    }

    private val acceptKeywords = listOf(
        "accept", "aceptar", "confirm", "confirmar", "tomar", "take it"
    )

    /**
     * UN SOLO recorrido de TODAS las ventanas que simultáneamente:
     *   - Evalúa precio/distancia/tienda → detecta match
     *   - Busca nodo cuyo texto contenga "Accept"/"Aceptar" → guarda referencia
     */
    private suspend fun processAllWindows(allRoots: List<AccessibilityNodeInfo>) {
        for (root in allRoots) {
            val rootPkg = root.packageName?.toString() ?: ""
            
            // Optimization: Only traverse windows that belong to Walmart, Spark, or our Sandbox.
            // This prevents massive lag when the Overlay is drawn on top of heavy third-party apps like Instagram.
            if (rootPkg.contains("walmart", ignoreCase = true) || 
                rootPkg.contains("spark", ignoreCase = true) ||
                rootPkg == "com.spark.autoclicker") {
                
                val result = ScanResult()
                collectNodes(root, result)
                
                // Evaluamos los filtros globalmente con la información acumulada de toda la pantalla
                if (result.matchPrice >= minPrice && result.matchPrice > 0 && result.matchDistance <= maxDistance) {
                    val storeOk = storeId.isNotEmpty() && storeId == result.matchStore
                    val typeOk = if (orderType.isBlank() || orderType.equals("Any", ignoreCase = true)) true
                    else {
                        val kws = orderType.split(",").map { it.trim() }.filter { it.isNotBlank() }
                        kws.isEmpty() || kws.any { result.allTextCombined.contains(it, ignoreCase = true) }
                    }
                    if (storeOk && typeOk) {
                        result.matchFound = true
                    }
                }
                
                if (result.matchFound) {
                    logToFlutter("🎯 Match ($rootPkg): \$${result.matchPrice} | ${result.matchDistance} mi | #${result.matchStore}")

                    // ── Estrategia 1: Nodo "Accept" encontrado durante recorrido manual ──
                    if (result.acceptNode != null) {
                        logToFlutter("🔍 Botón Accept localizado (recorrido manual)")
                        val clicked = clickNode(result.acceptNode!!, result.acceptRect)
                        result.acceptNode!!.recycle()
                        if (clicked) {
                            logToFlutter("✅ ¡Clic ejecutado!")
                            return
                        }
                    }

                    // ── Estrategia 2: findAccessibilityNodeInfosByText (apps nativas) ──
                    for (kw in acceptKeywords) {
                        val nodes = root.findAccessibilityNodeInfosByText(kw)
                        if (nodes.isNotEmpty()) {
                            val validNode = nodes.firstOrNull { node ->
                                val rect = Rect().also { node.getBoundsInScreen(it) }
                                val isNotTooGiant = rect.width() < 800 && rect.height() < 300
                                val hasBounds = !rect.isEmpty
                                isNotTooGiant && hasBounds
                            }
                            if (validNode != null) {
                                logToFlutter("🔍 [API nativa] Botón '$kw' válido encontrado")
                                val clicked = clickNode(validNode, null)
                                nodes.forEach { it.recycle() }
                                if (clicked) {
                                    logToFlutter("✅ ¡Clic por API nativa!")
                                    return
                                }
                            }
                            nodes.forEach { it.recycle() }
                        }
                    }
                }
            }
        }
    }
    /**
     * Recorrido recursivo que recolecta match de precio Y nodo Accept en un solo pase.
     */
    private fun collectNodes(node: AccessibilityNodeInfo?, result: ScanResult, depth: Int = 0) {
        if (node == null || depth > 30) return
        // Terminación temprana: ya tenemos match + botón, no hay más que buscar
        if (result.matchFound && result.acceptNode != null) return

        val text = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        val combined = text.ifBlank { cd }

        if (combined.isNotBlank()) {
            // Acumular el texto para cruces de palabras clave en toda la pantalla
            result.allTextCombined += "$combined "

            // ── Detectar match de precio/distancia (Acumulativo) ──
            val priceMatches = PRICE_REGEX.findAll(combined).toList()
            if (priceMatches.isNotEmpty()) {
                val maxPrice = priceMatches.maxOfOrNull {
                    it.groupValues[1].replace(",", ".").toDoubleOrNull() ?: 0.0
                } ?: 0.0
                if (maxPrice > result.matchPrice) result.matchPrice = maxPrice
            }

            val distMatches = DISTANCE_REGEX.findAll(combined).toList()
            if (distMatches.isNotEmpty()) {
                val currentMaxDist = distMatches.maxOfOrNull {
                    it.groupValues[1].replace(",", ".").toDoubleOrNull() ?: 0.0
                } ?: 0.0
                // Guardamos la máxima distancia hallada en toda la orden (total distancia de entrega)
                if (result.matchDistance == 999.0 || currentMaxDist > result.matchDistance) {
                    result.matchDistance = currentMaxDist
                }
            }

            val storeMatch = STORE_REGEX.find(combined)?.groupValues?.get(1)
            if (storeMatch != null) result.matchStore = storeMatch

            // ── Detectar botón Accept/Aceptar (Verificando Clickable) ──
            if (result.acceptNode == null) {
                if (acceptKeywords.any { combined.contains(it, ignoreCase = true) }) {
                    if (node.isClickable || node.className?.toString()?.contains("Button", ignoreCase = true) == true) {
                        result.acceptNode = AccessibilityNodeInfo.obtain(node)
                        result.acceptRect = Rect().also { node.getBoundsInScreen(it) }
                        Log.d(TAG, "🔎 Accept encontrado (Directo): '$combined' click=${node.isClickable} rect=${result.acceptRect} d=$depth")
                    } else {
                        var parent = node.parent
                        var isParentClickable = false
                        while (parent != null) {
                            if (parent.isClickable || parent.className?.toString()?.contains("Button", ignoreCase = true) == true) {
                                isParentClickable = true
                                parent.recycle()
                                break
                            }
                            val next = parent.parent
                            parent.recycle()
                            parent = next
                        }
                        if (isParentClickable) {
                            result.acceptNode = AccessibilityNodeInfo.obtain(node)
                            result.acceptRect = Rect().also { node.getBoundsInScreen(it) }
                            Log.d(TAG, "🔎 Accept encontrado (Padre Clickable): '$combined' rect=${result.acceptRect} d=$depth")
                        }
                    }
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                collectNodes(child, result, depth + 1)
                child.recycle()
            }
        }
    }

    /**
     * Ejecuta clic en un nodo priorizando Gesto (bypass anti-bot) o escalando.
     */
    private suspend fun clickNode(node: AccessibilityNodeInfo, fallbackRect: Rect?): Boolean {
        return withContext(Dispatchers.Main) {
            lastClickTime = System.currentTimeMillis()

            val rect = fallbackRect ?: Rect().also { node.getBoundsInScreen(it) }
            
            // Intento 1: PRIORIDAD GESTO EN COORDENADAS (Evita falsos positivos de ACTION_CLICK)
            if (!rect.isEmpty) {
                logToFlutter("🎯 Intentando Gesto en coordenadas: $rect")
                val gestureOk = clickAt(rect)
                if (gestureOk) return@withContext true
            }

            // Intento 2: clic directo (Fallback)
            if (node.isClickable) {
                if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    logToFlutter("⚡ ACTION_CLICK directo OK")
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
                        logToFlutter("⚡ ACTION_CLICK padre (d=$d) OK")
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
                    logToFlutter("⚡ Gesto completado (Jitter)")
                    continuation.resume(true)
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    logToFlutter("❌ Gesto cancelado")
                    continuation.resume(false)
                }
            }, null)
            
            if (!dispatched) {
                continuation.resume(false)
            }
        }
    }

    override fun onInterrupt() {
        stopScanningLoop()
        logToFlutter("🛑 Servicio interrumpido")
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        stopScanningLoop()
        prefs?.unregisterOnSharedPreferenceChangeListener(this)
        logToFlutter("💀 Servicio destruido")
        instance = null
    }
}
