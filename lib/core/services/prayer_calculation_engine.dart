import 'dart:math';
import 'package:flutter/material.dart';

enum CalculationMethod {
  karachi(
    id: 'karachi',
    name: 'University of Islamic Sciences, Karachi',
    urduName: 'جامعۃ العلوم الاسلامیہ، بنوری ٹاؤن، کراچی',
    description: 'Fajr 18.0°, Isha 18.0° (Deeniyat / South Asia / Deoband Standard)',
    fajrAngle: 18.0,
    ishaAngle: 18.0,
  ),
  mwl(
    id: 'mwl',
    name: 'Muslim World League (MWL)',
    urduName: 'رابطہ عالم اسلامی (مکہ مکرمہ)',
    description: 'Fajr 18.0°, Isha 17.0°',
    fajrAngle: 18.0,
    ishaAngle: 17.0,
  ),
  ummAlQura(
    id: 'umm_al_qura',
    name: 'Umm Al-Qura University, Makkah',
    urduName: 'جامعہ ام القریٰ، مکہ مکرمہ',
    description: 'Fajr 18.5°, Isha 90 min after Maghrib',
    fajrAngle: 18.5,
    ishaAngle: 0.0, // Minutes based
    ishaMinutesAfterMaghrib: 90,
  ),
  egyptian(
    id: 'egyptian',
    name: 'Egyptian General Authority of Survey',
    urduName: 'مصری جنرل اتھارٹی',
    description: 'Fajr 19.5°, Isha 17.5°',
    fajrAngle: 19.5,
    ishaAngle: 17.5,
  ),
  isna(
    id: 'isna',
    name: 'Islamic Society of North America (ISNA)',
    urduName: 'اسلامک سوسائٹی آف نارتھ امریکہ',
    description: 'Fajr 15.0°, Isha 15.0°',
    fajrAngle: 15.0,
    ishaAngle: 15.0,
  );

  final String id;
  final String name;
  final String urduName;
  final String description;
  final double fajrAngle;
  final double ishaAngle;
  final int ishaMinutesAfterMaghrib;

  const CalculationMethod({
    required this.id,
    required this.name,
    required this.urduName,
    required this.description,
    required this.fajrAngle,
    required this.ishaAngle,
    this.ishaMinutesAfterMaghrib = 0,
  });

  static CalculationMethod fromId(String id) {
    return CalculationMethod.values.firstWhere(
      (m) => m.id == id,
      orElse: () => CalculationMethod.karachi,
    );
  }
}

enum JuristicMethod {
  hanafi(id: 'Hanafi', name: 'Hanafi (حنفی)', shadowFactor: 2.0),
  shafii(id: 'Shafii', name: 'Shafi\'i / Maliki / Hanbali (شافعی)', shadowFactor: 1.0);

  final String id;
  final String name;
  final double shadowFactor;

  const JuristicMethod({
    required this.id,
    required this.name,
    required this.shadowFactor,
  });

  static JuristicMethod fromId(String id) {
    if (id.toLowerCase() == 'shafii') return JuristicMethod.shafii;
    return JuristicMethod.hanafi;
  }
}

class CalculatedPrayerTimes {
  final DateTime date;
  final TimeOfDay sehriEnd;
  final TimeOfDay fajr;
  final TimeOfDay sunrise;
  final TimeOfDay ishraq;
  final TimeOfDay chaasht;
  final TimeOfDay zawalStart;
  final TimeOfDay zawalEnd;
  final TimeOfDay dhuhr;
  final TimeOfDay asr;
  final TimeOfDay maghrib;
  final TimeOfDay isha;
  final TimeOfDay midnight;

  const CalculatedPrayerTimes({
    required this.date,
    required this.sehriEnd,
    required this.fajr,
    required this.sunrise,
    required this.ishraq,
    required this.chaasht,
    required this.zawalStart,
    required this.zawalEnd,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    required this.midnight,
  });
}

class PrayerCalculationEngine {
  static double degToRad(double d) => d * pi / 180.0;
  static double radToDeg(double r) => r * 180.0 / pi;

  static double fixAngle(double a) {
    a = a - 360.0 * (a / 360.0).floor();
    return a < 0 ? a + 360.0 : a;
  }

  static double fixHour(double h) {
    h = h - 24.0 * (h / 24.0).floor();
    return h < 0 ? h + 24.0 : h;
  }

  /// Calculates Julian Day number from Gregorian date
  static double julianDate(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor() +
        (30.6001 * (month + 1)).floor() +
        day +
        b -
        1524.5;
  }

  /// Computes declination (degrees) and Equation of Time (hours)
  static List<double> sunPosition(double jd) {
    final d = jd - 2451545.0;
    final g = fixAngle(357.529 + 0.98560028 * d);
    final q = fixAngle(280.459 + 0.98564736 * d);
    final l = fixAngle(q + 1.915 * sin(degToRad(g)) + 0.020 * sin(degToRad(2 * g)));

    final e = 23.439 - 0.00000036 * d;
    final dd = radToDeg(asin(sin(degToRad(e)) * sin(degToRad(l))));
    var ra = radToDeg(atan2(cos(degToRad(e)) * sin(degToRad(l)), cos(degToRad(l)))) / 15.0;
    ra = fixHour(ra);

    final eqT = q / 15.0 - ra;
    return [dd, eqT];
  }

