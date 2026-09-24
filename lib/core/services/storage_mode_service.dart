import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppStorageMode {
  offlineOnly,
  onlineCloud,
}

class StorageModeService {
  static const String _storageModePrefKey = 'app_storage_mode';
  static final ValueNotifier<AppStorageMode> modeNotifier =
      ValueNotifier<AppStorageMode>(AppStorageMode.onlineCloud);

  static AppStorageMode get currentMode => modeNotifier.value;
  static bool get isOnlineSyncEnabled => currentMode == AppStorageMode.onlineCloud;
  static bool get isOfflineOnly => currentMode == AppStorageMode.offlineOnly;

  /// Initialize from SharedPreferences on app startup
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedModeStr = prefs.getString(_storageModePrefKey);
      if (savedModeStr != null) {
        if (savedModeStr == 'offline') {
          modeNotifier.value = AppStorageMode.offlineOnly;
        } else {
          modeNotifier.value = AppStorageMode.onlineCloud;
        }
      } else {
        // Default to Online Cloud Sync
        modeNotifier.value = AppStorageMode.onlineCloud;
      }
    } catch (e) {
      debugPrint('Error initializing StorageModeService: $e');
    }
  }

  /// Change storage mode and persist preference
  static Future<void> setMode(AppStorageMode mode) async {
    modeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageModePrefKey,
        mode == AppStorageMode.offlineOnly ? 'offline' : 'online',
      );
    } catch (e) {
      debugPrint('Error saving storage mode: $e');
    }
  }
}
