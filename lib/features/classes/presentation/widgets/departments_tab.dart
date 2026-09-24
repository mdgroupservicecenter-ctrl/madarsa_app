import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/academic_repository.dart';
import '../../../students/presentation/widgets/class_progression_series_dialog.dart';

class DepartmentsTab extends StatefulWidget {
  final AcademicRepository repository;

  const DepartmentsTab({super.key, required this.repository});

  @override
  State<DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends State<DepartmentsTab> {
  bool _isLoading = true;
  List<dynamic> _departments = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterTab = 0; // 0 = All, 1 = With Sub-Depts, 2 = Without Sub-Depts
  final Set<String> _expandedDeptIds = {};

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.repository.getAllDepartments();
      final List<dynamic> processed = [];
      for (final d in data) {
        final map = Map<String, dynamic>.from(d as Map);
        final dId = map['id']?.toString() ?? '';
        final existingSubs = (map['sub_departments'] as List?) ?? [];
        final Map<String, dynamic> subsMap = {};
        for (final s in existingSubs) {
          if (s is Map) {
            final sMap = Map<String, dynamic>.from(s);
            final sId = sMap['id']?.toString() ?? '';
            if (sId.isNotEmpty) subsMap[sId] = sMap;
          }
        }
        for (final other in data) {
          if (other is Map) {
            final pid = other['parent_id']?.toString();
            if (pid != null && pid.isNotEmpty && pid != 'null' && pid == dId) {
              final otherId = other['id']?.toString() ?? '';
              if (otherId.isNotEmpty && !subsMap.containsKey(otherId)) {
                subsMap[otherId] = Map<String, dynamic>.from(other);
              }
            }
          }
        }
        map['sub_departments'] = subsMap.values.toList();
        processed.add(map);
      }
      setState(() {
        _departments = processed;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load departments: $e')),
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

  void _showAddEditDialog([Map<String, dynamic>? currentDept, String? defaultParentId]) {
    final nameCtrl = TextEditingController(text: currentDept?['name'] ?? '');
    final descCtrl = TextEditingController(text: currentDept?['description'] ?? '');
    final headCtrl = TextEditingController(text: currentDept?['head_name'] ?? '');
    String? selectedParentId = currentDept?['parent_id'] ?? defaultParentId;

    // Potential parent departments (main departments only, excluding self)
    final mainDepts = _departments.where((d) {
      final isSelf = currentDept != null && d['id'] == currentDept['id'];
      return d['parent_id'] == null && !isSelf;
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final isEdit = currentDept != null;
        final width = MediaQuery.of(context).size.width;
        final scale = (width / 375.0).clamp(0.75, 1.0);

        return StatefulBuilder(
          builder: (context, setModalState) {
            final isSubDept = selectedParentId != null;

            return _buildStudentStyleFormDialog(
              context: context,
              title: isEdit
                  ? (isSubDept ? 'Edit Sub-Department' : 'Edit Department')
                  : (isSubDept ? 'Add Sub-Department' : 'Add New Department'),
              subtitle: isEdit
                  ? 'Update department / sub-department details'
                  : (isSubDept ? 'Create a sub-department under parent department' : 'Create a main department'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Parent Department Selector
                  DropdownButtonFormField<String?>(
                    initialValue: selectedParentId,
                    dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale, color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'Department Type / Parent',
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(
                        isSubDept ? Icons.subdirectory_arrow_right_rounded : Icons.apartment_rounded,
                        size: 18 * scale,
                        color: AppTheme.primaryColor,
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Row(
                          children: [
                            Icon(Icons.business_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                            SizedBox(width: 8 * scale),
                            Text('None (Main Department)', style: TextStyle(fontSize: 12.5 * scale, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ...mainDepts.map((d) => DropdownMenuItem<String?>(
                            value: d['id'].toString(),
                            child: Row(
                              children: [
                                Icon(Icons.subdirectory_arrow_right_rounded, size: 16 * scale, color: const Color(0xFF1565C0)),
                                SizedBox(width: 8 * scale),
                                Text('Sub of: ${d['name']}', style: TextStyle(fontSize: 12.5 * scale)),
                              ],
                            ),
                          )),
                    ],
                    onChanged: (val) {
                      setModalState(() => selectedParentId = val);
                    },
                  ),
                  SizedBox(height: 12 * scale),

                  // Department / Sub-Department Name
                  TextField(
                    controller: nameCtrl,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: isSubDept ? 'Sub-Department Name *' : 'Department Name *',
                      hintText: isSubDept ? 'e.g. Hifz Awwal, Tajweed, Farsee' : 'e.g. Shouba-e-Hifz-o-Nazra',
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.business_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 12 * scale),

                  // Head / Supervisor
                  TextField(
                    controller: headCtrl,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: 'Head / In-charge / Supervisor (Optional)',
                      hintText: 'e.g. Qari Abdul Rahman',
                      hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                      labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: BorderSide(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 12 * scale),

                  // Description
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    decoration: InputDecoration(
                      labelText: context.tr('description'),
                      hintText: 'Brief description of department / sub-department activities',
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
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
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
                icon: Icon(isEdit ? Icons.save_rounded : Icons.check_circle_rounded),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D6B4E),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final scaffoldMessenger = ScaffoldMessenger.of(this.context);
                  Navigator.pop(context);
                  setState(() => _isLoading = true);

                  try {
                    final payload = {
                      'name': nameCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'head_name': headCtrl.text.trim(),
                      'parent_id': selectedParentId,
                    };

                    if (currentDept == null) {
                      await widget.repository.createDepartment(payload);
                    } else {
                      await widget.repository.updateDepartment(currentDept['id'], payload);
                    }
                    _loadDepartments();
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('Error saving department: $e')),
                      );
                      setState(() => _isLoading = false);
                    }
                  }
                },
                label: Text(
                  isEdit ? context.tr('save') : context.tr('create'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
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

  Future<void> _deleteDepartment(String id, String name, {bool isSubDept = false, int subDeptCount = 0}) async {
    String content = 'Are you sure you want to delete "$name"?';
    if (!isSubDept && subDeptCount > 0) {
      content = 'Are you sure you want to delete "$name"?\nThis will also unlink its $subDeptCount sub-department(s).';
    }
    final confirm = await _showStyledConfirmDialog(
      context: context,
      title: isSubDept ? 'Delete Sub-Department?' : 'Delete Department?',
      content: content,
      confirmText: context.tr('delete'),
      confirmColor: Colors.red,
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await widget.repository.deleteDepartment(id);
      _loadDepartments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

final mainDepts = _departments.where((d) => d['parent_id'] == null).toList();
    final subDepts = _departments.where((d) => d['parent_id'] != null).toList();

    final withSubDepts = mainDepts.where((d) {
      final subs = (d['sub_departments'] as List?) ?? [];
      return subs.isNotEmpty;
    }).toList();

    final withoutSubDepts = mainDepts.where((d) {
      final subs = (d['sub_departments'] as List?) ?? [];
      return subs.isEmpty;
    }).toList();

    List<dynamic> targetList = mainDepts;
    if (_selectedFilterTab == 1) {
      targetList = withSubDepts;
    } else if (_selectedFilterTab == 2) {
      targetList = withoutSubDepts;
    }

    final q = _searchQuery.trim().toLowerCase();
    final filtered = targetList.where((dept) {
      if (q.isEmpty) return true;
      final name = (dept['name'] ?? '').toString().toLowerCase();
      final desc = (dept['description'] ?? '').toString().toLowerCase();
      final head = (dept['head_name'] ?? '').toString().toLowerCase();
      final classesStr = ((dept['classes'] as List?) ?? [])
          .map((c) => (c['name'] ?? '').toString().toLowerCase())
          .join(' ');
      final subs = (dept['sub_departments'] as List?) ?? [];
      final subMatches = subs.any((s) {
        final sName = (s['name'] ?? '').toString().toLowerCase();
        final sHead = (s['head_name'] ?? '').toString().toLowerCase();
        final sDesc = (s['description'] ?? '').toString().toLowerCase();
        final sClasses = ((s['classes'] as List?) ?? [])
            .map((c) => (c['name'] ?? '').toString().toLowerCase())
            .join(' ');
        return sName.contains(q) || sHead.contains(q) || sDesc.contains(q) || sClasses.contains(q);
      });
      return name.contains(q) || desc.contains(q) || head.contains(q) || classesStr.contains(q) || subMatches;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Departments & Sub-Departments',
                      style: AppTheme.getFontStyle(
                        fontSize: isCompact ? (15 * scale) : 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${mainDepts.length} Main Departments • ${subDepts.length} Sub-Departments',
                      style: AppTheme.getFontStyle(
                        fontSize: isCompact ? (11 * scale) : 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8 * scale,
                  children: [
                    // Class & Department Progression Series
                    isCompact
                        ? Material(
                            color: const Color(0xFF0D6B4E).withAlpha(20),
                            borderRadius: BorderRadius.circular(10 * scale),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10 * scale),
                              onTap: () async {
                                final res = await ClassProgressionSeriesDialog.show(context);
                                if (res == true) _loadDepartments();
                              },
                              child: Tooltip(
                                message: 'Class & Department Progression Series',
                                child: Padding(
                                  padding: EdgeInsets.all(8 * scale),
                                  child: Icon(Icons.account_tree_rounded, color: const Color(0xFF0D6B4E), size: 20 * scale),
                                ),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () async {
                              final res = await ClassProgressionSeriesDialog.show(context);
                              if (res == true) _loadDepartments();
                            },
                            icon: const Icon(Icons.account_tree_rounded, size: 16),
                            label: Text(
                              'Progression Series',
                              style: AppTheme.getFontStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0D6B4E),
                              side: const BorderSide(color: Color(0xFF0D6B4E)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                    if (!isCompact)
                      OutlinedButton.icon(
                        onPressed: () => _showAddEditDialog(null, mainDepts.isNotEmpty ? mainDepts.first['id'] : null),
                        icon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 16),
                        label: Text(
                          'Add Sub-Dept',
                          style: AppTheme.getFontStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1565C0),
                          side: const BorderSide(color: Color(0xFF1565C0)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    isCompact
                        ? Material(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(10 * scale),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10 * scale),
                              onTap: () => _showAddEditDialog(),
                              child: Padding(
                                padding: EdgeInsets.all(8 * scale),
                                child: Icon(Icons.add_rounded, color: Colors.white, size: 20 * scale),
                              ),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed: () => _showAddEditDialog(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(
                              'Add Department',
                              style: AppTheme.getFontStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 10 * scale),

            // Search Bar & Filter Tabs
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: isCompact ? (38 * scale) : 42,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: AppTheme.getFontStyle(fontSize: isCompact ? (12.5 * scale) : 13.5),
                      decoration: InputDecoration(
                        hintText: 'Search department, sub-department, head or class...',
                        hintStyle: AppTheme.getFontStyle(fontSize: isCompact ? (11.5 * scale) : 13, color: Colors.grey),
                        prefixIcon: Icon(Icons.search_rounded, size: isCompact ? (17 * scale) : 19),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded, size: isCompact ? (16 * scale) : 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 0),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10 * scale),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8 * scale),

            // Filter Tabs Chips & Expand All Toggle
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All (${mainDepts.length})', 0, isDark, scale),
                        SizedBox(width: 6 * scale),
                        _buildFilterChip('With Sub-Depts (${withSubDepts.length})', 1, isDark, scale),
                        SizedBox(width: 6 * scale),
                        _buildFilterChip('Without Sub-Depts (${withoutSubDepts.length})', 2, isDark, scale),
                      ],
                    ),
                  ),
                ),
                if (mainDepts.isNotEmpty)
                  InkWell(
                    onTap: () {
                      setState(() {
                        final allIds = mainDepts.map((d) => d['id'].toString()).toSet();
                        if (_expandedDeptIds.length == allIds.length) {
                          _expandedDeptIds.clear();
                        } else {
                          _expandedDeptIds.addAll(allIds);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8 * scale),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 5 * scale),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8 * scale),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _expandedDeptIds.length == mainDepts.length ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                            size: 14 * scale,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          SizedBox(width: 4 * scale),
                          Text(
                            _expandedDeptIds.length == mainDepts.length ? 'Collapse All' : 'Expand All',
                            style: AppTheme.getFontStyle(
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 10 * scale),

            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 54 * scale,
                            height: 54 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryColor.withAlpha(15),
                            ),
                            child: Icon(
                              Icons.business_rounded,
                              size: 28 * scale,
                              color: AppTheme.primaryColor.withAlpha(120),
                            ),
                          ),
                          SizedBox(height: 12 * scale),
                          Text(
                            'No departments found',
                            style: AppTheme.getFontStyle(
                              fontSize: isCompact ? (14 * scale) : 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            'Click Add Department to create one.',
                            style: AppTheme.getFontStyle(
                              fontSize: isCompact ? (12 * scale) : 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final dept = filtered[index];
                        final deptId = dept['id'].toString();
                        final headName = dept['head_name'] as String?;
                        final classCount = (dept['class_count'] ?? 0) as int;
                        final classesList = (dept['classes'] as List?) ?? [];
                        final subDeptsList = (dept['sub_departments'] as List?) ?? [];

                        // Auto-expand if search query matches any sub-department of this department
                        final hasSubMatch = q.isNotEmpty && subDeptsList.any((s) {
                          final sName = (s['name'] ?? '').toString().toLowerCase();
                          final sHead = (s['head_name'] ?? '').toString().toLowerCase();
                          final sDesc = (s['description'] ?? '').toString().toLowerCase();
                          final sClasses = ((s['classes'] as List?) ?? [])
                              .map((c) => (c['name'] ?? '').toString().toLowerCase())
                              .join(' ');
                          return sName.contains(q) || sHead.contains(q) || sDesc.contains(q) || sClasses.contains(q);
                        });

                        final isExpanded = _expandedDeptIds.contains(deptId) || hasSubMatch;

                        return Container(
                          margin: EdgeInsets.only(bottom: 10 * scale),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: BorderRadius.circular(12 * scale),
                            border: Border.all(
                              color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 15 : 5),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? (10 * scale) : 16,
                              vertical: isCompact ? (8 * scale) : 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: isCompact ? (36 * scale) : 44,
                                      height: isCompact ? (36 * scale) : 44,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withAlpha(20),
                                        borderRadius: BorderRadius.circular(8 * scale),
                                      ),
                                      child: Icon(
                                        Icons.business_center_rounded,
                                        color: AppTheme.primaryColor,
                                        size: isCompact ? (20 * scale) : 24,
                                      ),
                                    ),
                                    SizedBox(width: 10 * scale),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  dept['name'] ?? '',
                                                  style: AppTheme.getFontStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: isCompact ? (14 * scale) : 16,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 6 * scale),
                                              // Sub-Depts Count Badge (clickable to toggle dropdown!)
                                              InkWell(
                                                onTap: () {
                                                  setState(() {
                                                    if (_expandedDeptIds.contains(deptId)) {
                                                      _expandedDeptIds.remove(deptId);
                                                    } else {
                                                      _expandedDeptIds.add(deptId);
                                                    }
                                                  });
                                                },
                                                borderRadius: BorderRadius.circular(10 * scale),
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 6 * scale,
                                                    vertical: 2 * scale,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: subDeptsList.isNotEmpty
                                                        ? const Color(0xFF1565C0).withAlpha(18)
                                                        : Colors.grey.withAlpha(18),
                                                    borderRadius: BorderRadius.circular(10 * scale),
                                                    border: Border.all(
                                                      color: subDeptsList.isNotEmpty
                                                          ? const Color(0xFF1565C0).withAlpha(50)
                                                          : Colors.grey.withAlpha(50),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.account_tree_rounded,
                                                        size: 11 * scale,
                                                        color: subDeptsList.isNotEmpty
                                                            ? const Color(0xFF1565C0)
                                                            : Colors.grey,
                                                      ),
                                                      SizedBox(width: 3 * scale),
                                                      Text(
                                                        '${subDeptsList.length} Sub-Depts',
                                                        style: TextStyle(
                                                          fontSize: 10 * scale,
                                                          fontWeight: FontWeight.w700,
                                                          color: subDeptsList.isNotEmpty
                                                            ? const Color(0xFF1565C0)
                                                            : Colors.grey,
                                                        ),
                                                      ),
                                                      SizedBox(width: 2 * scale),
                                                      Icon(
                                                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                                        size: 13 * scale,
                                                        color: subDeptsList.isNotEmpty
                                                            ? const Color(0xFF1565C0)
                                                            : Colors.grey,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 4 * scale),
                                              // Class Count Badge
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 6 * scale,
                                                  vertical: 2 * scale,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: classCount > 0
                                                      ? const Color(0xFF0D6B4E).withAlpha(20)
                                                      : Colors.grey.withAlpha(20),
                                                  borderRadius: BorderRadius.circular(10 * scale),
                                                  border: Border.all(
                                                    color: classCount > 0
                                                        ? const Color(0xFF0D6B4E).withAlpha(50)
                                                        : Colors.grey.withAlpha(50),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.class_rounded,
                                                      size: 11 * scale,
                                                      color: classCount > 0
                                                          ? const Color(0xFF0D6B4E)
                                                          : Colors.grey,
                                                    ),
                                                    SizedBox(width: 3 * scale),
                                                    Text(
                                                      '$classCount Classes',
                                                      style: TextStyle(
                                                        fontSize: 10 * scale,
                                                        fontWeight: FontWeight.w700,
                                                        color: classCount > 0
                                                            ? const Color(0xFF0D6B4E)
                                                            : Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (headName != null && headName.isNotEmpty) ...[
                                            SizedBox(height: 3 * scale),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.person_outline_rounded,
                                                  size: 12 * scale,
                                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                ),
                                                SizedBox(width: 3 * scale),
                                                Expanded(
                                                  child: Text(
                                                    'Head: $headName',
                                                    style: TextStyle(
                                                      fontSize: 11 * scale,
                                                      fontWeight: FontWeight.w500,
                                                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (dept['description'] != null && dept['description'].toString().trim().isNotEmpty) ...[
                                            SizedBox(height: 2 * scale),
                                            Text(
                                              dept['description'].toString().trim(),
                                              style: TextStyle(
                                                fontSize: 10.5 * scale,
                                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 6 * scale),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.add_circle_outline_rounded,
                                            color: const Color(0xFF1565C0),
                                            size: isCompact ? (18 * scale) : 20,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showAddEditDialog(null, dept['id'].toString()),
                                          tooltip: 'Add Sub-Department',
                                        ),
                                        SizedBox(width: 8 * scale),
                                        IconButton(
                                          icon: Icon(
                                            Icons.edit_rounded,
                                            color: Colors.blue.shade700,
                                            size: isCompact ? (18 * scale) : 20,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showAddEditDialog(dept),
                                          tooltip: context.tr('edit'),
                                        ),
                                        SizedBox(width: 8 * scale),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_rounded,
                                            color: Colors.red,
                                            size: isCompact ? (18 * scale) : 20,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _deleteDepartment(
                                            dept['id'],
                                            dept['name'] ?? '',
                                            subDeptCount: subDeptsList.length,
                                          ),
                                          tooltip: context.tr('delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),

                                // Directly assigned classes chips
                                if (classesList.isNotEmpty) ...[
                                  SizedBox(height: 8 * scale),
                                  Wrap(
                                    spacing: 4 * scale,
                                    runSpacing: 4 * scale,
                                    children: classesList.map((c) {
                                      final className = c['name']?.toString() ?? '';
                                      return Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6 * scale,
                                          vertical: 2 * scale,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withAlpha(10)
                                              : const Color(0xFFF0F4F8),
                                          borderRadius: BorderRadius.circular(6 * scale),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white12
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          className,
                                          style: AppTheme.getFontStyle(
                                            fontSize: 10 * scale,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? Colors.white70 : const Color(0xFF1A1A2E),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                // Dropdown Header / Accordion for Sub-Departments
                                SizedBox(height: 8 * scale),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (_expandedDeptIds.contains(deptId)) {
                                        _expandedDeptIds.remove(deptId);
                                      } else {
                                        _expandedDeptIds.add(deptId);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8 * scale),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10 * scale,
                                      vertical: 7 * scale,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isExpanded
                                          ? const Color(0xFF1565C0).withAlpha(isDark ? 35 : 18)
                                          : (isDark ? Colors.white.withAlpha(6) : const Color(0xFFF1F5F9)),
                                      borderRadius: BorderRadius.circular(8 * scale),
                                      border: Border.all(
                                        color: isExpanded
                                            ? const Color(0xFF1565C0).withAlpha(isDark ? 80 : 60)
                                            : (isDark ? Colors.white10 : Colors.grey.shade300),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.account_tree_rounded,
                                          size: 14 * scale,
                                          color: subDeptsList.isNotEmpty
                                              ? const Color(0xFF1565C0)
                                              : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                        ),
                                        SizedBox(width: 8 * scale),
                                        Text(
                                          'Sub-Departments (${subDeptsList.length})',
                                          style: AppTheme.getFontStyle(
                                            fontSize: 11.5 * scale,
                                            fontWeight: FontWeight.bold,
                                            color: subDeptsList.isNotEmpty
                                                ? (isDark ? const Color(0xFF90CAF9) : const Color(0xFF0D47A1))
                                                : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          isExpanded ? 'Hide' : 'Show',
                                          style: TextStyle(
                                            fontSize: 10.5 * scale,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                          ),
                                        ),
                                        SizedBox(width: 2 * scale),
                                        Icon(
                                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                          size: 16 * scale,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Expanded Sub-Departments Dropdown Content
                                if (isExpanded) ...[
                                  SizedBox(height: 8 * scale),
                                  Container(
                                    padding: EdgeInsets.all(10 * scale),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF151522) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10 * scale),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF1565C0).withAlpha(45)
                                            : const Color(0xFF90CAF9).withAlpha(120),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (subDeptsList.isEmpty) ...[
                                          Padding(
                                            padding: EdgeInsets.symmetric(vertical: 6 * scale, horizontal: 4 * scale),
                                            child: Row(
                                              children: [
                                                Icon(Icons.info_outline_rounded, size: 14 * scale, color: Colors.grey),
                                                SizedBox(width: 6 * scale),
                                                Expanded(
                                                  child: Text(
                                                    'No sub-departments under this department.',
                                                    style: TextStyle(
                                                      fontSize: 11.5 * scale,
                                                      fontStyle: FontStyle.italic,
                                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () => _showAddEditDialog(null, dept['id'].toString()),
                                                  icon: Icon(Icons.add_rounded, size: 14 * scale, color: const Color(0xFF1565C0)),
                                                  label: Text(
                                                    'Add Sub-Dept',
                                                    style: TextStyle(
                                                      fontSize: 11.5 * scale,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF1565C0),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ] else ...[
                                          ...subDeptsList.asMap().entries.map((entry) {
                                            final subIndex = entry.key;
                                            final subRaw = entry.value;
                                            final Map<String, dynamic> sub = subRaw is Map<String, dynamic>
                                                ? subRaw
                                                : (subRaw is Map ? Map<String, dynamic>.from(subRaw) : <String, dynamic>{'name': subRaw.toString()});
                                            final subName = (sub['name'] ?? '').toString().trim();
                                            final subHead = sub['head_name']?.toString().trim();
                                            final subDesc = sub['description']?.toString().trim();
                                            final subClasses = (sub['classes'] as List?) ?? [];
                                            final int subClassCount = sub['class_count'] != null
                                                ? (sub['class_count'] as num).toInt()
                                                : subClasses.length;

                                            return Container(
                                              margin: EdgeInsets.only(
                                                bottom: subIndex < subDeptsList.length - 1 ? 8 * scale : 0,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                                                borderRadius: BorderRadius.circular(8 * scale),
                                                border: Border.all(
                                                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                                                  width: 1.0,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withAlpha(isDark ? 15 : 5),
                                                    blurRadius: 3,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8 * scale),
                                                child: IntrinsicHeight(
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                                    children: [
                                                      // Blue left accent indicator strip
                                                      Container(
                                                        width: 4 * scale,
                                                        color: const Color(0xFF1565C0),
                                                      ),
                                                      SizedBox(width: 8 * scale),
                                                      // Icon
                                                      Padding(
                                                        padding: EdgeInsets.symmetric(vertical: 8 * scale),
                                                        child: Align(
                                                          alignment: Alignment.topCenter,
                                                          child: Container(
                                                            padding: EdgeInsets.all(4 * scale),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF1565C0).withAlpha(15),
                                                              borderRadius: BorderRadius.circular(6 * scale),
                                                            ),
                                                            child: Icon(
                                                              Icons.subdirectory_arrow_right_rounded,
                                                              size: 16 * scale,
                                                              color: const Color(0xFF1565C0),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(width: 8 * scale),
                                                      // Content details
                                                      Expanded(
                                                        child: Padding(
                                                          padding: EdgeInsets.symmetric(vertical: 8 * scale),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Expanded(
                                                                    child: Text(
                                                                      subName.isEmpty ? 'Sub-Department' : subName,
                                                                      style: AppTheme.getFontStyle(
                                                                        fontSize: 13 * scale,
                                                                        fontWeight: FontWeight.bold,
                                                                        color: isDark ? Colors.white : Colors.black87,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  SizedBox(width: 6 * scale),
                                                                  Container(
                                                                    padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                                                                    decoration: BoxDecoration(
                                                                      color: subClassCount > 0
                                                                          ? const Color(0xFF0D6B4E).withAlpha(18)
                                                                          : Colors.grey.withAlpha(15),
                                                                      borderRadius: BorderRadius.circular(6 * scale),
                                                                      border: Border.all(
                                                                        color: subClassCount > 0
                                                                            ? const Color(0xFF0D6B4E).withAlpha(50)
                                                                            : Colors.grey.withAlpha(40),
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      '$subClassCount Classes',
                                                                      style: TextStyle(
                                                                        fontSize: 9.5 * scale,
                                                                        fontWeight: FontWeight.w700,
                                                                        color: subClassCount > 0 ? const Color(0xFF0D6B4E) : Colors.grey,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              if (subHead != null && subHead.isNotEmpty) ...[
                                                                SizedBox(height: 3 * scale),
                                                                Row(
                                                                  children: [
                                                                    Icon(Icons.person_outline_rounded, size: 11 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                                                    SizedBox(width: 3 * scale),
                                                                    Expanded(
                                                                      child: Text(
                                                                        'Head: $subHead',
                                                                        style: TextStyle(
                                                                          fontSize: 11 * scale,
                                                                          fontWeight: FontWeight.w500,
                                                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                              if (subDesc != null && subDesc.isNotEmpty) ...[
                                                                SizedBox(height: 2 * scale),
                                                                Text(
                                                                  subDesc,
                                                                  style: TextStyle(
                                                                    fontSize: 10.5 * scale,
                                                                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                                                  ),
                                                                  maxLines: 2,
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ],
                                                              if (subClasses.isNotEmpty) ...[
                                                                SizedBox(height: 4 * scale),
                                                                Wrap(
                                                                  spacing: 4 * scale,
                                                                  runSpacing: 2 * scale,
                                                                  children: subClasses.map((c) {
                                                                    final cName = (c is Map ? (c['name'] ?? '') : c).toString();
                                                                    return Container(
                                                                      padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                                                                      decoration: BoxDecoration(
                                                                        color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFF1F5F9),
                                                                        borderRadius: BorderRadius.circular(4 * scale),
                                                                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                                                      ),
                                                                      child: Text(
                                                                        cName,
                                                                        style: TextStyle(
                                                                          fontSize: 9.5 * scale,
                                                                          fontWeight: FontWeight.w500,
                                                                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                                                                        ),
                                                                      ),
                                                                    );
                                                                  }).toList(),
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(width: 6 * scale),
                                                      // Action buttons
                                                      Padding(
                                                        padding: EdgeInsets.only(right: 8 * scale),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            IconButton(
                                                              icon: Icon(Icons.edit_rounded, size: 16 * scale, color: Colors.blue.shade700),
                                                              padding: EdgeInsets.zero,
                                                              constraints: const BoxConstraints(),
                                                              onPressed: () => _showAddEditDialog(sub),
                                                              tooltip: 'Edit Sub-Dept',
                                                            ),
                                                            SizedBox(width: 8 * scale),
                                                            IconButton(
                                                              icon: Icon(Icons.delete_rounded, size: 16 * scale, color: Colors.red),
                                                              padding: EdgeInsets.zero,
                                                              constraints: const BoxConstraints(),
                                                              onPressed: () => _deleteDepartment(sub['id'], sub['name'] ?? '', isSubDept: true),
                                                              tooltip: 'Delete Sub-Dept',
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                          SizedBox(height: 6 * scale),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              onPressed: () => _showAddEditDialog(null, dept['id'].toString()),
                                              icon: Icon(Icons.add_rounded, size: 14 * scale, color: const Color(0xFF1565C0)),
                                              label: Text(
                                                'Add Sub-Department',
                                                style: TextStyle(
                                                  fontSize: 11.5 * scale,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFF1565C0),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, int index, bool isDark, double scale) {
    final isSelected = _selectedFilterTab == index;

    return InkWell(
      onTap: () => setState(() => _selectedFilterTab = index),
      borderRadius: BorderRadius.circular(8 * scale),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(8 * scale),
        ),
        child: Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 11.5 * scale,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey.shade400 : Colors.grey.shade800),
          ),
        ),
      ),
    );
  }
}
