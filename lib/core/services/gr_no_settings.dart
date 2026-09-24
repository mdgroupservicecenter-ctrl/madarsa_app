import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';

class GrNoSettingsModel {
  final bool enableAlphabet;
  final String startAlphabet; // e.g. 'A'
  final String endAlphabet;   // e.g. 'Z'
  final String alphabetPrefix; // Current active letter e.g. 'A'
  
  final bool enableYear;
  final String yearFormat; // '2digit' (26) or '4digit' (2026)
  final String customYearValue; // e.g. '26', '2026', '25'
  
  final int digitPadding; // e.g. 4 (0001), 6 (000001), or 0 (no padding)
  final int startingNumber; // e.g. 1

  GrNoSettingsModel({
    this.enableAlphabet = false,
    this.startAlphabet = 'A',
    this.endAlphabet = 'Z',
    this.alphabetPrefix = 'A',
    this.enableYear = false,
    this.yearFormat = '2digit',
    this.customYearValue = '',
    this.digitPadding = 4,
    this.startingNumber = 1,
  });

  /// Resolves active Year String (default current year, or custom edited year)
  String getEffectiveYear({DateTime? targetDate}) {
    if (!enableYear) return '';
    final now = targetDate ?? DateTime.now();

    if (customYearValue.trim().isNotEmpty) {
      return customYearValue.trim();
    }
    if (yearFormat == '4digit') {
      return DateFormat('yyyy').format(now);
    }
    return DateFormat('yy').format(now);
  }

  /// Resolves active Alphabet Prefix
  String getEffectiveAlphabet() {
    if (!enableAlphabet) return '';
    final alpha = alphabetPrefix.trim().toUpperCase();
    if (alpha.isNotEmpty) return alpha;
    final start = startAlphabet.trim().toUpperCase();
    return start.isNotEmpty ? start : 'A';
  }

  /// Builds prefix part including hyphen if alphabet or year is enabled
  /// Examples:
  /// Alphabet 'A' + Year '26' -> 'A26-'
  /// Alphabet '' + Year '26' -> '26-'
  /// Alphabet 'A' + Year '' -> 'A-'
  /// None -> ''
  String buildPrefix({DateTime? targetDate}) {
    final alpha = getEffectiveAlphabet();
    final year = getEffectiveYear(targetDate: targetDate);

    if (alpha.isNotEmpty || year.isNotEmpty) {
      return '$alpha$year-';
    }
    return '';
  }

  /// Formats sequence number to exact custom digit padding length
  String formatSequence(int seq) {
    if (digitPadding > 0) {
      return seq.toString().padLeft(digitPadding, '0');
    }
    return seq.toString();
  }

  /// Builds a full GR No for a given sequence number
  String buildGrNo(int seq, {DateTime? targetDate}) {
    return '${buildPrefix(targetDate: targetDate)}${formatSequence(seq)}';
  }

  GrNoSettingsModel copyWith({
    bool? enableAlphabet,
    String? startAlphabet,
    String? endAlphabet,
    String? alphabetPrefix,
    bool? enableYear,
    String? yearFormat,
    String? customYearValue,
    int? digitPadding,
    int? startingNumber,
  }) {
    return GrNoSettingsModel(
      enableAlphabet: enableAlphabet ?? this.enableAlphabet,
      startAlphabet: startAlphabet ?? this.startAlphabet,
      endAlphabet: endAlphabet ?? this.endAlphabet,
      alphabetPrefix: alphabetPrefix ?? this.alphabetPrefix,
      enableYear: enableYear ?? this.enableYear,
      yearFormat: yearFormat ?? this.yearFormat,
      customYearValue: customYearValue ?? this.customYearValue,
      digitPadding: digitPadding ?? this.digitPadding,
      startingNumber: startingNumber ?? this.startingNumber,
    );
  }
}

class GrNoSettings {
  static const String _keyEnableAlphabet = 'gr_enable_alphabet';
  static const String _keyStartAlphabet = 'gr_start_alphabet';
  static const String _keyEndAlphabet = 'gr_end_alphabet';
  static const String _keyAlphabetPrefix = 'gr_alphabet_prefix';

  static const String _keyEnableYear = 'gr_enable_year';
  static const String _keyYearFormat = 'gr_year_format';
  static const String _keyCustomYearValue = 'gr_custom_year_value';

  static const String _keyDigitPadding = 'gr_digit_padding';
  static const String _keyStartingNumber = 'gr_starting_number';

