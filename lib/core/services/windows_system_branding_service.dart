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
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final exeIco = File(p.join(exeDir, _icoFileName));
        await exeIco.writeAsBytes(icoBytes, flush: true);
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
  }) async {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;

      final userProfile = Platform.environment['USERPROFILE'] ?? '';
      final appData = Platform.environment['APPDATA'] ?? '';

      final targetDirs = <String>[];
      if (userProfile.isNotEmpty) {
        final desktop = p.join(userProfile, 'Desktop');
        if (Directory(desktop).existsSync()) {
          targetDirs.add(desktop);
        }
      }
      if (appData.isNotEmpty) {
        final startMenu = p.join(appData, r'Microsoft\Windows\Start Menu\Programs');
        if (Directory(startMenu).existsSync()) {
          targetDirs.add(startMenu);
        }
      }

      final safeName = appName.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
      final cleanName = safeName.isNotEmpty ? safeName : AppBranding.defaultAppNameEnglish;

      // Fallback icon path if custom icon is absent
      String resolvedIco = (icoPath != null && File(icoPath).existsSync())
          ? icoPath
          : p.join(exeDir, _icoFileName);
      if (!File(resolvedIco).existsSync()) {
        const defaultResource = r'windows\runner\resources\app_icon.ico';
        if (File(defaultResource).existsSync()) {
          resolvedIco = File(defaultResource).absolute.path;
        } else {
          resolvedIco = exePath; // Fallback to exe embedded icon
        }
      }

      for (final dir in targetDirs) {
        // Clean up any stale shortcut with previous names pointing to this app
        try {
          final entries = Directory(dir).listSync();
          for (final entry in entries) {
            if (entry is File && entry.path.toLowerCase().endsWith('.lnk')) {
              final fileName = p.basenameWithoutExtension(entry.path).toLowerCase();
              if (fileName.contains('madarsa') ||
                  fileName.contains('مدرسہ') ||
                  fileName == cleanName.toLowerCase()) {
                if (p.basenameWithoutExtension(entry.path) != cleanName) {
                  try {
                    entry.deleteSync();
                  } catch (_) {}
                }
              }
            }
          }
        } catch (_) {}

        final shortcutPath = p.join(dir, '$cleanName.lnk');

        // PowerShell script to create or update Windows shortcut via WScript.Shell
        final escapedShortcut = shortcutPath.replaceAll("'", "''");
        final escapedExe = exePath.replaceAll("'", "''");
        final escapedDir = exeDir.replaceAll("'", "''");
        final escapedIco = resolvedIco.replaceAll("'", "''");
        final escapedDesc = tagline.replaceAll("'", "''");

        final psScript = '''
\$WshShell = New-Object -ComObject WScript.Shell;
\$Shortcut = \$WshShell.CreateShortcut('$escapedShortcut');
\$Shortcut.TargetPath = '$escapedExe';
\$Shortcut.WorkingDirectory = '$escapedDir';
\$Shortcut.IconLocation = '$escapedIco,0';
\$Shortcut.Description = '$escapedDesc';
\$Shortcut.Save();
''';

        await Process.run('powershell.exe', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          psScript,
        ]);
      }

      // Tell Windows Explorer to refresh its icon cache immediately
      refreshWindowsShell();
    } catch (e) {
      debugPrint('[WindowsSystemBrandingService] updateSystemShortcuts error: $e');
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

  /// Master function: Applies custom Branding across the entire system.
  static Future<void> applySystemBranding(AppBranding branding) async {
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
    );
  }
}
