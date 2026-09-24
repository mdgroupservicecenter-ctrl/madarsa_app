import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/database_helper.dart';
import '../network/api_client.dart';
import '../../features/fees/data/models/fee_models.dart';
import '../../features/fees/data/repositories/fees_repository.dart';

class FeeConditionFieldConfig {
  final String id;
  final String label;
  final String fieldType; // 'number', 'contributor', 'text', 'staff'
  final String mathAction; // 'add' (+), 'subtract' (-), 'discount' (- % or ₹), 'multiply' (*), 'divide' (/), 'none'
  final String fieldSource; // 'staff', 'contributor', 'other', 'none'
  final String targetFeeField; // 'all' or fee id/label that discount applies to
  final String discountMode; // 'auto', 'percentage', 'flat'
  final String billingType; // 'monthly', 'one_time', 'session', 'yearly', 'half_yearly', 'quarterly', 'custom'
  final int billingMonths; // 12, 1, 10, 6, 3, etc.
  final List<String> monthsList;

  FeeConditionFieldConfig({
    required this.id,
    required this.label,
    required this.fieldType,
    required this.mathAction,
    this.fieldSource = 'other',
    this.targetFeeField = 'all',
    this.discountMode = 'auto',
    this.billingType = 'monthly',
    this.billingMonths = 12,
    this.monthsList = const [],
  });

  bool get isDeduction => mathAction == 'subtract' || mathAction == 'discount';

  FeeConditionFieldConfig copyWith({
    String? id,
    String? label,
    String? fieldType,
    String? mathAction,
    String? fieldSource,
    String? targetFeeField,
    String? discountMode,
    String? billingType,
    int? billingMonths,
    List<String>? monthsList,
  }) {
    return FeeConditionFieldConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      fieldType: fieldType ?? this.fieldType,
      mathAction: mathAction ?? this.mathAction,
      fieldSource: fieldSource ?? this.fieldSource,
      targetFeeField: targetFeeField ?? this.targetFeeField,
      discountMode: discountMode ?? this.discountMode,
      billingType: billingType ?? this.billingType,
      billingMonths: billingMonths ?? this.billingMonths,
      monthsList: monthsList ?? this.monthsList,
    );
  }

  bool get isContributor {
    if (fieldType == 'number') return false;
    if (fieldType == 'contributor') return true;
    final l = label.toLowerCase().trim();
    final i = id.toLowerCase().trim();
    if (l.contains('kafil') ||
        l.contains('kafeel') ||
        l.contains('contributor') ||
        l.contains('sponsor') ||
        l.contains('donor')) {
      return !l.contains('amount') && !l.contains('concession') && !l.contains('discount');
    }
    return (i.contains('contributor') || i.contains('kafil')) && !i.contains('amount');
  }

  bool get isStaff {
    if (fieldType == 'number') return false;
    if (fieldType == 'staff') return true;
    final l = label.toLowerCase().trim();
    final i = id.toLowerCase().trim();
    if (l.contains('staff') || i.contains('staff')) {
      return !l.contains('amount') && !l.contains('concession') && !l.contains('discount') && !i.contains('amount') && !i.contains('discount');
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'fieldType': fieldType,
        'mathAction': mathAction,
        'fieldSource': fieldSource,
        'targetFeeField': targetFeeField,
        'discountMode': discountMode,
        'billingType': billingType,
        'billingMonths': billingMonths,
        'months_list': monthsList,
      };

  factory FeeConditionFieldConfig.fromJson(Map<String, dynamic> json) {
    final label = (json['label'] ?? '').toString().toLowerCase().trim();
    final id = (json['id'] ?? '').toString().toLowerCase().trim();
    String fieldType = json['fieldType'] ?? 'number';
    String fieldSource = json['fieldSource'] ??
        (fieldType == 'staff'
            ? 'staff'
            : (fieldType == 'contributor' ? 'contributor' : 'other'));

    // Auto-heal / fix legacy or misconfigured kafil/contributor fields
    final isContributorLabel = label.contains('kafil') ||
        label.contains('kafeel') ||
        label.contains('contributor') ||
        label.contains('sponsor') ||
        label.contains('donor') ||
        id.contains('contributor') ||
        id.contains('kafil');

    if (isContributorLabel && fieldType != 'number') {
      fieldType = 'contributor';
      fieldSource = 'contributor';
    }

    // Auto-heal staff dropdown if misconfigured as number
    if (fieldType == 'staff') {
      fieldSource = 'staff';
    }

    final isOneTime = id.contains('admission') ||
        id.contains('dakhila') ||
        id.contains('book') ||
        id.contains('kitab') ||
        id.contains('exam') ||
        label.contains('admission') ||
        label.contains('dakhila') ||
        label.contains('book') ||
        label.contains('kitab') ||
        label.contains('exam');

    final defBillingType = isOneTime ? 'one_time' : 'monthly';
    final defBillingMonths = isOneTime ? 1 : 12;

    final billingType = json['billingType']?.toString() ?? defBillingType;
    final billingMonths = (json['billingMonths'] as num?)?.toInt() ??
        (billingType == 'one_time' ? 1 : defBillingMonths);

    final rawMonths = json['months_list'] ?? json['specific_months'];
    List<String> monthsList = [];
    if (rawMonths is List) {
      monthsList = rawMonths.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }

    return FeeConditionFieldConfig(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      fieldType: fieldType,
      mathAction: json['mathAction'] ?? 'add',
      fieldSource: fieldSource,
      targetFeeField: json['targetFeeField'] ?? 'all',
      discountMode: json['discountMode'] ?? 'auto',
      billingType: billingType,
      billingMonths: billingMonths,
      monthsList: monthsList,
    );
  }
}

class FeeConditionConfig {
  final String conditionName;
  final List<FeeConditionFieldConfig> fields;

  FeeConditionConfig({
    required this.conditionName,
    required this.fields,
  });

  Map<String, dynamic> toJson() => {
        'conditionName': conditionName,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  factory FeeConditionConfig.fromJson(Map<String, dynamic> json) =>
      FeeConditionConfig(
        conditionName: json['conditionName'] ?? '',
        fields: (json['fields'] as List? ?? [])
            .map((f) =>
                FeeConditionFieldConfig.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

// ── Fee Types Helper ──────────────────────────────────────────────────────────

class FeeTypesHelper {
  static Future<List<FeeType>> getFeeTypes() async {
    try {
      final dbTypes = await DatabaseHelper().getFeeTypes();
      if (dbTypes.isNotEmpty) {
        return dbTypes.map((row) {
          final rawMonths = row['months_list'] ?? row['specific_months'];
          List<String> monthsList = [];
          if (rawMonths is String && rawMonths.isNotEmpty) {
            try {
              final decoded = jsonDecode(rawMonths);
              if (decoded is List) monthsList = decoded.map((e) => e.toString()).toList();
            } catch (_) {}
          } else if (rawMonths is List) {
            monthsList = rawMonths.map((e) => e.toString()).toList();
          }
          return FeeType(
            id: row['id']?.toString() ?? '',
            name: row['name']?.toString() ?? '',
            billingType: row['billing_type']?.toString() ?? 'monthly',
            defaultMonths: (row['default_months'] as num?)?.toInt() ?? 12,
            defaultAmount: (row['default_amount'] as num?)?.toDouble() ?? 0.0,
            monthsList: monthsList,
          );
        }).toList();
      }
      try {
        return await FeesRepository(ApiClient()).getFeeTypes();
      } catch (_) {
        return [];
      }
    } catch (_) {
      return [];
    }
  }

  static Future<FeeType> addFeeType(
    String name, {
    String billingType = 'monthly',
    int defaultMonths = 12,
    double defaultAmount = 0.0,
    List<String>? monthsList,
  }) async {
    List<String> finalMonths = monthsList ?? const [];
    if (finalMonths.isEmpty) {
      final freqs = await BillingFrequencySettings.getFrequencies();
      final match = freqs.where((f) => f.id == billingType || f.name.toLowerCase() == billingType.toLowerCase()).firstOrNull;
      if (match != null && match.monthsList.isNotEmpty) {
        finalMonths = match.monthsList;
      }
    }
    final id = 'fee_type_${DateTime.now().millisecondsSinceEpoch}';
    final data = {
      'id': id,
      'name': name,
      'billing_type': billingType,
      'default_months': defaultMonths,
      'default_amount': defaultAmount,
      'months_list': finalMonths,
    };
    await DatabaseHelper().insertFeeType(data);
    try {
      await FeesRepository(ApiClient()).addFeeType(
        name,
        billingType: billingType,
        defaultMonths: defaultMonths,
        defaultAmount: defaultAmount,
      );
    } catch (_) {}
    return FeeType.fromJson(data);
  }

  static Future<void> updateFeeType(
    String id,
    String name, {
    String? billingType,
    int? defaultMonths,
    double? defaultAmount,
    List<String>? monthsList,
  }) async {
    final data = <String, dynamic>{'name': name};
    if (billingType != null) data['billing_type'] = billingType;
    if (defaultMonths != null) data['default_months'] = defaultMonths;
    if (defaultAmount != null) data['default_amount'] = defaultAmount;
    if (monthsList != null) {
      data['months_list'] = monthsList;
    } else if (billingType != null) {
      final freqs = await BillingFrequencySettings.getFrequencies();
      final match = freqs.where((f) => f.id == billingType || f.name.toLowerCase() == billingType.toLowerCase()).firstOrNull;
      if (match != null && match.monthsList.isNotEmpty) {
        data['months_list'] = match.monthsList;
      }
    }
    await DatabaseHelper().updateFeeType(id, data);
    try {
      await FeesRepository(ApiClient()).updateFeeType(
        id,
        name,
        billingType: billingType,
        defaultMonths: defaultMonths,
        defaultAmount: defaultAmount,
      );
    } catch (_) {}
  }

  static Future<void> deleteFeeType(String id) async {
    await DatabaseHelper().deleteFeeType(id);
    try {
      await FeesRepository(ApiClient()).deleteFeeType(id);
    } catch (_) {}
  }
}

// ── Billing Frequency Option & Settings ──────────────────────────────────────

class BillingFrequencyOption {
  final String id;
  final String name;
  final int months;
  final List<String> monthsList;

  static const List<String> allMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  static const List<String> shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String getShortMonth(String fullMonth) {
    final idx = allMonths.indexWhere((m) => m.toLowerCase() == fullMonth.toLowerCase());
    if (idx != -1) return shortMonths[idx];
    return fullMonth.length > 3 ? fullMonth.substring(0, 3) : fullMonth;
  }

  static String getFullMonth(String shortMonth) {
    final idx = shortMonths.indexWhere((m) => m.toLowerCase() == shortMonth.toLowerCase());
    if (idx != -1) return allMonths[idx];
    return shortMonth;
  }

  const BillingFrequencyOption({
    required this.id,
    required this.name,
    required this.months,
    this.monthsList = const [],
  });

  String get monthsDisplay {
    if (monthsList.isEmpty) {
      return '$months ${months == 1 ? 'Month' : 'Months'}';
    }
    if (monthsList.length == 12) return 'All 12 Months';
    return monthsList.map(getShortMonth).join(', ');
  }

  bool isDueInMonth(String monthName) {
    if (monthsList.isEmpty) {
      if (id == 'monthly' || name.toLowerCase() == 'monthly') return true;
      return false;
    }
    final target = monthName.toLowerCase().trim();
    return monthsList.any((m) {
      final clean = m.toLowerCase().trim();
      return clean == target ||
          (clean.length >= 3 && target.length >= 3 && clean.substring(0, 3) == target.substring(0, 3));
    });
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'months': months,
        'months_list': monthsList,
      };

  factory BillingFrequencyOption.fromJson(Map<String, dynamic> json) {
    final rawMonths = json['months_list'] ?? json['specific_months'];
    List<String> monthsList = [];
    if (rawMonths is List) {
      monthsList = rawMonths.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    final monthsCount = (json['months'] as num?)?.toInt() ?? (monthsList.isNotEmpty ? monthsList.length : 1);
    return BillingFrequencyOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      months: monthsCount,
      monthsList: monthsList,
    );
  }
}

class BillingFrequencySettings {
  static const String _prefKey = 'billing_frequency_options_v4';

  static List<BillingFrequencyOption> get defaultFrequencies => [
        const BillingFrequencyOption(id: 'monthly', name: 'Monthly', months: 12, monthsList: BillingFrequencyOption.allMonths),
        const BillingFrequencyOption(id: 'yearly', name: 'Yearly', months: 12, monthsList: BillingFrequencyOption.allMonths),
        const BillingFrequencyOption(id: 'session_10', name: 'Session', months: 10),
        const BillingFrequencyOption(id: 'half_yearly', name: 'Half-Yearly', months: 6),
        const BillingFrequencyOption(id: 'quarterly', name: 'Quarterly', months: 3),
        const BillingFrequencyOption(id: 'one_time', name: 'One-Time', months: 1),
      ];

  static Future<List<BillingFrequencyOption>> getFrequencies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return List.from(defaultFrequencies);
      }
      final list = jsonDecode(jsonStr) as List;
      if (list.isEmpty) return List.from(defaultFrequencies);
      final seenIds = <String>{};
      final uniqueList = <BillingFrequencyOption>[];
      for (final e in list) {
        final opt = BillingFrequencyOption.fromJson(e as Map<String, dynamic>);
        if (opt.id.isNotEmpty && !seenIds.contains(opt.id)) {
          seenIds.add(opt.id);
          uniqueList.add(opt);
        }
      }
      return uniqueList.isNotEmpty ? uniqueList : List.from(defaultFrequencies);
    } catch (_) {
      return List.from(defaultFrequencies);
    }
  }

  static Future<void> saveFrequencies(List<BillingFrequencyOption> list) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_prefKey, jsonStr);
  }

  static Future<void> addFrequency(String name, int months, {List<String> monthsList = const []}) async {
    final list = await getFrequencies();
    final id = 'freq_${DateTime.now().millisecondsSinceEpoch}';
    list.add(BillingFrequencyOption(id: id, name: name, months: months, monthsList: monthsList));
    await saveFrequencies(list);
  }

  static Future<void> updateFrequency(String id, String name, int months, {List<String> monthsList = const []}) async {
    final list = await getFrequencies();
    final idx = list.indexWhere((f) => f.id == id);
    if (idx != -1) {
      list[idx] = BillingFrequencyOption(id: id, name: name, months: months, monthsList: monthsList);
      await saveFrequencies(list);
    }
  }

  static Future<void> deleteFrequency(String id) async {
    final list = await getFrequencies();
    list.removeWhere((f) => f.id == id);
    await saveFrequencies(list);
  }
}

