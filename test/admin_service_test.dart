import 'package:flutter_test/flutter_test.dart';
import 'package:spark_autoclicker/features/admin/domain/user_model.dart';

void main() {
  group('UserModel & Expiration Logic', () {
    test('User should be inactive if current date is after expirationDate', () {
      final expiredDate = DateTime.now().subtract(const Duration(hours: 1));
      final user = UserModel(
        id: 'test',
        name: 'Test Driver',
        role: UserRole.driver,
        status: UserStatus.active,
        expirationDate: expiredDate,
        authorizedDeviceIds: [],
      );

      expect(user.isActive, isFalse);
    });

    test('User should be active if current date is before expirationDate and status is active', () {
      final validDate = DateTime.now().add(const Duration(hours: 1));
      final user = UserModel(
        id: 'test',
        name: 'Test Driver',
        role: UserRole.driver,
        status: UserStatus.active,
        expirationDate: validDate,
        authorizedDeviceIds: [],
      );

      expect(user.isActive, isTrue);
    });

    test('User should be inactive if status is pending even if date is valid', () {
      final validDate = DateTime.now().add(const Duration(hours: 1));
      final user = UserModel(
        id: 'test',
        name: 'Test Driver',
        role: UserRole.driver,
        status: UserStatus.pending,
        expirationDate: validDate,
        authorizedDeviceIds: [],
      );

      expect(user.isActive, isFalse);
    });
  });
}
