import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../storage/database_helper.dart';

class DonationReceiptSettingsModel {
  final String customPrefix; // e.g. 'DN-', 'REC-', or ''
  final bool enableAlphabet;
  final String startAlphabet; // e.g. 'A'
  final String endAlphabet;   // e.g. 'Z'
  final String alphabetPrefix; // e.g. 'A'
  
  final bool enableYear;
  final String yearFormat; // '2digit' (26) or '4digit' (2026)
  final String customYearValue; // e.g. '26', '2026'
  
  final int digitPadding; // e.g. 5 -> 00001
  final int startingNumber; // e.g. 1
  final bool syncReceiptNumbers; // whether Fee & Donation share one series (true) or run independent series (false)

  DonationReceiptSettingsModel({
    this.customPrefix = 'DN-',
    this.enableAlphabet = false,
    this.startAlphabet = 'A',
    this.endAlphabet = 'Z',
    this.alphabetPrefix = 'A',
    this.enableYear = false,
    this.yearFormat = '2digit',
    this.customYearValue = '',
    this.digitPadding = 5,
    this.startingNumber = 1,
    this.syncReceiptNumbers = true,
  });

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

  String getEffectiveAlphabet() {
    if (!enableAlphabet) return '';
    final alpha = alphabetPrefix.trim().toUpperCase();
    if (alpha.isNotEmpty) return alpha;
    final start = startAlphabet.trim().toUpperCase();
    return start.isNotEmpty ? start : 'A';
  }

  String buildPrefix({DateTime? targetDate}) {
    final base = customPrefix.trim();
    final alpha = getEffectiveAlphabet();
    final year = getEffectiveYear(targetDate: targetDate);

    final sb = StringBuffer();
    if (base.isNotEmpty) sb.write(base);
    if (alpha.isNotEmpty) sb.write(alpha);
    if (year.isNotEmpty) sb.write(year);

    final res = sb.toString();
    if (res.isNotEmpty && !res.endsWith('-') && !res.endsWith('/')) {
      return '$res-';
    }
    return res;
  }

  String formatSequence(int seq) {
    if (digitPadding > 0) {
      return seq.toString().padLeft(digitPadding, '0');
    }
    return seq.toString();
  }

  String buildReceiptNo(int seq, {DateTime? targetDate}) {
    return '${buildPrefix(targetDate: targetDate)}${formatSequence(seq)}';
  }

  DonationReceiptSettingsModel copyWith({
    String? customPrefix,
    bool? enableAlphabet,
    String? startAlphabet,
    String? endAlphabet,
    String? alphabetPrefix,
    bool? enableYear,
    String? yearFormat,
    String? customYearValue,
    int? digitPadding,
    int? startingNumber,
    bool? syncReceiptNumbers,
  }) {
    return DonationReceiptSettingsModel(
      customPrefix: customPrefix ?? this.customPrefix,
      enableAlphabet: enableAlphabet ?? this.enableAlphabet,
      startAlphabet: startAlphabet ?? this.startAlphabet,
      endAlphabet: endAlphabet ?? this.endAlphabet,
      alphabetPrefix: alphabetPrefix ?? this.alphabetPrefix,
      enableYear: enableYear ?? this.enableYear,
      yearFormat: yearFormat ?? this.yearFormat,
      customYearValue: customYearValue ?? this.customYearValue,
      digitPadding: digitPadding ?? this.digitPadding,
      startingNumber: startingNumber ?? this.startingNumber,
      syncReceiptNumbers: syncReceiptNumbers ?? this.syncReceiptNumbers,
    );
  }
}

class DonationReceiptSettings {
  static const String _keyCustomPrefix = 'donation_receipt_prefix';
  static const String _keyEnableAlphabet = 'donation_receipt_enable_alphabet';
  static const String _keyStartAlphabet = 'donation_receipt_start_alphabet';
  static const String _keyEndAlphabet = 'donation_receipt_end_alphabet';
  static const String _keyAlphabetPrefix = 'donation_receipt_alphabet_prefix';
  static const String _keyEnableYear = 'donation_receipt_enable_year';
  static const String _keyYearFormat = 'donation_receipt_year_format';
  static const String _keyCustomYearValue = 'donation_receipt_custom_year';
  static const String _keyDigitPadding = 'donation_receipt_digit_padding';
  static const String _keyStartingNumber = 'donation_receipt_starting_number';
  static const String _keySyncReceiptNumbers = 'donation_receipt_sync_receipt_numbers';

