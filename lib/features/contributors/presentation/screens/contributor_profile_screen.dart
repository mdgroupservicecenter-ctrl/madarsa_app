import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../../../students/data/models/student_model.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../students/presentation/bloc/students_bloc.dart';
import '../../../students/presentation/screens/student_profile_screen.dart';
import '../../data/models/contributor_model.dart';
import '../../data/repositories/contributor_repository.dart';

class ContributorProfileScreen extends StatefulWidget {
  final String contributorId;

  const ContributorProfileScreen({super.key, required this.contributorId});

  @override
  State<ContributorProfileScreen> createState() => _ContributorProfileScreenState();
}

class _ContributorProfileScreenState extends State<ContributorProfileScreen> {
  late final ContributorRepository _repository;
  late Future<Contributor> _profileFuture;

  List<Student> _sponsoredStudents = [];
  String? _selectedStudentId;
  bool _loadingStudents = false;
  final Map<String, Map<String, dynamic>> _studentAcademicSummaries = {};
  final Map<String, bool> _loadingSummary = {};

  @override
  void initState() {
    super.initState();
    _repository = ContributorRepository(ApiClient());
    _loadProfileAndStudents();
  }

  void _loadProfileAndStudents() {
    _profileFuture = _repository.getContributorProfile(widget.contributorId);
    _profileFuture.then((contributor) {
      if (mounted) {
        _loadContributorStudents(contributor);
      }
    }).catchError((e) {
      debugPrint('Error loading contributor profile: $e');
    });
  }

  void _refreshProfile() {
    setState(() {
      _loadProfileAndStudents();
    });
  }

  Future<void> _loadContributorStudents(Contributor contributor) async {
    setState(() => _loadingStudents = true);
    try {
      final List<Student> list = [];
      final seenIds = <String>{};

      // 1. Primary Authority: Load students explicitly listed in contributor.sponsoredStudents
      for (final sp in contributor.sponsoredStudents) {
        if (sp.id.isNotEmpty && !seenIds.contains(sp.id)) {
          try {
            final st = await StudentRepository(ApiClient()).getStudentById(sp.id);
            list.add(st);
            seenIds.add(sp.id);
          } catch (_) {
            list.add(
              Student(
                id: sp.id,
                registrationNumber: sp.grNo ?? sp.id,
                fullName: sp.fullName,
                fatherName: sp.fatherName,
                surname: sp.surname,
                grNo: sp.grNo,
                className: sp.className,
                conditionType: sp.conditionType,
                contributorId: widget.contributorId,
                contributorAmount: sp.contributorAmount,
                contributorName: contributor.name,
              ),
            );
            seenIds.add(sp.id);
          }
        }
      }

      // 2. Also check DB for any students strictly matching this contributor ID or exact name
      final dbStudents = await DatabaseHelper().getStudentsForContributor(
        contributorId: widget.contributorId,
        contributorName: contributor.name,
      );

      for (final st in dbStudents) {
        if (!seenIds.contains(st.id)) {
          list.add(st);
          seenIds.add(st.id);
        }
      }

      if (mounted) {
        setState(() {
          _sponsoredStudents = list;
          _loadingStudents = false;
          if (_sponsoredStudents.isNotEmpty) {
            if (_selectedStudentId == null || !_sponsoredStudents.any((s) => s.id == _selectedStudentId)) {
              _selectedStudentId = _sponsoredStudents.first.id;
            }
            final sel = _sponsoredStudents.firstWhere((s) => s.id == _selectedStudentId);
            _loadStudentAcademicSummary(sel);
          } else {
            _selectedStudentId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading contributor students: $e');
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  Future<void> _loadStudentAcademicSummary(Student student) async {
    if (_loadingSummary[student.id] == true) return;
    setState(() => _loadingSummary[student.id] = true);
    try {
      final summary = await DatabaseHelper().calculateStudentAcademicSummary(
        student.id,
        classId: student.className,
        fallbackMonthlyFees: student.monthlyFees,
        fallbackAdmissionFee: student.admissionFee,
        fallbackBookFee: student.bookFee,
        fallbackFeeStructure: student.feeStructure,
      );
      if (mounted) {
        setState(() {
          _studentAcademicSummaries[student.id] = summary;
          _loadingSummary[student.id] = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading student summary: $e');
      if (mounted) {
        setState(() => _loadingSummary[student.id] = false);
      }
    }
  }

  void _navigateToStudentProfile(Student student) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (routeContext, animation, secondaryAnimation) => BlocProvider(
          create: (_) => StudentsBloc(repository: StudentRepository(ApiClient())),
          child: StudentProfileScreen(
            studentId: student.id,
            initialStudent: student,
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, childWidget) {
          const begin = Offset(0.04, 0.0);
          const end = Offset.zero;
          final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: begin, end: end).animate(curve),
              child: childWidget,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 160),
      ),
    );
    _refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F1A) : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF161625) : Colors.white,
        elevation: 0.5,
        title: Text(
          'Contributor Profile',
          style: AppTheme.getFontStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: isDark ? Colors.white : Colors.black),
            onPressed: _refreshProfile,
          ),
        ],
      ),
      body: FutureBuilder<Contributor>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load contributor details: ${snapshot.error}',
                style: AppTheme.getFontStyle(color: AppTheme.errorColor),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: Text(context.tr('contributor_not_found')));
          }

