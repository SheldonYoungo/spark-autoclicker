import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/overlay_util.dart';
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
  StreamSubscription? _overlaySubscription;
  final FilterService _filterService = FilterService();
  OverlayPosition? _originalPosition;
  bool _wasOnLeftSide = false;

  // Dimensiones del panel y burbuja (en dp)
  int get _panelWidth {
    final screenW = _getScreenWidthDp();
    // 90% del ancho de pantalla, mínimo 280, máximo 340
    return (screenW * 0.9).clamp(280.0, 340.0).toInt();
  }
  
  double get _containerWidth => _panelWidth - 20.0; // Margen interno de la ventana

  static const int _panelHeight = 560;
  static const int _collapsedSize = 80;

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    _loadInitialFilters();

    // Sincronización reactiva: Actualizar UI y liberar estado de carga cuando cambie el bot status globalmente
    _filterService.isBotActiveNotifier.addListener(_onBotStatusChanged);

    _overlaySubscription = _filterService.overlayEvents.listen((event) {
      debugPrint("Overlay recibió evento: $event");
      if (event == 'reset_overlay_state') {
        if (mounted) setState(() => _isExpanded = false);
      } else if (event == 'refresh_filters') {
        _handleFiltersRefresh();
      }
    });
  }

  void _onBotStatusChanged() {
    if (mounted) {
      debugPrint("Overlay UI: Detectado cambio de estado global -> Bot ${_filterService.isBotActiveNotifier.value ? 'ON' : 'OFF'}");
      setState(() {
        _isValidating = false;
      });
    }
  }

  Future<void> _handleFiltersRefresh() async {
    await Future.delayed(const Duration(milliseconds: 150));
    await _loadInitialFilters();
    // Nota: El motor nativo ya se auto-sincroniza vía SharedPreferences
  }

  Future<void> _loadInitialFilters() async {
    await _filterService.loadFilters(forceReload: true);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _filterService.isBotActiveNotifier.removeListener(_onBotStatusChanged);
    _overlaySubscription?.cancel();
    super.dispose();
  }

  /// Obtiene el ancho real de la pantalla en dp usando el Display del sistema.
  /// Fallback: estima desde la posición del imán.
  double _getScreenWidthDp() {
    try {
      final display = ui.PlatformDispatcher.instance.displays.first;
      return display.size.width / display.devicePixelRatio;
    } catch (_) {
      return (_originalPosition?.x ?? 280) + _collapsedSize;
    }
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
    return RepaintBoundary(
      key: const ValueKey('bubble'),
      child: Center(
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await _loadInitialFilters();
          
          try {
            _originalPosition = await FlutterOverlayWindow.getOverlayPosition();
          } catch (e) {
            debugPrint("OverlayPosition get falló: $e");
          }

          // RIGHT gravity: x ≈ 0 = borde derecho, x >> 0 = borde izquierdo.
          // Umbral de 50dp distingue lados de forma segura (el imán solo deja x=0 o x=screenW-bubble).
          _wasOnLeftSide = _originalPosition != null && _originalPosition!.x > 50;

          // FIX: El plugin nativo dispara una animación al soltar el toque.
          // Esperamos 200ms para asegurar que el magnetismo termine.
          await Future.delayed(const Duration(milliseconds: 200));

          // Deshabilitar el drag para el panel grande.
          await FlutterOverlayWindow.resizeOverlay(_panelWidth, _panelHeight, false);
          
          // Esperamos 50ms para que la vista nativa asimile el nuevo tamaño
          await Future.delayed(const Duration(milliseconds: 50));

          // Centramos el panel SIEMPRE, sin importar si _originalPosition es null
          try {
            final screenW = _getScreenWidthDp();
            // Dado que la gravedad es centerRight, X es la distancia desde el borde derecho.
            // Para centrarlo horizontalmente, X debe ser la mitad del espacio sobrante.
            final centerX = ((screenW - _panelWidth) / 2).round().clamp(0, 999);
            
            // Mantenemos Y en su posición original si es posible, o 0 (centro)
            final destY = _originalPosition?.y ?? 0.0;
            
            await FlutterOverlayWindow.moveOverlay(
              OverlayPosition(centerX.toDouble(), destY),
            );
          } catch (e) {
            debugPrint("moveOverlay centrar panel falló: $e");
          }

          if (mounted) {
            setState(() => _isExpanded = true);
          }
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: _filterService.isBotActiveNotifier,
          builder: (context, isActive, _) {
            final Color statusColor = isActive 
                ? const Color(0xFF00FF88) // Verde Neón Vibrante (Active)
                : const Color(0xFFFF3333); // Rojo Intenso (Inactive)
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: 70, height: 70,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0D1B3E), Color(0xFF020E21)],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: statusColor, 
                  width: isActive ? 3.5 : 2.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Image.asset(
                  'public/images/SPARK-LOGO-BIG.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                    Icon(
                      isActive ? Icons.bolt : Icons.smart_toy, 
                      color: statusColor, 
                      size: 28,
                    ),
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildDraggablePanel() {
    return RepaintBoundary(
      key: const ValueKey('panel'),
      child: Center(
        child: OverflowBox(
          maxWidth: _panelWidth.toDouble(),
          maxHeight: 600,
          child: Container(
            width: _containerWidth,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1629), Color(0xFF020E21)],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderBlue.withValues(alpha: 0.8), width: 1.5),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10))),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text('SPARK BOT', style: GoogleFonts.orbitron(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.white), overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    if (mounted) setState(() => _isExpanded = false);
                    await Future.delayed(const Duration(milliseconds: 50));
                    // Rehabilitar drag para la burbuja
                    await FlutterOverlayWindow.resizeOverlay(_collapsedSize, _collapsedSize, true);
                    
                    // Restaurar burbuja a su posición original (X e Y)
                    if (_originalPosition != null) {
                      try {
                        final screenW = _getScreenWidthDp();
                        // LEFT edge = screenW - bubble. RIGHT edge = 0
                        final destX = _wasOnLeftSide ? (screenW - _collapsedSize).round() : 0;
                        await FlutterOverlayWindow.moveOverlay(
                          OverlayPosition(destX.toDouble(), _originalPosition!.y),
                        );
                      } catch (e) {
                        debugPrint("Error restaurando posición: $e");
                      }
                    }
                    _originalPosition = null;
                    _wasOnLeftSide = false;
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
      ),
      ),
      ),
    );
  }

  Widget _buildCriteriaCard(BotFilters filters, String store, String types) {
    String speedLabel = 'NORMAL';
    if (filters.speedMultiplier >= 3.0) speedLabel = 'EXTREMO';
    else if (filters.speedMultiplier >= 2.0) speedLabel = 'LIEBRE';
    else if (filters.speedMultiplier >= 1.5) speedLabel = 'SEGURO';

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
          const Divider(height: 20, color: Colors.white10),
          _buildInteractiveCriteriaRow(
            'Velocidad', 
            speedLabel, 
            onTap: () {
              final tiers = [1.0, 1.5, 2.0, 3.0];
              int index = tiers.indexOf(filters.speedMultiplier);
              if (index == -1) index = 1; // Default to Seguro if mismatch
              double nextVal = tiers[(index + 1) % tiers.length];
              _filterService.saveFilters(filters.copyWith(speedMultiplier: nextVal));
            }
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveCriteriaRow(String label, String value, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(value.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, color: AppColors.primarySpark, fontWeight: FontWeight.bold), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  const Icon(Icons.sync, size: 12, color: AppColors.primarySpark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBotToggle(bool currentState) async {
    final bool newState = !currentState;
    if (mounted) setState(() => _isValidating = true);
    try {
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
