import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'prayer_calculation_engine.dart';

class SalatPrayer {
  final String id;
  final String name;
  final String urduName;
  final String arabicName;
  TimeOfDay azanTime;
  TimeOfDay jamatTime;
  final IconData icon;
  final bool isPrayer; // false for sunrise/ishraq

  SalatPrayer({
    required this.id,
    required this.name,
    required this.urduName,
    required this.arabicName,
    required this.azanTime,
    required this.jamatTime,
    required this.icon,
    this.isPrayer = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'urduName': urduName,
        'arabicName': arabicName,
        'azanHour': azanTime.hour,
        'azanMinute': azanTime.minute,
        'jamatHour': jamatTime.hour,
        'jamatMinute': jamatTime.minute,
        'isPrayer': isPrayer,
      };

  factory SalatPrayer.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return SalatPrayer(
      id: id,
      name: json['name'] as String,
      urduName: json['urduName'] as String,
      arabicName: json['arabicName'] as String,
      azanTime: TimeOfDay(
        hour: json['azanHour'] as int? ?? 5,
        minute: json['azanMinute'] as int? ?? 0,
      ),
      jamatTime: TimeOfDay(
        hour: json['jamatHour'] as int? ?? 5,
        minute: json['jamatMinute'] as int? ?? 30,
      ),
      icon: _getIconForPrayer(id),
      isPrayer: json['isPrayer'] as bool? ?? true,
    );
  }

  static IconData _getIconForPrayer(String id) {
    switch (id) {
      case 'fajr':
        return Icons.nights_stay_rounded;
      case 'sunrise':
        return Icons.wb_twilight_rounded;
      case 'dhuhr':
        return Icons.wb_sunny_rounded;
      case 'asr':
        return Icons.wb_cloudy_rounded;
      case 'maghrib':
        return Icons.wb_twilight_rounded;
      case 'isha':
        return Icons.nightlight_round;
      case 'jummah':
        return Icons.mosque_rounded;
      default:
        return Icons.access_time_filled_rounded;
    }
  }
}

class NextPrayerInfo {
  final SalatPrayer prayer;
  final Duration timeRemaining;
  final bool isJamatNext;

  const NextPrayerInfo({
    required this.prayer,
    required this.timeRemaining,
    required this.isJamatNext,
  });
}

class CityCoordinate {
  final String name;
  final String urduName;
  final double latitude;
  final double longitude;
  final double timeZone;

  const CityCoordinate(
    this.name,
    this.urduName,
    this.latitude,
    this.longitude, [
    this.timeZone = 5.5,
  ]);
}

class SalatTimeService {
  static const _prefKey = 'madarsa_salat_timings_v2';
  static const _isAutoKey = 'salat_is_auto_calc';
  static const _methodKey = 'salat_calc_method';
  static const _juristicKey = 'salat_juristic_method';
  static const _cityKey = 'salat_city_name';
  static const _latKey = 'salat_lat';
  static const _lonKey = 'salat_lon';
  static const _tzKey = 'salat_timezone';
  static const _jamatModeKey = 'salat_jamat_mode';
  static const _jamatOffsetsKey = 'salat_jamat_offsets';
  static const _adjustmentsKey = 'salat_minute_adjustments';