          final contributor = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner Layout
                _buildHeaderBanner(contributor, isDark),
                const SizedBox(height: 24),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 800;

                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column - Details Card
                          Expanded(
                            flex: 1,
                            child: _buildDetailsCard(contributor, isDark),
                          ),
                          const SizedBox(width: 24),

                          // Right Column - Stats Overview & Students Table
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildStatsOverview(contributor, isDark),
                                const SizedBox(height: 20),
                                _buildStudentsListCard(contributor, isDark),
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        _buildStatsOverview(contributor, isDark),
                        const SizedBox(height: 16),
                        _buildDetailsCard(contributor, isDark),
                        const SizedBox(height: 16),
                        _buildStudentsListCard(contributor, isDark),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // ── Comprehensive Sponsored Student History & Fee Explorer Section ──
                _buildStudentHistorySection(contributor, isDark),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderBanner(Contributor contributor, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withAlpha(30),
            child: Text(
              contributor.name.isNotEmpty ? contributor.name[0].toUpperCase() : 'C',
              style: AppTheme.getFontStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contributor.name,
                  style: AppTheme.getFontStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sponsorship Contributor / کفیل',
                  style: AppTheme.getFontStyle(
                    fontSize: 13,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(Contributor contributor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161625) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Details',
            style: AppTheme.getFontStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          const Divider(height: 24),
          _buildDetailRow(Icons.phone_rounded, 'Phone', contributor.phone ?? '-'),
          const SizedBox(height: 16),
          _buildDetailRow(Icons.email_rounded, 'Email', contributor.email ?? '-'),
          const SizedBox(height: 16),
          _buildDetailRow(Icons.location_on_rounded, 'Address', contributor.address ?? '-'),
          const SizedBox(height: 16),
          _buildDetailRow(
            Icons.calendar_today_rounded,
            'Added Date',
            contributor.createdAt != null && contributor.createdAt!.length >= 10
                ? contributor.createdAt!.substring(0, 10)
                : '-',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTheme.getFontStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsOverview(Contributor contributor, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildSmallStatCard(
            'Students Sponsored',
            '${contributor.totalStudentsHelped}',
            Icons.school_rounded,
            AppTheme.primaryColor,
            isDark,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSmallStatCard(
            'Total Monthly Sponsorship',
            '₹${contributor.totalContributionAmount.toStringAsFixed(0)}',
            Icons.currency_rupee_rounded,
            Colors.orange.shade700,
            isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161625) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: AppTheme.getFontStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsListCard(Contributor contributor, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161625) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sponsored Students List',
                style: AppTheme.getFontStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              if (contributor.sponsoredStudents.isNotEmpty)
                Text(
                  'Click student to explore history below',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          const Divider(height: 24),
          contributor.sponsoredStudents.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      'No students sponsored yet.',
                      style: AppTheme.getFontStyle(color: Colors.grey.shade500),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 34,
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(label: Text('GR.NO.', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Student Name', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Class', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Sponsorship (Monthly)', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Action', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: contributor.sponsoredStudents.map((s) {
                      final isSelected = s.id == _selectedStudentId;
                      return DataRow(
                        selected: isSelected,
                        onSelectChanged: (_) {
                          setState(() => _selectedStudentId = s.id);
                          final match = _sponsoredStudents.where((st) => st.id == s.id).toList();
                          if (match.isNotEmpty) {
                            _loadStudentAcademicSummary(match.first);
                          }
                        },
                        cells: [
                          DataCell(Text(s.grNo ?? '-', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(s.fullName, style: AppTheme.getFontStyle())),
                          DataCell(Text(s.className ?? '-', style: AppTheme.getFontStyle())),
                          DataCell(
                            Text(
                              '₹${s.contributorAmount.toStringAsFixed(0)}',
                              style: AppTheme.getFontStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          DataCell(
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                side: BorderSide(color: AppTheme.primaryColor),
                              ),
                              onPressed: () {
                                setState(() => _selectedStudentId = s.id);
                                final match = _sponsoredStudents.where((st) => st.id == s.id).toList();
                                if (match.isNotEmpty) {
                                  _loadStudentAcademicSummary(match.first);
                                }
                              },
                              child: Text(
                                'View History',
                                style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ],
      ),
    );
  }

  // ── Comprehensive Sponsored Student History & Fee Explorer Section ──
  Widget _buildStudentHistorySection(Contributor contributor, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final scale = isCompact ? (constraints.maxWidth / 375.0).clamp(0.75, 1.0) : 1.0;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161625) : Colors.white,
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 6),
                blurRadius: 10 * scale,
                offset: Offset(0, 4 * scale),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 14 * scale),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0D6B4E).withAlpha(isDark ? 35 : 18),
                      const Color(0xFF0D6B4E).withAlpha(isDark ? 15 : 6),
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16 * scale)),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white.withAlpha(8) : const Color(0xFF0D6B4E).withAlpha(20),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(7 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D6B4E).withAlpha(isDark ? 45 : 25),
                        borderRadius: BorderRadius.circular(10 * scale),
                      ),
                      child: Icon(
                        Icons.history_edu_rounded,
                        size: 18 * scale,
                        color: const Color(0xFF0D6B4E),
                      ),
                    ),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Sponsored Student History & Fee Explorer',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 15 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8 * scale),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                                decoration: BoxDecoration(
                                  color: _sponsoredStudents.isNotEmpty
                                      ? const Color(0xFF0D6B4E).withAlpha(isDark ? 60 : 25)
                                      : Colors.grey.withAlpha(isDark ? 40 : 20),
                                  borderRadius: BorderRadius.circular(12 * scale),
                                  border: Border.all(
                                    color: _sponsoredStudents.isNotEmpty
                                        ? const Color(0xFF0D6B4E).withAlpha(80)
                                        : Colors.grey.withAlpha(50),
                                  ),
                                ),
                                child: Text(
                                  '${_sponsoredStudents.length} ${_sponsoredStudents.length == 1 ? 'Student' : 'Students'}',
                                  style: TextStyle(
                                    fontSize: 10.5 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: _sponsoredStudents.isNotEmpty
                                        ? const Color(0xFF0D6B4E)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 2 * scale),
                          Text(
                            'طالب علم کی مکمل تفصیل اور فیس ریکارڈ (Full profile history, monthly status & receipts)',
                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh Students',
                      icon: Icon(Icons.refresh_rounded, size: 18 * scale, color: const Color(0xFF0D6B4E)),
                      onPressed: () => _loadContributorStudents(contributor),
                    ),
                  ],
                ),
              ),

              // Section Body
              if (_loadingStudents)
                Padding(
                  padding: EdgeInsets.all(32 * scale),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0D6B4E)),
                        ),
                        SizedBox(height: 12 * scale),
                        Text(
                          'Loading sponsored students & fee history...',
                          style: TextStyle(fontSize: 12 * scale, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_sponsoredStudents.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 32 * scale, horizontal: 24 * scale),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(16 * scale),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
                          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                        ),
                        child: Icon(Icons.person_search_rounded, size: 36 * scale, color: Colors.grey.shade400),
                      ),
                      SizedBox(height: 12 * scale),
                      Text(
                        'No Students Sponsored by this Contributor',
                        style: AppTheme.getFontStyle(
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey.shade800,
                        ),
                      ),
                      SizedBox(height: 6 * scale),
                      Text(
                        'Jab kisi student ki admission ya fee structure me is contributor ko sponsor assign kiya jayega, to us student ki puri history, mahinawar attendance, fees, receipts aur report yahan show hogi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5 * scale,
                          color: Colors.grey.shade500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Render the interactive history view for selected student
                _buildActiveStudentHistoryDetails(contributor, isDark, scale),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveStudentHistoryDetails(Contributor contributor, bool isDark, double scale) {
    final selectedStudent = _sponsoredStudents.firstWhere(
      (s) => s.id == _selectedStudentId,
      orElse: () => _sponsoredStudents.first,
    );

    final summary = _studentAcademicSummaries[selectedStudent.id];
    final isLoadingSummary = _loadingSummary[selectedStudent.id] == true;

    // Financial calculations
    final feeTotal = (summary?['fee_total'] as num?)?.toDouble() ??
        (selectedStudent.monthlyFees != null ? selectedStudent.monthlyFees! * 12 : 0.0);
    final feePaid = (summary?['fee_paid'] as num?)?.toDouble() ?? 0.0;
    final feePending = (summary?['fee_pending'] as num?)?.toDouble() ?? (feeTotal - feePaid).clamp(0.0, double.infinity);
    final feePendingMonths = (summary?['fee_pending_months'] as num?)?.toInt() ?? 0;
    final feePaidMonths = (summary?['fee_paid_months'] as num?)?.toInt() ?? 0;

    // Sponsorship amount for this student
    double contributorMonthlySponsorship = 0.0;
    final spMatch = contributor.sponsoredStudents.where((s) => s.id == selectedStudent.id).toList();
    if (spMatch.isNotEmpty) {
      contributorMonthlySponsorship = spMatch.first.contributorAmount;
    } else {
      contributorMonthlySponsorship = selectedStudent.monthlyFees ?? 0.0;
    }

    final feeBreakdown = (summary?['fee_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final feePayments = (summary?['fee_payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final presentDays = (summary?['present_days'] as num?)?.toInt() ?? 0;
    final totalDays = (summary?['total_attendance_days'] as num?)?.toInt() ?? 0;
    final attPct = (summary?['attendance_percentage'] as num?)?.toDouble() ??
        (totalDays > 0 ? (presentDays / totalDays * 100) : 0.0);

    return Padding(
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Dropdown & Quick Selector ──
          Container(
            padding: EdgeInsets.all(12 * scale),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_search_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                    SizedBox(width: 8 * scale),
                    Text(
                      'Select Student to View History / طالب علم منتخب کریں:',
                      style: AppTheme.getFontStyle(
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white70 : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * scale),
                DropdownButtonFormField<String>(
                  key: ValueKey('contributor_student_dd_${_selectedStudentId ?? selectedStudent.id}'),
                  initialValue: _selectedStudentId ?? selectedStudent.id,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF252538) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10 * scale),
                      borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10 * scale),
                      borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10 * scale),
                      borderSide: const BorderSide(color: Color(0xFF0D6B4E), width: 1.5),
                    ),
                  ),
                  items: _sponsoredStudents.map((st) {
                    final grStr = (st.grNo != null && st.grNo!.isNotEmpty) ? ' (GR: ${st.grNo})' : '';
                    final classStr = (st.className != null && st.className!.isNotEmpty) ? ' • Class: ${st.className}' : '';
                    return DropdownMenuItem<String>(
                      value: st.id,
                      child: Row(
                        children: [
                          Icon(Icons.school_rounded, size: 15 * scale, color: const Color(0xFF0D6B4E)),
                          SizedBox(width: 8 * scale),
                          Expanded(
                            child: Text(
                              '${st.fullName}$classStr$grStr',
                              style: TextStyle(
                                fontSize: 12.5 * scale,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedStudentId = val);
                      final st = _sponsoredStudents.firstWhere((x) => x.id == val);
                      _loadStudentAcademicSummary(st);
                    }
                  },
                ),

                // Quick Choice Chips if 2 or more students
                if (_sponsoredStudents.length > 1) ...[
                  SizedBox(height: 8 * scale),
                  Wrap(
                    spacing: 8 * scale,
                    runSpacing: 6 * scale,
                    children: _sponsoredStudents.map((st) {
                      final isSelected = st.id == (_selectedStudentId ?? selectedStudent.id);
                      return ChoiceChip(
                        selected: isSelected,
                        avatar: Icon(
                          Icons.person_rounded,
                          size: 14 * scale,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                        ),
                        label: Text('${st.fullName} (${st.className ?? 'N/A'})'),
                        selectedColor: const Color(0xFF0D6B4E),
                        backgroundColor: isDark ? const Color(0xFF252538) : Colors.white,
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF0D6B4E)
                              : (isDark ? Colors.white12 : Colors.grey.shade300),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11 * scale,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedStudentId = st.id);
                            _loadStudentAcademicSummary(st);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),

          SizedBox(height: 14 * scale),

          // ── 2. Selected Student Banner & "Open Profile" button ──
          Container(
            padding: EdgeInsets.all(12 * scale),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22 * scale,
                  backgroundColor: const Color(0xFF0D6B4E).withAlpha(isDark ? 70 : 30),
                  child: Text(
                    selectedStudent.fullName.isNotEmpty
                        ? selectedStudent.fullName[0].toUpperCase()
                        : 'S',
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0D6B4E),
                    ),
                  ),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              selectedStudent.fullName,
                              style: TextStyle(
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8 * scale),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 2 * scale),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D6B4E).withAlpha(25),
                              borderRadius: BorderRadius.circular(6 * scale),
                              border: Border.all(color: const Color(0xFF0D6B4E).withAlpha(60)),
                            ),
                            child: Text(
                              contributorMonthlySponsorship > 0
                                  ? '₹${contributorMonthlySponsorship.toStringAsFixed(0)}/mo Sponsorship'
                                  : 'Sponsored Student',
                              style: TextStyle(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0D6B4E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 3 * scale),
                      Wrap(
                        spacing: 12 * scale,
                        runSpacing: 2 * scale,
                        children: [
                          if (selectedStudent.grNo != null && selectedStudent.grNo!.isNotEmpty)
                            Text('GR: ${selectedStudent.grNo}',
                                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                          if (selectedStudent.className != null && selectedStudent.className!.isNotEmpty)
                            Text('Class: ${selectedStudent.className}',
                                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                          if (selectedStudent.division != null && selectedStudent.division!.isNotEmpty)
                            Text('Div: ${selectedStudent.division}',
                                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                          if (selectedStudent.rollNumber != null && selectedStudent.rollNumber!.isNotEmpty)
                            Text('Roll: ${selectedStudent.rollNumber}',
                                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * scale),
                FilledButton.tonalIcon(
                  onPressed: () => _navigateToStudentProfile(selectedStudent),
                  icon: Icon(Icons.open_in_new_rounded, size: 13 * scale),
                  label: Text('Open Profile', style: TextStyle(fontSize: 11 * scale)),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 14 * scale),

          // ── 3. Metrics Loading / Content ──
          if (isLoadingSummary && summary == null)
            Padding(
              padding: EdgeInsets.all(24 * scale),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D6B4E)),
                ),
              ),
            )
          else ...[
            // ── 4 Financial Stats Grid ──
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 650;
                final cards = [
                  _buildStudentFeeMetricCard(
                    title: 'Total Session Fee (کل فیس)',
                    amount: feeTotal,
                    subtitle: 'Annual Session Expected',
                    color: const Color(0xFF1565C0),
                    icon: Icons.receipt_long_rounded,
                    isDark: isDark,
                    scale: scale,
                  ),
                  _buildStudentFeeMetricCard(
                    title: 'Contributor Sponsorship (امداد)',
                    amount: contributorMonthlySponsorship * 12,
                    subtitle: '₹${contributorMonthlySponsorship.toStringAsFixed(0)}/month Sponsorship',
                    color: const Color(0xFFE65100),
                    icon: Icons.volunteer_activism_rounded,
                    isDark: isDark,
                    scale: scale,
                  ),
                  _buildStudentFeeMetricCard(
                    title: 'Paid Fee (ادا شدہ فیس)',
                    amount: feePaid,
                    subtitle: feePaidMonths > 0 ? '$feePaidMonths Mo Cleared' : 'Total Deposited',
                    color: const Color(0xFF0D6B4E),
                    icon: Icons.check_circle_outline_rounded,
                    isDark: isDark,
                    scale: scale,
                  ),
                  _buildStudentFeeMetricCard(
                    title: 'Pending Fee (بقایا فیس)',
                    amount: feePending,
                    subtitle: feePendingMonths > 0 ? '$feePendingMonths Months Due' : 'All Cleared ✓',
                    color: feePending > 0 ? const Color(0xFFD32F2F) : const Color(0xFF0D6B4E),
                    icon: feePending > 0 ? Icons.pending_actions_rounded : Icons.verified_rounded,
                    isDark: isDark,
                    scale: scale,
                  ),
                ];

                if (isNarrow) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: cards[0]),
                          SizedBox(width: 8 * scale),
                          Expanded(child: cards[1]),
                        ],
                      ),
                      SizedBox(height: 8 * scale),
                      Row(
                        children: [
                          Expanded(child: cards[2]),
                          SizedBox(width: 8 * scale),
                          Expanded(child: cards[3]),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    SizedBox(width: 10 * scale),
                    Expanded(child: cards[1]),
                    SizedBox(width: 10 * scale),
                    Expanded(child: cards[2]),
                    SizedBox(width: 10 * scale),
                    Expanded(child: cards[3]),
                  ],
                );
              },
            ),

            SizedBox(height: 14 * scale),

            // ── Month-by-Month Fee Status Tracker ──
            _buildMonthlyStatusTracker(feeBreakdown, isDark, scale),

            SizedBox(height: 14 * scale),

            // ── Attendance Summary Card ──
            _buildAttendanceSummaryCard(
              presentDays: presentDays,
              totalDays: totalDays,
              attPct: attPct,
              isDark: isDark,
              scale: scale,
            ),

            SizedBox(height: 14 * scale),

            // ── Itemized Fee Heads Breakdown ──
            _buildFeeHeadsBreakdownTable(feeBreakdown, isDark, scale),

            SizedBox(height: 14 * scale),

            // ── Payment Transactions & PDF Receipts ──
            _buildPaymentTransactionsLog(selectedStudent, summary ?? {}, feePayments, isDark, scale),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentFeeMetricCard({
    required String title,
    required double amount,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool isDark,
    required double scale,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(
          color: color.withAlpha(isDark ? 60 : 35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(isDark ? 15 : 10),
            blurRadius: 8 * scale,
            offset: Offset(0, 2 * scale),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: EdgeInsets.all(5 * scale),
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 35 : 18),
                  borderRadius: BorderRadius.circular(8 * scale),
                ),
                child: Icon(icon, size: 14 * scale, color: color),
              ),
            ],
          ),
          SizedBox(height: 6 * scale),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 18 * scale,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 2 * scale),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10 * scale,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyStatusTracker(
      List<Map<String, dynamic>> feeBreakdown, bool isDark, double scale) {
    final monthlyHeads = feeBreakdown.where((h) {
      final billing = (h['billing_type']?.toString() ?? '').toLowerCase();
      final name = (h['fee_type_name']?.toString() ?? '').toLowerCase();
      return billing == 'monthly' || name.contains('tuition') || name.contains('monthly');
    }).toList();

    if (monthlyHeads.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<String> defaultMonthNames = [
      'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
      'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar',
    ];

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181826) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
              SizedBox(width: 8 * scale),
              Text(
                'Month-by-Month Fee Status (ماہانہ فیس کی تفصیل)',
                style: AppTheme.getFontStyle(
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          ...monthlyHeads.map((item) {
            final name = item['fee_type_name']?.toString() ?? 'Monthly Tuition Fee';
            final monthlyRate = (item['amount'] as num?)?.toDouble() ?? 0.0;
            final rawMonthsList = item['months_list'] as List? ?? [];
            List<String> monthNames = [];
            if (rawMonthsList.isNotEmpty) {
              monthNames = rawMonthsList.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
            }
            final monthsCount = (item['months_count'] as num?)?.toInt() ?? (monthNames.isNotEmpty ? monthNames.length : 12);
            if (monthNames.isEmpty) {
              monthNames = defaultMonthNames.take(monthsCount).toList();
              while (monthNames.length < monthsCount) {
                monthNames.add('M${monthNames.length + 1}');
              }
            }

            final totalExpected = (item['total_expected'] as num?)?.toDouble() ?? (monthlyRate * monthsCount);
            final totalPaid = (item['total_paid'] as num?)?.toDouble() ?? 0.0;
            final totalPending = (item['total_pending'] as num?)?.toDouble() ?? (totalExpected - totalPaid).clamp(0.0, double.infinity);
            final paidMonths = (item['paid_months'] as num?)?.toInt() ??
                (monthlyRate > 0 ? (totalPaid / monthlyRate).floor().clamp(0, monthsCount) : 0);
            final pendingMonths = (item['pending_months'] as num?)?.toInt() ?? (monthsCount - paidMonths).clamp(0, monthsCount);
            final double progress = totalExpected > 0 ? (totalPaid / totalExpected).clamp(0.0, 1.0) : 1.0;

            return Container(
              margin: EdgeInsets.only(bottom: 8 * scale),
              padding: EdgeInsets.all(12 * scale),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222236) : Colors.white,
                borderRadius: BorderRadius.circular(10 * scale),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: AppTheme.getFontStyle(
                              fontSize: 12 * scale,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            ),
                          ),
                          SizedBox(width: 8 * scale),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D6B4E).withAlpha(20),
                              borderRadius: BorderRadius.circular(6 * scale),
                            ),
                            child: Text(
                              '₹${monthlyRate.toStringAsFixed(0)}/mo',
                              style: TextStyle(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0D6B4E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        pendingMonths > 0
                            ? '$pendingMonths Mo Baki (Due: ₹${totalPending.toStringAsFixed(0)})'
                            : 'All $monthsCount Mo Paid ✓',
                        style: TextStyle(
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.bold,
                          color: pendingMonths > 0 ? Colors.red.shade700 : const Color(0xFF0D6B4E),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * scale),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4 * scale),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5 * scale,
                      backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        progress >= 1.0 ? const Color(0xFF0D6B4E) : const Color(0xFFE65100),
                      ),
                    ),
                  ),
                  SizedBox(height: 10 * scale),
                  Wrap(
                    spacing: 6 * scale,
                    runSpacing: 6 * scale,
                    children: List.generate(monthsCount, (idx) {
                      final mLabel = idx < monthNames.length ? monthNames[idx] : 'M${idx + 1}';
                      final bool isPaid = idx < paidMonths;

                      final Color bg = isPaid
                          ? (isDark ? const Color(0xFF064E3B).withAlpha(120) : const Color(0xFFDCFCE7))
                          : (isDark ? const Color(0xFF7F1D1D).withAlpha(100) : const Color(0xFFFEE2E2));
                      final Color border = isPaid
                          ? (isDark ? const Color(0xFF059669) : const Color(0xFF86EFAC))
                          : (isDark ? const Color(0xFFDC2626) : const Color(0xFFFCA5A5));
                      final Color textColor = isPaid
                          ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF166534))
                          : (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B));

                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(6 * scale),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPaid ? Icons.check_circle_rounded : Icons.pending_rounded,
                              size: 11 * scale,
                              color: textColor,
                            ),
                            SizedBox(width: 4 * scale),
                            Text(
                              mLabel,
                              style: TextStyle(
                                fontSize: 10 * scale,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummaryCard({
    required int presentDays,
    required int totalDays,
    required double attPct,
    required bool isDark,
    required double scale,
  }) {
    final absentDays = (totalDays - presentDays).clamp(0, 9999);
    final attProgress = totalDays > 0 ? (presentDays / totalDays).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2F23) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.green.withAlpha(isDark ? 60 : 80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_reg_rounded, size: 16 * scale, color: Colors.green.shade800),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Text(
                  'Academic Attendance Summary (حاضری کا ریکارڈ)',
                  style: AppTheme.getFontStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.green.shade900,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Text(
                  '${attPct.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          ClipRRect(
            borderRadius: BorderRadius.circular(4 * scale),
            child: LinearProgressIndicator(
              value: attProgress,
              minHeight: 6 * scale,
              backgroundColor: Colors.green.withAlpha(40),
              valueColor: AlwaysStoppedAnimation(
                attPct >= 75 ? Colors.green.shade700 : (attPct >= 50 ? Colors.amber.shade800 : Colors.red.shade700),
              ),
            ),
          ),
          SizedBox(height: 8 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Present: ${presentDays}d',
                style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.bold, color: Colors.green.shade800),
              ),
              Text(
                'Absent: ${absentDays}d',
                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade600),
              ),
              Text(
                'Total Working Days: ${totalDays}d',
                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeeHeadsBreakdownTable(
      List<Map<String, dynamic>> feeBreakdown, bool isDark, double scale) {
    if (feeBreakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181826) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
            child: Row(
              children: [
                Icon(Icons.list_alt_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                SizedBox(width: 8 * scale),
                Text(
                  'Itemized Fee Heads Breakdown',
                  style: AppTheme.getFontStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
            child: Column(
              children: feeBreakdown.map((item) {
                final name = item['fee_type_name']?.toString() ?? 'Fee Head';
                final expected = (item['total_expected'] as num?)?.toDouble() ?? 0.0;
                final paid = (item['total_paid'] as num?)?.toDouble() ?? 0.0;
                final pending = (item['total_pending'] as num?)?.toDouble() ?? (expected - paid).clamp(0.0, double.infinity);
                final disc = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
                final billing = item['billing_type']?.toString() ?? 'one_time';

                final isPaid = pending <= 0 && expected > 0;
                final isPartial = pending > 0 && paid > 0;

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 6 * scale),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              billing == 'monthly' ? 'Monthly Billing' : 'One Time Fee',
                              style: TextStyle(fontSize: 10 * scale, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      if (disc > 0)
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '-₹${disc.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                              Text('Concession', style: TextStyle(fontSize: 9.5 * scale, color: Colors.grey)),
                            ],
                          ),
                        ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${expected.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.grey.shade800,
                              ),
                            ),
                            Text('Expected', style: TextStyle(fontSize: 9.5 * scale, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${paid.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0D6B4E),
                              ),
                            ),
                            Text('Paid', style: TextStyle(fontSize: 9.5 * scale, color: Colors.grey)),
                          ],
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 2.5 * scale),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? Colors.green.withAlpha(25)
                              : (isPartial ? Colors.amber.withAlpha(25) : Colors.red.withAlpha(25)),
                          borderRadius: BorderRadius.circular(6 * scale),
                        ),
                        child: Text(
                          isPaid ? 'Paid' : (isPartial ? 'Partial' : 'Due'),
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                            color: isPaid
                                ? Colors.green.shade700
                                : (isPartial ? Colors.amber.shade900 : Colors.red.shade700),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentTransactionsLog(
    Student child,
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> payments,
    bool isDark,
    double scale,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181826) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                SizedBox(width: 8 * scale),
                Text(
                  'Payment History & Receipts (${payments.length})',
                  style: AppTheme.getFontStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
          if (payments.isEmpty)
            Padding(
              padding: EdgeInsets.all(20 * scale),
              child: Center(
                child: Text(
                  'No fee payments recorded yet for this sponsored student.',
                  style: TextStyle(fontSize: 11.5 * scale, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(10 * scale),
              itemCount: payments.length,
              separatorBuilder: (ctx, i) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
              itemBuilder: (context, idx) {
                final p = payments[idx];
                final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
                final feeType = p['fee_type']?.toString() ?? 'Tuition Fee';
                final dateStr = p['payment_date']?.toString() ?? '';
                final receiptNo = p['receipt_no']?.toString() ?? p['id']?.toString() ?? '';

                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8 * scale, horizontal: 4 * scale),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D6B4E).withAlpha(isDark ? 35 : 18),
                          borderRadius: BorderRadius.circular(8 * scale),
                        ),
                        child: Icon(Icons.receipt_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                      ),
                      SizedBox(width: 10 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  feeType,
                                  style: TextStyle(
                                    fontSize: 12.5 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                                SizedBox(width: 6 * scale),
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4 * scale),
                                  ),
                                  child: Text(
                                    'Paid',
                                    style: TextStyle(
                                      fontSize: 9.5 * scale,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 2 * scale),
                            Text(
                              'Date: $dateStr ${receiptNo.isNotEmpty ? '• Rec: $receiptNo' : ''}',
                              style: TextStyle(fontSize: 10.5 * scale, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${amt.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0D6B4E),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      IconButton(
                        tooltip: 'Print / Download PDF Receipt',
                        icon: Icon(Icons.print_rounded, size: 18 * scale, color: const Color(0xFF0D6B4E)),
                        onPressed: () async {
                          try {
                            await ReceiptPdfGenerator.printFeeReceipt(
                              studentName: child.fullName,
                              grNo: child.grNo ?? '',
                              className: child.className ?? '',
                              amountPaid: amt,
                              feeType: feeType,
                              remainingBalance: (summary['fee_pending'] as num?)?.toDouble() ?? 0.0,
                              date: dateStr.isNotEmpty ? dateStr : DateTime.now().toIso8601String(),
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to generate receipt: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
