import 'dart:convert';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../../../core/services/fee_condition_settings.dart';
import '../../../../features/staff/data/models/staff_model.dart';
import '../../../../features/contributors/data/models/contributor_model.dart';
import '../../data/models/student_model.dart';


import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/students_bloc.dart';


import '../widgets/document_upload_dialog.dart';
import '../widgets/student_id_card_builder_dialog.dart';
import '../widgets/student_form_dialog.dart';
import '../../../../core/network/api_client.dart';
import 'package:madarsa_app/core/constants/app_constants.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../data/models/student_academic_history_model.dart';
import '../../data/repositories/student_repository.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../shared/widgets/movable_resizable_dialog.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../../../../core/widgets/app_date_range_picker.dart';
import '../../../../shared/widgets/dribbble_date_picker.dart';

String _formatDiscountDisplay(double disc, double orig, String tag) {
  final pct = orig > 0 ? (disc / orig) * 100.0 : 0.0;
  String pctStr = pct.toStringAsFixed(pct < 1 ? 2 : 1);
  if (pct == pct.truncateToDouble()) {
    pctStr = '${pct.toInt()}%';
  } else if (pctStr.contains('.')) {
    pctStr = '${pctStr.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}%';
  } else {
    pctStr = '$pctStr%';
  }

  if (tag.isNotEmpty && tag.contains('%')) {
    return tag;
  }
  if (tag.isNotEmpty) {
    return pct > 0 ? '$tag ($pctStr)' : tag;
  }
  return pct > 0 ? '- ₹${disc.toStringAsFixed(0)} ($pctStr)' : '- ₹${disc.toStringAsFixed(0)}';
}

class StudentProfileScreen extends StatefulWidget {
  final String studentId;
  final Student? initialStudent;
  final VoidCallback onBack;

  const StudentProfileScreen({
    super.key,
    required this.studentId,
    this.initialStudent,
    required this.onBack,
  });

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  FeeConditionConfig? _conditionConfig;
  Map<String, String> _staffNameMap = {};
  Map<String, String> _contributorNameMap = {};
  Student? _student;

  static Map<String, String>? _cachedStaffNameMap;
  static Map<String, String>? _cachedContributorNameMap;
  static DateTime? _cacheTimestamp;

  @override
  void initState() {
    super.initState();
    _student = widget.initialStudent;
    if (_cachedStaffNameMap != null && _cachedContributorNameMap != null) {
      _staffNameMap = _cachedStaffNameMap!;
      _contributorNameMap = _cachedContributorNameMap!;
    }
    context.read<StudentsBloc>().add(LoadStudentDetails(widget.studentId));
    _loadLookupData();
  }

  Future<void> _loadLookupData() async {
    if (_cachedStaffNameMap != null &&
        _cachedContributorNameMap != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!).inMinutes < 5) {
      return;
    }

