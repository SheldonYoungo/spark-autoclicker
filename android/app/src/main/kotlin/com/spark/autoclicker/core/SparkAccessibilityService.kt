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
 * Servicio de Accesibilidad para automatizar la captura de ofertas en Spark Driver.
 * Acumula información de precios y distancias de TODOS los nodos visibles
 * (Walmart separa precio y distancia en nodos distintos del árbol de accesibilidad).
 *
 * Arquitectura: collectNodes (DFS) -> processAllWindows (evaluación global) -> accept click.
 */
class SparkAccessibilityService : AccessibilityService(), SharedPreferences.OnSharedPreferenceChangeListener {

    companion object {
        private const val TAG = "SparkAccessibility"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        var instance: SparkAccessibilityService? = null

        private val PRICE_REGEX = Regex("""\$\s*(\d+[\.,]\d+|\d+)""")
        private val DISTANCE_REGEX = Regex("""(\d+[\.,]\d+|\d+)\s*(?:mi|mile|miles|millas|m)\b""", RegexOption.IGNORE_CASE)
        private val STORE_REGEX = Regex("""#\s*(\d+)""")
    }

    private data class ScanResult(
        val price: Double = 0.0,
        val distance: Double = 999.0,
        val store: String? = null,
        val allTextCombined: String = ""
    )

    var isBotActive = false
        private set

    private var minPrice = 0.0
    private var maxDistance = 99.9
    private var storeId = ""
    private var orderType = ""

    private var lastClickTime = 0L
    private var lastScanTime = 0L
    private val clickDebounce = 500L
    private var scanSpeed = 300L

    private var prefs: SharedPreferences? = null

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    private val acceptKeywords = listOf(
        "accept", "aceptar", "confirm", "confirmar", "tomar", "take it"
    )

