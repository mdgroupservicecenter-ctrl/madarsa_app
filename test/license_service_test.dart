import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/licensing/license_model.dart';
import 'package:madarsa_app/core/licensing/license_service.dart';

void main() {
  group('Licensing System Tests', () {
    test('Basic Plan Generation & Verification', () {
      final key = LicenseService.generateKey(
        institutionName: 'Madarsa Faiz-e-Aam',
        tier: SubscriptionTier.basic,
        validityDays: 365,
      );

      expect(key.startsWith('MDL-BASIC-'), isTrue);

      final result = LicenseService.verifyKey(key);
      expect(result.isValid, isTrue);
      expect(result.license, isNotNull);
      expect(result.license!.institutionName, equals('Madarsa Faiz-e-Aam'));
      expect(result.license!.tier, equals(SubscriptionTier.basic));
      expect(result.license!.isLifetime, isFalse);
      expect(result.license!.isExpired, isFalse);

      // Verify Basic module access
      expect(result.license!.hasModuleAccess('students'), isTrue);
      expect(result.license!.hasModuleAccess('attendance'), isTrue);
      expect(result.license!.hasModuleAccess('dashboard'), isTrue);

      // Verify locked modules in Basic
      expect(result.license!.hasModuleAccess('fees'), isFalse);
      expect(result.license!.hasModuleAccess('hostel'), isFalse);
      expect(result.license!.hasModuleAccess('kitchen'), isFalse);
    });

    test('Medium Plan Generation & Verification', () {
      final key = LicenseService.generateKey(
        institutionName: 'Darul Uloom Deoband',
        tier: SubscriptionTier.medium,
        validityDays: 180,
      );

      final result = LicenseService.verifyKey(key);
      expect(result.isValid, isTrue);
      expect(result.license!.tier, equals(SubscriptionTier.medium));

      // Medium modules accessible
      expect(result.license!.hasModuleAccess('students'), isTrue);
      expect(result.license!.hasModuleAccess('fees'), isTrue);
      expect(result.license!.hasModuleAccess('exams'), isTrue);
      expect(result.license!.hasModuleAccess('classes'), isTrue);

      // Pro modules still locked in Medium
      expect(result.license!.hasModuleAccess('hostel'), isFalse);
      expect(result.license!.hasModuleAccess('kitchen'), isFalse);
      expect(result.license!.hasModuleAccess('library'), isFalse);
    });

    test('Lifetime Plan Generation & Verification', () {
      final key = LicenseService.generateKey(
        institutionName: 'Jamia Islamia',
        tier: SubscriptionTier.lifetime,
      );

      final result = LicenseService.verifyKey(key);
      expect(result.isValid, isTrue);
      expect(result.license!.tier, equals(SubscriptionTier.lifetime));
      expect(result.license!.isLifetime, isTrue);
      expect(result.license!.isExpired, isFalse);
      expect(result.license!.daysRemaining, greaterThan(1000));

      // All 15 modules accessible
      for (final mod in SubscriptionTier.pro.defaultModules) {
        expect(result.license!.hasModuleAccess(mod), isTrue);
      }
    });

    test('Anti-Tampering Security Check', () {
      final validKey = LicenseService.generateKey(
        institutionName: 'Authentic Madarsa',
        tier: SubscriptionTier.pro,
        validityDays: 365,
      );

      // Tamper with key signature
      final tamperedKey = '${validKey.substring(0, validKey.length - 3)}XYZ';
      final tamperedResult = LicenseService.verifyKey(tamperedKey);

      expect(tamperedResult.isValid, isFalse);
      expect(tamperedResult.license, isNull);
    });
  });
}
