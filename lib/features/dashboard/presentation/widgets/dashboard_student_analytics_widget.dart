import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/student_form_options_settings.dart';
import '../../../fees/data/models/fee_models.dart';
import '../../../fees/data/repositories/fees_repository.dart';
import '../../../students/data/models/student_model.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../students/presentation/bloc/students_bloc.dart';
import '../../../students/presentation/screens/student_profile_screen.dart';

class DashboardStudentAnalyticsWidget extends StatefulWidget {
  final bool isDark;
  final int totalStudentsFallback;
  final String? attendancePercentageFallback;
  final void Function(String module)? onNavigate;
  final double? fixedHeight;
  final List<Student>? initialStudents;

  const DashboardStudentAnalyticsWidget({
    super.key,
    required this.isDark,
    this.totalStudentsFallback = 0,
    this.attendancePercentageFallback,
    this.onNavigate,
    this.fixedHeight,
    this.initialStudents,
  });

  @override
  State<DashboardStudentAnalyticsWidget> createState() => _DashboardStudentAnalyticsWidgetState();
}

class _DashboardStudentAnalyticsWidgetState extends State<DashboardStudentAnalyticsWidget> {
  List<Student> _students = [];
  Map<String, StudentFeeSummary> _feeSummaryMap = {};
  bool _isLoading = true;

  // Interactive Tab & Filter State
  // 0: Overview & Fees, 1: By Location (Village/District/State), 2: By Dept & Class, 3: Student Fee Lookup
  int _selectedTabIndex = 0;
  String _locationType = 'village'; // 'village', 'district', 'state'
  String _selectedLocation = 'All';

  // Multi-tier filtering for Tab 2 (By Dept & Class)
  String _selectedDept = 'All';
  String _selectedSubDept = 'All';
  String _selectedClass = 'All';
  String _selectedDivision = 'All';

  String? _selectedStudentId;