// ── Fee Condition Settings Storage ───────────────────────────────────────────

class FeeConditionSettings {
  static const String _prefKey = 'fee_condition_config_v4';

  static List<FeeConditionConfig> get defaultConditionConfigs => [
        FeeConditionConfig(
          conditionName: 'Regular',
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Monthly Fees (₹)',
              fieldType: 'number',
              mathAction: 'add',
            ),
          ],
        ),
        FeeConditionConfig(
          conditionName: 'Partial',
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Monthly Fees (₹)',
              fieldType: 'number',
              mathAction: 'add',
            ),
            FeeConditionFieldConfig(
              id: 'contributor_id',
              label: 'Contributor Name',
              fieldType: 'contributor',
              mathAction: 'none',
            ),
            FeeConditionFieldConfig(
              id: 'contributor_amount',
              label: 'Contributor Amount (₹)',
              fieldType: 'number',
              mathAction: 'subtract',
            ),
          ],
        ),
        FeeConditionConfig(
          conditionName: 'Scholarship',
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Monthly Fees (₹)',
              fieldType: 'number',
              mathAction: 'add',
            ),
            FeeConditionFieldConfig(
              id: 'scholarship_discount',
              label: 'Scholarship Discount (₹)',
              fieldType: 'number',
              mathAction: 'subtract',
            ),
          ],
        ),
        FeeConditionConfig(
          conditionName: 'Concession',
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Monthly Fees (₹)',
              fieldType: 'number',
              mathAction: 'add',
            ),
            FeeConditionFieldConfig(
              id: 'concession_amount',
              label: 'Concession Discount (₹)',
              fieldType: 'number',
              mathAction: 'subtract',
            ),
          ],
        ),
        FeeConditionConfig(
          conditionName: 'Orphan Free',
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Base Fee Amount (₹)',
              fieldType: 'number',
              mathAction: 'none',
            ),
          ],
        ),
        FeeConditionConfig(
          conditionName: 'Staff Child',
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Standard Fee (₹)',
              fieldType: 'number',
              mathAction: 'add',
            ),
            FeeConditionFieldConfig(
              id: 'staff_id',
              label: 'Staff Member Name',
              fieldType: 'staff',
              mathAction: 'none',
              fieldSource: 'staff',
            ),
            FeeConditionFieldConfig(
              id: 'staff_discount',
              label: 'Staff Concession (₹)',
              fieldType: 'number',
              mathAction: 'subtract',
            ),
          ],
        ),
      ];

  static Future<List<FeeConditionConfig>> getConditionConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List decoded = jsonDecode(raw);
        return decoded
            .map((c) => FeeConditionConfig.fromJson(c as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error decoding fee condition config: $e');
      }
    }
    return defaultConditionConfigs;
  }

  static Future<void> saveConditionConfigs(
      List<FeeConditionConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(_prefKey, encoded);
  }

  static Future<FeeConditionConfig> getConfigFor(String conditionName) async {
    final configs = await getConditionConfigs();
    final match = configs.firstWhere(
      (c) => c.conditionName.toLowerCase() == conditionName.toLowerCase(),
      orElse: () => FeeConditionConfig(
        conditionName: conditionName,
        fields: [
          FeeConditionFieldConfig(
            id: 'monthly_fees',
            label: 'Monthly Fees (₹)',
            fieldType: 'number',
            mathAction: 'add',
          ),
        ],
      ),
    );
    return match;
  }

  /// Helper to calculate academic session months from Madarsah Start Date and End Date.
  static int calculateSessionMonths(Map<String, dynamic>? config) {
    if (config == null) return 12;
    final startDateStr = config['start_date']?.toString();
    final endDateStr = config['end_date']?.toString();
    int sessionMonths = 12;
    if (startDateStr != null && endDateStr != null && startDateStr.isNotEmpty && endDateStr.isNotEmpty) {
      try {
        final start = DateTime.parse(startDateStr.trim());
        final end = DateTime.parse(endDateStr.trim());
        if (!end.isBefore(start)) {
          int m = (end.year - start.year) * 12 + (end.month - start.month);
          if (end.day >= 15) m += 1;
          if (start.day > 20) m -= 1;
          if (m > 0) sessionMonths = m;
        }
      } catch (_) {}
    } else {
      final m = (config['total_months'] as num?)?.toInt() ??
          (config['session_months'] as num?)?.toInt() ??
          12;
      if (m > 0) sessionMonths = m;
    }
    return sessionMonths;
  }

  /// Calculates dynamic fees including flat deductions, percentage discounts, and billing time multiplier.
  static FeeCalculationResult calculateConditionFees({
    required List<FeeConditionFieldConfig> fields,
    required Map<String, String> rawFieldValues,
    Map<String, String>? fieldTargets,
    Map<String, String>? fieldDiscountModes,
    double fallbackMonthlyFee = 0.0,
    double fallbackAdmissionFee = 0.0,
    double fallbackBookFee = 0.0,
    double fallbackContributorAmount = 0.0,
    int sessionMonths = 12,
    List<BillingFrequencyOption>? frequencies,
  }) {
    final fieldAmounts = <String, double>{};
    final annualFieldAmounts = <String, double>{};
    final fieldBillingMonths = <String, int>{};
    double grossTotal = 0.0;
    double annualGrossTotal = 0.0;

    int resolveMonths(FeeConditionFieldConfig f) {
      if (frequencies != null && frequencies.isNotEmpty) {
        final match = frequencies.where((freq) =>
            freq.id == f.billingType ||
            freq.name.trim().toLowerCase() == f.billingType.trim().toLowerCase()).firstOrNull;
        if (match != null) {
          if (match.id == 'session' || match.name.toLowerCase() == 'session') {
            return match.months > 0 ? match.months : (sessionMonths > 0 ? sessionMonths : 10);
          }
          if (match.id == 'monthly' || match.name.toLowerCase() == 'monthly') {
            return f.billingMonths > 0
                ? f.billingMonths
                : (match.months > 1 ? match.months : (sessionMonths > 0 ? sessionMonths : 12));
          }
          return match.months > 0 ? match.months : 1;
        }
      }
      if (f.billingType == 'one_time') return 1;
      if (f.billingType == 'yearly') return 12;
      if (f.billingType == 'half_yearly') return 6;
      if (f.billingType == 'quarterly') return 3;
      if (f.billingType == 'session') return sessionMonths > 0 ? sessionMonths : 12;
      if (f.billingType == 'monthly') {
        return f.billingMonths > 0 ? f.billingMonths : (sessionMonths > 0 ? sessionMonths : 12);
      }
      return f.billingMonths > 0 ? f.billingMonths : 1;
    }

    // 1. Accumulate positive (add) fee fields
    for (final f in fields) {
      if (f.fieldType == 'number' && f.mathAction == 'add') {
        final m = resolveMonths(f);
        fieldBillingMonths[f.id] = m;

        final raw = rawFieldValues[f.id]?.trim() ?? '';
        final clean = raw.replaceAll(RegExp(r'[^\d.]'), '');
        double val = double.tryParse(clean) ?? 0.0;
        final fLower = '${f.id} ${f.label}'.toLowerCase();
        if (val <= 0.0) {
          if (fLower.contains('monthly') || fLower.contains('tuition')) {
            val = fallbackMonthlyFee;
          } else if (fLower.contains('admission') || fLower.contains('dakhila')) {
            val = fallbackAdmissionFee;
          } else if (fLower.contains('book') || fLower.contains('kitab')) {
            val = fallbackBookFee;
          }
        }
        fieldAmounts[f.id] = val;
        annualFieldAmounts[f.id] = val * m;
        grossTotal += val;
        annualGrossTotal += val * m;
      }
    }

    if (grossTotal == 0.0 && fallbackMonthlyFee > 0.0) {
      grossTotal = fallbackMonthlyFee;
      annualGrossTotal = fallbackMonthlyFee * sessionMonths;
    }
    if (fallbackAdmissionFee > 0.0 && !fields.any((f) => f.label.toLowerCase().contains('admission') || f.label.toLowerCase().contains('dakhila'))) {
      grossTotal += fallbackAdmissionFee;
      annualGrossTotal += fallbackAdmissionFee;
    }
    if (fallbackBookFee > 0.0 && !fields.any((f) => f.label.toLowerCase().contains('book') || f.label.toLowerCase().contains('kitab'))) {
      grossTotal += fallbackBookFee;
      annualGrossTotal += fallbackBookFee;
    }

    // 2. Compute deductions for discount and subtract fields
    double totalDeductions = 0.0;
    double annualTotalDeductions = 0.0;
    final fieldDeductions = <String, double>{};
    final fieldDeductionDisplays = <String, String>{};

    for (final f in fields) {
      if (f.fieldType == 'number' && f.isDeduction) {
        final m = resolveMonths(f);
        fieldBillingMonths[f.id] = m;

        final raw = rawFieldValues[f.id]?.trim() ?? '';
        if (raw.isEmpty) continue;

        final mode = fieldDiscountModes?[f.id] ?? f.discountMode;
        final isPercent = raw.contains('%') || mode == 'percentage';
        final clean = raw.replaceAll(RegExp(r'[^\d.]'), '');
        final numVal = double.tryParse(clean) ?? 0.0;
        if (numVal <= 0) continue;

        // Base amount resolution: default to grossTotal / annualGrossTotal
        double baseUnit = grossTotal;
        double baseAnnual = annualGrossTotal;
        String baseName = 'Total';
        final target = (fieldTargets?[f.id] ?? f.targetFeeField).toLowerCase().trim();

        if (target != 'all' && target.isNotEmpty) {
          FeeConditionFieldConfig? targetField;
          for (final tf in fields) {
            final tId = tf.id.toLowerCase().trim();
            final tLabel = tf.label.toLowerCase().trim();
            final tClean = tLabel.replaceAll(RegExp(r'\(.*?\)'), '').trim();
            if (tId == target || tLabel == target || tClean == target) {
              targetField = tf;
              break;
            }
            if (target == 'monthly_fees' && (tId.contains('month') || tLabel.contains('month') || tLabel.contains('tuition'))) {
              targetField = tf;
              break;
            }
            if (target == 'admission_fee' && (tId.contains('admission') || tLabel.contains('admission') || tLabel.contains('dakhila'))) {
              targetField = tf;
              break;
            }
            if (target == 'book_fee' && (tId.contains('book') || tLabel.contains('book') || tLabel.contains('kitab'))) {
              targetField = tf;
              break;
            }
          }

          if (targetField != null) {
            baseUnit = fieldAmounts[targetField.id] ?? 0.0;
            baseAnnual = annualFieldAmounts[targetField.id] ?? (baseUnit * resolveMonths(targetField));
            baseName = targetField.label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
            if (baseUnit <= 0.0) {
              final tfText = '${targetField.id} ${targetField.label}'.toLowerCase();
              if (tfText.contains('monthly') || tfText.contains('tuition')) {
                baseUnit = fallbackMonthlyFee;
                baseAnnual = fallbackMonthlyFee * resolveMonths(targetField);
              } else if (tfText.contains('admission') || tfText.contains('dakhila')) {
                baseUnit = fallbackAdmissionFee;
                baseAnnual = fallbackAdmissionFee;
              } else if (tfText.contains('book') || tfText.contains('kitab')) {
                baseUnit = fallbackBookFee;
                baseAnnual = fallbackBookFee;
              }
            }
          } else {
            if (target == 'monthly_fees' || target.contains('monthly') || target.contains('tuition')) {
              baseUnit = fallbackMonthlyFee;
              baseAnnual = fallbackMonthlyFee * sessionMonths;
              baseName = 'Monthly Fees';
            } else if (target == 'admission_fee' || target.contains('admission') || target.contains('dakhila')) {
              baseUnit = fallbackAdmissionFee;
              baseAnnual = fallbackAdmissionFee;
              baseName = 'Admission Fee';
            } else if (target == 'book_fee' || target.contains('book') || target.contains('kitab')) {
              baseUnit = fallbackBookFee;
              baseAnnual = fallbackBookFee;
              baseName = 'Book Fee';
            }
          }
        }

        double unitDeduction = 0.0;
        double annualDeduction = 0.0;

        if (isPercent) {
          unitDeduction = (baseUnit * numVal) / 100.0;
          annualDeduction = (baseAnnual * numVal) / 100.0;
          fieldDeductions[f.id] = unitDeduction;
          fieldDeductionDisplays[f.id] =
              '-₹${unitDeduction.toStringAsFixed(0)} (${numVal.toStringAsFixed(0)}% of $baseName)';
        } else {
          // Flat amount: if billingType is monthly, numVal is monthly rate; otherwise annual
          if (f.billingType == 'monthly') {
            unitDeduction = numVal.clamp(0.0, baseUnit > 0 ? baseUnit : double.infinity);
            annualDeduction = unitDeduction * m;
          } else {
            annualDeduction = numVal.clamp(0.0, baseAnnual > 0 ? baseAnnual : double.infinity);
            unitDeduction = m > 0 ? (annualDeduction / m) : annualDeduction;
          }
          fieldDeductions[f.id] = unitDeduction;
          fieldDeductionDisplays[f.id] = '-₹${unitDeduction.toStringAsFixed(0)}';
        }

        totalDeductions += unitDeduction;
        annualTotalDeductions += annualDeduction;
      }
    }

    if (fields.isEmpty && totalDeductions == 0.0 && fallbackContributorAmount > 0.0) {
      totalDeductions = fallbackContributorAmount;
      annualTotalDeductions = fallbackContributorAmount * sessionMonths;
    }

    final netTotal = (grossTotal - totalDeductions).clamp(0.0, double.infinity);
    final annualNetTotal = (annualGrossTotal - annualTotalDeductions).clamp(0.0, double.infinity);

    // Calculate monthly payable net (e.g. Total 6000 - 10% disc = 5400, monthly = 450)
    double monthlyNetPayable = 0.0;
    final monthlyFieldId = fields.where((f) =>
      f.fieldType == 'number' && f.mathAction == 'add' &&
      (f.id == 'monthly_fees' || f.id.contains('month') || f.label.toLowerCase().contains('month') || f.label.toLowerCase().contains('tuition'))
    ).map((f) => f.id).firstOrNull;

    if (monthlyFieldId != null) {
      final monthlyUnit = fieldAmounts[monthlyFieldId] ?? 0.0;
      final monthlyMonths = fieldBillingMonths[monthlyFieldId] ?? sessionMonths;
      final monthlyAnnual = annualFieldAmounts[monthlyFieldId] ?? (monthlyUnit * monthlyMonths);

      double monthlyDeductionsAnnual = 0.0;
      for (final f in fields) {
        if (f.fieldType == 'number' && f.isDeduction) {
          final target = (fieldTargets?[f.id] ?? f.targetFeeField).toLowerCase().trim();
          if (target == monthlyFieldId.toLowerCase().trim() || target == 'monthly_fees' || target.contains('month') || target.contains('tuition')) {
            final raw = rawFieldValues[f.id]?.trim() ?? '';
            final mode = fieldDiscountModes?[f.id] ?? f.discountMode;
            final isPercent = raw.contains('%') || mode == 'percentage';
            final clean = raw.replaceAll(RegExp(r'[^\d.]'), '');
            final numVal = double.tryParse(clean) ?? 0.0;
            if (isPercent) {
              monthlyDeductionsAnnual += (monthlyAnnual * numVal) / 100.0;
            } else {
              monthlyDeductionsAnnual += (f.billingType == 'monthly' ? (numVal * (fieldBillingMonths[f.id] ?? monthlyMonths)) : numVal);
            }
          } else if (target == 'all' || target.isEmpty) {
            if (annualGrossTotal > 0) {
              final share = monthlyAnnual / annualGrossTotal;
              final raw = rawFieldValues[f.id]?.trim() ?? '';
              final mode = fieldDiscountModes?[f.id] ?? f.discountMode;
              final isPercent = raw.contains('%') || mode == 'percentage';
              final clean = raw.replaceAll(RegExp(r'[^\d.]'), '');
              final numVal = double.tryParse(clean) ?? 0.0;
              if (isPercent) {
                monthlyDeductionsAnnual += (monthlyAnnual * numVal) / 100.0;
              } else {
                final totalDisc = f.billingType == 'monthly' ? (numVal * (fieldBillingMonths[f.id] ?? monthlyMonths)) : numVal;
                monthlyDeductionsAnnual += totalDisc * share;
              }
            }
          }
        }
      }
      final monthlyNetAnnual = (monthlyAnnual - monthlyDeductionsAnnual).clamp(0.0, double.infinity);
      monthlyNetPayable = monthlyMonths > 0 ? (monthlyNetAnnual / monthlyMonths) : monthlyNetAnnual;
    } else {
      monthlyNetPayable = sessionMonths > 0 ? (annualNetTotal / sessionMonths) : annualNetTotal;
    }

    return FeeCalculationResult(
      grossTotal: grossTotal,
      totalDeductions: totalDeductions,
      netTotal: netTotal,
      fieldAmounts: fieldAmounts,
      fieldDeductions: fieldDeductions,
      fieldDeductionDisplays: fieldDeductionDisplays,
      annualGrossTotal: annualGrossTotal,
      annualTotalDeductions: annualTotalDeductions,
      annualNetTotal: annualNetTotal,
      monthlyNetPayable: monthlyNetPayable,
      annualFieldAmounts: annualFieldAmounts,
      fieldBillingMonths: fieldBillingMonths,
    );
  }
}

