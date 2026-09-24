class UrduNumberHelper {
  /// Digit mappings for supported scripts:
  /// en (English), ur (Urdu), ar (Arabic), hi (Hindi), gu (Gujarati), bn (Bengali)
  static const Map<String, List<String>> digitMaps = {
    'en': ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
    'ur': ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'],
    'ar': ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'],
    'hi': ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'],
    'gu': ['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'],
    'bn': ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'],
  };

  /// Supported card number & text languages
  static const List<Map<String, String>> supportedCardLanguages = [
    {'code': 'ur', 'name': 'Urdu (اردو)', 'nativeName': 'اردو'},
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'hi', 'name': 'Hindi (हिन्दी)', 'nativeName': 'हिन्दी'},
    {'code': 'gu', 'name': 'Gujarati (ગુજરાતી)', 'nativeName': 'ગુજરાતી'},
    {'code': 'ar', 'name': 'Arabic (العربية)', 'nativeName': 'العربية'},
    {'code': 'bn', 'name': 'Bengali (বাংলা)', 'nativeName': 'বাংলা'},
  ];

  /// Converts any string containing Urdu, Arabic, Devanagari, Gujarati, or Bengali digits into standard ASCII digits (0-9).
  static String normalize(String input) {
    if (input.isEmpty) return input;
    var result = input.trim();

    // Arabic-Indic Digits (U+0660..U+0669)
    result = result
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9');

    // Extended Arabic-Indic / Urdu Digits (U+06F0..U+06F9)
    result = result
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9');

    // Devanagari Digits (U+0966..U+096F)
    result = result
        .replaceAll('०', '0')
        .replaceAll('१', '1')
        .replaceAll('२', '2')
        .replaceAll('३', '3')
        .replaceAll('४', '4')
        .replaceAll('५', '5')
        .replaceAll('६', '6')
        .replaceAll('७', '7')
        .replaceAll('८', '8')
        .replaceAll('९', '9');

    // Gujarati Digits (U+0AE6..U+0AEF)
    result = result
        .replaceAll('૦', '0')
        .replaceAll('૧', '1')
        .replaceAll('૨', '2')
        .replaceAll('૩', '3')
        .replaceAll('૪', '4')
        .replaceAll('૫', '5')
        .replaceAll('૬', '6')
        .replaceAll('૭', '7')
        .replaceAll('૮', '8')
        .replaceAll('૯', '9');

    // Bengali Digits (U+09E6..U+09EF)
    result = result
        .replaceAll('০', '0')
        .replaceAll('১', '1')
        .replaceAll('২', '2')
        .replaceAll('৩', '3')
        .replaceAll('৪', '4')
        .replaceAll('৫', '5')
        .replaceAll('৬', '6')
        .replaceAll('৭', '7')
        .replaceAll('৮', '8')
        .replaceAll('৯', '9');

    // Urdu / Arabic Decimal Separator
    result = result.replaceAll('٫', '.').replaceAll('،', '.');
    return result;
  }

  /// Parses double supporting English, Urdu, Arabic, Devanagari, Gujarati, Bengali numerals.
  static double? tryParseDouble(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final normalized = normalize(text);
    return double.tryParse(normalized);
  }

  /// Parses int supporting English, Urdu, Arabic, Devanagari, Gujarati, Bengali numerals.
  static int? tryParseInt(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final normalized = normalize(text);
    return int.tryParse(normalized);
  }

  /// Converts ASCII or localized digits in [input] to digits of target language script ([langCode]).
  static String convertDigits(dynamic input, String langCode) {
    if (input == null) return '';
    String str = input.toString();
    if (str.isEmpty) return str;

    // Normalize input to ASCII digits first
    str = normalize(str);

    if (langCode == 'en' || !digitMaps.containsKey(langCode)) {
      return str;
    }

    final targetDigits = digitMaps[langCode]!;
    final sb = StringBuffer();
    final isUrduOrArabic = langCode == 'ur' || langCode == 'ar';
    for (int i = 0; i < str.length; i++) {
      final char = str[i];
      final code = str.codeUnitAt(i);
      if (code >= 48 && code <= 57) { // '0'..'9'
        sb.write(targetDigits[code - 48]);
      } else if (char == '%' && isUrduOrArabic) {
        sb.write('٪');
      } else {
        sb.write(char);
      }
    }
    return sb.toString();
  }

  /// Converts English ASCII digits to Urdu digits for display.
  static String toUrduDigits(dynamic number) {
    return convertDigits(number, 'ur');
  }
}

