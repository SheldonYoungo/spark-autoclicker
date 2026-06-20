import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
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
  
  Timer? _reloadDebounce;

  void _initOverlayListener() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;

    FlutterOverlayWindow.overlayListener.listen(_handleIncomingMessage);

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
    if (message is String) {
      FlutterOverlayWindow.shareData(message);
    }

    final targetPortName = _portName + (isMainIsolate ? '_overlay' : '_main');
    final sendPort = IsolateNameServer.lookupPortByName(targetPortName);
    sendPort?.send(message);
  }

  void processNativeEvent(String event) {
    final isolateName = isMainIsolate ? 'Main' : 'Overlay';
    debugPrint("FilterService: [$isolateName] processNativeEvent -> $event");
    
    if (event == 'STATUS:ACTIVE' || event == 'bot_activated') {
      debugPrint("FilterService: [$isolateName] 🟢 Detectada ACTIVACIÓN. Notifier actual: ${isBotActiveNotifier.value}");
      if (isBotActiveNotifier.value != true) {
        isBotActiveNotifier.value = true;
        if (isMainIsolate) _sendToOtherIsolate('STATUS:ACTIVE');
      }
    } else if (event == 'STATUS:INACTIVE' || event == 'bot_deactivated') {
      debugPrint("FilterService: [$isolateName] 🔴 Detectada DESACTIVACIÓN. Notifier actual: ${isBotActiveNotifier.value}");
      if (isBotActiveNotifier.value != false) {
        isBotActiveNotifier.value = false;
        if (isMainIsolate) _sendToOtherIsolate('STATUS:INACTIVE');
      }
    } else if (event == 'refresh_filters') {
      debugPrint("FilterService: [$isolateName] 🔄 Solicitud de refresco de filtros (Debounced)");
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
        loadFilters(forceReload: true);
      });
    }
  }

  Future<BotFilters> loadFilters({bool forceReload = false}) async {
    if (!_isInitialized) _initOverlayListener();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (forceReload) await prefs.reload();
      
      // CRÍTICO: Solo leer el estado del bot en la carga INICIAL.
      // Nunca sobrescribir si el bot ya está activo (previene lecturas stale
      // de SharedPreferences que causan autodesactivación tras clics).
      if (!_isInitialized) {
        isBotActiveNotifier.value = prefs.getBool(_keyBotActive) ?? false;
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
      final int? expirationTs = prefs.getInt(_keyExpiration);
      final bool hasActiveDriverSession = expirationTs != null && prefs.getString(_keyStatus) == 'active';
      
      if (isAdmin) return true;
      
      if (isMainIsolate && !hasActiveDriverSession) {
        isAdmin = await AdminService().isCurrentDeviceAdmin();
        if (isAdmin) return true;
      }
      
      if (!hasActiveDriverSession) return false;
      
      DateTime now;
      try {
        debugPrint("FilterService: [${isMainIsolate ? 'Main' : 'Overlay'}] Obteniendo tiempo de red...");
        now = await NtpService.getNetworkTime();
      } catch (e) {
        // Fallback: si NTP falla (datos móviles lentos o sin internet), usar hora local como contingencia
        debugPrint("FilterService: NTP falló ($e). Usando hora local como fallback.");
        now = DateTime.now();
      }
      
      return now.isBefore(DateTime.fromMillisecondsSinceEpoch(expirationTs!));
    } catch (e) { return false; }
  }

  Future<void> saveFilters(BotFilters newFilters) async {
    try {
      filtersNotifier.value = newFilters;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(newFilters.toJson()));
      
      await prefs.setDouble('minPay', newFilters.minPay);
      await prefs.setDouble('maxDistance', newFilters.maxDistance);
      
      if (isMainIsolate) {
        // Si el bot está activo, empujar los nuevos filtros inmediatamente al motor nativo
        if (isBotActiveNotifier.value) {
          await syncWithNative(true);
        }
      }

      // Notificar a otros isolates
      await _sendToOtherIsolate({'type': 'refresh_filters'});
    } catch (e) {
      debugPrint("FilterService: Error en saveFilters: $e");
    }
  }

  Future<void> toggleBot(bool active) async {
    debugPrint("FilterService: [${isMainIsolate ? 'Main' : 'Overlay'}] toggleBot($active)");

    if (active) {
      if (filtersNotifier.value.storeCode == null || filtersNotifier.value.storeCode!.isEmpty) {
        debugPrint("FilterService: Tienda no configurada, abortando toggle.");
        return;
      }

      if (isMainIsolate) {
        bool isEnabled = await AccessibilityUtil.isServiceEnabled();
        if (!isEnabled) {
          await AccessibilityUtil.openSettings();
          return;
        }
        bool isValid = await isSessionValid();
        if (!isValid) {
          debugPrint("FilterService: Sesión inválida, abortando toggle.");
          return;
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBotActive, active);
    
    isBotActiveNotifier.value = active;

    if (!isMainIsolate) {
      final mainPort = IsolateNameServer.lookupPortByName(_portName + '_main');
      if (mainPort != null) {
        debugPrint("FilterService: Delegando toggleBot al Main Isolate...");
        mainPort.send({'type': 'toggle_request', 'active': active});
      }
    } else {
      // Sincronización explícita con el motor nativo
      await syncWithNative(active);
    }
    
    await _sendToOtherIsolate(active ? 'bot_activated' : 'bot_deactivated');
  }

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
