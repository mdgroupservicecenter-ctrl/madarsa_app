import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:madarsa_app/core/branding/app_branding.dart';
import 'package:madarsa_app/core/branding/app_branding_cubit.dart';
import 'package:madarsa_app/core/services/windows_system_branding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppBranding Model Tests', () {
    test('Default values are correct', () {
      const branding = AppBranding();
      expect(branding.appNameEnglish, AppBranding.defaultAppNameEnglish);
      expect(branding.appNameUrdu, AppBranding.defaultAppNameUrdu);
      expect(branding.tagline, AppBranding.defaultTagline);
      expect(branding.logoPath, isNull);
      expect(branding.hasCustomLogo, isFalse);
    });

    test('copyWith works as expected including clearLogo flag', () {
      const branding = AppBranding(
        appNameEnglish: 'Custom Madarsa',
        appNameUrdu: 'کسٹم مدرسہ',
        tagline: 'Education',
        logoPath: 'C:\\test\\logo.png',
      );

      final updated = branding.copyWith(appNameEnglish: 'New Academy');
      expect(updated.appNameEnglish, 'New Academy');
      expect(updated.logoPath, 'C:\\test\\logo.png');

      final cleared = updated.copyWith(clearLogo: true);
      expect(cleared.logoPath, isNull);
      expect(cleared.hasCustomLogo, isFalse);
    });
  });

  group('Multi-Layer ICO Generation Tests', () {
    test('Converts dummy PNG image to standard Windows multi-layer ICO with 6 mipmaps', () async {
      final tempDir = await Directory.systemTemp.createTemp('branding_test_');
      try {
        final dummyPngFile = File('${tempDir.path}\\dummy_logo.png');

        // Create a 128x128 green test image
        final testImage = img.Image(width: 128, height: 128);
        img.fill(testImage, color: img.ColorRgba8(15, 118, 110, 255));
        final pngBytes = img.encodePng(testImage);
        await dummyPngFile.writeAsBytes(pngBytes);

        expect(dummyPngFile.existsSync(), isTrue);

        // Convert to ICO using WindowsSystemBrandingService
        final icoPath = await WindowsSystemBrandingService.generateIcoFromImage(dummyPngFile.path);
        expect(icoPath, isNotNull);
        expect(File(icoPath!).existsSync(), isTrue);

        final icoBytes = await File(icoPath).readAsBytes();
        // ICO Header verification:
        // Reserved (2 bytes): 0x00 0x00
        // Type (2 bytes): 0x01 0x00 (1 for icon)
        // Image Count (2 bytes): 6 images (16, 32, 48, 64, 128, 256)
        expect(icoBytes.length, greaterThan(100));
        expect(icoBytes[0], 0);
        expect(icoBytes[1], 0);
        expect(icoBytes[2], 1);
        expect(icoBytes[3], 0);
        expect(icoBytes[4], 6); // 6 layers
        expect(icoBytes[5], 0);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('AppBrandingCubit State Management Tests', () {
    test('Load, update, remove logo, and resetToDefaults work accurately', () async {
      final cubit = AppBrandingCubit();

      // Initial state
      expect(cubit.state.appNameEnglish, AppBranding.defaultAppNameEnglish);

      // Update name and tagline
      final updated = await cubit.updateBranding(
        nameEn: 'Jamia Darul Uloom',
        nameUr: 'جامعہ دار العلوم',
        tagline: 'Center of Excellence',
      );
      expect(updated, isTrue);
      expect(cubit.state.appNameEnglish, 'Jamia Darul Uloom');
      expect(cubit.state.appNameUrdu, 'جامعہ دار العلوم');
      expect(cubit.state.tagline, 'Center of Excellence');

      // Reset to defaults
      await cubit.resetToDefaults();
      expect(cubit.state.appNameEnglish, AppBranding.defaultAppNameEnglish);
      expect(cubit.state.appNameUrdu, AppBranding.defaultAppNameUrdu);
      expect(cubit.state.tagline, AppBranding.defaultTagline);
      expect(cubit.state.logoPath, isNull);

      await cubit.close();
    });
  });
}