  /// Calculates sun angle time relative to midday
  static double? sunAngleTime(double angle, double midDay, double lat, double decl, bool isMorning) {
    final val = (-sin(degToRad(angle)) - sin(degToRad(lat)) * sin(degToRad(decl))) /
        (cos(degToRad(lat)) * cos(degToRad(decl)));
    if (val > 1.0 || val < -1.0) return null;
    final h = radToDeg(acos(val)) / 15.0;
    return midDay + (isMorning ? -h : h);
  }

  /// Calculates Asr time using shadow factor (1 for Shafi'i, 2 for Hanafi)
  static double asrTime(double factor, double midDay, double lat, double decl) {
    final d = -radToDeg(atan(1.0 / (factor + tan(degToRad((lat - decl).abs())))));
    final res = sunAngleTime(d, midDay, lat, decl, false);
    return res ?? (midDay + 3.0);
  }

  static TimeOfDay _decimalHoursToTimeOfDay(double decimalHours) {
    final fixed = fixHour(decimalHours);
    final totalMinutes = (fixed * 60).round();
    final hour = (totalMinutes ~/ 60) % 24;
    final minute = totalMinutes % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Main calculation method: returns complete daily prayer times
  static CalculatedPrayerTimes calculate({
    required DateTime date,
    required double latitude,
    required double longitude,
    double? timeZoneOffsetHours,
    CalculationMethod method = CalculationMethod.karachi,
    JuristicMethod juristic = JuristicMethod.hanafi,
    Map<String, int> minuteAdjustments = const {},
  }) {
    // Determine timezone offset in hours
    final tz = timeZoneOffsetHours ?? (date.timeZoneOffset.inMinutes / 60.0);

    final jd = julianDate(date.year, date.month, date.day);
    final sun = sunPosition(jd);
    final decl = sun[0];
    final eqT = sun[1];

    // Midday (Solar Noon)
    final midDay = fixHour(12.0 + tz - (longitude / 15.0) - eqT);

    // Dhuhr (Solar noon + 2 min for safety)
    final dhuhrDec = midDay + (2.0 / 60.0);

    // Sunrise & Sunset (atmospheric refraction angle 0.833°)
    final sunriseDec = sunAngleTime(0.833, midDay, latitude, decl, true) ?? (midDay - 6.0);
    final sunsetDec = sunAngleTime(0.833, midDay, latitude, decl, false) ?? (midDay + 6.0);

    // Fajr
    final fajrDec = sunAngleTime(method.fajrAngle, midDay, latitude, decl, true) ?? (sunriseDec - 1.5);

    // Asr
    final asrDec = asrTime(juristic.shadowFactor, midDay, latitude, decl);

    // Maghrib
    final maghribDec = sunsetDec;

    // Isha
    double ishaDec;
    if (method.ishaMinutesAfterMaghrib > 0) {
      ishaDec = maghribDec + (method.ishaMinutesAfterMaghrib / 60.0);
    } else {
      ishaDec = sunAngleTime(method.ishaAngle, midDay, latitude, decl, false) ?? (maghribDec + 1.5);
    }

    // Extended Shar'i Timings
    // 1. Ishraq: Approx 18 minutes after sunrise (sun altitude ~4.5°)
    final ishraqDec = sunriseDec + (18.0 / 60.0);

    // 2. Chaasht / Duha: Midpoint between sunrise and midday
    final chaashtDec = (sunriseDec + midDay) / 2.0;

    // 3. Zawal (Forbidden Istiwa Period): 10 mins before Dhuhr to Dhuhr start
    final zawalStartDec = midDay - (10.0 / 60.0);
    final zawalEndDec = dhuhrDec;

    // 4. Midnight (Nisf al-Layl): Midpoint between sunset and next sunrise
    final nightDuration = fixHour(sunriseDec - sunsetDec + 24.0);
    final midnightDec = sunsetDec + (nightDuration / 2.0);

    // Apply minute adjustments if any
    double applyAdj(double dec, String key) {
      final adj = minuteAdjustments[key] ?? 0;
      return dec + (adj / 60.0);
    }

    return CalculatedPrayerTimes(
      date: date,
      sehriEnd: _decimalHoursToTimeOfDay(applyAdj(fajrDec, 'fajr')),
      fajr: _decimalHoursToTimeOfDay(applyAdj(fajrDec, 'fajr')),
      sunrise: _decimalHoursToTimeOfDay(applyAdj(sunriseDec, 'sunrise')),
      ishraq: _decimalHoursToTimeOfDay(applyAdj(ishraqDec, 'ishraq')),
      chaasht: _decimalHoursToTimeOfDay(applyAdj(chaashtDec, 'chaasht')),
      zawalStart: _decimalHoursToTimeOfDay(zawalStartDec),
      zawalEnd: _decimalHoursToTimeOfDay(zawalEndDec),
      dhuhr: _decimalHoursToTimeOfDay(applyAdj(dhuhrDec, 'dhuhr')),
      asr: _decimalHoursToTimeOfDay(applyAdj(asrDec, 'asr')),
      maghrib: _decimalHoursToTimeOfDay(applyAdj(maghribDec, 'maghrib')),
      isha: _decimalHoursToTimeOfDay(applyAdj(ishaDec, 'isha')),
      midnight: _decimalHoursToTimeOfDay(midnightDec),
    );
  }
}
