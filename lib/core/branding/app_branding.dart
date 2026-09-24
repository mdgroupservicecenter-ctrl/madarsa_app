import 'dart:io';

/// Immutable model representing customizable application identity and branding.
class AppBranding {
  static const String defaultAppNameEnglish = 'Madarsa Management';
  static const String defaultAppNameUrdu = 'مدرسہ مینجمنٹ';
  static const String defaultTagline = 'Management System';

  final String appNameEnglish;
  final String appNameUrdu;
  final String tagline;
  final String? logoPath;

  const AppBranding({
    this.appNameEnglish = defaultAppNameEnglish,
    this.appNameUrdu = defaultAppNameUrdu,
    this.tagline = defaultTagline,
    this.logoPath,
  });

  /// Check whether a valid custom logo image file exists on the local filesystem.
  bool get hasCustomLogo {
    if (logoPath == null || logoPath!.trim().isEmpty) return false;
    try {
      return File(logoPath!).existsSync();
    } catch (_) {
      return false;
    }
  }

  AppBranding copyWith({
    String? appNameEnglish,
    String? appNameUrdu,
    String? tagline,
    String? logoPath,
    bool clearLogo = false,
  }) {
    return AppBranding(
      appNameEnglish: appNameEnglish ?? this.appNameEnglish,
      appNameUrdu: appNameUrdu ?? this.appNameUrdu,
      tagline: tagline ?? this.tagline,
      logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'appNameEnglish': appNameEnglish,
      'appNameUrdu': appNameUrdu,
      'tagline': tagline,
      'logoPath': logoPath,
    };
  }

  factory AppBranding.fromMap(Map<String, dynamic> map) {
    return AppBranding(
      appNameEnglish: map['appNameEnglish'] as String? ?? defaultAppNameEnglish,
      appNameUrdu: map['appNameUrdu'] as String? ?? defaultAppNameUrdu,
      tagline: map['tagline'] as String? ?? defaultTagline,
      logoPath: map['logoPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBranding &&
          runtimeType == other.runtimeType &&
          appNameEnglish == other.appNameEnglish &&
          appNameUrdu == other.appNameUrdu &&
          tagline == other.tagline &&
          logoPath == other.logoPath;

  @override
  int get hashCode =>
      appNameEnglish.hashCode ^
      appNameUrdu.hashCode ^
      tagline.hashCode ^
      (logoPath?.hashCode ?? 0);
}
