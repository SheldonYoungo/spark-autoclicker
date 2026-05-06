import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  void _showAddDriverDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

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
            onPressed: () async {
              final report = await FirebaseDiagnostics.checkHealth();
              if (mounted) {
                showDialog(
                  context: context,
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
    final bool isActive = user.status == UserStatus.active;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? AppColors.borderBlue : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.white),
                  ),
                  Text(
                    'Llave: ${user.activationKey ?? "---"} | ID: ${user.id}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDisabled),
                  ),
                ],
              ),
              Switch(
                value: isActive,
                activeColor: AppColors.primarySpark,
                onChanged: (value) {
                  _adminService.updateUserStatus(
                    user.id,
                    value ? UserStatus.active : UserStatus.inactive,
                  );
                },
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          Row(
            children: [
              const Icon(Icons.phone_android, size: 14, color: AppColors.secondaryCian),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  user.authorizedDeviceIds.isEmpty 
                    ? 'Esperando vinculación...' 
                    : 'IDs: ${user.authorizedDeviceIds.join(", ")}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.white.withOpacity(0.7)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActive ? 'ACTIVO' : 'INACTIVO',
                  style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.bold, 
                    color: isActive ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
