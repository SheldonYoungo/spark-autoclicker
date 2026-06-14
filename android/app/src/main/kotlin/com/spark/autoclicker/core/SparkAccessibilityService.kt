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
    private val clickDebounce = 250L

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

        val statusText = if (active) "ON" else "OFF"
        logToFlutter("🤖 Motor Nativo: Sincronización Automática -> $statusText")
        Log.d(TAG, "⚙️ Config: MinPrice=$price, Distance=$distance, Store=$store, Type=$type")
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

        val roots = captureRootsOnUiThread()
        if (roots.isEmpty()) return

        serviceScope.launch {
            processAllWindows(roots)
            roots.forEach { it.recycle() }
        }
    }

    private fun captureRootsOnUiThread(): List<AccessibilityNodeInfo> {
        val allRoots = mutableListOf<AccessibilityNodeInfo>()
        try {
            windows?.forEach { w -> w.root?.let { allRoots.add(it) } }
        } catch (_: Exception) {}
        if (allRoots.isEmpty()) rootInActiveWindow?.let { allRoots.add(it) }
        return allRoots
    }

    private suspend fun processAllWindows(roots: List<AccessibilityNodeInfo>) {
        var matchedRoot: AccessibilityNodeInfo? = null
        var offerFound = false
        var matchedRootIsCard = false
        var windowContextStore: String? = null

        for (root in roots) {
            val pkg = root.packageName?.toString() ?: ""
            if (!pkg.contains("walmart", ignoreCase = true)) continue

            // Shallow scan for window-context store (headers, outside cards)
            if (windowContextStore == null) {
                val tempResults = mutableListOf<ScanResult>()
                val tempText = StringBuilder()
                collectNodes(root, 0, 8, tempResults, tempText)
                windowContextStore = tempResults.firstOrNull { it.store != null }?.store
            }

            // Phase 1: Card isolation
            val cards = findOfferCards(root)
            if (cards.isNotEmpty()) {
                for (card in cards) {
                    if (evaluateCard(card, windowContextStore)) {
                        offerFound = true
                        matchedRoot = AccessibilityNodeInfo.obtain(card)
                        matchedRootIsCard = true
                        break
                    }
                }
                cards.forEach { it.recycle() }
                if (offerFound) break
            }

            // Phase 2: Fallback flat scan
            val results = mutableListOf<ScanResult>()
            val allText = StringBuilder()
            collectNodes(root, 0, 30, results, allText)
            if (results.isEmpty()) continue

            val hasValidPrice = results.any { it.price >= minPrice && it.price > 0 }
            if (!hasValidPrice) continue
            val hasValidDistance = results.any { it.distance <= maxDistance }
            if (!hasValidDistance) continue

            val store = results.firstOrNull { it.store != null }?.store ?: windowContextStore
            if (!storeMatches(store)) continue
            if (!typeMatches(allText.toString())) continue

            offerFound = true
            matchedRoot = root
            break
        }

        if (offerFound && matchedRoot != null) {
            logToFlutter("🎯 Oferta válida encontrada. Buscando botón Accept...")
            var clicked = false

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

        for (root in roots) root.recycle()
        if (matchedRootIsCard) matchedRoot?.recycle()
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

    private fun findOfferCards(root: AccessibilityNodeInfo): List<AccessibilityNodeInfo> {
        val cards = mutableListOf<AccessibilityNodeInfo>()
        val screenWidth = try {
            resources.displayMetrics.widthPixels
        } catch (e: Exception) { 1080 }
        findCardContainers(root, cards, screenWidth, 0, 25)
        return cards
    }

    private fun findCardContainers(
        node: AccessibilityNodeInfo?,
        cards: MutableList<AccessibilityNodeInfo>,
        screenWidth: Int,
        depth: Int,
        maxDepth: Int
    ) {
        if (node == null || depth > maxDepth) return
        if (isCardSized(node, screenWidth) && hasDollarSign(node)) {
            cards.add(AccessibilityNodeInfo.obtain(node))
            return
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            findCardContainers(child, cards, screenWidth, depth + 1, maxDepth)
            child.recycle()
        }
    }

    private fun isCardSized(node: AccessibilityNodeInfo, screenWidth: Int): Boolean {
        val rect = Rect().also { node.getBoundsInScreen(it) }
        if (rect.isEmpty) return false
        val width = rect.width()
        val height = rect.height()
        val minWidth = (screenWidth * 0.30).toInt()
        val maxWidth = (screenWidth * 0.95).toInt()
        return width in minWidth..maxWidth && height in 80..1200
    }

    private fun hasDollarSign(node: AccessibilityNodeInfo): Boolean {
        val text = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        if ("$" in text || "$" in cd) return true
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = hasDollarSign(child)
            child.recycle()
            if (found) return true
        }
        return false
    }

    private fun evaluateCard(card: AccessibilityNodeInfo, windowContextStore: String?): Boolean {
        val results = mutableListOf<ScanResult>()
        val allText = StringBuilder()
        collectNodes(card, 0, 15, results, allText)
        if (results.isEmpty()) return false

        val hasValidPrice = results.any { it.price >= minPrice && it.price > 0 }
        if (!hasValidPrice) return false
        val hasValidDistance = results.any { it.distance <= maxDistance }
        if (!hasValidDistance) return false

        val store = results.firstOrNull { it.store != null }?.store ?: windowContextStore
        if (!storeMatches(store)) return false
        return typeMatches(allText.toString())
    }

    private fun storeMatches(store: String?): Boolean {
        if (storeId.isEmpty()) return true
        val accepted = storeId.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        if (accepted.isEmpty()) return true
        return store != null && accepted.contains(store)
    }

    private fun typeMatches(text: String): Boolean {
        if (orderType.isBlank() || orderType.equals("Any", ignoreCase = true)) return true
        val kws = orderType.split(",").map { it.trim() }.filter { it.isNotBlank() }
        if (kws.isEmpty()) return true
        return kws.any { text.contains(it, ignoreCase = true) }
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
