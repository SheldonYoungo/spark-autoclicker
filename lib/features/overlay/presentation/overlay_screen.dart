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

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isExpanded ? _buildExpandedPanel() : _buildCollapsedIcon(),
      ),
    );
  }

  // --- 1. ICONO FLOTANTE (ARRASTRABLE) ---
  Widget _buildCollapsedIcon() {
    return GestureDetector(
      key: const ValueKey('collapsed'),
      onTap: () async {
        setState(() => _isExpanded = true);
        
        // EXPANDIR A TAMAÑO DE PANEL (320x500 dp)
        // Mantenemos enableDrag: true para que el menú también se pueda mover.
        await FlutterOverlayWindow.resizeOverlay(320, 500, true);
      },
      child: Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.9),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primarySpark, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8, spreadRadius: 1),
            ],
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

  // --- 2. PANEL DE CONTROL (TARJETA ARRASTRABLE) ---
  Widget _buildExpandedPanel() {
    return Center(
      child: Container(
        key: const ValueKey('expanded'),
        width: 300, // Un poco más pequeño que la ventana (320) para evitar cortes
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderBlue, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 15, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mango visual para arrastre
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
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primarySpark
                )),
                IconButton(
                  icon: const Icon(Icons.remove, color: Colors.white54),
                  onPressed: () async {
                    // MINIMIZAR: Volvemos al cristal pequeño de 150x150 dp
                    await FlutterOverlayWindow.resizeOverlay(150, 150, true);
                    await Future.delayed(const Duration(milliseconds: 50));
                    if (mounted) setState(() => _isExpanded = false);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCriteriaRow('Tienda', '#7178'),
            _buildCriteriaRow('Monto', '> \$20.00'),
            const SizedBox(height: 32),
            _buildActionButton(
              label: _isBotActive ? 'DETENER' : 'ACTIVAR',
              color: _isBotActive ? Colors.redAccent : Colors.greenAccent.withValues(alpha: 0.2),
              textColor: _isBotActive ? Colors.white : Colors.greenAccent,
              onTap: () => setState(() => _isBotActive = !_isBotActive),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: 'CERRAR BOT',
              color: Colors.white10,
              textColor: Colors.white54,
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
