import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../domain/user_model.dart';
import 'admin_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final AdminService _adminService = AdminService();

  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String) onCodeSent,
    required Function(FirebaseAuthException) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (e) => onError(e),
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// Proceso de Login por SMS para Administrador y Chofer.
  Future<UserModel?> signInWithSms({
    required String verificationId,
    required String smsCode,
    bool isAdminRequest = false,
  }) async {
    try {
      final AuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      // 1. Manejo de Bootstrap de Administrador
      if (isAdminRequest) {
        final alreadyHasAdmin = await _adminService.hasAdmin();
        if (!alreadyHasAdmin) {
          // Es el primer arranque: Creamos al dueño antes de que las reglas se cierren
          await _adminService.promoteToAdmin(
            uid: user.uid,
            phone: user.phoneNumber ?? '',
            name: 'Administrador Principal',
          );
        }
      }

      // 2. Obtener datos del usuario (Sea admin o chofer vinculado)
      final snapshot = await _db.ref('users/${user.uid}').get();

      if (snapshot.exists) {
        return UserModel.fromJson(Map<String, dynamic>.from(snapshot.value as Map));
      } else {
        // Si no existe por UID, buscamos si Sheldon lo registró por teléfono (Chofer nuevo)
        final phoneId = (user.phoneNumber ?? '').replaceAll('+', '').replaceAll('.', '_');
        final phoneSnapshot = await _db.ref('users/$phoneId').get();

        if (phoneSnapshot.exists) {
          // VINCULACIÓN: El chofer entra por primera vez, movemos su perfil de Teléfono -> UID
          final data = Map<String, dynamic>.from(phoneSnapshot.value as Map);
          await _db.ref('users/${user.uid}').set(data);
          await _db.ref('users/$phoneId').remove();
          return UserModel.fromJson(data);
        }

        await _auth.signOut();
        throw Exception("Este número no está autorizado. Contacta al administrador.");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Mantenemos este para compatibilidad con el flujo de llaves actual si es necesario
  Future<UserModel?> validateActivationKey(String key, String deviceId) async {
    try {
      final snapshot = await _db.ref('users').get();
      if (!snapshot.exists) return null;

      final usersMap = snapshot.value as Map<dynamic, dynamic>;
      for (var entry in usersMap.entries) {
        final userData = Map<String, dynamic>.from(entry.value as Map);
        if (userData['activationKey'] == key) {
          final user = UserModel.fromJson(userData);
          if (user.authorizedDeviceIds.contains(deviceId)) {
            return user;
          } else if (user.authorizedDeviceIds.isEmpty) {
            await _db.ref('users/${user.id}/authorizedDeviceIds').set([deviceId]);
            return user;
          } else {
            throw Exception("Dispositivo no autorizado.");
          }
        }
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }
}
