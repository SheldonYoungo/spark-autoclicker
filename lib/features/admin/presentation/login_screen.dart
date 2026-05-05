import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../../core/theme/app_theme.dart';

import 'admin_dashboard.dart';
import '../../automation/presentation/bot_main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
// ... rest of imports and class remains but the navigation part below will be changed too

class _LoginScreenState extends State<LoginScreen> {
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  String _deviceId = 'Obteniendo ID...';

  @override
  void initState() {
    super.initState();
    _getDeviceId();
  }

  Future<void> _getDeviceId() async {
    String? deviceId;
    final deviceInfo = DeviceInfoPlugin();
    
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // ID único de hardware en Android
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor;
      }
    } catch (e) {
      deviceId = 'Error al obtener ID';
    }

    if (mounted) {
      setState(() {
        _deviceId = deviceId ?? 'Desconocido';
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.length == 1 && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID de dispositivo copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -1.0),
            radius: 2.0,
            colors: [
              Color(0xFF00D9F7),
              Color(0xFF00B4E4),
              Color(0xFF008ED1),
              Color(0xFF0069BD),
              Color(0xFF0043AA),
              Color(0xFF013688),
              Color(0xFF012966),
              Color(0xFF021B43),
              AppColors.background,
            ],
            stops: [0.0, 0.12, 0.24, 0.36, 0.49, 0.61, 0.74, 0.87, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  'Ingresa tu Llave de Activación proporcionada por el administrador',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    color: AppColors.white,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 56),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(4, (index) {
                    return Container(
                      width: 75,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.white, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            color: AppColors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                          ),
                          onChanged: (value) => _onChanged(value, index),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                // Mostrar Device ID para que el usuario se lo envíe al admin
                GestureDetector(
                  onTap: _copyDeviceId,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'TU ID DE DISPOSITIVO:',
                          style: TextStyle(color: AppColors.secondaryCian, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _deviceId,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '(Toca para copiar)',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Ayuda',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            color: AppColors.primarySpark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Obtener el código ingresado
                          String code = _controllers.map((e) => e.text).join();
                          
                          if (code == '0000') {
                            // MODO CONDUCTOR (TEST)
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const BotMainScreen()),
                            );
                          } else if (code == '9999') {
                            // MODO ADMINISTRADOR (TEST)
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const AdminDashboard()),
                            );
                          } else if (code.length == 4) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Llave incorrecta o dispositivo no autorizado'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primarySpark,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Activar',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
