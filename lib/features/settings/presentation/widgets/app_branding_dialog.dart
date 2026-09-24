import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/branding/app_branding.dart';
import '../../../../core/branding/app_branding_cubit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_logo_widget.dart';

class AppBrandingDialog extends StatefulWidget {
  const AppBrandingDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const AppBrandingDialog(),
    );
  }

  @override
  State<AppBrandingDialog> createState() => _AppBrandingDialogState();
}

class _AppBrandingDialogState extends State<AppBrandingDialog> {
  late TextEditingController _nameEnController;
  late TextEditingController _nameUrController;
  late TextEditingController _taglineController;

  String? _selectedNewLogoPath;
  bool _removeCurrentLogo = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final branding = context.read<AppBrandingCubit>().state;
    _nameEnController = TextEditingController(text: branding.appNameEnglish);
    _nameUrController = TextEditingController(text: branding.appNameUrdu);
    _taglineController = TextEditingController(text: branding.tagline);
  }

  @override
  void dispose() {
    _nameEnController.dispose();
    _nameUrController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  Future<void> _pickLogoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedNewLogoPath = result.files.single.path;
          _removeCurrentLogo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking logo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onRemoveLogo() {
    setState(() {
      _selectedNewLogoPath = null;
      _removeCurrentLogo = true;
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    final cubit = context.read<AppBrandingCubit>();

    if (_removeCurrentLogo) {
      await cubit.removeLogo();
    }

    final success = await cubit.updateBranding(
      nameEn: _nameEnController.text.trim(),
      nameUr: _nameUrController.text.trim(),
      tagline: _taglineController.text.trim(),
      newLogoSourcePath: _selectedNewLogoPath,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'App branding, Desktop & Taskbar updated! / ایپ نام، لوگو، ڈیسک ٹاپ اور ٹاسک بار کامیابی سے تبدیل ہو گیا',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _resetToDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults? / ڈیفالٹ پر بحال کریں؟'),
        content: const Text(
          'This will reset the App Name, Urdu Title, and Logo back to original Madarsa Management system defaults.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel / منسوخ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset / بحال کریں', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<AppBrandingCubit>().resetToDefaults();
      setState(() {
        _nameEnController.text = AppBranding.defaultAppNameEnglish;
        _nameUrController.text = AppBranding.defaultAppNameUrdu;
        _taglineController.text = AppBranding.defaultTagline;
        _selectedNewLogoPath = null;
        _removeCurrentLogo = false;
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reset to system defaults / تمام ترتیبات، ڈیسک ٹاپ اور ٹاسک بار ڈیفالٹ پر بحال کر دی گئیں'),
            backgroundColor: Colors.blueGrey,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final branding = context.watch<AppBrandingCubit>().state;

    // Determine current preview logo
    String? previewLogoPath = _selectedNewLogoPath;
    if (previewLogoPath == null && !_removeCurrentLogo) {
      previewLogoPath = branding.logoPath;
    }

    final hasCustomLogo = previewLogoPath != null &&
        previewLogoPath.isNotEmpty &&
        File(previewLogoPath).existsSync();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 630,
        constraints: const BoxConstraints(maxWidth: 630, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.branding_watermark_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App Identity & Branding',
                          style: AppTheme.getFontStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppTheme.primaryDark,
                          ),
                        ),
                        Text(
                          'Customize Madarsa name, tagline and official logo',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- LIVE PREVIEW BOX ---
                    Text(
                      'Live Preview (Sidebar Header)',
                      style: AppTheme.getFontStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor,
                            AppTheme.primaryColor.withAlpha(220),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withAlpha(60),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AppLogoWidget(
                            size: 46,
                            overrideLogoPath: previewLogoPath,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nameUrController.text.isNotEmpty
                                      ? _nameUrController.text
                                      : 'مدرسہ',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1.3,
                                  ),
                                ),
                                Text(
                                  _nameEnController.text.isNotEmpty
                                      ? _nameEnController.text
                                      : 'Management',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11.5,
                                    color: Colors.white.withAlpha(200),
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- LOGO MANAGEMENT SECTION ---
                    Text(
                      'Official App Logo',
                      style: AppTheme.getFontStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141422) : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          AppLogoWidget(
                            size: 64,
                            shape: BoxShape.circle,
                            overrideLogoPath: previewLogoPath,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: _pickLogoFile,
                                      icon: const Icon(Icons.upload_file_rounded, size: 16),
                                      label: const Text(
                                        'Upload Logo',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (hasCustomLogo) ...[
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red.shade400,
                                          side: BorderSide(color: Colors.red.shade400),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: _onRemoveLogo,
                                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                        label: const Text(
                                          'Remove',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Supported formats: PNG, JPG, WEBP. (Square image e.g. 512x512 with transparent background recommended)',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- NAME FIELDS ---
                    Text(
                      'App / Institution Name',
                      style: AppTheme.getFontStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // App Name (Urdu)
                    TextFormField(
                      controller: _nameUrController,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        labelText: 'App Name (Urdu)',
                        hintText: 'مثال: دار العلوم فیض القرآن',
                        prefixIcon: const Icon(Icons.translate_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),

                    // App Name (English)
                    TextFormField(
                      controller: _nameEnController,
                      decoration: InputDecoration(
                        labelText: 'App Name (English)',
                        hintText: 'e.g. Jamia Darul Uloom',
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),

                    // Tagline / Subtitle
                    TextFormField(
                      controller: _taglineController,
                      decoration: InputDecoration(
                        labelText: 'Tagline / Subtitle',
                        hintText: 'e.g. Management System / Islamic Academy',
                        prefixIcon: const Icon(Icons.short_text_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),

            // Footer actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161622) : Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _isSaving ? null : _resetToDefaults,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset Defaults', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 38),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: const Size(85, 38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400),
                    ),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      minimumSize: const Size(130, 38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isSaving ? null : _saveChanges,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Changes',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
