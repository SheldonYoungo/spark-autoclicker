import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart';
import '../data/auth_service.dart';
import '../../automation/data/activation_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final ActivationService _activationService = ActivationService();
  final List<TextEditingController> _pinControllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(4, (_) => FocusNode());
  
  String _deviceId = 'Obteniendo ID...';
  bool _isLoading = false;
  String? _errorMessage;
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
    for (var c in _pinControllers) {
      c.dispose();
    }
    for (var f in _pinFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _getDeviceId() async {
    String? deviceId;
    try {
      deviceId = await _activationService.getDeviceId();
    } catch (e) {
      deviceId = 'Error al obtener ID';
    }
    if (mounted) setState(() => _deviceId = deviceId ?? 'Desconocido');
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

  // --- LÓGICA DE ACTIVACIÓN DIRECTA (PARA CHOFERES) ---
  Future<void> _handleActivation() async {
    final String key = _pinControllers.map((c) => c.text).join();
    if (key.length < 4) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final String? error = await _activationService.activateDeviceWithKeyOnly(key, _deviceId);

    if (!mounted) return;

    if (error == null) {
      // El AuthWrapper en main.dart detectará el cambio
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
      // Limpiar PIN
      for (var c in _pinControllers) {
        c.clear();
      }
      _pinFocusNodes[0].requestFocus();
    }
  }

  // --- LÓGICA DE LOGIN SECRETO (PARA ADMIN) ---
  void _showSecretAdminLogin() {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Modo Administrador', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
              decoration: InputDecoration(
                labelText: 'Número de Teléfono',
                labelStyle: GoogleFonts.inter(color: Colors.white70),
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
              
              Navigator.pop(ctx); // Cierra diálogo de teléfono
              _startTimer();
              _showLoadingDialog('Enviando SMS...');
              
              await _authService.verifyPhone(
                phoneNumber: phone,
                onCodeSent: (verId) {
                  _popSafe(); // Quitar loading
                  if (mounted) _showOtpDialog(verId);
                },
                onError: (e) {
                  _popSafe(); // Quitar loading
                  if (mounted) _showError(e.message ?? 'Error de SMS');
                },
              );
            },
            child: const Text('Enviar SMS', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showOtpDialog(String verId) {
    final otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Verificar', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: otpController,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(hintText: '000000', hintStyle: TextStyle(color: Colors.white24)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark),
            onPressed: () async {
              final code = otpController.text;
              if (code.length < 6) return;
              
              Navigator.pop(ctx); // Cierra diálogo OTP
              _showLoadingDialog('Verificando...');
              
              try {
                await _authService.signInWithSms(
                  verificationId: verId,
                  smsCode: code,
                  isAdminRequest: true,
                );
                _popSafe(); // Quitar loading
              } catch (e) {
                _popSafe(); // Quitar loading
                if (mounted) _showError(e.toString());
              }
            },
            child: const Text('Entrar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceAll("Exception: ", "")), backgroundColor: Colors.red),
    );
  }

  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID copiado al portapapeles')));
    }
  }

  void _popSafe() {
    final nav = navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -1.0),
            radius: 2.2,
            colors: [
              Color(0xFF00D9F7), 
              Color(0xFF00B4E4), 
              Color(0xFF008ED1), 
              Color(0xFF0069BD), 
              Color(0xFF0043AA), 
              Color(0xFF013688), 
              Color(0xFF012966), 
              Color(0xFF021B43), 
              AppColors.background
            ],
            stops: [0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              children: [
                const Spacer(flex: 2),
                
                // Logo Discreto con Gesto Secreto
                GestureDetector(
                  onLongPress: _showSecretAdminLogin,
                  child: Text(
                    'SPARK APP',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'VINCULACIÓN DE HARDWARE',
                  style: GoogleFonts.inter(
                    color: AppColors.primarySpark,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                
                const Spacer(flex: 3),

                // Cuadro de Vinculación (PIN)
                Text(
                  'INGRESA TU LLAVE',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(4, (index) {
                    return Container(
                      width: 60,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Center(
                        child: TextField(
                          controller: _pinControllers[index],
                          focusNode: _pinFocusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: GoogleFonts.jetBrainsMono(
                            color: AppColors.primarySpark,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                          onChanged: (value) {
                            if (value.isNotEmpty && index < 3) {
                              _pinFocusNodes[index + 1].requestFocus();
                            } else if (value.isEmpty && index > 0) {
                              _pinFocusNodes[index - 1].requestFocus();
                            }
                            
                            final currentKey = _pinControllers.map((c) => c.text).join();
                            if (currentKey.length == 4) {
                              _handleActivation();
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],

                const Spacer(flex: 2),

                // Device Info Card
                GestureDetector(
                  onTap: _copyDeviceId,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'ID DE HARDWARE:',
                          style: GoogleFonts.inter(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _deviceId,
                          style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '(Toca para copiar)',
                          style: GoogleFonts.inter(color: Colors.white24, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const Spacer(flex: 2),
                
                if (_isLoading)
                  const CircularProgressIndicator(color: AppColors.primarySpark)
                else
                  Text(
                    'Spark Engine v1.0.2',
                    style: GoogleFonts.inter(color: Colors.white10, fontSize: 10),
                  ),
                  
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