    private fun logToFlutter(message: String) {
        Log.d(TAG, message)

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

        syncWithPrefs()

        logToFlutter("✅ Servicio de Accesibilidad Vinculado (Sync Nativa OK)")
    }

    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) {
        if (key != "flutter.is_bot_active_state" && key != "flutter.bot_filters_config") return

        val p = prefs ?: return
        val newActive = p.getBoolean("flutter.is_bot_active_state", false)

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
                val speed = json.optInt("scanSpeed", 300)

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
            updateConfig(active, 0.0, 99.0, "", "Any", 300)
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
        scanSpeed = if (speed > 0) speed.toLong() else 300L

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
        if (currentTime - lastScanTime < scanSpeed) return
        lastScanTime = currentTime

        serviceScope.launch {
            processAllWindows()
        }
    }

    /**
     * Procesa TODAS las ventanas visibles. Acumula ScanResults de cada nodo y evalúa
     * la oferta de forma GLOBAL: precio de un nodo, distancia de otro (Walmart los separa).
     */
    private suspend fun processAllWindows() {
        val allRoots = mutableListOf<AccessibilityNodeInfo>()
        try {
            windows?.forEach { w -> w.root?.let { allRoots.add(it) } }
        } catch (_: Exception) {}
        if (allRoots.isEmpty()) rootInActiveWindow?.let { allRoots.add(it) }
        if (allRoots.isEmpty()) return

        var matchedRoot: AccessibilityNodeInfo? = null
        var offerFound = false

        for (root in allRoots) {
            val results = mutableListOf<ScanResult>()
            val allText = StringBuilder()
            collectNodes(root, 0, 30, results, allText)

            if (results.isEmpty()) continue

            val hasValidPrice = results.any { it.price >= minPrice && it.price > 0 }
            if (!hasValidPrice) continue

            val hasValidDistance = results.any { it.distance <= maxDistance }
            val combinedStore = results.firstOrNull { it.store != null }?.store
            val storeOk = if (storeId.isEmpty()) {
                true
            } else {
                val acceptedStores = storeId.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                acceptedStores.isEmpty() || (combinedStore != null && acceptedStores.contains(combinedStore))
            }
            val typeOk = if (orderType.isBlank() || orderType.equals("Any", ignoreCase = true)) {
                true
            } else {
                val kws = orderType.split(",").map { it.trim() }.filter { it.isNotBlank() }
                kws.isEmpty() || kws.any { allText.contains(it, ignoreCase = true) }
            }

            if (hasValidPrice && hasValidDistance && storeOk && typeOk) {
                offerFound = true
                matchedRoot = root
                break
            }
        }

        if (offerFound && matchedRoot != null) {
            logToFlutter("🎯 Oferta válida encontrada. Buscando botón Accept...")
            var clicked = false

            // Intento 1: findAccessibilityNodeInfosByText (nativo, rápido)
            for (kw in acceptKeywords) {
                val nodes = matchedRoot.findAccessibilityNodeInfosByText(kw)
                if (nodes.isNotEmpty()) {
                    val validNode = nodes.firstOrNull { node ->
                        val rect = Rect().also { node.getBoundsInScreen(it) }
                        val isNotTooGiant = rect.width() < 2000 && rect.height() < 500
                        !rect.isEmpty && isNotTooGiant
                    }
                    if (validNode != null) {
                        val finalRect = Rect().also { validNode.getBoundsInScreen(it) }
                        logToFlutter("🔍 Accept ('$kw') en: $finalRect")
                        val nodeToClick = AccessibilityNodeInfo.obtain(validNode)
                        val result = clickNode(nodeToClick, finalRect)
                        nodeToClick.recycle()
                        if (result) {
                            logToFlutter("✅ ¡Accept completado!")
                            clicked = true
                        }
                    }
                    nodes.forEach { it.recycle() }
                    if (clicked) break
                }
            }

            // Intento 2: búsqueda manual recursiva (fallback para Flutter/React Native)
            if (!clicked) {
                logToFlutter("⚠️ Búsqueda nativa falló. Buscando manualmente...")
                val manualNode = findAcceptNodeManually(matchedRoot)
                if (manualNode != null) {
                    val finalRect = Rect().also { manualNode.getBoundsInScreen(it) }
                    logToFlutter("🔍 Accept (manual) en: $finalRect")
                    val result = clickNode(manualNode, finalRect)
                    manualNode.recycle()
                    if (result) {
                        logToFlutter("✅ ¡Accept completado!")
                        clicked = true
                    }
                } else {
                    logToFlutter("❌ No se encontró botón Accept en la pantalla")
                }
            }
        } else {
            Log.d(TAG, "⏳ No se encontraron ofertas válidas en este scan")
        }

        allRoots.forEach { it.recycle() }
    }

    /**
     * DFS recursivo con depth limit. Acumula ScanResult por cada nodo que tenga texto.
     * Esto permite evaluar precio y distancia aunque estén en nodos separados del árbol.
     */
    private fun collectNodes(
        node: AccessibilityNodeInfo?,
        depth: Int,
        maxDepth: Int,
        results: MutableList<ScanResult>,
        allText: StringBuilder
    ) {
        if (node == null || depth > maxDepth) return

        val text = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        val combined = "$text $cd".trim()

        if (combined.isNotBlank()) {
            allText.append(combined).append(" ")

            val price = PRICE_REGEX.find(combined)?.groupValues?.get(1)
                ?.replace(",", ".")?.toDoubleOrNull() ?: 0.0
            val distance = DISTANCE_REGEX.find(combined)?.groupValues?.get(1)
                ?.replace(",", ".")?.toDoubleOrNull() ?: 999.0
            val store = STORE_REGEX.find(combined)?.groupValues?.get(1)

            results.add(ScanResult(price, distance, store, combined))
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectNodes(child, depth + 1, maxDepth, results, allText)
            child.recycle()
        }
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
                if (node.isClickable || node.className?.toString()?.contains("Button", ignoreCase = true) == true) {
                    return AccessibilityNodeInfo.obtain(node)
                }
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

            // Intento 1: gesto en coordenadas con Jitter (evita falsos positivos de ACTION_CLICK)
            if (!rect.isEmpty) {
                Log.d(TAG, "🎯 Intentando Gesto en coordenadas: $rect")
                val gestureOk = clickAt(rect)
                if (gestureOk) return@withContext true
            }

            // Intento 2: ACTION_CLICK directo
            if (node.isClickable) {
                if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    Log.d(TAG, "⚡ ACTION_CLICK directo OK")
                    return@withContext true
                }
            }

            // Intento 3: escalar a padres
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
        prefs?.edit()?.putBoolean("flutter.is_bot_active_state", false)?.apply()
        logToFlutter("💀 Servicio destruido")
        instance = null
    }
}