  // Comprehensive Standard Cities Preset
  static const List<CityCoordinate> standardCities = [
    CityCoordinate('Deoband', 'دیوبند', 29.6976, 77.6749, 5.5),
    CityCoordinate('Saharanpur', 'سہارنپور', 29.9640, 77.5460, 5.5),
    CityCoordinate('Muzaffarnagar', 'مظفر نگر', 29.4727, 77.7085, 5.5),
    CityCoordinate('Meerut', 'میرٹھ', 28.9845, 77.7064, 5.5),
    CityCoordinate('Delhi', 'دہلی', 28.6139, 77.2090, 5.5),
    CityCoordinate('Lucknow', 'لکھنؤ', 26.8467, 80.9462, 5.5),
    CityCoordinate('Kanpur', 'کانپور', 26.4499, 80.3319, 5.5),
    CityCoordinate('Bareilly', 'بریلی', 28.3670, 79.4304, 5.5),
    CityCoordinate('Aligarh', 'علی گڑھ', 27.8974, 78.0880, 5.5),
    CityCoordinate('Moradabad', 'مرادآباد', 28.8386, 78.7733, 5.5),
    CityCoordinate('Agra', 'آگرہ', 27.1767, 78.0081, 5.5),
    CityCoordinate('Varanasi', 'وارانسی', 25.3176, 82.9739, 5.5),
    CityCoordinate('Mumbai', 'ممبئی', 19.0760, 72.8777, 5.5),
    CityCoordinate('Pune', 'پونے', 18.5204, 73.8567, 5.5),
    CityCoordinate('Hyderabad', 'حیدرآباد', 17.3850, 78.4867, 5.5),
    CityCoordinate('Bengaluru', 'بنگلور', 12.9716, 77.5946, 5.5),
    CityCoordinate('Chennai', 'چنئی', 13.0827, 80.2707, 5.5),
    CityCoordinate('Kolkata', 'کولکاتہ', 22.5726, 88.3639, 5.5),
    CityCoordinate('Ahmedabad', 'احمد آباد', 23.0225, 72.5714, 5.5),
    CityCoordinate('Surat', 'سورت', 21.1702, 72.8311, 5.5),
    CityCoordinate('Bhopal', 'بھوپال', 23.2599, 77.4126, 5.5),
    CityCoordinate('Patna', 'پٹنہ', 25.5941, 85.1376, 5.5),
    CityCoordinate('Srinagar', 'سری نگر', 34.0837, 74.7973, 5.5),
    CityCoordinate('Jaipur', 'جے پور', 26.9124, 75.7873, 5.5),
    CityCoordinate('Guwahati', 'گوہاٹی', 26.1445, 91.7362, 5.5),
    CityCoordinate('Karachi', 'کراچی', 24.8607, 67.0011, 5.0),
    CityCoordinate('Lahore', 'لاہور', 31.5204, 74.3587, 5.0),
    CityCoordinate('Islamabad', 'اسلام آباد', 33.6844, 73.0479, 5.0),
    CityCoordinate('Peshawar', 'پشاور', 34.0151, 71.5249, 5.0),
    CityCoordinate('Dhaka', 'ڈھاکہ', 23.8103, 90.4125, 6.0),
    CityCoordinate('Chittagong', 'چٹاگانگ', 22.3569, 91.7832, 6.0),
    CityCoordinate('Makkah', 'مکہ مکرمہ', 21.4225, 39.8262, 3.0),
    CityCoordinate('Madinah', 'مدینہ منورہ', 24.5247, 39.5692, 3.0),
    CityCoordinate('Dubai', 'دبئی', 25.2048, 55.2708, 4.0),
    CityCoordinate('London', 'لندن', 51.5074, -0.1278, 0.0),
  ];

  static CityCoordinate? findPresetCity(String query) {
    final clean = query.trim().toLowerCase();
    for (final c in standardCities) {
      if (c.name.toLowerCase() == clean ||
          c.urduName.contains(clean) ||
          clean.contains(c.name.toLowerCase())) {
        return c;
      }
    }
    return null;
  }

  // Configuration Properties
  static bool isAutoCalculation = true;
  static CalculationMethod calculationMethod = CalculationMethod.karachi;
  static JuristicMethod juristicMethod = JuristicMethod.hanafi;
  static String cityName = 'Deoband';
  static double latitude = 29.6976;
  static double longitude = 77.6749;
  static double timeZone = 5.5; // IST default
  static String jamatMode = 'offset'; // 'offset' or 'fixed'

  // Default Jamat offsets in minutes after Azan
  static Map<String, int> jamatOffsets = {
    'fajr': 25,
    'dhuhr': 20,
    'asr': 15,
    'maghrib': 5,
    'isha': 20,
    'jummah': 30,
  };

  // Fine-tuning adjustments (-30 to +30 minutes)
  static Map<String, int> minuteAdjustments = {
    'fajr': 0,
    'sunrise': 0,
    'dhuhr': 0,
    'asr': 0,
    'maghrib': 0,
    'isha': 0,
  };

