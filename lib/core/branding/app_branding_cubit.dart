import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_branding.dart';
import '../services/windows_system_branding_service.dart';

/// Cubit managing the application's customized branding, identity, and logo.
class AppBrandingCubit extends Cubit<AppBranding> {
  static const String _prefNameEnKey = 'app_branding_name_en_v1';
  static const String _prefNameUrKey = 'app_branding_name_ur_v1';
  static const String _prefTaglineKey = 'app_branding_tagline_v1';
  static const String _prefLogoPathKey = 'app_branding_logo_path_v1';

  AppBrandingCubit() : super(const AppBranding());

  /// Load persisted branding settings from SharedPreferences
  Future<void> loadBranding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nameEn = prefs.getString(_prefNameEnKey) ?? AppBranding.defaultAppNameEnglish;
      final nameUr = prefs.getString(_prefNameUrKey) ?? AppBranding.defaultAppNameUrdu;
      final tagline = prefs.getString(_prefTaglineKey) ?? AppBranding.defaultTagline;
      String? logoPath = prefs.getString(_prefLogoPathKey);

      // Verify logo path exists on disk
      if (logoPath != null && logoPath.isNotEmpty) {
        final file = File(logoPath);
        if (!file.existsSync()) {
          logoPath = null;
          await prefs.remove(_prefLogoPathKey);
        }
      }

      final loadedState = AppBranding(
        appNameEnglish: nameEn,
        appNameUrdu: nameUr,
        tagline: tagline,
        logoPath: logoPath,
      );

      emit(loadedState);

      // Apply system-wide desktop, taskbar, and shortcut branding on Windows
      if (Platform.isWindows) {
        WindowsSystemBrandingService.applySystemBranding(loadedState);
      }
    } catch (e) {
      debugPrint('AppBrandingCubit.loadBranding error: $e');
    }
  }

  /// Update branding fields and optionally save a new logo image
  Future<bool> updateBranding({
    String? nameEn,
    String? nameUr,
    String? tagline,
    String? newLogoSourcePath,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedNameEn = (nameEn != null && nameEn.trim().isNotEmpty)
          ? nameEn.trim()
          : state.appNameEnglish;
      final updatedNameUr = (nameUr != null && nameUr.trim().isNotEmpty)
          ? nameUr.trim()
          : state.appNameUrdu;
      final updatedTagline = (tagline != null && tagline.trim().isNotEmpty)
          ? tagline.trim()
          : state.tagline;

      String? targetLogoPath = state.logoPath;

      // Handle new logo upload
      if (newLogoSourcePath != null && newLogoSourcePath.isNotEmpty) {
        final sourceFile = File(newLogoSourcePath);
        if (sourceFile.existsSync()) {
          Directory brandingDir;
          try {
            final appDocDir = await getApplicationDocumentsDirectory();
            brandingDir = Directory(p.join(appDocDir.path, 'Madarsa_App_Branding'));
          } catch (_) {
            final appData = Platform.environment['APPDATA'];
            if (appData != null && appData.isNotEmpty) {
              brandingDir = Directory(p.join(appData, 'Madarsa_App_Branding'));
            } else {
              brandingDir = Directory(p.join(Directory.systemTemp.path, 'Madarsa_App_Branding'));
            }
          }
          if (!brandingDir.existsSync()) {
            brandingDir.createSync(recursive: true);
          }

          final ext = p.extension(newLogoSourcePath).toLowerCase();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final newFileName = 'app_logo_$timestamp$ext';
          final savedFile = p.join(brandingDir.path, newFileName);

          // Copy source file to persistent app directory
          await sourceFile.copy(savedFile);

          // Clean up old custom logo file if it exists
          if (state.logoPath != null && state.logoPath != savedFile) {
            try {
              final oldFile = File(state.logoPath!);
              if (oldFile.existsSync()) {
                oldFile.deleteSync();
              }
            } catch (_) {}
          }

          targetLogoPath = savedFile;
        }
      }

      await prefs.setString(_prefNameEnKey, updatedNameEn);
      await prefs.setString(_prefNameUrKey, updatedNameUr);
      await prefs.setString(_prefTaglineKey, updatedTagline);

      if (targetLogoPath != null) {
        await prefs.setString(_prefLogoPathKey, targetLogoPath);
      }

      final updatedState = AppBranding(
        appNameEnglish: updatedNameEn,
        appNameUrdu: updatedNameUr,
        tagline: updatedTagline,
        logoPath: targetLogoPath,
      );

      emit(updatedState);

      // Apply system-wide desktop, taskbar, and shortcut branding on Windows
      if (Platform.isWindows) {
        await WindowsSystemBrandingService.applySystemBranding(updatedState);
      }

      return true;
    } catch (e) {
      debugPrint('AppBrandingCubit.updateBranding error: $e');
      return false;
    }
  }

  /// Remove custom logo and revert to default icon
  Future<void> removeLogo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state.logoPath != null) {
        try {
          final file = File(state.logoPath!);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (_) {}
      }

      await prefs.remove(_prefLogoPathKey);

      final clearedState = state.copyWith(clearLogo: true);
      emit(clearedState);

      if (Platform.isWindows) {
        await WindowsSystemBrandingService.applySystemBranding(clearedState);
      }
    } catch (e) {
      debugPrint('AppBrandingCubit.removeLogo error: $e');
    }
  }

  /// Reset all branding to system defaults
  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (state.logoPath != null) {
        try {
          final file = File(state.logoPath!);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (_) {}
      }

      await prefs.remove(_prefNameEnKey);
      await prefs.remove(_prefNameUrKey);
      await prefs.remove(_prefTaglineKey);
      await prefs.remove(_prefLogoPathKey);

      const defaultState = AppBranding();
      emit(defaultState);

      if (Platform.isWindows) {
        await WindowsSystemBrandingService.applySystemBranding(defaultState);
      }
    } catch (e) {
      debugPrint('AppBrandingCubit.resetToDefaults error: $e');
    }
  }
}
