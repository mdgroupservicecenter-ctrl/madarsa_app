import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../storage/database_helper.dart';

/// Model representing application update metadata
class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String downloadUrl;
  final double? fileSizeMb;
  final bool isMandatory;
  final String? publishedAt;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.downloadUrl,
    this.fileSizeMb,
    this.isMandatory = false,
    this.publishedAt,
  });

  bool get hasUpdate => AppUpdateService.isNewerVersion(latestVersion, currentVersion);

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json, String currentVersion) {
    // Check if GitHub Releases API response
    if (json.containsKey('tag_name')) {
      final tagName = json['tag_name']?.toString() ?? '0.0.0';
      final cleanVersion = tagName.replaceAll(RegExp(r'[^0-9.]'), '');
      final name = json['name']?.toString() ?? 'Release $tagName';
      final body = json['body']?.toString() ?? 'No release notes provided.';
      final publishedAt = json['published_at']?.toString();

      // Look for .exe or .zip asset in assets array
      String downloadUrl = '';
      double? fileSizeMb;
      final assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final assetName = asset['name']?.toString().toLowerCase() ?? '';
          if (assetName.endsWith('.exe') || assetName.endsWith('.msi') || assetName.endsWith('.zip')) {
            downloadUrl = asset['browser_download_url']?.toString() ?? '';
            final sizeBytes = asset['size'] as num?;
            if (sizeBytes != null && sizeBytes > 0) {
              fileSizeMb = sizeBytes / (1024 * 1024);
            }
            break;
          }
        }
      }

      if (downloadUrl.isEmpty) {
        downloadUrl = json['html_url']?.toString() ?? '';
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: cleanVersion.isNotEmpty ? cleanVersion : tagName,
        releaseTitle: name,
        releaseNotes: body,
        downloadUrl: downloadUrl,
        fileSizeMb: fileSizeMb,
        isMandatory: false,
        publishedAt: publishedAt,
      );
    }

    // Standard Custom JSON format:
    // { "version": "1.1.0", "title": "...", "notes": "...", "download_url": "...", "file_size_mb": 45.0, "is_mandatory": false }
    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: json['version']?.toString() ?? '0.0.0',
      releaseTitle: json['title']?.toString() ?? 'New Version Available',
      releaseNotes: json['notes']?.toString() ?? json['release_notes']?.toString() ?? 'Bug fixes and performance improvements.',
      downloadUrl: json['download_url']?.toString() ?? json['url']?.toString() ?? '',
      fileSizeMb: (json['file_size_mb'] is num) ? (json['file_size_mb'] as num).toDouble() : null,
      isMandatory: json['is_mandatory'] == true,
      publishedAt: json['published_at']?.toString(),
    );
  }
}

/// Service handling in-app update checks, file downloads with progress, and installation
class AppUpdateService {
  /// Default Application Version (synced with pubspec.yaml)
  static const String defaultAppVersion = '0.0.0.3';
  static const int defaultAppBuildNumber = 3;

  static String _cachedVersion = defaultAppVersion;
  static int _cachedBuildNumber = defaultAppBuildNumber;

  static String get appVersion => _cachedVersion;
  static int get appBuildNumber => _cachedBuildNumber;

  static const String _prefInstalledVersionKey = 'app_installed_version_v2';
  static const String _prefInstalledBuildKey = 'app_installed_build_v2';

  /// Default Cloud Endpoint (Firebase Realtime Database)
  static const String defaultUpdateUrl =
      'https://madarsa-management-cloud-default-rtdb.asia-southeast1.firebasedatabase.app/settings/app_update.json';