  static Future<DonationReceiptSettingsModel> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return DonationReceiptSettingsModel(
      customPrefix: prefs.getString(_keyCustomPrefix) ?? 'DN-',
      enableAlphabet: prefs.getBool(_keyEnableAlphabet) ?? false,
      startAlphabet: prefs.getString(_keyStartAlphabet) ?? 'A',
      endAlphabet: prefs.getString(_keyEndAlphabet) ?? 'Z',
      alphabetPrefix: prefs.getString(_keyAlphabetPrefix) ?? 'A',
      enableYear: prefs.getBool(_keyEnableYear) ?? false,
      yearFormat: prefs.getString(_keyYearFormat) ?? '2digit',
      customYearValue: prefs.getString(_keyCustomYearValue) ?? '',
      digitPadding: prefs.getInt(_keyDigitPadding) ?? 5,
      startingNumber: prefs.getInt(_keyStartingNumber) ?? 1,
      syncReceiptNumbers: prefs.getBool(_keySyncReceiptNumbers) ?? true,
    );
  }

  static Future<void> saveSettings(DonationReceiptSettingsModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomPrefix, model.customPrefix.trim());
    await prefs.setBool(_keyEnableAlphabet, model.enableAlphabet);
    await prefs.setString(_keyStartAlphabet, model.startAlphabet.trim().toUpperCase());
    await prefs.setString(_keyEndAlphabet, model.endAlphabet.trim().toUpperCase());
    await prefs.setString(_keyAlphabetPrefix, model.alphabetPrefix.trim().toUpperCase());
    await prefs.setBool(_keyEnableYear, model.enableYear);
    await prefs.setString(_keyYearFormat, model.yearFormat);
    await prefs.setString(_keyCustomYearValue, model.customYearValue.trim());
    await prefs.setInt(_keyDigitPadding, model.digitPadding);
    await prefs.setInt(_keyStartingNumber, model.startingNumber);
    await prefs.setBool(_keySyncReceiptNumbers, model.syncReceiptNumbers);
  }

  /// Queries existing receipt numbers.
  /// If [receiptType] is 'fee', queries only the fees table.
  /// If [receiptType] is 'donation', queries only the donations table.
  /// If [receiptType] is 'all', queries both tables (UNION).
  static Future<List<String>> getAllExistingReceiptNos({
    String receiptType = 'all',
    List<String>? additionalInMemory,
  }) async {
    final Set<String> allNos = {};
    if (additionalInMemory != null) {
      for (final no in additionalInMemory) {
        if (no.trim().isNotEmpty) allNos.add(no.trim());
      }
    }
    try {
      final db = await DatabaseHelper().database;
      String query;
      if (receiptType == 'fee') {
        query = "SELECT receipt_no FROM fees WHERE receipt_no IS NOT NULL AND TRIM(receipt_no) != ''";
      } else if (receiptType == 'donation') {
        query = "SELECT receipt_no FROM donations WHERE receipt_no IS NOT NULL AND TRIM(receipt_no) != ''";
      } else {
        query = '''
          SELECT receipt_no FROM fees WHERE receipt_no IS NOT NULL AND TRIM(receipt_no) != ''
          UNION
          SELECT receipt_no FROM donations WHERE receipt_no IS NOT NULL AND TRIM(receipt_no) != ''
        ''';
      }
      final rows = await db.rawQuery(query);
      for (final r in rows) {
        final val = r['receipt_no']?.toString().trim();
        if (val != null && val.isNotEmpty) {
          allNos.add(val);
        }
      }
    } catch (_) {}
    return allNos.toList();
  }

  /// Generates the next receipt number.
  /// If [settings.syncReceiptNumbers] is true, queries both tables together for a unified sequence.
  /// If [settings.syncReceiptNumbers] is false, uses [receiptType] ('fee' or 'donation') to query only that table for independent sequences.
  static Future<String> getNextUnifiedReceiptNo({
    DonationReceiptSettingsModel? settings,
    DateTime? targetDate,
    String receiptType = 'all',
    List<String>? additionalInMemory,
  }) async {
    final s = settings ?? await loadSettings();
    final effectiveType = s.syncReceiptNumbers ? 'all' : receiptType;
    final existingNos = await getAllExistingReceiptNos(
      receiptType: effectiveType,
      additionalInMemory: additionalInMemory,
    );
    return DonationReceiptGenerator.generateNextReceiptNo(
      existingReceiptNos: existingNos,
      settings: s,
      targetDate: targetDate,
    );
  }
}

class DonationReceiptGenerator {
  static String generateNextReceiptNo({
    required List<String> existingReceiptNos,
    required DonationReceiptSettingsModel settings,
    DateTime? targetDate,
  }) {
    final prefix = settings.buildPrefix(targetDate: targetDate);
    final prefixNorm = prefix.toLowerCase();

    int maxSeq = settings.startingNumber - 1;

    for (final rawNo in existingReceiptNos) {
      final no = rawNo.trim();
      if (no.isEmpty) continue;

      if (prefixNorm.isNotEmpty) {
        if (no.toLowerCase().startsWith(prefixNorm)) {
          final remainder = no.substring(prefix.length).trim();
          final match = RegExp(r'^(\d+)').firstMatch(remainder);
          if (match != null) {
            final val = int.tryParse(match.group(1)!);
            if (val != null && val > maxSeq) {
              maxSeq = val;
            }
          }
        } else {
          // If no starts with different prefix or raw numbers, also check trailing sequence if sensible
          final match = RegExp(r'(\d+)$').firstMatch(no);
          if (match != null) {
            final val = int.tryParse(match.group(1)!);
            if (val != null && val > maxSeq && val < 10000000) {
              maxSeq = val;
            }
          }
        }
      } else {
        final match = RegExp(r'(\d+)$').firstMatch(no);
        if (match != null) {
          final val = int.tryParse(match.group(1)!);
          if (val != null && val > maxSeq && val < 10000000) {
            maxSeq = val;
          }
        }
      }
    }

    final nextSeq = maxSeq + 1;
    return settings.buildReceiptNo(nextSeq, targetDate: targetDate);
  }
}
