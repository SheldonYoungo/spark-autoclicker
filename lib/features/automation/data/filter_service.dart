import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:ui';
import 'dart:isolate';
import '../domain/filter_model.dart';
import '../../../core/utils/accessibility_util.dart';
import '../../../core/network/ntp_service.dart';
import '../../admin/data/admin_service.dart';

class FilterService {
  static const String _storageKey = 'bot_filters_config';
  static const String _keyBotActive = 'is_bot_active_state';
  static const String _keyExpiration = 'auth_expiration_ts';
  static const String _keyStatus = 'auth_status';
  
  static final FilterService _instance = FilterService._internal();
  factory FilterService() => _instance;
  FilterService._internal();

  static bool isMainIsolate = false;

  final ValueNotifier<BotFilters> filtersNotifier = ValueNotifier<BotFilters>(BotFilters());
  final ValueNotifier<bool> isBotActiveNotifier = ValueNotifier<bool>(false);
  bool _isInitialized = false;

  static final StreamController<dynamic> _overlayEventController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get overlayEvents => _overlayEventController.stream;

  static const String _portName = 'spark_isolate_port';
  ReceivePort? _receivePort;
  static bool _listenerRegistered = false;

  void _initOverlayListener() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;

    // Escuchar FlutterOverlayWindow (por si acaso)
    FlutterOverlayWindow.overlayListener.listen(_handleIncomingMessage);

