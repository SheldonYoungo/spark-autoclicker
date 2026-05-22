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
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  
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
    _pinController.dispose();
    _pinFocusNode.dispose();
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
    final String key = _pinController.text;
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
      // ÉXITO: No navegamos manualmente. 
      // El ValueNotifier en ActivationService notificará al AuthWrapper en main.dart
      // y la pantalla cambiará automáticamente a BotMainScreen.
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
      // Limpiar PIN
      _pinController.clear();
      _pinFocusNode.requestFocus();
    }
  }

  // --- LÓGICA DE LOGIN SECRETO (PARA ADMIN) ---
  void _showSecretAdminLogin() {
    final phoneController = TextEditingController();
    String selectedCode = '+1';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.background,
          title: Text('Modo Administrador', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCode,
                        dropdownColor: AppColors.background,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: '+1', child: Text('🇺🇸 +1')),
                          DropdownMenuItem(value: '+58', child: Text('🇻🇪 +58')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedCode = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: phoneController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Número',
                        labelStyle: GoogleFonts.inter(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark),
              onPressed: () async {
                final phone = phoneController.text.trim();
                if (phone.isEmpty) return;
                
                final fullPhone = '$selectedCode$phone';
                
                Navigator.pop(ctx); // Cierra diálogo de teléfono
                _startTimer();
                _showLoadingDialog('Enviando SMS...');
                
                await _authService.verifyPhone(
                  phoneNumber: fullPhone,
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
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    
                    // Logo Oficial con Gesto Secreto
                    GestureDetector(
                      onLongPress: _showSecretAdminLogin,
                      child: Hero(
                        tag: 'app_logo',
                        child: Image.asset(
                          'public/images/SPARK-LOGO-BIG.png',
                          height: 200,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    SizedBox(
                      height: 70,
                      child: Stack(
                        children: [
                          // 1. Interfaz visual (Fondo)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(4, (index) {
                              final String char = _pinController.text.length > index 
                                  ? _pinController.text[index] 
                                  : "";
                              final bool isFocused = _pinController.text.length == index;
                              
                              return Container(
                                width: 60,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isFocused ? AppColors.primarySpark : Colors.white24,
                                    width: isFocused ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    char,
                                    style: GoogleFonts.jetBrainsMono(
                                      color: AppColors.primarySpark,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          // 2. TextField Transparente (Frente - Captura de input)
                          Positioned.fill(
                            child: TextField(
                              controller: _pinController,
                              focusNode: _pinFocusNode,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              autofocus: true,
                              cursorColor: Colors.transparent,
                              showCursor: false,
                              enableInteractiveSelection: false,
                              style: const TextStyle(
                                color: Colors.transparent, 
                                fontSize: 28, // Mantener tamaño para el área de toque
                                letterSpacing: 50, // Espaciado para que no se amontone
                              ),
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (value) {
                                setState(() {});
                                if (value.length == 4) {
                                  _handleActivation();
                                }
                              },
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                counterText: "",
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
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
              
              // Banner de Expiración
              ValueListenableBuilder<bool>(
                valueListenable: ActivationService.showExpiredBanner,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.shrink();
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.95),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
                        ]
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.black),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SUSCRIPCIÓN VENCIDA',
                                  style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                                Text(
                                  'Tu tiempo de uso ha terminado. Contacta al administrador para renovar.',
                                  style: GoogleFonts.inter(color: Colors.black87, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black, size: 20),
                            onPressed: () => ActivationService.showExpiredBanner.value = false,
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
