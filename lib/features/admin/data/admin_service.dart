import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../../automation/data/activation_service.dart';
import '../domain/user_model.dart';
import 'package:flutter/foundation.dart';

class AdminService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  static final ValueNotifier<int> forceReloadNotifier = ValueNotifier(0);

  // Obtener flujo de usuarios en tiempo real
  Stream<List<UserModel>> getUsersStream() {
    return _db.ref('users').onValue.map((event) {
      final Map<dynamic, dynamic>? usersMap = event.snapshot.value as Map<dynamic, dynamic>?;
      if (usersMap == null) return [];
      
      return usersMap.entries.map((entry) {
        return UserModel.fromJson(Map<String, dynamic>.from(entry.value as Map));
      }).toList();
    });
  }

  /// Verifica si ya existe un administrador.
  /// RUTA PÚBLICA: 'config/has_admin' para evitar Permission Denied.
  Future<bool> hasAdmin() async {
    try {
      final snapshot = await _db.ref('config/has_admin').get();
      if (snapshot.exists) {
        return snapshot.value == true;
      }
      return false;
    } catch (e) {
      // Si falla, asumimos que las reglas ya están cerradas (y por tanto hay un admin)
      return true;
    }
  }

  /// Promover a un usuario a Administrador usando su UID.
  Future<void> promoteToAdmin({
    required String uid,
    required String phone,
    required String name,
  }) async {
    final adminUser = UserModel(
      id: uid,
      name: name,
      role: UserRole.admin,
      status: UserStatus.active,
      expirationDate: DateTime(2099, 12, 31),
      authorizedDeviceIds: [],
    );
    
    // Primero marcamos el flag global (la regla debe permitirlo si auth != null)
    await _db.ref('config/has_admin').set(true);
    // Luego creamos el perfil (la regla permite !data.exists() para el usuario logueado)
    await _db.ref('users/$uid').set(adminUser.toJson());
  }

  Future<void> updateUserStatus(String uid, UserStatus status) async {
    await _db.ref('users/$uid').update({
      'status': status.name,
    });
  }

  Future<void> addAdminDevice(String uid, String deviceId) async {
    final snapshot = await _db.ref('users/$uid/authorizedDeviceIds').get();
    List<String> devices = [];
    if (snapshot.exists && snapshot.value != null) {
      final value = snapshot.value;
      if (value is List) {
        devices = List<String>.from(value);
      }
    }
    if (!devices.contains(deviceId)) {
      devices.add(deviceId);
      await _db.ref('users/$uid/authorizedDeviceIds').set(devices);
    }
    
    // Registrar también en un nodo global de configuración para el bypass sin sesión (Zero Cost)
    await _db.ref('config/admin_devices/$deviceId').set(true);
  }

  Future<bool> isCurrentDeviceAdmin() async {
    try {
      final auth = FirebaseAuth.instance;
      final deviceId = await ActivationService().getDeviceId();
      
      final prefs = await SharedPreferences.getInstance();
      final isRevoked = prefs.getBool('bypass_revoked') ?? false;
      
      // Chequeo 1: Vía Auth Directo (Si acaba de iniciar sesión con OTP)
      if (auth.currentUser != null && !auth.currentUser!.isAnonymous) {
        final uid = auth.currentUser!.uid;
        final snapshot = await _db.ref('users/$uid/role').get();
        if (snapshot.exists && snapshot.value?.toString() == 'admin') {
          return true;
        }
      }

      // Chequeo 2: Vía Hardware ID Bypass (Si borró caché o desinstaló, usamos login anónimo y consultamos config)
      if (isRevoked) {
        return false; // El usuario cerró sesión explícitamente en este dispositivo
      }

      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }
      
      final deviceSnapshot = await _db.ref('config/admin_devices/$deviceId').get();
      if (deviceSnapshot.exists && deviceSnapshot.value == true) {
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint("isCurrentDeviceAdmin error: $e");
      return false;
    }
  }

  String generateActivationKey() {
    return (1000 + Random().nextInt(9000)).toString();
  }

  /// Obtener las horas de servicio por defecto (4 horas)
  Future<int> getDefaultHours() async {
    final snapshot = await _db.ref('config/default_driver_hours').get();
    if (snapshot.exists) {
      return (snapshot.value as num).toInt();
    }
    return 4;
  }

  /// Establecer las horas de servicio por defecto globalmente
  Future<void> setDefaultHours(int hours) async {
    await _db.ref('config/default_driver_hours').set(hours);
  }

  /// Registrar un nuevo conductor con horas personalizadas o por defecto
  Future<void> addDriver({
    required String phone,
    required String name,
    int? customHours,
    int maxSlots = 1,
  }) async {
    final int hours = customHours ?? await getDefaultHours();
    final tempId = phone.replaceAll('+', '').replaceAll('.', '_');
    final String key = generateActivationKey();
    
    final newUser = UserModel(
      id: tempId,
      name: name,
      role: UserRole.driver,
      status: UserStatus.pending,
      expirationDate: DateTime.now().add(Duration(hours: hours)),
      authorizedDeviceIds: [],
      maxSlots: maxSlots,
      activationKey: key,
    );

    // Guardar usuario
    await _db.ref('users/$tempId').set(newUser.toJson());
    // Registrar llave para búsqueda rápida
    await _db.ref('activation_keys/$key').set({'uid': tempId});
  }

  /// Renovar el servicio de un conductor: genera nueva llave y extiende tiempo desde ahora.
  /// También permite al admin decidir si limpia los Device IDs vinculados (Reset de Hardware).
  Future<void> renewDriver(String uid, {int? customHours, bool resetHardware = false}) async {
    final int hours = customHours ?? await getDefaultHours();
    final String newKey = generateActivationKey();
    
    // 1. Limpiar llave anterior si existe en el nodo de búsqueda rápida
    final oldKeySnapshot = await _db.ref('users/$uid/activationKey').get();
    if (oldKeySnapshot.exists) {
      await _db.ref('activation_keys/${oldKeySnapshot.value}').remove();
    }

    final Map<String, dynamic> updates = {
      'expirationDate': DateTime.now().add(Duration(hours: hours)).toIso8601String(),
      'activationKey': newKey,
      'status': UserStatus.pending.name,
    };

    if (resetHardware) {
      updates['authorizedDeviceIds'] = [];
    }
    
    // 2. Actualizar usuario
    await _db.ref('users/$uid').update(updates);
    // 3. Registrar nueva llave
    await _db.ref('activation_keys/$newKey').set({'uid': uid});
  }

  /// Resetear manualmente los dispositivos vinculados de un usuario
  Future<void> resetHardware(String uid) async {
    // Al resetear hardware, el status vuelve a pending para forzar re-activación
    await _db.ref('users/$uid').update({
      'authorizedDeviceIds': [],
      'status': UserStatus.pending.name,
    });
  }

  /// Actualizar la cantidad de slots permitidos para un usuario
  Future<void> updateMaxSlots(String uid, int maxSlots) async {
    await _db.ref('users/$uid').update({
      'maxSlots': maxSlots,
    });
  }

  /// Eliminar un usuario (conductor) de la base de datos
  Future<void> deleteUser(String uid) async {
    // Limpiar llave en activation_keys antes de borrar al usuario
    final keySnapshot = await _db.ref('users/$uid/activationKey').get();
    if (keySnapshot.exists) {
      await _db.ref('activation_keys/${keySnapshot.value}').remove();
    }
    await _db.ref('users/$uid').remove();
  }
}
