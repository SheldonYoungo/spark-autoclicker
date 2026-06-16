import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';
import 'package:spark_autoclicker/core/utils/accessibility_util.dart';

class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  bool _testMode = false;
  bool _botActive = false;
  bool _activating = false;
  final List<String> _logs = [];
  final ScrollController _logScroll = ScrollController();
  int _heartbeat = 0;
  Timer? _heartbeatTimer;
  Timer? _countdownTimer;
  int _countdownSeconds = 5;
  bool _acceptClicked = false;
  String? _lastChevronTapped;
  final Set<String> _acceptedLabels = {};

  // Filter config for the test
  double _minPrice = 13.0;
  double _maxDistance = 10.0;
  String _storeId = "1234";
  String _orderType = "Compras,Recolección";

  final List<_TestOffer> _testCards = [
    _TestOffer(label: 'Buena', price: '45.50', distance: '2.1', store: '1234', type: 'Compras', color: Colors.green),
    _TestOffer(label: 'Recolección', price: '25.00', distance: '1.5', store: '1234', type: 'Recolección', color: Colors.blue),
    _TestOffer(label: 'Multiviaje', price: '35.00', distance: '4.2', store: '1234', type: 'Multiviajes', color: Colors.cyan),
    _TestOffer(label: 'Barata', price: '12.00', distance: '0.5', store: '5678', type: 'Compras', color: Colors.orange),
    _TestOffer(label: 'Lejana', price: '50.00', distance: '12.5', store: '1234', type: 'Compras', color: Colors.red),
    _TestOffer(label: 'SoloTi', price: '60.00', distance: '1.0', store: '1234', type: 'Compras', color: Colors.purple, badge: 'SOLO PARA TI'),
    _TestOffer(label: '8Paradas', price: '40.00', distance: '3.0', store: '1234', type: 'Compras', color: Colors.brown, badge: '8 paradas'),
    _TestOffer(label: 'Tilde', price: '30.00', distance: '2.0', store: '1234', type: 'Recolección', color: Colors.teal, badge: 'Recolección'),
  ];

  @override
  void initState() {
    super.initState();
    _loadTestLogs();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _heartbeat++);
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _countdownTimer?.cancel();
    _logScroll.dispose();
    AccessibilityUtil.clearNativeLogger();
    _cleanupTestMode();
    super.dispose();
  }

  void _cleanupTestMode() {
    if (_testMode || _botActive) {
      AccessibilityUtil.setTestMode(false);
      _testMode = false;
      _botActive = false;
    }
  }

  void _loadTestLogs() {
    AccessibilityUtil.initNativeLogger((log) {
      if (mounted) {
        setState(() {
          _logs.add("[${DateTime.now().toString().split(' ')[1].split('.')[0]}] $log");
          if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
        });
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_logScroll.hasClients) {
            _logScroll.animateTo(
              _logScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  Future<void> _toggleTestMode() async {
    if (_testMode) {
      // Desactivar
      await AccessibilityUtil.setTestMode(false);
      if (_botActive) await _toggleBot();
      setState(() => _testMode = false);
      _addLog("🧪 Modo prueba DESACTIVADO");
    } else {
      // Activar
      await AccessibilityUtil.setTestMode(true);
      setState(() => _testMode = true);
      _addLog("🧪 Modo prueba ACTIVADO — el bot escaneará esta pantalla");
    }
  }

  Future<void> _toggleBot() async {
    if (_activating) return;
    setState(() => _activating = true);
    try {
      if (!_botActive) {
        _addLog("🔄 Activando bot en modo prueba...");
        await AccessibilityUtil.updateBotConfiguration(
          isActive: true,
          minPrice: _minPrice,
          maxDistance: _maxDistance,
          storeId: _storeId,
          orderType: _orderType,
          scanSpeed: 300,
        );
        setState(() => _botActive = true);
        _addLog("✅ Bot activado — escaneando ofertas simuladas");
      } else {
        await AccessibilityUtil.updateBotConfiguration(
          isActive: false,
          minPrice: _minPrice,
          maxDistance: _maxDistance,
          storeId: _storeId,
          orderType: _orderType,
          scanSpeed: 300,
        );
        setState(() => _botActive = false);
        _addLog("🛑 Bot desactivado");
      }
    } catch (e) {
      _addLog("❌ Error: $e");
    } finally {
      setState(() => _activating = false);
    }
  }

  void _addLog(String msg) {
    if (mounted) {
      setState(() {
        _logs.add("[${DateTime.now().toString().split(' ')[1].split('.')[0]}] $msg");
        if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
      });
    }
  }

  void _acceptOffer(String label) {
    setState(() => _acceptedLabels.add(label));
    _addLog("✅ Oferta '$label' aceptada — tarjeta eliminada");
  }

  void _simularCountdown() {
    if (_countdownTimer != null) return;
    setState(() => _countdownSeconds = 5);
    _addLog("⏳ Countdown iniciado: disponible en 0:05");
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _countdownSeconds <= 1) {
        timer.cancel();
        _countdownTimer = null;
        if (mounted) {
          setState(() => _countdownSeconds = 0);
          _addLog("✅ Countdown expirado — ACEPTAR debería estar visible ahora");
        }
        return;
      }
      setState(() => _countdownSeconds--);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth * 0.85;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sandbox de Pruebas',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white54),
            onPressed: () => setState(() => _logs.clear()),
            tooltip: 'Limpiar logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // === Control panel ===
          _buildControlPanel(),
          const Divider(height: 1, color: Colors.white10),

          // === Fake offer cards ===
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ..._testCards
                      .where((o) => !_acceptedLabels.contains(o.label))
                      .map((offer) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildOfferCard(offer, cardWidth),
                      )),

                  // Countdown section
                  _buildCountdownSection(cardWidth),
                  const SizedBox(height: 12),

                  // ACEPTAR button
                  _buildAcceptButton(cardWidth),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // === Log console ===
          Expanded(
            flex: 2,
            child: _buildLogConsole(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0A1629),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined,
                  color: _testMode ? Colors.orangeAccent : Colors.white38, size: 20),
              const SizedBox(width: 8),
              Text('MODO PRUEBA',
                  style: TextStyle(
                    color: _testMode ? Colors.orangeAccent : Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  )),
              const Spacer(),
              SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: _toggleTestMode,
                  icon: Icon(
                    _testMode ? Icons.power_settings_new : Icons.play_arrow,
                    size: 14,
                  ),
                  label: Text(_testMode ? 'DESACTIVAR' : 'ACTIVAR',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _testMode ? Colors.orangeAccent : AppColors.borderBlue,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildFilterChip('\$${_minPrice.toStringAsFixed(0)} min'),
              const SizedBox(width: 6),
              _buildFilterChip('${_maxDistance.toStringAsFixed(0)}mi max'),
              const SizedBox(width: 6),
              _buildFilterChip('#$_storeId'),
              const SizedBox(width: 6),
              _buildFilterChip(_orderType.replaceAll(',', ' | ')),
              const Spacer(),
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _botActive ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _botActive ? 'BOT ON' : 'BOT OFF',
                style: TextStyle(
                  color: _botActive ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_testMode)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _activating ? null : _toggleBot,
                  icon: _activating
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Icon(
                          _botActive ? Icons.pause : Icons.play_arrow,
                          size: 16,
                        ),
                  label: Text(
                    _activating
                        ? 'ACTIVANDO...'
                        : (_botActive ? 'DETENER BOT' : 'ACTIVAR BOT'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _botActive ? Colors.redAccent : Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primarySpark.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(color: AppColors.primarySpark, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildOfferCard(_TestOffer offer, double cardWidth) {
    return Semantics(
      container: true,
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B3E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: offer.color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('\$${offer.price}',
                    style: TextStyle(
                      color: offer.color,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    )),
                Semantics(
                  label: 'chevron_${offer.label}',
                  child: IconButton(
                    icon: Icon(Icons.chevron_right, color: offer.color, size: 28),
                    onPressed: () {
                      _addLog("▶️ Chevron '${offer.label}' presionado manualmente");
                      setState(() => _lastChevronTapped = offer.label);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text('${offer.distance} mi',
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const Spacer(),
                Icon(Icons.store, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text('#${offer.store}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: offer.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(offer.type,
                  style: TextStyle(color: offer.color, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            if (offer.badge != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(offer.badge!,
                    style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
            const SizedBox(height: 10),
            Semantics(
              label: 'accept_${offer.label}',
              button: true,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _acceptOffer(offer.label),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.25),
                    foregroundColor: Colors.greenAccent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('ACEPTAR',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownSection(double cardWidth) {
    return Semantics(
      container: true,
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B3E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    const Text('OFERTA CON TEMPORIZADOR',
                        style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_countdownSeconds > 0)
                  Text('0:${_countdownSeconds.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'disponible en 0:05',
              style: TextStyle(color: Colors.amber, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _countdownTimer != null ? null : _simularCountdown,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.withValues(alpha: 0.2),
                  foregroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                  _countdownTimer != null ? 'CONTANDO...' : 'INICIAR COUNTDOWN',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptButton(double cardWidth) {
    return Semantics(
      container: true,
      button: true,
      child: SizedBox(
        width: cardWidth,
        child: ElevatedButton(
          onPressed: () {
            setState(() => _acceptClicked = true);
            _addLog("✅ ACEPTAR presionado manualmente — el bot debería detectarlo");
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _acceptClicked ? Colors.green : AppColors.primarySpark,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            _acceptClicked ? '✅ ¡ACEPTADO!' : 'ACEPTAR',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildLogConsole() {
    return Container(
      width: double.infinity,
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.white.withValues(alpha: 0.03),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.greenAccent, size: 14),
                const SizedBox(width: 6),
                const Text('LOGS DEL BOT',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_logs.length} líneas',
                    style: const TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Activa el modo prueba y el bot para ver logs',
                      style: TextStyle(color: Colors.white24, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, i) {
                      final log = _logs[i];
                      Color textColor = Colors.greenAccent;
                      if (log.contains('❌')) textColor = Colors.redAccent;
                      else if (log.contains('✅') || log.contains('🎯') || log.contains('⚡')) textColor = Colors.greenAccent;
                      else if (log.contains('⚠️') || log.contains('⏳')) textColor = Colors.orangeAccent;
                      else if (log.contains('🛑') || log.contains('💀')) textColor = Colors.redAccent;
                      else if (log.contains('🧪')) textColor = Colors.orangeAccent;
                      else if (log.contains('📜')) textColor = Colors.cyanAccent;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          log,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TestOffer {
  final String label;
  final String price;
  final String distance;
  final String store;
  final String type;
  final MaterialColor color;
  final String? badge;

  const _TestOffer({
    required this.label,
    required this.price,
    required this.distance,
    required this.store,
    required this.type,
    required this.color,
    this.badge,
  });
}