class FeeCalculationResult {
  final double grossTotal;
  final double totalDeductions;
  final double netTotal;
  final Map<String, double> fieldAmounts;
  final Map<String, double> fieldDeductions;
  final Map<String, String> fieldDeductionDisplays;
  final double annualGrossTotal;
  final double annualTotalDeductions;
  final double annualNetTotal;
  final double monthlyNetPayable;
  final Map<String, double> annualFieldAmounts;
  final Map<String, int> fieldBillingMonths;

  const FeeCalculationResult({
    required this.grossTotal,
    required this.totalDeductions,
    required this.netTotal,
    required this.fieldAmounts,
    required this.fieldDeductions,
    required this.fieldDeductionDisplays,
    this.annualGrossTotal = 0.0,
    this.annualTotalDeductions = 0.0,
    this.annualNetTotal = 0.0,
    this.monthlyNetPayable = 0.0,
    this.annualFieldAmounts = const {},
    this.fieldBillingMonths = const {},
  });
}

// ── Unified Management Dialog (Fee Conditions & Fee Types) ─────────────────────

class ManageFeeConditionsDialog extends StatefulWidget {
  final int initialTabIndex;

  const ManageFeeConditionsDialog({
    super.key,
    this.initialTabIndex = 0,
  });

  static Future<void> show(BuildContext context, {int initialTabIndex = 0, Color? barrierColor}) async {
    await showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (ctx) => ManageFeeConditionsDialog(initialTabIndex: initialTabIndex),
    );
  }

  @override
  State<ManageFeeConditionsDialog> createState() =>
      _ManageFeeConditionsDialogState();
}

class _ManageFeeConditionsDialogState extends State<ManageFeeConditionsDialog> {
  final _newConditionController = TextEditingController();
  late int _selectedTab;
  List<FeeConditionConfig> _configs = [];
  List<FeeType> _feeTypes = [];
  bool _isLoadingConditions = true;
  bool _isLoadingFeeTypes = true;
  bool _isChildDialogOpen = false;

  Future<T?> _openSubDialog<T>(Future<T?> Function() dialogOpener) async {
    setState(() => _isChildDialogOpen = true);
    try {
      return await dialogOpener();
    } finally {
      if (mounted) {
        setState(() => _isChildDialogOpen = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex;
    _loadConditions();
    _loadFeeTypes();
  }

  @override
  void dispose() {
    _newConditionController.dispose();
    super.dispose();
  }

  Future<void> _loadConditions() async {
    final list = await FeeConditionSettings.getConditionConfigs();
    if (mounted) {
      setState(() {
        _configs = list;
        _isLoadingConditions = false;
      });
    }
  }

  Future<void> _loadFeeTypes() async {
    final list = await FeeTypesHelper.getFeeTypes();
    if (mounted) {
      setState(() {
        _feeTypes = list;
        _isLoadingFeeTypes = false;
      });
    }
  }

  Future<void> _addCondition() async {
    final text = _newConditionController.text.trim();
    if (text.isEmpty) return;

    if (!_configs.any((c) => c.conditionName.toLowerCase() == text.toLowerCase())) {
      _configs.add(
        FeeConditionConfig(
          conditionName: text,
          fields: [
            FeeConditionFieldConfig(
              id: 'monthly_fees',
              label: 'Monthly Fees (₹)',
              fieldType: 'number',
              mathAction: 'add',
            ),
          ],
        ),
      );
      await FeeConditionSettings.saveConditionConfigs(_configs);
    }
    _newConditionController.clear();
    await _loadConditions();
  }

  Future<void> _deleteCondition(String conditionName) async {
    final confirm = await _openSubDialog(() => showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Condition?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to delete the condition "$conditionName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
    if (confirm != true) return;
    _configs.removeWhere((c) => c.conditionName == conditionName);
    await FeeConditionSettings.saveConditionConfigs(_configs);
    await _loadConditions();
  }

  Future<void> _renameCondition(FeeConditionConfig config) async {
    final controller = TextEditingController(text: config.conditionName);
    final formKey = GlobalKey<FormState>();
    final newName = await _openSubDialog(() => showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Condition Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Condition Name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dContext, controller.text.trim());
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
            child: const Text('Save'),
          ),
        ],
      ),
    ));

