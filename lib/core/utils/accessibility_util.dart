import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class AccessibilityUtil {
  static const MethodChannel _channel = MethodChannel('com.spark.autoclicker/core');
  static bool _isListening = false;

  static Function(String)? _onNativeLog;
  static Function(String)? _globalLogHandler;

  /// Inicia la escucha de logs nativos. 
  /// [onLog] es un listener temporal (normalmente para UI).
  /// [isGlobal] define si este listener debe persistir como el logger base.
  static void initNativeLogger(Function(String) onLog, {bool isGlobal = false}) {
    if (isGlobal) {
      _globalLogHandler = onLog;
    } else {
      _onNativeLog = onLog;
    }

    if (_isListening) return;
    _isListening = true;
    
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'nativeLog') {
        final message = call.arguments.toString();
        
        // 1. Ejecutar el handler global (si existe)
        _globalLogHandler?.call(message);
        
        // 2. Ejecutar el handler temporal (si existe)
        _onNativeLog?.call(message);
      }
    });
  }

  /// Limpia el listener temporal de logs
  static void clearNativeLogger() {
    _onNativeLog = null;
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

  /// Consulta el estado actual de activación del bot en el motor nativo
  static Future<bool> getBotStatus() async {
    try {
      final bool? status = await _channel.invokeMethod('getBotStatus');
      return status ?? false;
    } catch (e) {
      debugPrint("Error consultando estado del bot: $e");
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
    required int scanSpeed,
  }) async {
    try {
      await _channel.invokeMethod('updateBotConfiguration', {
        'isActive': isActive,
        'minPrice': minPrice,
        'maxDistance': maxDistance,
        'storeId': storeId,
        'orderType': orderType,
        'scanSpeed': scanSpeed,
      });
      debugPrint("Configuración del bot sincronizada: Active=$isActive, Price=$minPrice, Speed=$scanSpeed");
    } catch (e) {
      debugPrint("Error sincronizando configuración del bot: $e");
    }
  }

  /// Activa/desactiva el modo de prueba (escanea nuestra propia app)
  static Future<void> setTestMode(bool enabled) async {
    try {
      await _channel.invokeMethod('setTestMode', {'testMode': enabled});
      debugPrint("🧪 Modo prueba: ${enabled ? "ON" : "OFF"}");
    } catch (e) {
      debugPrint("Error cambiando modo prueba: $e");
    }
  }

  /// Verifica si la app está exenta de la optimización de batería
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final bool ignored = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      return ignored;
    } catch (e) {
      debugPrint("Error verificando optimización de batería: $e");
      return true; // Ante error, asumimos true para no bloquear
    }
  }

  /// Solicita excluir la app de la optimización de batería de Android
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final bool result = await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      return result;
    } catch (e) {
      debugPrint("Error solicitando ignorar optimización de batería: $e");
      return false;
    }
  }
}