  static List<SalatPrayer> get defaultPrayers => [
        SalatPrayer(
          id: 'fajr',
          name: 'Fajr',
          urduName: 'فجر',
          arabicName: 'الفجر',
          azanTime: const TimeOfDay(hour: 5, minute: 0),
          jamatTime: const TimeOfDay(hour: 5, minute: 25),
          icon: Icons.nights_stay_rounded,
        ),
        SalatPrayer(
          id: 'sunrise',
          name: 'Sunrise / Ishraq',
          urduName: 'اشراق / طلوع آفتاب',
          arabicName: 'الشروق',
          azanTime: const TimeOfDay(hour: 6, minute: 15),
          jamatTime: const TimeOfDay(hour: 6, minute: 30),
          icon: Icons.wb_twilight_rounded,
          isPrayer: false,
        ),
        SalatPrayer(
          id: 'dhuhr',
          name: 'Dhuhr',
          urduName: 'ظہر',
          arabicName: 'الظهر',
          azanTime: const TimeOfDay(hour: 12, minute: 30),
          jamatTime: const TimeOfDay(hour: 12, minute: 50),
          icon: Icons.wb_sunny_rounded,
        ),
        SalatPrayer(
          id: 'asr',
          name: 'Asr',
          urduName: 'عصر',
          arabicName: 'العصر',
          azanTime: const TimeOfDay(hour: 16, minute: 30),
          jamatTime: const TimeOfDay(hour: 16, minute: 45),
          icon: Icons.wb_cloudy_rounded,
        ),
        SalatPrayer(
          id: 'maghrib',
          name: 'Maghrib',
          urduName: 'مغرب',
          arabicName: 'المغرب',
          azanTime: const TimeOfDay(hour: 18, minute: 20),
          jamatTime: const TimeOfDay(hour: 18, minute: 25),
          icon: Icons.wb_twilight_rounded,
        ),
        SalatPrayer(
          id: 'isha',
          name: 'Isha',
          urduName: 'عشاء',
          arabicName: 'العشاء',
          azanTime: const TimeOfDay(hour: 19, minute: 45),
          jamatTime: const TimeOfDay(hour: 20, minute: 5),
          icon: Icons.nightlight_round,
        ),
        SalatPrayer(
          id: 'jummah',
          name: 'Jummah',
          urduName: 'جمعہ',
          arabicName: 'الجمعة',
          azanTime: const TimeOfDay(hour: 12, minute: 30),
          jamatTime: const TimeOfDay(hour: 13, minute: 0),
          icon: Icons.mosque_rounded,
        ),
      ];

  static final ValueNotifier<List<SalatPrayer>> prayersNotifier =
      ValueNotifier<List<SalatPrayer>>(defaultPrayers);

  static List<SalatPrayer> get prayers => prayersNotifier.value;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    isAutoCalculation = prefs.getBool(_isAutoKey) ?? true;
    calculationMethod = CalculationMethod.fromId(prefs.getString(_methodKey) ?? 'karachi');
    juristicMethod = JuristicMethod.fromId(prefs.getString(_juristicKey) ?? 'Hanafi');
    cityName = prefs.getString(_cityKey) ?? prefs.getString('dashboard_weather_city') ?? 'Deoband';
    latitude = prefs.getDouble(_latKey) ?? prefs.getDouble('dashboard_weather_lat') ?? 29.6976;
    longitude = prefs.getDouble(_lonKey) ?? prefs.getDouble('dashboard_weather_lon') ?? 77.6749;
    timeZone = prefs.getDouble(_tzKey) ?? 5.5;
    jamatMode = prefs.getString(_jamatModeKey) ?? 'offset';

