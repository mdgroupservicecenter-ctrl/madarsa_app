import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';
import '../branding/app_branding.dart';

typedef _SHChangeNotifyC = Void Function(
  Int32 wEventId,
  Uint32 uFlags,
  Pointer<Void> dwItem1,
  Pointer<Void> dwItem2,
);
typedef _SHChangeNotifyDart = void Function(
  int wEventId,
  int uFlags,
  Pointer<Void> dwItem1,
  Pointer<Void> dwItem2,
);

/// Comprehensive Windows System Integration Service.
/// Synchronizes customized App Name and Logo to:
/// 1. Window Title & Titlebar Icon
/// 2. Windows Taskbar (Name & Icon)
/// 3. Windows Desktop Shortcut (.lnk)
/// 4. Windows Start Menu Shortcut (.lnk)
/// 5. Windows Shell Icon Cache
class WindowsSystemBrandingService {
  static const String _icoFileName = 'app_custom_icon.ico';
  static int? _cachedHwnd;

  /// Locates the top-level main window handle (HWND) for the current Flutter process.
  static int? getMainWindowHwnd() {
    if (!Platform.isWindows) return null;
    if (_cachedHwnd != null && IsWindow(_cachedHwnd!) != 0) {
      return _cachedHwnd;
    }

    final currentPid = GetCurrentProcessId();
    int foundHwnd = 0;

    final callback = NativeCallable<WNDENUMPROC>.isolateLocal(
      (int hwnd, int lParam) {
        final pPid = calloc<DWORD>();
        try {
          GetWindowThreadProcessId(hwnd, pPid);
          if (pPid.value == currentPid) {
            if (IsWindowVisible(hwnd) != 0) {
              final parent = GetWindow(hwnd, GW_OWNER);
              if (parent == 0) {
                foundHwnd = hwnd;
                return 0; // Stop enumeration
              }
            }
          }
          return 1; // Continue
        } finally {
          calloc.free(pPid);
        }
      },
      exceptionalReturn: 0,
    );

    EnumWindows(callback.nativeFunction, 0);
    callback.close();

    if (foundHwnd != 0) {
      _cachedHwnd = foundHwnd;
      return foundHwnd;
    }
    return null;
  }

  /// Converts any image file (PNG, JPG, JPEG, WEBP) to a high-definition
  /// Windows multi-layer ICO file containing 16x16, 32x32, 48x48, 64x64, 128x128, and 256x256 icons.
  static Future<String?> generateIcoFromImage(String sourceImagePath) async {
    try {
      final sourceFile = File(sourceImagePath);
      if (!sourceFile.existsSync()) return null;

      final bytes = await sourceFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Generate standard Windows multi-resolution icon layers
      const sizes = [16, 32, 48, 64, 128, 256];
      final layers = <img.Image>[];
      for (final s in sizes) {
        layers.add(img.copyResize(
          decoded,
          width: s,
          height: s,
          interpolation: img.Interpolation.linear,
        ));
      }

      final encoder = img.IcoEncoder();
      final icoBytes = encoder.encodeImages(layers);

      // Save to persistent App Documents Branding folder (with fallback to APPDATA / systemTemp)
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

      final targetIco = File(p.join(brandingDir.path, _icoFileName));
      await targetIco.writeAsBytes(icoBytes, flush: true);

      // Copy adjacent to executable for Windows Explorer / shortcut linking
      try {
        final exePath = Platform.resolvedExecutable;
        final exeDir = File(exePath).parent.path;
        final exeIco = File(p.join(exeDir, _icoFileName));
        await exeIco.writeAsBytes(icoBytes, flush: true);

        // Also copy to parent launcher directory (Madarsa Management System)
        final parentDir = p.dirname(exeDir);
        final parentIco = File(p.join(parentDir, _icoFileName));
        await parentIco.writeAsBytes(icoBytes, flush: true);
      } catch (_) {}

      // Copy to windows project runner resources if present
      try {
        const projectIco = r'windows\runner\resources\app_icon.ico';
        final projFile = File(projectIco);
        if (projFile.existsSync() || Directory(p.dirname(projectIco)).existsSync()) {
          await projFile.writeAsBytes(icoBytes, flush: true);
        }
      } catch (_) {}

      return targetIco.path;
    } catch (e) {
      debugPrint('[WindowsSystemBrandingService] Error generating ICO: $e');
      return null;
    }
  }

  /// Updates the live Windows window title and taskbar button text in real-time.
  static void updateWindowTitle(String title) {
    if (!Platform.isWindows) return;
    try {
      final hwnd = getMainWindowHwnd();
      if (hwnd == null) return;

      final pTitle = title.toNativeUtf16();
      try {
        SetWindowText(hwnd, pTitle);
      } finally {
        calloc.free(pTitle);
      }
    } catch (e) {
      debugPrint('[WindowsSystemBrandingService] updateWindowTitle error: $e');
    }
  }

