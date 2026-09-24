import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/movable_resizable_dialog.dart';
import '../../data/models/student_academic_history_model.dart';
import '../../data/repositories/student_repository.dart';
import '../bloc/students_bloc.dart';
import '../screens/student_profile_screen.dart';

class AcademicHistoryExplorerDialog extends StatefulWidget {
  const AcademicHistoryExplorerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => const AcademicHistoryExplorerDialog(),
    );
  }

  @override
  State<AcademicHistoryExplorerDialog> createState() => _AcademicHistoryExplorerDialogState();
}

class _AcademicHistoryExplorerDialogState extends State<AcademicHistoryExplorerDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _filteredRecords = [];

  // Dropdown filter options
  List<String> _academicYears = ['All'];
  List<String> _classes = ['All'];
  List<String> _departments = ['All'];
  final List<String> _statuses = ['All', 'Promoted', 'Repeated', 'Farigh', 'Admitted'];

  // Current filter selections
  String _selectedYear = 'All';
  String _selectedClass = 'All';
  String _selectedDepartment = 'All';
  String _selectedStatus = 'All';
  final TextEditingController _searchController = TextEditingController();

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final dbHelper = DatabaseHelper();

    // 1. Load filter dropdown lists
    final yearsList = await dbHelper.getAllAcademicYears();
    final yearNames = yearsList.map((y) => y['year_name']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList();
    yearNames.sort((a, b) => b.compareTo(a));

    final classList = await dbHelper.getDistinctClassNames();
    final deptList = await dbHelper.getDistinctDepartments();

    if (mounted) {
      setState(() {
        _academicYears = ['All', ...yearNames];
        _classes = ['All', ...classList];
        _departments = ['All', ...deptList];
      });
    }

    // 2. Fetch history records
    await _fetchRecords();
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    final dbHelper = DatabaseHelper();

    final results = await dbHelper.queryAcademicHistory(
      academicYear: _selectedYear == 'All' ? null : _selectedYear,
      className: _selectedClass == 'All' ? null : _selectedClass,
      departmentId: _selectedDepartment == 'All' ? null : _selectedDepartment,
      status: _selectedStatus == 'All' ? null : _selectedStatus,
      searchQuery: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
    );

    if (mounted) {
      setState(() {
        _filteredRecords = results;
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    _fetchRecords();
  }

  void _resetFilters() {
    setState(() {
      _selectedYear = 'All';
      _selectedClass = 'All';
      _selectedDepartment = 'All';
      _selectedStatus = 'All';
      _searchController.clear();
    });
    _fetchRecords();
  }

  void _openStudentProfile(String studentId, String studentName) {
    if (studentId.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (routeContext, animation, secondaryAnimation) => BlocProvider(
          create: (_) => StudentsBloc(repository: StudentRepository(ApiClient())),
          child: StudentProfileScreen(
            studentId: studentId,
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.04, 0.0);
          const end = Offset.zero;
          final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(position: Tween(begin: begin, end: end).animate(curve), child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Metrics calculations
    final totalCount = _filteredRecords.length;
    int promotedCount = 0;
    int repeatedCount = 0;
    int farighCount = 0;
    double totalFeesPaid = 0.0;
    double totalFeesPending = 0.0;
    double totalExpense = 0.0;

    for (final r in _filteredRecords) {
      final st = (r['status']?.toString() ?? '').toLowerCase();
      if (st == 'promoted') promotedCount++;
      if (st == 'repeated') repeatedCount++;
      if (st == 'farigh' || st == 'graduated') farighCount++;

      final paid = (r['fee_paid'] as num?)?.toDouble() ?? 0.0;
      final pending = (r['fee_pending'] as num?)?.toDouble() ?? 0.0;
      final exp = (r['per_student_expense'] as num?)?.toDouble() ?? 0.0;

      totalFeesPaid += paid;
      totalFeesPending += pending;
      totalExpense += exp;
    }

    return MovableResizableDialog(
      initialWidth: 1100,
      initialHeight: 740,
      minWidth: 700,
      minHeight: 500,
      headerLeading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white.withAlpha(30), shape: BoxShape.circle),
        child: const Icon(Icons.history_edu_rounded, color: Colors.white, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Academic History & Progression Explorer (تعلیمی تاریخ اور ترقی کا ریکارڈ)',
            style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            'Search & view student historical records across years, classes, departments, exams, fees, and expenses.',
            style: AppTheme.getFontStyle(fontSize: 11, color: Colors.white.withAlpha(200)),
          ),
        ],
      ),
      content: Container(
        color: isDark ? const Color(0xFF14141E) : const Color(0xFFF8F9FA),
        child: Column(
          children: [
            // ─── Filter Bar ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Search field
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by Name, Roll No, GR No...',
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        _applyFilters();
                                      },
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onSubmitted: (_) => _applyFilters(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Academic Year Filter
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 40,
                          child: _buildDropdownFilter(
                            label: 'Year / سال',
                            icon: Icons.date_range_rounded,
                            value: _selectedYear,
                            items: _academicYears,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _selectedYear = v);
                                _applyFilters();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Class Filter
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 40,
                          child: _buildDropdownFilter(
                            label: 'Class / درجہ',
                            icon: Icons.school_rounded,
                            value: _selectedClass,
                            items: _classes,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _selectedClass = v);
                                _applyFilters();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Department Filter
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 40,
                          child: _buildDropdownFilter(
                            label: 'Department / شعبہ',
                            icon: Icons.account_balance_rounded,
                            value: _selectedDepartment,
                            items: _departments,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _selectedDepartment = v);
                                _applyFilters();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Status Filter
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 40,
                          child: _buildDropdownFilter(
                            label: 'Status / کیفیت',
                            icon: Icons.flag_rounded,
                            value: _selectedStatus,
                            items: _statuses,
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _selectedStatus = v);
                                _applyFilters();
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Apply / Reset Buttons
                      ElevatedButton.icon(
                        onPressed: _applyFilters,
                        icon: const Icon(Icons.filter_list_rounded, size: 16),
                        label: const Text('Filter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D6B4E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Reset Filters',
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: _resetFilters,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ─── KPI Metric Cards Bar ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: isDark ? const Color(0xFF1B1B2A) : Colors.grey.shade100,
              child: Row(
                children: [
                  _buildMetricBadge('Total Records', '$totalCount', Icons.people_outline_rounded, const Color(0xFF1565C0), isDark),
                  const SizedBox(width: 8),
                  _buildMetricBadge('Promoted (ترقی)', '$promotedCount', Icons.trending_up_rounded, Colors.green.shade700, isDark),
                  const SizedBox(width: 8),
                  _buildMetricBadge('Repeated (تکرار)', '$repeatedCount', Icons.replay_rounded, Colors.orange.shade800, isDark),
                  const SizedBox(width: 8),
                  _buildMetricBadge('Farigh (فارغ)', '$farighCount', Icons.school_outlined, Colors.purple.shade700, isDark),
                  const Spacer(),
                  _buildMetricBadge('Fees Paid', _currencyFormat.format(totalFeesPaid), Icons.check_circle_outline, Colors.teal.shade700, isDark),
                  const SizedBox(width: 8),
                  _buildMetricBadge('Fees Due', _currencyFormat.format(totalFeesPending), Icons.pending_actions_rounded, Colors.red.shade700, isDark),
                  const SizedBox(width: 8),
                  _buildMetricBadge('Madarsa Expense', _currencyFormat.format(totalExpense), Icons.account_balance_wallet_outlined, const Color(0xFF0D6B4E), isDark),
                ],
              ),
            ),

            // ─── Content Body: List of Historical Records ─────────────
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredRecords.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: _filteredRecords.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = _filteredRecords[index];
                            return _buildRecordCard(row, isDark);
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${_filteredRecords.length} historical student archive records',
            style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Close'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String title, String val, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? color.withAlpha(25) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTheme.getFontStyle(fontSize: 9.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
              Text(val, style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_toggle_off_rounded, size: 48, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'No Historical Academic Records Found',
              style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Academic history records are created when students are promoted, graduated, or when the academic year ends.',
              style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text('Reset All Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> row, bool isDark) {
    final history = StudentAcademicHistory.fromJson(row);
    final studentName = row['student_full_name']?.toString() ?? 'Student';
    final fatherName = row['student_father_name']?.toString() ?? '';
    final grNo = row['student_gr_no']?.toString() ?? row['student_registration_number']?.toString() ?? '-';
    final photoPath = row['student_photo_path']?.toString();

    final status = history.status.toLowerCase();
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.arrow_upward_rounded;
    String statusUrdu = 'ترقی یافتہ';

    if (status == 'repeated') {
      statusColor = Colors.orange;
      statusIcon = Icons.replay_rounded;
      statusUrdu = 'تکرار (اسی درجہ میں)';
    } else if (status == 'farigh' || status == 'graduated') {
      statusColor = Colors.purple;
      statusIcon = Icons.school_rounded;
      statusUrdu = 'فارغ التحصیل';
    } else if (status == 'admitted') {
      statusColor = Colors.blue;
      statusIcon = Icons.how_to_reg_rounded;
      statusUrdu = 'جدید داخلہ';
    }

    final books = history.parsedBooksAndMarks;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 5),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: InkWell(
          onTap: () => _openStudentProfile(history.studentId, studentName),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.primaryColor.withAlpha(30),
            backgroundImage: photoPath != null && File(photoPath).existsSync() ? FileImage(File(photoPath)) : null,
            child: photoPath == null || !File(photoPath).existsSync()
                ? Text(
                    studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  )
                : null,
          ),
        ),
        title: Row(
          children: [
            InkWell(
              onTap: () => _openStudentProfile(history.studentId, studentName),
              child: Text(
                studentName,
                style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
            if (fatherName.isNotEmpty) ...[
              Text(
                ' ولد $fatherName',
                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('GR: $grNo', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            ),
            if (history.rollNumber != null && history.rollNumber!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Roll: ${history.rollNumber}', style: const TextStyle(fontSize: 10.5)),
              ),
            ],
            const Spacer(),
            // Year Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1565C0).withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 12, color: Color(0xFF1565C0)),
                  const SizedBox(width: 4),
                  Text(
                    history.academicYear + (history.academicYearHijri != null ? ' (${history.academicYearHijri})' : ''),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    '${history.status} ($statusUrdu)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Class & Division
              _buildSubInfoChip(
                Icons.class_rounded,
                'Class: ${history.className}${history.division != null && history.division!.isNotEmpty ? " (${history.division})" : ""}',
                isDark,
              ),
              // Department
              if (history.departmentName != null && history.departmentName!.isNotEmpty)
                _buildSubInfoChip(Icons.account_balance_rounded, 'Dept: ${history.departmentName}', isDark),
              // Attendance
              _buildSubInfoChip(
                Icons.fact_check_outlined,
                'Attendance: ${history.attendancePercentage.toStringAsFixed(1)}% (${history.presentDays}/${history.totalAttendanceDays} Days)',
                isDark,
                color: history.attendancePercentage >= 75 ? Colors.green : Colors.orange,
              ),
              // Exam Result
              _buildSubInfoChip(
                Icons.analytics_outlined,
                'Exams: ${history.examPercentage.toStringAsFixed(1)}% ${history.resultGrade != null ? "Grade: ${history.resultGrade}" : ""}',
                isDark,
                color: history.examPercentage >= 40 ? const Color(0xFF0D6B4E) : Colors.red,
              ),
              // Fee Status
              _buildSubInfoChip(
                Icons.payments_outlined,
                'Fees: Paid ${_currencyFormat.format(history.feePaid)} / ${_currencyFormat.format(history.feeTotal)}'
                '${history.feePending > 0 ? " (Pending: ${_currencyFormat.format(history.feePending)})" : " (Clear)"}',
                isDark,
                color: history.feePending > 0 ? Colors.red.shade700 : Colors.teal.shade700,
              ),
              // Per Student Expense
              _buildSubInfoChip(
                Icons.receipt_long_rounded,
                'Kharch (Madarsa Expense): ${_currencyFormat.format(history.perStudentExpense)}',
                isDark,
                color: const Color(0xFF6A1B9A),
              ),
            ],
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
              border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Books & Exam Marks Breakdown (کتابیں اور امتحانات کے تفصیلی نمبرات):',
                      style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${books.length} Books Registered',
                      style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No individual book exam marks recorded for this academic period.',
                      style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  )
                else
                  Column(
                    children: books.map((b) {
                      final bName = b['book_name']?.toString() ?? 'Book';
                      final exams = (b['exams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                      final bMax = (b['total_max'] as num?)?.toDouble() ?? 0.0;
                      final bObt = (b['total_obtained'] as num?)?.toDouble() ?? 0.0;
                      final bPct = (b['percentage'] as num?)?.toDouble() ?? 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF252538) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFF0D6B4E)),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Text(
                                bName,
                                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: exams.map((ex) {
                                  final exName = ex['exam_name']?.toString() ?? 'Exam';
                                  final obt = (ex['marks_obtained'] as num?)?.toDouble() ?? 0.0;
                                  final max = (ex['max_marks'] as num?)?.toDouble() ?? 100.0;
                                  final isAbs = ex['is_absent'] == true;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white12 : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$exName: ${isAbs ? "Abs" : "${obt.toStringAsFixed(0)}/${max.toStringAsFixed(0)}"}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isAbs ? Colors.red : (isDark ? Colors.white70 : Colors.grey.shade800),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D6B4E).withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${bObt.toStringAsFixed(0)} / ${bMax.toStringAsFixed(0)} (${bPct.toStringAsFixed(0)}%)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0D6B4E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                if (history.remarks != null && history.remarks!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Promotion Remarks: ${history.remarks}',
                    style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade600).copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubInfoChip(IconData icon, String text, bool isDark, {Color? color}) {
    final c = color ?? (isDark ? Colors.grey.shade300 : Colors.grey.shade700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTheme.getFontStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isDense: true,
          isExpanded: true,
          items: items
              .map((it) => DropdownMenuItem(value: it, child: Text(it, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
