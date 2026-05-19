import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/overlay_util.dart';
import '../../../core/utils/accessibility_util.dart';
import '../../automation/data/filter_service.dart';
import '../../automation/domain/filter_model.dart';

class OverlayScreen extends StatefulWidget {
  const OverlayScreen({super.key});

  @override
  State<OverlayScreen> createState() => _OverlayScreenState();
}

class _OverlayScreenState extends State<OverlayScreen> {
  bool _isExpanded = false;
  bool _isValidating = false;
  Completer<bool>? _accessibilityCompleter;
  StreamSubscription? _overlaySubscription;
  final FilterService _filterService = FilterService();

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    _loadInitialFilters();

    _overlaySubscription = _filterService.overlayEvents.listen((event) {
      debugPrint("Overlay recibió evento: $event");
      if (event == 'reset_overlay_state') {
        if (mounted) setState(() => _isExpanded = false);
      } else if (event == 'refresh_filters') {
        _handleFiltersRefresh();
      } else if (event == 'bot_activated' || event == 'bot_deactivated') {
        // Cuando recibimos confirmación del Isolate principal, detenemos la carga
        if (mounted) setState(() => _isValidating = false);
      } else if (event is Map && event['type'] == 'accessibility_result') {
        _accessibilityCompleter?.complete(event['enabled'] == true);
      }
    });
  }

  Future<bool> _proxyIsServiceEnabled() async {
    _accessibilityCompleter = Completer<bool>();
    await FlutterOverlayWindow.shareData('request_accessibility_check');
    // Timeout de 2 segundos por seguridad
    return _accessibilityCompleter!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => false,
    );
  }

  Future<void> _proxyOpenSettings() async {
    await FlutterOverlayWindow.shareData('request_open_settings');
  }

  Future<void> _handleFiltersRefresh() async {
    // Pequeño delay para asegurar que el I/O del isolate principal terminó
    await Future.delayed(const Duration(milliseconds: 150));
    await _loadInitialFilters();
    
    // Si el bot está activo, re-sincronizamos con el motor nativo con los nuevos valores
    if (_filterService.isBotActiveNotifier.value) {
      await _filterService.syncWithNative(true);
    }
  }

  Future<void> _loadInitialFilters() async {
    // forceReload: true es CRÍTICO aquí porque el Overlay corre en su propio Isolate
    await _filterService.loadFilters(forceReload: true);
    if (mounted) {
      setState(() {}); // Forzamos rebuild para reflejar cambios en UI
    }
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            );
          },
          child: _isExpanded
              ? _buildDraggablePanel()
              : _buildFloatingBubble(),
        ),
      ),
    );
  }

  Widget _buildFloatingBubble() {
    return Center(
      key: const ValueKey('bubble'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await _loadInitialFilters();
          // CRÍTICO: Redimensionar ANTES de mostrar el panel para evitar overflow
          await FlutterOverlayWindow.resizeOverlay(320, 560, true);
          if (mounted) {
            setState(() => _isExpanded = true);
          }
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: _filterService.isBotActiveNotifier,
          builder: (context, isActive, _) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 70, height: 70,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isActive 
                      ? [AppColors.primarySpark, const Color(0xFF0043AA)]
                      : [const Color(0xFF0A1629), const Color(0xFF020E21)],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? Colors.white : AppColors.primarySpark, 
                  width: isActive ? 3.5 : 2.5
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isActive ? AppColors.primarySpark : Colors.black)
                        .withValues(alpha: isActive ? 0.6 : 0.25), 
                    blurRadius: isActive ? 20 : 15,
                    spreadRadius: isActive ? 2 : 0
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: ClipOval(
                  child: Image.asset(
                    'public/images/SPARK-LOGO.png',
                    fit: BoxFit.cover,
                    color: isActive ? Colors.white : null,
                    colorBlendMode: isActive ? BlendMode.srcIn : null,
                    errorBuilder: (context, error, stackTrace) =>
                      Icon(isActive ? Icons.bolt : Icons.smart_toy, 
                        color: isActive ? Colors.white : AppColors.primarySpark, 
                        size: 30),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDraggablePanel() {
    return Center(
      key: const ValueKey('panel'),
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1629), Color(0xFF020E21)],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderBlue.withValues(alpha: 0.8), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10))),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SPARK BOT', style: GoogleFonts.orbitron(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.white)),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () async {
                    // Redimensionar ANTES de colapsar para evitar overflow transitorio
                    await FlutterOverlayWindow.resizeOverlay(80, 80, true);
                    if (mounted) {
                      setState(() => _isExpanded = false);
                    }
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            ValueListenableBuilder<BotFilters>(
              valueListenable: _filterService.filtersNotifier,
              builder: (context, filters, _) {
                final String storeDisplay = filters.storeCode?.isNotEmpty == true 
                    ? '#${filters.storeCode}' : 'TODAS';
                
                String typesDisplay = 'TODAS';
                if (filters.orderTypes.isNotEmpty) {
                  if (filters.orderTypes.length > 2) {
                    typesDisplay = '${filters.orderTypes.length} CATEGORÍAS';
                  } else {
                    typesDisplay = filters.orderTypes.join(', ').toUpperCase();
                  }
                }

                return _buildCriteriaCard(filters, storeDisplay, typesDisplay);
              },
            ),
            
            const SizedBox(height: 28),
            
            if (_isValidating)
              const CircularProgressIndicator(color: AppColors.primarySpark)
            else
              ValueListenableBuilder<bool>(
                valueListenable: _filterService.isBotActiveNotifier,
                builder: (context, isActive, _) {
                  return _buildActionButton(
                    label: isActive ? 'DETENER BOT' : 'ACTIVAR BOT',
                    isPrimary: !isActive,
                    isDanger: isActive,
                    onTap: () => _handleBotToggle(isActive),
                  );
                },
              ),
            
            const SizedBox(height: 12),
            
            _buildActionButton(
              label: 'CERRAR SISTEMA',
              isSecondary: true,
              onTap: () => OverlayUtil.closeOverlay(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriteriaCard(BotFilters filters, String store, String types) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          _buildCriteriaRow('Tienda', store),
          const Divider(height: 20, color: Colors.white10),
          _buildCriteriaRow('Pago Mín.', '> \$${filters.minPay.toStringAsFixed(2)}'),
          const Divider(height: 20, color: Colors.white10),
          _buildCriteriaRow('Distancia', '< ${filters.maxDistance.toStringAsFixed(1)} mi'),
          const Divider(height: 20, color: Colors.white10),
          _buildCriteriaRow('Categorías', types),
        ],
      ),
    );
  }

  Future<void> _handleBotToggle(bool currentState) async {
    final bool newState = !currentState;
    
    if (mounted) setState(() => _isValidating = true);

    try {
      // El toggleBot de FilterService ahora detecta si está en el Overlay
      // y delega la ejecución real (incluyendo validaciones) al Isolate Principal.
      // Esperamos el evento 'bot_activated' o 'bot_deactivated' para quitar el spinner.
      await _filterService.toggleBot(newState);
    } catch (e) {
      debugPrint("Overlay: Error al solicitar toggle del bot: $e");
      if (mounted) setState(() => _isValidating = false);
    }
  }

  Widget _buildCriteriaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(child: Text(value.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, color: AppColors.secondaryCian, fontWeight: FontWeight.bold), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildActionButton({required String label, required VoidCallback onTap, bool isPrimary = false, bool isDanger = false, bool isSecondary = false}) {
    Color bgColor = isPrimary ? AppColors.primarySpark : (isDanger ? Colors.redAccent : Colors.white10);
    Color textColor = isPrimary ? Colors.black : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
        child: Center(child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w900, color: textColor))),
      ),
    );
  }
}
