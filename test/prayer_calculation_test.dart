import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:madarsa_app/core/services/prayer_calculation_engine.dart';
import 'package:madarsa_app/core/services/salat_time_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Deeniyat Astronomical Prayer Calculation Tests', () {
    test('Calculates valid solar prayer times for Deoband on Equinox / Autumn', () {
      final date = DateTime(2026, 9, 20); // Sept 20
      final result = PrayerCalculationEngine.calculate(
        date: date,
        latitude: 29.6976, // Deoband
        longitude: 77.6749,
        timeZoneOffsetHours: 5.5, // IST
        method: CalculationMethod.karachi,
        juristic: JuristicMethod.hanafi,
      );

      final fajrMins = result.fajr.hour * 60 + result.fajr.minute;
      final sunriseMins = result.sunrise.hour * 60 + result.sunrise.minute;
      final ishraqMins = result.ishraq.hour * 60 + result.ishraq.minute;
      final chaashtMins = result.chaasht.hour * 60 + result.chaasht.minute;
      final dhuhrMins = result.dhuhr.hour * 60 + result.dhuhr.minute;
      final asrMins = result.asr.hour * 60 + result.asr.minute;
      final maghribMins = result.maghrib.hour * 60 + result.maghrib.minute;
      final ishaMins = result.isha.hour * 60 + result.isha.minute;

      expect(fajrMins < sunriseMins, isTrue, reason: 'Fajr must be before Sunrise');
      expect(sunriseMins < ishraqMins, isTrue, reason: 'Ishraq must be after Sunrise');
      expect(ishraqMins < chaashtMins, isTrue, reason: 'Chaasht must be after Ishraq');
      expect(chaashtMins < dhuhrMins, isTrue, reason: 'Dhuhr must be after Chaasht');
      expect(dhuhrMins < asrMins, isTrue, reason: 'Asr must be after Dhuhr');
      expect(asrMins < maghribMins, isTrue, reason: 'Maghrib must be after Asr');
      expect(maghribMins < ishaMins, isTrue, reason: 'Isha must be after Maghrib');

      // Realistic timings for Northern India in September:
      expect(result.fajr.hour, anyOf(4, 5));
      expect(result.sunrise.hour, 6);
      expect(result.dhuhr.hour, 12);
      expect(result.asr.hour, 16);
      expect(result.maghrib.hour, 18);
      expect(result.isha.hour, 19);
    });

    test('Hanafi Asr is later than Shafi\'i Asr', () {
      final date = DateTime(2026, 9, 20);
      final hanafi = PrayerCalculationEngine.calculate(
        date: date,
        latitude: 29.6976,
        longitude: 77.6749,
        timeZoneOffsetHours: 5.5,
        juristic: JuristicMethod.hanafi,
      );
      final shafii = PrayerCalculationEngine.calculate(
        date: date,
        latitude: 29.6976,
        longitude: 77.6749,
        timeZoneOffsetHours: 5.5,
        juristic: JuristicMethod.shafii,
      );

      final hanafiMins = hanafi.asr.hour * 60 + hanafi.asr.minute;
      final shafiiMins = shafii.asr.hour * 60 + shafii.asr.minute;

      expect(hanafiMins > shafiiMins, isTrue);
      expect(hanafiMins - shafiiMins, inInclusiveRange(40, 80));
    });

    test('Changing location significantly changes prayer times between cities', () {
      final date = DateTime(2026, 9, 20);

      // 1. Deoband (Northern India, Lon: 77.67)
      final deoband = PrayerCalculationEngine.calculate(
        date: date,
        latitude: 29.6976,
        longitude: 77.6749,
        timeZoneOffsetHours: 5.5,
      );

      // 2. Kolkata (Eastern India, Lon: 88.36) - Sun rises & sets ~42 mins EARLIER than Deoband
      final kolkata = PrayerCalculationEngine.calculate(
        date: date,
        latitude: 22.5726,
        longitude: 88.3639,
        timeZoneOffsetHours: 5.5,
      );

      // 3. Mumbai (Western India, Lon: 72.88) - Sun rises & sets ~20 mins LATER than Deoband
      final mumbai = PrayerCalculationEngine.calculate(
        date: date,
        latitude: 19.0760,
        longitude: 72.8777,
        timeZoneOffsetHours: 5.5,
      );

      final deobandMaghribMins = deoband.maghrib.hour * 60 + deoband.maghrib.minute;
      final kolkataMaghribMins = kolkata.maghrib.hour * 60 + kolkata.maghrib.minute;
      final mumbaiMaghribMins = mumbai.maghrib.hour * 60 + mumbai.maghrib.minute;

      // Kolkata is east of Deoband -> sunset is earlier
      expect(kolkataMaghribMins < deobandMaghribMins, isTrue);
      expect(deobandMaghribMins - kolkataMaghribMins, inInclusiveRange(35, 55));

      // Mumbai is west of Deoband -> sunset is later
      expect(mumbaiMaghribMins > deobandMaghribMins, isTrue);
      expect(mumbaiMaghribMins - deobandMaghribMins, inInclusiveRange(10, 25));

      // Total spread between Kolkata and Mumbai in the same timezone is ~55-65 minutes
      expect(mumbaiMaghribMins - kolkataMaghribMins, inInclusiveRange(50, 75));
    });

    test('SalatTimeService changes times immediately when setting city and coordinates', () async {
      SalatTimeService.isAutoCalculation = true;

      // 1. Set to Deoband
      await SalatTimeService.setCityAndCoordinates('Deoband', 29.6976, 77.6749, tz: 5.5);
      final deobandPrayers = List.of(SalatTimeService.prayers);
      final deobandFajr = deobandPrayers.firstWhere((p) => p.id == 'fajr').azanTime;
      final deobandMaghrib = deobandPrayers.firstWhere((p) => p.id == 'maghrib').azanTime;

      // 2. Set to Kolkata
      await SalatTimeService.setCityAndCoordinates('Kolkata', 22.5726, 88.3639, tz: 5.5);
      final kolkataPrayers = List.of(SalatTimeService.prayers);
      final kolkataFajr = kolkataPrayers.firstWhere((p) => p.id == 'fajr').azanTime;
      final kolkataMaghrib = kolkataPrayers.firstWhere((p) => p.id == 'maghrib').azanTime;

      // Ensure Fajr and Maghrib times ACTUALLY CHANGED between Deoband and Kolkata
      expect(deobandFajr != kolkataFajr, isTrue);
      expect(deobandMaghrib != kolkataMaghrib, isTrue);

      final deobandFajrMins = deobandFajr.hour * 60 + deobandFajr.minute;
      final kolkataFajrMins = kolkataFajr.hour * 60 + kolkataFajr.minute;
      expect(kolkataFajrMins < deobandFajrMins, isTrue);
    });
  });
}
