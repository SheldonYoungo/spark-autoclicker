import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class AccessibilityUtil {
  static const MethodChannel _channel = MethodChannel('com.spark.autoclicker/core');
  static bool _isListening = false;

  static Function(String)? _onNativeLog;

  /// Inicia la escucha de logs nativos
  static void initNativeLogger([Function(String)? onLog]) {
    _onNativeLog = onLog;
    if (_isListening) return;
    _isListening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nativeLog') {
        final message = call.arguments.toString();
        debugPrint("🤖 KOTLIN MOTOR: $message");
        _onNativeLog?.call(message);
      }
    });
  }

  /// Verifica si el servicio de accesibilidad está activado
  static Future<bool> isServiceEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('isServiceEnabled');
      return enabled;
    } catch (e) {
      debugPrint("Error verificando servicio de accesibilidad: $e");
      return false;
    }
  }

  /// Abre la pantalla de configuración de accesibilidad de Android
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (e) {
      debugPrint("Error abriendo configuración: $e");
    }
  }

  /// Sincroniza el estado del bot y los filtros con el motor nativo
  static Future<void> updateBotConfiguration({
    required bool isActive,
    required double minPrice,
    required double maxDistance,
    required String storeId,
    required String orderType,
  }) async {
    try {
      await _channel.invokeMethod('updateBotConfiguration', {
        'isActive': isActive,
        'minPrice': minPrice,
        'maxDistance': maxDistance,
        'storeId': storeId,
        'orderType': orderType,
      });
      debugPrint("Configuración del bot sincronizada: Active=$isActive, Price=$minPrice");
    } catch (e) {
      debugPrint("Error sincronizando configuración del bot: $e");
    }
  }
}