    if (newName != null && newName.isNotEmpty && newName != config.conditionName) {
      final index = _configs.indexWhere((c) => c.conditionName == config.conditionName);
      if (index != -1) {
        _configs[index] = FeeConditionConfig(conditionName: newName, fields: config.fields);
        await FeeConditionSettings.saveConditionConfigs(_configs);
        await _loadConditions();
      }
    }
  }

  Future<void> _editConditionFields(FeeConditionConfig config) async {
    await _openSubDialog(() => EditConditionFieldsDialog.show(context, config, (updatedConfig) async {
      final index = _configs.indexWhere((c) => c.conditionName == config.conditionName);
      if (index != -1) {
        _configs[index] = updatedConfig;
        await FeeConditionSettings.saveConditionConfigs(_configs);
        await _loadConditions();
      }
    }));
    // Also reload fee types in case any new fee types were added while configuring fields
    await _loadFeeTypes();
  }

  Future<void> _openAddFeeTypeDialog() async {
    await _openSubDialog(() => AddEditFeeTypeDialog.show(
      context,
      onSave: (name, billingType, defaultMonths, defaultAmount) async {
        await FeeTypesHelper.addFeeType(
          name,
          billingType: billingType,
          defaultMonths: defaultMonths,
          defaultAmount: defaultAmount,
        );
        await _loadFeeTypes();
      },
    ));
  }

  Future<void> _openEditFeeTypeDialog(FeeType t) async {
    await _openSubDialog(() => AddEditFeeTypeDialog.show(
      context,
      initialFeeType: t,
      onSave: (name, billingType, defaultMonths, defaultAmount) async {
        await FeeTypesHelper.updateFeeType(
          t.id,
          name,
          billingType: billingType,
          defaultMonths: defaultMonths,
          defaultAmount: defaultAmount,
        );
        await _loadFeeTypes();
      },
    ));
  }

  Future<void> _deleteFeeType(FeeType t) async {
    final confirm = await _openSubDialog(() => showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Fee Type?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to delete "${t.name}"? This fee type will no longer be available for new entries.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
    if (confirm != true) return;
    await FeeTypesHelper.deleteFeeType(t.id);
    await _loadFeeTypes();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF222234) : Colors.white;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    return Visibility(
      visible: !_isChildDialogOpen,
      maintainState: true,
      maintainSize: false,
      maintainAnimation: false,
      maintainInteractivity: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          width: 660,
          constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (_selectedTab == 0 ? const Color(0xFFD4AF37) : Colors.blue).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _selectedTab == 0 ? Icons.tune_rounded : Icons.category_rounded,
                      color: _selectedTab == 0 ? const Color(0xFFD4AF37) : Colors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fee Conditions & Fee Types',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedTab == 0
                              ? 'Manage student categories (Day Scholar, Hosteller, etc.) & fee structures'
                              : 'Manage recurring & one-time fee heads (Admission, Tuition, Books, Exams)',
                          style: TextStyle(fontSize: 11.5, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subtitleColor),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Segmented Tab Selector Bar
              Container(
                height: 46,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222234) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    // Tab 0: Fee Conditions
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _selectedTab = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? (isDark ? const Color(0xFF2D2D42) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _selectedTab == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(isDark ? 50 : 15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 16,
                                color: _selectedTab == 0 ? const Color(0xFFD4AF37) : subtitleColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Fee Conditions',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _selectedTab == 0 ? FontWeight.bold : FontWeight.w500,
                                  color: _selectedTab == 0 ? textColor : subtitleColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 0
                                      ? const Color(0xFFD4AF37).withAlpha(35)
                                      : (isDark ? Colors.white12 : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_configs.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTab == 0 ? const Color(0xFFD4AF37) : subtitleColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Tab 1: Fee Types
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _selectedTab = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? (isDark ? const Color(0xFF2D2D42) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _selectedTab == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(isDark ? 50 : 15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.category_rounded,
                                size: 16,
                                color: _selectedTab == 1 ? Colors.blue : subtitleColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Fee Types (Heads)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: _selectedTab == 1 ? FontWeight.bold : FontWeight.w500,
                                  color: _selectedTab == 1 ? textColor : subtitleColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 1
                                      ? Colors.blue.withAlpha(35)
                                      : (isDark ? Colors.white12 : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_feeTypes.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTab == 1 ? Colors.blue : subtitleColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Tab 0 Content: Fee Conditions
              if (_selectedTab == 0) ...[
                // Input bar to add new condition
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF222234) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.playlist_add_rounded, color: Color(0xFFD4AF37), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _newConditionController,
                          style: TextStyle(fontSize: 13.5, color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Enter new condition name (e.g. Day Scholar, Hosteller, Staff Child)...',
                            hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.grey.shade500),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _addCondition(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _addCondition,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Condition', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (_isLoadingConditions)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _configs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final cfg = _configs[index];
                        final addCount = cfg.fields.where((f) => f.mathAction == 'add').length;
                        final subCount = cfg.fields.where((f) => f.isDeduction).length;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 20 : 6),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37).withAlpha(25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.layers_rounded, color: Color(0xFFD4AF37), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cfg.conditionName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withAlpha(20),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.blue.withAlpha(40)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.view_list_rounded, size: 11, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${cfg.fields.length} Fields',
                                                style: const TextStyle(fontSize: 10.5, color: Colors.blue, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (addCount > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF22C55E).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF22C55E).withAlpha(50)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.add_circle_outline_rounded, size: 11, color: Color(0xFF22C55E)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '+$addCount Add',
                                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF22C55E), fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (subCount > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFEF4444).withAlpha(50)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.remove_circle_outline_rounded, size: 11, color: Color(0xFFEF4444)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '-$subCount Concession',
                                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Prominent CTA: Configure Fields
                              FilledButton.icon(
                                onPressed: () => _editConditionFields(cfg),
                                icon: const Icon(Icons.tune_rounded, size: 15),
                                label: const Text('Configure Fields', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D6B4E).withAlpha(isDark ? 50 : 20),
                                  foregroundColor: const Color(0xFF0D6B4E),
                                  elevation: 0,
                                  side: BorderSide(color: const Color(0xFF0D6B4E).withAlpha(120), width: 1.2),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Rename Condition',
                                child: IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 18),
                                  onPressed: () => _renameCondition(cfg),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.orange.withAlpha(20),
                                    padding: const EdgeInsets.all(8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Delete Condition',
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  onPressed: () => _deleteCondition(cfg.conditionName),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red.withAlpha(20),
                                    padding: const EdgeInsets.all(8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ]
              // Tab 1 Content: Fee Types
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withAlpha(40)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Standard fee heads with default billing frequency and amounts.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.blue.shade200 : const Color(0xFF1E40AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _openSubDialog(() => ManageBillingFrequenciesDialog.show(context));
                          await _loadFeeTypes();
                        },
                        icon: const Icon(Icons.repeat_rounded, size: 15),
                        label: const Text('Frequencies', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _openAddFeeTypeDialog,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add Fee Type', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (_isLoadingFeeTypes)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_feeTypes.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category_rounded, size: 42, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            'No Fee Types Configured Yet',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Click "+ Add Fee Type" to create Admission, Tuition, Books etc.',
                            style: TextStyle(fontSize: 12, color: subtitleColor),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _feeTypes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final t = _feeTypes[index];
                        final billingLabel = t.billingType == 'one_time'
                            ? 'One-Time'
                            : t.billingType == 'yearly'
                                ? 'Yearly'
                                : 'Monthly (${t.defaultMonths} mo)';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 20 : 6),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.payments_rounded, size: 18, color: Colors.blue),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withAlpha(20),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.blue.withAlpha(50)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.repeat_rounded, size: 11, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              Text(
                                                billingLabel,
                                                style: const TextStyle(fontSize: 10.5, color: Colors.blue, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (t.defaultAmount > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF22C55E).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF22C55E).withAlpha(60)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.currency_rupee_rounded, size: 11, color: Color(0xFF22C55E)),
                                                const SizedBox(width: 2),
                                                Text(
                                                  'Default: ₹${t.defaultAmount.toStringAsFixed(0)}',
                                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF22C55E), fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Tooltip(
                                message: 'Edit Fee Type',
                                child: IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 18),
                                  onPressed: () => _openEditFeeTypeDialog(t),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.orange.withAlpha(20),
                                    padding: const EdgeInsets.all(8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Delete Fee Type',
                                child: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  onPressed: () => _deleteFeeType(t),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red.withAlpha(20),
                                    padding: const EdgeInsets.all(8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],

              const SizedBox(height: 14),
              // Footer
              Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 16, color: isDark ? Colors.amber.shade300 : const Color(0xFFD4AF37)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _selectedTab == 0
                          ? 'Click "Configure Fields" on any condition to link fee heads and concessions.'
                          : 'Fee Types created here will be available to link inside Fee Conditions.',
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: _selectedTab == 0 ? const Color(0xFFD4AF37) : Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Edit Condition Fields Dialog ("Jahan Fee Condition Ki Field Banti Hai") ───

class EditConditionFieldsDialog extends StatefulWidget {
  final FeeConditionConfig config;
  final Function(FeeConditionConfig) onSaved;

  const EditConditionFieldsDialog({
    super.key,
    required this.config,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context,
    FeeConditionConfig config,
    Function(FeeConditionConfig) onSaved, {
    Color? barrierColor,
  }) async {
    await showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.transparent,
      builder: (ctx) => EditConditionFieldsDialog(config: config, onSaved: onSaved),
    );
  }

  @override
  State<EditConditionFieldsDialog> createState() => _EditConditionFieldsDialogState();
}

class _EditConditionFieldsDialogState extends State<EditConditionFieldsDialog> {
  late List<FeeConditionFieldConfig> _fields;
  final _newLabelController = TextEditingController();
  final _newAmountLabelController = TextEditingController();
  String _newFieldCategory = 'number'; // 'number', 'discount', 'contributor', 'staff', 'text'
  String _newMathAction = 'add';
  String _newBillingType = 'monthly';
  int _newBillingMonths = 12;
  List<String> _newMonthsList = [];
  int _sessionMonths = 12;
  List<FeeType> _availableFeeTypes = [];
  bool _isLoadingFeeTypes = true;
  List<BillingFrequencyOption> _availableFrequencies = List.from(BillingFrequencySettings.defaultFrequencies);
  bool _isChildDialogOpen = false;

  Future<T?> _openSubDialog<T>(Future<T?> Function() dialogOpener) async {
    setState(() => _isChildDialogOpen = true);
    try {
      return await dialogOpener();
    } finally {
      if (mounted) {
        setState(() => _isChildDialogOpen = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fields = List<FeeConditionFieldConfig>.from(widget.config.fields);
    _loadFeeTypes();
    _loadSessionMonths();
    _loadFrequencies();
  }

  Future<void> _loadFrequencies() async {
    final list = await BillingFrequencySettings.getFrequencies();
    if (mounted) {
      setState(() {
        final seen = <String>{};
        _availableFrequencies = list.where((f) => seen.add(f.id)).toList();
        final match = _availableFrequencies.where((f) => f.id == _newBillingType || f.name.toLowerCase() == _newBillingType.toLowerCase()).firstOrNull;
        if (match != null) {
          _newBillingType = match.id;
          _newBillingMonths = (match.id == 'monthly' || match.name.toLowerCase() == 'monthly') && match.months == 1 && _sessionMonths > 1
              ? _sessionMonths
              : match.months;
          _newMonthsList = List.from(match.monthsList);
        } else if (_availableFrequencies.isNotEmpty) {
          _newBillingType = _availableFrequencies.first.id;
          _newBillingMonths = _availableFrequencies.first.months > 0 ? _availableFrequencies.first.months : 1;
          _newMonthsList = List.from(_availableFrequencies.first.monthsList);
        }
      });
    }
  }

  @override
  void dispose() {
    _newLabelController.dispose();
    _newAmountLabelController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionMonths() async {
    try {
      final cfg = await DatabaseHelper().getCurrentAcademicSessionConfig();
      final m = FeeConditionSettings.calculateSessionMonths(cfg);
      if (mounted) {
        setState(() {
          _sessionMonths = m;
          if (_newBillingType == 'monthly' || _newBillingType == 'session') {
            _newBillingMonths = m;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFeeTypes() async {
    final types = await FeeTypesHelper.getFeeTypes();
    if (mounted) {
      setState(() {
        _availableFeeTypes = types;
        _isLoadingFeeTypes = false;
      });
    }
  }

  bool _isFeeTypeAlreadyField(String feeTypeName) {
    final clean = feeTypeName.trim().toLowerCase();
    return _fields.any((f) {
      final fClean = f.label.replaceAll(RegExp(r'\(.*?\)'), '').trim().toLowerCase();
      return fClean == clean || f.label.toLowerCase().contains(clean);
    });
  }

  void _addFeeTypeAsField(FeeType t) {
    if (_isFeeTypeAlreadyField(t.name)) return;
    final id = 'fee_type_field_${t.id}_${DateTime.now().millisecondsSinceEpoch}';
    final bType = t.billingType;
    final bMonths = t.defaultMonths > 0 ? t.defaultMonths : (bType == 'one_time' ? 1 : _sessionMonths);
    setState(() {
      _fields.add(
        FeeConditionFieldConfig(
          id: id,
          label: '${t.name} (₹)',
          fieldType: 'number',
          mathAction: 'add',
          fieldSource: 'other',
          billingType: bType,
          billingMonths: bMonths,
        ),
      );
    });
  }

  Future<void> _editFeeType(FeeType t) async {
    await _openSubDialog(() => AddEditFeeTypeDialog.show(
      context,
      initialFeeType: t,
      onSave: (name, billingType, defaultMonths, defaultAmount) async {
        await FeeTypesHelper.updateFeeType(
          t.id,
          name,
          billingType: billingType,
          defaultMonths: defaultMonths,
          defaultAmount: defaultAmount,
        );
        if (mounted) {
          setState(() {
            for (var i = 0; i < _fields.length; i++) {
              if (_fields[i].id.contains('fee_type_field_${t.id}') ||
                  _fields[i].label.trim().toLowerCase() == '${t.name.trim().toLowerCase()} (₹)') {
                _fields[i] = FeeConditionFieldConfig(
                  id: _fields[i].id,
                  label: '$name (₹)',
                  fieldType: _fields[i].fieldType,
                  mathAction: _fields[i].mathAction,
                  fieldSource: _fields[i].fieldSource,
                  billingType: billingType,
                  billingMonths: defaultMonths,
                );
              }
            }
          });
          await _loadFeeTypes();
        }
      },
    ));
  }

  Future<void> _deleteFeeType(FeeType t) async {
    final confirm = await _openSubDialog(() => showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Fee Type?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to delete "${t.name}"? This fee type will no longer be available for new entries.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
    if (confirm != true) return;
    await FeeTypesHelper.deleteFeeType(t.id);
    if (mounted) {
      setState(() {
        _fields.removeWhere((f) =>
            f.id.contains('fee_type_field_${t.id}') ||
            f.label.trim().toLowerCase() == '${t.name.trim().toLowerCase()} (₹)');
      });
      await _loadFeeTypes();
    }
  }

  Future<void> _quickCreateFeeType() async {
    await _openSubDialog(() => AddEditFeeTypeDialog.show(
      context,
      onSave: (name, billingType, defaultMonths, defaultAmount) async {
        final newType = await FeeTypesHelper.addFeeType(
          name,
          billingType: billingType,
          defaultMonths: defaultMonths,
          defaultAmount: defaultAmount,
        );
        await _loadFeeTypes();
        _addFeeTypeAsField(newType);
      },
    ));
  }

  void _addField() {
    String label = _newLabelController.text.trim();
    if (label.isEmpty) {
      if (_newFieldCategory == 'contributor') {
        label = 'Contributor Name';
      } else if (_newFieldCategory == 'staff') {
        label = 'Staff Member Name';
      } else {
        return;
      }
    }

    if (_newFieldCategory == 'contributor') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final contribId = _fields.any((f) => f.id == 'contributor_id') ? 'contributor_id_$now' : 'contributor_id';
      final amountId = _fields.any((f) => f.id == 'contributor_amount') ? 'contributor_amount_$now' : 'contributor_amount';

      final amountLabelInput = _newAmountLabelController.text.trim();
      final amountLabel = amountLabelInput.isNotEmpty
          ? (amountLabelInput.contains('(') ? amountLabelInput : '$amountLabelInput (₹)')
          : 'Contributor Amount (₹)';

      final amountMath = (_newMathAction == 'none' || _newMathAction == 'add' || _newMathAction == 'discount' || _newMathAction == 'subtract' || _newMathAction == 'multiply' || _newMathAction == 'divide')
          ? _newMathAction
          : 'subtract';

      setState(() {
        _fields.add(
          FeeConditionFieldConfig(
            id: contribId,
            label: label,
            fieldType: 'contributor',
            mathAction: 'none',
            fieldSource: 'contributor',
            billingType: 'one_time',
            billingMonths: 1,
          ),
        );
        _fields.add(
          FeeConditionFieldConfig(
            id: amountId,
            label: amountLabel,
            fieldType: 'number',
            mathAction: amountMath,
            fieldSource: 'contributor',
            targetFeeField: 'all',
            discountMode: amountMath == 'discount' ? 'auto' : 'flat',
            billingType: _newBillingType,
            billingMonths: _newBillingMonths,
            monthsList: _newMonthsList,
          ),
        );
        _newLabelController.clear();
        _newAmountLabelController.clear();
      });
      return;
    }

    if (_newFieldCategory == 'staff') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final staffId = _fields.any((f) => f.id == 'staff_id') ? 'staff_id_$now' : 'staff_id';
      final amountId = _fields.any((f) => f.id == 'staff_discount') ? 'staff_amount_$now' : 'staff_discount';

      final amountLabelInput = _newAmountLabelController.text.trim();
      final amountLabel = amountLabelInput.isNotEmpty
          ? (amountLabelInput.contains('(') ? amountLabelInput : '$amountLabelInput (₹)')
          : 'Staff Concession (₹)';

      final amountMath = (_newMathAction == 'none' || _newMathAction == 'add' || _newMathAction == 'discount' || _newMathAction == 'subtract' || _newMathAction == 'multiply' || _newMathAction == 'divide')
          ? _newMathAction
          : 'subtract';

      setState(() {
        _fields.add(
          FeeConditionFieldConfig(
            id: staffId,
            label: label,
            fieldType: 'staff',
            mathAction: 'none',
            fieldSource: 'staff',
            billingType: 'one_time',
            billingMonths: 1,
          ),
        );
        _fields.add(
          FeeConditionFieldConfig(
            id: amountId,
            label: amountLabel,
            fieldType: 'number',
            mathAction: amountMath,
            fieldSource: 'staff',
            targetFeeField: 'all',
            discountMode: amountMath == 'discount' ? 'auto' : 'flat',
            billingType: _newBillingType,
            billingMonths: _newBillingMonths,
            monthsList: _newMonthsList,
          ),
        );
        _newLabelController.clear();
        _newAmountLabelController.clear();
      });
      return;
    }

    final id = 'field_${DateTime.now().millisecondsSinceEpoch}';
    String finalType = _newFieldCategory;
    String finalSource = 'other';

    if (_newFieldCategory == 'discount') {
      finalType = 'number';
      finalSource = 'other';
    } else if (_newFieldCategory == 'number') {
      finalType = 'number';
      finalSource = 'other';
    } else {
      finalType = 'text';
      finalSource = 'other';
    }

    final isDiscount = _newFieldCategory == 'discount' || _newMathAction == 'discount';
    final resolvedMath = finalType == 'number'
        ? (isDiscount ? 'discount' : _newMathAction)
        : 'none';

    setState(() {
      _fields.add(
        FeeConditionFieldConfig(
          id: id,
          label: label,
          fieldType: finalType,
          mathAction: resolvedMath,
          fieldSource: finalSource,
          targetFeeField: 'all',
          discountMode: 'auto',
          billingType: _newBillingType,
          billingMonths: _newBillingMonths,
          monthsList: _newMonthsList,
        ),
      );
      _newLabelController.clear();
      _newAmountLabelController.clear();
    });
  }

  void _removeField(int index) {
    setState(() {
      _fields.removeAt(index);
    });
  }

  Future<void> _editField(int index) async {
    final f = _fields[index];
    final labelCtrl = TextEditingController(text: f.label);
    String mathAction = f.mathAction;
    String billingType = f.billingType;
    int billingMonths = f.billingMonths;
    List<String> fieldMonthsList = List<String>.from(f.monthsList);
    final monthsCtrl = TextEditingController(text: billingMonths.toString());
    String targetFee = f.targetFeeField;
    String discountMode = f.discountMode;

    await _openSubDialog(() => showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF0D6B4E), size: 22),
                  const SizedBox(width: 8),
                  const Text('Edit Field Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: labelCtrl,
                        decoration: InputDecoration(
                          labelText: 'Field Label / Name',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          prefixIcon: const Icon(Icons.label_outline_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (f.fieldType == 'number') ...[
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: mathAction,
                          decoration: InputDecoration(
                            labelText: 'Math Calculation Rule',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            prefixIcon: const Icon(Icons.calculate_outlined, size: 18),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'add', child: Text('➕ Addition (+ Add to Total)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'discount', child: Text('🏷️ Discount / Concession (- % or ₹)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'subtract', child: Text('➖ Subtraction (- Flat Deduct)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'multiply', child: Text('✖️ Multiply (* Factor)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'divide', child: Text('➗ Division (/ Divide)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'none', child: Text('⚪ Neutral (Informational only)', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => mathAction = v);
                          },
                        ),
                        const SizedBox(height: 12),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (ctx) {
                                  final uniqueFrequencies = <String, BillingFrequencyOption>{};
                                  for (final freq in _availableFrequencies) {
                                    if (freq.id.isNotEmpty && freq.id != 'custom' && freq.id != '__manage__' && !uniqueFrequencies.containsKey(freq.id)) {
                                      uniqueFrequencies[freq.id] = freq;
                                    }
                                  }

                                  String? safeEditBillingValue;
                                  if (billingType == 'custom') {
                                    safeEditBillingValue = 'custom';
                                  } else if (uniqueFrequencies.containsKey(billingType)) {
                                    safeEditBillingValue = billingType;
                                  } else {
                                    final match = uniqueFrequencies.values.where((freq) =>
                                        freq.name.toLowerCase() == billingType.toLowerCase()).firstOrNull;
                                    if (match != null) {
                                      safeEditBillingValue = match.id;
                                    } else if (uniqueFrequencies.isNotEmpty) {
                                      safeEditBillingValue = uniqueFrequencies.keys.first;
                                    } else {
                                      safeEditBillingValue = null;
                                    }
                                  }

                                  return DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    key: ValueKey('edit_billing_${safeEditBillingValue}_${uniqueFrequencies.length}'),
                                    initialValue: safeEditBillingValue,
                                    decoration: InputDecoration(
                                      labelText: 'Billing Time / Frequency',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      prefixIcon: const Icon(Icons.calendar_month_rounded, size: 18),
                                    ),
                                    items: [
                                      ...uniqueFrequencies.values.map((freq) {
                                        final monthsDisplay = (freq.id == 'monthly' || freq.name.toLowerCase() == 'monthly') && freq.months == 1 && _sessionMonths > 1
                                            ? '$_sessionMonths Months'
                                            : '${freq.months} Months';
                                        return DropdownMenuItem(
                                          value: freq.id,
                                          child: Text('${freq.name} ($monthsDisplay)', overflow: TextOverflow.ellipsis),
                                        );
                                      }),
                                      const DropdownMenuItem(
                                        value: 'custom',
                                        child: Text('Custom Months Count...'),
                                      ),
                                      const DropdownMenuItem(
                                        value: '__manage__',
                                        child: Row(
                                          children: [
                                            Icon(Icons.tune_rounded, size: 15, color: Colors.blue),
                                            SizedBox(width: 6),
                                            Text(
                                              '+ Add / Manage Frequencies...',
                                              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) async {
                                      if (v == '__manage__') {
                                        await _openSubDialog(() => ManageBillingFrequenciesDialog.show(context));
                                        await _loadFrequencies();
                                        setDialogState(() {});
                                        return;
                                      }
                                      if (v != null) {
                                        setDialogState(() {
                                          billingType = v;
                                          if (v != 'custom') {
                                            final match = uniqueFrequencies[v];
                                            if (match != null) {
                                              billingMonths = (match.id == 'monthly' || match.name.toLowerCase() == 'monthly') && match.months == 1 && _sessionMonths > 1
                                                  ? _sessionMonths
                                                  : match.months;
                                              monthsCtrl.text = billingMonths.toString();
                                              fieldMonthsList = List<String>.from(match.monthsList);
                                            }
                                          }
                                        });
                                      }
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: IconButton.filledTonal(
                                tooltip: 'Add / Edit Frequencies',
                                icon: const Icon(Icons.tune_rounded, color: Color(0xFF0D6B4E), size: 18),
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D6B4E).withAlpha(25),
                                  padding: const EdgeInsets.all(10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  await _openSubDialog(() => ManageBillingFrequenciesDialog.show(context));
                                  await _loadFrequencies();
                                  setDialogState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        if (billingType == 'custom') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: monthsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Months Count',
                              hintText: 'e.g. 10, 12, 6...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: const Icon(Icons.numbers_rounded, size: 18),
                            ),
                            onChanged: (v) {
                              final parsed = int.tryParse(v.trim());
                              if (parsed != null && parsed > 0) {
                                billingMonths = parsed;
                              }
                            },
                          ),
                        ],
                        if (mathAction == 'discount' || mathAction == 'subtract') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: discountMode,
                            decoration: InputDecoration(
                              labelText: 'Discount Mode',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              prefixIcon: const Icon(Icons.percent_rounded, size: 18),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('Auto (% or ₹ Switchable)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'percentage', child: Text('Percentage Only (%)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'flat', child: Text('Flat Amount Only (₹)', overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) {
                              if (v != null) setDialogState(() => discountMode = v);
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final newLabel = labelCtrl.text.trim();
                    if (newLabel.isNotEmpty) {
                      final customMonths = int.tryParse(monthsCtrl.text.trim()) ?? billingMonths;
                      setState(() {
                        _fields[index] = _fields[index].copyWith(
                          label: newLabel,
                          mathAction: mathAction,
                          billingType: billingType,
                          billingMonths: customMonths > 0 ? customMonths : 1,
                          targetFeeField: targetFee,
                          discountMode: discountMode,
                          monthsList: fieldMonthsList,
                        );
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
                  child: const Text('Update Field'),
                ),
              ],
            );
          },
        );
      },
    ));
    labelCtrl.dispose();
    monthsCtrl.dispose();
  }

  void _save() {
    widget.onSaved(
      FeeConditionConfig(
        conditionName: widget.config.conditionName,
        fields: _fields,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF222234) : Colors.white;
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

    return Visibility(
      visible: !_isChildDialogOpen,
      maintainState: true,
      maintainSize: false,
      maintainAnimation: false,
      maintainInteractivity: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          width: 660,
          constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6B4E).withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF0D6B4E), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Configure: ${widget.config.conditionName}',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Link fee types, set up discounts & assign contributor/staff dropdowns',
                          style: TextStyle(fontSize: 11.5, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subtitleColor),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Scrollable Body
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Configured Fields Header
                      Row(
                        children: [
                          Text(
                            'Configured Fields (${_fields.length}):',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D6B4E),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.touch_app_rounded, size: 12, color: isDark ? Colors.amber.shade300 : const Color(0xFFD4AF37)),
                                const SizedBox(width: 4),
                                Text(
                                  'Click rule badge to change (+, -, *, /)',
                                  style: TextStyle(fontSize: 10.5, color: subtitleColor, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_fields.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.playlist_add_rounded, size: 36, color: Colors.grey.shade400),
                                const SizedBox(height: 6),
                                Text(
                                  'No fields configured for "${widget.config.conditionName}" yet.',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Click any Fee Type below or add a custom concession field.',
                                  style: TextStyle(fontSize: 11.5, color: subtitleColor),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _fields.length,
                          itemBuilder: (context, index) {
                            final f = _fields[index];
                            final math = f.mathAction;

                            Color mathBg;
                            Color mathColor;
                            String mathText;
                            IconData mathIcon;

                            if (math == 'add') {
                              mathBg = const Color(0xFF22C55E).withAlpha(25);
                              mathColor = const Color(0xFF22C55E);
                              mathText = '+ Addition';
                              mathIcon = Icons.add_circle_outline_rounded;
                            } else if (math == 'discount') {
                              mathBg = const Color(0xFFE11D48).withAlpha(25);
                              mathColor = const Color(0xFFE11D48);
                              mathText = '🏷️ Discount (${f.discountMode == 'percentage' ? '%' : (f.discountMode == 'flat' ? '₹' : '₹/%')})';
                              mathIcon = Icons.discount_outlined;
                            } else if (math == 'subtract') {
                              mathBg = const Color(0xFFEF4444).withAlpha(25);
                              mathColor = const Color(0xFFEF4444);
                              mathText = '- Deduct (Concession)';
                              mathIcon = Icons.remove_circle_outline_rounded;
                            } else if (math == 'multiply') {
                              mathBg = const Color(0xFFA855F7).withAlpha(25);
                              mathColor = const Color(0xFFA855F7);
                              mathText = '* Multiply';
                              mathIcon = Icons.close_rounded;
                            } else if (math == 'divide') {
                              mathBg = const Color(0xFFF97316).withAlpha(25);
                              mathColor = const Color(0xFFF97316);
                              mathText = '/ Divide';
                              mathIcon = Icons.horizontal_rule_rounded;
                            } else {
                              mathBg = Colors.grey.withAlpha(25);
                              mathColor = Colors.grey.shade500;
                              mathText = 'Neutral (Info)';
                              mathIcon = Icons.info_outline_rounded;
                            }

                            final isStaff = f.isStaff;
                            final isContributor = f.isContributor;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 7),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: f.isDeduction
                                      ? const Color(0xFFE11D48).withAlpha(60)
                                      : (isContributor
                                          ? const Color(0xFF0D6B4E).withAlpha(60)
                                          : (isStaff ? Colors.blue.withAlpha(60) : borderColor)),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(isDark ? 18 : 5),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Type Icon
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: (isStaff
                                              ? Colors.blue
                                              : (isContributor
                                                  ? const Color(0xFF0D6B4E)
                                                  : (f.isDeduction ? const Color(0xFFE11D48) : const Color(0xFF22C55E))))
                                          .withAlpha(25),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isStaff
                                          ? Icons.badge_rounded
                                          : (isContributor
                                              ? Icons.volunteer_activism_rounded
                                              : (f.fieldType == 'number'
                                                  ? (f.isDeduction ? Icons.discount_outlined : Icons.currency_rupee_rounded)
                                                  : Icons.notes_rounded)),
                                      size: 16,
                                      color: isStaff
                                          ? Colors.blue
                                          : (isContributor
                                              ? const Color(0xFF0D6B4E)
                                              : (f.isDeduction ? const Color(0xFFE11D48) : const Color(0xFF22C55E))),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            f.label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isContributor) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0D6B4E).withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF0D6B4E).withAlpha(60)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.volunteer_activism_rounded, size: 10, color: Color(0xFF0D6B4E)),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Contributor Dropdown',
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D6B4E)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ] else if (isStaff) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.blue.withAlpha(60)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.badge_rounded, size: 10, color: Colors.blue),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Staff Member Dropdown',
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Interactive Math Rule Button (Popup Selector with quick direct choices!)
                                  if (f.fieldType == 'number') ...[
                                    PopupMenuButton<String>(
                                      tooltip: 'Click to select math calculation rule',
                                      initialValue: f.mathAction,
                                      onSelected: (String action) {
                                        setState(() {
                                          _fields[index] = _fields[index].copyWith(
                                            mathAction: action,
                                          );
                                        });
                                      },
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      color: isDark ? const Color(0xFF262638) : Colors.white,
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'add',
                                          child: Row(
                                            children: [
                                              Icon(Icons.add_circle_outline_rounded, color: Color(0xFF22C55E), size: 16),
                                              SizedBox(width: 8),
                                              Text('+ Addition (Add to Total)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF22C55E))),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'discount',
                                          child: Row(
                                            children: [
                                              Icon(Icons.discount_outlined, color: Color(0xFFE11D48), size: 16),
                                              SizedBox(width: 8),
                                              Text('🏷️ Discount / Concession (- % or ₹)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFE11D48))),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'subtract',
                                          child: Row(
                                            children: [
                                              Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                              SizedBox(width: 8),
                                              Text('- Deduct (Flat Subtraction)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFEF4444))),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'multiply',
                                          child: Row(
                                            children: [
                                              Icon(Icons.close_rounded, color: Color(0xFFA855F7), size: 16),
                                              SizedBox(width: 8),
                                              Text('* Multiply (Factor)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFA855F7))),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'divide',
                                          child: Row(
                                            children: [
                                              Icon(Icons.horizontal_rule_rounded, color: Color(0xFFF97316), size: 16),
                                              SizedBox(width: 8),
                                              Text('/ Divide (Split)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFF97316))),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'none',
                                          child: Row(
                                            children: [
                                              Icon(Icons.info_outline_rounded, color: Colors.grey, size: 16),
                                              SizedBox(width: 8),
                                              Text('Neutral (Informational only)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                                            ],
                                          ),
                                        ),
                                      ],
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: mathBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: mathColor.withAlpha(120)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(mathIcon, size: 13, color: mathColor),
                                            const SizedBox(width: 5),
                                            Text(
                                              mathText,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: mathColor,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(Icons.arrow_drop_down_rounded, size: 16, color: mathColor),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),

                                  // Billing Time Badge
                                  if (f.fieldType == 'number') ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withAlpha(20),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.blue.withAlpha(50)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.calendar_month_rounded, size: 11, color: Colors.blue),
                                          const SizedBox(width: 4),
                                          Text(
                                            _availableFrequencies.where((freq) => freq.id == f.billingType || freq.name.toLowerCase() == f.billingType.toLowerCase()).firstOrNull?.name ??
                                                (f.billingType == 'one_time'
                                                    ? 'One-Time'
                                                    : '${f.billingMonths} Mo'),
                                            style: const TextStyle(fontSize: 10.5, color: Colors.blue, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],

                                  // Edit Field Button
                                  Tooltip(
                                    message: 'Edit field name, math rule & billing time',
                                    child: IconButton(
                                      icon: const Icon(Icons.edit_outlined, color: Colors.orange, size: 18),
                                      onPressed: () => _editField(index),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.orange.withAlpha(20),
                                        padding: const EdgeInsets.all(6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  Tooltip(
                                    message: 'Remove field',
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                      onPressed: () => _removeField(index),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.red.withAlpha(15),
                                        padding: const EdgeInsets.all(6),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 14),

                      // ── SECTION 2: INTEGRATED FEE TYPES ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.blue.withAlpha(40)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withAlpha(25),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(Icons.category_rounded, size: 18, color: Colors.blue),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Add Fee Types into this Condition:',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Click any fee type below to link it as an active field for "${widget.config.conditionName}":',
                                        style: TextStyle(fontSize: 10.5, color: subtitleColor),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: _quickCreateFeeType,
                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                                  label: const Text(
                                    '+ New Fee Type',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                                    elevation: 1,
                                    shadowColor: const Color(0xFF0284C7).withAlpha(80),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            if (_isLoadingFeeTypes)
                              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                            else if (_availableFeeTypes.isEmpty)
                              Row(
                                children: [
                                  Text('No fee types defined.', style: TextStyle(fontSize: 11.5, color: subtitleColor)),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _quickCreateFeeType,
                                    child: const Text(
                                      '+ Create first Fee Type',
                                      style: TextStyle(fontSize: 11.5, color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _availableFeeTypes.map((t) {
                                  final alreadyAdded = _isFeeTypeAlreadyField(t.name);
                                  final amtLabel = t.defaultAmount > 0 ? ' (₹${t.defaultAmount.toStringAsFixed(0)})' : '';

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: alreadyAdded
                                          ? const Color(0xFF22C55E).withAlpha(isDark ? 30 : 18)
                                          : (isDark ? const Color(0xFF28283C) : Colors.white),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: alreadyAdded
                                            ? const Color(0xFF22C55E).withAlpha(90)
                                            : Colors.blue.withAlpha(70),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Tap to link if not already added
                                        InkWell(
                                          onTap: alreadyAdded ? null : () => _addFeeTypeAsField(t),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  alreadyAdded ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                                  size: 14,
                                                  color: alreadyAdded ? const Color(0xFF22C55E) : Colors.blue,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${t.name}$amtLabel',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: alreadyAdded
                                                        ? const Color(0xFF22C55E)
                                                        : (isDark ? Colors.blue.shade200 : const Color(0xFF1E40AF)),
                                                  ),
                                                ),
                                                if (alreadyAdded) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF22C55E).withAlpha(30),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Text(
                                                      'Linked',
                                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF22C55E)),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Fee Type Options Popup Menu
                                        PopupMenuButton<String>(
                                          tooltip: 'Options',
                                          icon: Icon(
                                            Icons.more_vert_rounded,
                                            size: 14,
                                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          color: isDark ? const Color(0xFF262638) : Colors.white,
                                          onSelected: (val) {
                                            if (val == 'edit') {
                                              _editFeeType(t);
                                            } else if (val == 'delete') {
                                              _deleteFeeType(t);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              height: 32,
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_outlined, size: 14, color: Colors.orange),
                                                  SizedBox(width: 8),
                                                  Text('Edit Fee Type', style: TextStyle(fontSize: 11.5)),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              height: 32,
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                                                  SizedBox(width: 8),
                                                  Text('Delete Fee Type', style: TextStyle(fontSize: 11.5, color: Colors.redAccent)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── SECTION 3: ADD CUSTOM FIELD BOX ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D6B4E).withAlpha(12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF0D6B4E).withAlpha(40)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.add_circle_outline_rounded, size: 18, color: Color(0xFF0D6B4E)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Add Custom Field (Concessions, Staff, Contributor):',
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
                                      ),
                                      Text(
                                        'Create discounts (e.g. Scholarship Concession), or contributor/staff dropdowns',
                                        style: TextStyle(fontSize: 10.5, color: subtitleColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _newLabelController,
                              style: TextStyle(fontSize: 13, color: textColor),
                              decoration: InputDecoration(
                                labelText: (_newFieldCategory == 'contributor' || _newFieldCategory == 'staff')
                                    ? 'Dropdown Name / Label *'
                                    : 'Field Name / Label *',
                                labelStyle: TextStyle(fontSize: 11.5, color: subtitleColor),
                                hintText: _newFieldCategory == 'contributor'
                                    ? 'Contributor Name'
                                    : (_newFieldCategory == 'staff'
                                        ? 'Staff Member Name'
                                        : 'e.g. Monthly Fees, Scholarship, Concession Discount...'),
                                hintStyle: TextStyle(fontSize: 11.5, color: isDark ? Colors.white38 : Colors.grey.shade400),
                                prefixIcon: const Icon(Icons.label_outline_rounded, size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF0D6B4E), width: 1.5),
                                ),
                              ),
                            ),
                            if (_newFieldCategory == 'contributor' || _newFieldCategory == 'staff') ...[
                              const SizedBox(height: 10),
                              TextField(
                                controller: _newAmountLabelController,
                                style: TextStyle(fontSize: 13, color: textColor),
                                decoration: InputDecoration(
                                  labelText: _newFieldCategory == 'contributor'
                                      ? 'Amount Field Name (e.g. Contributor Amount (₹))'
                                      : 'Concession Field Name (e.g. Staff Concession (₹))',
                                  labelStyle: TextStyle(fontSize: 11.5, color: subtitleColor),
                                  hintText: _newFieldCategory == 'contributor'
                                      ? 'Contributor Amount (₹)'
                                      : 'Staff Concession (₹)',
                                  hintStyle: TextStyle(fontSize: 11.5, color: isDark ? Colors.white38 : Colors.grey.shade400),
                                  prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFF0D6B4E), width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            // Row 1: Field Category + Math Rule
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Field Type Dropdown
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _newFieldCategory,
                                    dropdownColor: isDark ? const Color(0xFF262638) : Colors.white,
                                    decoration: InputDecoration(
                                      labelText: 'Field Category',
                                      labelStyle: TextStyle(fontSize: 11, color: subtitleColor),
                                      prefixIcon: const Icon(Icons.tune_rounded, size: 17),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: borderColor),
                                      ),
                                    ),
                                    style: TextStyle(fontSize: 12, color: textColor),
                                    items: const [
                                      DropdownMenuItem(value: 'number', child: Text('💵 Numeric Amount (₹)', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'discount', child: Text('🏷️ Discount (% or ₹)', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'contributor', child: Text('🤝 Contributor Dropdown', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'staff', child: Text('👔 Staff Member Dropdown', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'text', child: Text('📝 Custom Text Input', overflow: TextOverflow.ellipsis)),
                                    ],
                                    onChanged: (v) => setState(() {
                                      _newFieldCategory = v!;
                                      if (v == 'discount') {
                                        _newMathAction = 'discount';
                                      } else if (v == 'contributor') {
                                        if (_newLabelController.text.trim().isEmpty || _newLabelController.text.trim() == 'Staff Member Name') {
                                          _newLabelController.text = 'Contributor Name';
                                        }
                                        if (_newAmountLabelController.text.trim().isEmpty) {
                                          _newAmountLabelController.text = 'Contributor Amount (₹)';
                                        }
                                        _newMathAction = 'subtract';
                                      } else if (v == 'staff') {
                                        if (_newLabelController.text.trim().isEmpty || _newLabelController.text.trim() == 'Contributor Name') {
                                          _newLabelController.text = 'Staff Member Name';
                                        }
                                        if (_newAmountLabelController.text.trim().isEmpty) {
                                          _newAmountLabelController.text = 'Staff Concession (₹)';
                                        }
                                        _newMathAction = 'subtract';
                                      } else if (v == 'number') {
                                        _newMathAction = 'add';
                                      }
                                    }),
                                  ),
                                ),
                                if (_newFieldCategory == 'number' || _newFieldCategory == 'contributor' || _newFieldCategory == 'staff' || _newFieldCategory == 'discount') ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      key: ValueKey('math_${_newFieldCategory}_$_newMathAction'),
                                      initialValue: _newMathAction,
                                      dropdownColor: isDark ? const Color(0xFF262638) : Colors.white,
                                      decoration: InputDecoration(
                                        labelText: (_newFieldCategory == 'contributor' || _newFieldCategory == 'staff')
                                            ? 'Amount Math Rule'
                                            : 'Math Rule',
                                        labelStyle: TextStyle(fontSize: 11, color: subtitleColor),
                                        prefixIcon: const Icon(Icons.calculate_outlined, size: 17),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: borderColor),
                                        ),
                                      ),
                                      style: TextStyle(fontSize: 12, color: textColor),
                                      items: const [
                                        DropdownMenuItem(value: 'subtract', child: Text('➖ Subtract (- Concession)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'discount', child: Text('🏷️ Discount (- % or ₹)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'add', child: Text('➕ Addition (+ Add)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'none', child: Text('⚪ Neutral (Info only)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'multiply', child: Text('✖️ Multiply (* Factor)', overflow: TextOverflow.ellipsis)),
                                        DropdownMenuItem(value: 'divide', child: Text('➗ Division (/ Divide)', overflow: TextOverflow.ellipsis)),
                                      ],
                                      onChanged: (v) => setState(() => _newMathAction = v!),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            // Row 2: Billing Time Dropdown + Manage Button
                            if (_newFieldCategory == 'number' || _newFieldCategory == 'contributor' || _newFieldCategory == 'staff' || _newFieldCategory == 'discount') ...[
                              const SizedBox(height: 10),
                              Builder(
                                builder: (context) {
                                  final uniqueFrequencies = <String, BillingFrequencyOption>{};
                                  for (final f in _availableFrequencies) {
                                    if (f.id.isNotEmpty && f.id != '__manage__' && !uniqueFrequencies.containsKey(f.id)) {
                                      uniqueFrequencies[f.id] = f;
                                    }
                                  }

                                  String? safeBillingValue;
                                  if (uniqueFrequencies.containsKey(_newBillingType)) {
                                    safeBillingValue = _newBillingType;
                                  } else {
                                    final match = uniqueFrequencies.values.where((f) =>
                                        f.name.toLowerCase() == _newBillingType.toLowerCase()).firstOrNull;
                                    if (match != null) {
                                      safeBillingValue = match.id;
                                    } else if (uniqueFrequencies.isNotEmpty) {
                                      safeBillingValue = uniqueFrequencies.keys.first;
                                    } else {
                                      safeBillingValue = null;
                                    }
                                  }

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          key: ValueKey('new_billing_${safeBillingValue}_${uniqueFrequencies.length}'),
                                          initialValue: safeBillingValue,
                                          dropdownColor: isDark ? const Color(0xFF262638) : Colors.white,
                                          decoration: InputDecoration(
                                            labelText: 'Billing Time / Frequency',
                                            labelStyle: TextStyle(fontSize: 11, color: subtitleColor),
                                            prefixIcon: const Icon(Icons.calendar_month_rounded, size: 17),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide(color: borderColor),
                                            ),
                                          ),
                                          style: TextStyle(fontSize: 12, color: textColor),
                                          items: [
                                            ...uniqueFrequencies.values.map((f) {
                                              final monthsDisplay = (f.id == 'monthly' || f.name.toLowerCase() == 'monthly') && f.months == 1 && _sessionMonths > 1
                                                  ? '$_sessionMonths Mo'
                                                  : '${f.months} Mo';
                                              return DropdownMenuItem<String>(
                                                value: f.id,
                                                child: Text('${f.name} ($monthsDisplay)', overflow: TextOverflow.ellipsis),
                                              );
                                            }),
                                            const DropdownMenuItem<String>(
                                              value: '__manage__',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.tune_rounded, size: 13, color: Colors.blue),
                                                  SizedBox(width: 4),
                                                  Text('+ Manage...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                          ],
                                          onChanged: (v) async {
                                            if (v == '__manage__') {
                                              await _openSubDialog(() => ManageBillingFrequenciesDialog.show(context));
                                              await _loadFrequencies();
                                              return;
                                            }
                                            if (v != null) {
                                              setState(() {
                                                _newBillingType = v;
                                                final match = uniqueFrequencies[v];
                                                if (match != null) {
                                                  _newBillingMonths = (match.id == 'monthly' || match.name.toLowerCase() == 'monthly') && match.months == 1 && _sessionMonths > 1
                                                      ? _sessionMonths
                                                      : match.months;
                                                  _newMonthsList = List<String>.from(match.monthsList);
                                                }
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'Manage Billing Frequencies',
                                        child: IconButton.filledTonal(
                                          icon: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFF0D6B4E)),
                                          style: IconButton.styleFrom(
                                            backgroundColor: const Color(0xFF0D6B4E).withAlpha(20),
                                            padding: const EdgeInsets.all(8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            await _openSubDialog(() => ManageBillingFrequenciesDialog.show(context));
                                            await _loadFrequencies();
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            if (_newFieldCategory == 'contributor' || _newFieldCategory == 'staff') ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFF0D6B4E)),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      _newFieldCategory == 'contributor'
                                          ? 'Contributor Name dropdown aur Contributor Amount (₹) dono automatically add honge (Math rule aur Billing Time customize kar sakte hain).'
                                          : 'Staff Member dropdown aur Staff Concession (₹) dono automatically add honge (Math rule aur Billing Time customize kar sakte hain).',
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF0D6B4E), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _addField,
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Add Field to Condition', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D6B4E),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_circle_rounded, size: 17),
                    label: const Text('Save Fields Configuration', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D6B4E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Manage Billing Frequencies Dialog ────────────────────────────────────────

class ManageBillingFrequenciesDialog extends StatefulWidget {
  const ManageBillingFrequenciesDialog({super.key});

  static Future<void> show(BuildContext context, {Color? barrierColor}) async {
    await showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.transparent,
      builder: (ctx) => const ManageBillingFrequenciesDialog(),
    );
  }

  @override
  State<ManageBillingFrequenciesDialog> createState() => _ManageBillingFrequenciesDialogState();
}

class _ManageBillingFrequenciesDialogState extends State<ManageBillingFrequenciesDialog> {
  List<BillingFrequencyOption> _frequencies = [];
  bool _isLoading = true;
  bool _isChildDialogOpen = false;
  final _nameController = TextEditingController();
  final _monthsController = TextEditingController(text: '12');
  BillingFrequencyOption? _editingFrequency;
  List<String> _selectedMonths = [];

  Future<T?> _openSubDialog<T>(Future<T?> Function() dialogOpener) async {
    setState(() => _isChildDialogOpen = true);
    try {
      return await dialogOpener();
    } finally {
      if (mounted) {
        setState(() => _isChildDialogOpen = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _monthsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await BillingFrequencySettings.getFrequencies();
    if (mounted) {
      setState(() {
        final seen = <String>{};
        _frequencies = list.where((f) => seen.add(f.id)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFrequency() async {
    final name = _nameController.text.trim();
    final months = int.tryParse(_monthsController.text.trim()) ?? (_selectedMonths.isNotEmpty ? _selectedMonths.length : 12);
    if (name.isEmpty) return;

    if (_editingFrequency != null) {
      await BillingFrequencySettings.updateFrequency(
        _editingFrequency!.id,
        name,
        months,
        monthsList: _selectedMonths,
      );
      _editingFrequency = null;
    } else {
      await BillingFrequencySettings.addFrequency(
        name,
        months,
        monthsList: _selectedMonths,
      );
    }
    _nameController.clear();
    _monthsController.text = '12';
    _selectedMonths = [];
    await _load();
  }

  void _startEditing(BillingFrequencyOption freq) {
    setState(() {
      _editingFrequency = freq;
      _nameController.text = freq.name;
      _monthsController.text = freq.months.toString();
      _selectedMonths = List<String>.from(freq.monthsList);
      if (_selectedMonths.isEmpty && freq.months == 12) {
        _selectedMonths = List<String>.from(BillingFrequencyOption.allMonths);
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingFrequency = null;
      _nameController.clear();
      _monthsController.text = '12';
      _selectedMonths = [];
    });
  }

  Future<void> _deleteFrequency(BillingFrequencyOption freq) async {
    final confirm = await _openSubDialog(() => showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Frequency?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Are you sure you want to delete "${freq.name}" (${freq.months} months)?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
    if (confirm == true) {
      if (_editingFrequency?.id == freq.id) {
        _editingFrequency = null;
        _nameController.clear();
        _monthsController.text = '12';
        _selectedMonths = [];
      }
      await BillingFrequencySettings.deleteFrequency(freq.id);
      await _load();
    }
  }

  Widget _buildPresetButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0D6B4E).withAlpha(15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF0D6B4E).withAlpha(50), width: 0.8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0D6B4E)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF64748B);
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    final isEditing = _editingFrequency != null;

    return Visibility(
      visible: !_isChildDialogOpen,
      maintainState: true,
      maintainSize: false,
      maintainAnimation: false,
      maintainInteractivity: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF161622) : Colors.white,
        child: Container(
          width: 560,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6B4E).withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.repeat_rounded, color: Color(0xFF0D6B4E), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Billing Frequencies',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        Text(
                          'Select specific months (Jan-Dec) & set frequency parameters',
                          style: TextStyle(fontSize: 11, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subtitleColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Form to Add or Edit Frequency (Inline without separate popup dialog!)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isEditing
                      ? Colors.orange.withAlpha(isDark ? 30 : 15)
                      : (isDark ? const Color(0xFF222234) : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEditing ? Colors.orange.withAlpha(120) : borderColor,
                    width: isEditing ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isEditing ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
                          size: 16,
                          color: isEditing ? Colors.orange : const Color(0xFF0D6B4E),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isEditing ? 'Edit Billing Frequency' : 'Add New Billing Frequency',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isEditing ? (isDark ? Colors.orange.shade300 : const Color(0xFFD97706)) : textColor,
                          ),
                        ),
                        if (isEditing) ...[
                          const Spacer(),
                          InkWell(
                            onTap: _cancelEditing,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.close_rounded, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Cancel',
                                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Frequency Name *',
                              hintText: 'e.g. Session 10 Months',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: isEditing ? Colors.orange.withAlpha(100) : borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: isEditing ? Colors.orange : const Color(0xFF0D6B4E), width: 1.5),
                              ),
                            ),
                            style: TextStyle(fontSize: 12.5, color: textColor),
                            onSubmitted: (_) => _saveFrequency(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _monthsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Months *',
                              hintText: '1-24',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: isEditing ? Colors.orange.withAlpha(100) : borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: isEditing ? Colors.orange : const Color(0xFF0D6B4E), width: 1.5),
                              ),
                            ),
                            style: TextStyle(fontSize: 12.5, color: textColor),
                            onSubmitted: (_) => _saveFrequency(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _saveFrequency,
                          icon: Icon(isEditing ? Icons.check_rounded : Icons.add_rounded, size: 16),
                          label: Text(
                            isEditing ? 'Update' : 'Add',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: isEditing ? const Color(0xFFD97706) : const Color(0xFF0D6B4E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Specific Calendar Months Selection Header & Presets
                    Row(
                      children: [
                        const Icon(Icons.calendar_month_outlined, size: 14, color: Color(0xFF0D6B4E)),
                        const SizedBox(width: 5),
                        Text(
                          'Select Months (${_selectedMonths.length} selected):',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        const Spacer(),
                        _buildPresetButton('All 12', () {
                          setState(() {
                            _selectedMonths = List.from(BillingFrequencyOption.allMonths);
                            _monthsController.text = '12';
                          });
                        }),
                        const SizedBox(width: 4),
                        _buildPresetButton('Quarterly', () {
                          setState(() {
                            _selectedMonths = ['January', 'April', 'July', 'October'];
                            _monthsController.text = '4';
                          });
                        }),
                        const SizedBox(width: 4),
                        _buildPresetButton('Half-Yearly', () {
                          setState(() {
                            _selectedMonths = ['January', 'July'];
                            _monthsController.text = '2';
                          });
                        }),
                        const SizedBox(width: 4),
                        _buildPresetButton('Clear', () {
                          setState(() {
                            _selectedMonths = [];
                            _monthsController.text = '0';
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Month Chips (Jan - Dec)
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: BillingFrequencyOption.allMonths.map((m) {
                        final short = BillingFrequencyOption.getShortMonth(m);
                        final isSelected = _selectedMonths.contains(m);
                        return FilterChip(
                          label: Text(short, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedMonths.add(m);
                                _selectedMonths.sort((a, b) =>
                                    BillingFrequencyOption.allMonths.indexOf(a).compareTo(BillingFrequencyOption.allMonths.indexOf(b)));
                              } else {
                                _selectedMonths.remove(m);
                              }
                              _monthsController.text = _selectedMonths.isNotEmpty ? _selectedMonths.length.toString() : '0';
                            });
                          },
                          selectedColor: const Color(0xFF0D6B4E).withAlpha(35),
                          checkmarkColor: const Color(0xFF0D6B4E),
                          backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF0D6B4E) : borderColor,
                              width: isSelected ? 1.2 : 0.8,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // List of frequencies Header
              Text(
                'Configured Frequencies (${_frequencies.length}):',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(height: 8),

              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_frequencies.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: Text('No frequencies found.', style: TextStyle(color: subtitleColor))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _frequencies.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (ctx, index) {
                      final f = _frequencies[index];
                      final isCurrentEditing = _editingFrequency?.id == f.id;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isCurrentEditing
                              ? Colors.orange.withAlpha(isDark ? 30 : 15)
                              : (isDark ? const Color(0xFF222234) : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrentEditing ? Colors.orange : borderColor,
                            width: isCurrentEditing ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, size: 16, color: Colors.blue.shade400),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.name,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                                  ),
                                  if (f.monthsList.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '🗓 ${f.monthsDisplay}',
                                      style: TextStyle(fontSize: 10.5, color: subtitleColor, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D6B4E).withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${f.months} ${f.months == 1 ? 'Month' : 'Months'}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D6B4E)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tooltip(
                              message: isCurrentEditing ? 'Currently Editing' : 'Edit',
                              child: IconButton(
                                icon: Icon(
                                  Icons.edit_rounded,
                                  size: 16,
                                  color: isCurrentEditing ? Colors.orange : Colors.orange.shade700,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: isCurrentEditing ? Colors.orange.withAlpha(30) : null,
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _startEditing(f),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: 'Delete',
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _deleteFrequency(f),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D6B4E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add/Edit Fee Type Dialog ─────────────────────────────────────────────────

class AddEditFeeTypeDialog extends StatefulWidget {
  final FeeType? initialFeeType;
  final Future<void> Function(String name, String billingType, int defaultMonths, double defaultAmount) onSave;

  const AddEditFeeTypeDialog({
    super.key,
    this.initialFeeType,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    FeeType? initialFeeType,
    required Future<void> Function(String name, String billingType, int defaultMonths, double defaultAmount) onSave,
    Color? barrierColor,
  }) async {
    await showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.transparent,
      builder: (ctx) => AddEditFeeTypeDialog(
        initialFeeType: initialFeeType,
        onSave: onSave,
      ),
    );
  }

  @override
  State<AddEditFeeTypeDialog> createState() => _AddEditFeeTypeDialogState();
}

class _AddEditFeeTypeDialogState extends State<AddEditFeeTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _monthsController;
  late TextEditingController _amountController;
  late String _billingType;
  String? _selectedFrequencyId;
  List<BillingFrequencyOption> _availableFrequencies = [];
  bool _isLoadingFrequencies = true;
  bool _isSaving = false;
  bool _isChildDialogOpen = false;

  Future<T?> _openSubDialog<T>(Future<T?> Function() dialogOpener) async {
    setState(() => _isChildDialogOpen = true);
    try {
      return await dialogOpener();
    } finally {
      if (mounted) {
        setState(() => _isChildDialogOpen = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialFeeType?.name ?? '');
    _billingType = widget.initialFeeType?.billingType ?? 'monthly';
    _monthsController = TextEditingController(text: (widget.initialFeeType?.defaultMonths ?? 12).toString());
    final amt = widget.initialFeeType?.defaultAmount ?? 0.0;
    _amountController = TextEditingController(text: amt > 0 ? amt.toStringAsFixed(0) : '');
    _loadFrequencies();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _monthsController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadFrequencies() async {
    final list = await BillingFrequencySettings.getFrequencies();
    if (mounted) {
      setState(() {
        _availableFrequencies = list;
        _isLoadingFrequencies = false;

        final initialType = widget.initialFeeType?.billingType ?? _billingType;
        final initialMonths = int.tryParse(_monthsController.text.trim()) ?? (widget.initialFeeType?.defaultMonths ?? 12);

        // Match frequency by ID or Name or Months count
        BillingFrequencyOption? match = list.where((f) => f.id == initialType || f.name.toLowerCase() == initialType.toLowerCase()).firstOrNull;
        match ??= list.where((f) => f.months == initialMonths).firstOrNull;
        match ??= list.firstOrNull;

        if (match != null) {
          _selectedFrequencyId = match.id;
          _billingType = match.id;
          if (widget.initialFeeType == null) {
            _monthsController.text = match.months.toString();
          }
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final name = _nameController.text.trim();
    final selectedFreq = _availableFrequencies.where((f) => f.id == _selectedFrequencyId).firstOrNull;
    final months = selectedFreq?.months ?? int.tryParse(_monthsController.text.trim()) ?? 12;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;

    await widget.onSave(name, _billingType, months, amount);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final isEdit = widget.initialFeeType != null;

    return Visibility(
      visible: !_isChildDialogOpen,
      maintainState: true,
      maintainSize: false,
      maintainAnimation: false,
      maintainInteractivity: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF181826) : Colors.white,
        child: Container(
        width: 470,
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.category_rounded, color: Colors.blue, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Fee Type' : 'Add New Fee Type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white60 : Colors.grey.shade600),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Fee Name (e.g. Admission Fee, Book Fee, Exam Fee)*',
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Fee name is required' : null,
              ),
              const SizedBox(height: 14),

              // Billing Time Dropdown with Settings Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _isLoadingFrequencies
                        ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                        : Builder(
                            builder: (context) {
                              final uniqueFrequencies = <String, BillingFrequencyOption>{};
                              for (final f in _availableFrequencies) {
                                if (f.id.isNotEmpty && f.id != '__manage__' && !uniqueFrequencies.containsKey(f.id)) {
                                  uniqueFrequencies[f.id] = f;
                                }
                              }

                              final hasSelected = uniqueFrequencies.containsKey(_selectedFrequencyId);
                              final safeValue = hasSelected ? _selectedFrequencyId : (uniqueFrequencies.isNotEmpty ? uniqueFrequencies.keys.first : null);

                              return DropdownButtonFormField<String>(
                                isExpanded: true,
                                key: ValueKey('quick_fee_billing_${safeValue}_${uniqueFrequencies.length}'),
                                initialValue: safeValue,
                                dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                decoration: InputDecoration(
                                  labelText: 'Billing Time *',
                                  prefixIcon: const Icon(Icons.repeat_rounded),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                items: [
                                  ...uniqueFrequencies.values.map((f) {
                                    return DropdownMenuItem(
                                      value: f.id,
                                      child: Text(
                                        f.name,
                                        style: TextStyle(fontSize: 13, color: textColor),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }),
                                  const DropdownMenuItem(
                                    value: '__manage__',
                                    child: Row(
                                      children: [
                                        Icon(Icons.tune_rounded, size: 15, color: Colors.blue),
                                        SizedBox(width: 6),
                                        Text(
                                          '+ Add / Manage Frequencies...',
                                          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == '__manage__') {
                                    _openSubDialog(() => ManageBillingFrequenciesDialog.show(context)).then((_) => _loadFrequencies());
                                    return;
                                  }
                                  if (v != null) {
                                    setState(() {
                                      _selectedFrequencyId = v;
                                      final match = uniqueFrequencies[v];
                                      if (match != null) {
                                        _billingType = match.name;
                                        _monthsController.text = match.months.toString();
                                      }
                                    });
                                  }
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filledTonal(
                      tooltip: 'Add / Edit Frequencies',
                      icon: const Icon(Icons.tune_rounded, color: Color(0xFF0D6B4E), size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0D6B4E).withAlpha(25),
                        padding: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await _openSubDialog(() => ManageBillingFrequenciesDialog.show(context));
                        await _loadFrequencies();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Default Amount (₹) (Optional)',
                  prefixIcon: const Icon(Icons.currency_rupee_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(isEdit ? 'Save Changes' : 'Add Fee Type'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
