import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../domain/filter_model.dart';
import '../../../core/utils/accessibility_util.dart';
import '../../../core/network/ntp_service.dart';

class FilterService {
  static const String _storageKey = 'bot_filters_config';
  static const String _keyBotActive = 'is_bot_active_state';
  static const String _keyExpiration = 'auth_expiration_ts';
  static const String _keyStatus = 'auth_status';
  
  static final FilterService _instance = FilterService._internal();
  factory FilterService() => _instance;
  FilterService._internal();

  // Flag para identificar el isolate principal de forma robusta
  static bool isMainIsolate = false;

  final ValueNotifier<BotFilters> filtersNotifier = ValueNotifier<BotFilters>(BotFilters());
  final ValueNotifier<bool> isBotActiveNotifier = ValueNotifier<bool>(false);
  bool _isInitialized = false;

  // StreamController broadcast para notificar a la UI (overlay_screen, bot_main_screen)
  static final StreamController<dynamic> _overlayEventController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get overlayEvents => _overlayEventController.stream;

  // Canal directo — bypass del getter overlayListener (que usa StreamController non-broadcast y se rompe con hot-restart)
  static const BasicMessageChannel _overlayMessageChannel =
      BasicMessageChannel("x-slayer/overlay_messenger", JSONMessageCodec());
  static bool _messageHandlerRegistered = false;