    // Configurar IsolateNameServer para comunicación ultra-rápida entre Isolates
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName + (isMainIsolate ? '_main' : '_overlay'));
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, _portName + (isMainIsolate ? '_main' : '_overlay'));
    
    _receivePort!.listen(_handleIncomingMessage);
  }

  Future<void> _handleIncomingMessage(dynamic message) async {
    dynamic decodedEvent = message;
    if (message is String) {
      final trimmed = message.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try { decodedEvent = jsonDecode(trimmed); } catch (_) {}
      }
    }

    // Procesar eventos de sincronización
    if (decodedEvent is String) {
      processNativeEvent(decodedEvent);
    } else if (decodedEvent is Map) {
      if (decodedEvent['type'] == 'refresh_filters') {
        await loadFilters(forceReload: true);
      } else if (decodedEvent['type'] == 'toggle_request') {
        if (isMainIsolate) {
          await toggleBot(decodedEvent['active']);
        }
      }
    }
    
    if (!_overlayEventController.isClosed) {
      _overlayEventController.add(decodedEvent);
    }
  }

  Future<void> _sendToOtherIsolate(dynamic message) async {
    // Enviar vía plugin
    if (message is String) {
      await FlutterOverlayWindow.shareData(message);
    }

    // Enviar vía SendPort (infalible entre Isolates activos)
    final targetPortName = _portName + (isMainIsolate ? '_overlay' : '_main');
    final sendPort = IsolateNameServer.lookupPortByName(targetPortName);
    sendPort?.send(message);
  }

  /// Procesa eventos provenientes del motor nativo o de otros isolates
  void processNativeEvent(String event) {
    final isolateName = isMainIsolate ? 'Main' : 'Overlay';
    debugPrint("FilterService: [$isolateName] processNativeEvent -> $event");
    
    if (event == 'STATUS:ACTIVE' || event == 'bot_activated') {
      debugPrint("FilterService: [$isolateName] 🟢 Detectada ACTIVACIÓN. Notifier actual: ${isBotActiveNotifier.value}");
      if (isBotActiveNotifier.value != true) {
        isBotActiveNotifier.value = true;
      }
    } else if (event == 'STATUS:INACTIVE' || event == 'bot_deactivated') {
      debugPrint("FilterService: [$isolateName] 🔴 Detectada DESACTIVACIÓN. Notifier actual: ${isBotActiveNotifier.value}");
      if (isBotActiveNotifier.value != false) {
        isBotActiveNotifier.value = false;
      }
    } else if (event == 'refresh_filters') {
      debugPrint("FilterService: [$isolateName] 🔄 Solicitud de refresco de filtros");
      loadFilters(forceReload: true);
    }
  }

  Future<BotFilters> loadFilters({bool forceReload = false}) async {
    if (!_isInitialized) _initOverlayListener();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (forceReload) await prefs.reload();
      
      isBotActiveNotifier.value = prefs.getBool(_keyBotActive) ?? false;

      // Verificación de salud: Sincronizar con el estado REAL del motor nativo (si es el isolate principal)
      if (isMainIsolate) {
        final bool realStatus = await AccessibilityUtil.getBotStatus();
        if (realStatus != isBotActiveNotifier.value) {
          debugPrint("FilterService: [Main] Desajuste detectado. Prefs=${isBotActiveNotifier.value}, Motor=$realStatus. Corrigiendo...");
          isBotActiveNotifier.value = realStatus;
          await prefs.setBool(_keyBotActive, realStatus);
        }
      }

      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        filtersNotifier.value = BotFilters.fromJson(jsonDecode(jsonStr));
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
      
      bool isAdmin = prefs.getBool('is_admin_device') ?? false;
      
      if (isMainIsolate && !isAdmin) {
        isAdmin = await AdminService().isCurrentDeviceAdmin();
      }
      
      if (isAdmin) return true;

      final int? expirationTs = prefs.getInt(_keyExpiration);
      if (expirationTs == null || prefs.getString(_keyStatus) != 'active') return false;
      final DateTime networkTime = await NtpService.getNetworkTime();
      return networkTime.isBefore(DateTime.fromMillisecondsSinceEpoch(expirationTs));
    } catch (e) { return false; }
  }

  Future<void> saveFilters(BotFilters newFilters) async {
    try {
      filtersNotifier.value = newFilters;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(newFilters.toJson()));
      
      // Notificar a otros isolates
      await _sendToOtherIsolate({'type': 'refresh_filters'});
    } catch (e) {
      debugPrint("FilterService: Error en saveFilters: $e");
    }
  }

  Future<void> toggleBot(bool active) async {
    debugPrint("FilterService: [${isMainIsolate ? 'Main' : 'Overlay'}] toggleBot($active)");

    // Si somos el Overlay, intentamos delegar la acción al Main Isolate (que tiene Firebase y caché fresca)
    if (!isMainIsolate) {
      final mainPort = IsolateNameServer.lookupPortByName(_portName + '_main');
      if (mainPort != null) {
        debugPrint("FilterService: Delegando toggleBot al Main Isolate...");
        mainPort.send({'type': 'toggle_request', 'active': active});
        return;
      }
      debugPrint("FilterService: Main Isolate no disponible, fallback local.");
    }

    if (active) {
      // Verificaciones de seguridad antes de permitir el encendido
      if (isMainIsolate) {
        bool isEnabled = await AccessibilityUtil.isServiceEnabled();
        if (!isEnabled) {
          await AccessibilityUtil.openSettings();
          return;
        }
      }
      
      bool isValid = await isSessionValid();
      if (!isValid) {
        debugPrint("FilterService: Sesión inválida, abortando toggle.");
        return;
      }
    }

    // Persistencia inmediata. El motor nativo detectará el cambio vía FileObserver/Listener.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBotActive, active);
    
    // Forzar actualización local y global
    isBotActiveNotifier.value = active;
    await _sendToOtherIsolate(active ? 'bot_activated' : 'bot_deactivated');
  }

  // Legacy/Helper - El motor nativo ahora se auto-sincroniza vía SharedPreferences
  Future<void> syncWithNative(bool active) async {
    if (isMainIsolate) {
      final filters = filtersNotifier.value;
      await AccessibilityUtil.updateBotConfiguration(
        isActive: active,
        minPrice: filters.minPay,
        maxDistance: filters.maxDistance,
        storeId: filters.storeCode ?? "",
        orderType: filters.orderTypes.isEmpty ? "Any" : filters.orderTypes.join(","),
        scanSpeed: filters.scanSpeed,
      );
    }
  }
}