  /// Updates the live Windows titlebar icon and taskbar button icon in real-time.
  static void updateWindowIcon(String icoPath) {
    if (!Platform.isWindows) return;
    try {
      final file = File(icoPath);
      if (!file.existsSync()) return;

      final hwnd = getMainWindowHwnd();
      if (hwnd == null) return;

      final pPath = icoPath.toNativeUtf16();
      try {
        final hIconBig = LoadImage(
          NULL,
          pPath,
          IMAGE_ICON,
          32,
          32,
          LR_LOADFROMFILE,
        );
        final hIconSmall = LoadImage(
          NULL,
          pPath,
          IMAGE_ICON,
          16,
          16,
          LR_LOADFROMFILE,
        );

        if (hIconBig != NULL) {
          SendMessage(hwnd, WM_SETICON, ICON_BIG, hIconBig);
        }
        if (hIconSmall != NULL) {
          SendMessage(hwnd, WM_SETICON, ICON_SMALL, hIconSmall);
        }
      } finally {
        calloc.free(pPath);
      }
    } catch (e) {
      debugPrint('[WindowsSystemBrandingService] updateWindowIcon error: $e');
    }
  }

  /// Creates or updates Windows Desktop and Start Menu shortcuts (.lnk)
  /// with the configured App Name, Target Executable, and Custom Logo.
  static Future<void> updateSystemShortcuts({
    required String appName,
    required String tagline,
    required String? icoPath,
    String? oldAppName,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      // 1. Target Executable Resolution:
      // If running from app/madarsa_app.exe, target the Launcher (Madarsa Management.exe)
      // in the parent directory so both Backend and Frontend are launched together!
      String targetExe = exePath;
      String targetDir = exeDir;
      final launcherInParent = p.normalize(p.join(exeDir, '..', 'Madarsa Management.exe'));
      final launcherInSame = p.normalize(p.join(exeDir, 'Madarsa Management.exe'));
      if (File(launcherInParent).existsSync()) {
        targetExe = launcherInParent;
        targetDir = p.dirname(launcherInParent);
      } else if (File(launcherInSame).existsSync()) {
        targetExe = launcherInSame;
        targetDir = exeDir;
      }

      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final appData = Platform.environment['APPDATA'] ?? '';
      final publicDir = Platform.environment['PUBLIC'] ?? r'C:\Users\Public';
      final programData = Platform.environment['ALLUSERSPROFILE'] ?? r'C:\ProgramData';

      final userDesktop = userProfile.isNotEmpty ? p.join(userProfile, 'Desktop') : '';
      final publicDesktop = publicDir.isNotEmpty ? p.join(publicDir, 'Desktop') : '';
      final userStartMenu = appData.isNotEmpty ? p.join(appData, r'Microsoft\Windows\Start Menu\Programs') : '';
      final publicStartMenu = programData.isNotEmpty ? p.join(programData, r'Microsoft\Windows\Start Menu\Programs') : '';

      final safeName = appName.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
      final cleanName = safeName.isNotEmpty ? safeName : AppBranding.defaultAppNameEnglish;

      final safeOldName = oldAppName?.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim() ?? '';

      // Fallback icon path if custom icon is absent
      String resolvedIco = (icoPath != null && File(icoPath).existsSync())
          ? icoPath
          : p.join(targetDir, _icoFileName);
      if (!File(resolvedIco).existsSync()) {
        resolvedIco = p.join(exeDir, _icoFileName);
      }
      if (!File(resolvedIco).existsSync()) {
        const defaultResource = r'windows\runner\resources\app_icon.ico';
        if (File(defaultResource).existsSync()) {
          resolvedIco = File(defaultResource).absolute.path;
        } else {
          resolvedIco = targetExe; // Fallback to exe embedded icon
        }
      }

      // Escape variables for PowerShell
      final escapedCleanName = cleanName.replaceAll("'", "''");
      final escapedOldName = safeOldName.replaceAll("'", "''");
      final escapedExe = targetExe.replaceAll("'", "''");
      final escapedDir = targetDir.replaceAll("'", "''");
      final escapedIco = resolvedIco.replaceAll("'", "''");
      final escapedDesc = tagline.replaceAll("'", "''");

      final escapedUserDesktop = userDesktop.replaceAll("'", "''");
      final escapedPublicDesktop = publicDesktop.replaceAll("'", "''");
      final escapedUserStart = userStartMenu.replaceAll("'", "''");
      final escapedPublicStart = publicStartMenu.replaceAll("'", "''");

      // 2. Comprehensive Target-based Shortcut Cleanup & Creation in PowerShell
      final psScript = '''
\$WshShell = New-Object -ComObject WScript.Shell
\$allDirs = @('$escapedUserDesktop', '$escapedPublicDesktop', '$escapedUserStart', '$escapedPublicStart')
\$targetDirs = @('$escapedUserDesktop', '$escapedUserStart')
\$cleanName = '$escapedCleanName'
\$oldName = '$escapedOldName'

# Step A: Deep scan and purge stale, duplicate, or previous shortcuts
foreach (\$dir in \$allDirs) {
    if (-not \$dir -or -not (Test-Path \$dir)) { continue }
    \$isPublic = (\$dir -like "*Public*" -or \$dir -like "*ProgramData*")

    Get-ChildItem -Path \$dir -Filter "*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
        \$lnkPath = \$_.FullName
        \$baseName = \$_.BaseName
        \$deleteThis = \$false

        # Explicit previous name match
        if (\$oldName -ne '' -and (\$baseName -eq \$oldName) -and (\$baseName -ne \$cleanName)) {
            \$deleteThis = \$true
        }

        # Default or legacy names match
        if ((\$baseName -like "*Madarsa Management*" -or \$baseName -like "*مدرسہ*") -and (\$baseName -ne \$cleanName)) {
            \$deleteThis = \$true
        }

        # Target-based inspection: check where the shortcut actually points!
        try {
            \$sc = \$WshShell.CreateShortcut(\$lnkPath)
            \$scTarget = \$sc.TargetPath
            \$scWork = \$sc.WorkingDirectory

            \$isOurApp = (\$scTarget -like "*Madarsa Management.exe*" -or 
                         \$scTarget -like "*madarsa_app.exe*" -or 
                         \$scWork -like "*Madarsa Management System*" -or 
                         \$scWork -like "*Madarsa_Single_Package*")

            if (\$isOurApp) {
                if (\$isPublic) {
                    # Always purge from Public desktop/start-menu
                    \$deleteThis = \$true
                } elseif (\$baseName -ne \$cleanName) {
                    # In User locations, remove any shortcut whose name is not the new cleanName
                    \$deleteThis = \$true
                }
            }
        } catch {}

        if (\$deleteThis) {
            try {
                [System.IO.File]::Delete(\$lnkPath)
            } catch {
                try { Remove-Item -Path \$lnkPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
    }
}

# Step B: Create / update the single clean shortcut in User Desktop and Start Menu
foreach (\$dir in \$targetDirs) {
    if (-not \$dir -or -not (Test-Path \$dir)) { continue }
    \$shortcutPath = Join-Path \$dir "\$cleanName.lnk"
    \$Shortcut = \$WshShell.CreateShortcut(\$shortcutPath)
    \$Shortcut.TargetPath = '$escapedExe'
    \$Shortcut.WorkingDirectory = '$escapedDir'
    \$Shortcut.IconLocation = '$escapedIco,0'
    \$Shortcut.Description = '$escapedDesc'
    \$Shortcut.Save()
}
''';

      await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psScript,
      ]);

