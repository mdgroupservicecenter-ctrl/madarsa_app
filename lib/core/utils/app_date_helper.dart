import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';
import '../localization/app_localizations.dart';

class AppDateHelper {
  static const Map<String, List<String>> _hijriMonths = {
    'en': [
      'Muharram',
      'Safar',
      "Rabi' al-Awwal",
      "Rabi' al-Thani",
      'Jumada al-Awwal',
      'Jumada al-Thani',
      'Rajab',
      "Sha'ban",
      'Ramadan',
      'Shawwal',
      "Dhu al-Qi'dah",
      'Dhu al-Hijjah',
    ],
    'ur': [
      'محرم الحرام',
      'صفر المظفر',
      'ربیع الاول',
      'ربیع الثانی',
      'جمادی الاول',
      'جمادی الثانی',
      'رجب المرجب',
      'شعبان المعظم',
      'رمضان المبارک',
      'شوال المکرم',
      'ذوالقعدہ',
      'ذوالحجہ',
    ],
    'hi': [
      'मुहर्रम',
      'सफ़र',
      'रबी-उल-अव्वल',
      'रबी-उस-सानी',
      'जुमादा-अल-अव्वल',
      'जुमादा-अल-सानी',
      'रजब',
      'शाबान',
      'रमज़ान',
      'शव्वाल',
      'ज़ुल-क़ादा',
      'ज़ुल-हज्जा',
    ],
    'gu': [
      'મોહરમ',
      'સફર',
      'રબી-ઉલ-અવ્વલ',
      'રબી-ઉસ-સાની',
      'જુમાદા-અલ-અવ્વલ',
      'જુમાદા-અલ-સાની',
      'રજબ',
      'શાબાન',
      'રમઝાન',
      'શવ્વાલ',
      'ઝુલ-કાયદા',
      'ઝુલ-હિજ્જા',
    ],
  };

  static const Map<String, List<String>> _gregorianWeekdays = {
    'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    'ur': ['پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ', 'اتوار'],
    'hi': ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'],
    'gu': ['સોમ', 'મંગળ', 'બુધ', 'ગુરુ', 'શુક્ર', 'શનિ', 'રવિ'],
  };

  static const Map<String, List<String>> _gregorianMonths = {
    'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    'ur': ['جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون', 'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر'],
    'hi': ['जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'],
    'gu': ['જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન', 'જુલાઈ', 'ઓગસ્ટ', 'સપ્ટેમ્બર', 'ઓક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર'],
  };

  /// Format Hijri Date in the requested language
  static String formatHijri(DateTime date, String langCode, {int adjustment = 0}) {
    final hijri = HijriCalendar.fromDate(date.add(Duration(days: adjustment)));
    final mIndex = (hijri.hMonth - 1).clamp(0, 11);
    final monthList = _hijriMonths[langCode] ?? _hijriMonths['en']!;
    final monthName = monthList[mIndex];

    switch (langCode) {
      case 'ur':
        return '\u200F${hijri.hDay} $monthName ${hijri.hYear}ھ\u200F';
      case 'hi':
        return '${hijri.hDay} $monthName ${hijri.hYear} हिजरी';
      case 'gu':
        return '${hijri.hDay} $monthName ${hijri.hYear} હિજરી';
      default:
        return '${hijri.hDay} $monthName ${hijri.hYear} AH';
    }
  }

  /// Format Gregorian Date in the requested language
  static String formatGregorian(DateTime date, String langCode) {
    final wIndex = (date.weekday - 1).clamp(0, 6);
    final mIndex = (date.month - 1).clamp(0, 11);

    final weekdays = _gregorianWeekdays[langCode] ?? _gregorianWeekdays['en']!;
    final months = _gregorianMonths[langCode] ?? _gregorianMonths['en']!;

    final weekdayName = weekdays[wIndex];
    final monthName = months[mIndex];

    if (langCode == 'ur') {
      return '\u200F$weekdayName، ${date.day} $monthName ${date.year}\u200F';
    } else {
      return '$weekdayName, ${date.day} $monthName ${date.year}';
    }
  }

  /// Format prayer jamat time with localized period and non-flipping LTR digits
  static String formatJamatTime(TimeOfDay time, String langCode, {bool is24Hour = false}) {
    if (is24Hour) {
      final h = time.hour.toString().padLeft(2, '0');
      final m = time.minute.toString().padLeft(2, '0');
      return '\u200E$h:$m\u200E';
    }
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final m = time.minute.toString().padLeft(2, '0');
    final isAm = time.period == DayPeriod.am;

    String periodText;
    switch (langCode) {
      case 'ur':
        periodText = isAm ? 'صبح' : 'شام';
        break;
      case 'hi':
        periodText = isAm ? 'सुबह' : 'शाम';
        break;
      case 'gu':
        periodText = isAm ? 'સવાર' : 'સાંજ';
        break;
      default:
        periodText = isAm ? 'AM' : 'PM';
    }

    return '\u200E$hour:$m\u200E $periodText';
  }

  /// Format remaining duration for next prayer
  static String formatTimeRemaining(Duration duration, String langCode) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    switch (langCode) {
      case 'ur':
        return hours > 0 ? '$hours گھنٹے $minutes منٹ میں' : '$minutes منٹ میں';
      case 'hi':
        return hours > 0 ? '$hours घंटे $minutes मिनट में' : '$minutes मिनट में';
      case 'gu':
        return hours > 0 ? '$hours કલાક $minutes મિનિટમાં' : '$minutes મિનિટમાં';
      default:
        return hours > 0 ? 'in ${hours}h ${minutes}m' : 'in ${minutes}m';
    }
  }

  /// Localize weather condition name
  static String localizeWeatherCondition(BuildContext context, String? condition) {
    if (condition == null || condition.trim().isEmpty) {
      return context.tr('weather_loading');
    }
    final cond = condition.toLowerCase().trim();
    if (cond.contains('clear sky')) return context.tr('weather_clear_sky');
    if (cond.contains('clear')) return context.tr('weather_mainly_clear');
    if (cond.contains('partly')) return context.tr('weather_partly_cloudy');
    if (cond.contains('overcast')) return context.tr('weather_overcast');
    if (cond.contains('fog')) return context.tr('weather_foggy');
    if (cond.contains('drizzle')) return context.tr('weather_light_drizzle');
    if (cond.contains('shower')) return context.tr('weather_rain_showers');
    if (cond.contains('rain')) return context.tr('weather_rain');
    if (cond.contains('snow')) return context.tr('weather_snow_flurries');
    if (cond.contains('thunder')) return context.tr('weather_thunderstorm');
    return condition;
  }
}
