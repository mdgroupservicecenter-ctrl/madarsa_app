import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_hwid_service.dart';
import 'license_model.dart';
import 'license_server_config.dart';
import '../services/firebase_service.dart';

/// Cryptographic service to generate, verify, and store application licenses
class LicenseService {
  static const String _prefLicenseKey = 'madarsa_app_license_key_v1';
  static const String _prefTrialInstalledAt = 'madarsa_app_trial_installed_at_v1';
  static const String _prefLastHeartbeatAt = 'madarsa_app_last_heartbeat_at_v1';

  /// Master secret key for HMAC-SHA256 digital signature
  static const String _secretMasterKey =
      'MD_GROUP_MADARSA_ERP_MASTER_SECRET_2026_!#78692';

  /// Generate an encrypted, tamper-proof license key for a customer
  static String generateKey({
    required String institutionName,
    required SubscriptionTier tier,
    int? validityDays, // null for lifetime
    int maxStudents = 0,
    List<String>? customModules,
  }) {
    final now = DateTime.now();
    final DateTime? expiry = (tier == SubscriptionTier.lifetime || validityDays == null || validityDays <= 0)
        ? null
        : now.add(Duration(days: validityDays));

    final payloadMap = {
      'org': institutionName.trim(),
      'tier': tier.id,
      'iat': now.toIso8601String().split('T')[0],
      'exp': expiry != null ? expiry.toIso8601String().split('T')[0] : 'lifetime',
      'max': maxStudents,
      if (customModules != null && customModules.isNotEmpty)
        'mod': customModules,
    };

    final jsonString = jsonEncode(payloadMap);
    final base64Payload = base64Url.encode(utf8.encode(jsonString)).replaceAll('=', '');

    // Generate HMAC-SHA256 signature
    final hmac = Hmac(sha256, utf8.encode(_secretMasterKey));
    final digest = hmac.convert(utf8.encode(base64Payload));
    final signature = digest.toString().substring(0, 16).toUpperCase();

    // Format: MDL-[TIER]-[PAYLOAD]-[SIGNATURE]
    return 'MDL-${tier.id.toUpperCase()}-$base64Payload-$signature';
  }

  /// Verify and decode a raw license key string locally
  static ({bool isValid, String? error, AppLicense? license}) verifyKey(String rawKey) {
    try {
      final cleanKey = rawKey.trim().toUpperCase();
      if (cleanKey.isEmpty) {
        return (isValid: false, error: 'License key cannot be empty', license: null);
      }

      final parts = cleanKey.split('-');
      if (parts.length < 4) {
        return (isValid: false, error: 'Invalid license key format (must be e.g. MD-PRO-XXXX-XXXX-XXXX)', license: null);
      }

      // ── Format 1: Standard Commercial Key (MD-TIER-XXXX-XXXX-XXXX) ──
      if (parts[0] == 'MD') {
        final tierCode = parts[1].toLowerCase();
        SubscriptionTier tier = SubscriptionTier.pro;
        if (tierCode.startsWith('bas')) {
          tier = SubscriptionTier.basic;
        } else if (tierCode.startsWith('med')) {
          tier = SubscriptionTier.medium;
        } else if (tierCode.startsWith('lif')) {
          tier = SubscriptionTier.lifetime;
        }

        final license = AppLicense(
          institutionName: 'Madarsa Organization',
          tier: tier,
          issuedAt: DateTime.now(),
          expiresAt: tier == SubscriptionTier.lifetime ? null : DateTime.now().add(const Duration(days: 365)),
          allowedModules: tier.defaultModules,
          maxStudentsLimit: 0,
          rawLicenseKey: cleanKey,
        );
        return (isValid: true, error: null, license: license);
      }

      // ── Format 2: Legacy Cryptographic Offline Key (MDL-TIER-PAYLOAD-SIGNATURE) ──
      if (parts[0] == 'MDL') {
        final tierStr = parts[1];
        final base64Payload = parts[2];
        final providedSignature = parts.sublist(3).join('-');

        // Re-verify HMAC signature
        final hmac = Hmac(sha256, utf8.encode(_secretMasterKey));
        final digest = hmac.convert(utf8.encode(base64Payload));
        final expectedSignature = digest.toString().substring(0, 16).toUpperCase();

        if (providedSignature.toUpperCase() != expectedSignature) {
          return (isValid: false, error: 'Invalid or tampered license key (signature verification failed)', license: null);
        }

        // Decode base64 payload
        String normalizedBase64 = base64Payload;
        while (normalizedBase64.length % 4 != 0) {
          normalizedBase64 += '=';
        }

        final jsonString = utf8.decode(base64Url.decode(normalizedBase64));
        final Map<String, dynamic> payload = jsonDecode(jsonString);

        final org = payload['org']?.toString() ?? 'Madarsa Institute';
        final tier = SubscriptionTierExtension.fromString(payload['tier']?.toString() ?? tierStr);
        final iatStr = payload['iat']?.toString();
        final expStr = payload['exp']?.toString();
        final maxStudents = int.tryParse(payload['max']?.toString() ?? '0') ?? 0;
        final List<dynamic>? customModList = payload['mod'] as List<dynamic>?;

        final issuedAt = iatStr != null ? (DateTime.tryParse(iatStr) ?? DateTime.now()) : DateTime.now();
        final DateTime? expiresAt = (expStr == null || expStr.toLowerCase() == 'lifetime')
            ? null
            : DateTime.tryParse(expStr);

        final allowedModules = customModList != null
            ? customModList.map((e) => e.toString()).toList()
            : tier.defaultModules;

        final license = AppLicense(
          institutionName: org,
          tier: tier,
          issuedAt: issuedAt,
          expiresAt: expiresAt,
          allowedModules: allowedModules,
          maxStudentsLimit: maxStudents,
          rawLicenseKey: cleanKey,
        );

        return (isValid: true, error: null, license: license);
      }

      return (isValid: false, error: 'Invalid license key format (must start with MD- or MDL-)', license: null);
    } catch (e) {
      return (isValid: false, error: 'License verification error: ${e.toString()}', license: null);
    }
  }

