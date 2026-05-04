import 'package:flutter/material.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';

void main() {
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
          ],
        ),
      ),
    );
  }
}
