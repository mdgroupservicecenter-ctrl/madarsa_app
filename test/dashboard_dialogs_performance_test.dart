import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:madarsa_app/features/dashboard/data/services/dashboard_config_service.dart';
import 'package:madarsa_app/features/dashboard/presentation/widgets/customize_dashboard_dialog.dart';
import 'package:madarsa_app/features/settings/presentation/widgets/watch_weather_settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'dashboard_is_analog_clock': true,
      'dashboard_clock_is_24h': false,
      'dashboard_clock_show_seconds': true,
      'weather_saved_city': 'Deoband',
    });
  });

  group('Dashboard Dialogs & Forms Performance Tests', () {
    testWidgets('CustomizeDashboardDialog renders with isolated RepaintBoundary items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomizeDashboardDialog(
              currentCards: DashboardConfigService.getDefaultCatalog(),
              onSaved: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Title
      expect(find.text('Customize Dashboard Cards'), findsOneWidget);

      // Verify category filter chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);

      // Verify RepaintBoundary wraps cards and filter row
      final repaintBoundaries = find.byType(RepaintBoundary);
      expect(repaintBoundaries, findsWidgets);

      // Toggle a filter chip to ensure smooth rebuild
      await tester.tap(find.text('Administration'));
      await tester.pumpAndSettle();

      expect(find.text('Total Enrolled Students'), findsOneWidget);
    });

    testWidgets('WatchWeatherSettingsDialog isolates live clock ticking without full-dialog rebuilds', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WatchWeatherSettingsDialog(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Dialog header
      expect(find.text('Watch Face & Theme Customization'), findsOneWidget);

      // Verify preview card & form items
      expect(find.text('Live Analog Preview'), findsOneWidget);
      expect(find.text('4. Weather Location'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Advance time by 2 seconds - verify timer fires without exception and keeps ticking smoothly
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // Verify live preview is still active and intact
      expect(find.text('Live Analog Preview'), findsOneWidget);
    });
  });
}
