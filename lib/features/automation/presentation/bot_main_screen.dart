import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

class BotMainScreen extends StatelessWidget {
  const BotMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.background,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Node 47:399)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SPARK APP',
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.white,
                          ),
                        ),
                        Text(
                          'By Sheldon & Valentina',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.settings, color: AppColors.white),
                  ],
                ),
                const SizedBox(height: 32),

                // Hero Card (INIBOT) (Node 21:124)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0043AA), AppColors.background],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.borderBlue),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'INIBOT',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primarySpark,
                            ),
                          ),
                          const Icon(Icons.bolt,
                              color: AppColors.primarySpark, size: 24),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Abre el cuadro flotante y pulsa Activar seguirá revisando la pantalla hasta tomar una oferta que coincida',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tipo de orden: Compras · Recolección',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.secondaryCian,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Grid de Filtros 2x2 (Node 21:82)
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.9,
                  children: [
                    _buildFilterCard(
                      'Código de Walmart',
                      'Ingresa el código de tienda',
                      Icons.storefront,
                    ),
                    _buildFilterCard(
                      'Distancia',
                      'Define radio de búsqueda',
                      Icons.map_outlined,
                    ),
                    _buildFilterCard(
                      'Orden',
                      'Elige tipos de orden',
                      Icons.shopping_bag_outlined,
                    ),
                    _buildFilterCard(
                      'Tarifa',
                      'Monto mínimo de oferta',
                      Icons.payments_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // IA Speed Boost (Node 28:195)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primarySpark.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.speed,
                            color: AppColors.primarySpark),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Impulso de velocidad IA',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                            Text(
                              'Frecuencia de escaneo: 1x',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.secondaryCian,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Botón "Abrir Panel Flotante"
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primarySpark,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'MOSTRAR OVERLAY',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.secondaryCian, size: 32),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: AppColors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}
