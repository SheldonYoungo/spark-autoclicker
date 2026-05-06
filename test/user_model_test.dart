import 'package:flutter_test/flutter_test.dart';
import 'package:spark_autoclicker/features/admin/domain/user_model.dart';

void main() {
  group('UserModel Business Logic Tests', () {
    test('Should return isActive true when status is active and date is in future', () {
      final user = UserModel(
        id: 'test',
        name: 'Test User',
        role: UserRole.driver,
        status: UserStatus.active,
        expirationDate: DateTime.now().add(const Duration(days: 1)),
        authorizedDeviceIds: [],
      );

      expect(user.isActive, isTrue);
    });

    test('Should return isActive false when status is inactive', () {
      final user = UserModel(
        id: 'test',
        name: 'Test User',
        role: UserRole.driver,
        status: UserStatus.inactive,
        expirationDate: DateTime.now().add(const Duration(days: 1)),
        authorizedDeviceIds: [],
      );

      expect(user.isActive, isFalse);
    });

    test('Should return isActive false when expiration date has passed', () {
      final user = UserModel(
        id: 'test',
        name: 'Test User',
        role: UserRole.driver,
        status: UserStatus.active,
        expirationDate: DateTime.now().subtract(const Duration(days: 1)),
        authorizedDeviceIds: [],
      );

      expect(user.isActive, isFalse);
    });

    test('UserModel should correctly serialize to/from JSON', () {
      final user = UserModel(
        id: '123',
        name: 'Sheldon',
        role: UserRole.admin,
        status: UserStatus.active,
        expirationDate: DateTime(2026, 12, 31),
        authorizedDeviceIds: ['DEVICE-001'],
        activationKey: '9999',
      );

      final json = user.toJson();
      final fromJson = UserModel.fromJson(json);

      expect(fromJson.id, user.id);
      expect(fromJson.name, user.name);
      expect(fromJson.role, user.role);
      expect(fromJson.status, user.status);
      expect(fromJson.authorizedDeviceIds, user.authorizedDeviceIds);
      expect(fromJson.activationKey, user.activationKey);
    });
  });
}
