import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/overlay_util.dart';
import '../../automation/data/filter_service.dart';
import '../../automation/domain/filter_model.dart';
import 'overlay_sizes.dart';

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

  @override
  void initState() {
    super.initState();
    _isExpanded = false;
    _loadInitialFilters();

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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = OverlaySizes(screenWidth: mq.size.width, screenHeight: mq.size.height);

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: _isExpanded
            ? _buildDraggablePanel(s)
            : _buildFloatingBubble(s),
      ),
    );
  }

  Widget _buildFloatingBubble(OverlaySizes s) {
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

          await Future.delayed(const Duration(milliseconds: 200));

          if (mounted) {
            setState(() => _isExpanded = true);
          }

          await FlutterOverlayWindow.resizeOverlay(s.panelWidth, s.panelHeight, false);

          await Future.delayed(const Duration(milliseconds: 50));

          try {
            final screenW = s.screenWidth;
            final screenH = s.screenHeight;
            final centerX = ((screenW - s.panelWidth) / 2).round().clamp(0, 999);
            final centerY = ((screenH - s.panelHeight) / 2).round().clamp(0, 999);

            await FlutterOverlayWindow.moveOverlay(
              OverlayPosition(centerX.toDouble(), centerY.toDouble()),
            );
          } catch (e) {
            debugPrint("moveOverlay centrar panel falló: $e");
          }
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: _filterService.isBotActiveNotifier,
          builder: (context, isActive, _) {
            final Color statusColor = isActive
                ? const Color(0xFF00FF88)
                : const Color(0xFFFF3333);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              width: OverlaySizes.bubbleSize,
              height: OverlaySizes.bubbleSize,
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

  Widget _buildDraggablePanel(OverlaySizes s) {
    final fs = s.fontScale;
    final ss = s.spacingScale;

    return RepaintBoundary(
      key: const ValueKey('panel'),
      child: Center(
        child: Container(
          width: s.panelWidth.toDouble(),
          constraints: BoxConstraints(maxHeight: s.panelHeight.toDouble()),
        padding: EdgeInsets.symmetric(horizontal: 16 * ss, vertical: 20 * ss),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0A1629), Color(0xFF020E21)],
          ),
          borderRadius: BorderRadius.circular(28 * ss),
          border: Border.all(color: AppColors.borderBlue.withValues(alpha: 0.8), width: 1.5),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36 * ss, height: 4, margin: EdgeInsets.only(bottom: 16 * ss),
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10))),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text('SPARK BOT', style: GoogleFonts.orbitron(fontSize: 16 * fs, fontWeight: FontWeight.w800, color: AppColors.white), overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    if (mounted) setState(() => _isExpanded = false);

                    await Future.delayed(const Duration(milliseconds: 50));

                    await FlutterOverlayWindow.resizeOverlay(
                      OverlaySizes.collapsedWindow.toInt(),
                      OverlaySizes.collapsedWindow.toInt(),
                      true,
                    );

                    if (_originalPosition != null) {
                      try {
                        await FlutterOverlayWindow.moveOverlay(_originalPosition!);
                      } catch (e) {
                        debugPrint("Error restaurando posición: $e");
                      }
                    }
                    _originalPosition = null;
                  },
                ),
              ],
            ),

            SizedBox(height: 24 * ss),

            ValueListenableBuilder<BotFilters>(
              valueListenable: _filterService.filtersNotifier,
              builder: (context, filters, _) {
                final String storeDisplay = filters.storeCode?.isNotEmpty == true
                    ? (filters.storeCode!.contains(',') ? '${filters.storeCode!.split(',').length} tnd' : '#${filters.storeCode}')
                    : 'FALTA';

                String typesDisplay = 'TODAS';
                if (filters.orderTypes.isNotEmpty) {
                  if (filters.orderTypes.length > 2) {
                    typesDisplay = '${filters.orderTypes.length} CATEGORÍAS';
                  } else {
                    typesDisplay = filters.orderTypes.join(', ').toUpperCase();
                  }
                }

                return _buildCriteriaCard(s, filters, storeDisplay, typesDisplay);
              },
            ),

            SizedBox(height: 28 * ss),

            if (_isValidating)
              const CircularProgressIndicator(color: AppColors.primarySpark)
            else
              ValueListenableBuilder<bool>(
                valueListenable: _filterService.isBotActiveNotifier,
                builder: (context, isActive, _) {
                  return _buildActionButton(
                    s,
                    label: isActive ? 'DETENER BOT' : 'ACTIVAR BOT',
                    isPrimary: !isActive,
                    isDanger: isActive,
                    onTap: () => _handleBotToggle(isActive),
                  );
                },
              ),

            SizedBox(height: 12 * ss),

            _buildActionButton(
              s,
              label: 'CERRAR SISTEMA',
              isSecondary: true,
              onTap: () => OverlayUtil.closeOverlay(),
            ),
          ],
        ),
        ),
      ),
      ),
    );
  }

  Widget _buildCriteriaCard(OverlaySizes s, BotFilters filters, String store, String types) {
    final ss = s.spacingScale;
    String speedLabel = 'NORMAL';
    if (filters.speedMultiplier >= 3.0) speedLabel = 'EXTREMO';
    else if (filters.speedMultiplier >= 2.0) speedLabel = 'LIEBRE';
    else if (filters.speedMultiplier >= 1.5) speedLabel = 'SEGURO';

    return Container(
      padding: EdgeInsets.all(16 * ss),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16 * ss),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          _buildCriteriaRow(s, 'Tienda', store),
          Divider(height: 20 * ss, color: Colors.white10),
          _buildCriteriaRow(s, 'Pago Mín.', '> \$${filters.minPay.toStringAsFixed(2)}'),
          Divider(height: 20 * ss, color: Colors.white10),
          _buildCriteriaRow(s, 'Distancia', '< ${filters.maxDistance.toStringAsFixed(1)} mi'),
          Divider(height: 20 * ss, color: Colors.white10),
          _buildCriteriaRow(s, 'Categorías', types),
          Divider(height: 20 * ss, color: Colors.white10),
          _buildInteractiveCriteriaRow(
            s,
            'Velocidad',
            speedLabel,
            onTap: () {
              final tiers = [1.0, 1.5, 2.0, 3.0];
              int index = tiers.indexOf(filters.speedMultiplier);
              if (index == -1) index = 1;
              double nextVal = tiers[(index + 1) % tiers.length];
              _filterService.saveFilters(filters.copyWith(speedMultiplier: nextVal));
            }
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveCriteriaRow(OverlaySizes s, String label, String value, {required VoidCallback onTap}) {
    final fs = s.fontScale;
    final ss = s.spacingScale;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4 * ss),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12 * fs, color: Colors.white70, fontWeight: FontWeight.w600)),
            SizedBox(width: 8 * ss),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(value.toUpperCase(), style: GoogleFonts.inter(fontSize: 11 * fs, color: AppColors.primarySpark, fontWeight: FontWeight.bold), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 4 * ss),
                  Icon(Icons.sync, size: 12 * fs, color: AppColors.primarySpark),
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
      await _filterService.toggleBot(newState).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint("Overlay: Error al solicitar toggle del bot: $e");
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  Widget _buildCriteriaRow(OverlaySizes s, String label, String value) {
    final fs = s.fontScale;
    final ss = s.spacingScale;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12 * fs, color: Colors.white70, fontWeight: FontWeight.w600)),
        SizedBox(width: 12 * ss),
        Expanded(child: Text(value.toUpperCase(), style: GoogleFonts.inter(fontSize: 11 * fs, color: AppColors.secondaryCian, fontWeight: FontWeight.bold), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildActionButton(OverlaySizes s, {required String label, required VoidCallback onTap, bool isPrimary = false, bool isDanger = false, bool isSecondary = false}) {
    final fs = s.fontScale;
    final ss = s.spacingScale;

    Color bgColor = isPrimary ? AppColors.primarySpark : (isDanger ? Colors.redAccent : Colors.white10);
    Color textColor = isPrimary ? Colors.black : Colors.white;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 16 * ss),
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14 * ss)),
        child: Center(child: Text(label, style: GoogleFonts.inter(fontSize: 13 * fs, fontWeight: FontWeight.w900, color: textColor))),
      ),
    );
  }
}
