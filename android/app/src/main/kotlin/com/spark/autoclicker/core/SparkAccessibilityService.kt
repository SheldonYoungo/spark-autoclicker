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
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import org.json.JSONObject
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import java.text.Normalizer

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
        private val COUNTDOWN_REGEX = Regex("""disponible\s+en\s+(\d{1,2}):(\d{2})""", RegexOption.IGNORE_CASE)
        private val SOLO_PARA_TI_REGEX = Regex("""\bsolo\s+para\s+ti\b|\bjust\s+for\s+you\b""", RegexOption.IGNORE_CASE)
        private val PARADAS_REGEX = Regex("""(\d+)\s*(?:paradas?|stops?)""", RegexOption.IGNORE_CASE)
        private const val MIN_PARADAS = 1
        private const val MAX_PARADAS = 5
        private const val NOTIFICATION_CHANNEL_ID = "spark_bot_service"
        private const val NOTIFICATION_ID = 9001

        init {
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                Log.e(TAG, "🔥 Uncaught exception en ${thread.name}: ${throwable.message}")
            }
        }
    }

    private data class ScanResult(
        val price: Double = 0.0,
        val distance: Double = 999.0,
        val store: String? = null,
        val allTextCombined: String = ""
    )

    var isBotActive = false
        private set

    var testMode = false

    private var minPrice = 0.0
    private var maxDistance = 99.9
    private var storeId = ""
    private var orderType = ""

    private var lastClickTime = 0L
    private val clickDebounce = 250L

    private var lastScrollAtMs = 0L
    private val scrollThrottleMs = 600L

    private var lastCountdownMs = 0L
    private val countdownCooldownMs = 7_000L

    private var lastChevronTapMs = 0L
    private val chevronCooldownMs = 5_000L

    private val screenHeightPx: Int by lazy {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        wm.defaultDisplay.getMetrics(metrics)
        metrics.heightPixels
    }

    private fun isOffScreenBelow(rect: Rect): Boolean {
        return rect.bottom > screenHeightPx - 200
    }

    private enum class TimedOfferState { NONE, PRESENT, PRECLICKED }

    private var prefs: SharedPreferences? = null

    private val exceptionHandler = CoroutineExceptionHandler { _, throwable ->
        Log.e(TAG, "🔥 Coroutine exception: ${throwable.message}")
    }

    private val serviceScope = CoroutineScope(Dispatchers.Default + SupervisorJob() + exceptionHandler)

    private val acceptKeywords = listOf(
        "accept", "aceptar", "confirm", "confirmar", "tomar", "take it", "take order"
    )

    private val TYPE_SYNONYMS = mapOf(
        "compra" to listOf("compra", "shopping", "groceries", "express", "delivery", "envio", "entrega", "grocery"),
        "recolección" to listOf("recolección", "pickup", "curbside", "retiro", "recogida"),
        "retiro" to listOf("recolección", "pickup", "curbside", "retiro", "recogida"),
        "multiviaje" to listOf("multiviaje", "batch", "multiple", "stops", "viaje", "multi"),
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
                         message.startsWith("💀") ||
                         message.startsWith("📦") ||
                         message.startsWith("📋")

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

    private fun sendDiagnosticData(key: String, value: String) {
        val clean = value.replace('\n', ' ').replace('\r', ' ')
        val escaped = clean.replace("\\", "\\\\").replace("\"", "\\\"")
        logToFlutter("DIAG:{\"$key\":\"$escaped\"}")
    }

    private fun sendDiagnosticDataMap(data: Map<String, String>) {
        val json = data.entries.joinToString(",") { (k, v) ->
            val clean = v.replace('\n', ' ').replace('\r', ' ')
            val ev = clean.replace("\\", "\\\\").replace("\"", "\\\"")
            "\"$k\":\"$ev\""
        }
        logToFlutter("DIAG:{$json}")
    }

    // ── Safe node recycling helpers ──

    private fun safeRecycle(node: AccessibilityNodeInfo?) {
        try { node?.recycle() } catch (_: Exception) {}
    }

    private fun safeRecycleAll(nodes: List<AccessibilityNodeInfo?>) {
        for (n in nodes) safeRecycle(n)
    }

    private fun <T> withNode(node: AccessibilityNodeInfo?, block: (AccessibilityNodeInfo) -> T): T? {
        if (node == null) return null
        try {
            return block(node)
        } finally {
            safeRecycle(node)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()

        instance = this
        createNotificationChannel()

        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs?.registerOnSharedPreferenceChangeListener(this)

        syncWithPrefs()

        logToFlutter("✅ Servicio de Accesibilidad Vinculado (Sync Nativa OK)")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Spark Bot",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Mantiene el bot activo escaneando ofertas"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): android.app.Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            android.app.Notification.Builder(this)
        }
        return builder
            .setContentTitle("Spark Bot")
            .setContentText("Escaneando ofertas...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(android.app.Notification.PRIORITY_MIN)
            .build()
    }

    private fun updateForeground(active: Boolean) {
        try {
            if (active) {
                startForeground(NOTIFICATION_ID, buildNotification())
            } else {
                stopForeground(STOP_FOREGROUND_REMOVE)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error en foreground: ${e.message}")
        }
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
        if (active != isBotActive) {
            updateForeground(active)
        }
        isBotActive = active
        minPrice = price
        maxDistance = distance
        storeId = store
        orderType = type

        val statusText = if (active) "ON" else "OFF"
        logToFlutter("🤖 Motor Nativo: Sincronización Automática -> $statusText")
        Log.d(TAG, "⚙️ Config: MinPrice=$price, Distance=$distance, Store=$store, Type=$type")
        sendDiagnosticDataMap(mapOf(
            "native_bot_active" to active.toString(),
            "native_min_price" to price.toString(),
            "native_max_distance" to distance.toString(),
            "native_store_id" to store.ifEmpty { "(empty)" },
            "native_order_type" to type.ifEmpty { "(empty)" },
        ))
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!isBotActive) return

        val packageName = event.packageName?.toString() ?: return

        if (packageName == "com.spark.autoclicker.sandbox") {
            testMode = true
            Log.d(TAG, "🧪 Sandbox detectado — testMode activado")
        }

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
        var actionTaken = false
        var countdownAction = false
        var scrolledForAccept = false

        sendDiagnosticData("windows_count", roots.size.toString())

        try {
            for (root in roots) {
            val pkg = root.packageName?.toString() ?: ""
            val isOurPkg = pkg == "com.spark.autoclicker"
            if (!(pkg.contains("walmart", ignoreCase = true) || (testMode && isOurPkg) || (testMode && pkg == "com.spark.autoclicker.sandbox"))) continue
            sendDiagnosticData("scanning_pkg", pkg)

            if (testMode && isOurPkg) {
                Log.d(TAG, "🧪 Test mode: escaneando ventana propia")
            }

            // Shallow scan for window-context store (headers, outside cards)
            if (windowContextStore == null) {
                val tempResults = mutableListOf<ScanResult>()
                val tempText = StringBuilder()
                collectNodes(root, 0, 8, tempResults, tempText)
                windowContextStore = tempResults.firstOrNull { it.store != null }?.store
            }

            // Phase 1: Click ACEPTAR via card isolation
            val cards = findOfferCards(root)
            sendDiagnosticData("cards_found", cards.size.toString())
            if (cards.isNotEmpty()) {
                for (card in cards) {
                    if (evaluateCard(card, windowContextStore)) {
                        Log.d(TAG, "📦 Card isolation: tarjeta válida encontrada")
                        offerFound = true
                        matchedRoot = AccessibilityNodeInfo.obtain(card)
                        matchedRootIsCard = true
                        break
                    }
                }
                cards.forEach { it.recycle() }
                // No break — let flow continue to chevron tap (Phase 4)
            }

            // Phase 3: Countdown handler — pre-click offers with timer
            if (rootContainsDisponibleEn(root)) {
                val now = System.currentTimeMillis()
                if (now - lastCountdownMs >= countdownCooldownMs) {
                    when (handleTimedOfferCountdown(root)) {
                        TimedOfferState.PRECLICKED -> {
                            lastCountdownMs = System.currentTimeMillis()
                            logToFlutter("⏰ Countdown: oferta aceptada tras temporizador")
                            countdownAction = true
                            actionTaken = true
                            break
                        }
                        else -> {}
                    }
                }
            }

            // Phase 4: Chevron tap — tap top-right corner of matching cards
            if (!matchedRootIsCard && !offerFound) {
                val canChevron = System.currentTimeMillis() - lastChevronTapMs >= chevronCooldownMs
                if (canChevron && findAndTapOfferChevron(root)) {
                    lastChevronTapMs = System.currentTimeMillis()
                    actionTaken = true
                    break
                }
            }
        }

        // Send diagnostics summary
        sendDiagnosticDataMap(mapOf(
            "offer_found" to if (offerFound) "true" else "false",
            "card_matched" to if (matchedRootIsCard) "true" else "false",
            "action_taken" to if (actionTaken) "true" else "false",
            "countdown_action" to if (countdownAction) "true" else "false",
            "scrolled_for_accept" to if (scrolledForAccept) "true" else "false",
        ))

        // Click ACEPTAR if found via card isolation or flat scan
        if (offerFound && matchedRoot != null && !countdownAction) {
            logToFlutter("🎯 Oferta válida encontrada. Buscando botón Accept...")
            var clicked = false

            // Step 1: Search within matchedRoot (fast path — ACEPTAR inside the card)
            for (kw in acceptKeywords) {
                val nodes = matchedRoot.findAccessibilityNodeInfosByText(kw)
                try {
                    if (nodes.isNotEmpty()) {
                        val validNode = nodes.firstOrNull { node ->
                            val rect = Rect().also { node.getBoundsInScreen(it) }
                            val isNotTooGiant = rect.width() < 2000 && rect.height() < 500
                            !rect.isEmpty && isNotTooGiant
                        }
                        if (validNode != null) {
                            val finalRect = Rect().also { validNode.getBoundsInScreen(it) }
                            logToFlutter("🔍 Accept ('$kw') en: $finalRect")
                            if (isOffScreenBelow(finalRect)) {
                                logToFlutter("📜 Accept fuera de pantalla (y=${finalRect.bottom} > $screenHeightPx). Scrolleando...")
                                scrolledForAccept = true
                            } else {
                                val nodeToClick = AccessibilityNodeInfo.obtain(validNode)
                                try {
                                    val result = clickNode(nodeToClick, finalRect)
                                    if (result) {
                                        logToFlutter("✅ ¡Accept completado!")
                                        clicked = true
                                    }
                                } finally {
                                    nodeToClick.recycle()
                                }
                            }
                        }
                    }
                } finally {
                    safeRecycleAll(nodes as List<AccessibilityNodeInfo?>)
                }
                if (clicked) break
            }

            // Step 2: DFS manual within matchedRoot only (no full-window — unsafe across cards)
            if (!clicked) {
                logToFlutter("⚠️ Búsqueda nativa falló. Buscando manualmente en card...")
                val manualNode = findAcceptNodeManually(matchedRoot)
                if (manualNode != null) {
                    val finalRect = Rect().also { manualNode.getBoundsInScreen(it) }
                    logToFlutter("🔍 Accept (manual) en: $finalRect")
                    sendDiagnosticData("accept_result", "found_manual_$finalRect")
                    if (isOffScreenBelow(finalRect)) {
                        logToFlutter("📜 Accept fuera de pantalla (y=${finalRect.bottom} > $screenHeightPx). Scrolleando...")
                        scrolledForAccept = true
                        manualNode.recycle()
                    } else {
                        val result = clickNode(manualNode, finalRect)
                        manualNode.recycle()
                        if (result) {
                            logToFlutter("✅ ¡Accept completado!")
                            sendDiagnosticData("accept_result", "clicked_ok_manual")
                            clicked = true
                        } else {
                            sendDiagnosticData("accept_result", "click_failed_manual")
                        }
                    }
                } else {
                    logToFlutter("❌ No se encontró botón Accept en la tarjeta")
                    sendDiagnosticData("accept_result", "not_found_in_card")
                }
            }
        }

        // Scroll down when no action taken or off-screen button needs revealing
        // Never scroll on our own overlay (com.spark.autoclicker)
        if ((!actionTaken || scrolledForAccept) && canScrollNow()) {
            for (root in roots) {
                val pkg = root.packageName?.toString() ?: ""
                if (pkg == "com.spark.autoclicker") continue
                if (!(pkg.contains("walmart", ignoreCase = true) || (testMode && pkg == "com.spark.autoclicker.sandbox"))) continue
                val scrolled = scrollDown(root)
                if (scrolled) {
                    Log.d(TAG, "📜 Scroll down ejecutado")
                    break
                }
            }
        }

        } finally {
            safeRecycleAll(roots)
            if (offerFound && matchedRoot != null) {
                safeRecycle(matchedRoot)
            }
        }
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

        // Bottom-up: find ACEPTAR buttons, then walk up to card-sized parent
        val acceptNodes = mutableListOf<AccessibilityNodeInfo>()
        findAcceptButtons(root, acceptNodes)

        for (acceptNode in acceptNodes) {
            val card = walkUpToCard(acceptNode, screenWidth)
            if (card != null) {
                cards.add(card)
            }
            acceptNode.recycle()
        }

        return cards
    }

    private fun findAcceptButtons(
        node: AccessibilityNodeInfo?,
        results: MutableList<AccessibilityNodeInfo>
    ) {
        if (node == null) return
        val text = node.text?.toString() ?: ""
        val cd = node.contentDescription?.toString() ?: ""
        val lowerText = text.lowercase()
        val lowerCd = cd.lowercase()
        val hasAcceptText = "aceptar" in lowerText || "accept" in lowerText ||
            "aceptar" in lowerCd || "accept" in lowerCd
        val isButtonClass = node.className?.toString()
            ?.contains("button", ignoreCase = true) == true
        if (hasAcceptText && isButtonClass) {
            results.add(AccessibilityNodeInfo.obtain(node))
            return
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            findAcceptButtons(child, results)
            child.recycle()
        }
    }

    private fun walkUpToCard(
        leaf: AccessibilityNodeInfo,
        screenWidth: Int
    ): AccessibilityNodeInfo? {
        var current = leaf
        var step = 0
        while (step < 100) {
            val parent = current.parent ?: break
            if (parent === current) break
            if (isCardSized(parent, screenWidth) && hasDollarSign(parent)) {
                return AccessibilityNodeInfo.obtain(parent)
            }
            if (current !== leaf) current.recycle()
            current = parent
            step++
        }
        if (current !== leaf) current.recycle()
        return null
    }

    private fun isCardSized(node: AccessibilityNodeInfo, screenWidth: Int): Boolean {
        val rect = Rect().also { node.getBoundsInScreen(it) }
        if (rect.isEmpty) return false
        val width = rect.width()
        val height = rect.height()
        val minWidth = (screenWidth * 0.20).toInt()
        val maxWidth = (screenWidth * 0.98).toInt()
        return width in minWidth..maxWidth && height in 80..2000
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
        collectNodes(card, 0, 40, results, allText)
        if (results.isEmpty()) {
            Log.d(TAG, "📦 Card eval: sin texto accesible")
            sendDiagnosticData("card_rejection", "sin_texto_accesible")
            return false
        }

        val text = allText.toString()
        val preview = text.take(120).replace('\n', ' ')
        Log.d(TAG, "📦 Card eval: \"$preview\"...")
        sendDiagnosticData("card_text_preview", preview)

        // Fase 2 — Bloqueo "solo para ti"
        if (containsBlockedOfferText(text)) {
            Log.d(TAG, "📦 Card rechazada: contiene 'solo para ti'")
            sendDiagnosticData("card_rejection", "solo_para_ti")
            return false
        }

        // Fase 2 — Paradas 1-5
        if (!matchesInternalStops(text)) {
            Log.d(TAG, "📦 Card rechazada: paradas fuera de rango (1-5)")
            sendDiagnosticData("card_rejection", "paradas_fuera_de_rango")
            return false
        }

        val hasValidPrice = results.any { it.price >= minPrice && it.price > 0 }
        if (!hasValidPrice) {
            Log.d(TAG, "📦 Card rechazada: precio < $minPrice")
            sendDiagnosticData("card_rejection", "precio_muy_bajo")
            return false
        }
        val hasValidDistance = results.any { it.distance <= maxDistance }
        if (!hasValidDistance) {
            Log.d(TAG, "📦 Card rechazada: distancia > $maxDistance")
            sendDiagnosticData("card_rejection", "distancia_muy_alta")
            return false
        }

        val store = results.firstOrNull { it.store != null }?.store ?: windowContextStore
        if (!storeMatches(store)) {
            Log.d(TAG, "📦 Card rechazada: store $store != [$storeId]")
            sendDiagnosticData("card_rejection", "tienda_no_coincide_${store}_vs_${storeId}")
            return false
        }
        val typeOk = typeMatches(text)
        if (!typeOk) {
            Log.d(TAG, "📦 Card rechazada: type no matchea ($orderType)")
            sendDiagnosticData("card_rejection", "tipo_no_coincide")
        }
        return typeOk
    }

    private fun storeMatches(store: String?): Boolean {
        if (storeId.isEmpty()) return true
        return store != null && store == storeId.trim()
    }

    private fun typeMatches(text: String): Boolean {
        if (orderType.isBlank() || orderType.equals("Any", ignoreCase = true)) return true
        val kws = orderType.split(",").map { it.trim() }.filter { it.isNotBlank() }
        if (kws.isEmpty()) return true
        val folded = foldDiacritics(text).lowercase()

        return kws.any { kw ->
            val nkw = foldDiacritics(kw).lowercase()
            if (folded.contains(nkw)) return true

            val synonyms = TYPE_SYNONYMS.entries.firstOrNull { nkw.contains(foldDiacritics(it.key).lowercase()) }?.value
            if (synonyms != null && synonyms.any { folded.contains(it) }) return true

            false
        }
    }

    private fun foldDiacritics(s: String): String {
        val normalized = Normalizer.normalize(s, Normalizer.Form.NFD)
        return normalized.replace(Regex("""\p{M}+"""), "")
    }

    private fun containsBlockedOfferText(text: String): Boolean {
        val lower = text.lowercase()
        return lower.contains("solo para ti") || lower.contains("just for you") ||
               SOLO_PARA_TI_REGEX.containsMatchIn(text)
    }

    private fun matchesInternalStops(text: String): Boolean {
        val match = PARADAS_REGEX.find(text) ?: return true
        val stops = match.groupValues[1].toIntOrNull() ?: return true
        return stops in MIN_PARADAS..MAX_PARADAS
    }

    // ── Scroll support ──

    private fun canScrollNow(): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastScrollAtMs < scrollThrottleMs) return false
        lastScrollAtMs = now
        return true
    }

    private fun findBestScrollable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var best: AccessibilityNodeInfo? = null
        var bestArea = -1
        fun dfs(node: AccessibilityNodeInfo) {
            try {
                if (node.isScrollable) {
                    val area = rectArea(node)
                    if (area > bestArea) {
                        best?.recycle()
                        best = AccessibilityNodeInfo.obtain(node)
                        bestArea = area
                    }
                }
                for (i in 0 until node.childCount) {
                    val child = node.getChild(i) ?: continue
                    try { dfs(child) } finally { child.recycle() }
                }
            } catch (_: Exception) {}
        }
        dfs(root)
        return best
    }

    private fun scrollDown(root: AccessibilityNodeInfo): Boolean {
        val scrollable = findBestScrollable(root) ?: return false
        try {
            val bounds = Rect()
            scrollable.getBoundsInScreen(bounds)
            if (bounds.isEmpty) return false

            // Gentle swipe: 150px or 25% of viewport, whichever is smaller
            val swipeDistance = minOf(150f, bounds.height() * 0.25f).coerceAtLeast(40f)
            val startX = bounds.centerX().toFloat()
            val startY = (bounds.top + bounds.height() * 0.70f)
                .coerceAtMost((bounds.bottom - 10).toFloat())
            val endY = (startY - swipeDistance)
                .coerceAtLeast((bounds.top + 10).toFloat())

            if (startY <= endY) return false

            val path = Path().apply {
                moveTo(startX, startY)
                lineTo(startX, endY)
            }
            val stroke = GestureDescription.StrokeDescription(path, 0, 120L)
            val gesture = GestureDescription.Builder()
                .addStroke(stroke)
                .build()

            return dispatchGesture(gesture, null, null)
        } catch (_: Exception) {
            return false
        } finally {
            try { scrollable.recycle() } catch (_: Exception) {}
        }
    }

    private fun rectArea(node: AccessibilityNodeInfo): Int {
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        return bounds.width() * bounds.height()
    }

    // ── Chevron tap ──

    private fun tapTopRightCorner(card: AccessibilityNodeInfo): Boolean {
        val bounds = Rect()
        card.getBoundsInScreen(bounds)
        if (bounds.width() <= 1 || bounds.height() <= 1) return false

        val x = (bounds.right - bounds.width() * 0.08f)
            .coerceAtLeast(bounds.left + 1f)
        val y = (bounds.top + bounds.height() * 0.16f)
            .coerceAtMost(bounds.bottom - 1f)

        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 30L)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()

        return dispatchGesture(gesture, null, null)
    }

    private fun nodeMatchesFilters(text: String): Boolean {
        if (containsBlockedOfferText(text)) return false
        if (!matchesInternalStops(text)) return false
        val price = PRICE_REGEX.find(text)?.groupValues?.get(1)
            ?.replace(",", ".")?.toDoubleOrNull() ?: 0.0
        if (price < minPrice || price <= 0) return false
        val distance = DISTANCE_REGEX.find(text)?.groupValues?.get(1)
            ?.replace(",", ".")?.toDoubleOrNull() ?: 999.0
        if (distance > maxDistance) return false
        val store = STORE_REGEX.find(text)?.groupValues?.get(1)
        if (!storeMatches(store)) return false
        return typeMatches(text)
    }

    private fun collectNodeText(node: AccessibilityNodeInfo, maxChars: Int): String {
        val sb = StringBuilder()
        appendNodeTextRecursive(node, sb, maxChars)
        return sb.toString()
    }

    private fun appendNodeTextRecursive(node: AccessibilityNodeInfo, sb: StringBuilder, maxChars: Int) {
        if (sb.length >= maxChars) return
        node.text?.let { t -> if (sb.length < maxChars) sb.append(t).append(' ') }
        node.contentDescription?.let { d -> if (sb.length < maxChars) sb.append(d).append(' ') }
        for (i in 0 until node.childCount) {
            if (sb.length >= maxChars) break
            val child = node.getChild(i) ?: continue
            try { appendNodeTextRecursive(child, sb, maxChars) } finally { child.recycle() }
        }
    }

    private fun findAndTapOfferChevron(root: AccessibilityNodeInfo): Boolean {
        val scoredCards = mutableListOf<Pair<AccessibilityNodeInfo, Int>>()
        fun dfs(node: AccessibilityNodeInfo) {
            try {
                val text = collectNodeText(node, 700)
                if (text.isNotEmpty() && nodeMatchesFilters(text)) {
                    val area = rectArea(node)
                    if (area > 0) {
                        scoredCards.add(AccessibilityNodeInfo.obtain(node) to area)
                    }
                }
                for (i in 0 until node.childCount) {
                    val child = node.getChild(i) ?: continue
                    try { dfs(child) } finally { child.recycle() }
                }
            } catch (_: Exception) {}
        }
        dfs(root)
        if (scoredCards.isEmpty()) return false
        scoredCards.sortBy { it.second }
        try {
            for ((card, _) in scoredCards) {
                if (tapTopRightCorner(card)) return true
            }
        } finally {
            for ((card, _) in scoredCards) {
                try { card.recycle() } catch (_: Exception) {}
            }
        }
        return false
    }

    // ── Countdown handler ──

    private fun rootContainsDisponibleEn(root: AccessibilityNodeInfo): Boolean {
        val text = collectNodeText(root, 1800)
        return COUNTDOWN_REGEX.containsMatchIn(text)
    }

    private suspend fun handleTimedOfferCountdown(root: AccessibilityNodeInfo): TimedOfferState {
        val text = collectNodeText(root, 1800)
        val match = COUNTDOWN_REGEX.find(text) ?: return TimedOfferState.NONE
        val minutes = match.groupValues[1].toIntOrNull() ?: return TimedOfferState.NONE
        val seconds = match.groupValues[2].toIntOrNull() ?: return TimedOfferState.NONE
        if (minutes == 0 && seconds <= 3) return TimedOfferState.NONE
        val totalSeconds = minutes * 60 + seconds
        if (totalSeconds > 30) return TimedOfferState.PRESENT
        val waitMs = (totalSeconds * 1000L) + 1000L
        logToFlutter("⏳ Countdown: ${minutes}m ${seconds}s, esperando ${totalSeconds}s...")
        delay(waitMs)
        try {
            clickAceptarInRoot(root)
            logToFlutter("✅ Click en ACEPTAR tras countdown")
            return TimedOfferState.PRECLICKED
        } catch (_: Exception) {
            return TimedOfferState.PRESENT
        }
    }

    private suspend fun clickAceptarInRoot(root: AccessibilityNodeInfo) {
        for (kw in acceptKeywords) {
            val nodes = root.findAccessibilityNodeInfosByText(kw)
            if (nodes.isNotEmpty()) {
                try {
                    val validNode = nodes.firstOrNull { node ->
                        val r = Rect().also { node.getBoundsInScreen(it) }
                        r.width() < 2000 && r.height() < 500 && !r.isEmpty
                    }
                    if (validNode != null) {
                        val rect = Rect().also { validNode.getBoundsInScreen(it) }
                        val copy = AccessibilityNodeInfo.obtain(validNode)
                        val ok = clickNode(copy, rect)
                        copy.recycle()
                        if (ok) return
                    }
                } finally {
                    nodes.forEach { try { it.recycle() } catch (_: Exception) {} }
                }
            }
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
        try {
            prefs?.unregisterOnSharedPreferenceChangeListener(this)
            prefs?.edit()?.putBoolean("flutter.is_bot_active_state", false)?.commit()
        } catch (_: Exception) {}
        instance = null
        Log.d(TAG, "💀 Servicio destruido")
    }
}
