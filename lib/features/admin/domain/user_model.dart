enum UserRole { admin, driver }

enum UserStatus { active, inactive, pending }

class DeviceInfo {
  final String id;
  final String model;
  final DateTime lastLogin;

  DeviceInfo({
    required this.id,
    required this.model,
    required this.lastLogin,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'model': model,
        'lastLogin': lastLogin.toIso8601String(),
      };

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id'],
        model: json['model'],
        lastLogin: DateTime.parse(json['lastLogin']),
      );
}

class UserModel {
  final String id;
  final String name;
  final UserRole role;
  final UserStatus status;
  final DateTime expirationDate;
  final List<String> authorizedDeviceIds;
  final int maxSlots;
  final String? activationKey;

  UserModel({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.expirationDate,
    required this.authorizedDeviceIds,
    this.maxSlots = 1,
    this.activationKey,
  });

  /// Verifica si el estado del usuario es activo. 
  /// NOTA: No valida expiración vía NTP. Usar ActivationService para validación de seguridad.
  bool get isActive => status == UserStatus.active;

  bool get isAdmin => role == UserRole.admin;

  bool get hasAvailableSlots => authorizedDeviceIds.length < maxSlots;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'status': status.name,
        'expirationDate': expirationDate.toIso8601String(),
        'authorizedDeviceIds': authorizedDeviceIds,
        'maxSlots': maxSlots,
        'activationKey': activationKey,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      name: json['name'] ?? '',
      role: UserRole.values.byName(json['role']),
      status: UserStatus.values.byName(json['status']),
      expirationDate: DateTime.parse(json['expirationDate']),
      authorizedDeviceIds: List<String>.from(json['authorizedDeviceIds'] ?? []),
      maxSlots: json['maxSlots'] ?? 1,
      activationKey: json['activationKey'],
    );
  }
}
