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

  Future<void> addDriver({
    required String phone,
    required String name,
    int days = 30,
  }) async {
    final tempId = phone.replaceAll('+', '').replaceAll('.', '_');
    final newUser = UserModel(
      id: tempId,
      name: name,
      role: UserRole.driver,
      status: UserStatus.pending,
      expirationDate: DateTime.now().add(Duration(days: days)),
      authorizedDeviceIds: [],
      activationKey: generateActivationKey(),
    );

    await _db.ref('users/$tempId').set(newUser.toJson());
  }
}
