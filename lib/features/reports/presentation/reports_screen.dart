import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:madarsa_app/core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/report_models.dart';
import 'bloc/reports_bloc.dart';
import '../../../core/network/api_client.dart';
import '../../../core/licensing/license_cubit.dart';
import '../../../core/licensing/license_model.dart';
import '../../licensing/presentation/upgrade_plan_dialog.dart';
import '../../../core/widgets/app_date_range_picker.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  String _selectedReport = 'Attendance'; // Attendance, Fees, Students
  DateTimeRange? _dateRange;
  List<String> _classesList = ['All'];
  String _selectedClass = 'All';

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _fetchReport();
  }

  Future<void> _fetchClasses() async {
    try {
      final response = await ApiClient().get('/classes');
      final List data = response.data ?? [];
      final names = data.map((item) => item['name'] as String).toList();
      setState(() {
        _classesList = ['All', ...names];
      });
    } catch (e) {
      debugPrint('Error fetching classes: $e');
    }
  }

  void _fetchReport() {
    final bloc = context.read<ReportsBloc>();
    final start = _dateRange?.start.toIso8601String().split('T')[0];
    final end = _dateRange?.end.toIso8601String().split('T')[0];

    switch (_selectedReport) {
      case 'Attendance':
        bloc.add(FetchAttendanceReport(
          startDate: start,
          endDate: end,
          className: _selectedClass,
        ));
        break;
      case 'Fees':
        bloc.add(FetchFeeReport(startDate: start, endDate: end));
        break;
      case 'Students':
        bloc.add(FetchStudentStats());
        break;
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await AppDateRangePicker.show(
      context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      title: 'Report Date Range',
    );

    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
      _fetchReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('reports_analytics'),
                      style: AppTheme.getFontStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.tr('reports_subtitle'),
                      style: AppTheme.getFontStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Report Type Selector
                _buildReportSelector(),
                const SizedBox(width: 12),
                if (_selectedReport == 'Attendance') ...[
                  _buildClassSelector(),
                  const SizedBox(width: 12),
                ],
                if (_selectedReport != 'Students')
                  _buildDateFilterButton(isDark),
                const SizedBox(width: 12),
                _buildExportButton(isDark),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Main Content
          Expanded(
            child: BlocBuilder<ReportsBloc, ReportsState>(
              builder: (context, state) {
                if (state is ReportsLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is ReportsError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('${context.tr('error')}: ${state.message}'),
                        ElevatedButton(
                          onPressed: _fetchReport,
                          child: Text(context.tr('try_again')),
                        ),
                      ],
                    ),
                  );
                }
                if (state is AttendanceReportLoaded) {
                  return _buildAttendanceReport(state.reports);
                }
                if (state is FeeReportLoaded) {
                  return _buildFeeReport(state.summary, state.breakdown);
                }
                if (state is StudentStatsLoaded) {
                  return _buildStudentReport(state.stats);
                }
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withAlpha(50)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedReport,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: AppTheme.getFontStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() => _selectedReport = newValue);
              _fetchReport();
            }
          },
          items: <String>['Attendance', 'Fees', 'Students']
              .map<DropdownMenuItem<String>>((String value) {
            String urduValue = value;
            if (value == 'Attendance') urduValue = context.tr('attendance');
            if (value == 'Fees') urduValue = context.tr('fees');
            if (value == 'Students') urduValue = context.tr('students');
            return DropdownMenuItem<String>(
              value: value,
              child: Text(urduValue),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildClassSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withAlpha(50)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedClass,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: AppTheme.getFontStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() => _selectedClass = newValue);
              _fetchReport();
            }
          },
          items: _classesList.map<DropdownMenuItem<String>>((String value) {
            String display = value;
            if (value == 'All') display = context.tr('all');
            return DropdownMenuItem<String>(
              value: value,
              child: Text(display),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDateFilterButton(bool isDark) {
    final rangeText = _dateRange == null
        ? context.tr('select_dates')
        : '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}';

    return OutlinedButton.icon(
      onPressed: _selectDateRange,
      icon: const Icon(Icons.calendar_today_rounded, size: 16),
      label: Text(rangeText, style: AppTheme.getFontStyle(fontSize: 14)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildExportButton(bool isDark) {
    return ElevatedButton.icon(
      onPressed: () {
        if (!_ensureFeatureAccess('reports_export', 'Export to PDF & Excel')) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('export_success'))),
        );
      },
      icon: const Icon(Icons.download_rounded, size: 16),
      label: Text(context.tr('export'), style: AppTheme.getFontStyle(fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Report Views ──────────────────────────────────────────

  Widget _buildAttendanceReport(List<AttendanceReport> reports) {
    if (reports.isEmpty) {
      return _buildEmptyState(context.tr('no_attendance_data'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildAttendanceChart(reports),
          const SizedBox(height: 24),
          _buildAttendanceTable(reports),
        ],
      ),
    );
  }

  Widget _buildFeeReport(FeeSummary summary, List<FeeBreakdown> breakdown) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Stat Cards
          Row(
            children: [
              _buildStatCard(context.tr('total_collected'), '₹${summary.totalCollected}', Colors.green),
              const SizedBox(width: 16),
              _buildStatCard(context.tr('total_pending'), '₹${summary.totalPending}', Colors.orange),
              const SizedBox(width: 16),
              _buildStatCard(context.tr('collection_rate'), 
                '${((summary.totalCollected / summary.totalExpected) * 100).toStringAsFixed(1)}%', 
                Colors.blue),
            ],
          ),
          const SizedBox(height: 24),
          _buildFeeBreakdownTable(breakdown),
        ],
      ),
    );
  }

  Widget _buildStudentReport(StudentStats stats) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatCard(context.tr('total_students'), '${stats.total}', AppTheme.primaryColor),
              const SizedBox(width: 16),
              ...stats.byGender.map((g) {
                String genderText = g.gender;
                if (g.gender == 'Male') genderText = context.tr('male');
                if (g.gender == 'Female') genderText = context.tr('female');
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: _buildStatCard(genderText, '${g.count}', 
                    g.gender == 'Male' ? Colors.blue : Colors.pink),
                );
              }),
            ],
          ),
          const SizedBox(height: 24),
          Text(context.tr('enrollment_class'), style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildClassStatsTable(stats.byClass),
        ],
      ),
    );
  }

  // ─── Widgets ──────────────────────────────────────────────

  Widget _buildStatCard(String title, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E32) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 8),
            Text(value, style: AppTheme.getFontStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceChart(List<AttendanceReport> reports) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 10,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= reports.length) return const SizedBox();
                  final date = reports[value.toInt()].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(DateFormat('Md').format(DateTime.parse(date)),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: reports.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(toY: e.value.present.toDouble(), color: Colors.green, width: 8),
                BarChartRodData(toY: e.value.absent.toDouble(), color: Colors.red, width: 8),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAttendanceTable(List<AttendanceReport> reports) {
    return _buildCardTable(
      columns: [
        context.tr('date'),
        context.tr('present'),
        context.tr('absent'),
        context.tr('late'),
        context.tr('absent_students'),
      ],
      rows: reports.map((r) => [
        DateFormat('MMM d, yyyy').format(DateTime.parse(r.date)),
        '${r.present}',
        '${r.absent}',
        '${r.late}',
        r.absentNames.isEmpty ? '-' : r.absentNames.join(', '),
      ]).toList(),
    );
  }

  Widget _buildFeeBreakdownTable(List<FeeBreakdown> breakdown) {
    return _buildCardTable(
      columns: [context.tr('fee_type'), context.tr('status'), context.tr('total_amount')],
      rows: breakdown.map((b) => [
        b.type,
        b.status,
        '₹${b.total}',
      ]).toList(),
    );
  }

  Widget _buildClassStatsTable(List<ClassStat> stats) {
    return _buildCardTable(
      columns: [context.tr('class_name'), context.tr('total'), context.tr('male'), context.tr('female')],
      rows: stats.map((s) => [
        s.className,
        '${s.count}',
        '${s.male}',
        '${s.female}',
      ]).toList(),
    );
  }

  Widget _buildCardTable({required List<String> columns, required List<List<String>> rows}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50),
        columns: columns.map((coll) => DataColumn(label: Text(coll, style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)))).toList(),
        rows: rows.map((row) => DataRow(cells: row.map((cell) => DataCell(Text(cell))).toList())).toList(),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: AppTheme.getFontStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
