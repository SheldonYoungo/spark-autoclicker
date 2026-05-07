import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseDiagnostics {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<Map<String, dynamic>> checkHealth() async {
    final Map<String, dynamic> report = {
      'timestamp': DateTime.now().toIso8601String(),
      'auth_status': 'unknown',
      'database_read': 'pending',
      'database_write': 'pending',
      'error': null,
    };

    try {
      // 1. Estado de Auth (Informativo)
      final user = _auth.currentUser;
      report['auth_status'] = user != null ? 'User: ${user.uid}' : 'No User Logged In';

      // 2. Probar lectura de una ruta estática (Sin variables, sin tokens raros)
      // Usamos 'health_check' que es una palabra simple sin caracteres especiales.
      await _db.ref('health_check').get();
      report['database_read'] = 'Success';

      // 3. Probar escritura en una ruta estática
      await _db.ref('health_check').set({
        'last_ping': ServerValue.timestamp,
        'status': 'ok'
      });
      report['database_write'] = 'Success';

    } on FirebaseException catch (e) {
      report['error'] = 'Firebase Error: ${e.code} - ${e.message}';
    } catch (e) {
      // Este es el catch que está atrapando la excepción de Java
      report['error'] = 'Java/Native Error: $e';
    }

    return report;
  }
}
