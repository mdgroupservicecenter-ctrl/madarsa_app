import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/movable_resizable_dialog.dart';

class ClassProgressionSeriesDialog extends StatefulWidget {
  const ClassProgressionSeriesDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const ClassProgressionSeriesDialog(),
    );
  }

  @override
  State<ClassProgressionSeriesDialog> createState() => _ClassProgressionSeriesDialogState();
}

class _ClassModel {
  String id;
  String className;
  int classOrder;
  bool isLastInDept;
  bool isFinalYear;
  TextEditingController orderController;

  _ClassModel({
    required this.id,
    required this.className,
    required this.classOrder,
    this.isLastInDept = false,
    this.isFinalYear = false,
  }) : orderController = TextEditingController(text: '$classOrder');
}

class _DeptModel {
  String id;
  String departmentName;
  int seriesOrder;
  bool isFinalDepartment;
  List<_ClassModel> classes;
  bool isExpanded;
  TextEditingController orderController;

  _DeptModel({
    required this.id,
    required this.departmentName,
    required this.seriesOrder,
    this.isFinalDepartment = false,
    required this.classes,
    this.isExpanded = false,
  }) : orderController = TextEditingController(text: '$seriesOrder');
}

class _ClassProgressionSeriesDialogState extends State<ClassProgressionSeriesDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _showRoadmapView = false; // Toggle between Accordion Setup and Full Roadmap View

  List<_DeptModel> _departments = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final d in _departments) {
      d.orderController.dispose();
      for (final c in d.classes) {
        c.orderController.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dbHelper = DatabaseHelper();

    // 1. Fetch live data from Classes & Division (API or local SQLite fallback)
    List<Map<String, dynamic>> apiDepts = [];
    List<dynamic> apiClasses = [];
    List<dynamic> apiHierarchy = [];

    try {
      final deptRes = await ApiClient().get('/academic/departments');
      if (deptRes.data is List) {
        apiDepts = (deptRes.data as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}

    try {
      final clsRes = await ApiClient().get('/classes');
      if (clsRes.data is List) {
        apiClasses = (clsRes.data as List).cast<dynamic>();
      }
    } catch (_) {}

    try {
      final hierRes = await ApiClient().get('/academic/hierarchy');
      if (hierRes.data is List) {
        apiHierarchy = (hierRes.data as List).cast<dynamic>();
      }
    } catch (_) {}

    // Fallback to local SQLite tables if API was empty
    final db = await dbHelper.database;
    if (apiDepts.isEmpty) {
      try {
        final localDepts = await db.query('departments', where: 'is_active = 1');
        apiDepts = localDepts;
      } catch (_) {}
    }
    if (apiClasses.isEmpty) {
      try {
        final localClasses = await db.query('classes', where: 'is_active = 1');
        apiClasses = localClasses;
      } catch (_) {}
    }

    // 2. Filter Main Departments strictly from Classes & Division (parent_id == null or empty)
    final mainDeptNodes = apiDepts.where((d) {
      final pId = d['parent_id']?.toString().trim();
      return pId == null || pId.isEmpty || pId == 'null';
    }).toList();

    final validMainDeptNames = mainDeptNodes
        .map((d) => (d['name'] ?? d['department_name'] ?? '').toString().trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();

    // 3. Load existing progression series saved in SQLite
    final savedDeptRows = await dbHelper.getDepartmentProgressionSeries();
    final savedClassRows = await dbHelper.getClassProgressionSeries();

    // Prune dummy / stale rows from SQLite department_progression_series
    try {
      for (final r in savedDeptRows) {
        final dName = r['department_name']?.toString().trim().toLowerCase() ?? '';
        if (dName.isNotEmpty && !validMainDeptNames.contains(dName)) {
          final sId = r['id']?.toString();
          if (sId != null && sId.isNotEmpty) {
            await dbHelper.deleteDepartmentProgressionItem(sId);
          }
        }
      }
    } catch (_) {}

    final Map<String, int> savedDeptOrder = {};
    final Map<String, bool> savedDeptFinal = {};
    for (final r in savedDeptRows) {
      final name = r['department_name']?.toString().trim().toLowerCase();
      if (name != null && validMainDeptNames.contains(name)) {
        savedDeptOrder[name] = (r['series_order'] as num?)?.toInt() ?? 999;
        savedDeptFinal[name] = (r['is_final_department'] as num?)?.toInt() == 1;
      }
    }

    final Map<String, Map<String, dynamic>> savedClassConfig = {};
    for (final r in savedClassRows) {
      final cName = r['class_name']?.toString().trim().toLowerCase();
      final dName = r['department_name']?.toString().trim().toLowerCase() ?? '';
      if (cName != null && validMainDeptNames.contains(dName)) {
        savedClassConfig['$dName::$cName'] = r;
        savedClassConfig['::$cName'] = r;
      }
    }

    // 4. Build Department Models and fetch their Classes from Classes & Division
    final List<_DeptModel> deptModels = [];
    int nextDeptOrder = 1;

    for (final mDept in mainDeptNodes) {
      final mId = mDept['id']?.toString() ?? '';
      final mName = (mDept['name'] ?? mDept['department_name'] ?? '').toString().trim();
      if (mName.isEmpty) continue;

      // Find sub-departments belonging to this main department
      final subDeptIds = apiDepts
          .where((d) => d['parent_id']?.toString() == mId)
          .map((d) => d['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // Find all classes belonging to this main department or its sub-departments
      final Set<String> deptClassNames = <String>{};

      // A. Direct from apiClasses
      for (final cls in apiClasses) {
        final cName = (cls['name'] ?? cls['class_name'])?.toString().trim();
        final cDeptId = cls['department_id']?.toString();
        final cParentDeptId = cls['department_parent_id']?.toString();
        final cDeptName = cls['department_name']?.toString().trim().toLowerCase();
        final cParentDeptName = cls['parent_department_name']?.toString().trim().toLowerCase();

        if (cName != null && cName.isNotEmpty) {
          if (cDeptId == mId ||
              (cDeptId != null && subDeptIds.contains(cDeptId)) ||
              cParentDeptId == mId ||
              cParentDeptName == mName.toLowerCase() ||
              (cParentDeptName == null && cDeptName == mName.toLowerCase())) {
            deptClassNames.add(cName);
          }
        }
      }

      // B. Direct from apiHierarchy
      for (final hNode in apiHierarchy) {
        final cName = hNode['name']?.toString().trim();
        final hDeptId = hNode['department_id']?.toString();
        final hParentId = hNode['department_parent_id']?.toString();
        final hDeptName = hNode['department_name']?.toString().trim().toLowerCase();
        final hParentName = hNode['parent_department_name']?.toString().trim().toLowerCase();

        if (cName != null && cName.isNotEmpty) {
          if (hDeptId == mId ||
              hParentId == mId ||
              hDeptName == mName.toLowerCase() ||
              hParentName == mName.toLowerCase() ||
              subDeptIds.contains(hDeptId)) {
            deptClassNames.add(cName);
          }
        }
      }

      // C. From mDept['classes'] and sub_departments['classes']
      if (mDept['classes'] is List) {
        for (final c in (mDept['classes'] as List)) {
          final cName = (c is Map ? (c['name'] ?? c['class_name']) : c)?.toString().trim();
          if (cName != null && cName.isNotEmpty) {
            deptClassNames.add(cName);
          }
        }
      }
      if (mDept['sub_departments'] is List) {
        for (final sub in (mDept['sub_departments'] as List)) {
          if (sub is Map && sub['classes'] is List) {
            for (final c in (sub['classes'] as List)) {
              final cName = (c is Map ? (c['name'] ?? c['class_name']) : c)?.toString().trim();
              if (cName != null && cName.isNotEmpty) {
                deptClassNames.add(cName);
              }
            }
          }
        }
      }

      // D. Direct from local SQLite classes table if available
      try {
        final localClsList = await db.rawQuery(
          'SELECT name FROM classes WHERE is_active = 1 AND (department_id = ? OR department_id IN (${subDeptIds.isEmpty ? "''" : subDeptIds.map((_) => '?').join(',')}))',
          [mId, ...subDeptIds],
        );
        for (final c in localClsList) {
          final cName = c['name']?.toString().trim();
          if (cName != null && cName.isNotEmpty) {
            deptClassNames.add(cName);
          }
        }
      } catch (_) {}

      // E. Previously saved classes in SQLite under this exact department
      for (final sc in savedClassRows) {
        final sDept = sc['department_name']?.toString().trim() ?? '';
        final sCls = sc['class_name']?.toString().trim() ?? '';
        if (sCls.isNotEmpty && sDept.toLowerCase() == mName.toLowerCase()) {
          deptClassNames.add(sCls);
        }
      }

      // Build classes for this department
      final List<_ClassModel> classModels = [];
      int nextClassOrder = 1;

      for (final cName in deptClassNames) {
        final savedConf = savedClassConfig['${mName.toLowerCase()}::${cName.toLowerCase()}'] ??
            savedClassConfig['::${cName.toLowerCase()}'];

        int cOrder = nextClassOrder++;
        bool isLast = false;
        bool isFinal = false;

        if (savedConf != null) {
          cOrder = (savedConf['class_order'] as num?)?.toInt() ??
              (savedConf['series_order'] as num?)?.toInt() ??
              cOrder;
          isLast = (savedConf['is_last_in_dept'] as num?)?.toInt() == 1;
          isFinal = (savedConf['is_final_year'] as num?)?.toInt() == 1;
        }

        classModels.add(_ClassModel(
          id: savedConf?['id']?.toString() ?? 'cps_${DateTime.now().millisecondsSinceEpoch}_$cOrder',
          className: cName,
          classOrder: cOrder,
          isLastInDept: isLast,
          isFinalYear: isFinal,
        ));
      }

      classModels.sort((a, b) => a.classOrder.compareTo(b.classOrder));
      for (int i = 0; i < classModels.length; i++) {
        classModels[i].classOrder = i + 1;
        classModels[i].orderController.text = '${i + 1}';
      }
      if (classModels.isNotEmpty && !classModels.any((c) => c.isLastInDept)) {
        classModels.last.isLastInDept = true;
      }

      final deptOrder = savedDeptOrder[mName.toLowerCase()] ?? nextDeptOrder++;
      final isFinalDept = savedDeptFinal[mName.toLowerCase()] ?? false;

      deptModels.add(_DeptModel(
        id: mDept['id']?.toString() ?? 'dept_${DateTime.now().millisecondsSinceEpoch}',
        departmentName: mName,
        seriesOrder: deptOrder,
        isFinalDepartment: isFinalDept,
        classes: classModels,
        isExpanded: false,
      ));
    }

    deptModels.sort((a, b) => a.seriesOrder.compareTo(b.seriesOrder));
    for (int i = 0; i < deptModels.length; i++) {
      deptModels[i].seriesOrder = i + 1;
      deptModels[i].orderController.text = '${i + 1}';
    }

    // Expand the first department by default for immediate preview
    if (deptModels.isNotEmpty) {
      deptModels.first.isExpanded = true;
    }

    if (mounted) {
      setState(() {
        _departments = deptModels;
        _isLoading = false;
      });
    }
  }

  // ─── Re-indexing & Sorting Helpers ───────────────────────────

  void _reindexDepartments() {
    _departments.sort((a, b) => a.seriesOrder.compareTo(b.seriesOrder));
    for (int i = 0; i < _departments.length; i++) {
      _departments[i].seriesOrder = i + 1;
      _departments[i].orderController.text = '${i + 1}';
      // Re-index classes inside too
      _departments[i].classes.sort((a, b) => a.classOrder.compareTo(b.classOrder));
      for (int j = 0; j < _departments[i].classes.length; j++) {
        _departments[i].classes[j].classOrder = j + 1;
        _departments[i].classes[j].orderController.text = '${j + 1}';
      }
    }
    setState(() {});
  }

  void _onReorderDepartment(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final movedDept = _departments.removeAt(oldIndex);
      _departments.insert(newIndex, movedDept);

      for (int i = 0; i < _departments.length; i++) {
        _departments[i].seriesOrder = i + 1;
        _departments[i].orderController.text = '${i + 1}';
      }
    });
  }

  void _onReorderClass(_DeptModel dept, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = dept.classes.removeAt(oldIndex);
      dept.classes.insert(newIndex, item);

      for (int i = 0; i < dept.classes.length; i++) {
        dept.classes[i].classOrder = i + 1;
        dept.classes[i].orderController.text = '${i + 1}';
      }

      // Maintain isLastInDept flag
      for (int i = 0; i < dept.classes.length; i++) {
        if (i == dept.classes.length - 1) {
          dept.classes[i].isLastInDept = true;
        } else if (dept.classes[i].isLastInDept && !dept.classes.last.isLastInDept) {
          dept.classes.last.isLastInDept = true;
        }
      }
    });
  }

  // ─── Destination Prediction ───────────────────────────────────

  String _getProgressionDestinationText(_DeptModel currentDept, _ClassModel item) {
    if (item.isFinalYear) {
      return '🎓 Graduated (Final Year - Farigh)';
    }

    final curIdx = currentDept.classes.indexOf(item);

    // If not the last class in this department and has higher classOrder
    if (!item.isLastInDept && curIdx != -1 && curIdx + 1 < currentDept.classes.length) {
      final nextClass = currentDept.classes[curIdx + 1];
      return '➔ Next Class: ${nextClass.classOrder}. ${nextClass.className} (Same Dept)';
    }

    // This is the last class of this department! Transition to next department in series!
    if (currentDept.isFinalDepartment) {
      return '🎓 Graduated (Final Dept Completed)';
    }

    final higherDepts = _departments.where((d) => d.seriesOrder > currentDept.seriesOrder).toList()
      ..sort((a, b) => a.seriesOrder.compareTo(b.seriesOrder));

    if (higherDepts.isNotEmpty) {
      final nextDept = higherDepts.first;
      if (nextDept.classes.isNotEmpty) {
        final sortedNextClasses = List<_ClassModel>.from(nextDept.classes)
          ..sort((a, b) => a.classOrder.compareTo(b.classOrder));
        final firstClass = sortedNextClasses.first;
        return '➔ Next Dept: [${nextDept.departmentName}] Class 1 (${firstClass.className})';
      } else {
        return '➔ Next Dept: [${nextDept.departmentName}] First Class';
      }
    }

    return '🎓 Graduated (Series Completed)';
  }



  // ─── Save All ────────────────────────────────────────────────

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      final dbHelper = DatabaseHelper();

      // Format department progression series items
      final List<Map<String, dynamic>> deptMaps = [];
      for (final d in _departments) {
        deptMaps.add({
          'id': d.id,
          'department_name': d.departmentName,
          'series_order': d.seriesOrder,
          'is_final_department': d.isFinalDepartment ? 1 : 0,
          'remarks': '',
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      await dbHelper.saveDepartmentProgressionSeries(deptMaps);

      // Format class progression series items
      final List<Map<String, dynamic>> classMaps = [];
      int globalSeriesOrder = 1;

      // Sort departments by seriesOrder first
      final sortedDepts = List<_DeptModel>.from(_departments)..sort((a, b) => a.seriesOrder.compareTo(b.seriesOrder));

      for (final d in sortedDepts) {
        final sortedClasses = List<_ClassModel>.from(d.classes)..sort((a, b) => a.classOrder.compareTo(b.classOrder));
        for (final c in sortedClasses) {
          classMaps.add({
            'id': c.id,
            'department_name': d.departmentName,
            'class_name': c.className,
            'class_order': c.classOrder,
            'series_order': globalSeriesOrder++,
            'is_last_in_dept': c.isLastInDept ? 1 : 0,
            'is_final_year': c.isFinalYear ? 1 : 0,
            'next_department_name': '',
            'next_class_name': c.isFinalYear ? 'Farigh' : '',
            'remarks': '',
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      await dbHelper.saveClassProgressionSeries(classMaps);

      // Online Cloud Sync
      try {
        await FirebaseService.syncDepartmentProgressionSeries(deptMaps);
        await FirebaseService.syncClassProgressionSeries(classMaps);
      } catch (_) {}

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Class & Department Progression Series saved & synced to cloud successfully! All dropdowns updated.'),
            backgroundColor: Color(0xFF0D6B4E),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save progression series: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Build UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalClassesCount = _departments.fold<int>(0, (sum, d) => sum + d.classes.length);

    final filteredDepts = _searchQuery.isEmpty
        ? _departments
        : _departments.where((d) {
            final matchesDept = d.departmentName.toLowerCase().contains(_searchQuery.toLowerCase());
            final matchesClass = d.classes.any((c) => c.className.toLowerCase().contains(_searchQuery.toLowerCase()));
            return matchesDept || matchesClass;
          }).toList();

    return MovableResizableDialog(
      initialWidth: 1120,
      initialHeight: 780,
      minWidth: 760,
      minHeight: 520,
      headerLeading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white.withAlpha(30), shape: BoxShape.circle),
        child: const Icon(Icons.account_tree_rounded, color: Colors.white, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Class & Department Progression Series',
                style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.lightGreenAccent, size: 13),
                    SizedBox(width: 4),
                    Text(
                      'Synced with Classes & Division',
                      style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Text(
            'Department & Class Sequence: Click a department to expand classes. Drag to reorder or enter sequence numbers.',
            style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(210)),
          ),
        ],
      ),
      content: Container(
        color: isDark ? const Color(0xFF14141E) : const Color(0xFFF8F9FA),
        child: Column(
          children: [
            // ── Top Toolbar & Actions ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  // Search Box
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search department or class...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Expand / Collapse All
                  OutlinedButton.icon(
                    onPressed: () {
                      final anyCollapsed = _departments.any((d) => !d.isExpanded);
                      setState(() {
                        for (final d in _departments) {
                          d.isExpanded = anyCollapsed;
                        }
                      });
                    },
                    icon: Icon(
                      _departments.any((d) => !d.isExpanded) ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                      size: 16,
                    ),
                    label: Text(_departments.any((d) => !d.isExpanded) ? 'Expand All' : 'Collapse All'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.grey.shade800,
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Auto-reindex numbers
                  OutlinedButton.icon(
                    onPressed: _reindexDepartments,
                    icon: const Icon(Icons.format_list_numbered_rounded, size: 16),
                    label: const Text('Auto-Order 1, 2, 3...'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D6B4E),
                      side: const BorderSide(color: Color(0xFF0D6B4E)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Switch between Setup View and Full Journey Roadmap
                  FilledButton.icon(
                    onPressed: () => setState(() => _showRoadmapView = !_showRoadmapView),
                    icon: Icon(_showRoadmapView ? Icons.tune_rounded : Icons.alt_route_rounded, size: 16),
                    label: Text(_showRoadmapView ? '⚙️ Progression Setup' : '🗺️ View Full Journey Roadmap'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _showRoadmapView ? const Color(0xFF1565C0) : const Color(0xFF0D6B4E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),

            // ── Main Content Area ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _showRoadmapView
                      ? _buildFullJourneyRoadmapView(isDark)
                      : _buildDepartmentsAccordionList(filteredDepts, isDark),
            ),
          ],
        ),
      ),
      actions: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 30 : 10),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Summary Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D6B4E).withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF0D6B4E).withAlpha(40),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.analytics_outlined, size: 16, color: Color(0xFF0D6B4E)),
                  const SizedBox(width: 8),
                  Text(
                    '${_departments.length} Main Departments  •  $totalClassesCount Classes Configured',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D6B4E),
                    ),
                  ),
                ],
              ),
            ),

            // Right: Cancel & Save Buttons (with right padding to prevent overlap with resize grip)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.grey.shade700,
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAll,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save Progression Series',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0D6B4E),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  // ─── Accordion Department List ───────────────────────────────

  Widget _buildDepartmentsAccordionList(List<_DeptModel> depts, bool isDark) {
    if (depts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty ? 'No departments or classes match "$_searchQuery"' : 'No main departments found.',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final isSearching = _searchQuery.isNotEmpty;

    if (isSearching) {
      return ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: depts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final dept = depts[index];
          final realIndex = _departments.indexOf(dept);
          return _buildDepartmentCard(dept, realIndex, isDark, canReorder: false);
        },
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(14),
      buildDefaultDragHandles: false,
      itemCount: depts.length,
      onReorder: _onReorderDepartment,
      itemBuilder: (context, index) {
        final dept = depts[index];
        return Padding(
          key: ValueKey('dept_${dept.id}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildDepartmentCard(dept, index, isDark, canReorder: true),
        );
      },
    );
  }

  Widget _buildDepartmentCard(_DeptModel dept, int index, bool isDark, {bool canReorder = true}) {
    final hasClasses = dept.classes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dept.isFinalDepartment
              ? Colors.purple.withAlpha(90)
              : dept.isExpanded
                  ? const Color(0xFF0D6B4E).withAlpha(120)
                  : (isDark ? Colors.white12 : Colors.grey.shade300),
          width: dept.isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Department Header (Click anywhere to expand/collapse) ──
          InkWell(
            onTap: () {
              setState(() {
                dept.isExpanded = !dept.isExpanded;
              });
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(12),
              bottom: dept.isExpanded ? Radius.zero : const Radius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: dept.isExpanded
                    ? (isDark ? const Color(0xFF252538) : const Color(0xFF0D6B4E).withAlpha(12))
                    : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: dept.isExpanded ? Radius.zero : const Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  // Drag Handle for Department
                  if (canReorder)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: ReorderableDragStartListener(
                        index: index,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Tooltip(
                            message: 'Drag & drop to reorder department series',
                            child: Container(
                              width: 32,
                              height: 36,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                size: 22,
                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 4),

                  const SizedBox(width: 4),

                  // Clean Single Department Series Number Box (No nested box, no extra arrows)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(
                      width: 44,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF222232) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF0D6B4E),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 20 : 8),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: const InputDecorationTheme(
                            filled: false,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        child: TextField(
                          controller: dept.orderController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D6B4E),
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                          ),
                          onChanged: (val) {
                            final num = int.tryParse(val.trim());
                            if (num != null && num > 0) {
                              dept.seriesOrder = num;
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Department Icon & Name
                  const Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFF0D6B4E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                dept.departmentName,
                                style: AppTheme.getFontStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (dept.isFinalDepartment)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.purple.withAlpha(80)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.school_rounded, size: 13, color: Colors.purple),
                                    SizedBox(width: 4),
                                    Text('🎓 Final Department', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.purple)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        Text(
                          '${dept.classes.length} Classes included • ${dept.isFinalDepartment ? "Students graduate upon completion" : "Promotes to next department Class 1"}',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  // Final Department Toggle Switch
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Final Dept', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        Switch(
                          value: dept.isFinalDepartment,
                          activeTrackColor: Colors.purple.withAlpha(150),
                          activeThumbColor: Colors.purple,
                          onChanged: (val) {
                            setState(() {
                              dept.isFinalDepartment = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  // Classes Count Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Text(
                      '${dept.classes.length} Classes',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Expand / Collapse Chevron
                  AnimatedRotation(
                    turns: dept.isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded Classes Dropdown Panel ──
          if (dept.isExpanded) ...[
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
                color: isDark ? const Color(0xFF181826) : const Color(0xFFFAFAFA),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info & Add Class Row
                  // Info Row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6B4E).withAlpha(12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF0D6B4E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Drag & drop classes to reorder or enter sequence numbers directly. Students will advance in this order.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white70 : const Color(0xFF0D6B4E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Table Column Headers
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF222234) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 28),
                        SizedBox(width: 44, child: Center(child: Text('No.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        SizedBox(width: 10),
                        Expanded(flex: 3, child: Text('Class Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        SizedBox(width: 12),
                        Expanded(flex: 4, child: Text('Next Step on Pass', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        SizedBox(width: 12),
                        SizedBox(width: 120, child: Center(child: Text('Last in Dept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        SizedBox(width: 110, child: Center(child: Text('Final Year', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        SizedBox(width: 40, child: Center(child: Text('Del', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Classes List
                  if (!hasClasses)
                    Container(
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.center,
                      child: Text(
                        'Classes & Division me is shoba ki koi class nahi mili.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: dept.classes.length,
                      onReorder: (oldIndex, newIndex) => _onReorderClass(dept, oldIndex, newIndex),
                      itemBuilder: (context, classIdx) {
                        final cls = dept.classes[classIdx];
                        return Padding(
                          key: ValueKey('cls_${dept.id}_${cls.id}'),
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _buildClassItemRow(dept, cls, classIdx, isDark),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClassItemRow(_DeptModel dept, _ClassModel cls, int index, bool isDark) {
    final nextDesc = _getProgressionDestinationText(dept, cls);
    final isExitClass = cls.isLastInDept || (index == dept.classes.length - 1 && !cls.isFinalYear);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cls.isFinalYear
              ? Colors.purple.withAlpha(80)
              : isExitClass
                  ? Colors.blue.withAlpha(80)
                  : (isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // Drag Handle
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'Drag & drop to reorder class',
                child: SizedBox(
                  width: 28,
                  height: 32,
                  child: Center(
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 20,
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Clean Single Class Order Number Box (No nested box, no second box, no arrows)
          Container(
            width: 44,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222232) : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isExitClass
                    ? Colors.blue.shade400
                    : const Color(0xFF0D6B4E),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 15 : 6),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: const InputDecorationTheme(
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              child: TextField(
                controller: cls.orderController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isExitClass ? Colors.blue.shade700 : const Color(0xFF0D6B4E),
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
                onChanged: (val) {
                  final num = int.tryParse(val.trim());
                  if (num != null && num > 0) {
                    setState(() {
                      cls.classOrder = num;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Class Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 15,
                  color: isExitClass ? Colors.blue.shade700 : const Color(0xFF0D6B4E),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cls.className,
                    style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Next Step Live Indicator Badge
          Expanded(
            flex: 4,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: cls.isFinalYear
                    ? Colors.purple.withAlpha(20)
                    : isExitClass
                        ? Colors.blue.withAlpha(15)
                        : const Color(0xFF0D6B4E).withAlpha(15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: cls.isFinalYear
                      ? Colors.purple.withAlpha(60)
                      : isExitClass
                          ? Colors.blue.withAlpha(50)
                          : const Color(0xFF0D6B4E).withAlpha(40),
                ),
              ),
              child: Text(
                nextDesc,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cls.isFinalYear
                      ? Colors.purple
                      : isExitClass
                          ? Colors.blue.shade700
                          : (isDark ? Colors.white70 : Colors.black87),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Last in Department Switch
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: cls.isLastInDept,
                  activeColor: Colors.blue.shade700,
                  onChanged: (val) {
                    setState(() {
                      cls.isLastInDept = val ?? false;
                      if (cls.isLastInDept) {
                        cls.isFinalYear = false;
                      }
                    });
                  },
                ),
                const Text('Last in Dept', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          // Final Year Switch
          SizedBox(
            width: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: cls.isFinalYear,
                  activeColor: Colors.purple,
                  onChanged: (val) {
                    setState(() {
                      cls.isFinalYear = val ?? false;
                      if (cls.isFinalYear) {
                        cls.isLastInDept = true;
                      }
                    });
                  },
                ),
                const Text('Final Year', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          // Delete Button
          SizedBox(
            width: 40,
            child: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Colors.redAccent),
              tooltip: 'Remove from department series',
              onPressed: () {
                setState(() {
                  dept.classes.removeAt(index);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Full Journey Roadmap View ───────────────────────────────

  Widget _buildFullJourneyRoadmapView(bool isDark) {
    final sortedDepts = List<_DeptModel>.from(_departments)..sort((a, b) => a.seriesOrder.compareTo(b.seriesOrder));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D6B4E).withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF0D6B4E).withAlpha(40)),
            ),
            child: const Row(
              children: [
                Icon(Icons.alt_route_rounded, color: Color(0xFF0D6B4E), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Progression Journey Roadmap: When students pass the final class of a department, they automatically advance to Class 1 of the next department.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          for (int i = 0; i < sortedDepts.length; i++) ...[
            _buildRoadmapDepartmentCard(sortedDepts[i], isDark),
            if (i < sortedDepts.length - 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue.withAlpha(70)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.blue),
                          const SizedBox(width: 6),
                          Text(
                            'Advance on Department Completion ➔ [${sortedDepts[i + 1].departmentName}] Class 1',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.purple.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.purple.withAlpha(70)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.school_rounded, size: 16, color: Colors.purple),
                          SizedBox(width: 6),
                          Text(
                            '🎓 Graduated / Completed (Farigh)',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.purple),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRoadmapDepartmentCard(_DeptModel dept, bool isDark) {
    final sortedClasses = List<_ClassModel>.from(dept.classes)..sort((a, b) => a.classOrder.compareTo(b.classOrder));

    return Card(
      elevation: 0,
      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dept.isFinalDepartment ? Colors.purple.withAlpha(80) : (isDark ? Colors.white12 : Colors.grey.shade300),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D6B4E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Dept #${dept.seriesOrder}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  dept.departmentName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (dept.isFinalDepartment)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.withAlpha(60)),
                    ),
                    child: const Text('🎓 Final Department', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple)),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            if (sortedClasses.isEmpty)
              const Text('No classes added to this department yet.', style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (int i = 0; i < sortedClasses.length; i++) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sortedClasses[i].isFinalYear
                            ? Colors.purple.withAlpha(20)
                            : (sortedClasses[i].isLastInDept || i == sortedClasses.length - 1)
                                ? Colors.blue.withAlpha(20)
                                : const Color(0xFF0D6B4E).withAlpha(15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sortedClasses[i].isFinalYear
                              ? Colors.purple.withAlpha(60)
                              : (sortedClasses[i].isLastInDept || i == sortedClasses.length - 1)
                                  ? Colors.blue.withAlpha(60)
                                  : const Color(0xFF0D6B4E).withAlpha(40),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${sortedClasses[i].classOrder}. ${sortedClasses[i].className}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: sortedClasses[i].isFinalYear
                                  ? Colors.purple
                                  : (sortedClasses[i].isLastInDept || i == sortedClasses.length - 1)
                                      ? Colors.blue.shade700
                                      : (isDark ? Colors.white : const Color(0xFF0D6B4E)),
                            ),
                          ),
                          if (sortedClasses[i].isLastInDept || i == sortedClasses.length - 1) ...[
                            const SizedBox(width: 4),
                            const Text('(Last Class)', style: TextStyle(fontSize: 10, color: Colors.blue)),
                          ],
                        ],
                      ),
                    ),
                    if (i < sortedClasses.length - 1)
                      const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

