import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../../admin/domain/user_model.dart';

class ActivationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

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

      return null; // Éxito
    } catch (e) {
      return 'Error durante la activación: $e';
    }
  }

  /// Validar una llave de activación buscando en todos los usuarios (para conductores sin login previo)
  Future<String?> activateDeviceWithKeyOnly(String key, String deviceId) async {
    // Si meten el código especial de admin, no buscamos en usuarios para evitar errores de permisos
    if (key == '9999') {
      return 'Acceso administrativo requerido.';
    }

    try {
      final snapshot = await _db.ref('users').get();
      if (!snapshot.exists) return 'Sistema no inicializado.';

      final usersMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
      String? targetUserId;
      UserModel? targetUser;

      // Buscar el usuario que tiene esta llave
      for (var entry in usersMap.entries) {
        final userData = Map<String, dynamic>.from(entry.value as Map);
        
        // Solo verificamos si tiene llave generada
        if (userData['activationKey'] == key) {
          targetUserId = entry.key.toString();
          targetUser = UserModel.fromJson(userData);
          break;
        }
      }

      if (targetUser == null) {
        return 'La llave de activación es incorrecta o ya fue usada.';
      }

      // Validar expiración
      if (DateTime.now().isAfter(targetUser.expirationDate)) {
        return 'Tu suscripción ha expirado. Contacta al administrador.';
      }

      // Validar slots
      if (targetUser.authorizedDeviceIds.contains(deviceId)) {
        await _db.ref('users/$targetUserId').update({'status': UserStatus.active.name});
        return null; // Ya vinculado
      }

      if (!targetUser.hasAvailableSlots) {
        return 'Límite de dispositivos alcanzado para esta llave.';
      }

      // Vincular
      final updatedDeviceIds = List<String>.from(targetUser.authorizedDeviceIds)..add(deviceId);
      await _db.ref('users/$targetUserId').update({
        'authorizedDeviceIds': updatedDeviceIds,
        'status': UserStatus.active.name,
        'activationKey': null, // Quemar llave
      });

      return null;
    } catch (e) {
      // Capturamos cualquier error (permisos, red, inexistencia) y devolvemos un mensaje amigable.
      return 'Llave inválida o expirada.';
    }
  }

  /// Verificar si este dispositivo está autorizado por algún CONDUCTOR (ignora admins)
  Future<bool> isCurrentDeviceAuthorized() async {
    try {
      final deviceId = await getDeviceId();
      final snapshot = await _db.ref('users').get();
      if (!snapshot.exists) return false;

      final usersMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
      for (var entry in usersMap.entries) {
        final userData = Map<String, dynamic>.from(entry.value as Map);
        final user = UserModel.fromJson(userData);
        
        // SOLO AUTORIZAMOS SI ES CONDUCTOR. 
        // Si el admin está en la lista pero cerró sesión, no debe entrar por hardware.
        if (user.role == UserRole.driver && user.authorizedDeviceIds.contains(deviceId) && user.isActive) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
