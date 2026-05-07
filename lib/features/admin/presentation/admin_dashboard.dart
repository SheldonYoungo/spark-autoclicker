import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';
import '../data/admin_service.dart';
import '../../../core/network/firebase_diagnostics.dart';

class AdminDashboard extends StatefulWidget {
// ... (omitting middle parts for clarity in the tool, but I must provide the exact replacement)
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AdminService _adminService = AdminService();

  void _showConfigDialog() async {
    final int currentDefault = await _adminService.getDefaultHours();
    final hoursController = TextEditingController(text: currentDefault.toString());

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Configuración Global', style: GoogleFonts.inter(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Define el tiempo de servicio predeterminado para todos los choferes nuevos.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDisabled),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hoursController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Horas predeterminadas',
                labelStyle: TextStyle(color: Colors.white70),
                suffixText: 'hrs',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark),
            onPressed: () async {
              final hours = int.tryParse(hoursController.text);
              if (hours != null) {
                await _adminService.setDefaultHours(hours);
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Guardar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showAddDriverDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final hoursController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Nuevo Conductor', style: GoogleFonts.inter(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Nombre Completo', labelStyle: TextStyle(color: Colors.white70)),
            ),
            TextField(
              controller: phoneController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Teléfono (con +)', labelStyle: TextStyle(color: Colors.white70)),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: hoursController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Horas (Opcional)',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'Dejar vacío para usar default',
                hintStyle: TextStyle(fontSize: 12, color: Colors.white24),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySpark),
            onPressed: () async {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                await _adminService.addDriver(
                  phone: phoneController.text,
                  name: nameController.text,
                  customHours: int.tryParse(hoursController.text),
                );
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Registrar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showRenewDialog(UserModel user) {
    final hoursController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Renovar Servicio', style: GoogleFonts.inter(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Se generará una nueva llave de activación para ${user.name}.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hoursController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nuevas Horas (Opcional)',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'Dejar vacío para usar default',
                hintStyle: TextStyle(fontSize: 12, color: Colors.white24),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondaryCian),
            onPressed: () async {
              await _adminService.renewDriver(
                user.id,
                customHours: int.tryParse(hoursController.text),
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Renovar y Generar Llave', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Eliminar Conductor', style: GoogleFonts.inter(color: Colors.white)),
        content: Text(
          '¿Estás seguro de que deseas eliminar a ${user.name}? Esta acción no se puede deshacer.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _adminService.deleteUser(user.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareToWhatsApp(UserModel user) async {
    final String phone = user.id.replaceAll('_', ''); // Revertimos la sanitización básica
    final String message = 
      "🚀 *Spark Autoclicker - Acceso Activado*\n\n"
      "Hola *${user.name}*, tu acceso al bot ha sido configurado:\n\n"
      "🔑 *Tu Llave:* ${user.activationKey}\n"
      "📅 *Vence:* ${DateFormat('dd/MM/yyyy HH:mm').format(user.expirationDate)}\n\n"
      "Instrucciones:\n"
      "1. Abre la app Spark Autoclicker.\n"
      "2. Inicia sesión con tu número.\n"
      "3. Ingresa la llave arriba cuando se te solicite.";

    final Uri whatsappUrl = Uri.parse("https://wa.me/$phone?text=${Uri.encodeComponent(message)}");
    
    if (await canLaunchUrl(whatsappUrl)) {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'PANEL DE CONTROL',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.white),
        ),
        actions: [
          IconButton(
            onPressed: _showConfigDialog,
            icon: const Icon(Icons.settings, color: AppColors.white),
          ),
          IconButton(
            onPressed: () async {
              final report = await FirebaseDiagnostics.checkHealth();
              if (mounted) {
                showDialog(
                  context: this.context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.background,
                    title: const Text('Diagnóstico Firebase', style: TextStyle(color: Colors.white)),
                    content: Text(
                      'Auth: ${report['auth_status']}\n'
                      'Lectura: ${report['database_read']}\n'
                      'Escritura: ${report['database_write']}\n'
                      'Error: ${report['error'] ?? 'Ninguno'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                    ],
                  ),
                );
              }
            },
            icon: const Icon(Icons.health_and_safety, color: AppColors.secondaryCian),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
            icon: const Icon(Icons.logout, color: AppColors.primarySpark),
          ),
        ],
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: _adminService.getUsersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primarySpark));
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }

          final users = snapshot.data?.where((u) => u.role == UserRole.driver).toList() ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hola, Sheldon',
                      style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primarySpark),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tienes ${users.length} conductores registrados',
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.secondaryCian),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    return _buildUserCard(users[index]);
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primarySpark,
        onPressed: _showAddDriverDialog,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final bool isExpired = DateTime.now().isAfter(user.expirationDate);
    final bool isActive = user.status == UserStatus.active && !isExpired;
    final String formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(user.expirationDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpired 
            ? Colors.red.withValues(alpha: 0.5) 
            : (isActive ? AppColors.borderBlue : Colors.white10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: GoogleFonts.inter(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold, 
                        color: AppColors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (user.activationKey != null) {
                              Clipboard.setData(ClipboardData(text: user.activationKey!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Llave ${user.activationKey} copiada'),
                                  duration: const Duration(seconds: 1),
                                  backgroundColor: AppColors.secondaryCian,
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primarySpark.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.primarySpark.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'LLAVE: ${user.activationKey ?? "---"}',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 13, 
                                    fontWeight: FontWeight.bold, 
                                    color: AppColors.primarySpark,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy, size: 12, color: AppColors.primarySpark),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ID: ${user.id}',
                          style: GoogleFonts.inter(fontSize: 11, color: AppColors.textDisabled),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Switch(
                    value: user.status == UserStatus.active,
                    activeThumbColor: AppColors.primarySpark,
                    onChanged: (value) {
                      _adminService.updateUserStatus(
                        user.id,
                        value ? UserStatus.active : UserStatus.inactive,
                      );
                    },
                  ),
                  Text(
                    isExpired ? 'EXPIRADO' : (isActive ? 'ACTIVO' : 'INACTIVO'),
                    style: TextStyle(
                      fontSize: 9, 
                      fontWeight: FontWeight.bold, 
                      color: isExpired ? Colors.red : (isActive ? Colors.green : Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: AppColors.secondaryCian),
                  const SizedBox(width: 8),
                  Text(
                    'Vence: $formattedDate',
                    style: GoogleFonts.inter(
                      fontSize: 12, 
                      color: isExpired ? Colors.red : AppColors.white.withOpacity(0.7),
                      fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone_android, size: 14, color: AppColors.secondaryCian),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.authorizedDeviceIds.isEmpty 
                        ? 'Esperando vinculación...' 
                        : 'ID: ${user.authorizedDeviceIds.first}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.white.withOpacity(0.5)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => _shareToWhatsApp(user),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                      foregroundColor: Colors.green,
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.share, size: 18),
                    tooltip: 'Enviar por WhatsApp',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _showDeleteDialog(user),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Eliminar Conductor',
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showRenewDialog(user),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondaryCian.withValues(alpha: 0.2),
                      foregroundColor: AppColors.secondaryCian,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Renovar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