      // Tell Windows Explorer to refresh its icon cache immediately
      refreshWindowsShell();
    } catch (e) {
      debugPrint('[WindowsSystemBrandingService] updateSystemShortcuts error: $e');
    }
  }

  /// Fail-safe: Ensures the Node.js backend server is running on port 3000.
  /// If port 3000 is not responding, automatically starts the bundled backend server.
  static Future<void> ensureBackendRunning() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    try {
      final isAlive = await _checkPort3000();
      if (isAlive) {
        debugPrint('[Backend] Backend is already active on port 3000.');
        return;
      }

      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        p.normalize(p.join(exeDir, '..', 'server')),
        p.normalize(p.join(exeDir, 'server')),
        p.normalize(p.join(exeDir, '..', 'Resources', 'server')),
        '/Applications/Madarsa Management.app/Contents/Resources/server',
        r'C:\Program Files\Madarsa Management System\server',
        r'D:\MD Group\Madarsa_Single_Package\server',
        r'D:\MD Group\backend',
      ];

      for (final sDir in candidates) {
        final serverJs = p.join(sDir, 'src', 'server.js');
        if (File(serverJs).existsSync()) {
          final localNode = Platform.isWindows ? p.join(sDir, 'node.exe') : p.join(sDir, 'node');
          final nodeExe = File(localNode).existsSync() ? localNode : 'node';
          debugPrint('[Backend] Auto-starting backend from $sDir via $nodeExe');
          await Process.start(
            nodeExe,
            ['src/server.js'],
            workingDirectory: sDir,
            mode: ProcessStartMode.detached,
          );

          for (int i = 0; i < 15; i++) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (await _checkPort3000()) {
              debugPrint('[WindowsBackend] Backend started and verified on port 3000 ✅');
              break;
            }
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('[WindowsBackend] Error in ensureBackendRunning: $e');
    }
  }

  static Future<bool> _checkPort3000() async {
    try {
      final socket = await Socket.connect('127.0.0.1', 3000, timeout: const Duration(milliseconds: 350));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers Windows Shell notification and ie4uinit to refresh icon caches immediately.
  static void refreshWindowsShell() {
    if (!Platform.isWindows) return;
    try {
      // 1. Native Win32 SHChangeNotify via shell32.dll
      try {
        final shell32 = DynamicLibrary.open('shell32.dll');
        final fn = shell32.lookupFunction<_SHChangeNotifyC, _SHChangeNotifyDart>('SHChangeNotify');
        // SHCNE_ASSOCCHANGED = 0x08000000, SHCNF_IDLIST = 0x0000
        fn(0x08000000, 0, nullptr, nullptr);
      } catch (_) {}

      // 2. Refresh Windows icon cache via ie4uinit
      try {
        Process.run('ie4uinit.exe', ['-show']);
      } catch (_) {}
    } catch (_) {}
  }

  /// Updates Windows Uninstall Registry (Add/Remove Programs, Control Panel, Geek Uninstaller)
  /// so that the user's custom App Name and custom Logo are displayed everywhere.
  static Future<void> updateUninstallRegistry({
    required String appName,
    required String? icoPath,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final safeName = appName.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
      final cleanName = safeName.isNotEmpty ? safeName : AppBranding.defaultAppNameEnglish;

      final escapedCleanName = cleanName.replaceAll("'", "''");
      final escapedIco = (icoPath != null && File(icoPath).existsSync())
          ? icoPath.replaceAll("'", "''")
          : '';

      final psScript = '''
\$keys = @(
    "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{D983A20B-48BE-48FB-B68C-28D8A78F2831}_is1",
    "HKCU:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{D983A20B-48BE-48FB-B68C-28D8A78F2831}_is1",
    "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{D983A20B-48BE-48FB-B68C-28D8A78F2831}_is1",
    "HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{D983A20B-48BE-48FB-B68C-28D8A78F2831}_is1"
)
foreach (\$k in \$keys) {
    if (Test-Path \$k) {
        try {
            \$ver = (Get-ItemProperty -Path \$k -Name "DisplayVersion" -ErrorAction SilentlyContinue).DisplayVersion
            \$displayName = if (\$ver) { "$escapedCleanName version \$ver" } else { "$escapedCleanName" }
            Set-ItemProperty -Path \$k -Name "DisplayName" -Value \$displayName -ErrorAction SilentlyContinue
            if ('$escapedIco' -ne '') {
                Set-ItemProperty -Path \$k -Name "DisplayIcon" -Value "$escapedIco,0" -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
''';

      await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psScript,
      ]);
    } catch (e) {
      debugPrint('[WindowsSystemBrandingService] updateUninstallRegistry error: $e');
    }
  }

  /// Master function: Applies custom Branding across the entire system.
  static Future<void> applySystemBranding(
    AppBranding branding, {
    String? oldAppName,
  }) async {
    if (!Platform.isWindows) return;

    final appName = branding.appNameEnglish.trim().isNotEmpty
        ? branding.appNameEnglish.trim()
        : AppBranding.defaultAppNameEnglish;

    // 1. Update live window title & taskbar label
    updateWindowTitle(appName);

    // 2. Generate or resolve Windows ICO file
    String? icoPath;
    if (branding.hasCustomLogo) {
      icoPath = await generateIcoFromImage(branding.logoPath!);
    } else {
      const defaultIco = r'windows\runner\resources\app_icon.ico';
      if (File(defaultIco).existsSync()) {
        icoPath = File(defaultIco).absolute.path;
      }
    }

    // 3. Update live window titlebar icon & taskbar button icon
    if (icoPath != null && File(icoPath).existsSync()) {
      updateWindowIcon(icoPath);
    }

    // 4. Update Desktop and Start Menu shortcuts (.lnk)
    await updateSystemShortcuts(
      appName: appName,
      tagline: branding.tagline,
      icoPath: icoPath,
      oldAppName: oldAppName,
    );

    // 5. Update Windows Uninstall Registry (Control Panel & Geek Uninstaller)
    await updateUninstallRegistry(
      appName: appName,
      icoPath: icoPath,
    );
  }
}
