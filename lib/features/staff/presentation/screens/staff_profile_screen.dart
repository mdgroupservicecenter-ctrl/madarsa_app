import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../../../students/data/models/student_model.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../students/presentation/bloc/students_bloc.dart';
import '../../../students/presentation/screens/student_profile_screen.dart';
import '../../data/models/staff_model.dart';
import '../widgets/staff_assignment_dialog.dart';
import '../widgets/staff_id_card_builder_dialog.dart';

class StaffProfileScreen extends StatefulWidget {
  final String staffId;
  final VoidCallback onBack;
  const StaffProfileScreen(
      {super.key, required this.staffId, required this.onBack});

  @override
  State<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends State<StaffProfileScreen>
    with SingleTickerProviderStateMixin {
  StaffMember? _staff;
  bool _loading = true;
  String? _error;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  // Staff Children & Fee State
  List<Student> _staffChildren = [];
  bool _loadingChildren = false;
  String? _selectedChildId;
  final Map<String, Map<String, dynamic>> _childFeeSummaries = {};
  final Map<String, bool> _loadingFeeSummary = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _loadStaff();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final resp = await ApiClient().get('/staff/${widget.staffId}');
      final raw = resp.data;
      final map = raw is Map ? (raw['data'] ?? raw) : raw;
      if (mounted) {
        final s = StaffMember.fromJson(map as Map<String, dynamic>);
        setState(() {
          _staff = s;
          _loading = false;
        });
        _animCtrl.forward();
        _loadStaffChildren(s);
      }
    } catch (e) {
      // Fallback to local SQLite database if API fails or offline
      try {
        final db = await DatabaseHelper().database;
        final rows = await db.query('staff', where: 'id = ?', whereArgs: [widget.staffId]);
        if (rows.isNotEmpty && mounted) {
          final s = StaffMember.fromJson(rows.first);
          setState(() {
            _staff = s;
            _loading = false;
          });
          _animCtrl.forward();
          _loadStaffChildren(s);
          return;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadStaffChildren(StaffMember staff) async {
    if (!mounted) return;
    setState(() => _loadingChildren = true);
    try {
      final children = await DatabaseHelper().getStudentsForStaff(
        staffId: staff.id,
        staffNo: staff.staffNo,
        staffName: staff.fullName,
      );
      if (mounted) {
        setState(() {
          _staffChildren = children;
          _loadingChildren = false;
          if (_staffChildren.isNotEmpty) {
            if (_selectedChildId == null ||
                !_staffChildren.any((c) => c.id == _selectedChildId)) {
              _selectedChildId = _staffChildren.first.id;
            }
            final selectedChild =
                _staffChildren.firstWhere((c) => c.id == _selectedChildId);
            _loadChildFeeSummary(selectedChild);
          } else {
            _selectedChildId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading staff children: $e');
      if (mounted) {
        setState(() => _loadingChildren = false);
      }
    }
  }

  Future<void> _loadChildFeeSummary(Student child) async {
    if (_loadingFeeSummary[child.id] == true) return;
    setState(() => _loadingFeeSummary[child.id] = true);
    try {
      final summary = await DatabaseHelper().calculateStudentAcademicSummary(
        child.id,
        fallbackMonthlyFees: child.monthlyFees,
        fallbackAdmissionFee: child.admissionFee,
        fallbackBookFee: child.bookFee,
        fallbackFeeStructure: child.feeStructure,
      );
      if (mounted) {
        setState(() {
          _childFeeSummaries[child.id] = summary;
          _loadingFeeSummary[child.id] = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading child fee summary: $e');
      if (mounted) {
        setState(() => _loadingFeeSummary[child.id] = false);
      }
    }
  }

  void _navigateToStudentProfile(Student child) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (routeContext, animation, secondaryAnimation) => BlocProvider(
          create: (_) => StudentsBloc(repository: StudentRepository(ApiClient())),
          child: StudentProfileScreen(
            studentId: child.id,
            initialStudent: child,
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
    if (mounted && _staff != null) {
      _loadStaffChildren(_staff!);
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Teacher':
        return const Color(0xFF0D6B4E);
      case 'Bavarchi':
        return const Color(0xFFE65100);
      case 'Nazim-e-Matbakh':
        return const Color(0xFFB8860B);
      case 'Accountant':
        return const Color(0xFF1565C0);
      case 'Worker':
        return const Color(0xFF37474F);
      case 'Office Staff':
        return const Color(0xFF6A1B9A);
      default:
        return const Color(0xFF555555);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Teacher':
        return Icons.school_rounded;
      case 'Bavarchi':
        return Icons.restaurant_rounded;
      case 'Nazim-e-Matbakh':
        return Icons.kitchen_rounded;
      case 'Accountant':
        return Icons.account_balance_rounded;
      case 'Worker':
        return Icons.construction_rounded;
      case 'Office Staff':
        return Icons.business_center_rounded;
      default:
        return Icons.work_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget body;
    if (_loading) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(context.tr('loading_profile'),
                style: AppTheme.getFontStyle(
                    fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      );
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withAlpha(15),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 32, color: Colors.red),
            ),
            const SizedBox(height: 16),
            Text(context.tr('failed_to_load_profile'),
                style: AppTheme.getFontStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!,
                  style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(context.tr('back')),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loadStaff,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.tr('retry')),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      final s = _staff!;
      final tc = _typeColor(s.staffType);

      body = FadeTransition(
        opacity: _fadeAnim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 800;
          final isCompact = constraints.maxWidth < 600;
          final scale = isCompact ? (constraints.maxWidth / 375.0).clamp(0.75, 1.0) : 1.0;

          return SingleChildScrollView(
            padding: EdgeInsets.all(isWide ? 28 : (16.0 * scale)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Back + Title Bar ──────────────────────────────────────
                _buildTopBar(isDark, isWide, scale),
                SizedBox(height: isWide ? 20 : (12.0 * scale)),

                // ── Hero Card ─────────────────────────────────────────────
                _buildHeroCard(s, isDark, isWide, tc, scale),
                SizedBox(height: isWide ? 20 : (12.0 * scale)),

                // ── Quick Stats ───────────────────────────────────────────
                _buildQuickStats(s, isDark, isWide, tc, scale),
                SizedBox(height: isWide ? 20 : (12.0 * scale)),

                // ── Details Grid ──────────────────────────────────────────
                isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildDetailCard(
                                  context.tr('personal_information'),
                                  Icons.person_rounded,
                                  const Color(0xFF6A1B9A),
                                  isDark,
                                  [
                                    _DetailRow(Icons.person_outline_rounded,
                                        context.tr('full_name'), s.fullName),
                                    _DetailRow(Icons.family_restroom_rounded,
                                        context.tr('father_name'), s.fatherName),
                                    _DetailRow(Icons.badge_rounded,
                                        context.tr('surname'), s.surname),
                                    _DetailRow(Icons.cake_rounded,
                                        context.tr('date_of_birth'), s.dateOfBirth),
                                    _DetailRow(
                                        s.gender == 'Male'
                                            ? Icons.male_rounded
                                            : Icons.female_rounded,
                                        context.tr('gender'),
                                        s.gender),
                                    _DetailRow(Icons.school_rounded,
                                        context.tr('qualification'), s.qualification),
                                    _DetailRow(Icons.timeline_rounded,
                                        context.tr('experience_years'),
                                        s.experienceYears > 0
                                            ? '${s.experienceYears} ${context.tr('years')}'
                                            : null),
                                  ],
                                  scale,
                                ),
                                SizedBox(height: isCompact ? (10.0 * scale) : 16),
                                _buildDetailCard(
                                  context.tr('contact_details'),
                                  Icons.contact_phone_rounded,
                                  const Color(0xFF1565C0),
                                  isDark,
                                  [
                                    _DetailRow(Icons.phone_rounded,
                                        context.tr('mobile'), s.mobileNo),
                                    _DetailRow(Icons.fingerprint_rounded,
                                        context.tr('aadhaar_no'), s.aadhaarNo),
                                    _DetailRow(Icons.emergency_rounded,
                                        context.tr('emergency_contact'),
                                        s.emergencyContact),
                                  ],
                                  scale,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: isCompact ? (10.0 * scale) : 16),
                          Expanded(
                            child: Column(
                              children: [
                                _buildDetailCard(
                                  context.tr('employment_details'),
                                  Icons.work_rounded,
                                  const Color(0xFF0D6B4E),
                                  isDark,
                                  [
                                    _DetailRow(Icons.numbers_rounded,
                                        context.tr('staff_no'), s.staffNo),
                                    _DetailRow(Icons.work_outline_rounded,
                                        context.tr('type'), s.staffType),
                                    _DetailRow(Icons.calendar_month_rounded,
                                        context.tr('joining_date'), s.joiningDate),
                                    _DetailRow(Icons.date_range_rounded,
                                        context.tr('joining_date_hijri'),
                                        s.joiningDateH),
                                    _DetailRow(Icons.currency_rupee_rounded,
                                        context.tr('monthly_salary_inr'),
                                        s.salary > 0
                                            ? '₹${s.salary.toStringAsFixed(0)}'
                                            : null),
                                    _DetailRow(Icons.admin_panel_settings_rounded,
                                        context.tr('roles'), s.roleName),
                                  ],
                                  scale,
                                ),
                                SizedBox(height: isCompact ? (10.0 * scale) : 16),
                                _buildDetailCard(
                                  context.tr('address'),
                                  Icons.location_on_rounded,
                                  const Color(0xFFE65100),
                                  isDark,
                                  [
                                    _DetailRow(Icons.home_rounded,
                                        'Area / Room No.', s.address),
                                    _DetailRow(Icons.holiday_village_rounded,
                                        context.tr('village'), s.village),
                                    _DetailRow(Icons.map_rounded,
                                        context.tr('taluka'), s.taluka),
                                    _DetailRow(Icons.location_city_rounded,
                                        context.tr('district'), s.district),
                                    _DetailRow(Icons.flag_rounded,
                                        context.tr('state'), s.state),
                                    _DetailRow(Icons.pin_drop_rounded,
                                        context.tr('pincode'), s.pinCode),
                                  ],
                                  scale,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildDetailCard(
                            context.tr('personal_information'),
                            Icons.person_rounded,
                            const Color(0xFF6A1B9A),
                            isDark,
                            [
                              _DetailRow(Icons.person_outline_rounded,
                                  context.tr('full_name'), s.fullName),
                              _DetailRow(Icons.family_restroom_rounded,
                                  context.tr('father_name'), s.fatherName),
                              _DetailRow(Icons.badge_rounded,
                                  context.tr('surname'), s.surname),
                              _DetailRow(Icons.cake_rounded,
                                  context.tr('date_of_birth'), s.dateOfBirth),
                              _DetailRow(
                                  s.gender == 'Male'
                                      ? Icons.male_rounded
                                      : Icons.female_rounded,
                                  context.tr('gender'),
                                  s.gender),
                              _DetailRow(Icons.school_rounded,
                                  context.tr('qualification'), s.qualification),
                              _DetailRow(Icons.timeline_rounded,
                                  context.tr('experience_years'),
                                  s.experienceYears > 0
                                      ? '${s.experienceYears} ${context.tr('years')}'
                                      : null),
                            ],
                            scale,
                          ),
                          SizedBox(height: isCompact ? (10.0 * scale) : 12),
                          _buildDetailCard(
                            context.tr('employment_details'),
                            Icons.work_rounded,
                            const Color(0xFF0D6B4E),
                            isDark,
                            [
                              _DetailRow(Icons.numbers_rounded,
                                  context.tr('staff_no'), s.staffNo),
                              _DetailRow(Icons.work_outline_rounded,
                                  context.tr('type'), s.staffType),
                              _DetailRow(Icons.calendar_month_rounded,
                                  context.tr('joining_date'), s.joiningDate),
                              _DetailRow(Icons.date_range_rounded,
                                  context.tr('joining_date_hijri'),
                                  s.joiningDateH),
                              _DetailRow(Icons.currency_rupee_rounded,
                                  context.tr('monthly_salary_inr'),
                                  s.salary > 0
                                      ? '₹${s.salary.toStringAsFixed(0)}'
                                      : null),
                              _DetailRow(Icons.admin_panel_settings_rounded,
                                  context.tr('roles'), s.roleName),
                            ],
                            scale,
                          ),
                          SizedBox(height: isCompact ? (10.0 * scale) : 12),
                          _buildDetailCard(
                            context.tr('contact_details'),
                            Icons.contact_phone_rounded,
                            const Color(0xFF1565C0),
                            isDark,
                            [
                              _DetailRow(Icons.phone_rounded,
                                  context.tr('mobile'), s.mobileNo),
                              _DetailRow(Icons.fingerprint_rounded,
                                  context.tr('aadhaar_no'), s.aadhaarNo),
                              _DetailRow(Icons.emergency_rounded,
                                  context.tr('emergency_contact'),
                                  s.emergencyContact),
                            ],
                            scale,
                          ),
                          SizedBox(height: isCompact ? (10.0 * scale) : 12),
                          _buildDetailCard(
                            context.tr('address'),
                            Icons.location_on_rounded,
                            const Color(0xFFE65100),
                            isDark,
                            [
                              _DetailRow(Icons.home_rounded,
                                  'Area / Room No.', s.address),
                              _DetailRow(Icons.holiday_village_rounded,
                                  context.tr('village'), s.village),
                              _DetailRow(Icons.map_rounded,
                                  context.tr('taluka'), s.taluka),
                              _DetailRow(Icons.location_city_rounded,
                                  context.tr('district'), s.district),
                              _DetailRow(Icons.flag_rounded,
                                  context.tr('state'), s.state),
                              _DetailRow(Icons.pin_drop_rounded,
                                  context.tr('pincode'), s.pinCode),
                            ],
                            scale,
                          ),
                        ],
                      ),

                // ── Assigned Books Section ──────────────────────────────────
                SizedBox(height: isCompact ? (12.0 * scale) : 16),
                _buildAssignedBooksCard(s.assignedBooks ?? [], isDark, s.id, scale),

                // ── Staff Children & Fees Section ───────────────────────────
                SizedBox(height: isCompact ? (12.0 * scale) : 16),
                _buildStaffChildrenFeeSection(s, isDark, scale),

                // ── Note Section ──────────────────────────────────────────
                if (s.note != null && s.note!.isNotEmpty) ...[
                  SizedBox(height: isCompact ? (12.0 * scale) : 16),
                  _buildNoteCard(s.note!, isDark, scale),
                ],

                  SizedBox(height: isCompact ? (40.0 * scale) : 60),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF12121E) : const Color(0xFFF8F9FA),
      body: SafeArea(child: body),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool isDark, bool isWide, double scale) {
    return Row(
      children: [
        InkWell(
          onTap: widget.onBack,
          borderRadius: BorderRadius.circular(12 * scale),
          child: Container(
            padding: EdgeInsets.all(10 * scale),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(
                color:
                    isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
              ),
            ),
            child: Icon(Icons.arrow_back_rounded,
                size: 20 * scale,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          ),
        ),
        SizedBox(width: 14 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('staff_profile'),
                style: AppTheme.getFontStyle(
                  fontSize: isWide ? 24 : (20 * scale),
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                context.tr('detailed_staff_information'),
                style: AppTheme.getFontStyle(
                    fontSize: 12 * scale, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        InkWell(
          onTap: _staff != null
              ? () => StaffIdCardBuilderDialog.show(context, _staff!)
              : null,
          borderRadius: BorderRadius.circular(10 * scale),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10 * scale),
              border: Border.all(
                color:
                    isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_rounded,
                    size: 16 * scale, color: const Color(0xFF0D6B4E)),
                SizedBox(width: 6 * scale),
                Text(
                  'Print ID Card',
                  style: AppTheme.getFontStyle(
                    fontSize: 12 * scale,
                    color: const Color(0xFF0D6B4E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero Card ───────────────────────────────────────────────────────────────
  Widget _buildHeroCard(
      StaffMember s, bool isDark, bool isWide, Color tc, double scale) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20 * scale),
        boxShadow: [
          BoxShadow(
            color: tc.withAlpha(60),
            blurRadius: 30 * scale,
            offset: Offset(0, 10 * scale),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * scale),
        child: Stack(
          children: [
            // Main gradient bg
            Container(
              padding: EdgeInsets.all(isWide ? 28 : (20.0 * scale)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    tc,
                    Color.lerp(tc, const Color(0xFF1A1A2E), 0.4)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: isWide ? 90 : (70.0 * scale),
                    height: isWide ? 90 : (70.0 * scale),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(20),
                      border: Border.all(
                        color: Colors.white.withAlpha(50),
                        width: 3 * scale,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(30),
                          blurRadius: 12 * scale,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: s.photoPath != null && s.photoPath!.isNotEmpty
                          ? Image.network(
                              '${ApiConstants.baseUrl.replaceAll('/api', '')}${s.photoPath}',
                              width: isWide ? 90 : (70.0 * scale),
                              height: isWide ? 90 : (70.0 * scale),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Center(
                                child: Text(
                                  s.initials,
                                  style: AppTheme.getFontStyle(
                                    fontSize: isWide ? 30 : (24.0 * scale),
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                s.initials,
                                style: AppTheme.getFontStyle(
                                  fontSize: isWide ? 30 : (24.0 * scale),
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(width: isWide ? 24 : (16.0 * scale)),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.fullName,
                          style: AppTheme.getFontStyle(
                            fontSize: isWide ? 24 : (20.0 * scale),
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (s.fatherName != null &&
                            s.fatherName!.isNotEmpty)
                          Text(
                            '${context.tr('son_of')} ${s.fatherName}',
                            style: AppTheme.getFontStyle(
                              fontSize: 13 * scale,
                              color: Colors.white.withAlpha(170),
                            ),
                          ),
                        SizedBox(height: 10 * scale),
                        Wrap(
                          spacing: 8 * scale,
                          runSpacing: 6 * scale,
                          children: [
                            _HeroBadge(
                              icon: _typeIcon(s.staffType),
                              label: s.staffType,
                              scale: scale,
                            ),
                            _HeroBadge(
                              icon: s.isActive
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              label: s.isActive ? context.tr('active') : context.tr('inactive'),
                              color: s.isActive
                                  ? Colors.green.shade300
                                  : Colors.red.shade300,
                              scale: scale,
                            ),
                            _HeroBadge(
                              icon: Icons.tag_rounded,
                              label: s.staffNo,
                              scale: scale,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Salary badge (wide only)
                  if (isWide && s.salary > 0)
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20 * scale, vertical: 14 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(16 * scale),
                        border: Border.all(
                            color: Colors.white.withAlpha(25)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '₹${s.salary.toStringAsFixed(0)}',
                            style: AppTheme.getFontStyle(
                              fontSize: 26 * scale,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '/month',
                            style: AppTheme.getFontStyle(
                              fontSize: 11 * scale,
                              color: Colors.white.withAlpha(150),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Decorative circles
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(8),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -30,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick Stats ─────────────────────────────────────────────────────────────
  Widget _buildQuickStats(
      StaffMember s, bool isDark, bool isWide, Color tc, double scale) {
    final stats = <_QuickStat>[
      if (s.mobileNo != null && s.mobileNo!.isNotEmpty)
        _QuickStat(Icons.phone_rounded, 'Mobile', s.mobileNo!,
            const Color(0xFF1565C0)),
      if (s.joiningDate != null && s.joiningDate!.isNotEmpty)
        _QuickStat(Icons.calendar_month_rounded, 'Joined',
            s.joiningDate!, const Color(0xFF0D6B4E)),
      if (s.qualification != null && s.qualification!.isNotEmpty)
        _QuickStat(Icons.school_rounded, 'Qualification',
            s.qualification!, const Color(0xFF6A1B9A)),
      if (s.village != null && s.village!.isNotEmpty)
        _QuickStat(Icons.location_on_rounded, 'Location',
            '${s.village}${s.district != null ? ', ${s.district}' : ''}',
            const Color(0xFFE65100)),
    ];

    if (stats.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 80 * scale,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stats.length,
        separatorBuilder: (_, __) => SizedBox(width: 12 * scale),
        itemBuilder: (_, i) {
          final stat = stats[i];
          return Container(
            width: isWide ? 220 : (180.0 * scale),
            padding: EdgeInsets.all(14 * scale),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(14 * scale),
              border: Border.all(
                color: isDark
                    ? Colors.white.withAlpha(10)
                    : stat.color.withAlpha(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: stat.color.withAlpha(isDark ? 10 : 8),
                  blurRadius: 10 * scale,
                  offset: Offset(0, 3 * scale),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40 * scale,
                  height: 40 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stat.color.withAlpha(isDark ? 30 : 15),
                  ),
                  child:
                      Icon(stat.icon, size: 18 * scale, color: stat.color),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stat.label,
                        style: AppTheme.getFontStyle(
                          fontSize: 10 * scale,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Text(
                        stat.value,
                        style: AppTheme.getFontStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Detail Card ─────────────────────────────────────────────────────────────
  Widget _buildDetailCard(String title, IconData icon, Color accent,
      bool isDark, List<_DetailRow> rows, double scale) {
    final visibleRows =
        rows.where((r) => r.value != null && r.value!.isNotEmpty).toList();
    if (visibleRows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 15 : 5),
            blurRadius: 12 * scale,
            offset: Offset(0, 4 * scale),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 14 * scale),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withAlpha(isDark ? 20 : 12),
                  accent.withAlpha(isDark ? 8 : 4),
                ],
              ),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(18 * scale)),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withAlpha(6)
                      : accent.withAlpha(15),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6 * scale),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withAlpha(isDark ? 40 : 20),
                  ),
                  child: Icon(icon, size: 14 * scale, color: accent),
                ),
                SizedBox(width: 10 * scale),
                Text(
                  title,
                  style: AppTheme.getFontStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8 * scale, vertical: 3 * scale),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(isDark ? 25 : 12),
                    borderRadius: BorderRadius.circular(8 * scale),
                  ),
                  child: Text(
                    '${visibleRows.length} ${context.tr('fields')}',
                    style: AppTheme.getFontStyle(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Rows
          Padding(
            padding: EdgeInsets.all(6 * scale),
            child: Column(
              children: visibleRows.asMap().entries.map((entry) {
                final r = entry.value;
                final isLast = entry.key == visibleRows.length - 1;
                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14 * scale, vertical: 10 * scale),
                      child: Row(
                        children: [
                          Icon(r.icon,
                              size: 16 * scale,
                              color: isDark
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade400),
                          SizedBox(width: 12 * scale),
                          SizedBox(
                            width: 120 * scale,
                            child: Text(
                              r.label,
                              style: AppTheme.getFontStyle(
                                fontSize: 12 * scale,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              r.value!,
                              style: AppTheme.getFontStyle(
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        indent: 44 * scale,
                        color: isDark
                            ? Colors.white.withAlpha(6)
                            : Colors.grey.shade100,
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

  // ── Note Card ───────────────────────────────────────────────────────────────
  Widget _buildNoteCard(String note, bool isDark, double scale) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(
          color: isDark ? Colors.amber.withAlpha(30) : Colors.amber.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8 * scale),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.withAlpha(isDark ? 30 : 20),
            ),
            child: Icon(Icons.sticky_note_2_rounded,
                size: 16 * scale, color: Colors.amber.shade700),
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('note'),
                  style: AppTheme.getFontStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade800,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  note,
                  style: AppTheme.getFontStyle(
                    fontSize: 13 * scale,
                    color: isDark
                        ? Colors.white.withAlpha(180)
                        : Colors.amber.shade900,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedBooksCard(List<dynamic> books, bool isDark, String staffId, double scale) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2D) : Colors.white,
        borderRadius: BorderRadius.circular(16 * scale),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withAlpha(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 15 * scale,
            offset: Offset(0, 5 * scale),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFFB8860B).withAlpha(15),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16 * scale),
                topRight: Radius.circular(16 * scale),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black.withAlpha(12),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB8860B).withAlpha(30),
                    borderRadius: BorderRadius.circular(8 * scale),
                  ),
                  child: Icon(Icons.menu_book_rounded, size: 16 * scale, color: const Color(0xFFB8860B)),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Text(
                    context.tr('assigned_books'),
                    style: AppTheme.getFontStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openAssignmentDialog(staffId),
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(context.tr('edit')),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB8860B),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: books.isEmpty
              ? Text(context.tr('no_books_assigned_yet'), style: AppTheme.getFontStyle(color: Colors.grey))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: books.map((b) {
                    return Tooltip(
                      message: '${b['class_name']} -> ${b['course_name']} -> ${b['book_name']}',
                      child: Chip(
                        avatar: Icon(Icons.class_, size: 14, color: isDark ? Colors.white : Colors.black87),
                        label: Text('${b['book_name']} (${b['class_name']})', style: AppTheme.getFontStyle(fontSize: 12)),
                        backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade100,
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                      ),
                    );
                  }).toList(),
                ),
          ),
        ],
      ),
    );
  }

  void _openAssignmentDialog(String staffId) {
    if (context.isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StaffAssignmentDialog(staffId: staffId, onSaved: _loadStaff),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => StaffAssignmentDialog(staffId: staffId, onSaved: _loadStaff),
      );
    }
  }

  // ── Staff Children & Fee Section ───────────────────────────────────────────
  Widget _buildStaffChildrenFeeSection(StaffMember staff, bool isDark, double scale) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18 * scale),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 15 : 5),
            blurRadius: 12 * scale,
            offset: Offset(0, 4 * scale),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section Header ───────────────────────────────────────────────
          Container(
            padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 14 * scale),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0D6B4E).withAlpha(isDark ? 30 : 15),
                  const Color(0xFF0D6B4E).withAlpha(isDark ? 10 : 5),
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18 * scale)),
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
                    Icons.family_restroom_rounded,
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
                              'Staff Children & Fees Details',
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
                              color: _staffChildren.isNotEmpty
                                  ? const Color(0xFF0D6B4E).withAlpha(isDark ? 60 : 25)
                                  : Colors.grey.withAlpha(isDark ? 40 : 20),
                              borderRadius: BorderRadius.circular(12 * scale),
                              border: Border.all(
                                color: _staffChildren.isNotEmpty
                                    ? const Color(0xFF0D6B4E).withAlpha(80)
                                    : Colors.grey.withAlpha(50),
                              ),
                            ),
                            child: Text(
                              '${_staffChildren.length} ${_staffChildren.length == 1 ? 'Child' : 'Children'}',
                              style: TextStyle(
                                fontSize: 10.5 * scale,
                                fontWeight: FontWeight.bold,
                                color: _staffChildren.isNotEmpty
                                    ? const Color(0xFF0D6B4E)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        'اسٹاف کے بچے اور فیس کا ریکارڈ (Enrolled children & academic fee status)',
                        style: TextStyle(
                          fontSize: 11 * scale,
                          color: Colors.grey.shade500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Children',
                  icon: Icon(Icons.refresh_rounded, size: 18 * scale, color: const Color(0xFF0D6B4E)),
                  onPressed: () => _loadStaffChildren(staff),
                ),
              ],
            ),
          ),

          // ── Section Body ─────────────────────────────────────────────────
          if (_loadingChildren)
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
                      'Loading staff children & fees...',
                      style: TextStyle(fontSize: 12 * scale, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            )
          else if (_staffChildren.isEmpty)
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
                    child: Icon(Icons.child_care_rounded, size: 36 * scale, color: Colors.grey.shade400),
                  ),
                  SizedBox(height: 12 * scale),
                  Text(
                    'No Children Linked to this Staff Member',
                    style: AppTheme.getFontStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade800,
                    ),
                  ),
                  SizedBox(height: 6 * scale),
                  Text(
                    'Jab aap kisi student ki fee condition me "Staff Child" select karenge aur is staff ko select karenge, to unke bachhe ka pura fee record, concessions, mahinawar status or receipt yahan show hoga.',
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
            Builder(
              builder: (context) {
                final selectedChild = _staffChildren.firstWhere(
                  (c) => c.id == _selectedChildId,
                  orElse: () => _staffChildren.first,
                );
                final summary = _childFeeSummaries[selectedChild.id];
                final isLoadingSummary = _loadingFeeSummary[selectedChild.id] == true;

                final feeTotal = (summary?['fee_total'] as num?)?.toDouble() ?? 0.0;
                final feePaid = (summary?['fee_paid'] as num?)?.toDouble() ?? 0.0;
                final feePending = (summary?['fee_pending'] as num?)?.toDouble() ?? 0.0;
                final pendingMonths = (summary?['fee_pending_months'] as num?)?.toInt() ?? 0;
                final feeBreakdown = (summary?['fee_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                final feePayments = (summary?['fee_payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                // Calculate total discount from breakdown or child contributor amount
                double totalDiscount = 0.0;
                for (final item in feeBreakdown) {
                  final d = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
                  totalDiscount += d;
                }
                if (totalDiscount <= 0 && selectedChild.contributorAmount != null && selectedChild.contributorAmount! > 0) {
                  totalDiscount = selectedChild.contributorAmount!;
                }

                return Padding(
                  padding: EdgeInsets.all(16 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Child Selector Dropdown & Quick Chips ──────────────
                      Container(
                        padding: EdgeInsets.all(12 * scale),
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
                                Icon(Icons.swap_horiz_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                                SizedBox(width: 6 * scale),
                                Text(
                                  'Select Child to View Details / بچہ منتخب کریں:',
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
                              key: ValueKey('staff_child_dd_${_selectedChildId ?? selectedChild.id}'),
                              initialValue: _selectedChildId ?? selectedChild.id,
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
                              items: _staffChildren.map((c) {
                                final grStr = (c.grNo != null && c.grNo!.isNotEmpty) ? ' (GR: ${c.grNo})' : '';
                                final classStr = (c.className != null && c.className!.isNotEmpty) ? ' • ${c.className}' : '';
                                return DropdownMenuItem<String>(
                                  value: c.id,
                                  child: Row(
                                    children: [
                                      Icon(Icons.school_rounded, size: 15 * scale, color: const Color(0xFF0D6B4E)),
                                      SizedBox(width: 8 * scale),
                                      Expanded(
                                        child: Text(
                                          '${c.fullName}$classStr$grStr',
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
                                  setState(() => _selectedChildId = val);
                                  final c = _staffChildren.firstWhere((x) => x.id == val);
                                  _loadChildFeeSummary(c);
                                }
                              },
                            ),

                            // Quick Choice Chips for 2-3 children
                            if (_staffChildren.length > 1) ...[
                              SizedBox(height: 8 * scale),
                              Wrap(
                                spacing: 8 * scale,
                                runSpacing: 6 * scale,
                                children: _staffChildren.map((child) {
                                  final isSelected = child.id == (_selectedChildId ?? selectedChild.id);
                                  return ChoiceChip(
                                    selected: isSelected,
                                    avatar: Icon(
                                      Icons.person_rounded,
                                      size: 14 * scale,
                                      color: isSelected
                                          ? Colors.white
                                          : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                                    ),
                                    label: Text('${child.fullName} (${child.className ?? 'N/A'})'),
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
                                        setState(() => _selectedChildId = child.id);
                                        _loadChildFeeSummary(child);
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

                      // ── Selected Child Banner & Profile Link ─────────────
                      Container(
                        padding: EdgeInsets.all(12 * scale),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF232336) : const Color(0xFFF1F5F9),
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
                                selectedChild.fullName.isNotEmpty
                                    ? selectedChild.fullName[0].toUpperCase()
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
                                          selectedChild.fullName,
                                          style: AppTheme.getFontStyle(
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
                                          color: const Color(0xFFB8860B).withAlpha(25),
                                          borderRadius: BorderRadius.circular(6 * scale),
                                          border: Border.all(color: const Color(0xFFB8860B).withAlpha(60)),
                                        ),
                                        child: Text(
                                          selectedChild.conditionType ?? 'Staff Child',
                                          style: TextStyle(
                                            fontSize: 10 * scale,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFB8860B),
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
                                      if (selectedChild.grNo != null && selectedChild.grNo!.isNotEmpty)
                                        Text('GR: ${selectedChild.grNo}',
                                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                                      if (selectedChild.className != null && selectedChild.className!.isNotEmpty)
                                        Text('Class: ${selectedChild.className}',
                                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                                      if (selectedChild.division != null && selectedChild.division!.isNotEmpty)
                                        Text('Div: ${selectedChild.division}',
                                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                                      if (selectedChild.rollNumber != null && selectedChild.rollNumber!.isNotEmpty)
                                        Text('Roll: ${selectedChild.rollNumber}',
                                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 8 * scale),
                            FilledButton.tonalIcon(
                              onPressed: () => _navigateToStudentProfile(selectedChild),
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

                      // ── Fee Metrics Loading / Content ─────────────────────
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
                        // ── 4 Stats Grid ──────────────────────────────────
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 650;
                            final cards = [
                              _buildChildFeeMetricCard(
                                title: 'Total Fee (کل فیس)',
                                amount: feeTotal,
                                subtitle: 'Expected Session Fees',
                                color: const Color(0xFF1565C0),
                                icon: Icons.receipt_long_rounded,
                                isDark: isDark,
                                scale: scale,
                              ),
                              _buildChildFeeMetricCard(
                                title: 'Staff Concession (رعایت)',
                                amount: totalDiscount,
                                subtitle: totalDiscount > 0 ? 'Discount Applied' : 'Standard Rate',
                                color: const Color(0xFFE65100),
                                icon: Icons.discount_rounded,
                                isDark: isDark,
                                scale: scale,
                              ),
                              _buildChildFeeMetricCard(
                                title: 'Paid Fee (ادا شدہ)',
                                amount: feePaid,
                                subtitle: 'Total Received',
                                color: const Color(0xFF0D6B4E),
                                icon: Icons.check_circle_outline_rounded,
                                isDark: isDark,
                                scale: scale,
                              ),
                              _buildChildFeeMetricCard(
                                title: 'Pending Fee (بقایا)',
                                amount: feePending,
                                subtitle: pendingMonths > 0 ? '$pendingMonths Months Due' : 'All Clear ✓',
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

                        // ── Month-by-Month Fee Status Tracker ──────────────
                        _buildChildMonthlyTracker(feeBreakdown, isDark, scale),

                        SizedBox(height: 14 * scale),

                        // ── Fee Heads Itemized Breakdown ───────────────────
                        _buildChildFeeBreakdownTable(feeBreakdown, isDark, scale),

                        SizedBox(height: 14 * scale),

                        // ── Payment Transactions & PDF Receipts ───────────
                        _buildChildPaymentsList(selectedChild, summary ?? {}, feePayments, isDark, scale),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChildFeeMetricCard({
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

  Widget _buildChildMonthlyTracker(
      List<Map<String, dynamic>> feeBreakdown, bool isDark, double scale) {
    // Look for monthly heads
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
            final paidMonths = (item['paid_months'] as num?)?.toInt() ?? (monthlyRate > 0 ? (totalPaid / monthlyRate).floor().clamp(0, monthsCount) : 0);
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

  Widget _buildChildFeeBreakdownTable(
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

  Widget _buildChildPaymentsList(
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
                  'No fee payments recorded yet for this child.',
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
                final feeType = p['fee_type']?.toString() ?? 'Fee';
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

// ── Data classes ──────────────────────────────────────────────────────────────
class _HeroBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final double scale;

  const _HeroBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13 * scale, color: color ?? Colors.white.withAlpha(200)),
          SizedBox(width: 5 * scale),
          Text(
            label,
            style: AppTheme.getFontStyle(
              fontSize: 11 * scale,
              fontWeight: FontWeight.w600,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _QuickStat(this.icon, this.label, this.value, this.color);
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String? value;
  const _DetailRow(this.icon, this.label, this.value);
}