  static const String _prefAutoCheckKey = 'app_auto_check_updates_v1';
  static const String _prefCustomUrlKey = 'app_custom_update_url_v1';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (status) => status != null && status < 500,
    headers: {
      'Accept': 'application/json, application/vnd.github.v3+json',
      'User-Agent': 'MadarsaApp-Desktop/$defaultAppVersion',
    },
  ));

  /// Initializes version information by reading from version.json / SharedPreferences
  static Future<String> initVersion() async {
    return await getCurrentVersion();
  }

  /// Gets current installed version dynamically
  static Future<String> getCurrentVersion() async {
    // 1. Check version.json in local application directory
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidateFiles = [
        File(p.join(exeDir, 'version.json')),
        File(p.join(p.dirname(exeDir), 'version.json')),
        File(p.join(Directory.current.path, 'version.json')),
      ];
      for (final f in candidateFiles) {
        if (f.existsSync()) {
          final content = jsonDecode(f.readAsStringSync());
          if (content is Map && content.containsKey('version')) {
            final fVer = content['version'].toString().trim();
            if (fVer.isNotEmpty) {
              _cachedVersion = fVer;
              if (content.containsKey('build_number') && content['build_number'] is int) {
                _cachedBuildNumber = content['build_number'] as int;
              }
              return _cachedVersion;
            }
          }
        }
      }
    } catch (_) {}

    // 2. Check SharedPreferences if an update was recorded
    try {
      final prefs = await SharedPreferences.getInstance();
      final recVer = prefs.getString(_prefInstalledVersionKey)?.trim();
      if (recVer != null && recVer.isNotEmpty) {
        _cachedVersion = recVer;
        _cachedBuildNumber = prefs.getInt(_prefInstalledBuildKey) ?? defaultAppBuildNumber;
        return _cachedVersion;
      }
    } catch (_) {}

    // 3. Default to code-compiled version
    _cachedVersion = defaultAppVersion;
    _cachedBuildNumber = defaultAppBuildNumber;
    return _cachedVersion;
  }

  /// Saves installed version to SharedPreferences
  static Future<void> recordInstalledVersion(String version, {int? buildNumber}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefInstalledVersionKey, version);
      if (buildNumber != null) {
        await prefs.setInt(_prefInstalledBuildKey, buildNumber);
      }
      _cachedVersion = version;
      if (buildNumber != null) {
        _cachedBuildNumber = buildNumber;
      }
    } catch (_) {}
  }

  /// Checks if auto-update checking on startup is enabled
  static Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoCheckKey) ?? true;
  }

  /// Sets auto-update checking preference
  static Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoCheckKey, enabled);
  }

  /// Gets the update endpoint URL (Firebase RTDB cloud endpoint)
  static Future<String> getUpdateEndpoint() async {
    return defaultUpdateUrl;
  }

  /// Sets custom update endpoint URL
  static Future<void> setUpdateEndpoint(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomUrlKey, url.trim());
  }

  /// Checks for available updates from remote server or GitHub API
  static Future<AppUpdateInfo?> checkForUpdate({String? customEndpoint}) async {
    try {
      final currentVer = await getCurrentVersion();
      final endpoint = customEndpoint ?? await getUpdateEndpoint();
      if (endpoint.isEmpty) return null;

      final response = await _dio.get(endpoint);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String ? jsonDecode(response.data as String) : response.data;
        if (data is Map<String, dynamic>) {
          return AppUpdateInfo.fromJson(data, currentVer);
        }
      }
    } catch (e) {
      debugPrint('AppUpdateService.checkForUpdate error: $e');
    }
    return null;
  }

  /// Compares semantic versions (e.g., '1.2.0' vs '1.1.5')
  /// Returns true if latest is strictly newer than current
  static bool isNewerVersion(String latest, String current) {
    try {
      final cleanLatest = latest.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');

      final lParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = lParts.length > cParts.length ? lParts.length : cParts.length;
      while (lParts.length < maxLen) {
        lParts.add(0);
      }
      while (cParts.length < maxLen) {
        cParts.add(0);
      }

      for (int i = 0; i < maxLen; i++) {
        if (lParts[i] > cParts[i]) return true;
        if (lParts[i] < cParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Converts sharing URLs (like Google Drive, Dropbox) into direct download links
  static String getDirectDownloadUrl(String url) {
    final clean = url.trim();
    if (clean.contains('drive.google.com')) {
      final regExp1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
      final match1 = regExp1.firstMatch(clean);
      if (match1 != null) {
        return 'https://drive.usercontent.google.com/download?id=${match1.group(1)}&export=download&confirm=t';
      }

      final regExp2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)');
      final match2 = regExp2.firstMatch(clean);
      if (match2 != null) {
        return 'https://drive.usercontent.google.com/download?id=${match2.group(1)}&export=download&confirm=t';
      }
    }
    return clean;
  }

  /// Downloads update file with real-time progress stream
  static Future<File?> downloadUpdate({
    required String downloadUrl,
    required String fileName,
    required void Function(int receivedBytes, int totalBytes, double progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = p.join(tempDir.path, fileName);
      var file = File(savePath);

      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }

      final directUrl = getDirectDownloadUrl(downloadUrl);

      await _dio.download(
        directUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total).clamp(0.0, 1.0);
            onProgress(received, total, progress);
          } else {
            onProgress(received, -1, 0.0);
          }
        },
      );

      if (file.existsSync()) {
        try {
          final isZip = _isZipArchive(file);
          if (isZip && !file.path.toLowerCase().endsWith('.zip')) {
            final newPath = p.setExtension(file.path, '.zip');
            final newFile = File(newPath);
            if (newFile.existsSync()) {
              try {
                newFile.deleteSync();
              } catch (_) {}
            }
            file = file.renameSync(newPath);
          } else if (!isZip && !file.path.toLowerCase().endsWith('.exe')) {
            final newPath = p.setExtension(file.path, '.exe');
            final newFile = File(newPath);
            if (newFile.existsSync()) {
              try {
                newFile.deleteSync();
              } catch (_) {}
            }
            file = file.renameSync(newPath);
          }
        } catch (e) {
          debugPrint('AppUpdateService.downloadUpdate extension normalization warning: $e');
        }
        return file;
      }
    } catch (e) {
      debugPrint('AppUpdateService.downloadUpdate error: $e');
      rethrow;
    }
    return null;
  }

  /// Applies the downloaded update (in-place patch .zip or silent .exe installer)
  /// and restarts the application seamlessly without wizard dialogues or file lock errors.
  static Future<bool> installUpdate(File updateFile, {String? targetVersion}) async {
    try {
      if (!await updateFile.exists()) return false;

      if (Platform.isWindows) {
        // 1. Create safety backup of user database before applying updates
        try {
          await createPreUpdateBackup();
        } catch (e) {
          debugPrint('Pre-update safety backup warning: $e');
        }

        // 2. Determine file type (ZIP patch vs PE EXE installer)
        final isZip = _isZipArchive(updateFile);

        // 3. Resolve target installation directory & relaunch executable
        final currentExe = Platform.resolvedExecutable;
        final appDir = p.dirname(currentExe);
        final parentDir = p.dirname(appDir);

        String targetDir = appDir;
        String relaunchExe = currentExe;

        final launcherInParent = p.join(parentDir, 'Madarsa Management.exe');
        final launcherInApp = p.join(appDir, 'Madarsa Management.exe');

        if (File(launcherInParent).existsSync()) {
          targetDir = parentDir;
          relaunchExe = launcherInParent;
        } else if (File(launcherInApp).existsSync()) {
          targetDir = appDir;
          relaunchExe = launcherInApp;
        }

        // 4. Create updater script files in %TEMP%\MadarsaApp_Updater
        final tempDir = Directory.systemTemp;
        final updaterDir = Directory(p.join(tempDir.path, 'MadarsaApp_Updater'));
        if (!updaterDir.existsSync()) {
          updaterDir.createSync(recursive: true);
        }

        final ps1File = File(p.join(updaterDir.path, 'updater.ps1'));
        final batFile = File(p.join(updaterDir.path, 'run_update.bat'));

        const ps1Script = r'''
param(
    [string]$PackageFile,
    [string]$TargetDir,
    [string]$RelaunchExe,
    [string]$IsZip,
    [string]$NewVersion = ""
)

$logFile = Join-Path $PSScriptRoot "updater.log"
function Write-Log($msg) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$time] $msg" | Out-File -FilePath $logFile -Append -Encoding utf8
}

Write-Log "========== Starting Madarsa Seamless Updater =========="
Write-Log "PackageFile: $PackageFile"
Write-Log "TargetDir: $TargetDir"
Write-Log "RelaunchExe: $RelaunchExe"
Write-Log "IsZipParam: $IsZip"
Write-Log "NewVersion: $NewVersion"

# Step 1: Terminate application and backend processes to release file locks
Write-Log "Terminating application processes..."
$waited = 0
while ((Get-Process -Name "madarsa_app", "Madarsa Management", "Madarsa Launcher" -ErrorAction SilentlyContinue) -and ($waited -lt 10)) {
    Start-Sleep -Milliseconds 500
    $waited += 0.5
}
Stop-Process -Name "madarsa_app" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Madarsa Management" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Madarsa Launcher" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "node" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800

# Verify file unlock for target executable
$targetExe = Join-Path $TargetDir "app\madarsa_app.exe"
if (-not (Test-Path $targetExe)) {
    $targetExe = Join-Path $TargetDir "madarsa_app.exe"
}
if (Test-Path $targetExe) {
    $unlocked = $false
    for ($i = 0; $i -lt 10; $i++) {
        try {
            $stream = [System.IO.File]::Open($targetExe, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $stream.Close()
            $stream.Dispose()
            $unlocked = $true
            break
        } catch {
            Write-Log "Executable still locked. Waiting 500ms (attempt $($i+1)/10)..."
            Start-Sleep -Milliseconds 500
        }
    }
    Write-Log "Executable unlock status: $unlocked"
}

# Step 2: Check write permissions in target folder
$canWrite = $true
$testGuid = [System.Guid]::NewGuid().ToString('N')
$testDir = $TargetDir
if (Test-Path (Join-Path $TargetDir "app")) {
    $testDir = Join-Path $TargetDir "app"
}
$testFile = Join-Path $testDir ".perm_test_$testGuid"
try {
    [System.IO.File]::WriteAllText($testFile, "test")
    if (Test-Path $testFile) {
        Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
    }
} catch {
    $canWrite = $false
}

Write-Log "Direct write permission: $canWrite"

if (-not $canWrite) {
    Write-Log "Elevation required for Program Files. Relaunching as Administrator..."
    $escapedPkg = $PackageFile.Replace("'", "''")
    $escapedTarget = $TargetDir.Replace("'", "''")
    $escapedRelaunch = $RelaunchExe.Replace("'", "''")
    $escapedVer = $NewVersion.Replace("'", "''")
    $argList = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\updater.ps1`" -PackageFile `"$escapedPkg`" -TargetDir `"$escapedTarget`" -RelaunchExe `"$escapedRelaunch`" -IsZip `"$IsZip`" -NewVersion `"$escapedVer`""
    Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList -Wait
    exit 0
}

# Step 3: Detect format (ZIP vs PE EXE installer) via magic bytes
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$isZipPackage = $false
try {
    $fs = [System.IO.File]::OpenRead($PackageFile)
    $magic = New-Object byte[] 4
    $read = $fs.Read($magic, 0, 4)
    $fs.Close()
    $fs.Dispose()
    if ($read -ge 2 -and $magic[0] -eq 0x50 -and $magic[1] -eq 0x4B) {
        $isZipPackage = $true
    } elseif ($read -ge 2 -and $magic[0] -eq 0x4D -and $magic[1] -eq 0x5A) {
        $isZipPackage = $false
    } else {
        $isZipPackage = ($IsZip -eq "1" -or $IsZip -eq "true" -or $PackageFile.ToLower().EndsWith(".zip"))
    }
} catch {
    $isZipPackage = ($IsZip -eq "1" -or $IsZip -eq "true")
}

Write-Log "Package format detected: isZipPackage=$isZipPackage"
$updateSuccess = $false

if ($isZipPackage) {
    Write-Log "Applying in-place patch using .NET ZipFile engine..."
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($PackageFile)
        $totalEntries = $zip.Entries.Count
        Write-Log "Archive opened. Total entries: $totalEntries"

        $extractedCount = 0
        $failedCount = 0
        $targetIsAppDir = (Test-Path (Join-Path $TargetDir "madarsa_app.exe"))

        foreach ($entry in $zip.Entries) {
            $rel = $entry.FullName
            if ([string]::IsNullOrWhiteSpace($rel) -or $rel.EndsWith('/') -or $rel.EndsWith('\')) {
                continue
            }

            $cleanRel = $rel -replace '/', '\'

            # If target dir is already the app folder and entry starts with 'app\', strip 'app\'
            if ($targetIsAppDir -and $cleanRel.StartsWith("app\")) {
                $cleanRel = $cleanRel.Substring(4)
            }

            $destFilePath = Join-Path $TargetDir $cleanRel
            $destFileDir = [System.IO.Path]::GetDirectoryName($destFilePath)

            if (-not (Test-Path $destFileDir)) {
                [System.IO.Directory]::CreateDirectory($destFileDir) | Out-Null
            }

            $entryDone = $false
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    if (Test-Path $destFilePath) {
                        [System.IO.File]::SetAttributes($destFilePath, [System.IO.FileAttributes]::Normal)
                    }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFilePath, $true)
                    $entryDone = $true
                    $extractedCount++
                    break
                } catch {
                    Write-Log "Attempt $attempt failed for $cleanRel : $_"
                    Start-Sleep -Milliseconds 400
                }
            }

            if (-not $entryDone) {
                $failedCount++
                Write-Log "CRITICAL: Could not overwrite $cleanRel after 5 attempts!"
            }
        }
        $zip.Dispose()

        Write-Log "Extraction finished. Extracted: $extractedCount, Failed: $failedCount"
        if ($failedCount -eq 0 -and $extractedCount -gt 0) {
            $updateSuccess = $true
            Write-Log "In-place patch applied successfully!"
        } else {
            Write-Log "Patch extraction incomplete or failed."
        }
    } catch {
        Write-Log "Error during zip extraction: $_"
    }
} else {
    Write-Log "Running silent installer: $PackageFile"
    try {
        $proc = Start-Process -FilePath $PackageFile -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /DIR=`"$TargetDir`"" -Wait -PassThru
        Write-Log "Installer finished with code: $($proc.ExitCode)"
        if ($proc.ExitCode -eq 0) {
            $updateSuccess = $true
        }
    } catch {
        Write-Log "Error running installer: $_"
    }
}

# Step 3.5: Update version.json only if update actually succeeded
if ($updateSuccess -and $NewVersion -and $NewVersion.Trim() -ne "") {
    Write-Log "Writing updated version.json ($NewVersion)..."
    $verJson = "{`r`n  `"version`": `"$NewVersion`",`r`n  `"build_number`": $([int]($NewVersion.Split('.')[-1]) + 1),`r`n  `"updated_at`": `"$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`"`r`n}"
    try {
        [System.IO.File]::WriteAllText((Join-Path $TargetDir "version.json"), $verJson)
        if (Test-Path (Join-Path $TargetDir "app")) {
            [System.IO.File]::WriteAllText((Join-Path $TargetDir "app\version.json"), $verJson)
        }
        Write-Log "version.json written successfully."
    } catch {
        Write-Log "Warning updating version.json: $_"
    }
} else {
    Write-Log "Skipped version.json update (updateSuccess=$updateSuccess)"
}

Start-Sleep -Milliseconds 800

# Step 4: Relaunch Application
Write-Log "Relaunching application..."
if (Test-Path $RelaunchExe) {
    Start-Process -FilePath $RelaunchExe
    Write-Log "Relaunched $RelaunchExe"
} else {
    $fallback = Join-Path $TargetDir "app\madarsa_app.exe"
    if (-not (Test-Path $fallback)) {
        $fallback = Join-Path $TargetDir "madarsa_app.exe"
    }
    if (Test-Path $fallback) {
        Start-Process -FilePath $fallback
        Write-Log "Relaunched fallback $fallback"
    }
}

Write-Log "Seamless updater completed successfully."
''';

        const batScript = r'''@echo off
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT_DIR%updater.ps1" -PackageFile "%~1" -TargetDir "%~2" -RelaunchExe "%~3" -IsZip "%~4" -NewVersion "%~5"
exit /b 0
''';

        await ps1File.writeAsString(ps1Script, flush: true);
        await batFile.writeAsString(batScript, flush: true);

        if (targetVersion != null && targetVersion.trim().isNotEmpty) {
          await recordInstalledVersion(targetVersion.trim());
        }

        // 5. Start updater detached
        await Process.start(
          'cmd.exe',
          [
            '/c',
            batFile.path,
            updateFile.path,
            targetDir,
            relaunchExe,
            isZip ? '1' : '0',
            targetVersion ?? '',
          ],
          mode: ProcessStartMode.detached,
        );

        // 6. Gracefully terminate current Flutter app so file locks are immediately released
        Future.delayed(const Duration(milliseconds: 300), () {
          exit(0);
        });

        return true;
      }

      return false;
    } catch (e) {
      debugPrint('AppUpdateService.installUpdate error: $e');
      return false;
    }
  }

  /// Helper to detect if file is a ZIP archive using magic bytes PK\x03\x04
  static bool _isZipArchive(File file) {
    try {
      final raf = file.openSync(mode: FileMode.read);
      final bytes = raf.readSync(4);
      raf.closeSync();
      if (bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04) {
        return true;
      }
    } catch (_) {}
    return file.path.toLowerCase().endsWith('.zip');
  }

  /// Creates an automatic safety backup of user database before applying updates
  static Future<String?> createPreUpdateBackup() async {
    try {
      final dbFile = await DatabaseHelper().getDatabaseFile();
      if (!await dbFile.exists()) return null;

      final appDocDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(appDocDir.path, 'Madarsa_App_Backups', 'Pre_Update_Safety_Backups'));
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final backupFileName = 'safety_backup_v${appVersion}_$timestamp.db';
      final targetPath = p.join(backupDir.path, backupFileName);

      await dbFile.copy(targetPath);
      debugPrint('Pre-update safety backup successfully created at: $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('Error creating pre-update safety backup: $e');
      return null;
    }
  }

  /// Opens the release webpage in default browser
  static Future<void> openReleasePage(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('AppUpdateService.openReleasePage error: $e');
    }
  }
}