  static const String _prefLiveModules = 'madarsa_app_license_live_modules_v1';
  static const String _prefDeviceBlockedKey = 'madarsa_app_device_blocked_v1';

  /// Load currently stored license, or fallback to free trial
  static Future<AppLicense> getActiveLicense() async {
    final prefs = await SharedPreferences.getInstance();
    final isBlocked = prefs.getBool(_prefDeviceBlockedKey) ?? false;
    final savedKey = prefs.getString(_prefLicenseKey);

    if (savedKey != null && savedKey.isNotEmpty) {
      // 1. Check if cached online license data exists
      final cachedDataStr = prefs.getString('madarsa_app_license_data');
      if (cachedDataStr != null && cachedDataStr.isNotEmpty) {
        try {
          final licData = jsonDecode(cachedDataStr);
          final tier = SubscriptionTierExtension.fromString(licData['tier']?.toString() ?? 'pro');
          final cachedLiveMods = prefs.getStringList(_prefLiveModules) ??
              List<String>.from(licData['allowed_modules'] ?? licData['custom_modules'] ?? tier.defaultModules);
          final lic = AppLicense(
            institutionName: (licData['institution_name'] ?? licData['customer_name'] ?? 'Madarsa Institute').toString(),
            tier: tier,
            issuedAt: DateTime.tryParse(licData['issued_at']?.toString() ?? '') ?? DateTime.now(),
            expiresAt: licData['expires_at'] != null ? DateTime.tryParse(licData['expires_at'].toString()) : null,
            allowedModules: cachedLiveMods,
            maxStudentsLimit: licData['max_students'] ?? 0,
            rawLicenseKey: savedKey,
            isBlocked: isBlocked,
          );
          return lic;
        } catch (_) {}
      }

      // 2. Offline verifyKey
      final res = verifyKey(savedKey);
      if (res.isValid && res.license != null) {
        final cachedLiveMods = prefs.getStringList(_prefLiveModules);
        final base = cachedLiveMods != null && cachedLiveMods.isNotEmpty
            ? res.license!.copyWith(allowedModules: cachedLiveMods)
            : res.license!;
        return base.copyWith(isBlocked: isBlocked);
      }
    }

    // No valid license key found: Check/Init Trial Mode
    String? trialDateStr = prefs.getString(_prefTrialInstalledAt);
    DateTime trialStart;
    if (trialDateStr == null) {
      trialStart = DateTime.now();
      await prefs.setString(_prefTrialInstalledAt, trialStart.toIso8601String());
    } else {
      trialStart = DateTime.tryParse(trialDateStr) ?? DateTime.now();
    }

    int trialDays = 14;
    List<String>? trialFeatures;
    final cachedTrialMods = prefs.getStringList('madarsa_app_trial_features_v1');
    if (cachedTrialMods != null && cachedTrialMods.isNotEmpty) {
      trialFeatures = cachedTrialMods;
    }

    final trialLicense = AppLicense.defaultTrial(
      startDate: trialStart,
      durationDays: trialDays,
      trialFeatures: trialFeatures,
    );

    return trialLicense.copyWith(isBlocked: isBlocked);
  }

