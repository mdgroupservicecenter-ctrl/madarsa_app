import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/app_theme.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.isMandatory,
      builder: (ctx) => AppUpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  bool _isInstalling = false;
  double _downloadProgress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  File? _downloadedFile;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog closed');
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _isInstalling = false;
      _downloadProgress = 0.0;
      _errorMessage = null;
      _cancelToken = CancelToken();
    });

    try {
      // 1. Automatically create safety database backup before applying update
      await AppUpdateService.createPreUpdateBackup();

      final downloadUrl = widget.updateInfo.downloadUrl;
      if (downloadUrl.isEmpty) {
        throw Exception('Download URL is not available for this release.');
      }

      // Always use .zip extension for seamless patch downloads.
      // Google Drive sends ZIP files regardless of the URL pattern.
      // The old logic that checked URL for '.exe' was causing the wrong extension,
      // which made PowerShell's Expand-Archive reject the file.
      final fileName = 'Madarsa_App_Update_${widget.updateInfo.latestVersion}.zip';

      final file = await AppUpdateService.downloadUpdate(
        downloadUrl: downloadUrl,
        fileName: fileName,
        cancelToken: _cancelToken,
        onProgress: (received, total, progress) {
          if (mounted) {
            setState(() {
              _receivedBytes = received;
              _totalBytes = total;
              _downloadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadedFile = file;
        });

        if (file != null) {
          _launchInstaller();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _launchInstaller() async {
    if (_downloadedFile == null || _isInstalling) return;
    setState(() => _isInstalling = true);

    // Give UI a brief moment to render "Applying update & restarting..." state
    await Future.delayed(const Duration(milliseconds: 500));

    final success = await AppUpdateService.installUpdate(
      _downloadedFile!,
      targetVersion: widget.updateInfo.latestVersion,
    );
    if (!success && mounted) {
      setState(() {
        _isInstalling = false;
        _errorMessage = 'Failed to apply update automatically. You can install it manually from Downloads.';
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = widget.updateInfo;

    return PopScope(
      canPop: !info.isMandatory && !_isDownloading && !_isInstalling,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        child: Container(
          width: min(640.0, MediaQuery.of(context).size.width - 32),
          constraints: BoxConstraints(maxHeight: min(660.0, MediaQuery.of(context).size.height - 32)),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Bar with App Icon & Version Badge ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F766E).withAlpha(80),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Update Available',
                              style: AppTheme.getFontStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF10B981)),
                              ),
                              child: Text(
                                'v${info.latestVersion}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'نئی اپڈیٹ دستیاب ہے (Current: v${info.currentVersion})',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!info.isMandatory && !_isDownloading && !_isInstalling)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Meta Info Chips (Size, Date) ──
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  if (info.fileSizeMb != null)
                    _buildMetaChip(
                      icon: Icons.folder_zip_rounded,
                      label: '${info.fileSizeMb!.toStringAsFixed(1)} MB',
                      isDark: isDark,
                    ),
                  if (info.publishedAt != null)
                    _buildMetaChip(
                      icon: Icons.calendar_today_rounded,
                      label: info.publishedAt!.split('T').first,
                      isDark: isDark,
                    ),
                  _buildMetaChip(
                    icon: Icons.verified_rounded,
                    label: 'Official Build',
                    isDark: isDark,
                  ),
                  _buildMetaChip(
                    icon: Icons.shield_rounded,
                    label: '🔒 100% Data Safe (Auto-Backup)',
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Data Safety Notice ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withAlpha(60)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'User data & database are automatically backed up before update. No data will be lost.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Release Notes / Changelog Box ──
              Text(
                'What\'s New / نئی تبدیلیاں:',
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade300,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      info.releaseNotes.trim().isNotEmpty
                          ? info.releaseNotes
                          : '• Performance improvements and bug fixes\n• Result Card Designer & Seating Plan enhancements\n• Offline PDF and Excel export updates',
                      style: AppTheme.getFontStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Download Progress / Error Display ──
              if (_isDownloading) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0F766E).withAlpha(60)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Downloading Update...',
                            style: AppTheme.getFontStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F766E),
                            ),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                        backgroundColor: Colors.grey.shade300,
                        color: const Color(0xFF0F766E),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatBytes(_receivedBytes)} / ${_totalBytes > 0 ? _formatBytes(_totalBytes) : 'Unknown'}',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                          ),
                          InkWell(
                            onTap: () {
                              _cancelToken?.cancel('User cancelled download');
                              setState(() => _isDownloading = false);
                            },
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withAlpha(100)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Action Buttons ──
              if (_downloadedFile == null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!info.isMandatory && !_isDownloading)
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('بعد میں (Remind Later)'),
                          ),
                        if (info.downloadUrl.startsWith('http') && !_isDownloading) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                            label: const Text('Browser Download'),
                            onPressed: () => AppUpdateService.openReleasePage(info.downloadUrl),
                          ),
                        ],
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isDownloading ? null : _startDownload,
                          icon: _isDownloading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            _isDownloading ? 'Downloading...' : 'Update Now (ابھی اپڈیٹ کریں)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Download completed successfully
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withAlpha(120)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Download complete! Ready to apply seamless update & restart.',
                              style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isInstalling)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0F766E)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F766E)),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Applying update & restarting... / ایپ دوبارہ شروع ہو رہی ہے',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F766E)),
                            ),
                          ],
                        ),
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!info.isMandatory)
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel (منسوخ)'),
                            ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                            onPressed: _launchInstaller,
                            icon: const Icon(Icons.restart_alt_rounded, size: 20),
                            label: const Text(
                              'Install & Restart (انسٹال اور دوبارہ شروع کریں)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
