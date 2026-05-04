import 'package:shopspring_decimal/shopspring_decimal.dart';

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
  final String phone;
  final UserRole role;
  final UserStatus status;
  final DateTime expirationDate;
  final List<DeviceInfo> devices;

  UserModel({
    required this.phone,
    required this.role,
    required this.status,
    required this.expirationDate,
    this.devices = const [],
  });

  bool get isActive => status == UserStatus.active && DateTime.now().isBefore(expirationDate);

  bool get isAdmin => role == UserRole.admin;

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'role': role.name,
        'status': status.name,
        'expirationDate': expirationDate.toIso8601String(),
        'devices': devices.map((d) => d.toJson()).toList(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      phone: json['phone'],
      role: UserRole.values.byName(json['role']),
      status: UserStatus.values.byName(json['status']),
      expirationDate: DateTime.parse(json['expirationDate']),
      devices: (json['devices'] as List? ?? [])
          .map((d) => DeviceInfo.fromJson(Map<String, dynamic>.from(d)))
          .toList(),
    );
  }
}
