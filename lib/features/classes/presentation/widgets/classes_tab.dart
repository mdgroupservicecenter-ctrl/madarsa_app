import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/classes_repository.dart';
import '../../data/repositories/academic_repository.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';

class ClassesTab extends StatefulWidget {
  final ClassesRepository repository;
  final AcademicRepository academicRepository;

  const ClassesTab({
    super.key,
    required this.repository,
    required this.academicRepository,
  });

  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  bool _isLoading = true;
  List<dynamic> _classes = [];
  List<dynamic> _departments = [];
  String? _selectedDeptId;

  // Multi-unassign selection for assigned classes
  final Set<String> _selectedClassIdsToUnassign = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final classesData = await widget.repository.getAllClasses();
      final deptsData = await widget.academicRepository.getAllDepartments();

      setState(() {
        _classes = classesData;
        _departments = deptsData;
        _selectedClassIdsToUnassign.clear();
        _isLoading = false;

        // Auto-select first department if available and none selected
        if (_selectedDeptId == null && _departments.isNotEmpty) {
          _selectedDeptId = _departments.first['id'].toString();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load classes or departments: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildStudentStyleFormDialog({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
    required Widget footerButton,
  }) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scale = isMobile ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

    if (isMobile) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF141421) : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(16 * scale, 18 * scale, 16 * scale, 16 * scale),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
                  ),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(12 * scale),
                      child: Container(
                        padding: EdgeInsets.all(8 * scale),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 20 * scale,
                        ),
                      ),
                    ),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: AppTheme.getFontStyle(
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: AppTheme.getFontStyle(
                                fontSize: 12 * scale,
                                color: Colors.white.withAlpha(180),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 20 * scale),
                  child: child,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: footerButton,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Container(
        width: min(500.0, MediaQuery.of(context).size.width - 40),
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 100 : 40),
              blurRadius: 40,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: AppTheme.getFontStyle(fontSize: 12, color: Colors.white.withAlpha(180)),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                border: Border(
                  top: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200),
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('cancel')),
                  ),
                  const SizedBox(width: 12),
                  footerButton,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String?>> _buildDepartmentDropdownItems(double scale, bool isDark) {
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text('No Department / General', style: TextStyle(fontSize: 12.5 * scale, color: Colors.grey)),
      ),
    ];

    final mainDepts = _departments.where((d) => d['parent_id'] == null).toList();
    for (final main in mainDepts) {
      items.add(
        DropdownMenuItem<String?>(
          value: main['id'].toString(),
          child: Row(
            children: [
              Icon(Icons.business_center_rounded, size: 15 * scale, color: AppTheme.primaryColor),
              SizedBox(width: 6 * scale),
              Text(main['name'] ?? '', style: TextStyle(fontSize: 12.5 * scale, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );

      final subDepts = (main['sub_departments'] as List?) ??
          _departments.where((d) => d['parent_id']?.toString() == main['id']?.toString()).toList();
      for (final sub in subDepts) {
        items.add(
          DropdownMenuItem<String?>(
            value: sub['id'].toString(),
            child: Padding(
              padding: EdgeInsets.only(left: 12 * scale),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right_rounded, size: 14 * scale, color: const Color(0xFF1565C0)),
                  SizedBox(width: 4 * scale),
                  Text('Sub: ${sub['name']}', style: TextStyle(fontSize: 12 * scale, color: const Color(0xFF1565C0))),
                ],
              ),
            ),
          ),
        );
      }
    }

    final otherSubs = _departments.where((d) => d['parent_id'] != null && !mainDepts.any((m) => m['id'] == d['parent_id'])).toList();
    for (final sub in otherSubs) {
      items.add(
        DropdownMenuItem<String?>(
          value: sub['id'].toString(),
          child: Row(
            children: [
              Icon(Icons.subdirectory_arrow_right_rounded, size: 14 * scale, color: const Color(0xFF1565C0)),
              SizedBox(width: 4 * scale),
              Text('Sub: ${sub['name']}', style: TextStyle(fontSize: 12 * scale, color: const Color(0xFF1565C0))),
            ],
          ),
        ),
      );
    }

    return items;
  }

  // 1. Create Class Dialog
  void _showCreateClassDialog() {
    if (!_ensureFeatureAccess('classes_manage', 'Create & Manage Classes')) return;

    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final durationCtrl = TextEditingController();
    String? selectedDept = _selectedDeptId;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final width = MediaQuery.of(context).size.width;
        final scale = (width / 375.0).clamp(0.75, 1.0);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return _buildStudentStyleFormDialog(
              context: context,
              title: 'Create New Class',
              subtitle: 'Add a new class to department or sub-department',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    value: selectedDept,
                    dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale, color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'Department / Sub-Department',
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.business_center_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                    items: _buildDepartmentDropdownItems(scale, isDark),
                    onChanged: (val) {
                      setModalState(() => selectedDept = val);
                    },
                  ),
                  SizedBox(height: 12 * scale),
                  TextField(
                    controller: nameCtrl,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('class_name_eg'),
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.class_outlined, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 12 * scale),
                  TextField(
                    controller: durationCtrl,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('duration_eg'),
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.timer_outlined, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 12 * scale),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('description'),
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.description_outlined, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              footerButton: FilledButton.icon(
                icon: const Icon(Icons.check_circle_rounded),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D6B4E),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  Navigator.pop(context);
                  setState(() => _isLoading = true);

                  try {
                    await widget.repository.createClass({
                      'name': nameCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'duration': durationCtrl.text.trim(),
                      'department_id': selectedDept,
                    });
                    _loadData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error creating class: $e')),
                      );
                      setState(() => _isLoading = false);
                    }
                  }
                },
                label: Text(context.tr('create'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            );
          },
        );
      },
    );
  }

  // 2. Edit Class Dialog
  void _editClass(Map<String, dynamic> currentClass, {VoidCallback? onRefresh}) {
    final nameCtrl = TextEditingController(text: currentClass['name'] ?? '');
    final descCtrl = TextEditingController(text: currentClass['description'] ?? '');
    final durationCtrl = TextEditingController(text: currentClass['duration'] ?? '');
    String? selectedDept = currentClass['department_id']?.toString();

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final width = MediaQuery.of(context).size.width;
        final scale = (width / 375.0).clamp(0.75, 1.0);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return _buildStudentStyleFormDialog(
              context: context,
              title: 'Edit Class',
              subtitle: 'Update class information and details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    value: selectedDept,
                    dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale, color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'Department / Sub-Department',
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.business_center_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                    items: _buildDepartmentDropdownItems(scale, isDark),
                    onChanged: (val) {
                      setModalState(() => selectedDept = val);
                    },
                  ),
                  SizedBox(height: 12 * scale),
                  TextField(
                    controller: nameCtrl,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('class_name_eg'),
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.class_outlined, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 12 * scale),
                  TextField(
                    controller: durationCtrl,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('duration_eg'),
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.timer_outlined, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 12 * scale),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('description'),
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.description_outlined, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              footerButton: FilledButton.icon(
                icon: const Icon(Icons.save_rounded),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D6B4E),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  Navigator.pop(context);
                  setState(() => _isLoading = true);

                  try {
                    await widget.repository.updateClass(currentClass['id'].toString(), {
                      'name': nameCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'duration': durationCtrl.text.trim(),
                      'department_id': selectedDept,
                    });
                    await _loadData();
                    onRefresh?.call();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating class: $e')),
                      );
                      setState(() => _isLoading = false);
                    }
                  }
                },
                label: Text(context.tr('save'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showStyledConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    Color confirmColor = Colors.orange,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
        insetPadding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 24 * scale),
        titlePadding: EdgeInsets.fromLTRB(20 * scale, 20 * scale, 20 * scale, 10 * scale),
        contentPadding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 10 * scale),
        actionsPadding: EdgeInsets.fromLTRB(16 * scale, 10 * scale, 16 * scale, 16 * scale),
        title: Text(
          title,
          style: AppTheme.getFontStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold),
        ),
        content: Text(
          content,
          style: TextStyle(fontSize: 13 * scale, color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
            ),
            onPressed: () => Navigator.pop(c, false),
            child: Text(context.tr('cancel'), style: TextStyle(fontSize: 13 * scale, color: isDark ? Colors.white60 : Colors.grey.shade700)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 10 * scale),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              confirmText,
              style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Delete Class Dialog
  Future<void> _deleteClass(Map<String, dynamic> currentClass, {VoidCallback? onRefresh}) async {
    final confirm = await _showStyledConfirmDialog(
      context: context,
      title: 'Delete Class?',
      content: 'Are you sure you want to delete "${currentClass['name']}"? This may affect enrolled students.',
      confirmText: context.tr('delete'),
      confirmColor: Colors.red,
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await widget.repository.deleteClass(currentClass['id'].toString());
      await _loadData();
      onRefresh?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete class: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // 4. Manage Global Classes Dialog
  void _showManageClassesDialog() {
    if (!_ensureFeatureAccess('classes_manage', 'Create & Manage Classes')) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final width = MediaQuery.of(context).size.width;
          final scale = (width / 375.0).clamp(0.75, 1.0);
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return _buildStudentStyleFormDialog(
            context: context,
            title: 'Manage Global Classes',
            subtitle: 'View, edit or delete global classes',
            child: _classes.isEmpty
                ? Center(child: Padding(padding: EdgeInsets.all(20 * scale), child: Text('No classes found.', style: TextStyle(fontSize: 13 * scale))))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _classes.length,
                    itemBuilder: (context, index) {
                      final cls = _classes[index];
                      final deptName = cls['department_name'];
                      return Card(
                        margin: EdgeInsets.only(bottom: 8 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                        color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 2 * scale),
                          title: Text(
                            cls['name'] ?? '',
                            style: AppTheme.getFontStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13 * scale,
                            ),
                          ),
                          subtitle: Text(
                            deptName != null && deptName.toString().isNotEmpty ? 'Dept: $deptName' : 'No Dept',
                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_rounded, color: Colors.blue, size: 18 * scale),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _editClass(cls, onRefresh: () => setModalState(() {}));
                                },
                              ),
                              SizedBox(width: 12 * scale),
                              IconButton(
                                icon: Icon(Icons.delete_rounded, color: Colors.red, size: 18 * scale),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _deleteClass(cls, onRefresh: () => setModalState(() {}));
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            footerButton: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6B4E),
                padding: EdgeInsets.symmetric(vertical: 12 * scale),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('close'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale)),
            ),
          );
        },
      ),
    );
  }

  // 5. --- MULTIPLE ASSIGN CLASSES TO DEPARTMENT DIALOG ---
  void _assignMultipleClassesToSelectedDepartment() {
    if (_selectedDeptId == null) return;

    final assignedNamesInThisDept = _classes
        .where((c) => c['department_id']?.toString() == _selectedDeptId)
        .map((c) => (c['name'] ?? '').toString().trim().toLowerCase())
        .toSet();

    // Deduplicate available classes by name
    final Map<String, dynamic> uniqueAvailable = {};
    for (final c in _classes) {
      final nameNorm = (c['name'] ?? '').toString().trim().toLowerCase();
      if (nameNorm.isNotEmpty && !assignedNamesInThisDept.contains(nameNorm)) {
        if (!uniqueAvailable.containsKey(nameNorm)) {
          uniqueAvailable[nameNorm] = c;
        }
      }
    }
    final availableClasses = uniqueAvailable.values.toList();
    final Set<String> selectedClassIds = {};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final width = MediaQuery.of(context).size.width;
          final scale = (width / 375.0).clamp(0.75, 1.0);
          final allSelected = availableClasses.isNotEmpty && selectedClassIds.length == availableClasses.length;
          final deptObj = _departments.where((d) => d['id'].toString() == _selectedDeptId).firstOrNull;

          return _buildStudentStyleFormDialog(
            context: context,
            title: 'Assign Classes',
            subtitle: 'Select classes to assign to ${deptObj?['name'] ?? 'Department'}',
            child: availableClasses.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20 * scale),
                      child: Text(
                        'All available classes are already assigned to this department.',
                        style: TextStyle(fontSize: 12 * scale),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      CheckboxListTile(
                        dense: true,
                        activeColor: const Color(0xFF0D6B4E),
                        title: Text('Select All Classes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13 * scale)),
                        value: allSelected,
                        onChanged: (val) {
                          setModalState(() {
                            if (val == true) {
                              selectedClassIds.addAll(availableClasses.map((c) => c['id'].toString()));
                            } else {
                              selectedClassIds.clear();
                            }
                          });
                        },
                      ),
                      const Divider(height: 1),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: availableClasses.length,
                        itemBuilder: (context, index) {
                          final cls = availableClasses[index];
                          final cId = cls['id'].toString();
                          final isChecked = selectedClassIds.contains(cId);

                          return CheckboxListTile(
                            dense: true,
                            activeColor: const Color(0xFF0D6B4E),
                            title: Text(cls['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13 * scale)),
                            subtitle: cls['description'] != null && cls['description'].toString().isNotEmpty
                                ? Text(cls['description'], style: TextStyle(fontSize: 11 * scale))
                                : null,
                            value: isChecked,
                            onChanged: (val) {
                              setModalState(() {
                                if (val == true) {
                                  selectedClassIds.add(cId);
                                } else {
                                  selectedClassIds.remove(cId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ],
                  ),
            footerButton: FilledButton.icon(
              icon: Icon(Icons.check_circle_rounded, size: 18 * scale),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6B4E),
                padding: EdgeInsets.symmetric(vertical: 12 * scale),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
              ),
              onPressed: selectedClassIds.isEmpty || availableClasses.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(context);
                      setState(() => _isLoading = true);
                      try {
                        for (final cId in selectedClassIds) {
                          final cls = availableClasses.where((item) => item['id'].toString() == cId).firstOrNull;
                          if (cls == null) continue;
                          final deptId = cls['department_id']?.toString();
                          if (deptId == null || deptId.isEmpty || deptId == 'null') {
                            // Unassigned class: assign to this department directly
                            await widget.repository.updateClass(cId, {'department_id': _selectedDeptId});
                          } else {
                            // Already assigned to another department: create a copy for this department
                            await widget.repository.createClass({
                              'name': cls['name'],
                              'description': cls['description'],
                              'duration': cls['duration'],
                              'department_id': _selectedDeptId,
                            });
                          }
                        }
                        _loadData();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error assigning classes: $e')),
                          );
                          setState(() => _isLoading = false);
                        }
                      }
                    },
              label: Text(
                'Assign Selected (${selectedClassIds.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale),
              ),
            ),
          );
        },
      ),
    );
  }

  // 6. --- MULTIPLE UNASSIGN CLASSES ACTION ---
  Future<void> _unassignSelectedClasses() async {
    if (_selectedClassIdsToUnassign.isEmpty) return;

    final count = _selectedClassIdsToUnassign.length;
    final confirm = await _showStyledConfirmDialog(
      context: context,
      title: 'Unassign Selected Classes?',
      content: 'Remove $count selected class(es) from this department?',
      confirmText: 'Unassign ($count)',
      confirmColor: Colors.orange.shade800,
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      for (final cId in _selectedClassIdsToUnassign.toList()) {
        final cls = _classes.where((c) => c['id'].toString() == cId).firstOrNull;
        if (cls != null) {
          await widget.repository.updateClass(cId, {
            'name': cls['name'],
            'description': cls['description'],
            'duration': cls['duration'],
            'department_id': null,
          });
        }
      }
      _selectedClassIdsToUnassign.clear();
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unassign classes: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Unassign single class
  Future<void> _unassignClass(Map<String, dynamic> cls) async {
    final confirm = await _showStyledConfirmDialog(
      context: context,
      title: 'Unassign Class?',
      content: 'Remove "${cls['name']}" from this department?',
      confirmText: 'Unassign',
      confirmColor: Colors.orange.shade800,
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await widget.repository.updateClass(cls['id'].toString(), {
        'name': cls['name'],
        'description': cls['description'],
        'duration': cls['duration'],
        'department_id': null,
      });
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unassign class: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  List<Widget> _buildDepartmentTreeWidgets({
    required bool isMobile,
    required double scale,
    required bool isDark,
    VoidCallback? onItemTapped,
  }) {
    final widgets = <Widget>[];

    // "All Departments" item
    final isAllSelected = _selectedDeptId == null;
    if (isMobile) {
      widgets.add(
        Container(
          margin: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
          decoration: BoxDecoration(
            color: isAllSelected
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : (isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50),
            borderRadius: BorderRadius.circular(10 * scale),
            border: Border.all(
              color: isAllSelected
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: ListTile(
            dense: true,
            leading: Radio<String?>(
              value: null,
              groupValue: _selectedDeptId,
              activeColor: Theme.of(context).primaryColor,
              onChanged: (v) {
                setState(() {
                  _selectedDeptId = null;
                  _selectedClassIdsToUnassign.clear();
                });
                onItemTapped?.call();
              },
            ),
            title: Text(
              'All Departments',
              style: AppTheme.getFontStyle(
                fontSize: 13 * scale,
                fontWeight: isAllSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            trailing: Container(
              padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8 * scale),
              ),
              child: Text(
                '${_classes.length} classes',
                style: TextStyle(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            onTap: () {
              setState(() {
                _selectedDeptId = null;
                _selectedClassIdsToUnassign.clear();
              });
              onItemTapped?.call();
            },
          ),
        ),
      );
    } else {
      widgets.add(
        ListTile(
          title: Text(
            'All Departments',
            style: AppTheme.getFontStyle(
              fontSize: 14,
              fontWeight: isAllSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isAllSelected
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_classes.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isAllSelected ? Theme.of(context).primaryColor : Colors.grey,
              ),
            ),
          ),
          selected: isAllSelected,
          selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          selectedColor: Theme.of(context).primaryColor,
          onTap: () {
            setState(() {
              _selectedDeptId = null;
              _selectedClassIdsToUnassign.clear();
            });
            onItemTapped?.call();
          },
        ),
      );
    }

    final mainDepts = _departments.where((d) => d['parent_id'] == null).toList();

    for (final main in mainDepts) {
      final mId = main['id'].toString();
      final isSelected = _selectedDeptId == mId;
      final mCount = (main['class_count'] ?? 0) as int;
      final head = main['head_name'] as String?;
      final subDepts = (main['sub_departments'] as List?) ??
          _departments.where((d) => d['parent_id']?.toString() == mId).toList();

      if (isMobile) {
        widgets.add(
          Container(
            margin: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                  : (isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50),
              borderRadius: BorderRadius.circular(10 * scale),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: ListTile(
              dense: true,
              leading: Radio<String?>(
                value: mId,
                groupValue: _selectedDeptId,
                activeColor: Theme.of(context).primaryColor,
                onChanged: (v) {
                  setState(() {
                    _selectedDeptId = mId;
                    _selectedClassIdsToUnassign.clear();
                  });
                  onItemTapped?.call();
                },
              ),
              title: Text(
                main['name'] ?? '',
                style: AppTheme.getFontStyle(
                  fontSize: 13 * scale,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              subtitle: head != null && head.isNotEmpty
                  ? Text('Head: $head', style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade600))
                  : null,
              trailing: Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8 * scale),
                ),
                child: Text(
                  '$mCount classes',
                  style: TextStyle(
                    fontSize: 10 * scale,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              onTap: () {
                setState(() {
                  _selectedDeptId = mId;
                  _selectedClassIdsToUnassign.clear();
                });
                onItemTapped?.call();
              },
            ),
          ),
        );

        // Sub-departments in mobile
        for (final sub in subDepts) {
          final sId = sub['id'].toString();
          final isSubSelected = _selectedDeptId == sId;
          final sCount = (sub['class_count'] ?? 0) as int;

          widgets.add(
            Container(
              margin: EdgeInsets.fromLTRB(26 * scale, 2 * scale, 10 * scale, 3 * scale),
              decoration: BoxDecoration(
                color: isSubSelected
                    ? const Color(0xFF1565C0).withValues(alpha: 0.12)
                    : (isDark ? const Color(0xFF222234) : const Color(0xFFF0F4F8)),
                borderRadius: BorderRadius.circular(8 * scale),
                border: Border.all(
                  color: isSubSelected
                      ? const Color(0xFF1565C0).withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Radio<String?>(
                  value: sId,
                  groupValue: _selectedDeptId,
                  activeColor: const Color(0xFF1565C0),
                  onChanged: (v) {
                    setState(() {
                      _selectedDeptId = sId;
                      _selectedClassIdsToUnassign.clear();
                    });
                    onItemTapped?.call();
                  },
                ),
                title: Row(
                  children: [
                    Icon(Icons.subdirectory_arrow_right_rounded, size: 14 * scale, color: const Color(0xFF1565C0)),
                    SizedBox(width: 4 * scale),
                    Expanded(
                      child: Text(
                        sub['name'] ?? '',
                        style: AppTheme.getFontStyle(
                          fontSize: 12 * scale,
                          fontWeight: isSubSelected ? FontWeight.bold : FontWeight.w500,
                          color: const Color(0xFF1565C0),
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6 * scale),
                  ),
                  child: Text(
                    '$sCount',
                    style: TextStyle(
                      fontSize: 9.5 * scale,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1565C0),
                    ),
                  ),
                ),
                onTap: () {
                  setState(() {
                    _selectedDeptId = sId;
                    _selectedClassIdsToUnassign.clear();
                  });
                  onItemTapped?.call();
                },
              ),
            ),
          );
        }
      } else {
        // Desktop item
        widgets.add(
          ListTile(
            dense: true,
            title: Text(
              main['name'] ?? '',
              style: AppTheme.getFontStyle(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$mCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                ),
              ),
            ),
            selected: isSelected,
            selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            selectedColor: Theme.of(context).primaryColor,
            onTap: () {
              setState(() {
                _selectedDeptId = mId;
                _selectedClassIdsToUnassign.clear();
              });
              onItemTapped?.call();
            },
          ),
        );

        // Desktop sub-departments
        for (final sub in subDepts) {
          final sId = sub['id'].toString();
          final isSubSelected = _selectedDeptId == sId;
          final sCount = (sub['class_count'] ?? 0) as int;

          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: Color(0xFF1565C0)),
                horizontalTitleGap: 0,
                title: Text(
                  sub['name'] ?? '',
                  style: AppTheme.getFontStyle(
                    fontSize: 12.5,
                    fontWeight: isSubSelected ? FontWeight.bold : FontWeight.w500,
                    color: const Color(0xFF1565C0),
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$sCount',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
                selected: isSubSelected,
                selectedTileColor: const Color(0xFF1565C0).withValues(alpha: 0.1),
                selectedColor: const Color(0xFF1565C0),
                onTap: () {
                  setState(() {
                    _selectedDeptId = sId;
                    _selectedClassIdsToUnassign.clear();
                  });
                  onItemTapped?.call();
                },
              ),
            ),
          );
        }
      }
    }

    return widgets;
  }

  void _showRightSideFilterPanel(BuildContext context, double scale, bool isDark) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) {
        final width = MediaQuery.of(context).size.width;

        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: width * 0.85,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16 * scale),
                  bottomLeft: Radius.circular(16 * scale),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(-4, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Right Drawer Header
                    Padding(
                      padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 8 * scale, 10 * scale),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.tune_rounded, color: Theme.of(context).primaryColor, size: 20 * scale),
                              SizedBox(width: 8 * scale),
                              Text(
                                'Select Department',
                                style: AppTheme.getFontStyle(
                                  fontSize: 15 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20 * scale),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Department List with Radio Tile & Badges
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.symmetric(vertical: 8 * scale),
                        children: _buildDepartmentTreeWidgets(
                          isMobile: true,
                          scale: scale,
                          isDark: isDark,
                          onItemTapped: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _classes.isEmpty && _departments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final assignedClasses = _selectedDeptId == null
        ? _classes
        : _classes.where((c) {
            final dId = c['department_id']?.toString();
            if (dId == _selectedDeptId) return true;
            final selectedDept = _departments.where((d) => d['id'].toString() == _selectedDeptId).firstOrNull;
            if (selectedDept != null && selectedDept['sub_departments'] is List) {
              final subIds = (selectedDept['sub_departments'] as List).map((s) => s['id'].toString()).toSet();
              if (subIds.contains(dId)) return true;
            }
            return false;
          }).toList();

    final selectedDept = _departments.where(
      (d) => d['id'].toString() == _selectedDeptId,
    ).firstOrNull;

    final allAssignedSelected = assignedClasses.isNotEmpty &&
        _selectedClassIdsToUnassign.length == assignedClasses.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        // Left Panel (Desktop): Select Department Box
        final deptPanel = Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.all(12 * scale),
                child: Text(
                  'Select Department',
                  style: AppTheme.getFontStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _departments.isEmpty && !_isLoading
                    ? const Center(child: Text('No departments found'))
                    : ListView(
                        children: _buildDepartmentTreeWidgets(
                          isMobile: false,
                          scale: scale,
                          isDark: isDark,
                        ),
                      ),
              ),
            ],
          ),
        );

        // Mobile Top Filter Status Bar
        final mobileTopFilterBar = Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            borderRadius: BorderRadius.circular(10 * scale),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      selectedDept?['parent_id'] != null
                          ? Icons.subdirectory_arrow_right_rounded
                          : Icons.business_rounded,
                      size: 16 * scale,
                      color: selectedDept?['parent_id'] != null
                          ? const Color(0xFF1565C0)
                          : Theme.of(context).primaryColor,
                    ),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        _selectedDeptId == null
                            ? 'All Departments'
                            : (selectedDept?['parent_id'] != null
                                ? 'Sub-Dept: ${selectedDept?['name']}'
                                : (selectedDept?['name'] ?? 'Department')),
                        style: AppTheme.getFontStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12 * scale,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _showRightSideFilterPanel(context, scale, isDark),
                borderRadius: BorderRadius.circular(8 * scale),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(8 * scale),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_rounded, size: 14 * scale, color: Colors.white),
                      SizedBox(width: 4 * scale),
                      Text(
                        'Details & Filter',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        // Right Panel: Classes List
        final classesPanel = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCompact) ...[
              mobileTopFilterBar,
              SizedBox(height: 10 * scale),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedDeptId == null
                      ? 'Classes'
                      : 'Classes in ${selectedDept?['name'] ?? ''}',
                  style: AppTheme.getFontStyle(
                    fontSize: isCompact ? (14 * scale) : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8 * scale),
                if (isCompact)
                  Row(
                    children: [
                      Material(
                        color: const Color(0xFF0D6B4E),
                        borderRadius: BorderRadius.circular(10 * scale),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10 * scale),
                          onTap: _showCreateClassDialog,
                          child: Padding(
                            padding: EdgeInsets.all(8 * scale),
                            child: Icon(Icons.add_rounded, color: Colors.white, size: 20 * scale),
                          ),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Material(
                        color: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10 * scale),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10 * scale),
                          onTap: _showManageClassesDialog,
                          child: Padding(
                            padding: EdgeInsets.all(8 * scale),
                            child: Icon(Icons.settings_rounded, color: isDark ? Colors.white : Colors.black87, size: 20 * scale),
                          ),
                        ),
                      ),
                      if (_selectedDeptId != null) ...[
                        SizedBox(width: 8 * scale),
                        Material(
                          color: const Color(0xFF043927),
                          borderRadius: BorderRadius.circular(10 * scale),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10 * scale),
                            onTap: _assignMultipleClassesToSelectedDepartment,
                            child: Padding(
                              padding: EdgeInsets.all(8 * scale),
                              child: Icon(Icons.library_add_rounded, color: Colors.white, size: 20 * scale),
                            ),
                          ),
                        ),
                      ],
                      if (_selectedClassIdsToUnassign.isNotEmpty) ...[
                        SizedBox(width: 8 * scale),
                        Material(
                          color: Colors.orange.shade800,
                          borderRadius: BorderRadius.circular(10 * scale),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10 * scale),
                            onTap: _unassignSelectedClasses,
                            child: Padding(
                              padding: EdgeInsets.all(8 * scale),
                              child: Icon(Icons.link_off_rounded, color: Colors.white, size: 20 * scale),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _showCreateClassDialog,
                        icon: const Icon(Icons.add_rounded, size: 19),
                        label: const Text('Create Global Class'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0D6B4E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showManageClassesDialog,
                        icon: const Icon(Icons.settings_rounded, size: 19),
                        label: const Text('Manage Classes'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF0D6B4E),
                          side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFF0D6B4E).withValues(alpha: 0.5), width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                      if (_selectedDeptId != null)
                        FilledButton.icon(
                          onPressed: _assignMultipleClassesToSelectedDepartment,
                          icon: const Icon(Icons.library_add_rounded, size: 19),
                          label: const Text('Assign Classes (Multi)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF043927),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                      if (_selectedClassIdsToUnassign.isNotEmpty)
                        FilledButton.icon(
                          onPressed: _unassignSelectedClasses,
                          icon: const Icon(Icons.link_off_rounded, size: 19),
                          label: Text('Unassign (${_selectedClassIdsToUnassign.length})'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 8 * scale),

            // Select All Header Bar for assigned classes list
            if (_selectedDeptId != null && assignedClasses.isNotEmpty) ...[
              Row(
                children: [
                  Checkbox(
                    activeColor: AppTheme.primaryColor,
                    value: allAssignedSelected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedClassIdsToUnassign.addAll(
                            assignedClasses.map((c) => c['id'].toString()),
                          );
                        } else {
                          _selectedClassIdsToUnassign.clear();
                        }
                      });
                    },
                  ),
                  Text(
                    'Select All Assigned Classes (${assignedClasses.length})',
                    style: AppTheme.getFontStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: isCompact ? (11 * scale) : 13,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4 * scale),
            ],

            Expanded(
              child: assignedClasses.isEmpty
                  ? Center(
                      child: Text(
                        _selectedDeptId == null
                            ? 'No classes found.'
                            : 'No classes assigned to this department yet.',
                        style: AppTheme.getFontStyle(
                          color: Colors.grey,
                          fontSize: isCompact ? (12 * scale) : 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: assignedClasses.length,
                      itemBuilder: (context, index) {
                        final cls = assignedClasses[index];
                        final cId = cls['id'].toString();
                        final deptName = cls['department_name'] as String?;
                        final parentDeptName = cls['parent_department_name'] as String?;
                        final isSubDept = cls['department_parent_id'] != null || parentDeptName != null;
                        final isChecked = _selectedClassIdsToUnassign.contains(cId);

                        return Card(
                          margin: EdgeInsets.only(bottom: 10 * scale),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? (8 * scale) : 16,
                              vertical: isCompact ? (6 * scale) : 10,
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  activeColor: AppTheme.primaryColor,
                                  value: isChecked,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedClassIdsToUnassign.add(cId);
                                      } else {
                                        _selectedClassIdsToUnassign.remove(cId);
                                      }
                                    });
                                  },
                                ),
                                SizedBox(width: 4 * scale),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cls['name'] ?? '',
                                        style: AppTheme.getFontStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: isCompact ? (13 * scale) : 16,
                                        ),
                                      ),
                                      if (deptName != null && deptName.isNotEmpty) ...[
                                        SizedBox(height: 3 * scale),
                                        Wrap(
                                          spacing: 6 * scale,
                                          runSpacing: 4 * scale,
                                          children: [
                                            if (isSubDept && parentDeptName != null) ...[
                                              Container(
                                                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0D6B4E).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6 * scale),
                                                ),
                                                child: Text(
                                                  'Dept: $parentDeptName',
                                                  style: TextStyle(
                                                    color: const Color(0xFF0D6B4E),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 10 * scale,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1565C0).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6 * scale),
                                                ),
                                                child: Text(
                                                  'Sub-Dept: $deptName',
                                                  style: TextStyle(
                                                    color: const Color(0xFF1565C0),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 10 * scale,
                                                  ),
                                                ),
                                              ),
                                            ] else ...[
                                              Container(
                                                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0D6B4E).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6 * scale),
                                                ),
                                                child: Text(
                                                  'Dept: $deptName',
                                                  style: TextStyle(
                                                    color: const Color(0xFF0D6B4E),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 10 * scale,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                      if (cls['description'] != null &&
                                          cls['description'].toString().isNotEmpty) ...[
                                        SizedBox(height: 2 * scale),
                                        Text(
                                          cls['description'],
                                          style: TextStyle(fontSize: isCompact ? (11 * scale) : 13),
                                        ),
                                      ],
                                      if (cls['duration'] != null &&
                                          cls['duration'].toString().isNotEmpty) ...[
                                        SizedBox(height: 2 * scale),
                                        Text(
                                          'Duration: ${cls['duration']}',
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 11 * scale,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(width: 4 * scale),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_selectedDeptId != null && cls['department_id']?.toString() == _selectedDeptId)
                                      IconButton(
                                        icon: Icon(Icons.link_off_rounded, color: Colors.orange, size: isCompact ? (18 * scale) : 20),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Unassign from Department',
                                        onPressed: () => _unassignClass(cls),
                                      ),
                                    SizedBox(width: 6 * scale),
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded, color: Colors.blue.shade700, size: isCompact ? (18 * scale) : 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _editClass(cls),
                                      tooltip: context.tr('edit'),
                                    ),
                                    SizedBox(width: 6 * scale),
                                    IconButton(
                                      icon: Icon(Icons.delete_rounded, color: Colors.red, size: isCompact ? (18 * scale) : 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _deleteClass(cls),
                                      tooltip: context.tr('delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );

        if (isCompact) {
          return classesPanel;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 1, child: deptPanel),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: classesPanel),
          ],
        );
      },
    );
  }
}
