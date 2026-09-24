import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/backup_service.dart';
import '../../../../core/theme/app_theme.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final _backupService = BackupService();
  bool _isLoading = false;

  Future<void> _handleBackup() async {
    setState(() => _isLoading = true);
    final result = await _backupService.exportDatabase();
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result ?? 'Backup cancelled')),
      );
    }
  }

  Future<void> _handleRestore() async {
    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('restore_data')),
        content: const Text(
          'WARNING: Restoring will overwrite all current data. This action cannot be undone. Do you want to proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text(context.tr('proceed')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    final result = await _backupService.importDatabase();
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result ?? 'Restore cancelled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF161625) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Backup & Restore', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_sync_rounded,
                  size: 80,
                  color: AppTheme.primaryColor.withAlpha(200),
                ),
                const SizedBox(height: 24),
                Text(
                  'Manage Your Data',
                  style: AppTheme.getFontStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Backup your database to a USB drive or external storage for safety, or restore it from a previous backup file.',
                  textAlign: TextAlign.center,
                  style: AppTheme.getFontStyle(
                    fontSize: 15,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 48),
                if (_isLoading)
                  const CircularProgressIndicator()
                else ...[
                  _buildActionButton(
                    context,
                    label: context.tr('export_backup_file'),
                    icon: Icons.upload_rounded,
                    color: AppTheme.primaryColor,
                    onPressed: _handleBackup,
                  ),
                  const SizedBox(height: 16),
                  _buildActionButton(
                    context,
                    label: context.tr('import_restore_file'),
                    icon: Icons.download_rounded,
                    color: AppTheme.accentColor,
                    isOutline: true,
                    onPressed: _handleRestore,
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withAlpha(10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.errorColor.withAlpha(30)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Important: Keep your backup files in a safe place. Loss of database files results in permanent data loss.',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            color: AppTheme.errorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool isOutline = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: isOutline
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label, style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color, width: 2),
                foregroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label, style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
    );
  }
}
