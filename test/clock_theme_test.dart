import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:madarsa_app/core/services/clock_theme_service.dart';
import 'package:madarsa_app/features/dashboard/presentation/widgets/analog_clock_painter.dart';
import 'package:madarsa_app/features/dashboard/presentation/widgets/digital_clock_painter.dart';
import 'package:madarsa_app/features/dashboard/presentation/widgets/dashboard_watch_weather_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ClockThemeService Tests (14 Curated Designs & Dynamic Card Theming)', () {
    test('Analog designs list contains 8 curated watch faces including Rose Gold Skeleton and MOP Moonphase', () {
      expect(ClockThemeService.analogDesigns.length, 8);
      final ids = ClockThemeService.analogDesigns.map((d) => d.id).toSet();
      expect(ids.length, 8);
      expect(ClockThemeService.analogDesigns.first.id, 'analog_military_chrono_md');
      expect(ids.contains('analog_rosegold_black_skeleton'), isTrue);
      expect(ids.contains('analog_moonphase_pearl_gold'), isTrue);

      for (final d in ClockThemeService.analogDesigns) {
        expect(d.name, isNotEmpty);
        expect(d.urduName, isNotEmpty);
        expect(d.description, isNotEmpty);
        expect(d.isDigital, isFalse);
        // Verify card theming properties are non-null
        expect(d.cardBgLight, isNotNull);
        expect(d.cardBgDark, isNotNull);
        expect(d.cardBorderColor, isNotNull);
        expect(d.cardShadowColor, isNotNull);
        expect(d.primaryColor, isNotNull);
        expect(d.accentColor, isNotNull);
        expect(d.textColorLight, isNotNull);
        expect(d.textColorDark, isNotNull);
      }
    });

    test('Digital designs list contains 8 curated display themes with card theming', () {
      expect(ClockThemeService.digitalDesigns.length, 8);
      final ids = ClockThemeService.digitalDesigns.map((d) => d.id).toSet();
      expect(ids.length, 8);
      expect(ClockThemeService.digitalDesigns.first.id, 'digital_dot_matrix_white');
      expect(ids.contains('digital_cyan_weather_schedule'), isTrue);
      expect(ids.contains('digital_amber_nixie_tube'), isTrue);
      expect(ids.contains('digital_emerald_gold_lcd'), isTrue);
      expect(ids.contains('digital_crimson_carbon_matrix'), isTrue);
      expect(ids.contains('digital_monochrome_bauhaus'), isTrue);
      expect(ids.contains('digital_cyber_violet_neon'), isTrue);
      expect(ids.contains('digital_ice_blue_crystal'), isTrue);

      for (final d in ClockThemeService.digitalDesigns) {
        expect(d.name, isNotEmpty);
        expect(d.urduName, isNotEmpty);
        expect(d.description, isNotEmpty);
        expect(d.isDigital, isTrue);
        // Verify card theming properties are non-null
        expect(d.cardBgLight, isNotNull);
        expect(d.cardBgDark, isNotNull);
        expect(d.cardBorderColor, isNotNull);
        expect(d.cardShadowColor, isNotNull);
        expect(d.primaryColor, isNotNull);
        expect(d.accentColor, isNotNull);
        expect(d.textColorLight, isNotNull);
        expect(d.textColorDark, isNotNull);
      }
    });

    test('Total curated designs count is 16', () {
      expect(ClockThemeService.designs.length, 16);
    });

    test('getDesignsForMode returns expected designs for both analog and digital modes', () {
      final analogList = ClockThemeService.getDesignsForMode(true);
      expect(analogList.length, 8);
      expect(analogList.first.id, 'analog_military_chrono_md');

      final digitalList = ClockThemeService.getDesignsForMode(false);
      expect(digitalList.length, 8);
      expect(digitalList.first.id, 'digital_dot_matrix_white');
    });

    test('Loads defaults and updates analog and digital designs with persistence', () async {
      await ClockThemeService.init();

      expect(ClockThemeService.currentAnalogDesign.id, 'analog_military_chrono_md');
      expect(ClockThemeService.currentDigitalDesign.id, 'digital_dot_matrix_white');

      // Change analog design to emerald leaf & code
      await ClockThemeService.setAnalogDesign('analog_emerald_leaf_code');
      expect(ClockThemeService.currentAnalogDesign.id, 'analog_emerald_leaf_code');

      // Change digital design to cyan dual dashboard
      await ClockThemeService.setDigitalDesign('digital_cyan_weather_schedule');
      expect(ClockThemeService.currentDigitalDesign.id, 'digital_cyan_weather_schedule');

      // Check active design by mode
      expect(ClockThemeService.getActiveDesign(true).id, 'analog_emerald_leaf_code');
      expect(ClockThemeService.getActiveDesign(false).id, 'digital_cyan_weather_schedule');

      // Reload from SharedPreferences to ensure persistence
      await ClockThemeService.init();
      expect(ClockThemeService.currentAnalogDesign.id, 'analog_emerald_leaf_code');
      expect(ClockThemeService.currentDigitalDesign.id, 'digital_cyan_weather_schedule');
    });
  });

  group('ClockPainter Multi-Design Rendering Tests', () {
    test('Paints all analog clock designs in light and dark modes without errors', () {
      final now = DateTime(2026, 9, 20, 14, 35, 20, 500);

      for (final design in ClockThemeService.analogDesigns) {
        final theme = ClockTheme.fromDesign(design);
        for (final isDark in [false, true]) {
          final painter = AnalogClockPainter(
            dateTime: now,
            isDark: isDark,
            design: design,
            theme: theme,
          );

          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          const size = Size(100, 100);

          // Must paint cleanly without throwing any exceptions at standard and enlarged size
          expect(() => painter.paint(canvas, size), returnsNormally);

          const enlargedSize = Size(146, 146);
          expect(() => painter.paint(canvas, enlargedSize), returnsNormally);

          final picture = recorder.endRecording();
          picture.dispose();
        }
      }
    });

    test('Paints all digital clock designs in 12h and 24h modes without errors', () {
      final now = DateTime(2026, 9, 21, 12, 38, 45);

      for (final design in ClockThemeService.digitalDesigns) {
        for (final is24h in [false, true]) {
          for (final showSecs in [false, true]) {
            final painter = DigitalClockPainter(
              dateTime: now,
              isDark: true,
              design: design,
              is24Hour: is24h,
              showSeconds: showSecs,
            );

            final recorder = PictureRecorder();
            final canvas = Canvas(recorder);
            const size = Size(140, 140);

            expect(() => painter.paint(canvas, size), returnsNormally);

            const previewSize = Size(115, 115);
            expect(() => painter.paint(canvas, previewSize), returnsNormally);

            final picture = recorder.endRecording();
            picture.dispose();
          }
        }
      }
    });

    testWidgets('DigitalClockFace renders all digital clock designs with MD logo without error', (tester) async {
      final now = DateTime(2026, 9, 21, 12, 38, 45);
      for (final design in ClockThemeService.digitalDesigns) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: DigitalClockFace(
                  dateTime: now,
                  isDark: true,
                  design: design,
                  size: 140,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(DigitalClockFace), findsOneWidget);
      }
    });

    testWidgets('DashboardWatchWeatherWidget renders at banner size 395px without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 395,
                child: DashboardWatchWeatherWidget(
                  isDark: false,
                  hijriDate: '10 Rabi\' Al-Thani 1448 AH',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Clean up widget tree to trigger dispose
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('DashboardWatchWeatherWidget renders at narrow 320px without overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: DashboardWatchWeatherWidget(
                  isDark: true,
                  hijriDate: '10 Rabi\' Al-Thani 1448 AH',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  });
}