  /// Activate key with central server HWID device registration + online Firebase check + offline fallback
  static Future<({bool success, String message, AppLicense? license})> activateKey(String key) async {
    String cleanKey = key.trim().toUpperCase();
    cleanKey = cleanKey.replaceAll(RegExp(r"""^[:"'s]+|[:"'s]+$"""), '');

    if (cleanKey.isEmpty) {
      return (success: false, message: 'License key cannot be empty', license: null);
    }

    // ── 1. Online Realtime Database Verification (Firebase RTDB Cloud) ──
    try {
      final docId = cleanKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final rtdbUrl = '${FirebaseService.masterRtdbBase}/licenses/$docId.json';
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 12)));
      final res = await dio.get(rtdbUrl);

      if (res.statusCode == 200 && res.data != null && res.data is Map) {
        final Map<String, dynamic> licData = Map<String, dynamic>.from(res.data);

        // Check if blocked or revoked
        if (licData['is_blocked'] == true || licData['status'] == 'revoked' || licData['status'] == 'blocked') {
          return (
            success: false,
            message: 'This license key has been blocked or revoked by the administrator.',
            license: null,
          );
        }

        // Check expiry
        if (licData['expires_at'] != null) {
          final exp = DateTime.tryParse(licData['expires_at'].toString());
          if (exp != null && exp.isBefore(DateTime.now())) {
            return (
              success: false,
              message: 'This license key expired on ${exp.toIso8601String().split('T').first}. Please contact administrator.',
              license: null,
            );
          }
        }

        // Check device limit
        final hwid = await DeviceHwidService.getDeviceHwid();
        final cleanHwid = hwid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final deviceName = DeviceHwidService.getDeviceName();
        final osInfo = DeviceHwidService.getOsInfo();

        int maxDevices = licData['max_devices'] ?? 1;
        Map<String, dynamic> existingDevices = {};
        if (licData['devices'] is Map) {
          existingDevices = Map<String, dynamic>.from(licData['devices']);
        }

        // If this device is not already registered and device limit reached
        if (!existingDevices.containsKey(cleanHwid) && existingDevices.length >= maxDevices) {
          return (
            success: false,
            message: 'Maximum PC limit reached ($maxDevices PC${maxDevices > 1 ? "s" : ""}). Please unlink another computer from Seller App or contact seller.',
            license: null,
          );
        }

        // Register this PC in Firebase RTDB
        final nowIso = DateTime.now().toIso8601String();
        final devUrl = '${FirebaseService.masterRtdbBase}/licenses/$docId/devices/$cleanHwid.json';
        await dio.put(devUrl, data: {
          'id': cleanHwid,
          'hwid': hwid,
          'device_name': deviceName,
          'os_info': osInfo,
          'first_activated_at': existingDevices[cleanHwid]?['first_activated_at'] ?? nowIso,
          'last_heartbeat_at': nowIso,
          'is_blocked': false,
        });

        // Update overall license heartbeat
        await dio.patch(rtdbUrl, data: {
          'last_heartbeat_at': nowIso,
        });

        // Determine tier & modules
        final tier = SubscriptionTierExtension.fromString(licData['tier']?.toString() ?? 'pro');
        List<String> allowedModules = [];
        if (licData['allowed_modules'] is List) {
          allowedModules = List<String>.from(licData['allowed_modules']);
        } else if (licData['custom_modules'] is List) {
          allowedModules = List<String>.from(licData['custom_modules']);
        } else {
          allowedModules = tier.defaultModules;
        }

        final org = (licData['institution_name'] ?? licData['customer_name'] ?? 'Madarsa Institute').toString();
        final issuedAt = licData['issued_at'] != null ? (DateTime.tryParse(licData['issued_at'].toString()) ?? DateTime.now()) : DateTime.now();
        final expiresAt = licData['expires_at'] != null ? DateTime.tryParse(licData['expires_at'].toString()) : null;

        final activeLicense = AppLicense(
          institutionName: org,
          tier: tier,
          issuedAt: issuedAt,
          expiresAt: expiresAt,
          allowedModules: allowedModules,
          maxStudentsLimit: licData['max_students'] ?? 0,
          rawLicenseKey: cleanKey,
          isBlocked: false,
        );

        // Save into SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLicenseKey, cleanKey);
        await prefs.setStringList(_prefLiveModules, allowedModules);
        await prefs.setString('madarsa_app_license_data', jsonEncode(licData));
        await prefs.remove(_prefDeviceBlockedKey);
        await prefs.setString(_prefLastHeartbeatAt, nowIso);

        return (
          success: true,
          message: 'License key activated successfully for $org (${tier.displayName})!',
          license: activeLicense,
        );
      }
    } catch (_) {}

    // ── 2. Local or Central DRM Server Verification ──
    try {
      final serverUrl = await LicenseServerConfig.getCentralServerUrl();
      final dio = await _getLicensingDio();
      final endpoint = (serverUrl.endsWith('/licensing') || serverUrl.endsWith('/licensing/'))
          ? '/client/activate'
          : '/licensing/client/activate';

      final hwid = await DeviceHwidService.getDeviceHwid();
      final deviceName = DeviceHwidService.getDeviceName();
      final osInfo = DeviceHwidService.getOsInfo();

      final response = await dio.post(
        endpoint,
        data: {
          'license_key': cleanKey,
          'hwid': hwid,
          'device_name': deviceName,
          'os_info': osInfo,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final srvLic = response.data['license'];
        if (srvLic != null) {
          final tier = SubscriptionTierExtension.fromString(srvLic['tier']?.toString() ?? 'pro');
          final allowedModules = List<String>.from(srvLic['allowed_modules'] ?? srvLic['custom_modules'] ?? tier.defaultModules);
          final org = (srvLic['institution_name'] ?? srvLic['customer_name'] ?? 'Madarsa Institute').toString();

          final activeLicense = AppLicense(
            institutionName: org,
            tier: tier,
            issuedAt: DateTime.tryParse(srvLic['issued_at']?.toString() ?? '') ?? DateTime.now(),
            expiresAt: srvLic['expires_at'] != null ? DateTime.tryParse(srvLic['expires_at'].toString()) : null,
            allowedModules: allowedModules,
            maxStudentsLimit: srvLic['max_students'] ?? 0,
            rawLicenseKey: cleanKey,
            isBlocked: false,
          );

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefLicenseKey, cleanKey);
          await prefs.setStringList(_prefLiveModules, allowedModules);
          await prefs.setString('madarsa_app_license_data', jsonEncode(srvLic));
          await prefs.remove(_prefDeviceBlockedKey);

          return (
            success: true,
            message: 'License activated successfully via Server for $org!',
            license: activeLicense,
          );
        }
      } else if (response.statusCode == 403 || response.statusCode == 400) {
        final err = response.data?['error']?.toString() ?? response.data?['message']?.toString();
        if (err != null && err.isNotEmpty) {
          return (success: false, message: err, license: null);
        }
      }
    } catch (_) {}

    // ── 3. Offline Cryptographic Verification (Fallback) ──
    final localRes = verifyKey(cleanKey);
    if (localRes.isValid && localRes.license != null) {
      if (localRes.license!.isExpired) {
        return (
          success: false,
          message: 'This license key has expired on ${localRes.license!.expiresAt?.toIso8601String().split('T').first}.',
          license: localRes.license,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLicenseKey, cleanKey);
      await prefs.remove(_prefDeviceBlockedKey);
      await prefs.setString(_prefLastHeartbeatAt, DateTime.now().toIso8601String());

      return (
        success: true,
        message: 'License key activated offline for ${localRes.license!.institutionName} (${localRes.license!.tier.displayName})',
        license: localRes.license,
      );
    }

    return (
      success: false,
      message: 'License key not found or invalid. Please check the key and your internet connection.',
      license: null,
    );
  }

  static Future<Dio> _getLicensingDio() async {
    final baseUrl = await LicenseServerConfig.getCentralServerUrl();
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
  }

  /// Periodic Heartbeat check to sync live plan changes, permissions & revocation with Firebase & server
  static Future<AppLicense?> syncHeartbeatWithServer(AppLicense currentLicense) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_prefLicenseKey);

      // ── 1. TRIAL MODE: Fast Realtime Google Firebase Telemetry ──
      if (savedKey == null || savedKey.isEmpty) {
        try {
          final fbRes = await FirebaseService.pingTrialTelemetry(
            institutionName: currentLicense.institutionName,
          );
          if (fbRes.isBlocked) {
            await prefs.setBool(_prefDeviceBlockedKey, true);
            return currentLicense.copyWith(
              isBlocked: true,
              blockedMessage: 'This trial computer has been blocked by administrator.',
              allowedModules: [],
            );
          } else {
            await prefs.remove(_prefDeviceBlockedKey);
          }

          if (fbRes.features != null && fbRes.features!.isNotEmpty) {
            await prefs.setStringList('madarsa_app_trial_features_v1', fbRes.features!);
            return currentLicense.copyWith(isBlocked: false, allowedModules: fbRes.features);
          }
          return currentLicense.copyWith(isBlocked: false);
        } catch (_) {}
      } else {
        // ── 2. PAID MODE: Fast Realtime Google Firebase License Check ──
        try {
          final fbLic = await FirebaseService.syncLicenseHeartbeat(savedKey);
          if (fbLic.isBlocked || !fbLic.isValid) {
            await prefs.setBool(_prefDeviceBlockedKey, true);
            await prefs.remove(_prefLicenseKey);
            await prefs.remove(_prefLiveModules);
            return currentLicense.copyWith(
              isBlocked: true,
              blockedMessage: fbLic.error ?? 'This license has been deleted or rejected by administrator.',
              allowedModules: [],
            );
          }

          if (fbLic.isValid) {
            await prefs.remove(_prefDeviceBlockedKey);
            if (fbLic.liveModules != null && fbLic.liveModules!.isNotEmpty) {
              await prefs.setStringList(_prefLiveModules, fbLic.liveModules!);
              currentLicense = currentLicense.copyWith(
                allowedModules: fbLic.liveModules,
                expiresAt: fbLic.expiresAt ?? currentLicense.expiresAt,
              );
            }
          }
        } catch (_) {}

        // ── 3. Central & Local DRM Server Heartbeat (Local SQLite & Central Sync) ──
        try {
          final serverUrl = await LicenseServerConfig.getCentralServerUrl();
          if (!serverUrl.contains('firestore.googleapis.com')) {
            final hwid = await DeviceHwidService.getDeviceHwid();
            final dio = await _getLicensingDio();
            final endpoint = (serverUrl.endsWith('/licensing') || serverUrl.endsWith('/licensing/'))
                ? '/client/heartbeat'
                : '/licensing/client/heartbeat';

            final res = await dio.post(
              endpoint,
              data: {
                'license_key': savedKey,
                'hwid': hwid,
              },
            );

            if (res.statusCode == 200 && res.data != null) {
              final data = res.data;
              if (data['is_valid'] == false || data['status'] == 'revoked') {
                await prefs.setBool(_prefDeviceBlockedKey, true);
                return currentLicense.copyWith(
                  isBlocked: true,
                  blockedMessage: 'This license has been blocked or revoked by administrator.',
                  allowedModules: [],
                );
              }
              if (data['allowed_modules'] is List) {
                final liveMods = List<String>.from(data['allowed_modules']);
                await prefs.setStringList(_prefLiveModules, liveMods);
                currentLicense = currentLicense.copyWith(
                  allowedModules: liveMods,
                  expiresAt: data['expires_at'] != null ? DateTime.tryParse(data['expires_at'].toString()) : currentLicense.expiresAt,
                );
              }
            } else if (res.statusCode == 403) {
              await prefs.setBool(_prefDeviceBlockedKey, true);
              return currentLicense.copyWith(
                isBlocked: true,
                blockedMessage: res.data?['error']?.toString() ?? 'Device or license blocked by administrator.',
                allowedModules: [],
              );
            }
          }
        } catch (_) {}
      }

      // Check persistent local block
      if (prefs.getBool(_prefDeviceBlockedKey) == true) {
        return currentLicense.copyWith(isBlocked: true, allowedModules: []);
      }

      return currentLicense.copyWith(isBlocked: false);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefDeviceBlockedKey) == true) {
        return currentLicense.copyWith(isBlocked: true, allowedModules: []);
      }
      return currentLicense;
    }
  }

  /// Deactivate active license on server and remove locally
  static Future<({bool success, String message})> deactivateActiveLicense() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_prefLicenseKey);
      if (savedKey != null && savedKey.isNotEmpty) {
        try {
          final serverUrl = await LicenseServerConfig.getCentralServerUrl();
          if (!serverUrl.contains('firestore.googleapis.com')) {
            final hwid = await DeviceHwidService.getDeviceHwid();
            final dio = await _getLicensingDio();
            final endpoint = (serverUrl.endsWith('/licensing') || serverUrl.endsWith('/licensing/'))
                ? '/client/deactivate'
                : '/licensing/client/deactivate';
            await dio.post(
              endpoint,
              data: {
                'license_key': savedKey,
                'hwid': hwid,
              },
            );
          }
        } catch (_) {}
      }
      await removeLicense();
      return (success: true, message: 'Plan cancelled and deactivated successfully.');
    } catch (_) {
      await removeLicense();
      return (success: true, message: 'License removed from this computer.');
    }
  }

  /// Reset / Remove active license
  static Future<void> removeLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLicenseKey);
    await prefs.remove(_prefLiveModules);
  }
}
