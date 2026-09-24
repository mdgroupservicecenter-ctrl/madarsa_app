import 'package:shared_preferences/shared_preferences.dart';

class LicenseServerConfig {
  static const String _prefServerUrl = 'madarsa_central_licensing_server_url_v1';

  // Default Central Licensing DRM Server (Connected to Local Backend in D:\MD Group\backend)
  static const String defaultCentralServerUrl =
      'http://127.0.0.1:3000/api/licensing';

  /// Get the active central licensing server URL
  static Future<String> getCentralServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_prefServerUrl);
    if (url != null && url.trim().isNotEmpty && !url.contains('firestore.googleapis.com')) {
      return url.trim().replaceAll(RegExp(r'/+$'), '');
    }
    return defaultCentralServerUrl;
  }

  /// Save a new central licensing server URL
  static Future<void> setCentralServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty || clean.contains('firestore.googleapis.com')) {
      await prefs.remove(_prefServerUrl);
    } else {
      await prefs.setString(_prefServerUrl, clean);
    }
  }
}
