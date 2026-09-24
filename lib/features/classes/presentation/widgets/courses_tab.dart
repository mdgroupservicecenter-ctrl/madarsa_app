import 'dart:math';
import 'package:madarsa_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/repositories/academic_repository.dart';

class CoursesTab extends StatefulWidget {
  final AcademicRepository repository;
  final List<dynamic> classes;

  const CoursesTab({super.key, required this.repository, required this.classes});

  @override
  State<CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<CoursesTab> {
  bool _isLoading = true;
  List<dynamic> _hierarchy = [];
  List<dynamic> _globalCourses = [];
  List<dynamic> _departments = [];
  String? _selectedDeptId;
  String? _selectedClassId;

  // Multi-unassign selection for assigned divisions
  final Set<String> _selectedClassCourseIdsToUnassign = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final hierarchy = await widget.repository.getAcademicHierarchy();
      final globalCourses = await widget.repository.getAllCourses();
      List<dynamic> depts = [];
      try {
        depts = await widget.repository.getAllDepartments();
      } catch (_) {}

      setState(() {
        _hierarchy = hierarchy;
        _globalCourses = globalCourses;
        _departments = depts;
        _selectedClassCourseIdsToUnassign.clear();
        _isLoading = false;

        if (_selectedClassId == null && _hierarchy.isNotEmpty) {
          _selectedClassId = _hierarchy.first['id'];
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load division data: $e')),
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

  void _showCreateCourseDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final width = MediaQuery.of(context).size.width;
        final scale = (width / 375.0).clamp(0.75, 1.0);

        return _buildStudentStyleFormDialog(
          context: context,
          title: 'Create New Global Division',
          subtitle: 'Add a new division/course globally',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                style: AppTheme.getFontStyle(fontSize: 13 * scale),
                decoration: InputDecoration(
                  labelText: 'Division Name (e.g. Fiqha, Nahw)',
                  hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                  labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  prefixIcon: Icon(Icons.grid_view_rounded, size: 16 * scale, color: AppTheme.primaryColor),
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await widget.repository.createCourse({
                  'name': nameCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                });
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating division: $e')),
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
  }

  void _editCourse(Map<String, dynamic> course, {VoidCallback? onRefresh}) {
    final nameCtrl = TextEditingController(text: course['name']);
    final descCtrl = TextEditingController(text: course['description']);

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final width = MediaQuery.of(context).size.width;
        final scale = (width / 375.0).clamp(0.75, 1.0);

        return _buildStudentStyleFormDialog(
          context: context,
          title: 'Edit Division',
          subtitle: 'Update division details and description',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                style: AppTheme.getFontStyle(fontSize: 13 * scale),
                decoration: InputDecoration(
                  labelText: 'Division Name',
                  hintStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey.shade400),
                  labelStyle: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  prefixIcon: Icon(Icons.grid_view_rounded, size: 16 * scale, color: AppTheme.primaryColor),
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
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await widget.repository.updateCourse(course['id'].toString(), {
                  'name': nameCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                });
                await _loadData();
                onRefresh?.call();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating division: $e')),
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

  void _deleteCourse(Map<String, dynamic> course, {VoidCallback? onRefresh}) async {
    final confirm = await _showStyledConfirmDialog(
      context: context,
      title: context.tr('delete'),
      content: 'Are you sure you want to delete "${course['name']}"? This might fail if the division is assigned to classes.',
      confirmText: context.tr('delete'),
      confirmColor: Colors.red,
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await widget.repository.deleteCourse(course['id'].toString());
        await _loadData();
        onRefresh?.call();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting division: $e')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  void _showManageCoursesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final width = MediaQuery.of(context).size.width;
            final scale = (width / 375.0).clamp(0.75, 1.0);
            return _buildStudentStyleFormDialog(
              context: context,
              title: 'Manage Global Divisions',
              subtitle: 'View, edit or delete global divisions',
              child: _globalCourses.isEmpty
                  ? Center(child: Padding(padding: EdgeInsets.all(20 * scale), child: Text('No global divisions found.', style: TextStyle(fontSize: 13 * scale))))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _globalCourses.length,
                      itemBuilder: (context, index) {
                        final course = _globalCourses[index];
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return Card(
                          margin: EdgeInsets.only(bottom: 8 * scale),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                          color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 2 * scale),
                            title: Text(course['name'] ?? '', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13 * scale)),
                            subtitle: course['description'] != null && course['description'].toString().isNotEmpty
                                ? Text(course['description'], style: TextStyle(fontSize: 11 * scale, color: Colors.grey))
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_rounded, color: Colors.blue, size: 18 * scale),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _editCourse(course, onRefresh: () {
                                      setModalState(() {});
                                    });
                                  },
                                ),
                                SizedBox(width: 12 * scale),
                                IconButton(
                                  icon: Icon(Icons.delete_rounded, color: Colors.red, size: 18 * scale),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    _deleteCourse(course, onRefresh: () {
                                      setModalState(() {});
                                    });
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
        );
      },
    );
  }

  // --- MULTIPLE ASSIGN DIVISIONS DIALOG ---
  void _assignMultipleCoursesToSelectedClass() {
    if (_selectedClassId == null) return;

    final selectedClassNode = _hierarchy.where((c) => c['id'] == _selectedClassId).firstOrNull;
    final assignedCourseIds = selectedClassNode != null
        ? (selectedClassNode['courses'] as List).map((c) => c['course_id'].toString()).toSet()
        : <String>{};

    final availableCourses = _globalCourses.where((c) => !assignedCourseIds.contains(c['id'].toString())).toList();
    final Set<String> selectedCourseIds = {};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final width = MediaQuery.of(context).size.width;
            final scale = (width / 375.0).clamp(0.75, 1.0);
            final allSelected = availableCourses.isNotEmpty && selectedCourseIds.length == availableCourses.length;

            return _buildStudentStyleFormDialog(
              context: context,
              title: 'Assign Divisions',
              subtitle: 'Select divisions to assign to ${selectedClassNode?['name'] ?? 'Class'}',
              child: availableCourses.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20 * scale),
                        child: Text(
                          'All available divisions are already assigned to this class.',
                          style: TextStyle(fontSize: 12 * scale),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        CheckboxListTile(
                          dense: true,
                          activeColor: const Color(0xFF0D6B4E),
                          title: Text('Select All Divisions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13 * scale)),
                          value: allSelected,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                selectedCourseIds.addAll(availableCourses.map((c) => c['id'].toString()));
                              } else {
                                selectedCourseIds.clear();
                              }
                            });
                          },
                        ),
                        const Divider(height: 1),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: availableCourses.length,
                          itemBuilder: (context, index) {
                            final course = availableCourses[index];
                            final courseId = course['id'].toString();
                            final isChecked = selectedCourseIds.contains(courseId);

                            return CheckboxListTile(
                              dense: true,
                              activeColor: const Color(0xFF0D6B4E),
                              title: Text(course['name'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13 * scale)),
                              subtitle: course['description'] != null && course['description'].toString().isNotEmpty
                                  ? Text(course['description'], style: TextStyle(fontSize: 11 * scale))
                                  : null,
                              value: isChecked,
                              onChanged: (val) {
                                setModalState(() {
                                  if (val == true) {
                                    selectedCourseIds.add(courseId);
                                  } else {
                                    selectedCourseIds.remove(courseId);
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
                onPressed: selectedCourseIds.isEmpty || availableCourses.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(context);
                        setState(() => _isLoading = true);
                        int successCount = 0;
                        try {
                          for (final cId in selectedCourseIds) {
                            await widget.repository.assignCourseToClass(_selectedClassId!, cId);
                            successCount++;
                          }
                          _loadData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Successfully assigned $successCount division(s)!')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error assigning divisions: $e')),
                            );
                            setState(() => _isLoading = false);
                          }
                        }
                      },
                label: Text(
                  'Assign Selected (${selectedCourseIds.length})',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- MULTIPLE UNASSIGN DIVISIONS ACTION ---
  Future<void> _unassignSelectedCourses() async {
    if (_selectedClassCourseIdsToUnassign.isEmpty) return;

    final count = _selectedClassCourseIdsToUnassign.length;
    final confirm = await _showStyledConfirmDialog(
      context: context,
      title: 'Unassign Selected Divisions?',
      content: 'Are you sure you want to unassign $count division(s) from this class?',
      confirmText: 'Unassign ($count)',
      confirmColor: Colors.orange.shade800,
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        for (final ccId in _selectedClassCourseIdsToUnassign.toList()) {
          await widget.repository.removeCourseFromClass(ccId);
        }
        _selectedClassCourseIdsToUnassign.clear();
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error unassigning divisions: $e')),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  List<DropdownMenuItem<String?>> _buildDepartmentDropdownItems(double scale, bool isDark) {
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('All Departments (${_hierarchy.length})', style: TextStyle(fontSize: 12.5 * scale)),
          ],
        ),
      ),
    ];

    final mainDepts = _departments.where((d) => d['parent_id'] == null).toList();
    for (final main in mainDepts) {
      final count = (main['class_count'] ?? 0) as int;
      items.add(
        DropdownMenuItem<String?>(
          value: main['id'].toString(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.business_center_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                  SizedBox(width: 5 * scale),
                  Text(main['name'] ?? '', style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Text('$count', style: TextStyle(fontSize: 9.5 * scale, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              ),
            ],
          ),
        ),
      );

      final subDepts = (main['sub_departments'] as List?) ??
          _departments.where((d) => d['parent_id']?.toString() == main['id']?.toString()).toList();
      for (final sub in subDepts) {
        final sCount = (sub['class_count'] ?? 0) as int;
        items.add(
          DropdownMenuItem<String?>(
            value: sub['id'].toString(),
            child: Padding(
              padding: EdgeInsets.only(left: 10 * scale),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.subdirectory_arrow_right_rounded, size: 13 * scale, color: const Color(0xFF1565C0)),
                      SizedBox(width: 4 * scale),
                      Text('Sub: ${sub['name']}', style: TextStyle(fontSize: 11.5 * scale, color: const Color(0xFF1565C0))),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6 * scale),
                    ),
                    child: Text('$sCount', style: TextStyle(fontSize: 9.5 * scale, fontWeight: FontWeight.bold, color: const Color(0xFF1565C0))),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return items;
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
                                'Select Class & Department',
                                style: AppTheme.getFontStyle(
                                  fontSize: 14 * scale,
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
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setDialogState) {
                          final dialogFilteredHierarchy = _selectedDeptId == null
                              ? _hierarchy
                              : _hierarchy.where((cls) {
                                  final dId = cls['department_id']?.toString();
                                  if (dId == _selectedDeptId) return true;
                                  final selectedDept = _departments.where((d) => d['id'].toString() == _selectedDeptId).firstOrNull;
                                  if (selectedDept != null && selectedDept['sub_departments'] is List) {
                                    final subIds = (selectedDept['sub_departments'] as List).map((s) => s['id'].toString()).toSet();
                                    if (subIds.contains(dId)) return true;
                                  }
                                  return false;
                                }).toList();

                          return ListView(
                            padding: EdgeInsets.all(12 * scale),
                            children: [
                              Text('1. Filter Department / Sub-Department', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12 * scale)),
                              SizedBox(height: 6 * scale),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8 * scale),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    value: _selectedDeptId,
                                    hint: Text('All Departments', style: TextStyle(fontSize: 12 * scale)),
                                    items: _buildDepartmentDropdownItems(scale, isDark),
                                    onChanged: (v) {
                                      setState(() {
                                        _selectedDeptId = v;
                                        _selectedClassId = null;
                                      });
                                      setDialogState(() {});
                                    },
                                  ),
                                ),
                              ),
                              SizedBox(height: 14 * scale),
                              Text('2. Select Class', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12 * scale)),
                              SizedBox(height: 6 * scale),
                              ...dialogFilteredHierarchy.map((cls) {
                                final cId = cls['id'].toString();
                                final isSelected = _selectedClassId?.toString() == cId;
                                final deptName = cls['department_name'] as String?;
                                final parentDeptName = cls['parent_department_name'] as String?;
                                final divCount = (cls['courses'] as List?)?.length ?? 0;

                                String deptDisplay = '';
                                if (parentDeptName != null && parentDeptName.isNotEmpty) {
                                  deptDisplay = '$parentDeptName • $deptName';
                                } else if (deptName != null && deptName.isNotEmpty) {
                                  deptDisplay = deptName;
                                }

                                return Container(
                                  margin: EdgeInsets.only(bottom: 6 * scale),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
                                        : (isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50),
                                    borderRadius: BorderRadius.circular(8 * scale),
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(context).primaryColor.withValues(alpha: 0.4)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10 * scale),
                                    leading: Radio<String>(
                                      value: cId,
                                      groupValue: _selectedClassId?.toString(),
                                      activeColor: Theme.of(context).primaryColor,
                                      onChanged: (v) {
                                        setState(() {
                                          _selectedClassId = cls['id'];
                                          _selectedClassCourseIdsToUnassign.clear();
                                        });
                                        Navigator.pop(context);
                                      },
                                    ),
                                    title: Text(
                                      cls['name'] ?? '',
                                      style: AppTheme.getFontStyle(
                                        fontSize: 12 * scale,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: deptDisplay.isNotEmpty
                                        ? Text('Dept: $deptDisplay', style: TextStyle(fontSize: 10 * scale, color: parentDeptName != null ? const Color(0xFF1565C0) : null))
                                        : null,
                                    trailing: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6 * scale),
                                      ),
                                      child: Text(
                                        '$divCount div',
                                        style: TextStyle(
                                          fontSize: 10 * scale,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedClassId = cls['id'];
                                        _selectedClassCourseIdsToUnassign.clear();
                                      });
                                      Navigator.pop(context);
                                    },
                                  ),
                                );
                              }),
                            ],
                          );
                        },
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
    if (_isLoading && _hierarchy.isEmpty && _departments.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filteredHierarchy = _selectedDeptId == null
        ? _hierarchy
        : _hierarchy.where((cls) {
            final dId = cls['department_id']?.toString();
            if (dId == _selectedDeptId) return true;
            final selectedDept = _departments.where((d) => d['id'].toString() == _selectedDeptId).firstOrNull;
            if (selectedDept != null && selectedDept['sub_departments'] is List) {
              final subIds = (selectedDept['sub_departments'] as List).map((s) => s['id'].toString()).toSet();
              if (subIds.contains(dId)) return true;
            }
            return false;
          }).toList();

    // Ensure selected class is in filtered list
    if (_selectedClassId != null && !filteredHierarchy.any((cls) => cls['id'] == _selectedClassId)) {
      _selectedClassId = filteredHierarchy.isNotEmpty ? filteredHierarchy.first['id'] : null;
    }

    // Get assigned courses for selected class
    final selectedClassNode = _hierarchy.where((c) => c['id'] == _selectedClassId).firstOrNull;
    final assignedCourses = selectedClassNode != null ? (selectedClassNode['courses'] as List) : [];

    final allAssignedSelected = assignedCourses.isNotEmpty &&
        _selectedClassCourseIdsToUnassign.length == assignedCourses.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        // Desktop Left Panel: Department Dropdown + Class List
        final classPanel = Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
            borderRadius: BorderRadius.circular(14 * scale),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_departments.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(10 * scale, 8 * scale, 10 * scale, 4 * scale),
                  child: Row(
                    children: [
                      Icon(Icons.filter_list_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                      SizedBox(width: 4 * scale),
                      Text(
                        'Filter Department',
                        style: AppTheme.getFontStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8 * scale),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey.shade300,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedDeptId,
                        items: _buildDepartmentDropdownItems(scale, isDark),
                        onChanged: (v) {
                          setState(() {
                            _selectedDeptId = v;
                          });
                        },
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 6 * scale),
                const Divider(height: 1),
              ],
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                child: Text(
                  'Select Class',
                  style: AppTheme.getFontStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filteredHierarchy.isEmpty && !_isLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('No classes found in this department.'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredHierarchy.length,
                        itemBuilder: (context, index) {
                          final cls = filteredHierarchy[index];
                          final isSelected = _selectedClassId == cls['id'];
                          final deptName = cls['department_name'] as String?;
                          final parentDeptName = cls['parent_department_name'] as String?;
                          final divCount = (cls['courses'] as List?)?.length ?? 0;

                          String deptDisplay = '';
                          if (parentDeptName != null && parentDeptName.isNotEmpty) {
                            deptDisplay = '$parentDeptName • $deptName';
                          } else if (deptName != null && deptName.isNotEmpty) {
                            deptDisplay = deptName;
                          }

                          return ListTile(
                            title: Text(
                              cls['name'] ?? '',
                              style: AppTheme.getFontStyle(fontSize: 14),
                            ),
                            subtitle: deptDisplay.isNotEmpty
                                ? Text(
                                    'Dept: $deptDisplay',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: parentDeptName != null ? const Color(0xFF1565C0) : Colors.grey.shade600,
                                      fontWeight: parentDeptName != null ? FontWeight.w500 : FontWeight.normal,
                                    ),
                                  )
                                : null,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$divCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            selected: isSelected,
                            selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            selectedColor: Theme.of(context).primaryColor,
                            onTap: () {
                              setState(() {
                                _selectedClassId = cls['id'];
                                _selectedClassCourseIdsToUnassign.clear();
                              });
                            },
                          );
                        },
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
                    Icon(Icons.class_rounded, size: 16 * scale, color: Theme.of(context).primaryColor),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        _selectedClassId == null
                            ? 'Select Class'
                            : 'Class: ${selectedClassNode?['name'] ?? ''}',
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

        // --- Right Panel: Division List with Multi-Assign & Multi-Unassign ---
        final coursesPanel = Column(
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
                  'Division',
                  style: AppTheme.getFontStyle(fontSize: isCompact ? (14 * scale) : 18, fontWeight: FontWeight.bold),
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
                          onTap: _showCreateCourseDialog,
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
                          onTap: _showManageCoursesDialog,
                          child: Padding(
                            padding: EdgeInsets.all(8 * scale),
                            child: Icon(Icons.settings_rounded, color: isDark ? Colors.white : Colors.black87, size: 20 * scale),
                          ),
                        ),
                      ),
                      if (_selectedClassId != null) ...[
                        SizedBox(width: 8 * scale),
                        Material(
                          color: const Color(0xFF043927),
                          borderRadius: BorderRadius.circular(10 * scale),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10 * scale),
                            onTap: _assignMultipleCoursesToSelectedClass,
                            child: Padding(
                              padding: EdgeInsets.all(8 * scale),
                              child: Icon(Icons.library_add_rounded, color: Colors.white, size: 20 * scale),
                            ),
                          ),
                        ),
                      ],
                      if (_selectedClassCourseIdsToUnassign.isNotEmpty) ...[
                        SizedBox(width: 8 * scale),
                        Material(
                          color: Colors.orange.shade800,
                          borderRadius: BorderRadius.circular(10 * scale),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10 * scale),
                            onTap: _unassignSelectedCourses,
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
                        onPressed: _showCreateCourseDialog,
                        icon: const Icon(Icons.add_rounded, size: 19),
                        label: const Text('Create Global Division'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0D6B4E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _showManageCoursesDialog,
                        icon: const Icon(Icons.settings_rounded, size: 19),
                        label: const Text('Manage Division'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF0D6B4E),
                          side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFF0D6B4E).withAlpha(120), width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                      if (_selectedClassId != null)
                        FilledButton.icon(
                          onPressed: _assignMultipleCoursesToSelectedClass,
                          icon: const Icon(Icons.library_add_rounded, size: 19),
                          label: const Text('Assign Divisions (Multi)'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF043927),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                      if (_selectedClassCourseIdsToUnassign.isNotEmpty)
                        FilledButton.icon(
                          onPressed: _unassignSelectedCourses,
                          icon: const Icon(Icons.link_off_rounded, size: 19),
                          label: Text('Unassign (${_selectedClassCourseIdsToUnassign.length})'),
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

            // Select All Header Bar for assigned divisions list
            if (_selectedClassId != null && assignedCourses.isNotEmpty) ...[
              Row(
                children: [
                  Checkbox(
                    activeColor: AppTheme.primaryColor,
                    value: allAssignedSelected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedClassCourseIdsToUnassign.addAll(
                            assignedCourses.map((c) => c['class_course_id'].toString()),
                          );
                        } else {
                          _selectedClassCourseIdsToUnassign.clear();
                        }
                      });
                    },
                  ),
                  Text(
                    'Select All Assigned (${assignedCourses.length})',
                    style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: isCompact ? (11 * scale) : 13),
                  ),
                ],
              ),
              SizedBox(height: 4 * scale),
            ],

            Expanded(
              child: _selectedClassId == null
                  ? Center(child: Text('Select a Class to manage division.', style: AppTheme.getFontStyle(color: Colors.grey, fontSize: isCompact ? (12 * scale) : 13)))
                  : assignedCourses.isEmpty
                      ? Center(child: Text('No division assigned to this class yet.', style: AppTheme.getFontStyle(color: Colors.grey, fontSize: isCompact ? (12 * scale) : 13)))
                      : ListView.builder(
                          itemCount: assignedCourses.length,
                          itemBuilder: (context, index) {
                            final course = assignedCourses[index];
                            final ccId = course['class_course_id'].toString();
                            final isChecked = _selectedClassCourseIdsToUnassign.contains(ccId);

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
                                            _selectedClassCourseIdsToUnassign.add(ccId);
                                          } else {
                                            _selectedClassCourseIdsToUnassign.remove(ccId);
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
                                            course['name'] ?? '',
                                            style: AppTheme.getFontStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: isCompact ? (13 * scale) : 16,
                                            ),
                                          ),
                                          SizedBox(height: 2 * scale),
                                          Text(
                                            course['description'] ?? 'No description',
                                            style: TextStyle(fontSize: isCompact ? (11 * scale) : 14),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 4 * scale),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.link_off_rounded, color: Colors.orange, size: isCompact ? (18 * scale) : 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: context.tr('unassign_from_class'),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                title: Text(context.tr('unassign_course_title')),
                                                content: Text(context.tr('unassign_course_confirm')),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('cancel'))),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                                    onPressed: () => Navigator.pop(c, true), 
                                                    child: Text(context.tr('unassign'))
                                                  ),
                                                ],
                                              )
                                            );
                                            if (confirm == true) {
                                              setState(() => _isLoading = true);
                                              await widget.repository.removeCourseFromClass(course['class_course_id']);
                                              _loadData();
                                            }
                                          },
                                        ),
                                        SizedBox(width: 6 * scale),
                                        IconButton(
                                          icon: Icon(Icons.edit_rounded, color: Colors.blue.shade700, size: isCompact ? (18 * scale) : 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: context.tr('edit'),
                                          onPressed: () {
                                            _editCourse({
                                              'id': course['course_id'],
                                              'name': course['name'],
                                              'description': course['description'],
                                            });
                                          },
                                        ),
                                        SizedBox(width: 6 * scale),
                                        IconButton(
                                          icon: Icon(Icons.delete_rounded, color: Colors.red, size: isCompact ? (18 * scale) : 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: context.tr('delete'),
                                          onPressed: () {
                                            _deleteCourse({
                                              'id': course['course_id'],
                                              'name': course['name'],
                                            });
                                          },
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
          return coursesPanel;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 1, child: classPanel),
            const SizedBox(width: 24),
            Expanded(flex: 2, child: coursesPanel),
          ],
        );
      },
    );
  }
}
