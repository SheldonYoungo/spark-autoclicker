import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../domain/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Paso 1: Enviar el código SMS
  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String) onCodeSent,
    required Function(FirebaseAuthException) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // En algunos Android, el SMS se lee solo y se loguea automáticamente
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: onError,
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // Paso 2: Validar el código que puso el usuario y ver si está en tu lista VIP
  Future<UserModel?> signInWithCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      // 1. Loguear en Firebase Auth
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final phone = userCredential.user?.phoneNumber;

      if (phone == null) return null;

      // 2. Buscar al usuario en tu base de datos (Realtime Database)
      final snapshot = await _db.ref('users/$phone').get();

      if (snapshot.exists) {
        return UserModel.fromJson(Map<String, dynamic>.from(snapshot.value as Map));
      } else {
        // El número no está registrado por Sheldon
        await _auth.signOut();
        throw Exception("Número no autorizado por el administrador.");
      }
    } catch (e) {
      rethrow;
    }
  }

  // Cerrar sesión
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