    final offsetsRaw = prefs.getString(_jamatOffsetsKey);
    if (offsetsRaw != null) {
      try {
        final map = jsonDecode(offsetsRaw) as Map<String, dynamic>;
        jamatOffsets = map.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }

    final adjRaw = prefs.getString(_adjustmentsKey);
    if (adjRaw != null) {
      try {
        final map = jsonDecode(adjRaw) as Map<String, dynamic>;
        minuteAdjustments = map.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }

    if (isAutoCalculation) {
      recalculateForDate(DateTime.now());
    } else {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = jsonDecode(raw) as List;
          final loaded = list.map((item) => SalatPrayer.fromJson(item as Map<String, dynamic>)).toList();
          prayersNotifier.value = loaded;
          return;
        } catch (_) {}
      }
      prayersNotifier.value = defaultPrayers;
    }
  }

  /// Calculates astronomical times for a specific date and returns full schedule
  static CalculatedPrayerTimes getExtendedDailySchedule([DateTime? date]) {
    final dt = date ?? DateTime.now();
    return PrayerCalculationEngine.calculate(
      date: dt,
      latitude: latitude,
      longitude: longitude,
      timeZoneOffsetHours: timeZone,
      method: calculationMethod,
      juristic: juristicMethod,
      minuteAdjustments: minuteAdjustments,
    );
  }

  static DateTime? _lastRecalculatedDay;

  /// Recalculates prayer times for given date and updates `prayersNotifier`
  static void recalculateForDate(DateTime date, {bool force = false}) {
    if (!force &&
        _lastRecalculatedDay != null &&
        _lastRecalculatedDay!.year == date.year &&
        _lastRecalculatedDay!.month == date.month &&
        _lastRecalculatedDay!.day == date.day) {
      return;
    }
    _lastRecalculatedDay = DateTime(date.year, date.month, date.day);

    final calc = getExtendedDailySchedule(date);

    TimeOfDay calculateJamat(String prayerId, TimeOfDay azanTime, TimeOfDay fallback) {
      if (jamatMode == 'fixed') {
        final existing = prayers.firstWhere((p) => p.id == prayerId, orElse: () => defaultPrayers.firstWhere((p) => p.id == prayerId));
        return existing.jamatTime;
      }
      final offset = jamatOffsets[prayerId] ?? 20;
      return addMinutes(azanTime, offset);
    }

    final updated = [
      SalatPrayer(
        id: 'fajr',
        name: 'Fajr',
        urduName: 'فجر',
        arabicName: 'الفجر',
        azanTime: calc.fajr,
        jamatTime: calculateJamat('fajr', calc.fajr, const TimeOfDay(hour: 5, minute: 25)),
        icon: Icons.nights_stay_rounded,
      ),
      SalatPrayer(
        id: 'sunrise',
        name: 'Sunrise / Ishraq',
        urduName: 'اشراق / طلوع آفتاب',
        arabicName: 'الشروق',
        azanTime: calc.sunrise,
        jamatTime: calc.ishraq,
        icon: Icons.wb_twilight_rounded,
        isPrayer: false,
      ),
      SalatPrayer(
        id: 'dhuhr',
        name: 'Dhuhr',
        urduName: 'ظہر',
        arabicName: 'الظهر',
        azanTime: calc.dhuhr,
        jamatTime: calculateJamat('dhuhr', calc.dhuhr, const TimeOfDay(hour: 12, minute: 50)),
        icon: Icons.wb_sunny_rounded,
      ),
      SalatPrayer(
        id: 'asr',
        name: 'Asr',
        urduName: 'عصر',
        arabicName: 'العصر',
        azanTime: calc.asr,
        jamatTime: calculateJamat('asr', calc.asr, const TimeOfDay(hour: 16, minute: 45)),
        icon: Icons.wb_cloudy_rounded,
      ),
      SalatPrayer(
        id: 'maghrib',
        name: 'Maghrib',
        urduName: 'مغرب',
        arabicName: 'المغرب',
        azanTime: calc.maghrib,
        jamatTime: calculateJamat('maghrib', calc.maghrib, const TimeOfDay(hour: 18, minute: 25)),
        icon: Icons.wb_twilight_rounded,
      ),
      SalatPrayer(
        id: 'isha',
        name: 'Isha',
        urduName: 'عشاء',
        arabicName: 'العشاء',
        azanTime: calc.isha,
        jamatTime: calculateJamat('isha', calc.isha, const TimeOfDay(hour: 20, minute: 5)),
        icon: Icons.nightlight_round,
      ),
      SalatPrayer(
        id: 'jummah',
        name: 'Jummah',
        urduName: 'جمعہ',
        arabicName: 'الجمعة',
        azanTime: calc.dhuhr,
        jamatTime: calculateJamat('jummah', calc.dhuhr, const TimeOfDay(hour: 13, minute: 0)),
        icon: Icons.mosque_rounded,
      ),
    ];

    prayersNotifier.value = updated;
  }

  static TimeOfDay addMinutes(TimeOfDay time, int minutes) {
    final total = time.hour * 60 + time.minute + minutes;
    final fixedTotal = (total % 1440 + 1440) % 1440;
    return TimeOfDay(hour: fixedTotal ~/ 60, minute: fixedTotal % 60);
  }

  static Future<void> setAutoCalculation(bool enabled) async {
    isAutoCalculation = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isAutoKey, enabled);
    if (enabled) {
      recalculateForDate(DateTime.now());
    }
  }

  static Future<void> setCalculationMethod(CalculationMethod method) async {
    calculationMethod = method;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_methodKey, method.id);
    if (isAutoCalculation) {
      recalculateForDate(DateTime.now());
    }
  }

  static Future<void> setJuristicMethod(JuristicMethod juristic) async {
    juristicMethod = juristic;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_juristicKey, juristic.id);
    if (isAutoCalculation) {
      recalculateForDate(DateTime.now());
    }
  }

  static Future<void> setCityAndCoordinates(
    String city,
    double lat,
    double lon, {
    double? tz,
  }) async {
    cityName = city;
    latitude = lat;
    longitude = lon;
    if (tz != null) {
      timeZone = tz;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cityKey, city);
    await prefs.setDouble(_latKey, lat);
    await prefs.setDouble(_lonKey, lon);
    await prefs.setDouble(_tzKey, timeZone);

    // Keep weather keys unified
    await prefs.setString('dashboard_weather_city', city);
    await prefs.setDouble('dashboard_weather_lat', lat);
    await prefs.setDouble('dashboard_weather_lon', lon);

    if (isAutoCalculation) {
      recalculateForDate(DateTime.now());
    }
  }

  static Future<void> setJamatConfig({
    required String mode,
    required Map<String, int> offsets,
  }) async {
    jamatMode = mode;
    jamatOffsets = Map.from(offsets);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jamatModeKey, mode);
    await prefs.setString(_jamatOffsetsKey, jsonEncode(jamatOffsets));
    if (isAutoCalculation) {
      recalculateForDate(DateTime.now());
    }
  }

  static Future<void> setMinuteAdjustments(Map<String, int> adjustments) async {
    minuteAdjustments = Map.from(adjustments);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adjustmentsKey, jsonEncode(minuteAdjustments));
    if (isAutoCalculation) {
      recalculateForDate(DateTime.now());
    }
  }

  static Future<void> saveManualPrayers(List<SalatPrayer> updated) async {
    prayersNotifier.value = updated;
    final prefs = await SharedPreferences.getInstance();
    final jsonList = updated.map((p) => p.toJson()).toList();
    await prefs.setString(_prefKey, jsonEncode(jsonList));
  }

  /// Check if the given time is within forbidden Zawal (Istiwa) window
  static bool isZawalPeriod(DateTime now) {
    final calc = getExtendedDailySchedule(now);
    final start = DateTime(now.year, now.month, now.day, calc.zawalStart.hour, calc.zawalStart.minute);
    final end = DateTime(now.year, now.month, now.day, calc.zawalEnd.hour, calc.zawalEnd.minute);
    return now.isAfter(start) && now.isBefore(end);
  }

  /// Calculates which prayer is upcoming next relative to current time
  static NextPrayerInfo? getNextPrayer(DateTime now) {
    if (isAutoCalculation) {
      recalculateForDate(now);
    }

    final activePrayers = prayers.where((p) => p.isPrayer).toList();
    if (activePrayers.isEmpty) return null;

    final isFriday = now.weekday == DateTime.friday;

    final list = activePrayers.where((p) {
      if (p.id == 'jummah') return isFriday;
      if (p.id == 'dhuhr') return !isFriday;
      return true;
    }).toList();

    for (final p in list) {
      final jamatDt = DateTime(now.year, now.month, now.day, p.jamatTime.hour, p.jamatTime.minute);
      if (jamatDt.isAfter(now)) {
        return NextPrayerInfo(
          prayer: p,
          timeRemaining: jamatDt.difference(now),
          isJamatNext: true,
        );
      }
    }

    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowSchedule = isAutoCalculation ? getExtendedDailySchedule(tomorrow) : null;
    final fajr = list.firstWhere((p) => p.id == 'fajr', orElse: () => list.first);

    final tomorrowJamat = tomorrowSchedule != null
        ? (jamatMode == 'offset' ? addMinutes(tomorrowSchedule.fajr, jamatOffsets['fajr'] ?? 25) : fajr.jamatTime)
        : fajr.jamatTime;

    final tomorrowFajrDt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, tomorrowJamat.hour, tomorrowJamat.minute);

    return NextPrayerInfo(
      prayer: fajr,
      timeRemaining: tomorrowFajrDt.difference(now),
      isJamatNext: true,
    );
  }

  static String formatTime(TimeOfDay time, {bool is24Hour = false}) {
    if (is24Hour) {
      final h = time.hour.toString().padLeft(2, '0');
      final m = time.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$m $period';
  }
}
