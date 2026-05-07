import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import '../domain/user_model.dart';

class AdminService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

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
  }) async {
    final int hours = customHours ?? await getDefaultHours();
    final tempId = phone.replaceAll('+', '').replaceAll('.', '_');
    
    final newUser = UserModel(
      id: tempId,
      name: name,
      role: UserRole.driver,
      status: UserStatus.pending,
      expirationDate: DateTime.now().add(Duration(hours: hours)),
      authorizedDeviceIds: [],
      activationKey: generateActivationKey(),
    );

    await _db.ref('users/$tempId').set(newUser.toJson());
  }

  /// Renovar el servicio de un conductor: genera nueva llave y extiende tiempo desde ahora
  Future<void> renewDriver(String uid, {int? customHours}) async {
    final int hours = customHours ?? await getDefaultHours();
    final String newKey = generateActivationKey();
    
    await _db.ref('users/$uid').update({
      'expirationDate': DateTime.now().add(Duration(hours: hours)).toIso8601String(),
      'activationKey': newKey,
      'status': UserStatus.pending.name, // Vuelve a pedir activación/vínculo si expiró
    });
  }

  /// Eliminar un usuario (conductor) de la base de datos
  Future<void> deleteUser(String uid) async {
    await _db.ref('users/$uid').remove();
  }
}
