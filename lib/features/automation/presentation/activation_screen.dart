import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/activation_service.dart';
import 'bot_main_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final List<TextEditingController> _controllers = List.generate(4, (index) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());
  final ActivationService _activationService = ActivationService();
  bool _isLoading = false;
  String? _errorMessage;

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

  Future<void> _handleActivation() async {
    final String key = _controllers.map((c) => c.text).join();
    if (key.length < 4) {
      setState(() => _errorMessage = 'Ingresa el código completo.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorMessage = 'Sesión no válida. Reinicia la app.');
      return;
    }

    // Convertimos el UID al formato usado en RTDB (el teléfono formateado)
    final String tempId = user.phoneNumber?.replaceAll('+', '').replaceAll('.', '_') ?? user.uid;

    final String? error = await _activationService.activateKey(tempId, key);

    if (error == null) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const BotMainScreen()),
        );
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Fondo negro Spark
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              // Header
              Text(
                'SPARK APP',
                style: GoogleFonts.montserrat(
                  color: const Color(0xFF0071CE), // Azul Walmart
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'By Sheldon Youngo',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(flex: 2),
              
              // Título de la sección
              Text(
                'ACTIVAR DISPOSITIVO',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Ingresa el código de 4 dígitos enviado por WhatsApp para vincular este teléfono.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),

              // PIN Input Fields
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return SizedBox(
                    width: 64,
                    height: 80,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFF0071CE),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF0071CE), width: 2),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty && index < 3) {
                          _focusNodes[index + 1].requestFocus();
                        } else if (value.isEmpty && index > 0) {
                          _focusNodes[index - 1].requestFocus();
                        }
                        if (index == 3 && value.isNotEmpty) {
                          _handleActivation();
                        }
                      },
                    ),
                  );
                }),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],

              const Spacer(flex: 3),

              // Botones
              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF0071CE))
              else
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _handleActivation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0071CE),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'ACTIVAR',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: Text(
                        'Cerrar Sesión',
                        style: GoogleFonts.inter(color: Colors.white54),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
