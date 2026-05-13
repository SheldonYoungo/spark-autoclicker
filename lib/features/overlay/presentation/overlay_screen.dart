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

class _OverlayScreenState extends State<OverlayScreen> with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isBotActive = false;
  
  // Posición base del componente
  Offset _position = const Offset(200, 300);
  
  // Animación para el efecto "Imán" (Magnetic Snap)
  late AnimationController _snapController;
  late Animation<Offset> _snapAnimation;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _snapController.addListener(() {
      setState(() {
        _position = _snapAnimation.value;
      });
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  // Lógica de "Imán" que pega el componente al borde lateral más cercano
  void _runSnapAnimation(double screenWidth, double elementWidth) {
    final double centerX = _position.dx + (elementWidth / 2);
    final double targetX = (centerX < screenWidth / 2) ? 0 : screenWidth - elementWidth;

    _snapAnimation = _snapController.drive(
      Tween<Offset>(
        begin: _position,
        end: Offset(targetX, _position.dy),
      ),
    );
    
    _snapController.reset();
    _snapController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _isExpanded 
          ? _buildDraggablePanel(screenSize.width) 
          : _buildFloatingBubble(screenSize.width),
      ),
    );
  }

  // --- 1. FLOATING BUBBLE (Messenger Style) ---
  Widget _buildFloatingBubble(double screenWidth) {
    return Center(
      key: const ValueKey('bubble'),
      child: GestureDetector(
        onTap: () async {
          setState(() => _isExpanded = true);
          // Expandimos la ventana nativa al tamaño del menú
          await FlutterOverlayWindow.resizeOverlay(320, 500, true);
        },
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

  // --- 2. PANEL DE CONTROL (TARJETA ARRASTRABLE NATIVAMENTE) ---
  Widget _buildDraggablePanel(double screenWidth) {
    return Center(
      key: const ValueKey('panel'),
      child: Container(
        width: 300, 
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderBlue, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 15, spreadRadius: 2),
          ],
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
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primarySpark
                )),
                IconButton(
                  icon: const Icon(Icons.remove, color: Colors.white54),
                  onPressed: () async {
                    setState(() => _isExpanded = false);
                    // Regresamos al cristal pequeño (150x150)
                    await FlutterOverlayWindow.resizeOverlay(150, 150, true);
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
