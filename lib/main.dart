import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';
import 'package:spark_autoclicker/features/admin/presentation/login_screen.dart';
import 'package:spark_autoclicker/features/admin/presentation/admin_dashboard.dart';
import 'package:spark_autoclicker/features/automation/presentation/bot_main_screen.dart';
import 'package:spark_autoclicker/features/automation/data/activation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: dotenv.get('FIREBASE_API_KEY'),
        appId: '1:1071477543888:android:55e638848d82137060965c',
        messagingSenderId: '1071477543888',
        projectId: dotenv.get('FIREBASE_PROJECT_ID'),
        databaseURL: dotenv.get('FIREBASE_DATABASE_URL'),
      ),
    );
  } catch (e) {
    debugPrint("Error al inicializar Firebase: $e");
  }

  runApp(const SparkApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SparkApp extends StatelessWidget {
  const SparkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Spark Autoclicker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen(message: 'Iniciando...');
        }

        final user = snapshot.data;
        
        // 1. Si hay un usuario logueado vía Firebase (ADMIN)
        if (user != null) {
          return FutureBuilder<bool>(
            future: _isUserAdmin(user.uid),
            builder: (context, adminSnapshot) {
              if (adminSnapshot.connectionState == ConnectionState.waiting) {
                return const LoadingScreen(message: 'Verificando privilegios...');
              }
              if (adminSnapshot.data == true) {
                return const AdminDashboard();
              }
              // Si no es admin pero está logueado, lo tratamos como login fallido
              return const LoginScreen();
            },
          );
        }

        // 2. Si no hay usuario logueado, verificamos si el dispositivo está vinculado (CONDUCTOR)
        return FutureBuilder<bool>(
          future: ActivationService().isCurrentDeviceAuthorized(),
          builder: (context, deviceSnapshot) {
            if (deviceSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingScreen(message: 'Validando hardware...');
            }

            // REDIRECCIÓN INTELIGENTE:
            // Si el dispositivo está autorizado, entra al bot.
            // Si NO está autorizado, muestra la pantalla de vinculación (azul).
            if (deviceSnapshot.data == true) {
              return const BotMainScreen();
            } else {
              return const LoginScreen();
            }
          },
        );
      },
    );
  }

  Future<bool> _isUserAdmin(String uid) async {
    try {
      final snapshot = await FirebaseDatabase.instance.ref('users/$uid/role').get();
      if (snapshot.exists) {
        return snapshot.value == 'admin';
      }
      return false;
    } catch (e) {
      debugPrint("Error verificando rol: $e");
      return false;
    }
  }
}

class LoadingScreen extends StatelessWidget {
  final String message;
  const LoadingScreen({super.key, this.message = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF021B43),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF0071CE)),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(message, style: const TextStyle(color: Colors.white70)),
            ],
          ],
        ),
      ),
    );
  }
}