    final api = ApiClient();
    try {
      final staffRes = await api.get('/staff');
      final rawStaff = staffRes.data;
      List<dynamic> staffList = [];
      if (rawStaff is Map) {
        staffList = (rawStaff['data'] as List?) ?? [];
      } else if (rawStaff is List) {
        staffList = rawStaff;
      }
      final sMap = <String, String>{};
      for (final item in staffList) {
        final s = StaffMember.fromJson(item as Map<String, dynamic>);
        sMap[s.id] = s.fullName;
      }

      final contribRes = await api.get('/contributors');
      final rawContrib = contribRes.data;
      List<dynamic> contribList = [];
      if (rawContrib is List) contribList = rawContrib;
      final cMap = <String, String>{};
      for (final item in contribList) {
        final c = Contributor.fromJson(item as Map<String, dynamic>);
        cMap[c.id] = c.name;
      }

      _cachedStaffNameMap = sMap;
      _cachedContributorNameMap = cMap;
      _cacheTimestamp = DateTime.now();

      if (mounted) {
        setState(() {
          _staffNameMap = sMap;
          _contributorNameMap = cMap;
        });
      }
    } catch (e) {
      debugPrint('Lookup load error: $e');
    }
  }

  String _getResolvedName(Student student) {
    if (student.contributorName != null &&
        student.contributorName!.isNotEmpty &&
        !student.contributorName!.contains('-')) {
      return student.contributorName!;
    }
    final id = student.contributorId;
    if (id != null && id.isNotEmpty) {
      if (_staffNameMap.containsKey(id)) return _staffNameMap[id]!;
      if (_contributorNameMap.containsKey(id)) return _contributorNameMap[id]!;
      if (student.contributorName != null && student.contributorName!.isNotEmpty) {
        return student.contributorName!;
      }
      return id;
    }
    return '-';
  }

  void _ensureConditionConfigLoaded(String? conditionName) {
    final name = (conditionName != null && conditionName.isNotEmpty) ? conditionName : 'Regular';
    if (_conditionConfig == null || _conditionConfig!.conditionName.toLowerCase() != name.toLowerCase()) {
      FeeConditionSettings.getConfigFor(name).then((cfg) {
        if (mounted) {
          setState(() {
            _conditionConfig = cfg;
          });
        }
      });
    }
  }

  void _showUploadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<StudentsBloc>(),
        child: DocumentUploadDialog(studentId: widget.studentId),
      ),
    );
  }

  Future<void> _openDocument(String filePath) async {
    try {
      String base = ApiConstants.baseUrl.replaceAll("/api", "");
      if (!base.endsWith('/')) {
        base = '$base/';
      }
      String path = filePath;
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      final urlString = '$base$path';
      final url = Uri.parse(urlString);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $urlString';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInfoRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: TextStyle(
                fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTheme.getFontStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
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
  }


  String _buildHeaderSubDetails(Student student, BuildContext context) {
    final parts = <String>[];
    parts.add('${context.tr('gr_no')}: ${student.grNo ?? student.registrationNumber}');
    if (student.rollNumber != null && student.rollNumber!.isNotEmpty) {
      final deptName = student.departmentName;
      final label = (deptName != null && deptName.isNotEmpty) ? '$deptName Roll' : 'Roll No';
      parts.add('$label: ${student.rollNumber}');
    }
    if (student.subDepartments != null) {
      for (final sub in student.subDepartments!) {
        if (sub.rollNumber != null && sub.rollNumber!.isNotEmpty) {
          final subName = sub.subDepartmentName ?? 'Sub-Dept';
          parts.add('$subName Roll: ${sub.rollNumber}');
        }
      }
    }
    return parts.join('  |  ');
  }

  Widget _buildMobileLayout(Student student, bool isDark) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final hasPhoto = student.photoPath != null && student.photoPath!.isNotEmpty;
    final themeBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top profile block
          Container(
            padding: EdgeInsets.symmetric(vertical: 12 * scale),
            child: Row(
              children: [
                // Rounded rectangle avatar
                Container(
                  width: 60 * scale,
                  height: 60 * scale,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(14 * scale),
                    image: hasPhoto
                        ? DecorationImage(
                            image: ResizeImage(
                              NetworkImage(
                                '${ApiConstants.baseUrl.replaceAll("/api", "")}${student.photoPath}',
                              ),
                              width: (60 * scale * 2.5).toInt(),
                              height: (60 * scale * 2.5).toInt(),
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: !hasPhoto
                      ? Icon(
                          Icons.person_rounded,
                          color: isDark ? Colors.white30 : Colors.black26,
                          size: 30 * scale,
                        )
                      : null,
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.fullName,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.getFontStyle(
                          fontSize: 18 * scale,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      SizedBox(height: 3 * scale),
                      Text(
                        _buildHeaderSubDetails(student, context),
                        style: AppTheme.getFontStyle(
                          fontSize: 11 * scale,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12 * scale),

          // 2. Stats cards row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(10 * scale),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10 * scale),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFC8E6C9),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(5 * scale),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(isDark ? 20 : 150),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          color: const Color(0xFF2E7D32),
                          size: 18 * scale,
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.tr('attendance'),
                              style: AppTheme.getFontStyle(
                                fontSize: 10 * scale,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2 * scale),
                            Text(
                              '${student.totalAttendance} ${context.tr('days')}',
                              style: AppTheme.getFontStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(10 * scale),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10 * scale),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFFFCDD2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(5 * scale),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(isDark ? 20 : 150),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.money_off_rounded,
                          color: const Color(0xFFC62828),
                          size: 18 * scale,
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.tr('pending_fees'),
                              style: AppTheme.getFontStyle(
                                fontSize: 10 * scale,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2 * scale),
                            Text(
                              '₹${student.pendingFees.toStringAsFixed(0)}',
                              style: AppTheme.getFontStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

            // 3. Detail Fields list (with Dividers and chevrons)
            Container(
              decoration: BoxDecoration(
                color: themeBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  _buildMobileDetailRow(context.tr('father_name'), student.fatherName ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('surname'), student.surname ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('grand_father_name'), student.grandFatherName ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('gender'), student.gender ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('date_of_birth'), student.dateOfBirth ?? '-', isDark),
                  if (student.departmentName != null && student.departmentName!.isNotEmpty) ...[
                    _buildMobileDetailDivider(isDark),
                    _buildMobileDetailRow(context.tr('department'), student.departmentName!, isDark),
                  ],
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(
                    student.subDepartments != null && student.subDepartments!.isNotEmpty
                        ? '${context.tr('class')} (${student.departmentName ?? 'Main'})'
                        : context.tr('class'),
                    student.className ?? '-',
                    isDark,
                  ),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(
                    student.subDepartments != null && student.subDepartments!.isNotEmpty
                        ? 'Roll No (${student.departmentName ?? 'Main'})'
                        : 'Roll No',
                    student.rollNumber ?? '-',
                    isDark,
                  ),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(
                    student.subDepartments != null && student.subDepartments!.isNotEmpty
                        ? '${context.tr('division')} (${student.departmentName ?? 'Main'})'
                        : context.tr('division'),
                    student.division ?? '-',
                    isDark,
                  ),
                  if (student.subDepartments != null && student.subDepartments!.isNotEmpty) ...[
                    for (final sub in student.subDepartments!) ...[
                      _buildMobileDetailDivider(isDark),
                      _buildMobileDetailRow(
                        context.tr('sub_department'),
                        sub.subDepartmentName ?? '-',
                        isDark,
                      ),
                      _buildMobileDetailDivider(isDark),
                      _buildMobileDetailRow(
                        '${sub.subDepartmentName ?? 'Sub-Dept'} Class',
                        sub.className ?? '-',
                        isDark,
                      ),
                      _buildMobileDetailDivider(isDark),
                      _buildMobileDetailRow(
                        '${sub.subDepartmentName ?? 'Sub-Dept'} Roll No',
                        sub.rollNumber ?? '-',
                        isDark,
                      ),
                      _buildMobileDetailDivider(isDark),
                      _buildMobileDetailRow(
                        '${sub.subDepartmentName ?? 'Sub-Dept'} Division',
                        sub.division ?? '-',
                        isDark,
                      ),
                    ],
                  ],
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('category'), student.category ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(
                    context.tr('status'),
                    student.studentStatus ??
                        (student.isActive
                            ? context.tr('active')
                            : context.tr('inactive')),
                    isDark,
                  ),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('admission_type'), student.admissionType ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('admission_date'), student.admissionDate ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('admission_date_hijri'), student.admissionDateH ?? '-', isDark),
                  ..._buildDynamicFeeRowsMobile(student, isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('admission_time_age'), _getResolvedAge(student.admissionTimeAge, student.dateOfBirth, student.admissionDate), isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('now_age'), _getResolvedAge(student.nowAge, student.dateOfBirth), isDark),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 3b. Address Details Container
            Text(
              context.tr('address_details'),
              style: AppTheme.getFontStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: themeBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  _buildMobileDetailRow(context.tr('address'), student.address ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('village'), student.village ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('taluka'), student.taluka ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('district'), student.district ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('state'), student.state ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('pincode'), student.pinCode ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('mobile'), student.mobileNo ?? '-', isDark),
                  _buildMobileDetailDivider(isDark),
                  _buildMobileDetailRow(context.tr('aadhaar_no'), _formatAadhaarDisplay(student.aadhaarNo), isDark),
                ],
              ),
            ),
          const SizedBox(height: 24),

          // 4. Uploaded Documents
          _buildMobileDocumentsSection(student, isDark),
          const SizedBox(height: 24),

          // 5. Assigned Books
          _buildMobileBooksSection(student, isDark),
          const SizedBox(height: 24),

          // 6. Academic History & Promotion Timeline
          _StudentAcademicHistoryTimeline(
            student: student,
            isDark: isDark,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _openEditStudent(Student student) async {
    if (!_ensureFeatureAccess('students_edit', 'Edit Student Details')) return;
    await showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<StudentsBloc>(),
        child: StudentFormDialog(student: student),
      ),
    );
    if (mounted) {
      context.read<StudentsBloc>().add(LoadStudentDetails(widget.studentId));
    }
  }

  List<Widget> _buildDynamicFeeRowsMobile(Student student, bool isDark) {
    _ensureConditionConfigLoaded(student.conditionType);
    final rows = <Widget>[];

    rows.add(_buildMobileDetailRow(context.tr('condition'), student.conditionType ?? '-', isDark));

    List<Map<String, dynamic>> parsedStructure = [];
    if (student.feeStructure != null && student.feeStructure!.trim().isNotEmpty && student.feeStructure != 'null') {
      try {
        final decoded = jsonDecode(student.feeStructure!);
        if (decoded is List) {
          parsedStructure = decoded.where((e) => e is Map).cast<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }

    if (parsedStructure.isNotEmpty) {
      for (final item in parsedStructure) {
        final name = item['fee_type_name']?.toString() ?? item['fee_type']?.toString() ?? 'Fee';
        final orig = (item['original_amount'] as num?)?.toDouble() ?? (item['amount'] as num?)?.toDouble() ?? 0.0;
        final disc = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
        final net = (item['net_amount'] as num?)?.toDouble() ?? (item['amount'] as num?)?.toDouble() ?? 0.0;
        final tag = item['discount_tag']?.toString() ?? '';

        if (disc > 0) {
          final displayTag = _formatDiscountDisplay(disc, orig, tag);
          rows.add(_buildMobileDetailDivider(isDark));
          rows.add(_buildMobileDetailRow(
            name,
            '₹${orig.toStringAsFixed(0)}',
            isDark,
          ));
          rows.add(_buildMobileDetailDivider(isDark));
          rows.add(_buildMobileDetailRow(
            '$name Discount',
            displayTag,
            isDark,
          ));
          rows.add(_buildMobileDetailDivider(isDark));
          rows.add(_buildMobileDetailRow(
            'Net $name',
            '₹${net.toStringAsFixed(0)}',
            isDark,
          ));
        } else {
          rows.add(_buildMobileDetailDivider(isDark));
          rows.add(_buildMobileDetailRow(
            name,
            '₹${orig.toStringAsFixed(0)}',
            isDark,
          ));
        }
      }

      final totalDisc = parsedStructure.fold<double>(
        0.0,
        (s, h) => s + ((h['discount_amount'] as num?)?.toDouble() ?? 0.0),
      );
      final totalOrig = parsedStructure.fold<double>(
        0.0,
        (s, h) => s + ((h['original_amount'] as num?)?.toDouble() ?? (h['amount'] as num?)?.toDouble() ?? 0.0),
      );

      if (totalDisc > 0) {
        final totalDisplayTag = _formatDiscountDisplay(totalDisc, totalOrig, '');
        rows.add(_buildMobileDetailDivider(isDark));
        rows.add(_buildMobileDetailRow('Total Discount', totalDisplayTag, isDark));
      }

      if ((student.contributorName != null && student.contributorName!.isNotEmpty) ||
          (student.contributorId != null && student.contributorId!.isNotEmpty)) {
        rows.add(_buildMobileDetailDivider(isDark));
        rows.add(_buildMobileDetailRow('Staff / Contributor', _getResolvedName(student), isDark));
      }

      final monthlyItem = parsedStructure.firstWhere(
        (h) => (h['fee_type_id']?.toString().toLowerCase().contains('month') ?? false) ||
               (h['fee_type_name']?.toString().toLowerCase().contains('month') ?? false) ||
               (h['fee_type_name']?.toString().toLowerCase().contains('tuition') ?? false),
        orElse: () => <String, dynamic>{},
      );
      if (monthlyItem.isNotEmpty) {
        final mNet = (monthlyItem['net_amount'] as num?)?.toDouble() ?? (monthlyItem['amount'] as num?)?.toDouble() ?? student.monthlyFees ?? 0.0;
        rows.add(_buildMobileDetailDivider(isDark));
        rows.add(_buildMobileDetailRow('Net Monthly Fee', '₹${mNet.toStringAsFixed(0)}', isDark));
      } else if (student.monthlyFees != null && student.monthlyFees! > 0) {
        rows.add(_buildMobileDetailDivider(isDark));
        rows.add(_buildMobileDetailRow('Net Monthly Fee', '₹${student.monthlyFees!.toStringAsFixed(0)}', isDark));
      }
    } else {
      final config = _conditionConfig;
      if (config != null && config.fields.isNotEmpty) {
        double baseFee = (student.monthlyFees ?? 0.0) + (student.contributorAmount ?? 0.0);

        for (final f in config.fields) {
          if (f.isStaff || f.isContributor) {
            final displayVal = _getResolvedName(student);
            rows.add(_buildMobileDetailDivider(isDark));
            rows.add(_buildMobileDetailRow(f.label, displayVal, isDark));
          } else if (f.fieldType == 'number') {
            if (f.mathAction == 'add') {
              rows.add(_buildMobileDetailDivider(isDark));
              rows.add(_buildMobileDetailRow(
                f.label,
                '₹${baseFee > 0 ? baseFee.toStringAsFixed(2) : (student.monthlyFees?.toStringAsFixed(2) ?? "0.00")}',
                isDark,
              ));
            } else if (f.isDeduction) {
              final subAmt = student.contributorAmount ?? 0.0;
              if (subAmt > 0) {
                final displayTag = _formatDiscountDisplay(subAmt, baseFee, '');
                rows.add(_buildMobileDetailDivider(isDark));
                rows.add(_buildMobileDetailRow(
                  f.label,
                  displayTag,
                  isDark,
                ));
              }
            } else if (student.contributorAmount != null &&
                student.contributorAmount! > 0 &&
                (f.fieldSource == 'contributor' ||
                    f.fieldSource == 'staff' ||
                    f.id.contains('contributor') ||
                    f.id.contains('staff') ||
                    f.label.toLowerCase().contains('contributor') ||
                    f.label.toLowerCase().contains('staff'))) {
              rows.add(_buildMobileDetailDivider(isDark));
              rows.add(_buildMobileDetailRow(
                f.label,
                '₹${student.contributorAmount!.toStringAsFixed(2)}',
                isDark,
              ));
            }
          }
        }
      } else {
        if ((student.contributorName != null && student.contributorName!.isNotEmpty) ||
            (student.contributorId != null && student.contributorId!.isNotEmpty)) {
          rows.add(_buildMobileDetailDivider(isDark));
          rows.add(_buildMobileDetailRow(
            'Contributor / Staff Name',
            _getResolvedName(student),
            isDark,
          ));
        }
        if (student.contributorAmount != null && student.contributorAmount! > 0) {
          final subAmt = student.contributorAmount!;
          final baseAmt = (student.monthlyFees ?? 0.0) + subAmt;
          final displayTag = _formatDiscountDisplay(subAmt, baseAmt, '');
          rows.add(_buildMobileDetailDivider(isDark));
          rows.add(_buildMobileDetailRow(
            'Discount / Concession',
            displayTag,
            isDark,
          ));
        }
      }

      if (student.admissionFee != null && student.admissionFee! > 0) {
        rows.add(_buildMobileDetailDivider(isDark));
        rows.add(_buildMobileDetailRow('Admission Fee', '₹${student.admissionFee!.toStringAsFixed(2)}', isDark));
      }
      if (student.bookFee != null && student.bookFee! > 0) {
        rows.add(_buildMobileDetailDivider(isDark));
        rows.add(_buildMobileDetailRow('Book Fee', '₹${student.bookFee!.toStringAsFixed(2)}', isDark));
      }

      rows.add(_buildMobileDetailDivider(isDark));
      rows.add(_buildMobileDetailRow(
        'Net Monthly Fee',
        student.monthlyFees != null ? '₹${student.monthlyFees!.toStringAsFixed(2)}' : '-',
        isDark,
      ));
    }

    return rows;
  }

  List<Widget> _buildDynamicFeeRowsDesktop(Student student) {
    _ensureConditionConfigLoaded(student.conditionType);
    final rows = <Widget>[];

    rows.add(_buildInfoRow(context.tr('condition'), student.conditionType ?? ''));

    List<Map<String, dynamic>> parsedStructure = [];
    if (student.feeStructure != null && student.feeStructure!.trim().isNotEmpty && student.feeStructure != 'null') {
      try {
        final decoded = jsonDecode(student.feeStructure!);
        if (decoded is List) {
          parsedStructure = decoded.where((e) => e is Map).cast<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }

    if (parsedStructure.isNotEmpty) {
      for (final item in parsedStructure) {
        final name = item['fee_type_name']?.toString() ?? item['fee_type']?.toString() ?? 'Fee';
        final orig = (item['original_amount'] as num?)?.toDouble() ?? (item['amount'] as num?)?.toDouble() ?? 0.0;
        final disc = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
        final net = (item['net_amount'] as num?)?.toDouble() ?? (item['amount'] as num?)?.toDouble() ?? 0.0;
        final tag = item['discount_tag']?.toString() ?? '';

        if (disc > 0) {
          final displayTag = _formatDiscountDisplay(disc, orig, tag);
          rows.add(_buildInfoRow(name, '₹${orig.toStringAsFixed(0)}'));
          rows.add(_buildInfoRow('$name Discount', displayTag));
          rows.add(_buildInfoRow('Net $name', '₹${net.toStringAsFixed(0)}', isHighlight: true));
        } else {
          rows.add(_buildInfoRow(name, '₹${orig.toStringAsFixed(0)}'));
        }
      }

      final totalDisc = parsedStructure.fold<double>(
        0.0,
        (s, h) => s + ((h['discount_amount'] as num?)?.toDouble() ?? 0.0),
      );
      final totalOrig = parsedStructure.fold<double>(
        0.0,
        (s, h) => s + ((h['original_amount'] as num?)?.toDouble() ?? (h['amount'] as num?)?.toDouble() ?? 0.0),
      );

      if (totalDisc > 0) {
        final totalDisplayTag = _formatDiscountDisplay(totalDisc, totalOrig, '');
        rows.add(_buildInfoRow('Total Discount', totalDisplayTag));
      }

      if ((student.contributorName != null && student.contributorName!.isNotEmpty) ||
          (student.contributorId != null && student.contributorId!.isNotEmpty)) {
        rows.add(_buildInfoRow(
          'Staff / Contributor',
          _getResolvedName(student),
        ));
      }

      final monthlyItem = parsedStructure.firstWhere(
        (h) => (h['fee_type_id']?.toString().toLowerCase().contains('month') ?? false) ||
               (h['fee_type_name']?.toString().toLowerCase().contains('month') ?? false) ||
               (h['fee_type_name']?.toString().toLowerCase().contains('tuition') ?? false),
        orElse: () => <String, dynamic>{},
      );
      if (monthlyItem.isNotEmpty) {
        final mNet = (monthlyItem['net_amount'] as num?)?.toDouble() ?? (monthlyItem['amount'] as num?)?.toDouble() ?? student.monthlyFees ?? 0.0;
        rows.add(_buildInfoRow('Net Monthly Fee', '₹${mNet.toStringAsFixed(0)}', isHighlight: true));
      } else if (student.monthlyFees != null && student.monthlyFees! > 0) {
        rows.add(_buildInfoRow('Net Monthly Fee', '₹${student.monthlyFees!.toStringAsFixed(0)}', isHighlight: true));
      }
    } else {
      final config = _conditionConfig;
      if (config != null && config.fields.isNotEmpty) {
        double baseFee = (student.monthlyFees ?? 0.0) + (student.contributorAmount ?? 0.0);

        for (final f in config.fields) {
          if (f.isStaff || f.isContributor) {
            final displayVal = _getResolvedName(student);
            rows.add(_buildInfoRow(f.label, displayVal));
          } else if (f.fieldType == 'number') {
            if (f.mathAction == 'add') {
              rows.add(_buildInfoRow(
                f.label,
                '₹${baseFee > 0 ? baseFee.toStringAsFixed(2) : (student.monthlyFees?.toStringAsFixed(2) ?? "0.00")}',
              ));
            } else if (f.isDeduction) {
              final subAmt = student.contributorAmount ?? 0.0;
              if (subAmt > 0) {
                final displayTag = _formatDiscountDisplay(subAmt, baseFee, '');
                rows.add(_buildInfoRow(
                  f.label,
                  displayTag,
                ));
              }
            } else if (student.contributorAmount != null &&
                student.contributorAmount! > 0 &&
                (f.fieldSource == 'contributor' ||
                    f.fieldSource == 'staff' ||
                    f.id.contains('contributor') ||
                    f.id.contains('staff') ||
                    f.label.toLowerCase().contains('contributor') ||
                    f.label.toLowerCase().contains('staff'))) {
              rows.add(_buildInfoRow(
                f.label,
                '₹${student.contributorAmount!.toStringAsFixed(2)}',
              ));
            }
          }
        }
      } else {
        if ((student.contributorName != null && student.contributorName!.isNotEmpty) ||
            (student.contributorId != null && student.contributorId!.isNotEmpty)) {
          rows.add(_buildInfoRow(
            'Contributor / Staff Name',
            _getResolvedName(student),
          ));
        }
        if (student.contributorAmount != null && student.contributorAmount! > 0) {
          final subAmt = student.contributorAmount!;
          final baseAmt = (student.monthlyFees ?? 0.0) + subAmt;
          final displayTag = _formatDiscountDisplay(subAmt, baseAmt, '');
          rows.add(_buildInfoRow(
            'Discount / Concession',
            displayTag,
          ));
        }
      }

      if (student.admissionFee != null && student.admissionFee! > 0) {
        rows.add(_buildInfoRow('Admission Fee', '₹${student.admissionFee!.toStringAsFixed(2)}'));
      }
      if (student.bookFee != null && student.bookFee! > 0) {
        rows.add(_buildInfoRow('Book Fee', '₹${student.bookFee!.toStringAsFixed(2)}'));
      }

      rows.add(_buildInfoRow(
        'Net Monthly Fee',
        student.monthlyFees != null ? '₹${student.monthlyFees!.toStringAsFixed(2)}' : '',
        isHighlight: true,
      ));
    }

    return rows;
  }

  String _formatAadhaarDisplay(String? raw) {
    if (raw == null || raw.isEmpty || raw == '-') return '-';
    String s = raw.trim();
    if (s.toLowerCase().contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) s = d.toStringAsFixed(0);
    }
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    final digitsOnly = s.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 12) {
      return '${digitsOnly.substring(0, 4)} ${digitsOnly.substring(4, 8)} ${digitsOnly.substring(8)}';
    }
    return digitsOnly.isNotEmpty ? digitsOnly : s;
  }

  String _getResolvedAge(String? storedAge, String? dob, [String? targetDate]) {
    if (storedAge != null && storedAge.isNotEmpty && storedAge != '0Days' && storedAge != '-') {
      return storedAge;
    }
    if (dob != null && dob.isNotEmpty && dob != '-') {
      try {
        DateTime? birth;
        final dmyMatch = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(dob.trim());
        if (dmyMatch != null) {
          birth = DateTime(
            int.parse(dmyMatch.group(3)!),
            int.parse(dmyMatch.group(2)!),
            int.parse(dmyMatch.group(1)!),
          );
        } else {
          birth = DateTime.tryParse(dob.trim());
        }

        if (birth != null) {
          DateTime target = DateTime.now();
          if (targetDate != null && targetDate.isNotEmpty && targetDate != '-') {
            final tMatch = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(targetDate.trim());
            if (tMatch != null) {
              target = DateTime(
                int.parse(tMatch.group(3)!),
                int.parse(tMatch.group(2)!),
                int.parse(tMatch.group(1)!),
              );
            } else {
              target = DateTime.tryParse(targetDate.trim()) ?? DateTime.now();
            }
          }

          int years = target.year - birth.year;
          int months = target.month - birth.month;
          int days = target.day - birth.day;

          if (days < 0) {
            months--;
            final prevMonth = DateTime(target.year, target.month, 0);
            days += prevMonth.day;
          }
          if (months < 0) {
            years--;
            months += 12;
          }

          String res = '';
          if (days > 0) res += '${days}Days ';
          if (months > 0) res += '${months}Months ';
          if (years > 0) res += '${years}Years';

          return res.trim().isNotEmpty ? res.trim() : '0Days';
        }
      } catch (_) {}
    }
    return storedAge ?? '-';
  }

  Widget _buildMobileDetailRow(String label, String value, bool isDark) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: AppTheme.getFontStyle(
                fontSize: 11 * scale,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
            ),
          ),
          SizedBox(width: 6 * scale),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.getFontStyle(
                fontSize: 11 * scale,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDetailDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: isDark ? Colors.white10 : Colors.grey.shade100,
    );
  }

  Widget _buildMobileDocumentsSection(Student student, bool isDark) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final docs = student.documents ?? [];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('uploaded_documents'),
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.getFontStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
              SizedBox(width: 8 * scale),
              ElevatedButton.icon(
                onPressed: () => _showUploadDialog(context),
                icon: Icon(Icons.cloud_upload_rounded, size: 13 * scale, color: Colors.white),
                label: Text(
                  context.tr('upload'),
                  style: AppTheme.getFontStyle(
                    fontSize: 10 * scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D6B4E),
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 5 * scale),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6 * scale),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),
          if (docs.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12 * scale),
                child: Text(
                  context.tr('no_documents_uploaded'),
                  style: AppTheme.getFontStyle(fontSize: 11 * scale, color: Colors.grey),
                ),
              ),
            )
          else
            Column(
              children: docs.map((doc) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _openDocument(doc.filePath),
                  leading: Icon(
                    Icons.description_rounded,
                    color: Colors.blue,
                    size: 18 * scale,
                  ),
                  title: Text(
                    doc.documentName,
                    style: AppTheme.getFontStyle(fontSize: 12 * scale, fontWeight: FontWeight.w600),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16 * scale),
                    onPressed: () {
                      _deleteDocumentDialog(student, doc);
                    },
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _deleteDocumentDialog(Student student, dynamic doc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('delete_document')),
        content: Text(context.tr('delete_document_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<StudentsBloc>().add(DeleteStudentDocument(student.id, doc.id));
              Navigator.pop(context);
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBooksSection(Student student, bool isDark) {
    return _AssignedBooksGallery(
      studentClassName: student.className,
      studentCategory: student.category,
      isDark: isDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (context.isMobile) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          elevation: 0,
          leadingWidth: 80,
          leading: TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF0D6B4E), size: 24),
            label: Text(
              context.tr('back'),
              style: AppTheme.getFontStyle(
                color: const Color(0xFF0D6B4E),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          centerTitle: true,
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              context.tr('student_profile'),
              style: AppTheme.getFontStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          actions: [
            BlocBuilder<StudentsBloc, StudentsState>(
              builder: (context, state) {
                final student = (state is StudentDetailsLoaded) ? state.student : _student;
                if (student != null) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: Color(0xFF0D6B4E)),
                        tooltip: 'Edit Student',
                        onPressed: () => _openEditStudent(student),
                      ),
                      IconButton(
                        icon: const Icon(Icons.badge_rounded, color: Color(0xFF0D6B4E)),
                        tooltip: 'Print ID Card',
                        onPressed: () {
                          if (_ensureFeatureAccess('students_id_card_print', 'ID Card Printing')) {
                            StudentIdCardBuilderDialog.show(context, student);
                          }
                        },
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
        ),
        body: BlocBuilder<StudentsBloc, StudentsState>(
          builder: (context, state) {
            final student = (state is StudentDetailsLoaded) ? state.student : _student;
            if (student != null) {
              return _buildMobileLayout(student, isDark);
            }
            if (state is StudentsLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is StudentsError) {
              return Center(child: Text('Error: ${state.message}'));
            }
            return const SizedBox();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF12121E) : const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('student_profile'),
                style: AppTheme.getFontStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              BlocBuilder<StudentsBloc, StudentsState>(
                builder: (context, state) {
                  final student = (state is StudentDetailsLoaded) ? state.student : _student;
                  if (student != null) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _openEditStudent(student),
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: Text(
                            'Edit Student',
                            style: AppTheme.getFontStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0D6B4E),
                            side: const BorderSide(color: Color(0xFF0D6B4E)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_ensureFeatureAccess('students_id_card_print', 'ID Card Printing')) {
                              StudentIdCardBuilderDialog.show(context, student);
                            }
                          },
                          icon: const Icon(Icons.badge_rounded, color: Colors.white),
                          label: Text(
                            'Print ID Card',
                            style: AppTheme.getFontStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D6B4E),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),

        Expanded(
          child: BlocBuilder<StudentsBloc, StudentsState>(
              builder: (context, state) {
                final student = (state is StudentDetailsLoaded) ? state.student : _student;
                if (student != null) {
                  final leftColumn = Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E32)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withAlpha(20)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: ClipOval(
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.blue.withAlpha(20),
                                  child: student.photoPath != null && student.photoPath!.isNotEmpty
                                      ? Image.network(
                                          '${ApiConstants.baseUrl.replaceAll('/api', '')}${student.photoPath}',
                                          width: 80,
                                          height: 80,
                                          cacheWidth: 160,
                                          cacheHeight: 160,
                                          filterQuality: FilterQuality.medium,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Center(
                                            child: Text(
                                              student.fullName.isNotEmpty
                                                  ? student.fullName[0].toUpperCase()
                                                  : '?',
                                              style: AppTheme.getFontStyle(
                                                fontSize: 32,
                                                color: Colors.blue,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            student.fullName.isNotEmpty
                                                ? student.fullName[0].toUpperCase()
                                                : '?',
                                            style: AppTheme.getFontStyle(
                                              fontSize: 32,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                student.fullName,
                                style: AppTheme.getFontStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Center(
                               child: Text(
                                 _buildHeaderSubDetails(student, context),
                                 style: TextStyle(
                                   color: Colors.grey.shade500,
                                   fontSize: 12,
                                 ),
                                 textAlign: TextAlign.center,
                               ),
                             ),
                             const Divider(height: 24),
                             _buildInfoRow(
                               context.tr('father_name'),
                               student.fatherName ?? '',
                             ),
                             _buildInfoRow(
                               context.tr('surname'),
                               student.surname ?? '',
                             ),
                             _buildInfoRow(
                               context.tr('grand_father_name'),
                               student.grandFatherName ?? '',
                             ),
                             _buildInfoRow(
                               context.tr('gender'),
                               student.gender ?? '',
                             ),
                             _buildInfoRow(
                               context.tr('date_of_birth'),
                               student.dateOfBirth ?? '',
                             ),
                             if (student.departmentName != null && student.departmentName!.isNotEmpty)
                               _buildInfoRow(
                                 context.tr('department'),
                                 student.departmentName!,
                               ),
                             _buildInfoRow(
                               student.subDepartments != null && student.subDepartments!.isNotEmpty
                                   ? '${context.tr('class')} (${student.departmentName ?? 'Main'})'
                                   : context.tr('class'),
                               student.className ?? '-',
                             ),
                             _buildInfoRow(
                               student.subDepartments != null && student.subDepartments!.isNotEmpty
                                   ? 'Roll No (${student.departmentName ?? 'Main'})'
                                   : 'Roll No',
                               student.rollNumber ?? '-',
                             ),
                             _buildInfoRow(
                               student.subDepartments != null && student.subDepartments!.isNotEmpty
                                   ? '${context.tr('division')} (${student.departmentName ?? 'Main'})'
                                   : context.tr('division'),
                               student.division ?? '-',
                             ),
                             if (student.subDepartments != null && student.subDepartments!.isNotEmpty)
                               for (final sub in student.subDepartments!) ...[
                                 _buildInfoRow(
                                   context.tr('sub_department'),
                                   sub.subDepartmentName ?? '-',
                                 ),
                                 _buildInfoRow(
                                   '${sub.subDepartmentName ?? 'Sub-Dept'} Class',
                                   sub.className ?? '-',
                                 ),
                                 _buildInfoRow(
                                   '${sub.subDepartmentName ?? 'Sub-Dept'} Roll No',
                                   sub.rollNumber ?? '-',
                                 ),
                                 _buildInfoRow(
                                   '${sub.subDepartmentName ?? 'Sub-Dept'} Division',
                                   sub.division ?? '-',
                                 ),
                               ],
                            _buildInfoRow(
                              context.tr('category'),
                              student.category ?? '-',
                            ),
                            _buildInfoRow(
                              context.tr('status'),
                              student.studentStatus ??
                                  (student.isActive
                                      ? context.tr('active')
                                      : context.tr('inactive')),
                            ),
                            _buildInfoRow(
                              context.tr('admission_type'),
                              student.admissionType ?? '',
                            ),
                            _buildInfoRow(
                              context.tr('admission_date'),
                              student.admissionDate ?? '',
                            ),
                            _buildInfoRow(
                              context.tr('admission_date_hijri'),
                              student.admissionDateH ?? '',
                            ),
                            ..._buildDynamicFeeRowsDesktop(student),
                            _buildInfoRow(
                              context.tr('admission_time_age'),
                              _getResolvedAge(student.admissionTimeAge, student.dateOfBirth, student.admissionDate),
                            ),
                            _buildInfoRow(
                              context.tr('now_age'),
                              _getResolvedAge(student.nowAge, student.dateOfBirth),
                              isHighlight: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E32)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withAlpha(20)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('address_details'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                             const SizedBox(height: 8),
                             _buildInfoRow(
                               context.tr('address'),
                               student.address ?? '',
                             ),
                             _buildInfoRow(
                              context.tr('village'),
                              student.village ?? '',
                            ),
                            _buildInfoRow(
                              context.tr('taluka'),
                              student.taluka ?? '',
                            ),
                            _buildInfoRow(
                              context.tr('district'),
                              student.district ?? '',
                            ),
                            _buildInfoRow(context.tr('state'), student.state ?? ''),
                            _buildInfoRow(
                              context.tr('pincode'),
                              student.pinCode ?? '',
                            ),
                            _buildInfoRow(
                              context.tr('mobile'),
                              student.mobileNo ?? '',
                            ),
                            _buildInfoRow(
                              context.tr('aadhaar_no'),
                              _formatAadhaarDisplay(student.aadhaarNo),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  final rightColumn = Column(
                    children: [
                      context.isMobile
                          ? Column(
                              children: [
                                _buildStatCard(
                                  isDark: isDark,
                                  title: context.tr('total_attendance'),
                                  value: '${student.totalAttendance} days',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: Colors.green,
                                ),
                                const SizedBox(height: 12),
                                _buildStatCard(
                                  isDark: isDark,
                                  title: context.tr('pending_fees'),
                                  value: '₹${student.pendingFees}',
                                  icon: Icons.money_off_csred_rounded,
                                  color: Colors.red,
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    isDark: isDark,
                                    title: context.tr('total_attendance'),
                                    value: '${student.totalAttendance} days',
                                    icon: Icons.check_circle_outline_rounded,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildStatCard(
                                    isDark: isDark,
                                    title: context.tr('pending_fees'),
                                    value: '₹${student.pendingFees}',
                                    icon: Icons.money_off_csred_rounded,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E32)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withAlpha(20)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  context.tr('uploaded_documents'),
                                  style: AppTheme.getFontStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _showUploadDialog(context),
                                  icon: const Icon(
                                    Icons.upload_file_rounded,
                                  ),
                                  label: Text(context.tr('upload')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (student.documents == null ||
                                student.documents!.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(context.tr('no_documents_uploaded')),
                                ),
                              )
                            else
                              SizedBox(
                                height: 300,
                                child: ListView.builder(
                                  itemCount: student.documents!.length,
                                  itemBuilder: (context, index) {
                                    final doc = student.documents![index];
                                    return ListTile(
                                      onTap: () => _openDocument(doc.filePath),
                                      leading: const Icon(
                                        Icons.file_present_rounded,
                                        color: Colors.blue,
                                      ),
                                      title: Text(doc.documentName),
                                      subtitle: Text(
                                        'Uploaded on ${doc.uploadedAt}',
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: Text(
                                                context.tr('delete_document'),
                                              ),
                                              content: Text(
                                                context.tr('delete_document_confirm'),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                      ),
                                                  child: Text(
                                                    context.tr('cancel'),
                                                  ),
                                                ),
                                                FilledButton(
                                                  style:
                                                      FilledButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.red,
                                                      ),
                                                  onPressed: () {
                                                    context
                                                        .read<
                                                          StudentsBloc
                                                        >()
                                                        .add(
                                                          DeleteStudentDocument(
                                                            student.id,
                                                            doc.id,
                                                          ),
                                                        );
                                                    Navigator.pop(
                                                      context,
                                                    );
                                                  },
                                                  child: Text(
                                                    context.tr('delete'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _AssignedBooksGallery(
                        studentClassName: student.className,
                        studentCategory: student.category,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 24),
                      _StudentAcademicHistoryTimeline(
                        student: student,
                        isDark: isDark,
                      ),
                    ],
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: MediaQuery.of(context).size.width < 1200
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftColumn,
                              const SizedBox(height: 24),
                              rightColumn,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 1, child: leftColumn),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: rightColumn),
                            ],
                          ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    ),
  );
}
}

class _AssignedBooksGallery extends StatefulWidget {
  final String? studentClassName;
  final String? studentCategory;
  final bool isDark;

  const _AssignedBooksGallery({
    this.studentClassName,
    this.studentCategory,
    required this.isDark,
  });

  @override
  State<_AssignedBooksGallery> createState() => _AssignedBooksGalleryState();
}

class _AssignedBooksGalleryState extends State<_AssignedBooksGallery> {
  bool _isLoading = true;
  List<dynamic> _books = [];

  @override
  void initState() {
    super.initState();
    _fetchBooks();
  }

  Future<void> _fetchBooks() async {
    if (widget.studentClassName == null || widget.studentClassName!.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    
    // Fallback or exact category
    final targetCategory = widget.studentCategory;

    try {
      final response = await ApiClient().get('/academic/hierarchy');
      final hierarchy = response.data as List;
      
      final booksList = <dynamic>[];
      final seenBookIds = <dynamic>{};
      for (var cls in hierarchy) {
        if (cls['name'] == widget.studentClassName) {
          final courses = cls['courses'] as List? ?? [];
          for (var crs in courses) {
            final crsBooks = crs['books'] as List? ?? [];
            for (var b in crsBooks) {
              final bookId = b['id'] ?? b['name'];
              if (seenBookIds.contains(bookId)) continue;

              final bookCategory = b['category']?.toString() ?? '';
              if (bookCategory.isEmpty) {
                booksList.add(b);
                seenBookIds.add(bookId);
              } else if (targetCategory != null &&
                  targetCategory.isNotEmpty &&
                  bookCategory.trim().toLowerCase() == targetCategory.trim().toLowerCase()) {
                booksList.add(b);
                seenBookIds.add(bookId);
              }
            }
          }
        }
      }

      setState(() {
        _books = booksList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Failed to fetch assigned books: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_books.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(16 * scale),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1E1E32) : Colors.white,
          borderRadius: BorderRadius.circular(12 * scale),
          border: Border.all(
            color: widget.isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.menu_book_rounded, size: 32 * scale, color: Colors.grey.withAlpha(100)),
            SizedBox(height: 8 * scale),
            Text(
              context.tr('no_books_assigned'),
              style: AppTheme.getFontStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4 * scale),
            Text(
              widget.studentCategory == null 
               ? 'This student does not have any assigned category.'
               : 'No books found for class "${widget.studentClassName}" and category "${widget.studentCategory}".',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11 * scale),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E1E32) : Colors.white,
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(
          color: widget.isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('assigned_books'),
            style: AppTheme.getFontStyle(fontSize: 15 * scale, fontWeight: FontWeight.w700),
          ),
          if (widget.studentCategory != null) ...[
            SizedBox(height: 2 * scale),
            Text(
              '${context.tr('category')}: ${widget.studentCategory}',
              style: TextStyle(color: Colors.blue.shade400, fontWeight: FontWeight.w500, fontSize: 11 * scale),
            ),
          ],
          SizedBox(height: 12 * scale),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _books.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: widget.isDark ? Colors.white10 : Colors.grey.shade200,
            ),
            itemBuilder: (context, index) {
              final b = _books[index];
              final author = b['author']?.toString() ?? '';
              return ListTile(
                contentPadding: EdgeInsets.symmetric(vertical: 2 * scale, horizontal: 4 * scale),
                leading: Container(
                  padding: EdgeInsets.all(6 * scale),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(6 * scale),
                  ),
                  child: Icon(
                    Icons.book_rounded,
                    color: Colors.blue,
                    size: 18 * scale,
                  ),
                ),
                title: Text(
                  b['name'] ?? 'Unknown Book',
                  style: AppTheme.getFontStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13 * scale,
                  ),
                ),
                subtitle: author.isNotEmpty
                    ? Text(
                        author,
                        style: AppTheme.getFontStyle(
                          fontSize: 11 * scale,
                          color: Colors.grey.shade500,
                        ),
                      )
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StudentAcademicHistoryTimeline extends StatefulWidget {
  final Student student;
  final bool isDark;

  const _StudentAcademicHistoryTimeline({
    required this.student,
    required this.isDark,
  });

  @override
  State<_StudentAcademicHistoryTimeline> createState() => _StudentAcademicHistoryTimelineState();
}

class _StudentAcademicHistoryTimelineState extends State<_StudentAcademicHistoryTimeline> {
  bool _isLoading = true;
  bool _isArchiving = false;
  List<StudentAcademicHistory> _historyList = [];
  Map<String, dynamic>? _currentSummary;
  Map<String, dynamic>? _sessionConfig;
  String _selectedYear = 'Current';
  final Set<String> _expandedBooksIds = {};
  bool _isCurrentSessionBooksExpanded = false;

  // Month & Day Explorer State
  String _selectedMonth = 'All';
  DateTime? _selectedSpecificDate;
  DateTimeRange? _selectedDateRange;
  bool _isCurrentAttendanceLogExpanded = true;
  bool _isCurrentFeesLogExpanded = true;
  final Set<String> _expandedPastAttendanceIds = {};
  final Set<String> _expandedPastFeesIds = {};
  final Map<String, String> _pastYearSelectedMonth = {};
  final Map<String, DateTime?> _pastYearSelectedDate = {};
  final Map<String, DateTimeRange?> _pastYearSelectedDateRange = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant _StudentAcademicHistoryTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.student.id != widget.student.id ||
        oldWidget.student.monthlyFees != widget.student.monthlyFees ||
        oldWidget.student.className != widget.student.className) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final list = await StudentRepository(ApiClient()).getStudentAcademicHistory(widget.student.id);
      final sessionConfig = await DatabaseHelper().getCurrentAcademicSessionConfig();
      final summary = await DatabaseHelper().calculateStudentAcademicSummary(
        widget.student.id,
        classId: widget.student.className,
        fallbackMonthlyFees: widget.student.monthlyFees,
        fallbackAdmissionFee: widget.student.admissionFee,
        fallbackBookFee: widget.student.bookFee,
        fallbackFeeStructure: widget.student.feeStructure,
        sessionConfig: sessionConfig,
      );

      if (mounted) {
        setState(() {
          _historyList = list;
          _currentSummary = summary;
          _sessionConfig = sessionConfig;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPromoteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _PromoteStudentDialog(
        student: widget.student,
        isDark: widget.isDark,
        onSuccess: () {
          _loadHistory();
          context.read<StudentsBloc>().add(LoadStudentDetails(widget.student.id));
        },
      ),
    );
  }

  Future<void> _archiveCurrentSnapshot() async {
    final curYear = _sessionConfig?['year_name']?.toString() ?? '${DateTime.now().year}-${DateTime.now().year + 1}';
    final curHijri = _sessionConfig?['year_name_hijri']?.toString();
    final curClass = widget.student.className ?? 'Class 1';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Current Session Snapshot'),
        content: Text(
          'Do you want to save a historical snapshot of this student\'s current academic performance for session $curYear?\n\n'
          '• Current Class: $curClass\n'
          '• Department: ${widget.student.departmentName ?? "General"}\n'
          '• All attendance, exam marks, books, fees, and expenses will be recorded and synced to online Cloud storage.\n'
          '• Current student class and department will NOT change.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive Snapshot Now'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isArchiving = true);
    try {
      await StudentRepository(ApiClient()).recordAcademicPromotion(
        student: widget.student,
        academicYear: curYear,
        academicYearHijri: curHijri,
        targetClass: curClass,
        targetDepartmentId: widget.student.departmentId,
        targetDepartmentName: widget.student.departmentName,
        targetDivision: widget.student.division,
        targetRollNumber: widget.student.rollNumber,
        status: 'Active',
        remarks: 'Manual snapshot archived for $curYear',
      );

      await _loadHistory();
      if (mounted) {
        setState(() => _isArchiving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Academic snapshot archived and synced to cloud successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isArchiving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive snapshot: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteHistory(String historyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Academic Record'),
        content: const Text('Are you sure you want to delete this historical academic snapshot? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await StudentRepository(ApiClient()).deleteAcademicHistory(historyId);
        _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Academic record removed'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete record: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final isDark = widget.isDark;

    final currentYearName = _sessionConfig?['year_name']?.toString() ?? '${DateTime.now().year}-${DateTime.now().year + 1}';
    final pastYears = _historyList.map((h) => h.academicYear).toSet().toList();
    pastYears.sort((a, b) => b.compareTo(a));

    final isCurrentSelected = _selectedYear == 'Current' || _selectedYear == currentYearName;
    final isAllSelected = _selectedYear == 'All';
    final matchingHistoryList = isAllSelected
        ? _historyList
        : _historyList.where((h) => h.academicYear == _selectedYear).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      padding: EdgeInsets.all(14 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(7 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D6B4E).withAlpha(25),
                  borderRadius: BorderRadius.circular(8 * scale),
                ),
                child: Icon(
                  Icons.history_edu_rounded,
                  color: const Color(0xFF0D6B4E),
                  size: 20 * scale,
                ),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Academic History & Promotion Timeline',
                      style: AppTheme.getFontStyle(
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      'Current and Past Sessions • Attendance, Fees Breakdown, Student Expense & Exam Marks',
                      style: AppTheme.getFontStyle(
                        fontSize: 11 * scale,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isArchiving ? null : _archiveCurrentSnapshot,
                icon: Icon(Icons.archive_outlined, size: 14 * scale),
                label: Text(
                  _isArchiving ? 'Archiving...' : 'Snapshot Now',
                  style: AppTheme.getFontStyle(fontSize: 11 * scale, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D6B4E),
                  side: const BorderSide(color: Color(0xFF0D6B4E)),
                  padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 6 * scale),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 6 * scale),
              FilledButton.icon(
                onPressed: _showPromoteDialog,
                icon: Icon(Icons.upgrade_rounded, size: 15 * scale),
                label: Text(
                  'Promote / Archive',
                  style: AppTheme.getFontStyle(fontSize: 11 * scale, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D6B4E),
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),

          SizedBox(height: 12 * scale),

          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else ...[
            // ── Interactive Year Selector Bar ──
            _buildYearSelectorBar(currentYearName, pastYears, scale),

            SizedBox(height: 12 * scale),

            // ── Dynamic Display Based On Year Selection ──
            if (isCurrentSelected) ...[
              _buildCurrentSessionCard(scale),
            ] else if (isAllSelected) ...[
              _buildCurrentSessionCard(scale),
              SizedBox(height: 16 * scale),
              Row(
                children: [
                  Icon(Icons.history_rounded, size: 16 * scale, color: Colors.grey.shade600),
                  SizedBox(width: 6 * scale),
                  Text(
                    'Archived Past Sessions (${_historyList.length})',
                    style: AppTheme.getFontStyle(
                      fontSize: 12.5 * scale,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : const Color(0xFF333333),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10 * scale),
              if (_historyList.isEmpty)
                _buildEmptyState(scale)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: matchingHistoryList.length,
                  separatorBuilder: (ctx, idx) => SizedBox(height: 12 * scale),
                  itemBuilder: (ctx, index) => _buildHistoryCard(matchingHistoryList[index], scale),
                ),
            ] else ...[
              // Specific past year selected
              if (matchingHistoryList.isEmpty)
                _buildEmptyState(scale, message: 'No archived records found for Session "$_selectedYear".')
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: matchingHistoryList.length,
                  separatorBuilder: (ctx, idx) => SizedBox(height: 12 * scale),
                  itemBuilder: (ctx, index) => _buildHistoryCard(matchingHistoryList[index], scale),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildYearSelectorBar(String currentYearName, List<String> pastYears, double scale) {
    final isDark = widget.isDark;
    final allOptions = ['Current', ...pastYears, 'All'];
    final selectedVal = allOptions.contains(_selectedYear) ? _selectedYear : 'Current';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
              SizedBox(width: 6 * scale),
              Text(
                'Select Academic Year / Session:',
                style: AppTheme.getFontStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : const Color(0xFF333333),
                ),
              ),
              const Spacer(),
              Container(
                height: 32 * scale,
                padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF252538) : Colors.white,
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedVal,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 18 * scale),
                    isDense: true,
                    dropdownColor: isDark ? const Color(0xFF252538) : Colors.white,
                    style: TextStyle(
                      fontSize: 11.5 * scale,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'Current',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, size: 8, color: Colors.green),
                            const SizedBox(width: 6),
                            Text('Current Session ($currentYearName)'),
                          ],
                        ),
                      ),
                      ...pastYears.map((yr) {
                        return DropdownMenuItem(
                          value: yr,
                          child: Text('Session $yr'),
                        );
                      }),
                      const DropdownMenuItem(
                        value: 'All',
                        child: Text('All Sessions (Full Timeline)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedYear = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildYearTabChip('Current', '🟢 Current ($currentYearName)', scale),
                ...pastYears.map((yr) => _buildYearTabChip(yr, yr, scale)),
                _buildYearTabChip('All', 'View All Sessions', scale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearTabChip(String value, String label, double scale) {
    final isSelected = _selectedYear == value;
    final isDark = widget.isDark;

    return Padding(
      padding: EdgeInsets.only(right: 6 * scale),
      child: InkWell(
        onTap: () => setState(() => _selectedYear = value),
        borderRadius: BorderRadius.circular(6 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D6B4E) : (isDark ? Colors.white10 : Colors.white),
            borderRadius: BorderRadius.circular(6 * scale),
            border: Border.all(
              color: isSelected ? const Color(0xFF0D6B4E) : (isDark ? Colors.white12 : Colors.grey.shade300),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11 * scale,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(double scale, {String? message}) {
    final isDark = widget.isDark;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18 * scale, color: Colors.grey.shade500),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              message ??
                  'No previous sessions archived yet. When this student advances upon year end or promotion, each year\'s complete snapshot will be preserved here.',
              style: TextStyle(fontSize: 11.5 * scale, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicMetricsGrid({
    required double scale,
    required bool isDark,
    required int presentDays,
    required int totalDays,
    required double attPct,
    required double obtMarks,
    required double totalMarks,
    required double examPct,
    required String grade,
    required double feeTotal,
    required double feePaid,
    required double feePending,
    int feePendingMonths = 0,
    int feePaidMonths = 0,
    required double perStudentExp,
  }) {
    final fTotal = feeTotal > 0 ? feeTotal : (feePaid + feePending);
    final fPaid = feePaid;
    final fPending = feePending > 0 ? feePending : (fTotal - fPaid).clamp(0.0, double.infinity);
    final feeProgress = fTotal > 0 ? (fPaid / fTotal).clamp(0.0, 1.0) : 1.0;

    final absentDays = (totalDays - presentDays).clamp(0, 9999);
    final attProgress = totalDays > 0 ? (presentDays / totalDays).clamp(0.0, 1.0) : 0.0;
    final marksProgress = totalMarks > 0 ? (obtMarks / totalMarks).clamp(0.0, 1.0) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final isMedium = constraints.maxWidth >= 440 && constraints.maxWidth < 720;
        final cardWidth = isWide
            ? (constraints.maxWidth - 30 * scale) / 4
            : (isMedium ? (constraints.maxWidth - 10 * scale) / 2 : constraints.maxWidth);

        return Wrap(
          spacing: 10 * scale,
          runSpacing: 10 * scale,
          children: [
            // ── 1. Attendance Tracker Card ──
            SizedBox(
              width: cardWidth,
              child: Container(
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B2F23) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8 * scale),
                  border: Border.all(color: Colors.green.withAlpha(isDark ? 50 : 80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.how_to_reg_rounded, size: 15 * scale, color: Colors.green.shade700),
                        SizedBox(width: 5 * scale),
                        Expanded(
                          child: Text(
                            'Attendance Record',
                            style: AppTheme.getFontStyle(fontSize: 11 * scale, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                          decoration: BoxDecoration(
                            color: Colors.green.shade700,
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            '${attPct.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6 * scale),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3 * scale),
                      child: LinearProgressIndicator(
                        value: attProgress,
                        minHeight: 4 * scale,
                        backgroundColor: Colors.green.withAlpha(40),
                        valueColor: AlwaysStoppedAnimation(
                          attPct >= 75 ? Colors.green.shade700 : (attPct >= 50 ? Colors.amber.shade800 : Colors.red.shade700),
                        ),
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Present: ${presentDays}d', style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                        Text('Absent: ${absentDays}d', style: TextStyle(fontSize: 10 * scale, color: Colors.grey.shade600)),
                        Text('Total: ${totalDays}d', style: TextStyle(fontSize: 10 * scale, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── 2. Fees Details Card (Total, Paid, Pending) ──
            SizedBox(
              width: cardWidth,
              child: Container(
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF332617) : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8 * scale),
                  border: Border.all(color: Colors.amber.withAlpha(isDark ? 60 : 100)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 15 * scale, color: Colors.amber.shade900),
                        SizedBox(width: 5 * scale),
                        Expanded(
                          child: Text(
                            'Fees Details',
                            style: AppTheme.getFontStyle(fontSize: 11 * scale, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                          decoration: BoxDecoration(
                            color: fPending <= 0 && fTotal > 0
                                ? Colors.green.shade700
                                : (fPending > 0 ? (fPaid > 0 ? Colors.orange.shade800 : Colors.red.shade700) : Colors.grey.shade600),
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            fPending <= 0 && fTotal > 0 ? 'Fully Paid' : (fPending > 0 ? 'Due: ₹${fPending.toStringAsFixed(0)}' : 'Free / Exempt'),
                            style: TextStyle(fontSize: 9.5 * scale, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6 * scale),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3 * scale),
                      child: LinearProgressIndicator(
                        value: feeProgress,
                        minHeight: 4 * scale,
                        backgroundColor: Colors.amber.withAlpha(40),
                        valueColor: AlwaysStoppedAnimation(
                          fPending <= 0 ? Colors.green.shade700 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total: ₹${fTotal.toStringAsFixed(0)}', style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
                        Text('Paid: ₹${fPaid.toStringAsFixed(0)}', style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                        Text(
                          'Pending: ₹${fPending.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                            color: fPending > 0 ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (feePendingMonths > 0 || feePaidMonths > 0) ...[
                      SizedBox(height: 5 * scale),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                        decoration: BoxDecoration(
                          color: feePendingMonths > 0
                              ? Colors.red.withAlpha(isDark ? 35 : 18)
                              : Colors.green.withAlpha(isDark ? 35 : 18),
                          borderRadius: BorderRadius.circular(4 * scale),
                          border: Border.all(
                            color: feePendingMonths > 0 ? Colors.red.withAlpha(50) : Colors.green.withAlpha(50),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              feePendingMonths > 0
                                  ? '⏳ $feePendingMonths Months Due'
                                  : '✅ All Months Cleared',
                              style: TextStyle(
                                fontSize: 9.5 * scale,
                                fontWeight: FontWeight.bold,
                                color: feePendingMonths > 0 ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                            ),
                            if (feePaidMonths > 0)
                              Text(
                                'Paid: $feePaidMonths Mo',
                                style: TextStyle(
                                  fontSize: 9.5 * scale,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── 3. Institution Student Expense Card ──
            SizedBox(
              width: cardWidth,
              child: Container(
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF162D2D) : const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(8 * scale),
                  border: Border.all(color: Colors.teal.withAlpha(isDark ? 50 : 80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payments_outlined, size: 15 * scale, color: Colors.teal.shade800),
                        SizedBox(width: 5 * scale),
                        Expanded(
                          child: Text(
                            'Student Expense',
                            style: AppTheme.getFontStyle(fontSize: 11 * scale, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            'Annual Cost',
                            style: TextStyle(fontSize: 9.5 * scale, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6 * scale),
                    Text(
                      '₹${perStudentExp.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 13.5 * scale, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      'Madarsa expense on student',
                      style: TextStyle(fontSize: 9.5 * scale, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // ── 4. Exam Results Card ──
            SizedBox(
              width: cardWidth,
              child: Container(
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B263B) : const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8 * scale),
                  border: Border.all(color: Colors.blue.withAlpha(isDark ? 50 : 80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events_outlined, size: 15 * scale, color: Colors.blue.shade700),
                        SizedBox(width: 5 * scale),
                        Expanded(
                          child: Text(
                            'Exam Results',
                            style: AppTheme.getFontStyle(fontSize: 11 * scale, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (grade != '-')
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade700,
                              borderRadius: BorderRadius.circular(4 * scale),
                            ),
                            child: Text(
                              grade,
                              style: TextStyle(fontSize: 9.5 * scale, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 6 * scale),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3 * scale),
                      child: LinearProgressIndicator(
                        value: marksProgress,
                        minHeight: 4 * scale,
                        backgroundColor: Colors.blue.withAlpha(40),
                        valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          obtMarks > 0 ? '${obtMarks.toStringAsFixed(0)} / ${totalMarks.toStringAsFixed(0)}' : 'No Marks',
                          style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                        Text(
                          obtMarks > 0 ? '${examPct.toStringAsFixed(1)}%' : '',
                          style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.w600, color: Colors.blue.shade800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMonthAndDateFilterBar({
    required List<Map<String, dynamic>> attendanceRecords,
    required List<Map<String, dynamic>> feePayments,
    required String selectedMonth,
    required DateTime? selectedDate,
    required DateTimeRange? selectedDateRange,
    required Function(String) onMonthChanged,
    required Function(DateTime?) onDateChanged,
    required Function(DateTimeRange?) onDateRangeChanged,
    required double scale,
    required bool isDark,
    String? currentYearLabel,
  }) {
    // Collect all available months (yyyy-MM)
    final Set<String> monthsSet = {};
    for (final r in attendanceRecords) {
      final d = r['date']?.toString().trim();
      if (d != null && d.length >= 7) {
        monthsSet.add(d.substring(0, 7));
      }
    }
    for (final p in feePayments) {
      final d = p['payment_date']?.toString().trim();
      if (d != null && d.length >= 7) {
        monthsSet.add(d.substring(0, 7));
      }
    }

    // Always include current calendar year's 12 months so month chips are always available
    final now = DateTime.now();
    for (int m = 1; m <= 12; m++) {
      monthsSet.add('${now.year}-${m.toString().padLeft(2, '0')}');
    }

    final sortedMonths = monthsSet.toList()..sort((a, b) => b.compareTo(a));

    return Container(
      margin: EdgeInsets.only(bottom: 10 * scale),
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt_outlined, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                  SizedBox(width: 6 * scale),
                  Text(
                    'Explore by Date Range, Month, or Day:',
                    style: AppTheme.getFontStyle(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),

              // Active Filter Badges or Picker Action Buttons
              if (selectedDateRange != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D6B4E).withAlpha(25),
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(color: const Color(0xFF0D6B4E), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.date_range_rounded, size: 14 * scale, color: const Color(0xFF0D6B4E)),
                      SizedBox(width: 6 * scale),
                      Text(
                        'Range: ${DateFormat('dd MMM').format(selectedDateRange.start)} - ${DateFormat('dd MMM yyyy').format(selectedDateRange.end)} (${selectedDateRange.duration.inDays + 1} d)',
                        style: TextStyle(
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0D6B4E),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      InkWell(
                        onTap: () => onDateRangeChanged(null),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              else if (selectedDate != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D6B4E).withAlpha(25),
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(color: const Color(0xFF0D6B4E), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.today_rounded, size: 14 * scale, color: const Color(0xFF0D6B4E)),
                      SizedBox(width: 6 * scale),
                      Text(
                        'Day: ${DateFormat('dd MMM yyyy').format(selectedDate)}',
                        style: TextStyle(
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0D6B4E),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      InkWell(
                        onTap: () => onDateChanged(null),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 6 * scale,
                  runSpacing: 6 * scale,
                  children: [
                    // 1. Date Range Picker Button
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await AppDateRangePicker.show(
                          context,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2035),
                          initialDateRange: DateTimeRange(
                            start: DateTime.now().subtract(const Duration(days: 7)),
                            end: DateTime.now(),
                          ),
                          title: 'Fee History Date Filter',
                        );
                        if (picked != null) {
                          onDateChanged(null);
                          onMonthChanged('All');
                          onDateRangeChanged(picked);
                        }
                      },
                      icon: Icon(Icons.date_range_rounded, size: 14 * scale),
                      label: Text('Date Range (2 Dates)',
                          style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0D6B4E),
                        side: const BorderSide(color: Color(0xFF0D6B4E), width: 1.2),
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                      ),
                    ),

                    // 2. Single Day Picker Button
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await DribbbleDatePickerDialog.show(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2035),
                          title: 'Select Day',
                        );
                        if (picked != null) {
                          onDateRangeChanged(null);
                          onMonthChanged('All');
                          onDateChanged(picked);
                        }
                      },
                      icon: Icon(Icons.today_rounded, size: 14 * scale),
                      label: Text('Single Day',
                          style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0D6B4E),
                        side: const BorderSide(color: Color(0xFF0D6B4E), width: 1.2),
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                      ),
                    ),

                    // 3. Pick Month Dialog Button
                    OutlinedButton.icon(
                      onPressed: () => _showPickMonthDialog(
                        context,
                        onMonthChanged,
                        onDateChanged,
                        onDateRangeChanged,
                        isDark,
                        scale,
                      ),
                      icon: Icon(Icons.calendar_month_rounded, size: 14 * scale),
                      label: Text('Pick Month',
                          style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0D6B4E),
                        side: const BorderSide(color: Color(0xFF0D6B4E), width: 1.2),
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: 8 * scale),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMonthChip(
                  label: 'All Months',
                  isSelected: selectedMonth == 'All' && selectedDate == null && selectedDateRange == null,
                  onTap: () {
                    onDateChanged(null);
                    onDateRangeChanged(null);
                    onMonthChanged('All');
                  },
                  scale: scale,
                  isDark: isDark,
                ),
                ...sortedMonths.map((mStr) {
                  String monthLabel = mStr;
                  try {
                    final parts = mStr.split('-');
                    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
                    monthLabel = DateFormat('MMM yyyy').format(dt);
                  } catch (_) {}

                  final count = attendanceRecords
                      .where((r) => r['date']?.toString().startsWith(mStr) == true)
                      .length;
                  final label = count > 0 ? '$monthLabel ($count d)' : monthLabel;

                  return _buildMonthChip(
                    label: label,
                    isSelected: selectedMonth == mStr && selectedDate == null && selectedDateRange == null,
                    onTap: () {
                      onDateChanged(null);
                      onDateRangeChanged(null);
                      onMonthChanged(mStr);
                    },
                    scale: scale,
                    isDark: isDark,
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPickMonthDialog(
    BuildContext context,
    Function(String) onMonthChanged,
    Function(DateTime?) onDateChanged,
    Function(DateTimeRange?) onDateRangeChanged,
    bool isDark,
    double scale,
  ) {
    int selectedYear = DateTime.now().year;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final monthNames = [
            'January', 'February', 'March', 'April',
            'May', 'June', 'July', 'August',
            'September', 'October', 'November', 'December'
          ];
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 20 * scale, color: const Color(0xFF0D6B4E)),
                    SizedBox(width: 8 * scale),
                    Text(
                      'Select Month',
                      style: AppTheme.getFontStyle(
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                DropdownButton<int>(
                  value: selectedYear,
                  dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                  items: List.generate(15, (i) => DateTime.now().year - 7 + i).map((y) {
                    return DropdownMenuItem<int>(
                      value: y,
                      child: Text('$y', style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedYear = val);
                    }
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 320 * scale,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: 12,
                itemBuilder: (context, idx) {
                  final mNum = idx + 1;
                  final mStr = '$selectedYear-${mNum.toString().padLeft(2, '0')}';
                  return InkWell(
                    onTap: () {
                      Navigator.pop(dialogCtx);
                      onDateChanged(null);
                      onDateRangeChanged(null);
                      onMonthChanged(mStr);
                    },
                    borderRadius: BorderRadius.circular(8 * scale),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(12) : const Color(0xFF0D6B4E).withAlpha(12),
                        borderRadius: BorderRadius.circular(8 * scale),
                        border: Border.all(
                          color: const Color(0xFF0D6B4E).withAlpha(isDark ? 60 : 30),
                        ),
                      ),
                      child: Text(
                        monthNames[idx].substring(0, 3),
                        style: TextStyle(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0D6B4E),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMonthChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required double scale,
    required bool isDark,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: 6 * scale),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 4 * scale),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D6B4E) : (isDark ? Colors.white10 : Colors.white),
            borderRadius: BorderRadius.circular(6 * scale),
            border: Border.all(
              color: isSelected ? const Color(0xFF0D6B4E) : (isDark ? Colors.white12 : Colors.grey.shade300),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5 * scale,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDailyAttendanceLog({
    required List<Map<String, dynamic>> records,
    required double scale,
    required bool isDark,
    required Color accentColor,
  }) {
    if (records.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(10 * scale),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6 * scale),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 15 * scale, color: Colors.grey.shade500),
            SizedBox(width: 6 * scale),
            Expanded(
              child: Text(
                'No daily attendance records marked for this selected period.',
                style: TextStyle(fontSize: 10.5 * scale, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(8 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: records.map((r) {
          final dateStr = r['date']?.toString() ?? '-';
          String formattedDate = dateStr;
          try {
            final dt = DateTime.parse(dateStr);
            formattedDate = DateFormat('EEE, dd MMM yyyy').format(dt);
          } catch (_) {}

          final st = (r['status']?.toString() ?? 'Present').toLowerCase();
          Color statusBg;
          Color statusFg;
          IconData statusIcon;
          String statusLabel = 'Present';

          if (st == 'present' || st == 'p' || st == 'hazir') {
            statusBg = Colors.green.withAlpha(isDark ? 50 : 35);
            statusFg = Colors.green.shade800;
            statusIcon = Icons.check_circle_rounded;
            statusLabel = 'Present';
          } else if (st == 'absent' || st == 'a' || st == 'ghair hazir') {
            statusBg = Colors.red.withAlpha(isDark ? 50 : 35);
            statusFg = Colors.red.shade700;
            statusIcon = Icons.cancel_rounded;
            statusLabel = 'Absent';
          } else {
            statusBg = Colors.orange.withAlpha(isDark ? 50 : 35);
            statusFg = Colors.orange.shade800;
            statusIcon = Icons.pending_actions_rounded;
            statusLabel = 'Leave';
          }

          final inTime = r['check_in_time']?.toString() ?? '';
          final outTime = r['check_out_time']?.toString() ?? '';
          final remarks = r['remarks']?.toString() ?? '';

          return Container(
            margin: EdgeInsets.only(bottom: 6 * scale),
            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(6) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(6 * scale),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                // Date
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(4 * scale),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 11 * scale, color: accentColor),
                      SizedBox(width: 4 * scale),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 10.5 * scale,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * scale),
                // Status Badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(4 * scale),
                    border: Border.all(color: statusFg.withAlpha(70)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12 * scale, color: statusFg),
                      SizedBox(width: 3 * scale),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10 * scale,
                          fontWeight: FontWeight.bold,
                          color: statusFg,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // In/Out Time
                if (inTime.isNotEmpty || outTime.isNotEmpty) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4 * scale),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded, size: 11 * scale, color: Colors.grey.shade600),
                        SizedBox(width: 3 * scale),
                        Text(
                          inTime.isNotEmpty && outTime.isNotEmpty && inTime != outTime
                              ? 'In: $inTime | Out: $outTime'
                              : 'Time: ${inTime.isNotEmpty ? inTime : outTime}',
                          style: TextStyle(fontSize: 10 * scale, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 6 * scale),
                ],
                // Remarks if any
                if (remarks.isNotEmpty) ...[
                  Tooltip(
                    message: remarks,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(20),
                        borderRadius: BorderRadius.circular(4 * scale),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 10 * scale, color: Colors.blue.shade700),
                          SizedBox(width: 3 * scale),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 120 * scale),
                            child: Text(
                              remarks,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 9.5 * scale, color: Colors.blue.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFeeTransactionsLog({
    required List<Map<String, dynamic>> payments,
    required double scale,
    required bool isDark,
    double? pendingBalance,
  }) {
    if (payments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(12 * scale),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8 * scale),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16 * scale, color: Colors.grey.shade500),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                'No fee payment transactions recorded for this session.',
                style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );
    }

    final totalPaidAmount = payments.fold<double>(
      0.0,
      (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    );

    final studentDisplayName = [
      widget.student.fullName,
      if (widget.student.fatherName != null && widget.student.fatherName!.trim().isNotEmpty) widget.student.fatherName!.trim(),
      if (widget.student.surname != null && widget.student.surname!.trim().isNotEmpty) widget.student.surname!.trim(),
    ].join(' ').trim();

    return Container(
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header: Total collected & count
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
            margin: EdgeInsets.only(bottom: 8 * scale),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(isDark ? 25 : 15),
              borderRadius: BorderRadius.circular(6 * scale),
              border: Border.all(color: Colors.green.withAlpha(50)),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, size: 14 * scale, color: Colors.green.shade700),
                SizedBox(width: 6 * scale),
                Expanded(
                  child: Text(
                    'Fee Payment History & Receipts',
                    style: AppTheme.getFontStyle(
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF166534),
                    ),
                  ),
                ),
                Text(
                  'Total: ₹${totalPaidAmount.toStringAsFixed(0)} (${payments.length} Payments)',
                  style: TextStyle(
                    fontSize: 10.5 * scale,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ),
          ...payments.map((p) {
            final pDate = p['payment_date']?.toString() ?? '-';
            String formattedDate = pDate;
            try {
              final dt = DateTime.parse(pDate);
              formattedDate = DateFormat('dd MMM yyyy').format(dt);
            } catch (_) {}

            final feeType = p['fee_type']?.toString() ?? 'Tuition Fee';
            final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
            final receipt = p['receipt_no']?.toString();
            final remarks = p['remarks']?.toString();

            return Container(
              margin: EdgeInsets.only(bottom: 6 * scale),
              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(6) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6 * scale),
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded, size: 14 * scale, color: Colors.green.shade700),
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              feeType,
                              style: AppTheme.getFontStyle(
                                fontSize: 11.5 * scale,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (receipt != null && receipt.isNotEmpty) ...[
                              SizedBox(width: 6 * scale),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(15),
                                  borderRadius: BorderRadius.circular(3 * scale),
                                ),
                                child: Text(
                                  'Rec #$receipt',
                                  style: TextStyle(
                                    fontSize: 9.5 * scale,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 2 * scale),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 10 * scale, color: Colors.grey.shade500),
                            SizedBox(width: 4 * scale),
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 10.5 * scale,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.grey.shade700,
                              ),
                            ),
                            if (remarks != null && remarks.trim().isNotEmpty) ...[
                              Text(' • ', style: TextStyle(color: Colors.grey.shade400)),
                              Expanded(
                                child: Text(
                                  remarks,
                                  style: TextStyle(fontSize: 10 * scale, color: Colors.grey.shade500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 6 * scale),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3.5 * scale),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(25),
                      borderRadius: BorderRadius.circular(4 * scale),
                      border: Border.all(color: Colors.green.withAlpha(70)),
                    ),
                    child: Text(
                      '₹${amt.toStringAsFixed(0)} (Paid)',
                      style: TextStyle(
                        fontSize: 10.5 * scale,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                  SizedBox(width: 6 * scale),
                  IconButton(
                    icon: Icon(Icons.picture_as_pdf_rounded, size: 16 * scale, color: Colors.red.shade700),
                    tooltip: 'Print / Download Receipt',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      ReceiptPdfGenerator.printFeeReceipt(
                        studentName: studentDisplayName.isNotEmpty ? studentDisplayName : widget.student.fullName,
                        grNo: widget.student.grNo ?? '-',
                        className: widget.student.className ?? '-',
                        amountPaid: amt,
                        feeType: feeType,
                        remainingBalance: pendingBalance ?? 0.0,
                        date: pDate,
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMonthlyFeeStatusTracker({
    required List<dynamic> feeBreakdown,
    required double scale,
    required bool isDark,
    String? sessionYear,
  }) {
    if (feeBreakdown.isEmpty) return const SizedBox.shrink();

    // Filter to monthly heads
    final monthlyHeads = feeBreakdown.where((item) {
      final map = item is Map<String, dynamic> ? item : (item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{});
      final billing = (map['billing_type']?.toString() ?? 'monthly').toLowerCase();
      return billing == 'monthly';
    }).toList();

    if (monthlyHeads.isEmpty) return const SizedBox.shrink();

    final List<String> defaultMonthNames = [
      'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
      'Oct', 'Nov', 'Dec', 'Jan', 'Feb', 'Mar',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: monthlyHeads.map((item) {
        final map = item is Map<String, dynamic> ? item : (item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{});
        final name = map['fee_type_name']?.toString() ?? 'Monthly Tuition Fee';
        final monthlyRate = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final rawMonthsList = map['months_list'] as List? ?? [];
        List<String> monthNames = [];
        if (rawMonthsList.isNotEmpty) {
          monthNames = rawMonthsList.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        }
        final monthsCount = (map['months_count'] as num?)?.toInt() ?? (monthNames.isNotEmpty ? monthNames.length : 12);
        if (monthNames.isEmpty) {
          monthNames = defaultMonthNames.take(monthsCount).toList();
          while (monthNames.length < monthsCount) {
            monthNames.add('Mo ${monthNames.length + 1}');
          }
        }

        final totalExpected = (map['total_expected'] as num?)?.toDouble() ?? (monthlyRate * monthsCount);
        final totalPaid = (map['total_paid'] as num?)?.toDouble() ?? 0.0;
        final totalPending = (map['total_pending'] as num?)?.toDouble() ?? (totalExpected - totalPaid).clamp(0.0, double.infinity);

        int paidMonths = (map['paid_months'] as num?)?.toInt() ?? (monthlyRate > 0 ? (totalPaid / monthlyRate).floor().clamp(0, monthsCount) : 0);
        int pendingMonths = (map['pending_months'] as num?)?.toInt() ?? (monthsCount - paidMonths).clamp(0, monthsCount);

        double partialPaid = 0.0;
        if (monthlyRate > 0 && totalPaid > (paidMonths * monthlyRate) && paidMonths < monthsCount) {
          partialPaid = totalPaid - (paidMonths * monthlyRate);
        }

        final bool isAllPaid = totalPending <= 0 && totalExpected > 0;
        final double progress = totalExpected > 0 ? (totalPaid / totalExpected).clamp(0.0, 1.0) : 1.0;

        return Container(
          margin: EdgeInsets.only(bottom: 10 * scale),
          padding: EdgeInsets.all(12 * scale),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(8 * scale),
            border: Border.all(
              color: isAllPaid
                  ? Colors.green.withAlpha(isDark ? 80 : 120)
                  : (totalPending > 0 ? Colors.amber.withAlpha(isDark ? 70 : 120) : Colors.grey.shade300),
              width: 1.2,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Fee Name + Rate + Status Badge
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(
                      color: isAllPaid
                          ? Colors.green.withAlpha(25)
                          : (totalPending > 0 ? Colors.amber.withAlpha(30) : Colors.blue.withAlpha(20)),
                      borderRadius: BorderRadius.circular(6 * scale),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      size: 16 * scale,
                      color: isAllPaid
                          ? Colors.green.shade700
                          : (totalPending > 0 ? Colors.amber.shade900 : Colors.blue.shade700),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: AppTheme.getFontStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(width: 6 * scale),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 1.5 * scale),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withAlpha(18),
                                borderRadius: BorderRadius.circular(4 * scale),
                              ),
                              child: Text(
                                '₹${monthlyRate.toStringAsFixed(0)}/mo',
                                style: TextStyle(
                                  fontSize: 10 * scale,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Total: $monthsCount Months • Scheduled session fees',
                          style: TextStyle(fontSize: 10 * scale, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                    decoration: BoxDecoration(
                      color: isAllPaid
                          ? Colors.green.shade50
                          : (totalPending > 0 ? const Color(0xFFFEF2F2) : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(16 * scale),
                      border: Border.all(
                        color: isAllPaid
                            ? Colors.green.shade300
                            : (totalPending > 0 ? Colors.red.shade300 : Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAllPaid
                              ? Icons.check_circle_rounded
                              : (totalPending > 0 ? Icons.hourglass_top_rounded : Icons.info_outline_rounded),
                          size: 12 * scale,
                          color: isAllPaid
                              ? Colors.green.shade700
                              : (totalPending > 0 ? Colors.red.shade700 : Colors.grey.shade700),
                        ),
                        SizedBox(width: 4 * scale),
                        Text(
                          isAllPaid
                              ? 'All $monthsCount Mo Paid'
                              : (pendingMonths > 0 ? '$pendingMonths Months Due (₹${totalPending.toStringAsFixed(0)})' : 'Free / Exempt'),
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                            color: isAllPaid
                                ? Colors.green.shade800
                                : (totalPending > 0 ? Colors.red.shade800 : Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10 * scale),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4 * scale),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6 * scale,
                  backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(
                    isAllPaid ? Colors.green.shade600 : (progress > 0.5 ? Colors.amber.shade700 : Colors.orange.shade700),
                  ),
                ),
              ),

              SizedBox(height: 6 * scale),

              // Summary Counters Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Paid: $paidMonths of $monthsCount Months (₹${totalPaid.toStringAsFixed(0)})',
                    style: TextStyle(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    totalPending > 0
                        ? 'Due: $pendingMonths Months (₹${totalPending.toStringAsFixed(0)})'
                        : 'Balance: ₹0 (No Due)',
                    style: TextStyle(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.bold,
                      color: totalPending > 0 ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 10 * scale),

              // Month-by-Month Status Chips Grid
              Text(
                'Month-by-Month Fee Status:',
                style: AppTheme.getFontStyle(
                  fontSize: 10.5 * scale,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
              SizedBox(height: 6 * scale),

              Wrap(
                spacing: 6 * scale,
                runSpacing: 6 * scale,
                children: List.generate(monthsCount, (idx) {
                  final mLabel = idx < monthNames.length ? monthNames[idx] : 'M${idx + 1}';
                  final bool isPaid = idx < paidMonths;
                  final bool isPartial = !isPaid && idx == paidMonths && partialPaid > 0;

                  Color bg;
                  Color border;
                  Color textColor;
                  IconData icon;
                  String statusText;

                  if (isPaid) {
                    bg = isDark ? const Color(0xFF064E3B).withAlpha(120) : const Color(0xFFDCFCE7);
                    border = isDark ? const Color(0xFF059669) : const Color(0xFF86EFAC);
                    textColor = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF166534);
                    icon = Icons.check_circle_rounded;
                    statusText = 'Paid';
                  } else if (isPartial) {
                    bg = isDark ? const Color(0xFF78350F).withAlpha(120) : const Color(0xFFFEF3C7);
                    border = isDark ? const Color(0xFFD97706) : const Color(0xFFFCD34D);
                    textColor = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
                    icon = Icons.access_time_rounded;
                    statusText = 'Part (₹${partialPaid.toStringAsFixed(0)})';
                  } else {
                    bg = isDark ? const Color(0xFF7F1D1D).withAlpha(100) : const Color(0xFFFEE2E2);
                    border = isDark ? const Color(0xFFDC2626).withAlpha(160) : const Color(0xFFFCA5A5);
                    textColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
                    icon = Icons.hourglass_top_rounded;
                    statusText = 'Due (₹${monthlyRate.toStringAsFixed(0)})';
                  }

                  return Tooltip(
                    message: isPaid
                        ? '$mLabel: Paid (₹${monthlyRate.toStringAsFixed(0)})'
                        : (isPartial
                            ? '$mLabel: Partially paid (Paid ₹${partialPaid.toStringAsFixed(0)} / Due ₹${(monthlyRate - partialPaid).toStringAsFixed(0)})'
                            : '$mLabel: Unpaid / Due (₹${monthlyRate.toStringAsFixed(0)})'),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 4 * scale),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(5 * scale),
                        border: Border.all(color: border, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 11 * scale, color: textColor),
                          SizedBox(width: 4 * scale),
                          Text(
                            '$mLabel: ',
                            style: TextStyle(
                              fontSize: 10 * scale,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 9.5 * scale,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCurrentSessionCard(double scale) {
    final isDark = widget.isDark;
    final yearName = _sessionConfig?['year_name']?.toString() ?? '${DateTime.now().year}-${DateTime.now().year + 1}';
    final hijriYear = _sessionConfig?['year_name_hijri']?.toString();
    final summary = _currentSummary ?? {};

    final presentDays = (summary['present_days'] as num?)?.toInt() ?? 0;
    final totalDays = (summary['total_attendance_days'] as num?)?.toInt() ?? 0;

    final obtMarks = (summary['obtained_marks'] as num?)?.toDouble() ?? 0.0;
    final totalMarks = (summary['total_marks'] as num?)?.toDouble() ?? 0.0;
    final examPct = (summary['exam_percentage'] as num?)?.toDouble() ?? 0.0;
    final grade = summary['result_grade']?.toString() ?? '-';

    final feeTotal = (summary['fee_total'] as num?)?.toDouble() ?? 0.0;
    final feePaid = (summary['fee_paid'] as num?)?.toDouble() ?? 0.0;
    final feePending = (summary['fee_pending'] as num?)?.toDouble() ?? 0.0;
    final feePendingMonths = (summary['fee_pending_months'] as num?)?.toInt() ?? 0;
    final feePaidMonths = (summary['fee_paid_months'] as num?)?.toInt() ?? 0;
    final perStudentExp = (summary['per_student_expense'] as num?)?.toDouble() ?? 15000.0;

    final books = (summary['books_marks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allAttRecords = (summary['attendance_records'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final allFeePayments = (summary['fee_payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final feeBreakdown = (summary['fee_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Filter attendance records based on selectedMonth, selectedSpecificDate, or selectedDateRange
    List<Map<String, dynamic>> filteredAttRecords = allAttRecords;
    if (_selectedDateRange != null) {
      final startStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      final endStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filteredAttRecords = allAttRecords.where((r) {
        final d = r['date']?.toString().trim();
        if (d == null || d.length < 10) return false;
        final dStr = d.substring(0, 10);
        return dStr.compareTo(startStr) >= 0 && dStr.compareTo(endStr) <= 0;
      }).toList();
    } else if (_selectedSpecificDate != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedSpecificDate!);
      filteredAttRecords = allAttRecords.where((r) => r['date']?.toString().startsWith(dateStr) == true).toList();
    } else if (_selectedMonth != 'All') {
      filteredAttRecords = allAttRecords.where((r) => r['date']?.toString().startsWith(_selectedMonth) == true).toList();
    }

    final isFiltered = _selectedMonth != 'All' || _selectedSpecificDate != null || _selectedDateRange != null;
    int displayPresentDays = 0;
    for (final r in filteredAttRecords) {
      final st = (r['status']?.toString() ?? '').toLowerCase();
      if (st == 'present' || st == 'p' || st == 'hazir') displayPresentDays++;
    }
    final displayTotalDays = isFiltered ? filteredAttRecords.length : totalDays;
    if (!isFiltered) displayPresentDays = presentDays;
    final displayAttPct = isFiltered
        ? (displayTotalDays > 0 ? ((displayPresentDays / displayTotalDays) * 100) : 0.0)
        : ((summary['attendance_percentage'] as num?)?.toDouble() ?? (displayTotalDays > 0 ? ((displayPresentDays / displayTotalDays) * 100) : 0.0));

    // Filter fee payments
    List<Map<String, dynamic>> filteredFeePayments = allFeePayments;
    if (_selectedDateRange != null) {
      final startStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      final endStr = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filteredFeePayments = allFeePayments.where((p) {
        final d = p['payment_date']?.toString().trim();
        if (d == null || d.length < 10) return false;
        final dStr = d.substring(0, 10);
        return dStr.compareTo(startStr) >= 0 && dStr.compareTo(endStr) <= 0;
      }).toList();
    } else if (_selectedSpecificDate != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedSpecificDate!);
      filteredFeePayments = allFeePayments.where((p) => p['payment_date']?.toString().startsWith(dateStr) == true).toList();
    } else if (_selectedMonth != 'All') {
      filteredFeePayments = allFeePayments.where((p) => p['payment_date']?.toString().startsWith(_selectedMonth) == true).toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232338) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(
          color: const Color(0xFF0D6B4E).withAlpha(isDark ? 60 : 40),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Active Session Badge + Year
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D6B4E),
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radio_button_checked_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 4 * scale),
                    Text(
                      'Active Ongoing Session ($yearName${hijriYear != null && hijriYear.isNotEmpty ? " • $hijriYear" : ""})',
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5 * scale,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(25),
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: Colors.green.withAlpha(60)),
                ),
                child: Text(
                  'Live Active Data',
                  style: TextStyle(
                    fontSize: 10.5 * scale,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 8 * scale),

          // Department & Class Details
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 14 * scale, color: const Color(0xFF0D6B4E)),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Text(
                  'Department: ${widget.student.departmentName ?? "General"} • Class: ${widget.student.className ?? "Not assigned"}${widget.student.division != null && widget.student.division!.isNotEmpty ? " • Div: ${widget.student.division}" : ""}${widget.student.rollNumber != null && widget.student.rollNumber!.isNotEmpty ? " • Roll: ${widget.student.rollNumber}" : ""}',
                  style: AppTheme.getFontStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1B382B),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 10 * scale),

          // ── Month & Date Interactive Explorer Filter Bar ──
          _buildMonthAndDateFilterBar(
            attendanceRecords: allAttRecords,
            feePayments: allFeePayments,
            selectedMonth: _selectedMonth,
            selectedDate: _selectedSpecificDate,
            selectedDateRange: _selectedDateRange,
            onMonthChanged: (m) => setState(() => _selectedMonth = m),
            onDateChanged: (d) => setState(() => _selectedSpecificDate = d),
            onDateRangeChanged: (r) => setState(() => _selectedDateRange = r),
            scale: scale,
            isDark: isDark,
            currentYearLabel: yearName,
          ),

          // ── Comprehensive 4-Metric Grid (Attendance, Fees: Total, Paid, Pending, Student Expense, Exam Results) ──
          _buildAcademicMetricsGrid(
            scale: scale,
            isDark: isDark,
            presentDays: displayPresentDays,
            totalDays: displayTotalDays,
            attPct: displayAttPct,
            obtMarks: obtMarks,
            totalMarks: totalMarks,
            examPct: examPct,
            grade: grade,
            feeTotal: feeTotal,
            feePaid: feePaid,
            feePending: feePending,
            feePendingMonths: feePendingMonths,
            feePaidMonths: feePaidMonths,
            perStudentExp: perStudentExp,
          ),

          SizedBox(height: 10 * scale),

          // ── Expandable Daily Attendance Records Log ──
          InkWell(
            onTap: () => setState(() => _isCurrentAttendanceLogExpanded = !_isCurrentAttendanceLogExpanded),
            borderRadius: BorderRadius.circular(6 * scale),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.white,
                borderRadius: BorderRadius.circular(6 * scale),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.how_to_reg_rounded, size: 14 * scale, color: const Color(0xFF0D6B4E)),
                  SizedBox(width: 6 * scale),
                  Expanded(
                    child: Text(
                      'Daily Attendance Records (${filteredAttRecords.length} Days${isFiltered ? " Filtered" : ""})',
                      style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    _isCurrentAttendanceLogExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16 * scale,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (_isCurrentAttendanceLogExpanded) ...[
            SizedBox(height: 6 * scale),
            _buildDailyAttendanceLog(
              records: filteredAttRecords,
              scale: scale,
              isDark: isDark,
              accentColor: const Color(0xFF0D6B4E),
            ),
          ],

          SizedBox(height: 10 * scale),

          // ── Expandable Fee Payments Transactions Log ──
          InkWell(
            onTap: () => setState(() => _isCurrentFeesLogExpanded = !_isCurrentFeesLogExpanded),
            borderRadius: BorderRadius.circular(6 * scale),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.white,
                borderRadius: BorderRadius.circular(6 * scale),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, size: 14 * scale, color: Colors.amber.shade900),
                  SizedBox(width: 6 * scale),
                  Expanded(
                    child: Text(
                      'Fee Payment Transactions (${filteredFeePayments.length} Payments${isFiltered ? " Filtered" : ""})',
                      style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(
                    _isCurrentFeesLogExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16 * scale,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          if (_isCurrentFeesLogExpanded) ...[
            SizedBox(height: 6 * scale),
            _buildFeeTransactionsLog(
              payments: filteredFeePayments,
              scale: scale,
              isDark: isDark,
              pendingBalance: feePending,
            ),
          ],

          // ── Month-by-Month Fees Status Tracker (Monthly Heads) ──
          if (feeBreakdown.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            _buildMonthlyFeeStatusTracker(
              feeBreakdown: feeBreakdown,
              scale: scale,
              isDark: isDark,
              sessionYear: yearName,
            ),
          ],

          // ── Itemized Fee Breakdown Card ──
          if (feeBreakdown.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            _buildItemizedFeeBreakdownCard(
              feeBreakdown: feeBreakdown,
              scale: scale,
              isDark: isDark,
            ),
          ],

          // Books & Exam Marks Expandable Section
          if (books.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            InkWell(
              onTap: () => setState(() => _isCurrentSessionBooksExpanded = !_isCurrentSessionBooksExpanded),
              borderRadius: BorderRadius.circular(6 * scale),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : Colors.white,
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 14 * scale, color: const Color(0xFF0D6B4E)),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        'Assigned Books & Exam Marks (${books.length} Subjects)',
                        style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(
                      _isCurrentSessionBooksExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16 * scale,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
            if (_isCurrentSessionBooksExpanded) ...[
              SizedBox(height: 6 * scale),
              _buildBooksTable(books, scale, isDark, const Color(0xFF0D6B4E)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard(StudentAcademicHistory item, double scale) {
    final isDark = widget.isDark;
    Color statusColor;
    IconData statusIcon;
    final st = item.status.toLowerCase();
    if (st == 'farigh' || st == 'graduated') {
      statusColor = const Color(0xFF6A1B9A); // Purple
      statusIcon = Icons.workspace_premium_rounded;
    } else if (st == 'repeated') {
      statusColor = const Color(0xFFE65100); // Orange
      statusIcon = Icons.refresh_rounded;
    } else {
      statusColor = const Color(0xFF2E7D32); // Green
      statusIcon = Icons.check_circle_rounded;
    }

    final books = item.parsedBooksAndMarks;
    final isBooksExpanded = _expandedBooksIds.contains(item.id);
    final pastMonth = _pastYearSelectedMonth[item.id] ?? 'All';
    final pastDate = _pastYearSelectedDate[item.id];
    final pastDateRange = _pastYearSelectedDateRange[item.id];
    final isAttExpanded = _expandedPastAttendanceIds.contains(item.id);
    final isFeesExpanded = _expandedPastFeesIds.contains(item.id);

    // Retrieve attendance records for this past session:
    List<Map<String, dynamic>> allAttRecords = item.parsedAttendanceRecords;
    if (allAttRecords.isEmpty && _currentSummary != null) {
      final allAtt = (_currentSummary!['attendance_records'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final years = item.academicYear.split(RegExp(r'[-/]')).map((y) => y.trim()).where((y) => y.length == 4).toList();
      if (years.isNotEmpty) {
        allAttRecords = allAtt.where((r) {
          final d = r['date']?.toString() ?? '';
          return years.any((yr) => d.startsWith(yr));
        }).toList();
      }
    }

    // Retrieve fee payments for this past session:
    List<Map<String, dynamic>> allFeePayments = item.parsedFeePayments;
    if (allFeePayments.isEmpty && _currentSummary != null) {
      final allFees = (_currentSummary!['fee_payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final years = item.academicYear.split(RegExp(r'[-/]')).map((y) => y.trim()).where((y) => y.length == 4).toList();
      if (years.isNotEmpty) {
        allFeePayments = allFees.where((p) {
          final d = p['payment_date']?.toString() ?? '';
          return years.any((yr) => d.startsWith(yr));
        }).toList();
      }
    }

    // Filter by month/date/date-range
    List<Map<String, dynamic>> filteredAttRecords = allAttRecords;
    if (pastDateRange != null) {
      final startStr = DateFormat('yyyy-MM-dd').format(pastDateRange.start);
      final endStr = DateFormat('yyyy-MM-dd').format(pastDateRange.end);
      filteredAttRecords = allAttRecords.where((r) {
        final d = r['date']?.toString().trim();
        if (d == null || d.length < 10) return false;
        final dStr = d.substring(0, 10);
        return dStr.compareTo(startStr) >= 0 && dStr.compareTo(endStr) <= 0;
      }).toList();
    } else if (pastDate != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(pastDate);
      filteredAttRecords = allAttRecords.where((r) => r['date']?.toString().startsWith(dateStr) == true).toList();
    } else if (pastMonth != 'All') {
      filteredAttRecords = allAttRecords.where((r) => r['date']?.toString().startsWith(pastMonth) == true).toList();
    }

    final isFiltered = pastMonth != 'All' || pastDate != null || pastDateRange != null;
    int displayPresent = 0;
    for (final r in filteredAttRecords) {
      final st = (r['status']?.toString() ?? '').toLowerCase();
      if (st == 'present' || st == 'p' || st == 'hazir') displayPresent++;
    }
    final displayTotal = isFiltered ? filteredAttRecords.length : item.totalAttendanceDays;
    if (!isFiltered) displayPresent = item.presentDays;
    final displayPct = displayTotal > 0 ? ((displayPresent / displayTotal) * 100) : 0.0;

    List<Map<String, dynamic>> filteredFeePayments = allFeePayments;
    if (pastDateRange != null) {
      final startStr = DateFormat('yyyy-MM-dd').format(pastDateRange.start);
      final endStr = DateFormat('yyyy-MM-dd').format(pastDateRange.end);
      filteredFeePayments = allFeePayments.where((p) {
        final d = p['payment_date']?.toString().trim();
        if (d == null || d.length < 10) return false;
        final dStr = d.substring(0, 10);
        return dStr.compareTo(startStr) >= 0 && dStr.compareTo(endStr) <= 0;
      }).toList();
    } else if (pastDate != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(pastDate);
      filteredFeePayments = allFeePayments.where((p) => p['payment_date']?.toString().startsWith(dateStr) == true).toList();
    } else if (pastMonth != 'All') {
      filteredFeePayments = allFeePayments.where((p) => p['payment_date']?.toString().startsWith(pastMonth) == true).toList();
    }

    // Resolve or synthesize fee breakdown for past session
    List<Map<String, dynamic>> pastFeeBreakdown = item.parsedFeeBreakdown;
    if (pastFeeBreakdown.isEmpty && item.feeTotal > 0) {
      final mFee = widget.student.monthlyFees ?? 0.0;
      final mMonths = mFee > 0 ? (item.feeTotal / mFee).round().clamp(1, 12) : 12;
      final paidMo = mFee > 0 ? (item.feePaid / mFee).floor().clamp(0, mMonths) : 0;
      final pendMo = (mMonths - paidMo).clamp(0, mMonths);
      pastFeeBreakdown = [
        {
          'fee_type_name': 'Session Tuition Fee',
          'amount': mFee > 0 ? mFee : (item.feeTotal / 12),
          'billing_type': 'monthly',
          'months_count': mMonths,
          'paid_months': paidMo,
          'pending_months': pendMo,
          'total_expected': item.feeTotal,
          'total_paid': item.feePaid,
          'total_pending': item.feePending,
        }
      ];
    }

    int pastFeePendingMonths = 0;
    int pastFeePaidMonths = 0;
    for (final head in pastFeeBreakdown) {
      final billing = (head['billing_type']?.toString() ?? 'monthly').toLowerCase();
      if (billing == 'monthly') {
        pastFeePendingMonths += (head['pending_months'] as num?)?.toInt() ?? 0;
        pastFeePaidMonths += (head['paid_months'] as num?)?.toInt() ?? 0;
      }
    }
    if (pastFeePendingMonths == 0 && pastFeePaidMonths == 0 && item.feeTotal > 0 && widget.student.monthlyFees != null && widget.student.monthlyFees! > 0) {
      pastFeePaidMonths = (item.feePaid / widget.student.monthlyFees!).floor().clamp(0, 12);
      pastFeePendingMonths = (12 - pastFeePaidMonths).clamp(0, 12);
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252538) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Year + Status Badge + Delete
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 12 * scale, color: AppTheme.primaryColor),
                    SizedBox(width: 4 * scale),
                    Text(
                      'Session ${item.academicYear}',
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5 * scale,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    if (item.academicYearHijri != null && item.academicYearHijri!.isNotEmpty) ...[
                      SizedBox(width: 4 * scale),
                      Text(
                        '(${item.academicYearHijri})',
                        style: AppTheme.getFontStyle(
                          fontSize: 10 * scale,
                          color: AppTheme.primaryColor.withAlpha(200),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: statusColor.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12 * scale, color: statusColor),
                    SizedBox(width: 4 * scale),
                    Text(
                      item.status,
                      style: AppTheme.getFontStyle(
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 4 * scale),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 16 * scale, color: Colors.redAccent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Delete this record',
                onPressed: () => _deleteHistory(item.id),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),

          // Department, Class, Division, Roll Number
          Row(
            children: [
              Icon(Icons.class_outlined, size: 14 * scale, color: Colors.grey.shade600),
              SizedBox(width: 6 * scale),
              Expanded(
                child: Text(
                  '${item.departmentName != null && item.departmentName!.isNotEmpty ? "Dept: ${item.departmentName} • " : ""}Class: ${item.className}${item.division != null && item.division!.isNotEmpty ? " • Div: ${item.division}" : ""}${item.rollNumber != null && item.rollNumber!.isNotEmpty ? " • Roll No: ${item.rollNumber}" : ""}',
                  style: AppTheme.getFontStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF333333),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10 * scale),

          // ── Month & Date Filter Bar for Past Session ──
          if (allAttRecords.isNotEmpty || allFeePayments.isNotEmpty) ...[
            _buildMonthAndDateFilterBar(
              attendanceRecords: allAttRecords,
              feePayments: allFeePayments,
              selectedMonth: pastMonth,
              selectedDate: pastDate,
              selectedDateRange: pastDateRange,
              onMonthChanged: (m) => setState(() => _pastYearSelectedMonth[item.id] = m),
              onDateChanged: (d) => setState(() => _pastYearSelectedDate[item.id] = d),
              onDateRangeChanged: (r) => setState(() => _pastYearSelectedDateRange[item.id] = r),
              scale: scale,
              isDark: isDark,
              currentYearLabel: item.academicYear,
            ),
          ],

          // ── Comprehensive 4-Metric Grid ──
          _buildAcademicMetricsGrid(
            scale: scale,
            isDark: isDark,
            presentDays: displayPresent,
            totalDays: displayTotal,
            attPct: displayPct,
            obtMarks: item.obtainedMarks,
            totalMarks: item.totalMarks,
            examPct: item.examPercentage,
            grade: item.resultGrade ?? '-',
            feeTotal: item.feeTotal,
            feePaid: item.feePaid,
            feePending: item.feePending,
            feePendingMonths: pastFeePendingMonths,
            feePaidMonths: pastFeePaidMonths,
            perStudentExp: item.perStudentExpense,
          ),

          // ── Expandable Daily Attendance Records Log (Past Session) ──
          if (allAttRecords.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            InkWell(
              onTap: () {
                setState(() {
                  if (_expandedPastAttendanceIds.contains(item.id)) {
                    _expandedPastAttendanceIds.remove(item.id);
                  } else {
                    _expandedPastAttendanceIds.add(item.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(6 * scale),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.how_to_reg_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        'Daily Attendance Records (${filteredAttRecords.length} Days${isFiltered ? " Filtered" : ""})',
                        style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(
                      isAttExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16 * scale,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
            if (isAttExpanded) ...[
              SizedBox(height: 6 * scale),
              _buildDailyAttendanceLog(
                records: filteredAttRecords,
                scale: scale,
                isDark: isDark,
                accentColor: AppTheme.primaryColor,
              ),
            ],
          ],

          // ── Expandable Fee Payments Log (Past Session) ──
          if (allFeePayments.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            InkWell(
              onTap: () {
                setState(() {
                  if (_expandedPastFeesIds.contains(item.id)) {
                    _expandedPastFeesIds.remove(item.id);
                  } else {
                    _expandedPastFeesIds.add(item.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(6 * scale),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, size: 14 * scale, color: Colors.amber.shade900),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        'Fee Payment Transactions (${filteredFeePayments.length} Payments${isFiltered ? " Filtered" : ""})',
                        style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(
                      isFeesExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16 * scale,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
            if (isFeesExpanded) ...[
              SizedBox(height: 6 * scale),
              _buildFeeTransactionsLog(
                payments: filteredFeePayments,
                scale: scale,
                isDark: isDark,
                pendingBalance: item.feePending,
              ),
            ],
          ],

          // ── Month-by-Month Fees Status Tracker (Past Session) ──
          if (pastFeeBreakdown.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            _buildMonthlyFeeStatusTracker(
              feeBreakdown: pastFeeBreakdown,
              scale: scale,
              isDark: isDark,
              sessionYear: item.academicYear,
            ),
          ],

          // ── Itemized Fee Breakdown Card (Past Session) ──
          if (pastFeeBreakdown.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            _buildItemizedFeeBreakdownCard(
              feeBreakdown: pastFeeBreakdown,
              scale: scale,
              isDark: isDark,
            ),
          ],

          // Books & Exam Marks Expandable Section
          if (books.isNotEmpty) ...[
            SizedBox(height: 10 * scale),
            InkWell(
              onTap: () {
                setState(() {
                  if (_expandedBooksIds.contains(item.id)) {
                    _expandedBooksIds.remove(item.id);
                  } else {
                    _expandedBooksIds.add(item.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(6 * scale),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6 * scale),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                    SizedBox(width: 6 * scale),
                    Expanded(
                      child: Text(
                        'Books & Exam Marks (${books.length} Subjects)',
                        style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(
                      isBooksExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16 * scale,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
            if (isBooksExpanded) ...[
              SizedBox(height: 6 * scale),
              _buildBooksTable(books, scale, isDark, AppTheme.primaryColor),
            ],
          ],

          if (item.remarks != null && item.remarks!.isNotEmpty) ...[
            SizedBox(height: 6 * scale),
            Text(
              'Remarks: ${item.remarks}',
              style: AppTheme.getFontStyle(
                fontSize: 11 * scale,
                color: Colors.grey.shade500,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemizedFeeBreakdownCard({
    required List<dynamic> feeBreakdown,
    required double scale,
    required bool isDark,
  }) {
    if (feeBreakdown.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.white,
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 14 * scale, color: Colors.amber.shade900),
              SizedBox(width: 6 * scale),
              Text(
                'Itemized Fee Heads Breakdown',
                style: AppTheme.getFontStyle(
                  fontSize: 11.5 * scale,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1B382B),
                ),
              ),
              const Spacer(),
              Text(
                '${feeBreakdown.length} Fee Heads',
                style: AppTheme.getFontStyle(fontSize: 10.5 * scale, color: Colors.grey.shade500),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          ...feeBreakdown.map((item) {
            final map = item is Map<String, dynamic>
                ? item
                : (item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{});
            final name = map['fee_type_name']?.toString() ?? 'Fee';
            final billing = map['billing_type']?.toString() ?? 'monthly';
            final months = (map['months_count'] as num?)?.toInt() ?? 1;
            final expected = (map['total_expected'] as num?)?.toDouble() ?? 0.0;
            final paid = (map['total_paid'] as num?)?.toDouble() ?? 0.0;
            final pending = (map['total_pending'] as num?)?.toDouble() ?? 0.0;
            final isFullyPaid = pending <= 0 && expected > 0;

            final origAmt = (map['original_amount'] as num?)?.toDouble();
            final discAmt = (map['discount_amount'] as num?)?.toDouble() ?? 0.0;
            final discTag = map['discount_tag']?.toString() ?? '';
            final displayTag = discAmt > 0
                ? _formatDiscountDisplay(discAmt, origAmt ?? (map['amount'] as num?)?.toDouble() ?? 0.0, discTag)
                : '';

            final typeBadge = billing == 'one_time'
                ? 'One-Time'
                : billing == 'yearly'
                    ? 'Yearly'
                    : '$months Mo';

            return Container(
              margin: EdgeInsets.only(bottom: 6 * scale),
              padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6 * scale),
                border: Border.all(
                  color: isFullyPaid
                      ? Colors.green.withAlpha(50)
                      : (pending > 0 ? Colors.red.withAlpha(40) : Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4 * scale),
                    ),
                    child: Text(
                      typeBadge,
                      style: TextStyle(
                        fontSize: 9.5 * scale,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4 * scale,
                          children: [
                            Text(
                              name,
                              style: AppTheme.getFontStyle(
                                fontSize: 11.5 * scale,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (discAmt > 0)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(3 * scale),
                                  border: Border.all(color: Colors.red.shade200, width: 0.5),
                                ),
                                child: Text(
                                  displayTag.isNotEmpty ? displayTag : '-₹${discAmt.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 8.5 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (billing == 'monthly' && map['amount'] != null)
                          Row(
                            children: [
                              if (origAmt != null && origAmt > (map['amount'] as num).toDouble())
                                Text(
                                  '₹${origAmt.toStringAsFixed(0)} ',
                                  style: TextStyle(
                                    fontSize: 9.5 * scale,
                                    color: Colors.grey.shade400,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              Text(
                                '₹${(map['amount'] as num).toDouble().toStringAsFixed(0)} / mo × $months months',
                                style: TextStyle(fontSize: 10 * scale, color: Colors.grey.shade500),
                              ),
                            ],
                          )
                        else if (origAmt != null && discAmt > 0)
                          Text(
                            'Orig: ₹${origAmt.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9.5 * scale,
                              color: Colors.grey.shade400,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Paid: ₹${paid.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                          Text(
                            ' / ₹${expected.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 11 * scale, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      SizedBox(height: 2 * scale),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1 * scale),
                        decoration: BoxDecoration(
                          color: isFullyPaid ? Colors.green.withAlpha(25) : Colors.red.withAlpha(20),
                          borderRadius: BorderRadius.circular(4 * scale),
                        ),
                        child: Text(
                          isFullyPaid
                              ? 'Fully Paid'
                              : (billing == 'monthly' && (map['pending_months'] as num?) != null && (map['pending_months'] as num).toInt() > 0
                                  ? 'Pending: ₹${pending.toStringAsFixed(0)} (${(map['pending_months'] as num).toInt()} Mo Due)'
                                  : 'Pending: ₹${pending.toStringAsFixed(0)}'),
                          style: TextStyle(
                            fontSize: 9.5 * scale,
                            fontWeight: FontWeight.bold,
                            color: isFullyPaid ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBooksTable(List<Map<String, dynamic>> books, double scale, bool isDark, Color accentColor) {
    return Container(
      padding: EdgeInsets.all(10 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(8 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        children: books.map((b) {
          final bName = b['book_name']?.toString() ?? 'Book';
          final exams = (b['exams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final bMax = (b['total_max'] as num?)?.toDouble() ?? 0.0;
          final bObt = (b['total_obtained'] as num?)?.toDouble() ?? 0.0;
          final bPct = (b['percentage'] as num?)?.toDouble() ?? 0.0;

          return Container(
            padding: EdgeInsets.symmetric(vertical: 5 * scale),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade100),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bookmark_outline_rounded, size: 13 * scale, color: accentColor),
                SizedBox(width: 6 * scale),
                Expanded(
                  flex: 3,
                  child: Text(
                    bName,
                    style: AppTheme.getFontStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 6 * scale),
                Expanded(
                  flex: 5,
                  child: Wrap(
                    spacing: 4 * scale,
                    runSpacing: 4 * scale,
                    children: [
                      ...exams.map((ex) {
                        final exName = ex['exam_name']?.toString() ?? 'Exam';
                        final obt = (ex['marks_obtained'] as num?)?.toDouble() ?? 0.0;
                        final max = (ex['max_marks'] as num?)?.toDouble() ?? 100.0;
                        final isAbs = ex['is_absent'] == true;
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            '$exName: ${isAbs ? "Abs" : "${obt.toStringAsFixed(0)}/${max.toStringAsFixed(0)}"}',
                            style: TextStyle(
                              fontSize: 10 * scale,
                              color: isAbs ? Colors.red : (isDark ? Colors.white70 : Colors.grey.shade800),
                            ),
                          ),
                        );
                      }),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                        decoration: BoxDecoration(
                          color: accentColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(4 * scale),
                        ),
                        child: Text(
                          'Total: ${bObt.toStringAsFixed(0)}/${bMax.toStringAsFixed(0)} (${bPct.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PromoteStudentDialog extends StatefulWidget {
  final Student student;
  final bool isDark;
  final VoidCallback onSuccess;

  const _PromoteStudentDialog({
    required this.student,
    required this.isDark,
    required this.onSuccess,
  });

  @override
  State<_PromoteStudentDialog> createState() => _PromoteStudentDialogState();
}

class _PromoteStudentDialogState extends State<_PromoteStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _academicYearController;
  late TextEditingController _hijriYearController;
  late TextEditingController _divisionController;
  late TextEditingController _rollNumberController;
  late TextEditingController _remarksController;

  String _selectedStatus = 'Promoted';
  String? _selectedNextClass;
  String? _selectedDepartment;
  List<String> _availableClasses = [];
  List<String> _availableDepartments = [];
  bool _isLoading = true;
  bool _isSaving = false;

  Map<String, dynamic>? _calculatedSummary;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final curYear = '${now.year}-${now.year + 1}';
    final curHijri = '${now.year - 579}-${now.year - 578} H';

    _academicYearController = TextEditingController(text: curYear);
    _hijriYearController = TextEditingController(text: curHijri);
    _divisionController = TextEditingController(text: widget.student.division ?? '');
    _rollNumberController = TextEditingController(text: widget.student.rollNumber ?? '');
    _remarksController = TextEditingController();

    _loadInitialData();
  }

  @override
  void dispose() {
    _academicYearController.dispose();
    _hijriYearController.dispose();
    _divisionController.dispose();
    _rollNumberController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final rawClasses = await DatabaseHelper().getDistinctClassNames();
      final deptSeries = await DatabaseHelper().getDepartmentProgressionSeries();
      final summary = await DatabaseHelper().calculateStudentAcademicSummary(
        widget.student.id,
        classId: widget.student.className,
        fallbackMonthlyFees: widget.student.monthlyFees,
        fallbackAdmissionFee: widget.student.admissionFee,
        fallbackBookFee: widget.student.bookFee,
        fallbackFeeStructure: widget.student.feeStructure,
      );

      if (mounted) {
        final classes = <String>[];
        final seenClasses = <String>{};
        for (final c in rawClasses) {
          final trimmed = c.trim();
          if (trimmed.isNotEmpty && !seenClasses.contains(trimmed.toLowerCase())) {
            seenClasses.add(trimmed.toLowerCase());
            classes.add(trimmed);
          }
        }
        final curClass = widget.student.className?.trim();
        if (curClass != null && curClass.isNotEmpty && !seenClasses.contains(curClass.toLowerCase())) {
          seenClasses.add(curClass.toLowerCase());
          classes.add(curClass);
        }

        final depts = <String>[];
        final seenDepts = <String>{};
        for (final d in deptSeries) {
          final name = d['department_name']?.toString().trim();
          if (name != null && name.isNotEmpty && !seenDepts.contains(name.toLowerCase())) {
            seenDepts.add(name.toLowerCase());
            depts.add(name);
          }
        }
        final curDept = widget.student.departmentName?.trim();
        if (curDept != null && curDept.isNotEmpty && !seenDepts.contains(curDept.toLowerCase())) {
          seenDepts.add(curDept.toLowerCase());
          depts.add(curDept);
        }

        final nextProg = await DatabaseHelper().getNextProgressionForStudent(
          currentClass: curClass,
          currentDepartment: widget.student.departmentName,
          availableClasses: classes,
        );
        final predictedNext = nextProg['next_class']?.toString() ?? 'Farigh';
        final predictedDept = nextProg['next_department']?.toString() ?? widget.student.departmentName;

        if (predictedDept != null && predictedDept.isNotEmpty && !seenDepts.contains(predictedDept.toLowerCase())) {
          seenDepts.add(predictedDept.toLowerCase());
          depts.add(predictedDept);
        }

        setState(() {
          _availableClasses = classes;
          _availableDepartments = depts;
          if (predictedNext == 'Farigh') {
            _selectedStatus = 'Farigh';
            _selectedNextClass = 'Farigh';
            _selectedDepartment = widget.student.departmentName;
          } else {
            _selectedNextClass = predictedNext;
            _selectedDepartment = predictedDept;
          }
          _calculatedSummary = summary;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onClassChanged(String? newClass) async {
    setState(() => _selectedNextClass = newClass);
    if (newClass != null && newClass.isNotEmpty) {
      try {
        final classRows = await DatabaseHelper().getClassProgressionSeries();
        for (final r in classRows) {
          if (r['class_name']?.toString().trim().toLowerCase() == newClass.trim().toLowerCase()) {
            final dept = r['department_name']?.toString().trim();
            if (dept != null && dept.isNotEmpty) {
              setState(() {
                if (!_availableDepartments.any((d) => d.toLowerCase() == dept.toLowerCase())) {
                  _availableDepartments.add(dept);
                }
                _selectedDepartment = _availableDepartments.firstWhere(
                  (d) => d.toLowerCase() == dept.toLowerCase(),
                  orElse: () => dept,
                );
              });
              break;
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final targetClass = (_selectedStatus == 'Farigh')
          ? 'Farigh'
          : (_selectedNextClass ?? widget.student.className ?? 'Next Class');
      final targetDept = (_selectedStatus == 'Farigh')
          ? widget.student.departmentName
          : (_selectedDepartment ?? widget.student.departmentName);

      await StudentRepository(ApiClient()).recordAcademicPromotion(
        student: widget.student,
        academicYear: _academicYearController.text.trim(),
        academicYearHijri: _hijriYearController.text.trim().isNotEmpty ? _hijriYearController.text.trim() : null,
        targetClass: targetClass,
        targetDepartmentName: targetDept,
        targetDivision: _divisionController.text.trim().isNotEmpty ? _divisionController.text.trim() : null,
        targetRollNumber: _rollNumberController.text.trim().isNotEmpty ? _rollNumberController.text.trim() : null,
        status: _selectedStatus,
        remarks: _remarksController.text.trim().isNotEmpty ? _remarksController.text.trim() : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedStatus == 'Farigh'
                  ? 'Student marked as Farigh (Graduated) and academic record archived!'
                  : 'Student promoted to "$targetClass" ($targetDept) and previous year archived!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save promotion: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return MovableResizableDialog(
      initialWidth: 560,
      initialHeight: 640,
      minWidth: 440,
      minHeight: 480,
      headerLeading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Academic Promotion & Transition',
            style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            widget.student.fullName,
            style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.white.withAlpha(180)),
          ),
        ],
      ),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: AppTheme.primaryColor, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Current Class: ${widget.student.className ?? "-"} | Dept: ${widget.student.departmentName ?? "-"} | Div: ${widget.student.division ?? "-"} | Roll: ${widget.student.rollNumber ?? "-"}',
                                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                if (_calculatedSummary != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Yearly Snapshot: Att: ${_calculatedSummary!["present_days"]}/${_calculatedSummary!["total_attendance_days"]} (${(_calculatedSummary!["attendance_percentage"] as num).toStringAsFixed(0)}%) • Result: ${(_calculatedSummary!["obtained_marks"] as num).toStringAsFixed(0)}/${(_calculatedSummary!["total_marks"] as num).toStringAsFixed(0)} • ${_calculatedSummary!["result_grade"]}',
                                    style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _academicYearController,
                            decoration: const InputDecoration(
                              labelText: 'Academic Year *',
                              hintText: 'e.g. 2025-2026',
                              prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _hijriYearController,
                            decoration: const InputDecoration(
                              labelText: 'Hijri Year',
                              hintText: 'e.g. 1446-1447 H',
                              prefixIcon: Icon(Icons.star_border_rounded, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Action / Status *',
                        prefixIcon: Icon(Icons.trending_up_rounded, size: 18),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Promoted', child: Text('Promoted to Next Class')),
                        DropdownMenuItem(value: 'Farigh', child: Text('Graduated / Completed (Farigh)')),
                        DropdownMenuItem(value: 'Repeated', child: Text('Repeat Current Class')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedStatus = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    if (_selectedStatus != 'Farigh') ...[
                      Row(
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final distinctDepts = _availableDepartments
                                    .map((d) => d.trim())
                                    .where((d) => d.isNotEmpty)
                                    .toSet()
                                    .toList();
                                final currentDept = distinctDepts.firstWhere(
                                  (d) => d.toLowerCase() == (_selectedDepartment ?? '').toLowerCase(),
                                  orElse: () => distinctDepts.isNotEmpty ? distinctDepts.first : '',
                                );

                                 return DropdownButtonFormField<String>(
                                  key: ValueKey('dept_${currentDept}_${distinctDepts.length}'),
                                  initialValue: currentDept.isNotEmpty ? currentDept : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Target Department',
                                    prefixIcon: Icon(Icons.account_tree_outlined, size: 18),
                                  ),
                                  items: distinctDepts.map((d) {
                                    return DropdownMenuItem(value: d, child: Text(d));
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() => _selectedDepartment = val);
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final distinctClasses = _availableClasses
                                    .map((c) => c.trim())
                                    .where((c) => c.isNotEmpty)
                                    .toSet()
                                    .toList();
                                final currentClass = distinctClasses.firstWhere(
                                  (c) => c.toLowerCase() == (_selectedNextClass ?? '').toLowerCase(),
                                  orElse: () => distinctClasses.isNotEmpty ? distinctClasses.first : '',
                                );

                                return DropdownButtonFormField<String>(
                                  key: ValueKey('class_${currentClass}_${distinctClasses.length}'),
                                  initialValue: currentClass.isNotEmpty ? currentClass : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Next Class *',
                                    prefixIcon: Icon(Icons.class_outlined, size: 18),
                                  ),
                                  items: distinctClasses.map((c) {
                                    return DropdownMenuItem(value: c, child: Text(c));
                                  }).toList(),
                                  onChanged: _onClassChanged,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _divisionController,
                              decoration: const InputDecoration(
                                labelText: 'Division',
                                hintText: 'e.g. A',
                                prefixIcon: Icon(Icons.grid_view_rounded, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _rollNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Roll Number',
                                hintText: 'e.g. 15',
                                prefixIcon: Icon(Icons.numbers_rounded, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _remarksController,
                      decoration: const InputDecoration(
                        labelText: 'Remarks / Notes (Optional)',
                        hintText: 'e.g. Promoted with distinction / Hifz completed',
                        prefixIcon: Icon(Icons.note_alt_outlined, size: 18),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
      actions: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isSaving ? null : _handleSave,
              icon: _isSaving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Confirm & Save'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
            ),
          ],
        ),
      ),
    );
  }
}

