import 'dart:convert';
import 'dart:io';

class DeviceHwidService {
  static String? _cachedHwid;
  static String? _cachedOsInfo;

  /// Get the exact Windows Device ID (matching Windows Settings > System > About)
  /// or unique tamper-resistant hardware identifier.
  static Future<String> getDeviceHwid() async {
    if (_cachedHwid != null && _cachedHwid!.isNotEmpty) return _cachedHwid!;

    String rawId = '';

    try {
      if (Platform.isWindows) {
        // 1. Try Windows SQMClient MachineId (Matches "Device ID" in Windows About / Device specifications)
        final sqmResult = await Process.run('reg', [
          'query',
          r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\SQMClient',
          '/v',
          'MachineId',
        ]);

        if (sqmResult.exitCode == 0 && sqmResult.stdout.toString().contains('MachineId')) {
          final match = RegExp(r'\{?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\}?')
              .firstMatch(sqmResult.stdout.toString());
          if (match != null && match.group(1) != null) {
            rawId = match.group(1)!.toUpperCase().trim();
          }
        }

        // 2. Fallback: Windows Cryptography MachineGuid
        if (rawId.isEmpty) {
          final regResult = await Process.run('reg', [
            'query',
            r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
            '/v',
            'MachineGuid',
          ]);

          if (regResult.exitCode == 0 && regResult.stdout.toString().contains('MachineGuid')) {
            final match = RegExp(r'\{?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\}?')
                .firstMatch(regResult.stdout.toString());
            if (match != null && match.group(1) != null) {
              rawId = match.group(1)!.toUpperCase().trim();
            }
          }
        }

        // 3. Fallback: Hostname + Processor Identifier
        if (rawId.isEmpty) {
          rawId = '${Platform.localHostname}_${Platform.environment['PROCESSOR_IDENTIFIER'] ?? 'WIN'}';
        }
      } else {
        // Fallback for other platforms
        rawId = '${Platform.operatingSystem}_${Platform.localHostname}_${Platform.numberOfProcessors}';
      }
    } catch (_) {
      rawId = '${Platform.operatingSystem}_${Platform.localHostname}';
    }

    // Clean formatting without brackets, standardized uppercase
    rawId = rawId.replaceAll('{', '').replaceAll('}', '').trim().toUpperCase();
    _cachedHwid = rawId;

    // Detect and cache real OS Info
    await _detectDetailedOsInfo();

    return _cachedHwid!;
  }

  /// Get the user-friendly computer / device name
  static String getDeviceName() {
    try {
      final name = Platform.localHostname;
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'Windows PC';
  }

  /// Get operating system description (matching Windows Settings > System > About)
  static String getOsInfo() {
    if (_cachedOsInfo != null && _cachedOsInfo!.isNotEmpty) {
      return _cachedOsInfo!;
    }

    // Fast synchronous fallback
    try {
      if (Platform.isWindows) {
        final ver = Platform.operatingSystemVersion.replaceAll('"', '').trim();
        return ver.startsWith('Windows') ? ver : 'Windows $ver';
      }
      return '${Platform.operatingSystem.toUpperCase()} (${Platform.operatingSystemVersion})';
    } catch (_) {}
    return 'Microsoft Windows';
  }

  /// Helper to detect rich OS details (Windows 11 / 10 Edition, DisplayVersion, Build)
  static Future<void> _detectDetailedOsInfo() async {
    if (_cachedOsInfo != null && _cachedOsInfo!.isNotEmpty) return;

    if (!Platform.isWindows) {
      _cachedOsInfo = '${Platform.operatingSystem.toUpperCase()} (${Platform.operatingSystemVersion})';
      return;
    }

    // Attempt 1: Fast PowerShell CimInstance for exact Edition (e.g. "Windows 11 Pro Insider Preview")
    try {
      final psResult = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$os = Get-CimInstance Win32_OperatingSystem; $curVer = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"; [PSCustomObject]@{Caption=$os.Caption; DisplayVersion=$curVer.DisplayVersion; Build=$os.BuildNumber; UBR=$curVer.UBR} | ConvertTo-Json',
      ]).timeout(const Duration(seconds: 4));

      if (psResult.exitCode == 0 && psResult.stdout.toString().trim().isNotEmpty) {
        final decoded = jsonDecode(psResult.stdout.toString());
        if (decoded is Map) {
          String caption = (decoded['Caption']?.toString() ?? '').replaceAll('Microsoft ', '').trim();
          String version = decoded['DisplayVersion']?.toString().trim() ?? '';
          String build = decoded['Build']?.toString().trim() ?? '';
          String ubr = decoded['UBR']?.toString().trim() ?? '';

          String fullBuild = build;
          if (ubr.isNotEmpty) {
            fullBuild = '$build.$ubr';
          }

          final parts = <String>[];
          if (caption.isNotEmpty) parts.add(caption);
          if (version.isNotEmpty) parts.add(version);
          if (fullBuild.isNotEmpty) parts.add('(Build $fullBuild)');

          if (parts.isNotEmpty) {
            _cachedOsInfo = parts.join(' ');
            return;
          }
        }
      }
    } catch (_) {}

    // Attempt 2: Direct Registry Query Fallback
    try {
      final buildQuery = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
        '/v',
        'CurrentBuildNumber',
      ]);
      final verQuery = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
        '/v',
        'DisplayVersion',
      ]);
      final ubrQuery = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
        '/v',
        'UBR',
      ]);
      final prodQuery = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
        '/v',
        'ProductName',
      ]);

      String buildNum = _extractRegValue(buildQuery.stdout.toString(), 'CurrentBuildNumber');
      String displayVer = _extractRegValue(verQuery.stdout.toString(), 'DisplayVersion');
      String ubrHex = _extractRegValue(ubrQuery.stdout.toString(), 'UBR');
      String prodName = _extractRegValue(prodQuery.stdout.toString(), 'ProductName');

      int buildInt = int.tryParse(buildNum) ?? 0;
      if (buildInt >= 22000 && prodName.contains('Windows 10')) {
        prodName = prodName.replaceAll('Windows 10', 'Windows 11');
      }

      String ubrDec = '';
      if (ubrHex.isNotEmpty) {
        if (ubrHex.startsWith('0x')) {
          ubrDec = (int.tryParse(ubrHex.substring(2), radix: 16) ?? '').toString();
        } else {
          ubrDec = ubrHex;
        }
      }

      String buildStr = buildNum;
      if (ubrDec.isNotEmpty) {
        buildStr = '$buildNum.$ubrDec';
      }

      final fallbackParts = <String>[];
      if (prodName.isNotEmpty) fallbackParts.add(prodName);
      if (displayVer.isNotEmpty) fallbackParts.add(displayVer);
      if (buildStr.isNotEmpty) fallbackParts.add('(Build $buildStr)');

      if (fallbackParts.isNotEmpty) {
        _cachedOsInfo = fallbackParts.join(' ');
        return;
      }
    } catch (_) {}

    _cachedOsInfo = Platform.operatingSystemVersion.replaceAll('"', '').trim();
  }

  static String _extractRegValue(String stdout, String valueName) {
    for (final line in stdout.split('\n')) {
      if (line.contains(valueName)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          return parts.sublist(2).join(' ').trim();
        }
      }
    }
    return '';
  }
}