  static Future<GrNoSettingsModel> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return GrNoSettingsModel(
      enableAlphabet: prefs.getBool(_keyEnableAlphabet) ?? false,
      startAlphabet: prefs.getString(_keyStartAlphabet) ?? 'A',
      endAlphabet: prefs.getString(_keyEndAlphabet) ?? 'Z',
      alphabetPrefix: prefs.getString(_keyAlphabetPrefix) ?? 'A',
      enableYear: prefs.getBool(_keyEnableYear) ?? false,
      yearFormat: prefs.getString(_keyYearFormat) ?? '2digit',
      customYearValue: prefs.getString(_keyCustomYearValue) ?? '',
      digitPadding: prefs.getInt(_keyDigitPadding) ?? 4,
      startingNumber: prefs.getInt(_keyStartingNumber) ?? 1,
    );
  }

  static Future<void> saveSettings(GrNoSettingsModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableAlphabet, model.enableAlphabet);
    await prefs.setString(_keyStartAlphabet, model.startAlphabet.trim().toUpperCase());
    await prefs.setString(_keyEndAlphabet, model.endAlphabet.trim().toUpperCase());
    await prefs.setString(_keyAlphabetPrefix, model.alphabetPrefix.trim().toUpperCase());

    await prefs.setBool(_keyEnableYear, model.enableYear);
    await prefs.setString(_keyYearFormat, model.yearFormat);
    await prefs.setString(_keyCustomYearValue, model.customYearValue.trim());

    await prefs.setInt(_keyDigitPadding, model.digitPadding);
    await prefs.setInt(_keyStartingNumber, model.startingNumber);

    FirebaseService.syncGrNoSettings(settings: {
      'enable_alphabet': model.enableAlphabet,
      'start_alphabet': model.startAlphabet.trim().toUpperCase(),
      'end_alphabet': model.endAlphabet.trim().toUpperCase(),
      'alphabet_prefix': model.alphabetPrefix.trim().toUpperCase(),
      'enable_year': model.enableYear,
      'year_format': model.yearFormat,
      'custom_year_value': model.customYearValue.trim(),
      'digit_padding': model.digitPadding,
      'starting_number': model.startingNumber,
    });
  }
}

class GrNoGenerator {
  /// Analyzes existing GR numbers in database, finds the max sequence for current prefix,
  /// and returns the next auto-incremented GR number in series.
  static String generateNextGrNo({
    required List<String> existingGrNos,
    required GrNoSettingsModel settings,
    DateTime? targetDate,
  }) {
    final prefix = settings.buildPrefix(targetDate: targetDate);
    final prefixNorm = prefix.toLowerCase();

    int maxSeq = settings.startingNumber - 1;

    for (final rawGr in existingGrNos) {
      final gr = rawGr.trim();
      if (gr.isEmpty) continue;

      if (prefixNorm.isNotEmpty) {
        if (gr.toLowerCase().startsWith(prefixNorm)) {
          final suffix = gr.substring(prefix.length).trim();
          final digitsMatch = RegExp(r'\d+').firstMatch(suffix);
          if (digitsMatch != null) {
            final numVal = int.tryParse(digitsMatch.group(0)!);
            if (numVal != null && numVal > maxSeq) {
              maxSeq = numVal;
            }
          }
        }
      } else {
        // No prefix: match purely numeric sequence
        final digitsMatch = RegExp(r'\d+').firstMatch(gr);
        if (digitsMatch != null) {
          final numVal = int.tryParse(digitsMatch.group(0)!);
          if (numVal != null && numVal > maxSeq) {
            maxSeq = numVal;
          }
        }
      }
    }

    int nextSeq = maxSeq + 1;

    // Check if sequence rolled over max digits for padding and alphabet is enabled
    if (settings.enableAlphabet && settings.digitPadding > 0) {
      final maxValForDigits = int.tryParse('9' * settings.digitPadding) ?? 99999999;
      if (nextSeq > maxValForDigits) {
        final currentAlpha = settings.getEffectiveAlphabet();
        if (currentAlpha.isNotEmpty) {
          final currentAlphaChar = currentAlpha.codeUnitAt(0);
          final endAlpha = settings.endAlphabet.trim().toUpperCase();
          final endAlphaChar = endAlpha.isNotEmpty ? endAlpha.codeUnitAt(0) : 'Z'.codeUnitAt(0);
          if (currentAlphaChar < endAlphaChar) {
            final nextAlpha = String.fromCharCode(currentAlphaChar + 1);
            final updatedSettings = settings.copyWith(alphabetPrefix: nextAlpha);
            return generateNextGrNo(
              existingGrNos: existingGrNos,
              settings: updatedSettings,
              targetDate: targetDate,
            );
          }
        }
      }
    }

    return settings.buildGrNo(nextSeq, targetDate: targetDate);
  }
}
