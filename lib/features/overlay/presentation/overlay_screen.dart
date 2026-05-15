import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/overlay_util.dart';

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  bool _isExpanded = false;
  bool _isBotActive = false;
  StreamSubscription? _overlaySubscription;

  @override
  void initState() {
    super.initState();
    debugPrint("OverlayScreen: initState llamado");
    _isExpanded = false;

    // Escuchar eventos para resetear el estado al recrear el overlay
    _overlaySubscription = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == 'reset_overlay_state') {
        debugPrint("OverlayScreen: Recibido reset_overlay_state");
        if (mounted) {
          setState(() => _isExpanded = false);
        }
      }
    });
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("OverlayScreen: build llamado (isExpanded: $_isExpanded)");

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _isExpanded
              ? _buildDraggablePanel()
              : _buildFloatingBubble(),
        ),
      ),
    );
  }

  // --- 1. FLOATING BUBBLE (Messenger Style Nativo) ---
  Widget _buildFloatingBubble() {
    return Center(
      key: const ValueKey('bubble'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          setState(() => _isExpanded = true);
          // Expandimos al tamaño del menú
          await FlutterOverlayWindow.resizeOverlay(320, 520, true);
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primarySpark, width: 2.5),
          ),
          child: ClipOval(
            child: Image.asset(
              'public/images/SPARK-LOGO.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.smart_toy, color: AppColors.primarySpark, size: 30),
            ),
          ),
        ),
      ),
    );
  }

  // --- 2. PANEL DE CONTROL (Diseño Completo) ---
  Widget _buildDraggablePanel() {
    return Center(
      key: const ValueKey('panel'),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderBlue, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('INIBOT', style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primarySpark
                )),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () async {
                    setState(() => _isExpanded = false);
                    await FlutterOverlayWindow.resizeOverlay(80, 80, true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCriteriaRow('Tienda', '#7178'),
            _buildCriteriaRow('Monto', '> \$20.00'),
            _buildCriteriaRow('Filtro', 'Compras'),
            const SizedBox(height: 32),
            _buildActionButton(
              label: _isBotActive ? 'DETENER BOT' : 'ACTIVAR BOT',
              color: _isBotActive ? Colors.redAccent : AppColors.primarySpark,
              textColor: _isBotActive ? Colors.white : AppColors.background,
              onTap: () => setState(() => _isBotActive = !_isBotActive),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: 'CERRAR SISTEMA',
              color: Colors.white10,
              textColor: Colors.white38,
              onTap: () => OverlayUtil.closeOverlay(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriteriaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.white38)),
          Text(value, style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionButton({required String label, required Color color, required Color textColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(label, style: GoogleFonts.inter(
          fontSize: 14, fontWeight: FontWeight.bold, color: textColor
        ))),
      ),
    );
  }
}
