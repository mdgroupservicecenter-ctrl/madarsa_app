import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/storage_mode_service.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/storage/database_helper.dart';

class StorageSyncSettingsScreen extends StatefulWidget {
  const StorageSyncSettingsScreen({super.key});

  @override
  State<StorageSyncSettingsScreen> createState() => _StorageSyncSettingsScreenState();
}

class _StorageSyncSettingsScreenState extends State<StorageSyncSettingsScreen> {
  bool _isProcessing = false;
  String _processStatus = '';
  int _localStudentsCount = 0;
  int _localStaffCount = 0;
  int _localDepartmentsCount = 0;
  int _localClassesCount = 0;
  int _localCoursesCount = 0;
  int _localBooksCount = 0;

  bool _autoSyncEnabled = true;
  int _autoSyncIntervalSeconds = 15;
  final TextEditingController _intervalCtrl = TextEditingController();
  StreamSubscription? _cloudUpdatesSub;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _autoSyncEnabled = FirebaseService.isAutoSyncEnabled;
    _autoSyncIntervalSeconds = FirebaseService.autoSyncIntervalSeconds;
    _intervalCtrl.text = _autoSyncIntervalSeconds.toString();

    _loadLocalStats();

    _cloudUpdatesSub = FirebaseService.onCloudUpdated.listen((_) {
      if (mounted) {
        _loadLocalStats();
        setState(() {});
      }
    });

    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _autoSyncEnabled) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    _cloudUpdatesSub?.cancel();
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalStats() async {
    try {
      final db = await DatabaseHelper().database;
      final stCount = (await db.rawQuery('SELECT COUNT(*) as c FROM students')).first['c'] as int? ?? 0;
      final sfCount = (await db.rawQuery('SELECT COUNT(*) as c FROM staff')).first['c'] as int? ?? 0;
      final dpCount = (await db.rawQuery('SELECT COUNT(*) as c FROM departments')).first['c'] as int? ?? 0;
      final clCount = (await db.rawQuery('SELECT COUNT(*) as c FROM classes')).first['c'] as int? ?? 0;
      final crCount = (await db.rawQuery('SELECT COUNT(*) as c FROM courses')).first['c'] as int? ?? 0;
      final bkCount = (await db.rawQuery('SELECT COUNT(*) as c FROM books')).first['c'] as int? ?? 0;
      if (mounted) {
        setState(() {
          _localStudentsCount = stCount;
          _localStaffCount = sfCount;
          _localDepartmentsCount = dpCount;
          _localClassesCount = clCount;
          _localCoursesCount = crCount;
          _localBooksCount = bkCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleModeChange(AppStorageMode newMode) async {
    if (newMode == StorageModeService.currentMode) return;

    if (newMode == AppStorageMode.onlineCloud) {
      // Prompt user to sync offline data to cloud
      final shouldUpload = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.cloud_upload_rounded, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              Text('Switch to Online Cloud Sync', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'Would you like to upload all your current offline records (Students: $_localStudentsCount, Staff: $_localStaffCount) to Google Firebase Cloud now?\n\nکیا آپ موجودہ آف لائن ڈیٹا فائر بیس کلاؤڈ پر اپلوڈ کرنا چاہتے ہیں؟',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Switch Only (بغیر اپلوڈ)'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Upload & Switch (اپلوڈ کریں)', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      await StorageModeService.setMode(AppStorageMode.onlineCloud);
      FirebaseService.startLiveCloudSync();

      if (shouldUpload == true) {
        await _handlePushToCloud();
      } else {
        if (mounted) {
          _showToast('Switched to Online Cloud Sync mode');
        }
      }
    } else {
      // Switching to Offline Only
      await StorageModeService.setMode(AppStorageMode.offlineOnly);
      FirebaseService.stopLiveCloudSync();
      if (mounted) {
        _showToast('Switched to Offline Only mode (صرف لوکل آف لائن)');
      }
    }

    setState(() {});
  }

  Future<void> _handleSyncNow() async {
    setState(() {
      _isProcessing = true;
      _processStatus = 'Syncing with Google Firebase Cloud...';
    });

    try {
      final res = await FirebaseService.performFullTwoWaySync();
      await _loadLocalStats();
      if (mounted) {
        if (res.success) {
          final msg = (res.deleted > 0 || res.uploaded > 0 || res.downloaded > 0)
              ? 'Sync mukammal ho gaya! Upload: ${res.uploaded}, Cloud se delete: ${res.deleted}'
              : 'Sync mukammal! Local aur Online data pehle se update he.';
          _showToast(msg);
        } else {
          _showToast('Sync error: ${res.error ?? "Failed"}', isError: true);
        }
      }
    } catch (e) {
      if (mounted) _showToast('Sync error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processStatus = '';
        });
      }
    }
  }

  Future<void> _handlePushToCloud() async {
    setState(() {
      _isProcessing = true;
      _processStatus = 'Uploading local records to Google Firebase Cloud...';
    });

    try {
      final counts = await FirebaseService.pushAllLocalDataToCloud();
      await _loadLocalStats();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 10),
                Text('Upload Successful'),
              ],
            ),
            content: Text(
              'Local data Google Firebase par kamyabi se upload ho gaya he:\n\n'
              '• Students: ${counts['students'] ?? 0}\n'
              '• Staff: ${counts['staff'] ?? 0}\n'
              '• Departments: ${counts['departments'] ?? 0}\n'
              '• Classes: ${counts['classes'] ?? 0}\n'
              '• Courses / Divisions: ${counts['courses'] ?? 0} (Mappings: ${counts['class_courses'] ?? 0})\n'
              '• Books: ${counts['books'] ?? 0} (Mappings: ${counts['course_books'] ?? 0})\n'
              '• Settings: ${counts['settings'] ?? 0}\n\n'
              '• Deleted from Cloud: ${counts['pruned'] ?? 0} records',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) _showToast('Upload error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processStatus = '';
        });
      }
    }
  }

  Future<void> _handlePullFromCloud() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cloud_download_rounded, color: AppTheme.accentColor),
            SizedBox(width: 10),
            Text('Download from Cloud'),
          ],
        ),
        content: const Text(
          'This will pull all records from Google Firebase Firestore into your local database.\n\nکیا آپ کلاؤڈ سے تمام ڈیٹا لوکل میں ڈاؤن لوڈ کرنا چاہتے ہیں؟',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
            child: const Text('Download (ڈاؤن لوڈ کریں)', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _processStatus = 'Downloading all records from Google Firebase...';
    });

    try {
      final counts = await FirebaseService.pullAllDataFromCloud();
      await _loadLocalStats();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 10),
                Text('Download Complete'),
              ],
            ),
            content: Text(
              'Successfully downloaded from Google Firebase:\n\n'
              '• Students: ${counts['students'] ?? _localStudentsCount}\n'
              '• Staff: ${counts['staff'] ?? _localStaffCount}\n'
              '• Departments: ${counts['departments'] ?? _localDepartmentsCount}\n'
              '• Classes: ${counts['classes'] ?? _localClassesCount}\n'
              '• Courses / Divisions: ${counts['courses'] ?? _localCoursesCount} (Mappings: ${counts['class_courses'] ?? 0})\n'
              '• Books: ${counts['books'] ?? _localBooksCount} (Mappings: ${counts['course_books'] ?? 0})',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) _showToast('Download error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processStatus = '';
        });
      }
    }
  }

  Future<void> _handleResetToDefaultFirebase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset to Default Firebase?'),
        content: const Text(
          'Do you want to disconnect your custom Firebase account and return to the default built-in cloud project?\n\nکیا آپ ڈیفالٹ فائر بیس پروجیکٹ پر واپس جانا چاہتے ہیں؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset to Default', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseService.resetToDefaultCredentials();
    setState(() {});
    _showToast('Restored default Firebase project (ڈیفالٹ پروجیکٹ فعال ہو گیا)');
  }

  void _showFirebaseConfigDialog() {
    final projController = TextEditingController(
      text: FirebaseService.isCustomAccount ? FirebaseService.projectId : '',
    );
    final keyController = TextEditingController(
      text: FirebaseService.isCustomAccount ? FirebaseService.apiKey : '',
    );
    bool obscureKey = true;
    bool isTesting = false;
    String? testResultMsg;
    bool? testSuccess;
    bool showInstructions = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.cloud_sync_rounded, color: AppTheme.primaryColor),
                const SizedBox(width: 10),
                Text(
                  'Connect Your Firebase Account',
                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter your Google Firebase Project ID and Web API Key to store madarsa data in your personal cloud.',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                    const SizedBox(height: 18),

                    // Project ID Field
                    TextField(
                      controller: projController,
                      decoration: InputDecoration(
                        labelText: 'Firebase Project ID (پروجیکٹ آئی ڈی)',
                        hintText: 'e.g. madarsa-alnoor-cloud',
                        prefixIcon: const Icon(Icons.folder_shared_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Web API Key Field
                    TextField(
                      controller: keyController,
                      obscureText: obscureKey,
                      decoration: InputDecoration(
                        labelText: 'Web API Key (اے پی آئی کی)',
                        hintText: 'AIzaSy...',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(obscureKey ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setDialogState(() => obscureKey = !obscureKey),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Test Connection Button & Status
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isTesting = true;
                                    testResultMsg = null;
                                    testSuccess = null;
                                  });
                                  final res = await FirebaseService.testConnection(
                                    projController.text,
                                    keyController.text,
                                  );
                                  setDialogState(() {
                                    isTesting = false;
                                    testSuccess = res.$1;
                                    testResultMsg = res.$2;
                                  });
                                },
                          icon: isTesting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.network_check_rounded, size: 18),
                          label: Text(isTesting ? 'Testing...' : 'Test Connection (چیک کریں)'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),

                    if (testResultMsg != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (testSuccess == true ? Colors.green : Colors.red).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (testSuccess == true ? Colors.green : Colors.red).withAlpha(80),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              testSuccess == true ? Icons.check_circle_rounded : Icons.error_rounded,
                              color: testSuccess == true ? Colors.green : Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                testResultMsg!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: testSuccess == true ? Colors.green.shade800 : Colors.red.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    // How to get keys guide toggle
                    InkWell(
                      onTap: () => setDialogState(() => showInstructions = !showInstructions),
                      child: Row(
                        children: [
                          Icon(
                            showInstructions ? Icons.expand_less_rounded : Icons.help_outline_rounded,
                            size: 16,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'How to get these from Firebase Console (رہنمائی)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (showInstructions) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '1. Go to console.firebase.google.com and sign in with your Google account.\n'
                          '2. Click "Add project" and name it (e.g. my-madarsa-cloud).\n'
                          '3. In sidebar, go to Build -> Firestore Database and click "Create database" (choose Test mode).\n'
                          '4. Click the gear icon ⚙️ (Project settings) at top left.\n'
                          '5. Copy the Project ID and Web API Key and paste them here.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final p = projController.text.trim();
                  final k = keyController.text.trim();
                  if (p.isEmpty || k.isEmpty) {
                    setDialogState(() {
                      testSuccess = false;
                      testResultMsg = 'Please enter both Project ID and API Key.';
                    });
                    return;
                  }
                  await FirebaseService.saveCustomCredentials(p, k);
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() {});
                  _showToast('Custom Firebase account saved and connected!');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save & Connect (محفوظ کریں)', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = StorageModeService.isOnlineSyncEnabled;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF161625) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Storage & Cloud Sync (ڈیٹا اسٹوریج موڈ)',
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        children: [
              // Top Banner
              _buildStatusCard(isDark, isOnline),
              const SizedBox(height: 24),

              // Mode Selection Section
              Text(
                'Choose Storage Location (اسٹوریج کا انتخاب کریں)',
                style: AppTheme.getFontStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              _buildModeCard(
                isDark: isDark,
                mode: AppStorageMode.onlineCloud,
                isSelected: isOnline,
                title: 'Online Cloud Sync (گوگل کلاؤڈ سنک - فائر بیس)',
                subtitle: 'Data is stored locally for maximum speed and synced automatically to Google Firebase Firestore. Perfect for multi-device access and real-time cloud backup.',
                icon: Icons.cloud_sync_rounded,
                activeColor: Colors.blueAccent,
                tag: 'RECOMMENDED',
              ),
              const SizedBox(height: 12),

              _buildModeCard(
                isDark: isDark,
                mode: AppStorageMode.offlineOnly,
                isSelected: !isOnline,
                title: 'Offline Only (صرف لوکل آف لائن)',
                subtitle: 'All data is stored strictly on this computer inside local SQLite database. 100% private, no internet required, zero cloud uploads.',
                icon: Icons.offline_pin_rounded,
                activeColor: Colors.teal,
                tag: '100% PRIVATE & OFFLINE',
              ),
              const SizedBox(height: 20),

              // Firebase Account Card
              _buildFirebaseAccountCard(isDark),
              const SizedBox(height: 24),

              // Auto Cloud Sync Card
              _buildAutoSyncCard(isDark, isOnline),
              const SizedBox(height: 28),

              // Manual Cloud Controls
              Text(
                'Manual Cloud Actions (ڈیٹا سنک اور ٹرانسفر)',
                style: AppTheme.getFontStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),

              if (_isProcessing)
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryColor.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _processStatus,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              _buildActionTile(
                isDark: isDark,
                icon: Icons.sync_rounded,
                title: 'Sync Now (ابھی سنک کریں)',
                subtitle: 'Run immediate 2-way cloud sync with Google Firebase.',
                buttonText: 'Sync Now',
                buttonColor: AppTheme.primaryColor,
                onPressed: _isProcessing ? null : _handleSyncNow,
              ),
              const SizedBox(height: 10),

              _buildActionTile(
                isDark: isDark,
                icon: Icons.cloud_upload_rounded,
                title: 'Push to Cloud (تمام ڈیٹا کلاؤڈ پر بھیجیں)',
                subtitle: 'Upload all local students, staff, and classes to Firebase Firestore.',
                buttonText: 'Push All',
                buttonColor: Colors.deepPurple,
                onPressed: _isProcessing ? null : _handlePushToCloud,
              ),
              const SizedBox(height: 10),

              _buildActionTile(
                isDark: isDark,
                icon: Icons.cloud_download_rounded,
                title: 'Pull from Cloud (کلاؤڈ سے تمام ڈیٹا ڈاؤن لوڈ کریں)',
                subtitle: 'Download all cloud records into your local SQLite database.',
                buttonText: 'Pull All',
                buttonColor: AppTheme.accentColor,
                onPressed: _isProcessing ? null : _handlePullFromCloud,
              ),
            ],
          ),
        );
      }

  Widget _buildStatusCard(bool isDark, bool isOnline) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline
              ? [const Color(0xFF1E3C72), const Color(0xFF2A5298)]
              : [const Color(0xFF2C3E50), const Color(0xFF4CA1AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOnline ? Icons.cloud_done_rounded : Icons.offline_pin_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isOnline ? 'Active Mode: Online Cloud Sync' : 'Active Mode: Offline Only (لوکل)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.greenAccent.withAlpha(50) : Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white38),
                ),
                child: Text(
                  isOnline ? '● LIVE SYNC' : 'OFFLINE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isOnline
                ? 'Your app stores data on this device for speed and automatically syncs with Google Firebase Firestore.'
                : 'Your app stores data purely on this device. No network connections are made to cloud servers.',
            style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13),
          ),
          const Divider(color: Colors.white24, height: 24),
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 20,
            runSpacing: 12,
            children: [
              _buildStatItem('Students', '$_localStudentsCount'),
              _buildStatItem('Staff', '$_localStaffCount'),
              _buildStatItem('Classes', '$_localClassesCount'),
              _buildStatItem('Departments', '$_localDepartmentsCount'),
              _buildStatItem('Courses', '$_localCoursesCount'),
              _buildStatItem('Books', '$_localBooksCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required bool isDark,
    required AppStorageMode mode,
    required bool isSelected,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    String? tag,
  }) {
    return InkWell(
      onTap: () => _handleModeChange(mode),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222235) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: activeColor.withAlpha(30),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isSelected ? activeColor : Colors.grey).withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? activeColor : Colors.grey, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTheme.getFontStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (tag != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: activeColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: activeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Radio<AppStorageMode>(
              value: mode,
              groupValue: StorageModeService.currentMode,
              activeColor: activeColor,
              onChanged: (val) {
                if (val != null) _handleModeChange(val);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required Color buttonColor,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222235) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: buttonColor.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: buttonColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildFirebaseAccountCard(bool isDark) {
    final isCustom = FirebaseService.isCustomAccount;
    final currentProj = FirebaseService.projectId;
    final currentKey = FirebaseService.apiKey;
    final maskedKey = currentKey.length > 10
        ? '${currentKey.substring(0, 6)}...${currentKey.substring(currentKey.length - 4)}'
        : '••••••••';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222235) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCustom ? Colors.green.withAlpha(140) : (isDark ? Colors.white12 : Colors.black12),
          width: isCustom ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isCustom ? Colors.green : Colors.orange).withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCustom ? Icons.verified_user_rounded : Icons.cloud_circle_rounded,
                  color: isCustom ? Colors.green : Colors.orange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Cloud Project (فائر بیس پروجیکٹ)',
                          style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isCustom ? Colors.green : Colors.blue).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isCustom ? 'CUSTOM / ذاتی' : 'DEFAULT / ڈیفالٹ',
                            style: TextStyle(
                              color: isCustom ? Colors.green : Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isCustom
                          ? 'Connected to your personal Google Firebase cloud account.'
                          : 'Using built-in cloud server. You can connect your own Firebase project anytime.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project ID: $currentProj',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'API Key: $maskedKey',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showFirebaseConfigDialog,
                icon: const Icon(Icons.settings_rounded, size: 16),
                label: Text(isCustom ? 'Change Account' : 'Connect Own Account'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (isCustom) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Reset to Default Cloud (ڈیفالٹ پر واپس جائیں)',
                  onPressed: _handleResetToDefaultFirebase,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.orange),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleToggleAutoSync(bool val) async {
    await FirebaseService.setAutoSyncEnabled(val);
    if (mounted) {
      setState(() {
        _autoSyncEnabled = val;
      });
      _showToast(val
          ? 'Auto Sync ON: Data har $_autoSyncIntervalSeconds second me sync hoga'
          : 'Auto Sync OFF: Khudkar sync band kar diya gaya he');
    }
  }

  Future<void> _handleSetInterval(int seconds) async {
    if (seconds < 3) seconds = 3;
    await FirebaseService.setAutoSyncInterval(seconds);
    if (mounted) {
      setState(() {
        _autoSyncIntervalSeconds = seconds;
        _intervalCtrl.text = seconds.toString();
      });
      _showToast('Auto Sync interval $seconds second par set kar diya gaya');
    }
  }

  String _formatLastSyncTime() {
    final lastTime = FirebaseService.lastAutoSyncTime;
    if (lastTime == null) return 'Abhi tak sync nahi hua';
    final diff = DateTime.now().difference(lastTime);
    if (diff.inSeconds < 5) return 'Just now (abhi abhi)';
    if (diff.inSeconds < 60) return '${diff.inSeconds} second pehle';
    final mins = diff.inMinutes;
    return '$mins minute pehle';
  }

  Widget _buildAutoSyncCard(bool isDark, bool isOnline) {
    final presets = [5, 10, 15, 30, 60, 120];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2235) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _autoSyncEnabled && isOnline
              ? AppTheme.primaryColor.withAlpha(140)
              : (isDark ? Colors.white12 : Colors.black12),
          width: _autoSyncEnabled && isOnline ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (_autoSyncEnabled && isOnline
                          ? AppTheme.primaryColor
                          : Colors.grey)
                      .withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.autorenew_rounded,
                  color: _autoSyncEnabled && isOnline
                      ? AppTheme.primaryColor
                      : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Auto Cloud Sync (خودکار کلاؤڈ سنک)',
                          style: AppTheme.getFontStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_autoSyncEnabled && isOnline)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withAlpha(100)),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'App ka data khudkar Google Firebase par save hota rahega, bar bar "Sync Now" dabane ki zaroorat nahi.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoSyncEnabled && isOnline,
                activeColor: AppTheme.primaryColor,
                onChanged: isOnline ? (val) => _handleToggleAutoSync(val) : null,
              ),
            ],
          ),

          if (!isOnline) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(60)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Auto sync ke liye upar "Online Cloud Sync" mode select karein.',
                      style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_autoSyncEnabled) ...[
            const Divider(height: 28),

            // Interval Configuration
            Text(
              'Set Auto Sync Interval (کتنے سیکنڈ بعد خودکار سنک ہو):',
              style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            // Input field + Set button
            Row(
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _intervalCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Seconds (سیکنڈ)',
                      hintText: 'e.g. 15',
                      suffixText: 'sec',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (val) {
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null) _handleSetInterval(parsed);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    final parsed = int.tryParse(_intervalCtrl.text.trim());
                    if (parsed != null) {
                      _handleSetInterval(parsed);
                    } else {
                      _showToast('Valid number of seconds darj karein', isError: true);
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Set Interval'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Preset Chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: presets.map((s) {
                final isSelected = _autoSyncIntervalSeconds == s;
                final label = s >= 60 ? '${s ~/ 60}m (${s}s)' : '${s}s';
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryColor,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (_) => _handleSetInterval(s),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Live Pulse / Status Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (isDark ? Colors.black26 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Live Auto-Sync: Har $_autoSyncIntervalSeconds second me background me sync ho raha he.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    'Last sync: ${_formatLastSyncTime()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
