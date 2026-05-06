import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';

import 'package:spark_autoclicker/features/admin/presentation/login_screen.dart';

void main() async {
  // Aseguramos que Flutter esté listo antes de iniciar Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // Cargamos las variables de entorno (.env)
  await dotenv.load(fileName: ".env");

  // Inicializamos Firebase
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: dotenv.get('FIREBASE_API_KEY'),
        appId: '1:1071477543888:android:55e638848d82137060965c', // ID del App (Android)
        messagingSenderId: '1071477543888',
        projectId: dotenv.get('FIREBASE_PROJECT_ID'),
        databaseURL: dotenv.get('FIREBASE_DATABASE_URL'),
      ),
    );
  } catch (e) {
    // Si falla es porque probablemente falta el archivo google-services.json
    print("Error al inicializar Firebase: $e");
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
      home: const LoginScreen(),
    );
  }
}
