import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../admin/domain/user_model.dart';

class ActivationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static const String _keyLinkedUid = 'linked_uid';

  /// Notificador para que la UI reaccione a cambios de activación en tiempo real
  static final ValueNotifier<String?> linkedUidNotifier = ValueNotifier<String?>(null);

  /// Cargar el estado inicial de activación
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    linkedUidNotifier.value = prefs.getString(_keyLinkedUid);
  }

  /// Obtener el ID único del dispositivo actual
  Future<String> getDeviceId() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return androidInfo.id; // En Android, 'id' es confiable para hardware
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    }
    return 'unknown_platform';
  }

  /// Validar una llave de activación y vincular el dispositivo si hay slots disponibles
  Future<String?> activateKey(String uid, String key) async {
    try {
      final snapshot = await _db.ref('users/$uid').get();
      if (!snapshot.exists) return 'Usuario no encontrado.';

      final user = UserModel.fromJson(Map<String, dynamic>.from(snapshot.value as Map));
      
      // 1. Validar llave
      if (user.activationKey != key) {
        return 'La llave de activación es incorrecta.';
      }

      // 2. Validar expiración
      if (DateTime.now().isAfter(user.expirationDate)) {
        return 'Tu suscripción ha expirado. Contacta al administrador.';
      }

      // 3. Validar slots
      final currentDeviceId = await getDeviceId();
      if (user.authorizedDeviceIds.contains(currentDeviceId)) {
        // Ya está vinculado, solo activamos el status si estaba pendiente
        if (user.status == UserStatus.pending) {
          await _db.ref('users/$uid').update({'status': UserStatus.active.name});
        }
        // Guardar localmente para acceso rápido
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLinkedUid, uid);
        return null; // Éxito (ya vinculado)
      }

      if (!user.hasAvailableSlots) {
        return 'Has alcanzado el límite de dispositivos (${user.maxSlots}).';
      }

      // 4. Vincular nuevo dispositivo
      final updatedDeviceIds = List<String>.from(user.authorizedDeviceIds)..add(currentDeviceId);
      
      await _db.ref('users/$uid').update({
        'authorizedDeviceIds': updatedDeviceIds,
        'status': UserStatus.active.name,
        'activationKey': null, // Quemamos la llave tras el primer uso exitoso en este dispositivo
      });

      // Guardar localmente para acceso rápido
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLinkedUid, uid);

      return null; // Éxito
    } catch (e) {
      return 'Error durante la activación: $e';
    }
  }

  /// Validar una llave de activación buscando directamente en el nodo público (O(1))
  Future<String?> activateDeviceWithKeyOnly(String key, String deviceId) async {
    if (key == '9999') {
      return 'Acceso administrativo requerido.';
    }

    try {
      // 1. Buscar la llave en el nodo público con timeout
      final keySnapshot = await _db.ref('activation_keys/$key').get().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Tiempo de espera agotado al buscar la llave.'),
      );

      if (!keySnapshot.exists) {
        return 'La llave es incorrecta o ya fue usada.';
      }

      final keyData = Map<String, dynamic>.from(keySnapshot.value as Map);
      final String uid = keyData['uid'];

      // 2. Obtener datos completos del usuario
      final userSnapshot = await _db.ref('users/$uid').get().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Tiempo de espera agotado al conectar con el servidor.'),
      );

      if (!userSnapshot.exists) return 'Error interno: Usuario no encontrado.';

      final user = UserModel.fromJson(Map<String, dynamic>.from(userSnapshot.value as Map));

      // 3. Validar expiración
      if (DateTime.now().isAfter(user.expirationDate)) {
        return 'Tu suscripción ha expirado. Contacta al administrador.';
      }

      // 4. Validar slots
      List<String> updatedDeviceIds = List<String>.from(user.authorizedDeviceIds);
      if (!updatedDeviceIds.contains(deviceId)) {
        if (!user.hasAvailableSlots) {
          return 'Has alcanzado el límite de dispositivos (${user.maxSlots}).';
        }
        updatedDeviceIds.add(deviceId);
      }

      // 5. Activar Usuario en RTDB
      await _db.ref('users/$uid').update({
        'status': UserStatus.active.name,
        'authorizedDeviceIds': updatedDeviceIds,
        'activationKey': null, 
      });

      // 6. Guardar localmente
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLinkedUid, uid);
      linkedUidNotifier.value = uid; // Notificar a la UI del cambio de estado

      // 7. Limpiar la llave (Opcional, si falla no bloqueamos al usuario)
      _db.ref('activation_keys/$key').remove().catchError((_) => null);

      return null;
    } catch (e) {
      if (e.toString().contains('Permission denied')) {
        return 'Error de seguridad (Firebase): Verifica las reglas.';
      }
      return 'Error: ${e.toString().split(':').last.trim()}';
    }
  }

  /// Verificar si este dispositivo está autorizado de forma eficiente
  Future<bool> isCurrentDeviceAuthorized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_keyLinkedUid);
      
      if (uid == null) return false;

      final deviceId = await getDeviceId();
      final snapshot = await _db.ref('users/$uid').get().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout'),
      );
      
      if (!snapshot.exists) return false;

      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      final user = UserModel.fromJson(userData);
      
      return user.role == UserRole.driver && 
             user.authorizedDeviceIds.contains(deviceId) && 
             user.isActive;
    } catch (e) {
      debugPrint("Error validando hardware: $e");
      return false;
    }
  }

  /// Cerrar sesión local (limpiar vinculación de hardware local)
  Future<void> clearLocalLink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLinkedUid);
  }
}
