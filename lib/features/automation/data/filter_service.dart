import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../domain/filter_model.dart';
import '../../../core/utils/accessibility_util.dart';
import '../../../core/network/ntp_service.dart';

class FilterService {
  static const String _storageKey = 'bot_filters_config';
  static const String _keyExpiration = 'auth_expiration_ts';
  static const String _keyStatus = 'auth_status';
  
  static final FilterService _instance = FilterService._internal();
  factory FilterService() => _instance;
  FilterService._internal();

  final ValueNotifier<BotFilters> filtersNotifier = ValueNotifier<BotFilters>(BotFilters());
  final ValueNotifier<bool> isBotActiveNotifier = ValueNotifier<bool>(false);
  bool _isInitialized = false;

  /// Traducciones de tipos de orden para el motor nativo (Spark App en inglés)
  static const Map<String, String> orderTypeMapping = {
    'Compras': 'Shopping',
    'Recolección': 'Pickup',
    'Devolución': 'Return',
    'Ofertas': 'Deals',
  };

  /// Inicializa o carga los filtros. Si [forceReload] es true, obliga a SharedPreferences
  /// a leer del disco (vital para sincronización entre Isolates como el Overlay).
  Future<BotFilters> loadFilters({bool forceReload = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (forceReload) await prefs.reload();
      
      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        final filters = BotFilters.fromJson(json);
        
        // La clase BotFilters garantiza minPay >= 20.0 en su constructor.
        // Si el valor en disco era menor, 'filters.minPay' ya vendrá ajustado a 20.0.
        filtersNotifier.value = filters;
        _isInitialized = true;

        // Si detectamos que el valor guardado era inferior al suelo de $20, 
        // persistimos el ajuste inmediatamente para limpiar datos obsoletos.
        final double savedMinPay = (json['minPay'] as num?)?.toDouble() ?? 0.0;
        if (savedMinPay < 20.0) {
          debugPrint("FilterService: Ajustando tarifa mínima obsoleta ($savedMinPay -> 20.0)");
          await saveFilters(filters);
        }

        return filters;
      }
    } catch (e) {
      debugPrint("FilterService Error en loadFilters: $e");
    }
    _isInitialized = true;
    return filtersNotifier.value;
  }

  /// Verifica si la suscripción sigue siendo válida usando tiempo NTP
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
      debugPrint("FilterService: Error validando sesión: $e");
      return false;
    }
  }

  /// Guarda los filtros en disco y los sincroniza si el bot está activo
  Future<void> saveFilters(BotFilters newFilters) async {
    try {
      // El constructor de BotFilters ya garantiza el suelo de $20.0, 
      // pero reforzamos la integridad aquí antes de persistir.
      final validatedFilters = newFilters.minPay < 20.0 
          ? newFilters.copyWith(minPay: 20.0)
          : newFilters;

      // Actualizar estado local inmediatamente para feedback visual
      filtersNotifier.value = validatedFilters;
      
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(validatedFilters.toJson());
      await prefs.setString(_storageKey, jsonStr);
      
      debugPrint("FilterService: Filtros guardados: $jsonStr");

      // Notificar al Overlay (Isolate secundario) si está activo
      final bool isOverlayOpen = await FlutterOverlayWindow.isActive();
      if (isOverlayOpen) {
        await FlutterOverlayWindow.shareData('refresh_filters');
      }

      if (isBotActiveNotifier.value) {
        await syncWithNative(true);
      }
    } catch (e) {
      debugPrint("FilterService Error en saveFilters: $e");
    }
  }

  /// Envía la configuración actual al motor de accesibilidad en Kotlin
  Future<void> syncWithNative(bool active) async {
    if (active) {
      final isValid = await isSessionValid();
      if (!isValid) {
        debugPrint("FilterService: Intento de activación sin suscripción válida.");
        await AccessibilityUtil.updateBotConfiguration(
          isActive: false, 
          minPrice: 0, 
          maxDistance: 0, 
          storeId: "", 
          orderType: "NONE"
        );
        return;
      }
    }

    final filters = filtersNotifier.value;
    final List<String> translatedTypes = filters.orderTypes
        .map((t) => orderTypeMapping[t] ?? t)
        .toList();
    
    // Si no hay tipos seleccionados, enviamos "Any" para que el bot acepte todo
    final String orderTypeStr = translatedTypes.isEmpty ? "Any" : translatedTypes.join(",");

    await AccessibilityUtil.updateBotConfiguration(
      isActive: active,
      minPrice: filters.minPay,
      maxDistance: filters.maxDistance,
      storeId: filters.storeCode ?? "",
      orderType: orderTypeStr,
    );
  }

  Future<void> toggleBot(bool active) async {
    isBotActiveNotifier.value = active;
    await syncWithNative(active);
  }
}
