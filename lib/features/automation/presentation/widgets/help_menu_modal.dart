import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

class HelpMenuModal extends StatefulWidget {
  const HelpMenuModal({Key? key}) : super(key: key);

  @override
  State<HelpMenuModal> createState() => _HelpMenuModalState();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return HelpMenuModal();
        },
      ),
    );
  }
}

class _HelpMenuModalState extends State<HelpMenuModal> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.spark.autoclicker/core');
  
  bool _overlayGranted = false;
  bool _notificationsGranted = false;
  bool _accessibilityGranted = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    // Use a timer to constantly check accessibility permission because Android doesn't always notify app resumes when navigating back from settings
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    final notif = await Permission.notification.isGranted;
    
    bool access = false;
    try {
      access = await platform.invokeMethod<bool>('isServiceEnabled') ?? false;
    } catch (e) {
      debugPrint("Error checking accessibility: \$e");
    }

    if (mounted && (_overlayGranted != overlay || _notificationsGranted != notif || _accessibilityGranted != access)) {
      setState(() {
        _overlayGranted = overlay;
        _notificationsGranted = notif;
        _accessibilityGranted = access;
      });
    }
  }

  Future<void> _requestOverlay() async {
    if (_overlayGranted) return;
    await FlutterOverlayWindow.requestPermission();
    _checkPermissions();
  }

  Future<void> _requestNotification() async {
    if (_notificationsGranted) return;
    final status = await Permission.notification.request();
    if (status.isPermanentlyDenied || status.isDenied) {
      // Si el sistema no muestra el prompt nativo, lo mandamos a los ajustes.
      await openAppSettings();
    }
    _checkPermissions();
  }

  Future<void> _requestAccessibility() async {
    if (_accessibilityGranted) return;
    try {
      await platform.invokeMethod('openSettings');
    } catch (e) {
      debugPrint("Error opening accessibility settings: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 16),
                _buildPermissionCard(
                  step: "Paso 1: ventana sobre otras apps",
                  description: "Android necesita que actives manualmente \"Mostrar sobre otras apps\" para Spark AI.",
                  grantedText: "Ventana sobre otras apps: permitida",
                  requestText: "Activar Permiso de Ventana",
                  isGranted: _overlayGranted,
                  onRequest: _requestOverlay,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  step: "Paso 2: notificaciones",
                  description: "Se usa una notificación pequeña mientras el botón flotante está activo (lo pide el sistema).",
                  grantedText: "Notificaciones: permitidas",
                  requestText: "Permitir Notificaciones",
                  isGranted: _notificationsGranted,
                  onRequest: _requestNotification,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  step: "Paso 3: servicio de accesibilidad",
                  description: "Activa \"Spark AI\" en Ajustes de accesibilidad: con el interruptor encendido, la app intentará pulsar el botón «ACEPTAR» en la pantalla actual (cada segundo). Revisa que el texto del botón sea reconocible por el sistema.",
                  grantedText: "Accesibilidad: Spark AI activado",
                  requestText: "Activar Accesibilidad",
                  isGranted: _accessibilityGranted,
                  onRequest: _requestAccessibility,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primarySpark.withOpacity(0.8),
            const Color(0xFF0043AA),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primarySpark.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.asset(
              'public/images/SPARK-LOGO-BIG.png',
              height: 48,
              width: 48,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPARK AI',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'bypirrihn',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NEURAL INTERFACE · v1',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondaryCian,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required String step,
    required String description,
    required String grantedText,
    required String requestText,
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1835), // Dark blue background similar to the image
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isGranted ? null : onRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: isGranted ? Colors.white.withOpacity(0.1) : AppColors.primarySpark.withOpacity(0.2),
                disabledBackgroundColor: Colors.white.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                isGranted ? grantedText : requestText,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isGranted ? Colors.white.withOpacity(0.4) : AppColors.secondaryCian,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