  // Dynamic Custom Genders
  List<String> _customGenders = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialStudents != null) {
      _students = widget.initialStudents!;
      _isLoading = false;
      _syncGendersFromStudents();
      if (_students.isNotEmpty) {
        _selectedStudentId = _students.first.id;
      }
      _loadFeeSummariesOnly();
    } else {
      _loadStudentsData();
    }
    _loadCustomGenders();
  }

  @override
  void didUpdateWidget(covariant DashboardStudentAnalyticsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStudents != oldWidget.initialStudents) {
      _students = widget.initialStudents ?? [];
      _syncGendersFromStudents();
      _loadFeeSummariesOnly();
    }
  }

  Future<void> _loadStudentsData() async {
    try {
      final repo = StudentRepository(ApiClient());
      final feeRepo = FeesRepository(ApiClient());
      final results = await Future.wait([
        repo.getAllStudents(),
        feeRepo.getStudentFeeSummaries().catchError((_) => <StudentFeeSummary>[]),
      ]);
      final studentList = results[0] as List<Student>;
      final feeList = results[1] as List<StudentFeeSummary>;

      final Map<String, StudentFeeSummary> feeMap = {};
      for (final f in feeList) {
        feeMap[f.id] = f;
      }

      if (mounted) {
        setState(() {
          _students = studentList;
          _feeSummaryMap = feeMap;
          _isLoading = false;
          _syncGendersFromStudents();
          if (_students.isNotEmpty && _selectedStudentId == null) {
            _selectedStudentId = _students.first.id;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFeeSummariesOnly() async {
    try {
      final feeRepo = FeesRepository(ApiClient());
      final feeList = await feeRepo.getStudentFeeSummaries();
      final Map<String, StudentFeeSummary> feeMap = {};
      for (final f in feeList) {
        feeMap[f.id] = f;
      }
      if (mounted && feeMap.isNotEmpty) {
        setState(() {
          _feeSummaryMap = feeMap;
        });
      }
    } catch (_) {}
  }

  ({double monthly, double paid, double pending, double expected}) _getStudentFeeMetrics(Student s) {
    StudentFeeSummary? summary = _feeSummaryMap[s.id];
    if (summary == null && s.grNo != null && s.grNo!.trim().isNotEmpty) {
      final targetGr = s.grNo!.trim().toLowerCase();
      final match = _feeSummaryMap.values.where((f) =>
          f.grNo != null && f.grNo!.trim().toLowerCase() == targetGr);
      if (match.isNotEmpty) summary = match.first;
    }

    if (summary != null) {
      final monthly = summary.monthlyFees > 0 ? summary.monthlyFees : (s.monthlyFees ?? 0.0);
      return (
        monthly: monthly,
        paid: summary.totalPaid,
        pending: summary.totalPending,
        expected: summary.totalExpected,
      );
    }

    final monthly = s.monthlyFees ?? 0.0;
    final paid = s.paidFees;
    final pending = s.pendingFees.toDouble();
    final expected = (paid + pending) > 0 ? (paid + pending) : (monthly * 12);
    return (
      monthly: monthly,
      paid: paid,
      pending: pending,
      expected: expected,
    );
  }

  void _syncGendersFromStudents() {
    final set = <String>{..._customGenders};
    for (final s in _students) {
      final g = s.gender?.trim();
      if (g != null && g.isNotEmpty) set.add(g);
    }
    if (set.isNotEmpty) {
      _customGenders = set.toList();
    }
  }

  Future<void> _loadCustomGenders() async {
    try {
      final saved = await StudentFormOptionsSettings.getGenders();
      final set = <String>{};
      for (final g in saved) {
        final clean = g.trim();
        if (clean.isNotEmpty) set.add(clean);
      }
      for (final s in _students) {
        final g = s.gender?.trim();
        if (g != null && g.isNotEmpty) set.add(g);
      }
      if (mounted && set.isNotEmpty) {
        setState(() {
          _customGenders = set.toList();
        });
      }
    } catch (_) {
      _syncGendersFromStudents();
    }
  }

  String _localizeGender(String genderName, BuildContext context) {
    final clean = genderName.trim();
    final lower = clean.toLowerCase();
    if (lower == 'male') {
      return context.tr('male');
    } else if (lower == 'female') {
      return context.tr('female');
    } else if (lower == 'other') {
      final trOther = context.tr('other');
      return trOther != 'other' ? trOther : clean;
    }
    return clean;
  }

  Map<String, int> _getGenderCounts(List<Student> studentList) {
    final Map<String, int> counts = {};
    for (final cg in _customGenders) {
      final clean = cg.trim();
      if (clean.isNotEmpty && !counts.containsKey(clean)) {
        counts[clean] = 0;
      }
    }
    for (final s in studentList) {
      final raw = s.gender?.trim();
      if (raw != null && raw.isNotEmpty) {
        final existingKey = counts.keys.firstWhere(
          (k) => k.toLowerCase() == raw.toLowerCase(),
          orElse: () => '',
        );
        if (existingKey.isNotEmpty) {
          counts[existingKey] = counts[existingKey]! + 1;
        } else {
          counts[raw] = 1;
        }
      }
    }
    return counts;
  }

  String _getGenderDisplayString(List<Student> studentList, BuildContext context) {
    if (studentList.isEmpty) return context.tr('gender_distribution');

    final counts = _getGenderCounts(studentList);
    final activeEntries = counts.entries.where((e) => e.value > 0).toList();

    if (activeEntries.isNotEmpty) {
      return activeEntries
          .map((e) => '${e.value} ${_localizeGender(e.key, context)}')
          .join(' • ');
    }

    if (_customGenders.isNotEmpty) {
      return _customGenders
          .take(3)
          .map((g) => '0 ${_localizeGender(g, context)}')
          .join(' • ');
    }

    return context.tr('gender_distribution');
  }

  String _formatCurrency(double amount, {bool compact = false}) {
    if (compact && amount >= 100000) {
      final inLakhs = amount / 100000;
      return '₹${inLakhs.toStringAsFixed(1)}L';
    }
    final formatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return formatter.format(amount);
  }

  String _getStudentLocationValue(Student s, String type) {
    switch (type) {
      case 'district':
        return s.district?.trim() ?? '';
      case 'state':
        return s.state?.trim() ?? '';
      case 'village':
      default:
        return s.village?.trim() ?? '';
    }
  }

  List<String> _getUniqueLocations(String type) {
    final Set<String> locations = {};
    for (final s in _students) {
      final val = _getStudentLocationValue(s, type);
      if (val.isNotEmpty) {
        locations.add(val);
      }
    }
    final list = locations.toList()..sort();
    return ['All', ...list];
  }

  List<String> _getUniqueDepartments() {
    final Set<String> depts = {};
    for (final s in _students) {
      final d = s.departmentName?.trim();
      if (d != null && d.isNotEmpty) depts.add(d);
    }
    final list = depts.toList()..sort();
    return ['All', ...list];
  }

  List<String> _getUniqueSubDepartments() {
    final Set<String> subDepts = {};
    for (final s in _students) {
      if (_selectedDept != 'All' && s.departmentName?.trim().toLowerCase() != _selectedDept.toLowerCase()) {
        continue;
      }
      if (s.subDepartments != null) {
        for (final sub in s.subDepartments!) {
          final name = sub.subDepartmentName?.trim();
          if (name != null && name.isNotEmpty) subDepts.add(name);
        }
      }
    }
    final list = subDepts.toList()..sort();
    return ['All', ...list];
  }

  List<String> _getUniqueClassesFiltered() {
    final Set<String> classes = {};
    for (final s in _students) {
      if (_selectedDept != 'All' && s.departmentName?.trim().toLowerCase() != _selectedDept.toLowerCase()) {
        continue;
      }
      if (_selectedSubDept != 'All') {
        final matchSub = s.subDepartments?.any((sub) =>
            sub.subDepartmentName?.trim().toLowerCase() == _selectedSubDept.toLowerCase()) ?? false;
        if (!matchSub) continue;
      }
      final c = s.className?.trim();
      if (c != null && c.isNotEmpty) classes.add(c);
      if (s.subDepartments != null) {
        for (final sub in s.subDepartments!) {
          final sc = sub.className?.trim();
          if (sc != null && sc.isNotEmpty) classes.add(sc);
        }
      }
    }
    final list = classes.toList()..sort();
    return ['All', ...list];
  }

  List<String> _getUniqueDivisionsFiltered() {
    final Set<String> divisions = {};
    for (final s in _students) {
      if (_selectedDept != 'All' && s.departmentName?.trim().toLowerCase() != _selectedDept.toLowerCase()) {
        continue;
      }
      if (_selectedSubDept != 'All') {
        final matchSub = s.subDepartments?.any((sub) =>
            sub.subDepartmentName?.trim().toLowerCase() == _selectedSubDept.toLowerCase()) ?? false;
        if (!matchSub) continue;
      }
      if (_selectedClass != 'All') {
        final matchClass = (s.className?.trim().toLowerCase() == _selectedClass.toLowerCase()) ||
            (s.subDepartments?.any((sub) =>
                sub.className?.trim().toLowerCase() == _selectedClass.toLowerCase()) ?? false);
        if (!matchClass) continue;
      }
      final d = s.division?.trim();
      if (d != null && d.isNotEmpty) divisions.add(d);
      if (s.subDepartments != null) {
        for (final sub in s.subDepartments!) {
          final sd = sub.division?.trim();
          if (sd != null && sd.isNotEmpty) divisions.add(sd);
        }
      }
    }
    final list = divisions.toList()..sort();
    return ['All', ...list];
  }

  List<Student> _getFilteredDeptClassStudents() {
    return _students.where((s) {
      if (_selectedDept != 'All') {
        final deptMatch = (s.departmentName?.trim().toLowerCase() == _selectedDept.toLowerCase());
        if (!deptMatch) return false;
      }
      if (_selectedSubDept != 'All') {
        final subMatch = s.subDepartments?.any((sub) =>
            sub.subDepartmentName?.trim().toLowerCase() == _selectedSubDept.toLowerCase()) ?? false;
        if (!subMatch) return false;
      }
      if (_selectedClass != 'All') {
        final classMatch = (s.className?.trim().toLowerCase() == _selectedClass.toLowerCase()) ||
            (s.subDepartments?.any((sub) =>
                sub.className?.trim().toLowerCase() == _selectedClass.toLowerCase()) ?? false);
        if (!classMatch) return false;
      }
      if (_selectedDivision != 'All') {
        final divMatch = (s.division?.trim().toLowerCase() == _selectedDivision.toLowerCase()) ||
            (s.subDepartments?.any((sub) =>
                sub.division?.trim().toLowerCase() == _selectedDivision.toLowerCase()) ?? false);
        if (!divMatch) return false;
      }
      return true;
    }).toList();
  }

  void _resetDeptClassFilters() {
    setState(() {
      _selectedDept = 'All';
      _selectedSubDept = 'All';
      _selectedClass = 'All';
      _selectedDivision = 'All';
    });
  }

  void _goToPreviousStudent() {
    if (_students.isEmpty) return;
    final currentIdx = _students.indexWhere((s) => s.id == _selectedStudentId);
    final newIdx = currentIdx > 0 ? currentIdx - 1 : _students.length - 1;
    setState(() {
      _selectedStudentId = _students[newIdx].id;
    });
  }

  void _goToNextStudent() {
    if (_students.isEmpty) return;
    final currentIdx = _students.indexWhere((s) => s.id == _selectedStudentId);
    final newIdx = (currentIdx >= 0 && currentIdx < _students.length - 1) ? currentIdx + 1 : 0;
    setState(() {
      _selectedStudentId = _students[newIdx].id;
    });
  }

  Future<void> _showStudentSearchDialog(BuildContext context, bool isDark) async {
    final selectedId = _selectedStudentId ?? (_students.isNotEmpty ? _students.first.id : '');
    await showDialog(
      context: context,
      builder: (dialogCtx) {
        String filterQuery = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final query = filterQuery.trim().toLowerCase();
            final filtered = query.isEmpty
                ? _students
                : _students.where((s) {
                    final name = s.fullName.toLowerCase();
                    final gr = (s.grNo ?? '').toLowerCase();
                    final reg = s.registrationNumber.toLowerCase();
                    final roll = (s.rollNumber ?? '').toLowerCase();
                    final cls = (s.className ?? '').toLowerCase();
                    return name.contains(query) ||
                        gr.contains(query) ||
                        reg.contains(query) ||
                        roll.contains(query) ||
                        cls.contains(query);
                  }).toList();

            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 500,
                height: 520,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Title & Close Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_search_rounded, color: Color(0xFF059669), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              context.tr('search_student'),
                              style: AppTheme.getFontStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                          splashRadius: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Search Input
                    TextField(
                      autofocus: true,
                      onChanged: (val) => setModalState(() => filterQuery = val),
                      style: AppTheme.getFontStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: context.tr('search_student_hint'),
                        hintStyle: AppTheme.getFontStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF059669), size: 20),
                        filled: true,
                        fillColor: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF059669), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Student List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                context.tr('no_records_yet'),
                                style: AppTheme.getFontStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (context, idx) {
                                final st = filtered[idx];
                                final isSelected = st.id == selectedId;
                                final gr = st.grNo ?? st.registrationNumber;
                                  final sm = _getStudentFeeMetrics(st);
                                  return ListTile(
                                    dense: true,
                                    selected: isSelected,
                                    selectedTileColor: const Color(0xFF059669).withAlpha(isDark ? 30 : 15),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: const Color(0xFF059669).withAlpha(isDark ? 50 : 25),
                                      child: Text(
                                        st.fullName.isNotEmpty ? st.fullName[0].toUpperCase() : 'S',
                                        style: AppTheme.getFontStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF059669),
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      st.fullName,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'GR: $gr • ${st.className ?? '-'} • 📅 ${st.totalAttendance} ${context.tr('days')}',
                                      style: AppTheme.getFontStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                      ),
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹${sm.monthly.toInt()}/mo',
                                          style: AppTheme.getFontStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF059669),
                                          ),
                                        ),
                                        if (sm.paid > 0)
                                          Text(
                                            'Paid: ₹${sm.paid.toInt()}',
                                            style: AppTheme.getFontStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF10B981),
                                            ),
                                          ),
                                        if (sm.pending > 0)
                                          Text(
                                            'Due: ₹${sm.pending.toInt()}',
                                            style: AppTheme.getFontStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFFEA580C),
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () {
                                      setState(() => _selectedStudentId = st.id);
                                      Navigator.pop(dialogCtx);
                                    },
                                  );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final totalStudents = _students.isNotEmpty ? _students.length : widget.totalStudentsFallback;

    final cardContent = Container(
      height: widget.fixedHeight,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(22) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withAlpha(60) : Colors.black.withAlpha(12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _isLoading && _students.isEmpty && widget.totalStudentsFallback == 0
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: widget.fixedHeight != null ? MainAxisSize.max : MainAxisSize.min,
              children: [
                // ── Interactive 4-Tab Selector ──
                _buildTabBar(isDark),
                const SizedBox(height: 10),

                // ── Tab Body Content ──
                if (widget.fixedHeight != null)
                  Expanded(
                    child: _buildActiveTabBody(isDark, totalStudents),
                  )
                else
                  _buildActiveTabBody(isDark, totalStudents),
              ],
            ),
    );

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section Label matching the dashboard rhythm
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669), // Emerald accent for students
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        context.tr('student_analytics_overview'),
                        style: AppTheme.getFontStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => widget.onNavigate?.call('students'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('view_students'),
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: Color(0xFF059669),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          cardContent,
        ],
      ),
    );
  }

  // ── Tab Switcher Bar ────────────────────────────────────────────────────────
  Widget _buildTabBar(bool isDark) {
    final tabs = [
      (icon: Icons.analytics_rounded, label: context.tr('tab_student_overview')),
      (icon: Icons.place_rounded, label: context.tr('tab_by_location')),
      (icon: Icons.account_tree_rounded, label: context.tr('tab_by_dept_and_class')),
      (icon: Icons.receipt_long_rounded, label: context.tr('tab_student_fees')),
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          final tab = tabs[index];
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTabIndex = index),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF059669) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 50 : 15),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: 13,
                      color: isSelected
                          ? (isDark ? Colors.white : const Color(0xFF059669))
                          : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        tab.label,
                        style: AppTheme.getFontStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Colors.white : const Color(0xFF059669))
                              : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveTabBody(bool isDark, int totalStudents) {
    switch (_selectedTabIndex) {
      case 1:
        return _buildLocationTab(isDark, totalStudents);
      case 2:
        return _buildDeptAndClassTab(isDark, totalStudents);
      case 3:
        return _buildStudentFeeLookupTab(isDark, totalStudents);
      case 0:
      default:
        return _buildOverviewTab(isDark, totalStudents);
    }
  }

  // ── Tab 0: Overview & Fees ─────────────────────────────────────────────────
  Widget _buildOverviewTab(bool isDark, int totalStudents) {
    final activeStudents = _students.where((s) => s.isActive).length;
    final activeRate = totalStudents > 0 ? ((activeStudents / totalStudents) * 100).round() : 0;

    double totalMonthlyFees = 0.0;
    double totalPaidFees = 0.0;
    double totalPendingFees = 0.0;

    for (final s in _students) {
      final m = _getStudentFeeMetrics(s);
      if (s.isActive) {
        totalMonthlyFees += m.monthly;
      }
      totalPaidFees += m.paid;
      totalPendingFees += m.pending;
    }

    final monthlyStr = _formatCurrency(totalMonthlyFees, compact: true);
    final paidStr = _formatCurrency(totalPaidFees, compact: true);
    final pendingStr = _formatCurrency(totalPendingFees, compact: true);

    // Hosteller vs Day Scholar
    final hostellerCount = _students.where((s) => (s.studentStatus ?? '').toLowerCase().contains('hostel')).length;
    final dayScholarCount = (totalStudents - hostellerCount).clamp(0, totalStudents);

    // Class distribution
    final Map<String, int> classCounts = {};
    for (final s in _students) {
      final c = s.className?.trim();
      if (c != null && c.isNotEmpty) {
        classCounts[c] = (classCounts[c] ?? 0) + 1;
      }
    }
    final sortedClasses = classCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topClasses = sortedClasses.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── 1. Top KPI Row: Students, Monthly Fees, Paid Fees, Pending Fees (NO Attendance) ──
        LayoutBuilder(
          builder: (context, constraints) {
            final studentTile = _buildMetricTile(
              label: context.tr('card_title_students'),
              value: totalStudents.toString(),
              subValue: totalStudents > 0 ? '$activeRate% ${context.tr('active')}' : '0 ${context.tr('active')}',
              icon: Icons.school_rounded,
              accentColor: const Color(0xFF059669),
              isDark: isDark,
            );

            final monthlyFeeTile = _buildMetricTile(
              label: context.tr('monthly_fees'),
              value: monthlyStr,
              subValue: context.tr('monthly'),
              icon: Icons.payments_rounded,
              accentColor: const Color(0xFF2563EB),
              isDark: isDark,
            );

            final paidFeeTile = _buildMetricTile(
              label: context.tr('paid_fees'),
              value: paidStr,
              subValue: context.tr('paid'),
              icon: Icons.check_circle_rounded,
              accentColor: const Color(0xFF10B981),
              isDark: isDark,
            );

            final pendingFeeTile = _buildMetricTile(
              label: context.tr('pending_fees'),
              value: pendingStr,
              subValue: totalPendingFees > 0 ? context.tr('needs_attention') : context.tr('all_fees_cleared'),
              icon: Icons.pending_actions_rounded,
              accentColor: totalPendingFees > 0 ? const Color(0xFFEA580C) : const Color(0xFF10B981),
              isDark: isDark,
            );

            final isCompact = constraints.maxWidth < 420;
            if (isCompact) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: studentTile),
                      const SizedBox(width: 6),
                      Expanded(child: monthlyFeeTile),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(child: paidFeeTile),
                      const SizedBox(width: 6),
                      Expanded(child: pendingFeeTile),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: studentTile),
                const SizedBox(width: 6),
                Expanded(child: monthlyFeeTile),
                const SizedBox(width: 6),
                Expanded(child: paidFeeTile),
                const SizedBox(width: 6),
                Expanded(child: pendingFeeTile),
              ],
            );
          },
        ),

        const SizedBox(height: 6),

        // ── 2. Class Distribution Breakdown ──
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    context.tr('class_distribution'),
                    style: AppTheme.getFontStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white.withAlpha(220) : const Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  totalStudents > 0 ? '$totalStudents ${context.tr('enrolled')}' : context.tr('no_records_yet'),
                  style: AppTheme.getFontStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Segmented Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Container(
                height: 7,
                width: double.infinity,
                color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200,
                child: totalStudents == 0
                    ? Container(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade300)
                    : Row(
                        children: topClasses.map((entry) {
                          final colors = [
                            const Color(0xFF059669),
                            const Color(0xFF2563EB),
                            const Color(0xFFF59E0B),
                            const Color(0xFF8B5CF6),
                          ];
                          final idx = topClasses.indexOf(entry) % colors.length;
                          return Expanded(
                            flex: entry.value,
                            child: Container(color: colors[idx]),
                          );
                        }).toList(),
                      ),
              ),
            ),

            const SizedBox(height: 5),

            // Legend Chips
            if (totalStudents == 0 || topClasses.isEmpty)
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      context.tr('no_records_yet'),
                      style: AppTheme.getFontStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: topClasses.map((entry) {
                  final colors = [
                    const Color(0xFF059669),
                    const Color(0xFF2563EB),
                    const Color(0xFFF59E0B),
                    const Color(0xFF8B5CF6),
                  ];
                  final idx = topClasses.indexOf(entry) % colors.length;
                  return _buildLegendItem(entry.key, entry.value, totalStudents, colors[idx], isDark);
                }).toList(),
              ),
          ],
        ),

        const SizedBox(height: 6),

        // ── 3. Bottom Demographics & Hosteller/Day Scholar Footer (NO Attendance) ──
        _buildDemographicsFooter(
          isDark: isDark,
          genderSummaryText: _getGenderDisplayString(_students, context),
          hostellerCount: hostellerCount,
          dayScholarCount: dayScholarCount,
          totalStudents: totalStudents,
          attendanceText: null,
        ),
      ],
    );
  }

  // ── Tab 1: By Location (Village / District / State) ─────────────────────────
  Widget _buildLocationTab(bool isDark, int totalStudents) {
    final locations = _getUniqueLocations(_locationType);
    final effectiveLocation = locations.contains(_selectedLocation) ? _selectedLocation : 'All';

    final filteredStudents = effectiveLocation == 'All'
        ? _students
        : _students.where((s) => _getStudentLocationValue(s, _locationType).toLowerCase().trim() == effectiveLocation.toLowerCase().trim()).toList();

    final locTotal = filteredStudents.length;
    final locActive = filteredStudents.where((s) => s.isActive).length;

    double locMonthlyFees = 0.0;
    double locPaidFees = 0.0;
    double locPendingFees = 0.0;
    for (final s in filteredStudents) {
      final m = _getStudentFeeMetrics(s);
      if (s.isActive) locMonthlyFees += m.monthly;
      locPaidFees += m.paid;
      locPendingFees += m.pending;
    }

    final monthlyStr = _formatCurrency(locMonthlyFees, compact: true);
    final paidStr = _formatCurrency(locPaidFees, compact: true);
    final pendingStr = _formatCurrency(locPendingFees, compact: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── Location Type Selector & Location Dropdown ──
        Row(
          children: [
            // Segmented Location Type Picker (Village, District, State)
            Container(
              height: 38,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLocationTypeButton('village', context.tr('village'), isDark),
                  _buildLocationTypeButton('district', context.tr('district'), isDark),
                  _buildLocationTypeButton('state', context.tr('state'), isDark),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Dropdown to pick specific location
            Expanded(
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: effectiveLocation,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF059669), size: 20),
                    dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    style: AppTheme.getFontStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedLocation = val);
                    },
                    items: locations.map((loc) {
                      final count = loc == 'All'
                          ? _students.length
                          : _students.where((s) => _getStudentLocationValue(s, _locationType).toLowerCase().trim() == loc.toLowerCase().trim()).length;
                      final label = loc == 'All' ? context.tr('all_locations') : loc;
                      return DropdownMenuItem<String>(
                        value: loc,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                style: AppTheme.getFontStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withAlpha(isDark ? 40 : 20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$count',
                                style: AppTheme.getFontStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── 4 Location Metric Tiles (Students, Monthly Fees, Paid Fees, Pending Fees - NO Attendance) ──
        LayoutBuilder(
          builder: (context, constraints) {
            final locStudentTile = _buildMetricTile(
              label: context.tr('students_in_location'),
              value: locTotal.toString(),
              subValue: '$locActive ${context.tr('active')}',
              icon: Icons.place_rounded,
              accentColor: const Color(0xFF059669),
              isDark: isDark,
            );
            final locMonthlyTile = _buildMetricTile(
              label: context.tr('monthly_fees'),
              value: monthlyStr,
              subValue: context.tr('monthly'),
              icon: Icons.payments_rounded,
              accentColor: const Color(0xFF2563EB),
              isDark: isDark,
            );
            final locPaidTile = _buildMetricTile(
              label: context.tr('paid_fees'),
              value: paidStr,
              subValue: context.tr('paid'),
              icon: Icons.check_circle_rounded,
              accentColor: const Color(0xFF10B981),
              isDark: isDark,
            );
            final locPendingTile = _buildMetricTile(
              label: context.tr('pending_fees'),
              value: pendingStr,
              subValue: locPendingFees > 0 ? context.tr('needs_attention') : context.tr('all_fees_cleared'),
              icon: Icons.pending_actions_rounded,
              accentColor: locPendingFees > 0 ? const Color(0xFFEA580C) : const Color(0xFF10B981),
              isDark: isDark,
            );

            final isCompact = constraints.maxWidth < 420;
            if (isCompact) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: locStudentTile),
                      const SizedBox(width: 6),
                      Expanded(child: locMonthlyTile),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(child: locPaidTile),
                      const SizedBox(width: 6),
                      Expanded(child: locPendingTile),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: locStudentTile),
                const SizedBox(width: 6),
                Expanded(child: locMonthlyTile),
                const SizedBox(width: 6),
                Expanded(child: locPaidTile),
                const SizedBox(width: 6),
                Expanded(child: locPendingTile),
              ],
            );
          },
        ),

        const SizedBox(height: 6),

        // ── Location Insights & Custom Genders Row (NO Attendance) ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wc_rounded, size: 14, color: Color(0xFF059669)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        locTotal > 0
                            ? _getGenderDisplayString(filteredStudents, context)
                            : '-',
                        style: AppTheme.getFontStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                totalStudents > 0
                    ? '${((locTotal / totalStudents) * 100).round()}% ${context.tr('card_sub_students')}'
                    : '',
                style: AppTheme.getFontStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationTypeButton(String type, String label, bool isDark) {
    final isSelected = _locationType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _locationType = type;
          _selectedLocation = 'All';
        });
      },
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF059669) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 40 : 10),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : const Color(0xFF059669))
                : (isDark ? Colors.white70 : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  // ── Tab 2: By Dept & Class ───────────────────────────────────────────────────
  Widget _buildDeptAndClassTab(bool isDark, int totalStudents) {
    final depts = _getUniqueDepartments();
    final subDepts = _getUniqueSubDepartments();
    final classes = _getUniqueClassesFiltered();
    final divisions = _getUniqueDivisionsFiltered();

    final effectiveDept = depts.contains(_selectedDept) ? _selectedDept : 'All';
    final effectiveSubDept = subDepts.contains(_selectedSubDept) ? _selectedSubDept : 'All';
    final effectiveClass = classes.contains(_selectedClass) ? _selectedClass : 'All';
    final effectiveDivision = divisions.contains(_selectedDivision) ? _selectedDivision : 'All';

    final filteredStudents = _getFilteredDeptClassStudents();

    final filteredTotal = filteredStudents.length;
    final filteredActive = filteredStudents.where((s) => s.isActive).length;

    double filteredMonthlyFees = 0.0;
    double filteredPaidFees = 0.0;
    double filteredPendingFees = 0.0;
    for (final s in filteredStudents) {
      final m = _getStudentFeeMetrics(s);
      if (s.isActive) filteredMonthlyFees += m.monthly;
      filteredPaidFees += m.paid;
      filteredPendingFees += m.pending;
    }

    final monthlyStr = _formatCurrency(filteredMonthlyFees, compact: true);
    final paidStr = _formatCurrency(filteredPaidFees, compact: true);
    final pendingStr = _formatCurrency(filteredPendingFees, compact: true);

    final isAnyFilterActive = effectiveDept != 'All' || effectiveSubDept != 'All' || effectiveClass != 'All' || effectiveDivision != 'All';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── 4-Tier Filtering Bar (Department, Sub-Dept, Class, Division) ──
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Department & Sub-Department
            Row(
              children: [
                Expanded(
                  child: _buildCompactFilterDropdown(
                    icon: Icons.domain_rounded,
                    label: context.tr('department'),
                    value: effectiveDept,
                    items: depts,
                    allLabel: context.tr('all_departments'),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDept = val;
                          final newSubs = _getUniqueSubDepartments();
                          if (!newSubs.contains(_selectedSubDept)) _selectedSubDept = 'All';
                          final newClasses = _getUniqueClassesFiltered();
                          if (!newClasses.contains(_selectedClass)) _selectedClass = 'All';
                          final newDivs = _getUniqueDivisionsFiltered();
                          if (!newDivs.contains(_selectedDivision)) _selectedDivision = 'All';
                        });
                      }
                    },
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildCompactFilterDropdown(
                    icon: Icons.snippet_folder_rounded,
                    label: context.tr('sub_department'),
                    value: effectiveSubDept,
                    items: subDepts,
                    allLabel: context.tr('all_sub_departments'),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedSubDept = val;
                          final newClasses = _getUniqueClassesFiltered();
                          if (!newClasses.contains(_selectedClass)) _selectedClass = 'All';
                          final newDivs = _getUniqueDivisionsFiltered();
                          if (!newDivs.contains(_selectedDivision)) _selectedDivision = 'All';
                        });
                      }
                    },
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Row 2: Class & Division + Optional Clear Button
            Row(
              children: [
                Expanded(
                  child: _buildCompactFilterDropdown(
                    icon: Icons.class_rounded,
                    label: context.tr('class'),
                    value: effectiveClass,
                    items: classes,
                    allLabel: context.tr('all_classes'),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedClass = val;
                          final newDivs = _getUniqueDivisionsFiltered();
                          if (!newDivs.contains(_selectedDivision)) _selectedDivision = 'All';
                        });
                      }
                    },
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildCompactFilterDropdown(
                    icon: Icons.grid_view_rounded,
                    label: context.tr('division'),
                    value: effectiveDivision,
                    items: divisions,
                    allLabel: context.tr('all_divisions'),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedDivision = val;
                        });
                      }
                    },
                    isDark: isDark,
                  ),
                ),
                if (isAnyFilterActive) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _resetDeptClassFilters,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(isDark ? 30 : 15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withAlpha(40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.close_rounded, size: 13, color: Colors.red),
                          const SizedBox(width: 2),
                          Text(
                            context.tr('clear_filters'),
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── 4 Metric Tiles (Students, Monthly Fees, Paid Fees, Pending Fees - NO Attendance) ──
        LayoutBuilder(
          builder: (context, constraints) {
            final filterStudentTile = _buildMetricTile(
              label: context.tr('card_title_students'),
              value: filteredTotal.toString(),
              subValue: '$filteredActive ${context.tr('active')}',
              icon: Icons.school_rounded,
              accentColor: const Color(0xFF059669),
              isDark: isDark,
            );
            final filterMonthlyTile = _buildMetricTile(
              label: context.tr('monthly_fees'),
              value: monthlyStr,
              subValue: context.tr('monthly'),
              icon: Icons.payments_rounded,
              accentColor: const Color(0xFF2563EB),
              isDark: isDark,
            );
            final filterPaidTile = _buildMetricTile(
              label: context.tr('paid_fees'),
              value: paidStr,
              subValue: context.tr('paid'),
              icon: Icons.check_circle_rounded,
              accentColor: const Color(0xFF10B981),
              isDark: isDark,
            );
            final filterPendingTile = _buildMetricTile(
              label: context.tr('pending_fees'),
              value: pendingStr,
              subValue: filteredPendingFees > 0 ? context.tr('needs_attention') : context.tr('all_fees_cleared'),
              icon: Icons.pending_actions_rounded,
              accentColor: filteredPendingFees > 0 ? const Color(0xFFEA580C) : const Color(0xFF10B981),
              isDark: isDark,
            );

            final isCompact = constraints.maxWidth < 420;
            if (isCompact) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: filterStudentTile),
                      const SizedBox(width: 6),
                      Expanded(child: filterMonthlyTile),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(child: filterPaidTile),
                      const SizedBox(width: 6),
                      Expanded(child: filterPendingTile),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: filterStudentTile),
                const SizedBox(width: 6),
                Expanded(child: filterMonthlyTile),
                const SizedBox(width: 6),
                Expanded(child: filterPaidTile),
                const SizedBox(width: 6),
                Expanded(child: filterPendingTile),
              ],
            );
          },
        ),

        const SizedBox(height: 6),

        // ── Filtered Demographics & Custom Genders Row (NO Attendance) ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wc_rounded, size: 14, color: Color(0xFF059669)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        filteredTotal > 0
                            ? _getGenderDisplayString(filteredStudents, context)
                            : '-',
                        style: AppTheme.getFontStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                totalStudents > 0
                    ? '${((filteredTotal / totalStudents) * 100).round()}% ${context.tr('enrolled')}'
                    : '',
                style: AppTheme.getFontStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactFilterDropdown({
    required IconData icon,
    required String label,
    required String value,
    required List<String> items,
    required String allLabel,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    final effectiveValue = items.contains(value) ? value : 'All';
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: effectiveValue != 'All'
              ? const Color(0xFF059669).withAlpha(isDark ? 120 : 180)
              : (isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1)),
          width: effectiveValue != 'All' ? 1.3 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF059669), size: 16),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: AppTheme.getFontStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          onChanged: onChanged,
          items: items.map((item) {
            final displayText = item == 'All' ? allLabel : item;
            return DropdownMenuItem<String>(
              value: item,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: const Color(0xFF059669)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      displayText,
                      style: AppTheme.getFontStyle(
                        fontSize: 11,
                        fontWeight: item == effectiveValue ? FontWeight.w700 : FontWeight.w500,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Tab 3: Individual Student Fee & Details Lookup ──────────────────────────
  Widget _buildStudentFeeLookupTab(bool isDark, int totalStudents) {
    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 30, color: isDark ? Colors.white38 : Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              context.tr('no_records_yet'),
              style: AppTheme.getFontStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    final effectiveStudentId = (_selectedStudentId != null && _students.any((s) => s.id == _selectedStudentId))
        ? _selectedStudentId!
        : _students.first.id;

    final selectedStudent = _students.firstWhere(
      (s) => s.id == effectiveStudentId,
      orElse: () => _students.first,
    );

    final studentMetrics = _getStudentFeeMetrics(selectedStudent);
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final monthlyFeeStr = currencyFormatter.format(studentMetrics.monthly);
    final paidFeeStr = currencyFormatter.format(studentMetrics.paid);
    final pendingFeeStr = studentMetrics.pending > 0
        ? currencyFormatter.format(studentMetrics.pending)
        : context.tr('all_fees_cleared');

    final studentGenderStr = (selectedStudent.gender != null && selectedStudent.gender!.trim().isNotEmpty)
        ? _localizeGender(selectedStudent.gender!.trim(), context)
        : '-';

    // Address location string (Village, District, State)
    final locParts = [
      if (selectedStudent.village != null && selectedStudent.village!.trim().isNotEmpty) selectedStudent.village!.trim(),
      if (selectedStudent.district != null && selectedStudent.district!.trim().isNotEmpty) selectedStudent.district!.trim(),
      if (selectedStudent.state != null && selectedStudent.state!.trim().isNotEmpty) selectedStudent.state!.trim(),
    ];
    final locationDisplay = locParts.isNotEmpty ? locParts.join(', ') : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── Searchable Student Selector Bar ──
        Row(
          children: [
            // Previous Student Button (<)
            InkWell(
              onTap: _goToPreviousStudent,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                width: 34,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Searchable Trigger Button
            Expanded(
              child: InkWell(
                onTap: () => _showStudentSearchDialog(context, isDark),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selectedStudent.isActive ? const Color(0xFF10B981) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '[${selectedStudent.grNo ?? selectedStudent.registrationNumber}] ${selectedStudent.fullName} (${selectedStudent.className ?? '-'})',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withAlpha(isDark ? 40 : 20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_rounded, size: 12, color: Color(0xFF059669)),
                            const SizedBox(width: 3),
                            Text(
                              context.tr('search_student'),
                              style: AppTheme.getFontStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF059669),
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
            const SizedBox(width: 6),
            // Next Student Button (>)
            InkWell(
              onTap: _goToNextStudent,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 38,
                width: 34,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white.withAlpha(20) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── Profile Header & View Profile Button ──
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF059669).withAlpha(isDark ? 60 : 30),
              child: Text(
                selectedStudent.fullName.isNotEmpty ? selectedStudent.fullName[0].toUpperCase() : 'S',
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF059669),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          selectedStudent.fullName,
                          style: AppTheme.getFontStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: (selectedStudent.isActive ? const Color(0xFF10B981) : Colors.grey).withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          selectedStudent.isActive ? context.tr('active') : 'Inactive',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: selectedStudent.isActive ? const Color(0xFF10B981) : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'GR: ${selectedStudent.grNo ?? selectedStudent.registrationNumber} • ${selectedStudent.className ?? '-'}',
                    style: AppTheme.getFontStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider(
                      create: (_) => StudentsBloc(repository: StudentRepository(ApiClient())),
                      child: StudentProfileScreen(
                        studentId: selectedStudent.id,
                        initialStudent: selectedStudent,
                        onBack: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withAlpha(isDark ? 40 : 15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF059669).withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('view_profile'),
                      style: AppTheme.getFontStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.open_in_new_rounded, size: 11, color: Color(0xFF059669)),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── 4 Highlight Badges: Paid Fees, Pending Fees, Monthly Fees & Attendance ──
        LayoutBuilder(
          builder: (context, constraints) {
            final paidBadge = _buildStudentFeeBadge(
              title: context.tr('paid_fees'),
              value: paidFeeStr,
              icon: Icons.check_circle_rounded,
              isDark: isDark,
              accentColor: const Color(0xFF10B981),
              bgColors: isDark
                  ? [const Color(0xFF064E3B).withAlpha(120), const Color(0xFF065F46).withAlpha(100)]
                  : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
            );

            final pendingBadge = _buildStudentFeeBadge(
              title: context.tr('pending_fees'),
              value: pendingFeeStr,
              icon: studentMetrics.pending > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
              isDark: isDark,
              accentColor: studentMetrics.pending > 0 ? const Color(0xFFEA580C) : const Color(0xFF10B981),
              bgColors: studentMetrics.pending > 0
                  ? (isDark
                      ? [const Color(0xFF7C2D12).withAlpha(120), const Color(0xFF9A3412).withAlpha(100)]
                      : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)])
                  : (isDark
                      ? [const Color(0xFF064E3B).withAlpha(120), const Color(0xFF065F46).withAlpha(100)]
                      : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]),
            );

            final monthlyBadge = _buildStudentFeeBadge(
              title: context.tr('monthly_fees'),
              value: monthlyFeeStr,
              icon: Icons.payments_rounded,
              isDark: isDark,
              accentColor: const Color(0xFF2563EB),
              bgColors: isDark
                  ? [const Color(0xFF1E3A8A).withAlpha(120), const Color(0xFF1D4ED8).withAlpha(100)]
                  : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
            );

            final attendanceBadge = _buildStudentFeeBadge(
              title: context.tr('attendance'),
              value: '${selectedStudent.totalAttendance} ${context.tr('days')}',
              icon: Icons.how_to_reg_rounded,
              isDark: isDark,
              accentColor: const Color(0xFF8B5CF6),
              bgColors: isDark
                  ? [const Color(0xFF4C1D95).withAlpha(120), const Color(0xFF5B21B6).withAlpha(100)]
                  : [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)],
            );

            if (constraints.maxWidth < 440) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: paidBadge),
                      const SizedBox(width: 6),
                      Expanded(child: pendingBadge),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(child: monthlyBadge),
                      const SizedBox(width: 6),
                      Expanded(child: attendanceBadge),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: paidBadge),
                const SizedBox(width: 6),
                Expanded(child: pendingBadge),
                const SizedBox(width: 6),
                Expanded(child: monthlyBadge),
                const SizedBox(width: 6),
                Expanded(child: attendanceBadge),
              ],
            );
          },
        ),

        const SizedBox(height: 6),

        // ── Student Address, Gender & Condition Row ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(12) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_rounded, size: 12, color: Color(0xFF059669)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        locationDisplay,
                        style: AppTheme.getFontStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${context.tr('gender')}: $studentGenderStr',
                  style: AppTheme.getFontStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selectedStudent.conditionType != null && selectedStudent.conditionType!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '🏷️ ${selectedStudent.conditionType}',
                    style: AppTheme.getFontStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentFeeBadge({
    required String title,
    required String value,
    required IconData icon,
    required bool isDark,
    required Color accentColor,
    required List<Color> bgColors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withAlpha(isDark ? 60 : 40),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: accentColor),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.getFontStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : accentColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.getFontStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Metric Tile Helper ─────────────────────────────────────────────────────
  Widget _buildMetricTile({
    required String label,
    required String value,
    required String subValue,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withAlpha(isDark ? 30 : 15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withAlpha(isDark ? 55 : 40),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accentColor),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.getFontStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTheme.getFontStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            subValue,
            style: AppTheme.getFontStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int count, int total, Color color, bool isDark) {
    final pct = total > 0 ? ((count / total) * 100).round() : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$label: $count ($pct%)',
          style: AppTheme.getFontStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildDemographicsFooter({
    required bool isDark,
    required String genderSummaryText,
    required int hostellerCount,
    required int dayScholarCount,
    required int totalStudents,
    String? attendanceText,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTight = constraints.maxWidth < 360;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isTight ? 8 : 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wc_rounded,
                size: 13,
                color: Color(0xFF059669),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  genderSummaryText,
                  style: AppTheme.getFontStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isTight) ...[
                const SizedBox(width: 6),
                Text(
                  '•',
                  style: TextStyle(
                    color: isDark ? Colors.white24 : Colors.grey.shade400,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.hotel_rounded,
                  size: 12,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    totalStudents > 0
                        ? '$hostellerCount ${context.tr('hosteller')} • $dayScholarCount ${context.tr('day_scholar')}'
                        : context.tr('card_sub_students'),
                    style: AppTheme.getFontStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (attendanceText != null && attendanceText.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '•',
                    style: TextStyle(
                      color: isDark ? Colors.white24 : Colors.grey.shade400,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.how_to_reg_rounded,
                    size: 12,
                    color: Color(0xFF0D9488),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      attendanceText,
                      style: AppTheme.getFontStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
              const Spacer(),
              InkWell(
                onTap: () => widget.onNavigate?.call('students'),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('manage_students'),
                        style: AppTheme.getFontStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 11,
                        color: Color(0xFF059669),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
