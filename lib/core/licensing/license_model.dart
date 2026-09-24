import 'package:flutter/material.dart';

/// Supported subscription and licensing tiers
enum SubscriptionTier {
  trial,
  basic,
  medium,
  pro,
  lifetime,
}

extension SubscriptionTierExtension on SubscriptionTier {
  String get id {
    switch (this) {
      case SubscriptionTier.trial:
        return 'trial';
      case SubscriptionTier.basic:
        return 'basic';
      case SubscriptionTier.medium:
        return 'medium';
      case SubscriptionTier.pro:
        return 'pro';
      case SubscriptionTier.lifetime:
        return 'lifetime';
    }
  }

  String get displayName {
    switch (this) {
      case SubscriptionTier.trial:
        return 'Free Trial';
      case SubscriptionTier.basic:
        return 'Basic Plan';
      case SubscriptionTier.medium:
        return 'Medium Plan';
      case SubscriptionTier.pro:
        return 'Pro Plan';
      case SubscriptionTier.lifetime:
        return 'Lifetime License';
    }
  }

  Color get color {
    switch (this) {
      case SubscriptionTier.trial:
        return const Color(0xFF0288D1);
      case SubscriptionTier.basic:
        return const Color(0xFF2E7D32);
      case SubscriptionTier.medium:
        return const Color(0xFFE65100);
      case SubscriptionTier.pro:
        return const Color(0xFF6A1B9A);
      case SubscriptionTier.lifetime:
        return const Color(0xFF0D6B4E);
    }
  }

  IconData get icon {
    switch (this) {
      case SubscriptionTier.trial:
        return Icons.access_time_rounded;
      case SubscriptionTier.basic:
        return Icons.verified_user_outlined;
      case SubscriptionTier.medium:
        return Icons.workspace_premium_rounded;
      case SubscriptionTier.pro:
        return Icons.military_tech_rounded;
      case SubscriptionTier.lifetime:
        return Icons.stars_rounded;
    }
  }

  /// Default modules accessible in this tier
  List<String> get defaultModules {
    switch (this) {
      case SubscriptionTier.trial:
        return const [
          'dashboard',
          'students_view',
          'students_admission',
          'staff_view',
          'attendance_mark',
          'classes_manage',
          'fees_collect',
          'exams_create',
          'exams_marks_entry',
          'exams_marksheet_print',
          'exams_rankings',
          'settings_profile',
          'settings',
        ];
      case SubscriptionTier.basic:
        return const [
          'dashboard',
          'students_view',
          'students_admission',
          'students_edit',
          'students_delete',
          'students_gr_no_config',
          'staff_view',
          'staff_add',
          'staff_edit',
          'staff_attendance',
          'attendance_mark',
          'attendance_bulk',
          'attendance_reports',
          'classes_manage',
          'settings_profile',
          'settings_hijri',
          'settings_backup',
          'settings',
        ];
      case SubscriptionTier.medium:
        return const [
          'dashboard',
          'students_view',
          'students_admission',
          'students_edit',
          'students_delete',
          'students_id_card',
          'students_id_card_print',
          'students_excel_export',
          'students_excel_import',
          'students_gr_no_config',
          'students_certificate',
          'staff_view',
          'staff_add',
          'staff_edit',
          'staff_attendance',
          'attendance_mark',
          'attendance_bulk',
          'attendance_reports',
          'classes_manage',
          'classes_promotion',
          'fees_collect',
          'fees_structure',
          'fees_discounts',
          'fees_defaulters',
          'fees_receipt_print',
          'exams_create',
          'exams_marks_entry',
          'exams_marksheet_print',
          'exams_rankings',
          'settings_profile',
          'settings_hijri',
          'settings_backup',
          'settings',
        ];
      case SubscriptionTier.pro:
      case SubscriptionTier.lifetime:
        return const [
          'dashboard',
          'students',
          'staff',
          'classes',
          'exams',
          'card_designer',
          'attendance',
          'fees',
          'kitchen',
          'purchases',
          'hostel',
          'library',
          'contributors',
          'reports',
          'roles',
          'users',
          'settings',
        ];
    }
  }

  static SubscriptionTier fromString(String? str) {
    if (str == null) return SubscriptionTier.trial;
    switch (str.toLowerCase().trim()) {
      case 'basic':
        return SubscriptionTier.basic;
      case 'medium':
        return SubscriptionTier.medium;
      case 'pro':
        return SubscriptionTier.pro;
      case 'lifetime':
        return SubscriptionTier.lifetime;
      case 'trial':
      default:
        return SubscriptionTier.trial;
    }
  }
}

