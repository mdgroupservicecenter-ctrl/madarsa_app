import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madarsa_app/core/theme/app_theme.dart';
import 'package:madarsa_app/core/localization/app_localizations.dart';
import 'backup_restore_screen.dart';
import 'storage_sync_settings_screen.dart';
import '../../../../core/services/storage_mode_service.dart';


import 'website_settings_screen.dart';


import 'gallery_management_screen.dart';

import 'madarsa_timings_screen.dart';
import 'academic_session_settings_screen.dart';
import 'salat_timings_settings_screen.dart';
import '../widgets/watch_weather_settings_dialog.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/hijri_cubit.dart';
import '../../../../core/services/pincode_settings.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import '../../../../core/services/app_update_service.dart';
import '../widgets/app_update_dialog.dart';
import '../../../../core/branding/app_branding.dart';
import '../../../../core/branding/app_branding_cubit.dart';
import '../../../../shared/widgets/app_logo_widget.dart';
import '../widgets/app_branding_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isCheckingUpdate = false;
  bool _autoCheckUpdates = true;

  @override
  void initState() {
    super.initState();
    _loadAutoCheckPref();
  }

  Future<void> _loadAutoCheckPref() async {
    final enabled = await AppUpdateService.isAutoCheckEnabled();
    if (mounted) {
      setState(() => _autoCheckUpdates = enabled);
    }
  }

  Future<void> _handleCheckUpdates(BuildContext context) async {
    setState(() => _isCheckingUpdate = true);
    try {
      final info = await AppUpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      if (info != null && info.hasUpdate) {
        AppUpdateDialog.show(context, info);
      } else if (info != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your app is up to date (v${AppUpdateService.appVersion})! آپ کے پاس سب سے نیا ورژن ہے',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Could not connect to update cloud. Check internet connection. اپڈیٹ سرور سے رابطہ نہیں ہو سکا',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.amber.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update check failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }



  bool _ensureFeatureAccess(BuildContext context, String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSubscriptionSection(context, isDark),
            const SizedBox(height: 24),
            _buildBrandingSection(context, isDark),
            const SizedBox(height: 32),
            _buildSection(
              context,
              title: context.tr('general_settings'),
              children: [
                _buildSettingTile(
                  context,
                  icon: Icons.branding_watermark_rounded,
                  title: 'App Name & Logo Branding (ایپ کا نام اور لوگو)',
                  subtitle: 'Change institution name, Urdu title, tagline and official logo',
                  onTap: () => AppBrandingDialog.show(context),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.language_rounded,
                  title: context.tr('language'),
                  subtitle: context.tr('change_lang_subtitle'),
                  onTap: () {
                    // Language selection logic is already in TopBar, 
                    // but we can add more details here if needed
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.palette_rounded,
                  title: context.tr('theme_mode'),
                  subtitle: context.tr('switch_theme_subtitle'),
                  onTap: () {
                    // Theme toggle is in TopBar
                  },
                ),
                _buildHijriAdjustmentTile(context),
                _buildSettingTile(
                  context,
                  icon: Icons.key_rounded,
                  title: 'Pincode API Key',
                  subtitle: 'Configure data.gov.in API key for Pincode lookup',
                  onTap: () {
                    if (!_ensureFeatureAccess(context, 'settings_profile', 'Pincode API Key Setup')) return;
                    _showPincodeApiDialog(context);
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.schedule_rounded,
                  title: context.tr('madarsa_timings_periods'),
                  subtitle: context.tr('set_timings_periods_desc'),
                  onTap: () {
                    if (!_ensureFeatureAccess(context, 'classes_timetable', 'Madarsa Timings & Periods')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MadarsaTimingsScreen()),
                    );
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.date_range_rounded,
                  title: 'Academic Session, Dates & Vacations (تعلیمی سال، تاریخ اور تعطیلات)',
                  subtitle: 'Configure session start/end dates, vacations (Ramzan, Eid), and auto-promotion',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AcademicSessionSettingsScreen()),
                    );
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.access_time_filled_rounded,
                  title: 'Clock, Theme & Weather (گھڑی، تھیم اور موسم)',
                  subtitle: 'Switch Analog/Digital, choose from 5 luxury clock themes & live weather city',
                  onTap: () => WatchWeatherSettingsDialog.show(context),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.mosque_rounded,
                  title: 'Salat & Jamat Timings (نماز اور جماعت کے اوقات)',
                  subtitle: 'Configure daily Azan and Jamat times, Hanafi/Shafi\'i calculations',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SalatTimingsSettingsScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSection(
              context,
              title: context.tr('data_security'),
              children: [
                _buildSettingTile(
                  context,
                  icon: Icons.cloud_sync_rounded,
                  title: 'Storage & Cloud Sync (ڈیٹا اسٹوریج موڈ)',
                  subtitle: StorageModeService.isOnlineSyncEnabled
                      ? 'Online Cloud Sync (Google Firebase)'
                      : 'Offline Only (Local SQLite Database)',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StorageSyncSettingsScreen()),
                    ).then((_) => setState(() {}));
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.backup_rounded,
                  title: context.tr('backup_restore'),
                  subtitle: context.tr('backup_restore_subtitle'),
                  onTap: () {
                    if (!_ensureFeatureAccess(context, 'settings_backup', 'Database Backup & Restore')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
                    );
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.security_rounded,
                  title: context.tr('security_logs'),
                  subtitle: context.tr('security_logs_subtitle'),
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSection(
              context,
              title: context.tr('website_controls'),
              children: [
                _buildSettingTile(
                  context,
                  icon: Icons.web_rounded,
                  title: context.tr('website_content'),
                  subtitle: context.tr('website_content_subtitle'),
                  onTap: () {
                    if (!_ensureFeatureAccess(context, 'settings_profile', 'Website Content')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WebsiteSettingsScreen()),
                    );
                  },
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.photo_library_rounded,
                  title: context.tr('photo_gallery'),
                  subtitle: context.tr('photo_gallery_subtitle'),
                  onTap: () {
                    if (!_ensureFeatureAccess(context, 'settings_profile', 'Photo Gallery')) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GalleryManagementScreen()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSection(
              context,
              title: 'App Updates & Version (ایپ اپڈیٹس اور ورژن)',
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.system_update_rounded,
                          color: Color(0xFF0F766E),
                          size: 24,
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
                                  'Madarsa Management System',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F766E).withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF0F766E)),
                                  ),
                                  child: Text(
                                    'v${AppUpdateService.appVersion}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F766E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Desktop Edition • Build ${AppUpdateService.appBuildNumber}',
                              style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isCheckingUpdate ? null : () => _handleCheckUpdates(context),
                        icon: _isCheckingUpdate
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(
                          _isCheckingUpdate ? 'Checking...' : 'Check for Updates (اپڈیٹ چیک کریں)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_mode_rounded, size: 20, color: Colors.grey.shade600),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto Check on Startup (شروع میں اپڈیٹ چیک کریں)',
                                style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Automatically notify when a newer update is released',
                                style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch(
                        value: _autoCheckUpdates,
                        activeThumbColor: const Color(0xFF0F766E),
                        onChanged: (val) async {
                          await AppUpdateService.setAutoCheckEnabled(val);
                          setState(() => _autoCheckUpdates = val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandingSection(BuildContext context, bool isDark) {
    return BlocBuilder<AppBrandingCubit, AppBranding>(
      builder: (context, branding) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E32) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 30 : 8),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              AppLogoWidget(
                size: 60,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withAlpha(40),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          branding.appNameUrdu,
                          style: AppTheme.getFontStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.primaryColor.withAlpha(80)),
                          ),
                          child: Text(
                            branding.hasCustomLogo ? 'Custom Logo' : 'Default Logo',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${branding.appNameEnglish} • ${branding.tagline}',
                      style: AppTheme.getFontStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Customize your institution name and upload official logo across the application',
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => AppBrandingDialog.show(context),
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text(
                  'Change Name & Logo (تبدیل کریں)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.getFontStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E32) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200,
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withAlpha(10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20),
      ),
      title: Text(
        title,
        style: AppTheme.getFontStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.getFontStyle(
          fontSize: 12,
          color: Colors.grey.shade500,
        ),
      ),
      trailing: onTap != null ? const Icon(Icons.chevron_right_rounded, size: 20) : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildHijriAdjustmentTile(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BlocBuilder<HijriCubit, HijriState>(
      builder: (context, HijriState state) {
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withAlpha(10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event_rounded, size: 20),
          ),
          title: Text(
            context.tr('hijri_adjustment'),
            style: AppTheme.getFontStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            '${context.tr('current_adjustment')}: ${state.adjustment > 0 ? '+' : ''}${state.adjustment} days',
            style: AppTheme.getFontStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
          trailing: SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: state.adjustment > -5 
                    ? () => context.read<HijriCubit>().updateAdjustment(state.adjustment - 1)
                    : null,
                ),
                Text(
                  '${state.adjustment}',
                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: state.adjustment < 5 
                    ? () => context.read<HijriCubit>().updateAdjustment(state.adjustment + 1)
                    : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPincodeApiDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<List<dynamic>>(
          future: Future.wait([
            PincodeSettings.getProvider(),
            PincodeSettings.getApiKey(),
            PincodeSettings.getCustomUrl(),
            PincodeSettings.getMapTaluka(),
            PincodeSettings.getMapDistrict(),
            PincodeSettings.getMapState(),
            PincodeSettings.getMapVillage(),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data ?? ['datagov', PincodeSettings.defaultApiKey, '', 'taluk', 'district', 'state', 'office'];
            
            String selectedProvider = data[0];
            final apiKeyCtrl = TextEditingController(text: data[1]);
            final customUrlCtrl = TextEditingController(text: data[2]);
            final talukaCtrl = TextEditingController(text: data[3]);
            final districtCtrl = TextEditingController(text: data[4]);
            final stateCtrl = TextEditingController(text: data[5]);
            final villageCtrl = TextEditingController(text: data[6]);

            return StatefulBuilder(
              builder: (context, setDialogState) {
                return Dialog(
                  backgroundColor: isDark ? const Color(0xFF1E1E32) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: SingleChildScrollView(
                    child: Container(
                      width: min(520.0, MediaQuery.of(context).size.width - 32),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.key_rounded, color: AppTheme.primaryColor),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'Pincode API Settings',
                                style: AppTheme.getFontStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // Provider Selector Dropdown
                          DropdownButtonFormField<String>(
                            initialValue: selectedProvider,
                            style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              labelText: 'API Provider',
                              labelStyle: AppTheme.getFontStyle(fontSize: 13),
                              prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            dropdownColor: isDark ? const Color(0xFF1E1E32) : Colors.white,
                            items: const [
                              DropdownMenuItem(value: 'datagov', child: Text('data.gov.in (Official Gov API)')),
                              DropdownMenuItem(value: 'postalpincode', child: Text('postalpincode.in (Free Public API)')),
                              DropdownMenuItem(value: 'custom', child: Text('Custom API / Any Other Website')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  selectedProvider = val;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // If data.gov.in or Custom is selected, show API Key field
                          if (selectedProvider == 'datagov' || selectedProvider == 'custom') ...[
                            TextFormField(
                              controller: apiKeyCtrl,
                              style: AppTheme.getFontStyle(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'API Key / Token',
                                labelStyle: AppTheme.getFontStyle(fontSize: 13),
                                prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.paste_rounded, size: 20),
                                  onPressed: () async {
                                    final clip = await Clipboard.getData(Clipboard.kTextPlain);
                                    if (clip?.text != null) {
                                      apiKeyCtrl.text = clip!.text!.trim();
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // If Custom API is selected, show custom URL pattern & mapping fields
                          if (selectedProvider == 'custom') ...[
                            TextFormField(
                              controller: customUrlCtrl,
                              style: AppTheme.getFontStyle(fontSize: 14),
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Custom API URL Pattern',
                                labelStyle: AppTheme.getFontStyle(fontSize: 13),
                                helperText: 'Use {pincode} and {apiKey} as placeholders.',
                                helperStyle: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                                prefixIcon: const Icon(Icons.link_rounded, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            
                            // JSON Key Mapping Sub-section
                            Row(
                              children: [
                                const Icon(Icons.settings_ethernet_rounded, size: 18, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  'JSON Key Mapping Config',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: talukaCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Taluka Key Name',
                                      labelStyle: AppTheme.getFontStyle(fontSize: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: districtCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'District Key Name',
                                      labelStyle: AppTheme.getFontStyle(fontSize: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: stateCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'State Key Name',
                                      labelStyle: AppTheme.getFontStyle(fontSize: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: villageCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Village List Key Name',
                                      labelStyle: AppTheme.getFontStyle(fontSize: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ] else if (selectedProvider == 'postalpincode') ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'postalpincode.in is a free, public API. It does not require any API Key or configuration.',
                                      style: AppTheme.getFontStyle(fontSize: 12, color: isDark ? Colors.blue.shade200 : Colors.blue.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Using official Government OGD Pincode Directory dataset. It provides verified official data.',
                                      style: AppTheme.getFontStyle(fontSize: 12, color: isDark ? Colors.green.shade200 : Colors.green.shade800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setDialogState(() {
                                    selectedProvider = 'datagov';
                                    apiKeyCtrl.text = PincodeSettings.defaultApiKey;
                                    customUrlCtrl.text = '';
                                    talukaCtrl.text = 'taluk';
                                    districtCtrl.text = 'district';
                                    stateCtrl.text = 'state';
                                    villageCtrl.text = 'office';
                                  });
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(
                                  'Reset Default',
                                  style: AppTheme.getFontStyle(fontSize: 12),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                              ),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      'Cancel',
                                      style: AppTheme.getFontStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () async {
                                      await PincodeSettings.setProvider(selectedProvider);
                                      await PincodeSettings.setApiKey(apiKeyCtrl.text.trim());
                                      await PincodeSettings.setCustomUrl(customUrlCtrl.text.trim());
                                      await PincodeSettings.setMapTaluka(talukaCtrl.text.trim());
                                      await PincodeSettings.setMapDistrict(districtCtrl.text.trim());
                                      await PincodeSettings.setMapState(stateCtrl.text.trim());
                                      await PincodeSettings.setMapVillage(villageCtrl.text.trim());
                                      
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Pincode API Settings saved successfully!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    child: Text(
                                      'Save Settings',
                                      style: AppTheme.getFontStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSubscriptionSection(BuildContext context, bool isDark) {
    return BlocBuilder<LicenseCubit, LicenseState>(
      builder: (context, state) {
        final license = state is LicenseLoaded ? state.license : AppLicense.defaultTrial();
        final tier = license.tier;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tier.color.withAlpha(isDark ? 45 : 25),
                tier.color.withAlpha(isDark ? 20 : 10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tier.color.withAlpha(90), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tier.color,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(tier.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tier.displayName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: tier.color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: license.isExpired ? Colors.red : Colors.green,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                license.isExpired ? 'EXPIRED' : (license.isLifetime ? 'PERMANENT' : 'ACTIVE'),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Registered to: ${license.institutionName}',
                          style: AppTheme.getFontStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => UpgradePlanDialog.show(context),
                    icon: const Icon(Icons.stars_rounded, size: 16),
                    label: const Text('Manage / Upgrade Plan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tier.color,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(
                    license.isLifetime ? Icons.all_inclusive_rounded : Icons.calendar_today_rounded,
                    size: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    license.isLifetime
                        ? 'Lifetime Access (No Renewal Required)'
                        : (license.isExpired
                            ? 'Subscription expired on ${license.expiresAt?.toIso8601String().split('T').first}'
                            : 'Valid until: ${license.expiresAt?.toIso8601String().split('T').first} (${license.daysRemaining} days remaining)'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
