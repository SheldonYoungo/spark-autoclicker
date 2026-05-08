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
  final String id; // El ID único o teléfono
  final String name;
  final UserRole role;
  final UserStatus status;
  final DateTime expirationDate;
  final List<String> authorizedDeviceIds; // Slots de hardware
  final int maxSlots; // Cantidad máxima de dispositivos permitidos
  final String? activationKey; // La llave que genera el admin

  UserModel({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.expirationDate,
    required this.authorizedDeviceIds,
    this.maxSlots = 1, // Por defecto 1 slot
    this.activationKey,
  });

  bool get isActive => status == UserStatus.active && DateTime.now().isBefore(expirationDate);

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