  void _initOverlayListener() {
    if (_messageHandlerRegistered) {
      debugPrint("FilterService: Listener ya registrado. Omitiendo.");
      return;
    }
    _messageHandlerRegistered = true;

    debugPrint("FilterService: Registrando messageHandler directo. isMainIsolate: $isMainIsolate");
    _overlayMessageChannel.setMessageHandler((message) async {
      debugPrint("FilterService: MENSAJE RECIBIDO: $message (isMain: $isMainIsolate)");
      
      dynamic decodedEvent = message;
      // Procesar si el evento viene como JSON string
      if (message is String) {
        final trimmed = message.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try {
            decodedEvent = jsonDecode(trimmed);
          } catch (_) {}
        }
      }

      // SOLO el engine Main puede ejecutar lógica nativa (MethodChannels)
      if (isMainIsolate) {
        if (decodedEvent == 'request_sync_native') {
          debugPrint("FilterService: [Main] Ejecutando sincronización nativa solicitada");
          await syncWithNative(isBotActiveNotifier.value, isProxy: false);
        } else if (decodedEvent is Map && decodedEvent['type'] == 'request_toggle_bot') {
          final bool active = decodedEvent['active'] ?? false;
          debugPrint("FilterService: [Main] SOLICITUD TOGGLE: active=$active");
          await _executeToggle(active);
        } else if (decodedEvent == 'request_accessibility_check') {
          final bool isEnabled = await AccessibilityUtil.isServiceEnabled();
          await FlutterOverlayWindow.shareData({
            'type': 'accessibility_result',
            'enabled': isEnabled,
          });
        } else if (decodedEvent == 'request_open_settings') {
          await AccessibilityUtil.openSettings();
        }
      }

      // LÓGICA COMPARTIDA — Actualizar estado local para que la UI reaccione
      if (decodedEvent == 'bot_activated') {
        debugPrint("FilterService: [${isMainIsolate ? 'Main' : 'Overlay'}] Notifier -> ACTIVE");
        isBotActiveNotifier.value = true;
      } else if (decodedEvent == 'bot_deactivated') {
        debugPrint("FilterService: [${isMainIsolate ? 'Main' : 'Overlay'}] Notifier -> INACTIVE");
        isBotActiveNotifier.value = false;
      } else if (decodedEvent == 'refresh_filters') {
        await loadFilters(forceReload: true);
      }
      
      if (!_overlayEventController.isClosed) {
        _overlayEventController.add(decodedEvent);
      }

      return message; // Requerido por el protocolo del BasicMessageChannel
    });
  }

  /// Inicializa o carga los filtros.
  Future<BotFilters> loadFilters({bool forceReload = false}) async {
    if (!_isInitialized) {
      _initOverlayListener();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (forceReload) await prefs.reload();
      
      final bool botActive = prefs.getBool(_keyBotActive) ?? false;
      isBotActiveNotifier.value = botActive;

      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        final filters = BotFilters.fromJson(json);
        
        filtersNotifier.value = filters;
        _isInitialized = true;

        return filters;
      }
    } catch (e) {
      debugPrint("FilterService: Error en loadFilters: $e");
    }
    _isInitialized = true;
    return filtersNotifier.value;
  }

  Future<bool> isSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final int? expirationTs = prefs.getInt(_keyExpiration);
      final String? status = prefs.getString(_keyStatus);
      if (expirationTs == null || status != 'active') return false;
      final DateTime networkTime = await NtpService.getNetworkTime();
      final DateTime expirationDate = DateTime.fromMillisecondsSinceEpoch(expirationTs);
      return networkTime.isBefore(expirationDate);
    } catch (e) {
      return false;
    }
  }

  Future<void> saveFilters(BotFilters newFilters) async {
    try {
      double validatedMinPay = newFilters.minPay;
      if (validatedMinPay < 13.0) validatedMinPay = 13.0;
      if (validatedMinPay > 150.0) validatedMinPay = 150.0;
      final validatedFilters = newFilters.copyWith(minPay: validatedMinPay);
      filtersNotifier.value = validatedFilters;
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(validatedFilters.toJson());
      await prefs.setString(_storageKey, jsonStr);
      
      final bool isOverlayOpen = await FlutterOverlayWindow.isActive();
      if (isOverlayOpen) {
        await FlutterOverlayWindow.shareData('refresh_filters');
      }
      
      if (isBotActiveNotifier.value) {
        await syncWithNative(true);
      }
    } catch (e) {
      debugPrint("FilterService: Error en saveFilters: $e");
    }
  }

  Future<void> syncWithNative(bool active, {bool isProxy = true}) async {
    // Si no estamos en el isolate principal, delegamos al principal
    if (isProxy && !isMainIsolate) {
      debugPrint("FilterService: [Overlay] syncWithNative -> delegando al Main");
      await FlutterOverlayWindow.shareData('request_sync_native');
      return;
    }

    debugPrint("FilterService: [Main] Sincronizando con Nativo: active=$active");

    if (active) {
      final isValid = await isSessionValid();
      if (!isValid) {
        debugPrint("FilterService: [Main] Sesión inválida en syncWithNative, desactivando.");
        await AccessibilityUtil.updateBotConfiguration(
          isActive: false, minPrice: 0, maxDistance: 0, storeId: "", orderType: "NONE"
        );
        return;
      }
    }
    
    final filters = filtersNotifier.value;
    final String orderTypeStr = filters.orderTypes.isEmpty ? "Any" : filters.orderTypes.join(",");
    
    await AccessibilityUtil.updateBotConfiguration(
      isActive: active,
      minPrice: filters.minPay,
      maxDistance: filters.maxDistance,
      storeId: filters.storeCode ?? "",
      orderType: orderTypeStr,
    );
  }

  Future<void> toggleBot(bool active) async {
    // Si estamos en el Overlay, redirigir al Main engine via shareData
    if (!isMainIsolate) {
      debugPrint("FilterService: [Overlay] Enviando PETICIÓN toggleBot($active) al Main");
      await FlutterOverlayWindow.shareData({
        'type': 'request_toggle_bot',
        'active': active,
      });
      return;
    }

    // Si estamos en el Main engine, ejecutar directamente
    await _executeToggle(active);
  }

  /// Lógica real del toggle. SOLO se ejecuta en el Main engine.
  /// Llamado por toggleBot (directo) o por el overlayListener (delegado).
  Future<void> _executeToggle(bool active) async {
    debugPrint("FilterService: [Main] _executeToggle($active)");

    if (active) {
      await loadFilters(forceReload: true);
      try {
        bool isEnabled = await AccessibilityUtil.isServiceEnabled();
        if (!isEnabled) {
          debugPrint("FilterService: [Main] ABORTADO: Accesibilidad OFF");
          await AccessibilityUtil.openSettings();
          await _notifyToggleResult(false);
          return;
        }
      } catch (e) {
        debugPrint("FilterService: [Main] Error verificando accesibilidad: $e");
        await _notifyToggleResult(false);
        return;
      }

      bool isValid = await isSessionValid();
      if (!isValid) {
        debugPrint("FilterService: [Main] ABORTADO: Sesión inválida");
        await _notifyToggleResult(false);
        return;
      }
    }

    // Actualización de estado REAL
    isBotActiveNotifier.value = active;
    await syncWithNative(active, isProxy: false);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBotActive, active);

    // DIFUSIÓN TOTAL
    await _notifyToggleResult(active);
  }

  Future<void> _notifyToggleResult(bool active) async {
    final String event = active ? 'bot_activated' : 'bot_deactivated';
    
    // 1. Notificar a listeners del Isolate actual (Main)
    if (!_overlayEventController.isClosed) {
      _overlayEventController.add(event);
    }

    // 2. Forzar actualización del notifier local del Isolate actual
    isBotActiveNotifier.value = active;

    // 3. Notificar al otro engine (Overlay) — siempre intentar, sin guard de isActive
    try {
      debugPrint("FilterService: [Main] Emitiendo evento GLOBAL -> $event");
      await FlutterOverlayWindow.shareData(event);
    } catch (e) {
      debugPrint("FilterService: Error enviando shareData: $e");
    }
  }
}
