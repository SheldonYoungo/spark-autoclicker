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
  static const String _keyExpiration = 'auth_expiration_ts';
  static const String _keyStatus = 'auth_status';

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
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    }
    return 'unknown_platform';
  }

  /// Persiste datos de autenticación localmente para el Overlay Isolate
  Future<void> _saveAuthDataLocally(UserModel user, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLinkedUid, uid);
    await prefs.setInt(_keyExpiration, user.expirationDate.millisecondsSinceEpoch);
    await prefs.setString(_keyStatus, user.status.name);
    linkedUidNotifier.value = uid;
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
        if (user.status == UserStatus.pending) {
          await _db.ref('users/$uid').update({'status': UserStatus.active.name});
        }
        await _saveAuthDataLocally(user, uid);
        return null;
      }

      if (!user.hasAvailableSlots) {
        return 'Has alcanzado el límite de dispositivos (${user.maxSlots}).';
      }

      // 4. Vincular nuevo dispositivo
      final updatedDeviceIds = List<String>.from(user.authorizedDeviceIds)..add(currentDeviceId);
      
      await _db.ref('users/$uid').update({
        'authorizedDeviceIds': updatedDeviceIds,
        'status': UserStatus.active.name,
        'activationKey': null,
      });

      await _saveAuthDataLocally(user, uid);
      return null;
    } catch (e) {
      return 'Error durante la activación: $e';
    }
  }

  /// Validar una llave de activación buscando directamente en el nodo público (O(1))
  Future<String?> activateDeviceWithKeyOnly(String key, String deviceId) async {
    if (key == '9999') return 'Acceso administrativo requerido.';

    try {
      final keySnapshot = await _db.ref('activation_keys/$key').get().timeout(const Duration(seconds: 10));
      if (!keySnapshot.exists) return 'La llave es incorrecta o ya fue usada.';

      final keyData = Map<String, dynamic>.from(keySnapshot.value as Map);
      final String uid = keyData['uid'];

      final userSnapshot = await _db.ref('users/$uid').get().timeout(const Duration(seconds: 10));
      if (!userSnapshot.exists) return 'Error interno: Usuario no encontrado.';

      final user = UserModel.fromJson(Map<String, dynamic>.from(userSnapshot.value as Map));

      if (DateTime.now().isAfter(user.expirationDate)) {
        return 'Tu suscripción ha expirado. Contacta al administrador.';
      }

      List<String> updatedDeviceIds = List<String>.from(user.authorizedDeviceIds);
      if (!updatedDeviceIds.contains(deviceId)) {
        if (!user.hasAvailableSlots) return 'Has alcanzado el límite de dispositivos (${user.maxSlots}).';
        updatedDeviceIds.add(deviceId);
      }

      await _db.ref('users/$uid').update({
        'status': UserStatus.active.name,
        'authorizedDeviceIds': updatedDeviceIds,
      });

      await _saveAuthDataLocally(user, uid);
      return null;
    } catch (e) {
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
      final snapshot = await _db.ref('users/$uid').get().timeout(const Duration(seconds: 5));
      if (!snapshot.exists) return false;

      final user = UserModel.fromJson(Map<String, dynamic>.from(snapshot.value as Map));
      
      final isValid = user.role == UserRole.driver && 
             user.authorizedDeviceIds.contains(deviceId) && 
             user.isActive &&
             !DateTime.now().isAfter(user.expirationDate);

      if (!isValid) {
        await clearLocalLink();
      } else {
        await _saveAuthDataLocally(user, uid);
      }
      
      return isValid;
    } catch (e) {
      debugPrint("Error validando hardware: $e");
      return false;
    }
  }

  /// Escuchar cambios en tiempo real para el estado de autenticación del chofer
  Stream<bool> authStateStream(String uid) async* {
    final deviceId = await getDeviceId();
    
    yield* _db.ref('users/$uid').onValue.map((event) {
      if (!event.snapshot.exists) return false;
      
      try {
        final user = UserModel.fromJson(Map<String, dynamic>.from(event.snapshot.value as Map));
        final isValid = user.role == UserRole.driver && 
               user.authorizedDeviceIds.contains(deviceId) && 
               user.isActive &&
               !DateTime.now().isAfter(user.expirationDate);

        if (!isValid) {
          clearLocalLink();
        } else {
          _saveAuthDataLocally(user, uid);
        }
        return isValid;
      } catch (e) {
        return false;
      }
    });
  }

  /// Cerrar sesión local
  Future<void> clearLocalLink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLinkedUid);
    await prefs.remove(_keyExpiration);
    await prefs.remove(_keyStatus);
    linkedUidNotifier.value = null;
  }
}
