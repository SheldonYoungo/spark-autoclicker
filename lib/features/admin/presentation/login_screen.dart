import 'dart:async';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart'; // Para el navigatorKey

import 'admin_dashboard.dart';
import '../../automation/presentation/bot_main_screen.dart';
import '../data/auth_service.dart';
import '../data/admin_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  final AuthService _authService = AuthService();
  
  String _deviceId = 'Obteniendo ID...';
  bool _isLoading = false;
  int _resendTimer = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _getDeviceId();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) controller.dispose();
    for (var node in _focusNodes) node.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendTimer = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendTimer == 0) {
        timer.cancel();
      } else {
        setState(() => _resendTimer--);
      }
    });
  }

  Future<void> _getDeviceId() async {
    String? deviceId;
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        deviceId = (await deviceInfo.iosInfo).identifierForVendor;
      }
    } catch (e) {
      deviceId = 'Error al obtener ID';
    }
    if (mounted) setState(() => _deviceId = deviceId ?? 'Desconocido');
  }

  void _onChanged(String value, int index) {
    if (value.length == 1 && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (value.length == 1 && index == 3) {
      _handleActivation();
    }
  }

  // --- GESTIÓN SEGURA DE NAVEGACIÓN ---
  
  void _safePop() {
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) nav.pop();
  }

  void _safePush(Widget page) {
    navigatorKey.currentState?.pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  // -------------------------------------

  Future<void> _handleActivation() async {
    String code = _controllers.map((e) => e.text).join();
    if (code.length < 4) return;

    setState(() => _isLoading = true);

    try {
      if (code == '9999') {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          final adminData = await FirebaseDatabase.instance.ref('users/${currentUser.uid}').get();
          if (adminData.exists && adminData.child('role').value == 'admin') {
            _safePush(const AdminDashboard());
          } else {
            await FirebaseAuth.instance.signOut();
            _showAdminSmsDialog();
          }
        } else {
          _showAdminSmsDialog();
        }
        return;
      }

      final user = await _authService.validateActivationKey(code, _deviceId);
      if (user != null) {
        if (!user.isActive) throw Exception("Suscripción inactiva.");
        _safePush(const BotMainScreen());
      } else {
        throw Exception("Llave no válida.");
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAdminSmsDialog() {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Acceso Administrador', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Recibirás un SMS para validar tu identidad.', 
              style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))], // Solo números y +
              decoration: const InputDecoration(
                labelText: 'Teléfono (+...)',
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark),
            onPressed: () async {
              final phone = phoneController.text;
              if (phone.isEmpty) return;
              
              _safePop(); // Cerrar diálogo de teléfono
              _startTimer();
              _showLoadingDialog('Enviando SMS...');
              
              await _authService.verifyPhone(
                phoneNumber: phone,
                onCodeSent: (verId) {
                  _safePop(); // Quitar loading
                  _showOtpDialog(verId, true);
                },
                onError: (e) {
                  _safePop(); // Quitar loading
                  _showError(e.message ?? 'Error de SMS');
                },
              );
            },
            child: const Text('Enviar SMS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primarySpark),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _showOtpDialog(String verId, bool isAdmin) {
    final otpController = TextEditingController();
    showDialog(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.background,
          title: const Text('Verificar Código', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: otpController,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly], // BLOQUEO DE LETRAS/SÍMBOLOS
                maxLength: 6,
                decoration: const InputDecoration(hintText: '000000', hintStyle: TextStyle(color: Colors.white24)),
              ),
              const SizedBox(height: 8),
              Text(
                _resendTimer > 0 ? 'Espera $_resendTimer s para reintentar' : '¿No recibiste el código?',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark),
              onPressed: () async {
                final code = otpController.text;
                if (code.length < 6) return;
                
                _safePop(); // Cerrar OTP
                _showLoadingDialog('Verificando...');

                try {
                  final user = await _authService.signInWithSms(
                    verificationId: verId,
                    smsCode: code,
                    isAdminRequest: isAdmin,
                  );
                  if (user != null) {
                    _safePop(); // Quitar loading
                    _safePush(const AdminDashboard());
                  }
                } catch (e) {
                  _safePop(); // Quitar loading
                  _showError(e.toString());
                }
              },
              child: const Text('Verificar', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceAll("Exception: ", "")), backgroundColor: Colors.red),
    );
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID de dispositivo copiado')));
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
            colors: [Color(0xFF00D9F7), Color(0xFF00B4E4), Color(0xFF008ED1), Color(0xFF0069BD), Color(0xFF0043AA), Color(0xFF013688), Color(0xFF012966), Color(0xFF021B43), AppColors.background],
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
                Text('Ingresa tu Llave de Activación', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 18, color: AppColors.white, height: 1.3)),
                const SizedBox(height: 56),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(4, (index) {
                    return Container(
                      width: 75, height: 80,
                      decoration: BoxDecoration(border: Border.all(color: AppColors.white, width: 1), borderRadius: BorderRadius.circular(12)),
                      child: Center(
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly], // BLOQUEO EN EL LOGIN
                          maxLength: 1,
                          style: GoogleFonts.inter(fontSize: 24, color: AppColors.white, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                          onChanged: (value) => _onChanged(value, index),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _copyDeviceId,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        Text('TU ID DE DISPOSITIVO:', style: TextStyle(color: AppColors.secondaryCian, fontSize: 10)),
                        const SizedBox(height: 4),
                        Text(_deviceId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('(Toca para copiar)', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                if (_isLoading)
                  const CircularProgressIndicator(color: AppColors.primarySpark)
                else
                  Row(
                    children: [
                      Expanded(child: TextButton(onPressed: () {}, child: Text('Ayuda', style: GoogleFonts.inter(fontSize: 18, color: AppColors.primarySpark)))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(onPressed: _handleActivation, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark, foregroundColor: Colors.black, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text('Activar', style: GoogleFonts.inter(fontSize: 18)))),
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
