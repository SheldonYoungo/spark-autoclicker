import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/user_model.dart';
import '../../../main.dart'; // Para cerrar sesión volviendo al Login

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Datos dummy para visualizar el diseño (luego vendrán de Firebase)
  final List<UserModel> _users = [
    UserModel(
      id: '1',
      name: 'Valentina Paredes',
      role: UserRole.driver,
      status: UserStatus.active,
      expirationDate: DateTime.now().add(const Duration(days: 30)),
      authorizedDeviceIds: ['HUA-9923-X'],
      activationKey: '1234',
    ),
    UserModel(
      id: '2',
      name: 'Pedro Chofer',
      role: UserRole.driver,
      status: UserStatus.inactive,
      expirationDate: DateTime.now().subtract(const Duration(days: 1)),
      authorizedDeviceIds: ['SAM-1102-Y'],
      activationKey: '5678',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'PANEL DE CONTROL',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/');
            },
            icon: const Icon(Icons.logout, color: AppColors.primarySpark),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, Sheldon',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primarySpark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tienes ${_users.length} conductores registrados',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.secondaryCian,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return _buildUserCard(user);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primarySpark,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () {
          // TODO: Abrir modal de nuevo usuario
        },
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
        border: Border.all(
          color: isActive ? AppColors.borderBlue : Colors.white10,
        ),
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
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                  Text(
                    'Llave: ${user.activationKey ?? "---"}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textDisabled,
                    ),
                  ),
                ],
              ),
              Switch(
                value: isActive,
                activeColor: AppColors.primarySpark,
                onChanged: (value) {
                  // TODO: Actualizar estado en Firebase
                },
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          Row(
            children: [
              Icon(Icons.phone_android, size: 14, color: AppColors.secondaryCian),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'IDs: ${user.authorizedDeviceIds.join(", ")}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.white.withOpacity(0.7),
                  ),
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