/// Information about the current active license
class AppLicense {
  final String institutionName;
  final SubscriptionTier tier;
  final DateTime issuedAt;
  final DateTime? expiresAt; // null means Lifetime / No expiry
  final List<String> allowedModules;
  final int maxStudentsLimit; // 0 means Unlimited
  final String rawLicenseKey;
  final String machineId;
  final bool isBlocked;
  final String? blockedMessage;

  const AppLicense({
    required this.institutionName,
    required this.tier,
    required this.issuedAt,
    this.expiresAt,
    required this.allowedModules,
    this.maxStudentsLimit = 0,
    required this.rawLicenseKey,
    this.machineId = '',
    this.isBlocked = false,
    this.blockedMessage,
  });

  /// Check if the license is currently expired
  bool get isExpired {
    if (isBlocked) return true;
    if (tier == SubscriptionTier.lifetime || expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if this is a lifetime license
  bool get isLifetime => tier == SubscriptionTier.lifetime || expiresAt == null;

  /// Remaining days before expiration
  int get daysRemaining {
    if (isBlocked) return 0;
    if (isLifetime) return 99999;
    if (expiresAt == null) return 0;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Check if a specific module key is accessible
  bool hasModuleAccess(String moduleKey) {
    if (isBlocked) return false;
    if (isExpired) return false;
    final normalized = moduleKey.toLowerCase().trim();
    if (normalized == 'dashboard' || normalized == 'settings') return true;

    final allowedLower = allowedModules.map((m) => m.toLowerCase().trim()).toSet();
    if (allowedLower.contains(normalized)) return true;

    // Check module prefix (e.g. students_*, staff_*, attendance_*)
    if (allowedLower.any((f) => f.startsWith('${normalized}_'))) return true;

    // Universal Card & Document Designer Access
    if (normalized == 'card_designer') {
      if (allowedLower.contains('denied_card_designer')) return false;
      if (allowedLower.contains('card_designer') || allowedLower.contains('card_designer_export')) return true;
      if (tier == SubscriptionTier.pro || tier == SubscriptionTier.lifetime) return true;
      if (allowedLower.contains('students_id_card') || allowedLower.contains('exams_marksheet_print')) return true;
      return false;
    }

    // Alias mapping for contributors/donors and roles/users
    if (normalized == 'contributors' || normalized == 'donors') {
      return allowedLower.contains('contributors') ||
          allowedLower.contains('donors') ||
          allowedLower.any((f) => f.startsWith('donors_') || f.startsWith('contributors_'));
    }
    if (normalized == 'roles' || normalized == 'users') {
      return allowedLower.contains('roles') ||
          allowedLower.contains('users') ||
          allowedLower.any((f) => f.startsWith('users_') || f.startsWith('roles_'));
    }

    return false;
  }

  /// Check if a specific granular sub-feature is accessible (e.g. 'students_id_card', 'students_admission', 'fees_defaulters')
  bool hasFeatureAccess(String featureKey) {
    if (isBlocked) return false;
    if (isExpired) return false;
    final normalized = featureKey.toLowerCase().trim();
    if (normalized == 'dashboard') return true;

    final allowedLower = allowedModules.map((m) => m.toLowerCase().trim()).toSet();
    if (allowedLower.contains(normalized)) return true;

    if (normalized == 'card_designer' || normalized == 'card_designer_export') {
      if (allowedLower.contains('denied_card_designer')) return false;
      if (allowedLower.contains('card_designer') || allowedLower.contains('card_designer_export')) return true;
      if (tier == SubscriptionTier.pro || tier == SubscriptionTier.lifetime) return true;
      if (allowedLower.contains('students_id_card') || allowedLower.contains('exams_marksheet_print')) return true;
      return false;
    }

    // Direct aliases for donors and users
    if (normalized == 'donors_records' || normalized == 'contributors_records') {
      if (allowedLower.contains('donors') || allowedLower.contains('contributors')) return true;
    }
    if (normalized == 'donors_receipts' || normalized == 'contributors_receipts') {
      if (allowedLower.contains('donors') || allowedLower.contains('contributors')) return true;
    }
    if (normalized == 'users_roles' || normalized == 'roles_roles') {
      if (allowedLower.contains('users') || allowedLower.contains('roles')) return true;
    }
    if (normalized == 'users_permissions' || normalized == 'roles_permissions') {
      if (allowedLower.contains('users') || allowedLower.contains('roles')) return true;
    }

    // If entire parent module is allowed AND no specific sub-features are filtering it
    final parentModule = normalized.contains('_') ? normalized.split('_').first : normalized;
    if (allowedLower.contains(parentModule)) {
      final hasSpecificSubFeatures = allowedLower.any((f) => f != parentModule && f.startsWith('${parentModule}_'));
      if (!hasSpecificSubFeatures) {
        return true;
      }
    }

    // Alias parent check for donors/contributors and users/roles
    if (parentModule == 'donors' || parentModule == 'contributors') {
      if (allowedLower.contains('donors') || allowedLower.contains('contributors')) {
        final hasSpecificSubFeatures = allowedLower.any((f) => f.startsWith('donors_') || f.startsWith('contributors_'));
        if (!hasSpecificSubFeatures) return true;
      }
    }
    if (parentModule == 'users' || parentModule == 'roles') {
      if (allowedLower.contains('users') || allowedLower.contains('roles')) {
        final hasSpecificSubFeatures = allowedLower.any((f) => f.startsWith('users_') || f.startsWith('roles_'));
        if (!hasSpecificSubFeatures) return true;
      }
    }

    return false;
  }

  /// Find minimum tier required for a given module
  static SubscriptionTier minimumTierForModule(String moduleKey) {
    final mod = moduleKey.toLowerCase().trim();
    if (mod == 'contributors' ||
        mod == 'donors' ||
        mod == 'roles' ||
        mod == 'users' ||
        mod == 'kitchen' ||
        mod == 'hostel' ||
        mod == 'library' ||
        mod == 'card_designer' ||
        mod == 'purchases') {
      return SubscriptionTier.pro;
    }
    if (SubscriptionTier.basic.defaultModules.contains(mod)) {
      return SubscriptionTier.basic;
    }
    if (SubscriptionTier.medium.defaultModules.contains(mod)) {
      return SubscriptionTier.medium;
    }
    return SubscriptionTier.pro;
  }

  AppLicense copyWith({
    String? institutionName,
    SubscriptionTier? tier,
    DateTime? issuedAt,
    DateTime? expiresAt,
    List<String>? allowedModules,
    int? maxStudentsLimit,
    String? rawLicenseKey,
    String? machineId,
    bool? isBlocked,
    String? blockedMessage,
  }) {
    return AppLicense(
      institutionName: institutionName ?? this.institutionName,
      tier: tier ?? this.tier,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      allowedModules: allowedModules ?? this.allowedModules,
      maxStudentsLimit: maxStudentsLimit ?? this.maxStudentsLimit,
      rawLicenseKey: rawLicenseKey ?? this.rawLicenseKey,
      machineId: machineId ?? this.machineId,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedMessage: blockedMessage ?? this.blockedMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'institutionName': institutionName,
      'tier': tier.id,
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'allowedModules': allowedModules,
      'maxStudentsLimit': maxStudentsLimit,
      'rawLicenseKey': rawLicenseKey,
      'machineId': machineId,
    };
  }

  factory AppLicense.fromJson(Map<String, dynamic> json) {
    final tier = SubscriptionTierExtension.fromString(json['tier']?.toString());
    final List<dynamic>? modulesJson = json['allowedModules'] as List<dynamic>?;
    final allowedModules = modulesJson != null
        ? modulesJson.map((e) => e.toString()).toList()
        : tier.defaultModules;

    return AppLicense(
      institutionName: json['institutionName']?.toString() ?? 'Madarsa Institute',
      tier: tier,
      issuedAt: json['issuedAt'] != null
          ? DateTime.tryParse(json['issuedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      allowedModules: allowedModules,
      maxStudentsLimit: int.tryParse(json['maxStudentsLimit']?.toString() ?? '0') ?? 0,
      rawLicenseKey: json['rawLicenseKey']?.toString() ?? '',
      machineId: json['machineId']?.toString() ?? '',
    );
  }

  /// Factory for a default trial with configurable duration and restricted default features
  factory AppLicense.defaultTrial({DateTime? startDate, int durationDays = 14, List<String>? trialFeatures}) {
    final start = startDate ?? DateTime.now();
    return AppLicense(
      institutionName: 'Evaluation / Trial Mode',
      tier: SubscriptionTier.trial,
      issuedAt: start,
      expiresAt: start.add(Duration(days: durationDays)),
      allowedModules: trialFeatures ?? SubscriptionTier.trial.defaultModules,
      maxStudentsLimit: 100,
      rawLicenseKey: 'TRIAL-FREE-EVALUATION',
      machineId: 'DEVICE_LOCAL',
    );
  }
}
