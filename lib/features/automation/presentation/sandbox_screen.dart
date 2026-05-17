import 'dart:async';
import 'package:flutter/material.dart';
import 'package:spark_autoclicker/core/theme/app_theme.dart';
import 'package:spark_autoclicker/core/utils/accessibility_util.dart';

class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  bool _isPressed = false;
  int _heartbeat = 0;
  Timer? _timer;
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AccessibilityUtil.initNativeLogger((log) {
      if (mounted) {
        setState(() {
          _logs.add("[${DateTime.now().toString().split(' ')[1].split('.')[0]}] $log");
          if (_logs.length > 50) _logs.removeAt(0);
        });
        // Auto-scroll al final
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
    // Forzamos un cambio visual cada segundo para que el AccessibilityService se dispare
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _heartbeat++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String _currentOfferText = 'Monto: \$45.50\nDistancia: 2.1 miles\nStore #7178';

  void _updateOffer(String price, String distance, String store) {
    setState(() {
      _currentOfferText = 'Monto: \$$price\nDistancia: $distance miles\nStore #$store';
      _isPressed = false;
      _logs.add(">>> OFERTA CAMBIADA: \$$price, $distance mi, #$store");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Motor Sandbox (Pruebas)', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white54),
            onPressed: () => setState(() => _logs.clear()),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1629),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.borderBlue, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'SIMULACIÓN DE OFERTA SPARK',
                        style: TextStyle(
                          color: AppColors.primarySpark,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _currentOfferText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Heartbeat (Actividad): $_heartbeat', 
                        style: const TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _offerButton('Buena', '45.50', '2.1', '7178', Colors.green),
                          _offerButton('Barata', '12.00', '1.5', '7178', Colors.orange),
                          _offerButton('Lejos', '50.00', '12.5', '7178', Colors.red),
                          _offerButton('Otra Tienda', '40.00', '2.0', '9999', Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            bool isEnabled = await AccessibilityUtil.isServiceEnabled();
                            if (!isEnabled) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Activa el servicio en Ajustes')),
                              );
                              await AccessibilityUtil.openSettings();
                              return;
                            }
                            
                            await AccessibilityUtil.updateBotConfiguration(
                              isActive: true,
                              minPrice: 20.0,
                              maxDistance: 5.0,
                              storeId: "7178",
                              orderType: "Compras",
                            );
                            
                            setState(() {
                              _logs.add(">>> CONFIGURACIÓN: >\$20.0, <5mi, Tienda #7178");
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.borderBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('1. APLICAR FILTROS (Min \$20, Max 5mi)', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _isPressed = true);
                            _logs.add(">>> EVENTO: Botón presionado físicamente");
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPressed ? Colors.green : AppColors.primarySpark,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'El bot busca la palabra "Accept"',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Consola de Logs
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _logs[index],
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerButton(String label, String p, String d, String s, Color color) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onPressed: () => _updateOffer(p, d, s),
    );
  }
}
