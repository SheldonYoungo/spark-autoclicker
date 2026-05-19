import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';
import 'package:spark_autoclicker/core/utils/accessibility_util.dart';
import 'package:spark_autoclicker/features/admin/presentation/login_screen.dart';
import 'package:spark_autoclicker/features/admin/presentation/admin_dashboard.dart';
import 'package:spark_autoclicker/features/automation/presentation/bot_main_screen.dart';
import 'package:spark_autoclicker/features/automation/data/activation_service.dart';
import 'package:spark_autoclicker/features/automation/data/filter_service.dart';
import 'package:spark_autoclicker/features/overlay/presentation/overlay_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics(); // FUERZA a Flutter a crear el árbol de accesibilidad
  await dotenv.load(fileName: ".env");

  // MARCADO DE ISOLATE PRINCIPAL: Crítico para que el FilterService sepa que puede usar MethodChannels
  FilterService.isMainIsolate = true;

  // Inicializar escucha de logs nativos globalmente
  AccessibilityUtil.initNativeLogger((log) {
    debugPrint("📱 [LOG NATIVO] $log");
  }, isGlobal: true);

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: dotenv.get('FIREBASE_API_KEY'),
          appId: '1:1071477543888:android:55e638848d82137060965c',
          messagingSenderId: '1071477543888',
          projectId: dotenv.get('FIREBASE_PROJECT_ID'),
          databaseURL: dotenv.get('FIREBASE_DATABASE_URL'),
        ),
      );
    }
    // Cargar estado inicial de activación de hardware y filtros
    await ActivationService().init();
    await FilterService().loadFilters();
  } catch (e) {
    debugPrint("Error al inicializar Firebase: $e");
  }

  runApp(const SparkApp());
}

// Punto de entrada específico para el Overlay Flotante
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // En el Overlay, isMainIsolate permanece en false (por defecto)
  
  // El Overlay corre en su propio proceso/isolate, necesita su propio logger
  AccessibilityUtil.initNativeLogger((log) {
    debugPrint("☁️ [OVERLAY NATIVO] $log");
  }, isGlobal: true);

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayScreen(),
    ),
  );
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

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ActivationService.linkedUidNotifier,
      builder: (context, linkedUid, _) {
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
                  return const LoginScreen();
                },
              );
            }

            // 2. Si no hay admin, pero el dispositivo está vinculado (CONDUCTOR)
            if (linkedUid != null) {
              return StreamBuilder<bool>(
                stream: ActivationService().authStateStream(linkedUid),
                builder: (context, deviceSnapshot) {
                  if (deviceSnapshot.connectionState == ConnectionState.waiting) {
                    // Solo mostramos loading la primera vez o si no tenemos data previa
                    if (!deviceSnapshot.hasData) {
                      return const LoadingScreen(message: 'Validando suscripción...');
                    }
                  }

                  if (deviceSnapshot.data == true) {
                    return const BotMainScreen();
                  } else {
                    // Si el stream emite false, el servicio ya llamó a clearLocalLink
                    return const LoginScreen();
                  }
                },
              );
            }

            // 3. Estado por defecto: Login
            return const LoginScreen();
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
