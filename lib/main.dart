import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';

void main() async {
  // Aseguramos que Flutter esté listo antes de iniciar Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // Cargamos las variables de entorno (.env)
  await dotenv.load(fileName: ".env");

  // Inicializamos Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Si falla es porque probablemente falta el archivo google-services.json
    print("Error al inicializar Firebase: $e");
  }

  runApp(const SparkApp());
}

class SparkApp extends StatelessWidget {
  const SparkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spark Autoclicker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatelessWidget {
  const MainScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'SPARK',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: AppColors.primarySpark,
                  ),
            ),
            const Text(
              'AUTOCLICKER',
              style: TextStyle(
                color: AppColors.white,
                letterSpacing: 4,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'SISTEMA CONFIGURADO',
              style: TextStyle(color: AppColors.secondaryCian, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
