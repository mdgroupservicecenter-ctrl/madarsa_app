import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/constants/app_constants.dart';
import '../bloc/students_bloc.dart';
import '../../data/models/student_model.dart';
import '../../data/repositories/student_repository.dart';
import '../widgets/student_form_dialog.dart';
import '../widgets/student_id_card_builder_dialog.dart';
import '../widgets/gr_no_config_dialog.dart';
import '../widgets/academic_history_explorer_dialog.dart';
import 'student_profile_screen.dart';
import '../../../../core/network/api_client.dart';
import '../../data/services/student_excel_service.dart';
import '../../../../core/services/student_status_settings.dart';
import '../../../../core/services/student_form_options_settings.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../shared/widgets/movable_resizable_dialog.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  void _openStudentProfile(String studentId, {Student? initialStudent}) {
    if (!_ensureFeatureAccess('students_view', 'Student Directory & Profiles')) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (routeContext, animation, secondaryAnimation) => BlocProvider(
          create: (_) => StudentsBloc(repository: StudentRepository(ApiClient())),
          child: StudentProfileScreen(
            studentId: studentId,
            initialStudent: initialStudent,
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.04, 0.0);
          const end = Offset.zero;
          final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: begin, end: end).animate(curve),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 130),
      ),
    );
  }

  void _showBulkAssignStatusDialog() {
    if (!_ensureFeatureAccess('students_edit', 'Bulk Assign Status')) return;
    if (_selectedStudentIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _BulkAssignStatusModal(
        studentIds: List<String>.from(_selectedStudentIds),
        repository: StudentRepository(ApiClient()),
        onSuccess: () {
          setState(() {
            _selectedStudentIds.clear();
            _isSelectionMode = false;
          });
          context.read<StudentsBloc>().add(LoadStudents(silent: true));
        },
      ),
    );
  }

  void _showBulkPromoteDialog() {
    if (!_ensureFeatureAccess('students_edit', 'Bulk Promotion')) return;
    if (_selectedStudentIds.isEmpty) return;

    final state = context.read<StudentsBloc>().state;
    List<Student> selectedStudents = [];
    if (state is StudentsLoaded) {
      selectedStudents = state.students.where((s) => _selectedStudentIds.contains(s.id)).toList();
    }

    showDialog(
      context: context,
      builder: (dialogContext) => _BulkPromoteModal(
        selectedStudents: selectedStudents,
        repository: StudentRepository(ApiClient()),
        onSuccess: () {
          setState(() {
            _selectedStudentIds.clear();
            _isSelectionMode = false;
          });
          context.read<StudentsBloc>().add(LoadStudents(silent: true));
        },
      ),
    );
  }

  void _showImportExcelDialog(List<Student> currentStudents) {
    if (!_ensureFeatureAccess('students_excel_import', 'Import from Excel')) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _ExcelImportModal(
        studentRepository: StudentRepository(ApiClient()),
        onImportSuccess: () {
          context.read<StudentsBloc>().add(LoadStudents());
        },
      ),
    );
  }

  Future<void> _exportToExcel(List<Student> students) async {
    if (!_ensureFeatureAccess('students_excel_export', 'Export to Excel')) return;

    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No student records to export.')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exporting student records to Excel/CSV...')),
      );

      final filePath = await StudentExcelService.exportStudentsToCsv(students);
      if (filePath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported successfully: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () {
                final uri = Uri.file(filePath);
                launchUrl(uri);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export students: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  /// Builds a combined display name: fullName + fatherName + surname
  static String _displayName(Student s) {
    final parts = <String>[
      s.fullName,
      if (s.fatherName != null && s.fatherName!.isNotEmpty) s.fatherName!,
      if (s.surname != null && s.surname!.isNotEmpty) s.surname!,
    ];
    return parts.join(' ');
  }

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  Timer? _debounce;
  // 'table' or 'card'
  String _viewMode = 'card';

  // Student Filter state
  String? _filterClass;
  String? _filterVillage;
  String? _filterDistrict;
  String? _filterState;
  String? _filterCategory;
  String? _filterDivision;
  String? _filterGender;
  String? _filterStatus;
  String? _filterMinAge;
  String? _filterMaxAge;
  String? _filterDepartment; // Main Department filter
  String? _filterSubDepartment; // Sub-Department filter

  // ── Performance & Zero-Lag Memoization Cache ───────────────────────────────
  List<Student>? _cachedRawStudents;
  int _cachedFilterHash = 0;
  List<Student> _cachedFilteredStudents = const [];

  final Map<String, int> _cachedStatsMap = {};
  int _cachedStatsFilterHash = 0;
  List<Student>? _cachedStatsStudentsRef;

  int _computeFilterHash() {
    return Object.hashAll([
      _filterDepartment,
      _filterSubDepartment,
      _filterClass,
      _filterVillage,
      _filterDistrict,
      _filterState,
      _filterCategory,
      _filterDivision,
      _filterGender,
      _filterStatus,
      _filterMinAge,
      _filterMaxAge,
      _searchQuery,
      _allDepartments.length,
      _academicHierarchy.length,
    ]);
  }

  // ── Customizable Stat Cards Configuration ──────────────────────────────────
  List<StudentStatCardConfig> _statCardConfigs = [];

  Future<void> _loadStatCardConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('students_stat_cards_config_v2');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final list = decoded
            .map((item) => StudentStatCardConfig.fromJson(item as Map<String, dynamic>))
            .toList();
        if (list.length == 4) {
          if (mounted) {
            setState(() {
              _statCardConfigs = list;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error loading stat cards config: $e');
    }

    await _initDefaultStatCardConfigs();
  }

  Future<void> _initDefaultStatCardConfigs() async {
    String primaryStatus = 'Active';
    String primaryGender1 = 'Male';
    String primaryGender2 = 'Female';

    try {
      final statuses = await StudentStatusSettings.getStatuses();
      if (statuses.isNotEmpty) {
        primaryStatus = statuses.first;
      }
      final genders = await StudentFormOptionsSettings.getGenders();
      if (genders.isNotEmpty) {
        primaryGender1 = genders[0];
        if (genders.length > 1) {
          primaryGender2 = genders[1];
        }
      }
    } catch (_) {}

    final defaultList = [
      StudentStatCardConfig(
        id: 'card_1',
        type: 'total',
        label: 'Total',
        filterValue: null,
        iconCodePoint: Icons.people_alt_rounded.codePoint,
        colorValue: 0xFF0D6B4E,
      ),
      StudentStatCardConfig(
        id: 'card_2',
        type: 'status',
        label: primaryStatus,
        filterValue: primaryStatus,
        iconCodePoint: Icons.check_circle_outline_rounded.codePoint,
        colorValue: 0xFF1565C0,
      ),
      StudentStatCardConfig(
        id: 'card_3',
        type: 'gender',
        label: primaryGender1,
        filterValue: primaryGender1,
        iconCodePoint: Icons.male_rounded.codePoint,
        colorValue: 0xFF6A1B9A,
      ),
      StudentStatCardConfig(
        id: 'card_4',
        type: 'gender',
        label: primaryGender2,
        filterValue: primaryGender2,
        iconCodePoint: Icons.female_rounded.codePoint,
        colorValue: 0xFFC62828,
      ),
    ];

    if (mounted) {
      setState(() {
        _statCardConfigs = defaultList;
      });
    }
  }

  Future<void> _saveStatCardConfigs(List<StudentStatCardConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
      await prefs.setString('students_stat_cards_config_v2', jsonStr);
      if (mounted) {
        setState(() {
          _statCardConfigs = List.from(configs);
        });
      }
    } catch (e) {
      debugPrint('Error saving stat cards config: $e');
    }
  }

  int _calculateStatCount(List<Student> students, StudentStatCardConfig config) {
    if (students.isEmpty) return 0;
    if (config.type == 'total') return students.length;

    final currentHash = _computeFilterHash();
    final cacheKey = '${config.id}_${config.type}_${config.filterValue ?? config.label}';

    if (identical(_cachedStatsStudentsRef, students) && _cachedStatsFilterHash == currentHash) {
      if (_cachedStatsMap.containsKey(cacheKey)) {
        return _cachedStatsMap[cacheKey]!;
      }
    } else {
      _cachedStatsStudentsRef = students;
      _cachedStatsFilterHash = currentHash;
      _cachedStatsMap.clear();
    }

    final target = (config.filterValue ?? config.label).trim().toLowerCase();
    int count = 0;

    switch (config.type) {
      case 'total':
        count = students.length;
        break;

      case 'status':
        for (int i = 0; i < students.length; i++) {
          final s = students[i];
          final st = (s.studentStatus ?? '').trim().toLowerCase();
          if (st.isNotEmpty) {
            if (st == target) {
              count++;
            } else if ((target == 'active' || target == 'chalu' || target == 'regular') &&
                (st == 'active' || st == 'chalu' || st == 'regular')) {
              count++;
            } else if ((target == 'inactive' || target == 'kharij' || target == 'left') &&
                (st == 'inactive' || st == 'kharij' || st == 'left')) {
              count++;
            }
          } else {
            if ((target == 'active' || target == 'chalu' || target == 'regular') && s.isActive) {
              count++;
            } else if ((target == 'inactive' || target == 'kharij' || target == 'left') && !s.isActive) {
              count++;
            }
          }
        }
        break;

      case 'gender':
        for (int i = 0; i < students.length; i++) {
          final s = students[i];
          final g = (s.gender ?? '').trim().toLowerCase();
          if (g.isNotEmpty) {
            if (g == target) {
              count++;
            } else if ((target == 'male' || target == 'ladka' || target == 'boy' || target == 'boys' || target == 'm') &&
                (g == 'male' || g == 'ladka' || g == 'boy' || g == 'boys' || g == 'm')) {
              count++;
            } else if ((target == 'female' || target == 'ladki' || target == 'girl' || target == 'girls' || target == 'f') &&
                (g == 'female' || g == 'ladki' || g == 'girl' || g == 'girls' || g == 'f')) {
              count++;
            }
          }
        }
        break;

      case 'category':
        for (int i = 0; i < students.length; i++) {
          final cat = (students[i].category ?? '').trim().toLowerCase();
          if (cat == target || cat.contains(target)) count++;
        }
        break;

      case 'department':
        for (int i = 0; i < students.length; i++) {
          final dept = (students[i].departmentName ?? '').trim().toLowerCase();
          if (dept == target || dept.contains(target)) count++;
        }
        break;

      case 'condition':
        for (int i = 0; i < students.length; i++) {
          final cond = (students[i].conditionType ?? '').trim().toLowerCase();
          if (cond == target || cond.contains(target)) count++;
        }
        break;

      case 'with_mobile':
        for (int i = 0; i < students.length; i++) {
          if (students[i].mobileNo != null && students[i].mobileNo!.trim().isNotEmpty) count++;
        }
        break;

      case 'without_mobile':
        for (int i = 0; i < students.length; i++) {
          if (students[i].mobileNo == null || students[i].mobileNo!.trim().isEmpty) count++;
        }
        break;

      case 'with_aadhaar':
        for (int i = 0; i < students.length; i++) {
          if (students[i].aadhaarNo != null && students[i].aadhaarNo!.trim().isNotEmpty) count++;
        }
        break;

      case 'without_aadhaar':
        for (int i = 0; i < students.length; i++) {
          if (students[i].aadhaarNo == null || students[i].aadhaarNo!.trim().isEmpty) count++;
        }
        break;

      default:
        for (int i = 0; i < students.length; i++) {
          final s = students[i];
          final st = (s.studentStatus ?? '').trim().toLowerCase();
          final g = (s.gender ?? '').trim().toLowerCase();
          final c = (s.category ?? '').trim().toLowerCase();
          if (st == target || g == target || c == target) count++;
        }
        break;
    }

    _cachedStatsMap[cacheKey] = count;
    return count;
  }

  void _onStatCardTapped(StudentStatCardConfig config) {
    setState(() {
      switch (config.type) {
        case 'total':
          _filterClass = null;
          _filterVillage = null;
          _filterDistrict = null;
          _filterState = null;
          _filterCategory = null;
          _filterDivision = null;
          _filterGender = null;
          _filterStatus = null;
          _filterMinAge = null;
          _filterMaxAge = null;
          _filterDepartment = null;
          _filterSubDepartment = null;
          _searchQuery = '';
          _searchController.clear();
          break;
        case 'status':
          _filterStatus = (config.filterValue ?? config.label).toLowerCase();
          break;
        case 'gender':
          _filterGender = (config.filterValue ?? config.label).toLowerCase();
          break;
        case 'category':
          _filterCategory = config.filterValue ?? config.label;
          break;
        case 'department':
          _filterDepartment = config.filterValue ?? config.label;
          break;
        default:
          break;
      }
    });
  }

  // Department & hierarchy data for filtering
  List<Map<String, dynamic>> _allDepartments = [];
  List<dynamic> _academicHierarchy = [];
  // Maps class_name → { department_name, parent_department_name }
  Map<String, Map<String, String?>> _classDeptMap = {};

  void _loadDepartmentsAndHierarchy() async {
    try {
      final deptResponse = await ApiClient().get('/academic/departments');
      final hierResponse = await ApiClient().get('/academic/hierarchy');
      if (mounted) {
        final depts = (deptResponse.data as List).cast<Map<String, dynamic>>();
        final hier = (hierResponse.data as List).cast<dynamic>();

        // Sort departments by Department Progression Series order
        try {
          final deptSeries = await DatabaseHelper().getDepartmentProgressionSeries();
          final deptOrderMap = <String, int>{};
          for (final r in deptSeries) {
            final name = r['department_name']?.toString().trim().toLowerCase();
            final ord = (r['series_order'] as num?)?.toInt() ?? 999;
            if (name != null && name.isNotEmpty) {
              deptOrderMap[name] = ord;
              final clean = name.replaceAll(RegExp(r'\(.*?\)'), '').trim();
              if (clean.isNotEmpty) deptOrderMap[clean] = ord;
            }
          }

          depts.sort((a, b) {
            // Keep main departments before sub-departments, or sort within parents
            final pA = a['parent_id'];
            final pB = b['parent_id'];
            if (pA == null && pB != null) return -1;
            if (pA != null && pB == null) return 1;

            final nameA = (a['name']?.toString().trim() ?? '').toLowerCase();
            final nameB = (b['name']?.toString().trim() ?? '').toLowerCase();
            final cleanA = nameA.replaceAll(RegExp(r'\(.*?\)'), '').trim();
            final cleanB = nameB.replaceAll(RegExp(r'\(.*?\)'), '').trim();
            final ordA = deptOrderMap[nameA] ?? deptOrderMap[cleanA] ?? 999;
            final ordB = deptOrderMap[nameB] ?? deptOrderMap[cleanB] ?? 999;
            if (ordA != ordB) return ordA.compareTo(ordB);
            return nameA.compareTo(nameB);
          });
        } catch (_) {}

        // Sort academic classes by Class Progression Series order
        try {
          final classSeries = await DatabaseHelper().getClassProgressionSeries();
          final classOrderMap = <String, int>{};
          for (final r in classSeries) {
            final cName = r['class_name']?.toString().trim().toLowerCase();
            final ord = (r['class_order'] as num?)?.toInt() ?? (r['series_order'] as num?)?.toInt() ?? 999;
            final deptOrd = (r['dept_order'] as num?)?.toInt() ?? 999;
            if (cName != null && cName.isNotEmpty) {
              classOrderMap[cName] = deptOrd * 1000 + ord;
            }
          }

          hier.sort((a, b) {
            final nameA = (a['name']?.toString().trim() ?? '').toLowerCase();
            final nameB = (b['name']?.toString().trim() ?? '').toLowerCase();
            final ordA = classOrderMap[nameA] ?? 999999;
            final ordB = classOrderMap[nameB] ?? 999999;
            if (ordA != ordB) return ordA.compareTo(ordB);
            return nameA.compareTo(nameB);
          });
        } catch (_) {}

        final mapping = <String, Map<String, String?>>{};
        for (final cls in hier) {
          final className = cls['name']?.toString();
          if (className != null && className.isNotEmpty) {
            mapping[className] = {
              'department_name': cls['department_name']?.toString(),
              'department_id': cls['department_id']?.toString(),
              'department_parent_id': cls['department_parent_id']?.toString(),
              'parent_department_name': cls['parent_department_name']?.toString(),
            };
          }
        }
        setState(() {
          _allDepartments = depts;
          _academicHierarchy = hier;
          _classDeptMap = mapping;
        });
      }
    } catch (e) {
      debugPrint('Failed to load departments for filter: $e');
    }
  }

  /// Get the display department & sub-department names for a student
  String? _getStudentAcademicDisplay(Student s) {
    String mainDept = s.departmentName ?? '';
    if (mainDept.isEmpty && s.className != null && _classDeptMap.containsKey(s.className)) {
      final info = _classDeptMap[s.className]!;
      mainDept = info['parent_department_name'] ?? info['department_name'] ?? '';
    }

    final parts = <String>[];
    if (mainDept.isNotEmpty) {
      parts.add(mainDept);
    }

    if (s.subDepartments != null && s.subDepartments!.isNotEmpty) {
      for (final sub in s.subDepartments!) {
        final subName = sub.subDepartmentName ?? '';
        final subDiv = sub.division != null && sub.division!.isNotEmpty ? ' (${sub.division})' : '';
        if (subName.isNotEmpty) {
          parts.add('$subName$subDiv');
        }
      }
    }

    return parts.isNotEmpty ? parts.join(' • ') : null;
  }

  /// Get the display department name for a student's class
  String? _getDeptDisplayForClass(String? className) {
    if (className == null || !_classDeptMap.containsKey(className)) return null;
    final info = _classDeptMap[className]!;
    final deptName = info['department_name'];
    final parentName = info['parent_department_name'];
    if (deptName == null) return null;
    if (parentName != null && parentName.isNotEmpty) {
      return '$parentName • $deptName';
    }
    return deptName;
  }

  int? _calculateStudentAgeInYears(Student s) {
    if (s.dateOfBirth != null && s.dateOfBirth!.isNotEmpty) {
      try {
        final dobDate = DateTime.parse(s.dateOfBirth!);
        final now = DateTime.now();
        int age = now.year - dobDate.year;
        if (now.month < dobDate.month || (now.month == dobDate.month && now.day < dobDate.day)) {
          age--;
        }
        return age;
      } catch (_) {}
    }
    final ageStr = s.nowAge ?? s.admissionTimeAge;
    if (ageStr != null && ageStr.isNotEmpty) {
      final match = RegExp(r'\d+').firstMatch(ageStr);
      if (match != null) {
        return int.tryParse(match.group(0)!);
      }
    }
    return null;
  }

  int get _activeFilterCount {
    int count = 0;
    if (_filterDepartment != null) count++;
    if (_filterSubDepartment != null) count++;
    if (_filterClass != null) count++;
    if (_filterVillage != null) count++;
    if (_filterDistrict != null) count++;
    if (_filterState != null) count++;
    if (_filterCategory != null) count++;
    if (_filterDivision != null) count++;
    if (_filterGender != null) count++;
    if (_filterStatus != null) count++;
    if (_filterMinAge != null && _filterMinAge!.isNotEmpty) count++;
    if (_filterMaxAge != null && _filterMaxAge!.isNotEmpty) count++;
    return count;
  }

  void _clearAllFilters() {
    setState(() {
      _filterDepartment = null;
      _filterSubDepartment = null;
      _filterClass = null;
      _filterVillage = null;
      _filterDistrict = null;
      _filterState = null;
      _filterCategory = null;
      _filterDivision = null;
      _filterGender = null;
      _filterStatus = null;
      _filterMinAge = null;
      _filterMaxAge = null;
    });
  }

  List<Student> _filterStudentList(List<Student> rawList) {
    if (rawList.isEmpty) return const [];

    final currentHash = _computeFilterHash();
    if (identical(_cachedRawStudents, rawList) && _cachedFilterHash == currentHash) {
      return _cachedFilteredStudents;
    }

    final hasNoFilters = _filterDepartment == null &&
        _filterSubDepartment == null &&
        _filterClass == null &&
        _filterVillage == null &&
        _filterDistrict == null &&
        _filterState == null &&
        _filterCategory == null &&
        _filterDivision == null &&
        _filterGender == null &&
        _filterStatus == null &&
        (_filterMinAge == null || _filterMinAge!.isEmpty) &&
        (_filterMaxAge == null || _filterMaxAge!.isEmpty);

    if (hasNoFilters) {
      _cachedRawStudents = rawList;
      _cachedFilterHash = currentHash;
      _cachedFilteredStudents = rawList;
      return rawList;
    }

    final minAge = _filterMinAge != null ? int.tryParse(_filterMinAge!) : null;
    final maxAge = _filterMaxAge != null ? int.tryParse(_filterMaxAge!) : null;

    // Pre-compute department class names for filtering
    Set<String>? deptClassNames;
    String? filterDeptName;
    String? filterSubDeptName;

    if (_filterSubDepartment != null) {
      final subDept = _allDepartments.where(
        (d) => d['id']?.toString() == _filterSubDepartment,
      ).firstOrNull;
      if (subDept != null) filterSubDeptName = subDept['name']?.toString();

      deptClassNames = <String>{};
      for (final cls in _academicHierarchy) {
        if (cls['department_id']?.toString() == _filterSubDepartment) {
          final cn = cls['name']?.toString();
          if (cn != null) deptClassNames.add(cn);
        }
      }
    } else if (_filterDepartment != null) {
      final selectedDept = _allDepartments.where(
        (d) => d['id']?.toString() == _filterDepartment,
      ).firstOrNull;
      if (selectedDept != null) {
        filterDeptName = selectedDept['name']?.toString();
        deptClassNames = <String>{};
        // Classes directly in this department
        for (final cls in _academicHierarchy) {
          if (cls['department_id']?.toString() == _filterDepartment) {
            final cn = cls['name']?.toString();
            if (cn != null) deptClassNames.add(cn);
          }
        }
        // If it's a main department, also include sub-department classes
        if (selectedDept['parent_id'] == null) {
          final subDepts = (selectedDept['sub_departments'] as List?) ??
              _allDepartments.where((d) => d['parent_id']?.toString() == _filterDepartment).toList();
          for (final sub in subDepts) {
            final subId = sub['id']?.toString();
            for (final cls in _academicHierarchy) {
              if (cls['department_id']?.toString() == subId) {
                final cn = cls['name']?.toString();
                if (cn != null) deptClassNames.add(cn);
              }
            }
          }
        }
      }
    }

    final filtered = rawList.where((s) {
      if (_filterSubDepartment != null) {
        final matchesClass = deptClassNames != null && s.className != null && deptClassNames.contains(s.className);
        final matchesSubDept = s.subDepartments != null && s.subDepartments!.any(
          (sub) => sub.subDepartmentId == _filterSubDepartment || (filterSubDeptName != null && sub.subDepartmentName == filterSubDeptName),
        );
        if (!matchesClass && !matchesSubDept) {
          return false;
        }
      } else if (_filterDepartment != null) {
        final matchesClass = deptClassNames != null && s.className != null && deptClassNames.contains(s.className);
        final matchesDirectDept = s.departmentId == _filterDepartment || (filterDeptName != null && s.departmentName == filterDeptName);
        if (!matchesClass && !matchesDirectDept) {
          return false;
        }
      }
      if (_filterClass != null && s.className != _filterClass) {
        return false;
      }
      if (_filterVillage != null && s.village != _filterVillage) {
        return false;
      }
      if (_filterDistrict != null && s.district != _filterDistrict) {
        return false;
      }
      if (_filterState != null && s.state != _filterState) {
        return false;
      }
      if (_filterCategory != null && s.category != _filterCategory) {
        return false;
      }
      if (_filterDivision != null && s.division != _filterDivision) {
        return false;
      }
      if (_filterGender != null) {
        final g = (s.gender ?? '').trim().toLowerCase();
        final fg = _filterGender!.trim().toLowerCase();
        if (g != fg) {
          final isMaleFilter = fg == 'male' || fg == 'ladka' || fg == 'boy' || fg == 'boys' || fg == 'm';
          final isMaleStudent = g == 'male' || g == 'ladka' || g == 'boy' || g == 'boys' || g == 'm';
          final isFemaleFilter = fg == 'female' || fg == 'ladki' || fg == 'girl' || fg == 'girls' || fg == 'f';
          final isFemaleStudent = g == 'female' || g == 'ladki' || g == 'girl' || g == 'girls' || g == 'f';
          if (!((isMaleFilter && isMaleStudent) || (isFemaleFilter && isFemaleStudent))) {
            return false;
          }
        }
      }
      if (_filterStatus != null) {
        final st = (s.studentStatus ?? (s.isActive ? 'active' : 'inactive')).trim().toLowerCase();
        final fs = _filterStatus!.trim().toLowerCase();
        if (st != fs) {
          final isActiveFilter = fs == 'active' || fs == 'chalu' || fs == 'regular';
          final isActiveStudent = st == 'active' || st == 'chalu' || st == 'regular' || s.isActive;
          final isInactiveFilter = fs == 'inactive' || fs == 'kharij' || fs == 'left';
          final isInactiveStudent = st == 'inactive' || st == 'kharij' || st == 'left' || !s.isActive;
          if (!((isActiveFilter && isActiveStudent) || (isInactiveFilter && isInactiveStudent))) {
            return false;
          }
        }
      }
      if (minAge != null || maxAge != null) {
        final age = _calculateStudentAgeInYears(s);
        if (age == null) return false;
        if (minAge != null && age < minAge) return false;
        if (maxAge != null && age > maxAge) return false;
      }
      return true;
    }).toList();

    _cachedRawStudents = rawList;
    _cachedFilterHash = currentHash;
    _cachedFilteredStudents = filtered;
    return filtered;
  }

  bool _isSelectionMode = false;
  List<String> _selectedStudentIds = [];

  void _toggleSelection(String studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedStudentIds.clear();
      }
    });
  }

  void _showBulkAssignCategoryDialog() async {
    if (!_ensureFeatureAccess('students_edit', 'Bulk Assign Category')) return;
    if (_selectedStudentIds.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiClient().get('/academic/books');
      final books = response.data as List;
      final categories = books
          .map((b) => b['category']?.toString())
          .where((c) => c != null && c.isNotEmpty)
          .toSet()
          .toList()
          .cast<String>();

      if (context.mounted) Navigator.pop(context); // pop loading

      String? selectedCategory;
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dContext) => StatefulBuilder(
            builder: (context, setModalState) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final width = MediaQuery.of(context).size.width;
              final scale = (width / 375.0).clamp(0.75, 1.0);
              return MovableResizableDialog(
                initialWidth: 500,
                initialHeight: 320,
                minWidth: 380,
                minHeight: 250,
                headerLeading: Container(
                  padding: EdgeInsets.all(6 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.category_rounded, color: Colors.white, size: 18 * scale),
                ),
                title: Text(
                  'Assign Category (${_selectedStudentIds.length})',
                  style: AppTheme.getFontStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                content: Padding(
                  padding: EdgeInsets.all(20 * scale),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (categories.isEmpty)
                        Text(
                          'No categories found. Create a book with a category first.',
                          style: AppTheme.getFontStyle(fontSize: 13 * scale),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          style: AppTheme.getFontStyle(
                            fontSize: 13 * scale,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          ),
                          dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                          decoration: InputDecoration(
                            labelText: context.tr('select_category'),
                            labelStyle: TextStyle(
                              fontSize: 12 * scale,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                          items: categories
                              .map(
                                (cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(
                                    cat,
                                    style: TextStyle(
                                      fontSize: 13 * scale,
                                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) => setModalState(() => selectedCategory = val),
                        ),
                    ],
                  ),
                ),
                actions: Padding(
                  padding: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 16 * scale),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dContext),
                        child: Text(context.tr('cancel'), style: TextStyle(fontSize: 13 * scale)),
                      ),
                      SizedBox(width: 8 * scale),
                      if (categories.isNotEmpty)
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0D6B4E),
                            padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                          ),
                          onPressed: () {
                            if (selectedCategory == null) return;
                            Navigator.pop(dContext);
                            this.context.read<StudentsBloc>().add(
                              BulkAssignCategory(
                                List.from(_selectedStudentIds),
                                selectedCategory!,
                              ),
                            );
                            setState(() {
                              _isSelectionMode = false;
                              _selectedStudentIds.clear();
                            });
                          },
                          child: Text(context.tr('assign'), style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load categories: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    StudentStatusSettings.getStatusColors();
    context.read<StudentsBloc>().add(LoadStudents());
    _loadDepartmentsAndHierarchy();
    _loadStatCardConfigs();
    DatabaseHelper().checkAndTriggerAutoPromotionIfNeeded();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = query);
      context.read<StudentsBloc>().add(SearchStudents(query));
    });
  }

  void _showAddEditDialog([Student? student]) {
    if (student == null) {
      if (!_ensureFeatureAccess('students_admission', 'New Admission Form')) return;
    } else {
      if (!_ensureFeatureAccess('students_edit', 'Edit Student Details')) return;
    }

    final formDialog = StudentFormDialog(
      student: student,
      initialDepartments: _allDepartments,
      initialHierarchy: _academicHierarchy,
    );

    if (MediaQuery.of(context).size.width < 700) {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 140),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          pageBuilder: (_, animation, secondaryAnimation) => BlocProvider.value(
            value: context.read<StudentsBloc>(),
            child: formDialog,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutQuad),
              child: child,
            );
          },
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => BlocProvider.value(
          value: context.read<StudentsBloc>(),
          child: formDialog,
        ),
      );
    }
  }

  void _showAssignRollNumberDialog(List<Student> allStudents, {List<String>? selectedIds}) async {
    if (!_ensureFeatureAccess('students_edit', 'Assign Roll Numbers & Division')) return;

    final hasSelection = selectedIds != null && selectedIds.isNotEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    List<String> divisionsList = [];
    try {
      final divs = <String>{};

      // 1. Fetch divisions/courses created in Division tab
      try {
        final response = await ApiClient().get('/academic/courses');
        final courses = response.data as List;
        for (final c in courses) {
          final name = c['name']?.toString();
          if (name != null && name.trim().isNotEmpty) {
            divs.add(name.trim());
          }
        }
      } catch (e) {
        debugPrint('Failed to load courses for division dropdown: $e');
      }

      // 2. Fetch hierarchy assigned courses/divisions
      try {
        final response = await ApiClient().get('/academic/hierarchy');
        final hierarchy = response.data as List;
        for (final cls in hierarchy) {
          final courses = cls['courses'] as List? ?? [];
          for (final course in courses) {
            final name = course['name']?.toString();
            if (name != null && name.trim().isNotEmpty) {
              divs.add(name.trim());
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to load hierarchy for division dropdown: $e');
      }

      // 3. Include any existing student divisions
      for (final s in allStudents) {
        if (s.division != null && s.division!.trim().isNotEmpty) {
          divs.add(s.division!.trim());
        }
        if (s.subDepartments != null) {
          for (final sub in s.subDepartments!) {
            if (sub.division != null && sub.division!.trim().isNotEmpty) {
              divs.add(sub.division!.trim());
            }
          }
        }
      }

      divisionsList = divs.toList()..sort();
    } catch (e) {
      debugPrint('Error fetching divisions: $e');
    }

    if (context.mounted) Navigator.pop(context); // pop loading

    // Fallback if no divisions found in system
    if (divisionsList.isEmpty) {
      divisionsList = ['A', 'B', 'C', 'D', 'A-1', 'A-2', 'B-1', 'B-2'];
    }
    divisionsList.add('Custom...');

    final classNames = allStudents
        .map((s) => s.className ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final categories = allStudents
        .map((s) => s.category ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    String? selectedDeptId;
    String? selectedSubDeptId;
    String? selectedClass = classNames.isNotEmpty ? classNames.first : null;
    String selectedCategory = 'ALL';

    // Helper: get divisions for a specific class
    List<String> getClassDivisions(String? clsName) {
      if (clsName == null) return ['Custom...'];
      final clsNode = _academicHierarchy.where(
        (c) => c['name']?.toString() == clsName,
      ).firstOrNull;
      final divs = <String>{};
      if (clsNode != null && clsNode['courses'] is List) {
        for (final c in (clsNode['courses'] as List)) {
          final n = c['name']?.toString();
          if (n != null && n.trim().isNotEmpty) divs.add(n.trim());
        }
      }
      for (final s in allStudents) {
        if (s.className == clsName && s.division != null && s.division!.trim().isNotEmpty) {
          divs.add(s.division!.trim());
        }
        if (s.subDepartments != null) {
          for (final sub in s.subDepartments!) {
            if (sub.className == clsName && sub.division != null && sub.division!.trim().isNotEmpty) {
              divs.add(sub.division!.trim());
            }
          }
        }
      }
      final sorted = divs.toList()..sort();
      return [...sorted, 'Custom...'];
    }

    // Helper: get available classes for dept / subdept
    List<String> getAvailableClasses(String? deptId, String? subDeptId) {
      if (subDeptId != null) {
        return _academicHierarchy
            .where((cls) => cls['department_id']?.toString() == subDeptId)
            .map((cls) => cls['name']?.toString())
            .where((n) => n != null && n.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList()..sort();
      }
      if (deptId != null) {
        final subDepts = _allDepartments.where((d) => d['parent_id']?.toString() == deptId).toList();
        final subIds = subDepts.map((s) => s['id']?.toString()).toSet();
        return _academicHierarchy
            .where((cls) {
              final dId = cls['department_id']?.toString();
              return dId == deptId || subIds.contains(dId);
            })
            .map((cls) => cls['name']?.toString())
            .where((n) => n != null && n.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList()..sort();
      }
      return classNames;
    }

    List<String> currentDivisions = getClassDivisions(selectedClass);
    String? selectedDivision = currentDivisions.first == 'Custom...' ? null : currentDivisions.first;
    final divisionCtrl = TextEditingController(text: selectedDivision ?? '');
    bool showCustomDivision = false;

    final Map<String, TextEditingController> controllers = {};
    final Map<String, FocusNode> focusNodes = {};
    final studentsBloc = context.read<StudentsBloc>();
    final Set<String> selectedStudentIdsInDialog = {};
    if (selectedIds != null && selectedIds.isNotEmpty) {
      selectedStudentIdsInDialog.addAll(selectedIds);
    }
    String dialogSearchQuery = '';

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider.value(
        value: studentsBloc,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final scale = (screenWidth / 380.0).clamp(0.70, 1.0);

            // Sub-departments for selected main dept
            List<Map<String, dynamic>> availableSubDepts = [];
            String? selectedDeptName;
            String? selectedSubDeptName;

            if (selectedDeptId != null) {
              final mainDept = _allDepartments.where(
                (d) => d['id']?.toString() == selectedDeptId,
              ).firstOrNull;
              if (mainDept != null) {
                selectedDeptName = mainDept['name']?.toString();
                availableSubDepts = ((mainDept['sub_departments'] as List?) ??
                        _allDepartments.where((d) => d['parent_id']?.toString() == selectedDeptId).toList())
                    .cast<Map<String, dynamic>>();
              }
            }

            if (selectedSubDeptId != null) {
              final subDept = availableSubDepts.where(
                (s) => s['id']?.toString() == selectedSubDeptId,
              ).firstOrNull;
              if (subDept != null) {
                selectedSubDeptName = subDept['name']?.toString();
              }
            }

            final availableClasses = getAvailableClasses(selectedDeptId, selectedSubDeptId);

            // Filter students
            final classFilteredStudents = hasSelection
                ? allStudents.where((s) => selectedIds.contains(s.id)).toList()
                : allStudents.where((s) {
                    final categoryMatch = selectedCategory == 'ALL' || s.category == selectedCategory;
                    if (!categoryMatch) return false;

                    if (selectedSubDeptId != null) {
                      final hasSub = s.subDepartments != null && s.subDepartments!.any(
                        (sub) => sub.subDepartmentId == selectedSubDeptId || (selectedSubDeptName != null && sub.subDepartmentName == selectedSubDeptName),
                      );
                      if (!hasSub) return false;
                      if (selectedClass != null) {
                        final matchingSub = s.subDepartments?.where(
                          (sub) => sub.subDepartmentId == selectedSubDeptId || (selectedSubDeptName != null && sub.subDepartmentName == selectedSubDeptName),
                        ).firstOrNull;
                        final subCls = matchingSub?.className ?? s.className;
                        return subCls == selectedClass;
                      }
                      return true;
                    } else if (selectedDeptId != null) {
                      final matchesDept = s.departmentId == selectedDeptId || (selectedDeptName != null && s.departmentName == selectedDeptName);
                      if (selectedClass != null) {
                        return (matchesDept || availableClasses.contains(s.className)) && s.className == selectedClass;
                      }
                      return matchesDept || (s.className != null && availableClasses.contains(s.className));
                    } else {
                      return selectedClass == null || s.className == selectedClass;
                    }
                  }).toList();

            final filteredStudents = dialogSearchQuery.trim().isEmpty
                ? classFilteredStudents
                : classFilteredStudents.where((s) {
                    final q = dialogSearchQuery.trim().toLowerCase();
                    final name = _displayName(s).toLowerCase();
                    final gr = (s.grNo ?? s.registrationNumber).toLowerCase();
                    final roll = (s.rollNumber ?? '').toLowerCase();
                    return name.contains(q) || gr.contains(q) || roll.contains(q);
                  }).toList();

            // Populate / sync controllers with correct roll numbers (Sub-Dept vs Main Dept)
            for (final s in classFilteredStudents) {
              String currentRoll = '';
              if (selectedSubDeptId != null) {
                final sub = s.subDepartments?.where(
                  (sub) => sub.subDepartmentId == selectedSubDeptId || (selectedSubDeptName != null && sub.subDepartmentName == selectedSubDeptName),
                ).firstOrNull;
                currentRoll = sub?.rollNumber ?? '';
              } else {
                currentRoll = s.rollNumber ?? '';
              }

              if (currentRoll.isNotEmpty &&
                  (RegExp(r'^\d{4}[-\/\.]\d{1,2}[-\/\.]\d{1,2}').hasMatch(currentRoll.trim()) ||
                   RegExp(r'^\d{1,2}[-\/\.]\d{1,2}[-\/\.]\d{2,4}').hasMatch(currentRoll.trim()))) {
                currentRoll = '';
              }

              if (!controllers.containsKey(s.id)) {
                controllers[s.id] = TextEditingController(text: currentRoll);
              }
            }

            filteredStudents.sort((a, b) {
              final rAStr = controllers[a.id]?.text.trim() ?? '';
              final rBStr = controllers[b.id]?.text.trim() ?? '';
              final rA = int.tryParse(rAStr);
              final rB = int.tryParse(rBStr);
              if (rA != null && rB != null) return rA.compareTo(rB);
              if (rA != null) return -1;
              if (rB != null) return 1;
              return a.fullName.compareTo(b.fullName);
            });

            final isAllFilteredSelected = filteredStudents.isNotEmpty &&
                filteredStudents.every((s) => selectedStudentIdsInDialog.contains(s.id));

            return MovableResizableDialog(
              initialWidth: (screenWidth * 0.96).clamp(380.0, 780.0),
              initialHeight: (screenHeight * 0.88).clamp(380.0, 740.0),
              minWidth: 380,
              minHeight: 320,
              headerLeading: Container(
                padding: EdgeInsets.all(6 * scale),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.format_list_numbered_rounded, color: Colors.white, size: 18 * scale),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedSubDeptId != null
                        ? 'Assign Roll No & Div ($selectedSubDeptName)'
                        : 'Assign Roll Numbers & Division',
                    style: AppTheme.getFontStyle(
                      fontSize: 14.5 * scale,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    '${selectedStudentIdsInDialog.length} of ${classFilteredStudents.length} students selected',
                    style: AppTheme.getFontStyle(
                      fontSize: 10.5 * scale,
                      color: Colors.white.withAlpha(200),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              content: Padding(
                padding: EdgeInsets.symmetric(horizontal: (screenWidth < 600 ? 8 : 14) * scale, vertical: 8 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasSelection) ...[
                      // Filter bar with responsive layout
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final availableW = constraints.maxWidth;
                          final isNarrow = availableW < 520;
                          final dropWidth = isNarrow ? (availableW - 8 * scale) / 2 : (availableW - 24 * scale) / 4;

                          return Wrap(
                            spacing: 8 * scale,
                            runSpacing: 6 * scale,
                            children: [
                              // Department Dropdown
                              SizedBox(
                                width: dropWidth,
                                child: DropdownButtonFormField<String?>(
                                  isExpanded: true,
                                  initialValue: selectedDeptId,
                                  dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11 * scale,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: context.tr('department'),
                                    labelStyle: TextStyle(fontSize: 10 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                    prefixIcon: Icon(Icons.business_center_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(value: null, child: Text('All Depts', overflow: TextOverflow.ellipsis)),
                                    ..._allDepartments.where((d) => d['parent_id'] == null).map((d) => DropdownMenuItem<String?>(
                                          value: d['id'].toString(),
                                          child: Text(d['name'] ?? '', overflow: TextOverflow.ellipsis),
                                        )),
                                  ],
                                  onChanged: (val) {
                                    setDialogState(() {
                                      selectedDeptId = val;
                                      selectedSubDeptId = null;
                                      controllers.clear();
                                      final newClasses = getAvailableClasses(val, null);
                                      if (selectedClass != null && !newClasses.contains(selectedClass)) {
                                        selectedClass = newClasses.isNotEmpty ? newClasses.first : null;
                                      }
                                      currentDivisions = getClassDivisions(selectedClass);
                                      selectedDivision = currentDivisions.first == 'Custom...' ? null : currentDivisions.first;
                                      divisionCtrl.text = selectedDivision ?? '';
                                      selectedStudentIdsInDialog.clear();
                                    });
                                  },
                                ),
                              ),

                              // Sub-Department Dropdown
                              if (availableSubDepts.isNotEmpty)
                                SizedBox(
                                  width: dropWidth,
                                  child: DropdownButtonFormField<String?>(
                                    isExpanded: true,
                                    key: ValueKey('assign_subdept_${selectedDeptId ?? 'none'}'),
                                    initialValue: selectedSubDeptId,
                                    dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                    style: AppTheme.getFontStyle(
                                      fontSize: 11 * scale,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: context.tr('sub_department'),
                                      labelStyle: TextStyle(fontSize: 10 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                      prefixIcon: Icon(Icons.subdirectory_arrow_right_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                      isDense: true,
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(value: null, child: Text('Main Dept Only', overflow: TextOverflow.ellipsis)),
                                      ...availableSubDepts.map((s) => DropdownMenuItem<String?>(
                                            value: s['id'].toString(),
                                            child: Text(s['name'] ?? '', overflow: TextOverflow.ellipsis),
                                          )),
                                    ],
                                    onChanged: (val) {
                                      setDialogState(() {
                                        selectedSubDeptId = val;
                                        controllers.clear();
                                        final newClasses = getAvailableClasses(selectedDeptId, val);
                                        if (selectedClass != null && !newClasses.contains(selectedClass)) {
                                          selectedClass = newClasses.isNotEmpty ? newClasses.first : null;
                                        }
                                        currentDivisions = getClassDivisions(selectedClass);
                                        selectedDivision = currentDivisions.first == 'Custom...' ? null : currentDivisions.first;
                                        divisionCtrl.text = selectedDivision ?? '';
                                        selectedStudentIdsInDialog.clear();
                                      });
                                    },
                                  ),
                                ),

                              // Class Dropdown
                              SizedBox(
                                width: dropWidth,
                                child: DropdownButtonFormField<String?>(
                                  isExpanded: true,
                                  key: ValueKey('assign_class_${selectedDeptId ?? 'all'}_${selectedSubDeptId ?? 'all'}'),
                                  initialValue: availableClasses.contains(selectedClass) ? selectedClass : null,
                                  dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11 * scale,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Class *',
                                    labelStyle: TextStyle(fontSize: 10 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                    prefixIcon: Icon(Icons.class_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(value: null, child: Text('All Classes', overflow: TextOverflow.ellipsis)),
                                    ...availableClasses.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
                                  ],
                                  onChanged: (val) {
                                    setDialogState(() {
                                      selectedClass = val;
                                      currentDivisions = getClassDivisions(val);
                                      selectedDivision = currentDivisions.first == 'Custom...' ? null : currentDivisions.first;
                                      divisionCtrl.text = selectedDivision ?? '';
                                      selectedStudentIdsInDialog.clear();
                                    });
                                  },
                                ),
                              ),

                              // Category Dropdown
                              SizedBox(
                                width: dropWidth,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: selectedCategory,
                                  dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11 * scale,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Category',
                                    labelStyle: TextStyle(fontSize: 10 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                    prefixIcon: Icon(Icons.category_rounded, size: 14 * scale, color: AppTheme.primaryColor),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: 'ALL', child: Text('All Cats', overflow: TextOverflow.ellipsis)),
                                    ...categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat, overflow: TextOverflow.ellipsis))),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDialogState(() {
                                        selectedCategory = val;
                                        selectedStudentIdsInDialog.clear();
                                      });
                                    }
                                  },
                                ),
                              ),

                              // Search TextField
                              SizedBox(
                                width: isNarrow ? availableW : dropWidth,
                                child: TextField(
                                  style: AppTheme.getFontStyle(fontSize: 11 * scale),
                                  decoration: InputDecoration(
                                    hintText: 'Search student...',
                                    hintStyle: TextStyle(fontSize: 10 * scale, color: Colors.grey),
                                    prefixIcon: Icon(Icons.search_rounded, size: 14 * scale, color: Colors.grey),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                                  ),
                                  onChanged: (val) {
                                    setDialogState(() => dialogSearchQuery = val);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: 6 * scale),
                    ],

                    // Division Assignment Header Box
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withAlpha(18),
                        borderRadius: BorderRadius.circular(8 * scale),
                        border: Border.all(color: const Color(0xFF1565C0).withAlpha(60)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.grid_view_rounded, size: 14 * scale, color: const Color(0xFF1565C0)),
                              SizedBox(width: 6 * scale),
                              Expanded(
                                child: Text(
                                  selectedSubDeptId != null
                                      ? 'Assign Division for [$selectedSubDeptName] (${selectedStudentIdsInDialog.length}):'
                                      : 'Assign Division to Selected (${selectedStudentIdsInDialog.length}):',
                                  style: AppTheme.getFontStyle(fontSize: 10.5 * scale, fontWeight: FontWeight.bold, color: const Color(0xFF1565C0)),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6 * scale),
                          LayoutBuilder(
                            builder: (context, divConstraints) {
                              final isSmall = divConstraints.maxWidth < 380;
                              if (showCustomDivision && isSmall) {
                                return Column(
                                  children: [
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      key: ValueKey('assign_div_${selectedClass ?? 'none'}_${selectedSubDeptId ?? 'main'}_${currentDivisions.length}'),
                                      initialValue: currentDivisions.contains(selectedDivision) ? selectedDivision : (currentDivisions.isNotEmpty ? currentDivisions.first : null),
                                      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 11 * scale,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Select Division (A, B, C, الف, ب)...',
                                        hintStyle: TextStyle(fontSize: 10 * scale, color: Colors.grey),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6 * scale)),
                                      ),
                                      items: currentDivisions
                                          .map((div) => DropdownMenuItem(
                                                value: div,
                                                child: Text(div, style: TextStyle(fontSize: 11 * scale), overflow: TextOverflow.ellipsis),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        setDialogState(() {
                                          selectedDivision = val;
                                          if (val == 'Custom...') {
                                            showCustomDivision = true;
                                            divisionCtrl.clear();
                                          } else {
                                            showCustomDivision = false;
                                            if (val != null) divisionCtrl.text = val;
                                          }
                                        });
                                      },
                                    ),
                                    SizedBox(height: 6 * scale),
                                    TextField(
                                      controller: divisionCtrl,
                                      style: AppTheme.getFontStyle(fontSize: 11 * scale),
                                      decoration: InputDecoration(
                                        hintText: 'Custom (e.g. A-1)',
                                        hintStyle: TextStyle(fontSize: 10 * scale, color: Colors.grey),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6 * scale)),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      key: ValueKey('assign_div_${selectedClass ?? 'none'}_${selectedSubDeptId ?? 'main'}_${currentDivisions.length}'),
                                      initialValue: currentDivisions.contains(selectedDivision) ? selectedDivision : (currentDivisions.isNotEmpty ? currentDivisions.first : null),
                                      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 11 * scale,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Select Division (A, B, C, الف, ب)...',
                                        hintStyle: TextStyle(fontSize: 10 * scale, color: Colors.grey),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6 * scale)),
                                      ),
                                      items: currentDivisions
                                          .map((div) => DropdownMenuItem(
                                                value: div,
                                                child: Text(div, style: TextStyle(fontSize: 11 * scale), overflow: TextOverflow.ellipsis),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        setDialogState(() {
                                          selectedDivision = val;
                                          if (val == 'Custom...') {
                                            showCustomDivision = true;
                                            divisionCtrl.clear();
                                          } else {
                                            showCustomDivision = false;
                                            if (val != null) divisionCtrl.text = val;
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  if (showCustomDivision) ...[
                                    SizedBox(width: 6 * scale),
                                    Expanded(
                                      child: TextField(
                                        controller: divisionCtrl,
                                        style: AppTheme.getFontStyle(fontSize: 11 * scale),
                                        decoration: InputDecoration(
                                          hintText: 'Custom (e.g. A-1)',
                                          hintStyle: TextStyle(fontSize: 10 * scale, color: Colors.grey),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 4 * scale),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6 * scale)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 6 * scale),

                    // Selection & Roll Number Controls Bar (Responsive Wrap so NO horizontal overflow)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6 * scale,
                      runSpacing: 4 * scale,
                      children: [
                        InkWell(
                          onTap: filteredStudents.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    if (isAllFilteredSelected) {
                                      for (final s in filteredStudents) {
                                        selectedStudentIdsInDialog.remove(s.id);
                                      }
                                    } else {
                                      selectedStudentIdsInDialog.addAll(filteredStudents.map((s) => s.id));
                                    }
                                  });
                                },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22 * scale,
                                height: 22 * scale,
                                child: Checkbox(
                                  value: isAllFilteredSelected,
                                  tristate: selectedStudentIdsInDialog.isNotEmpty && !isAllFilteredSelected,
                                  onChanged: filteredStudents.isEmpty
                                      ? null
                                      : (val) {
                                          setDialogState(() {
                                            if (val == true) {
                                              selectedStudentIdsInDialog.addAll(filteredStudents.map((s) => s.id));
                                            } else {
                                              for (final s in filteredStudents) {
                                                selectedStudentIdsInDialog.remove(s.id);
                                              }
                                            }
                                          });
                                        },
                                ),
                              ),
                              SizedBox(width: 4 * scale),
                              Text(
                                'Select All (${selectedStudentIdsInDialog.length}/${filteredStudents.length})',
                                style: AppTheme.getFontStyle(
                                  fontSize: 10.5 * scale,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 6 * scale,
                          runSpacing: 4 * scale,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: selectedStudentIdsInDialog.isEmpty
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        final selectedList = filteredStudents
                                            .where((s) => selectedStudentIdsInDialog.contains(s.id))
                                            .toList();
                                        for (int i = 0; i < selectedList.length; i++) {
                                          final id = selectedList[i].id;
                                          controllers[id]?.text = (i + 1).toString();
                                        }
                                      });
                                    },
                              icon: Icon(Icons.auto_awesome_rounded, size: 12 * scale),
                              label: Text(
                                'Auto Serial (1,2,3...)',
                                style: AppTheme.getFontStyle(fontSize: 10 * scale, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primaryColor,
                                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: selectedStudentIdsInDialog.isEmpty
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        for (final id in selectedStudentIdsInDialog) {
                                          controllers[id]?.clear();
                                        }
                                      });
                                    },
                              icon: Icon(Icons.clear_all_rounded, size: 13 * scale, color: Colors.red),
                              label: Text(
                                'Clear',
                                style: AppTheme.getFontStyle(fontSize: 10 * scale, color: Colors.red),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 3 * scale),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 4 * scale),
                    Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                    SizedBox(height: 4 * scale),

                    // Student items list
                    Expanded(
                      child: filteredStudents.isEmpty
                          ? Center(
                              child: Text(
                                selectedClass == null
                                    ? 'Please select a Class'
                                    : 'No students found matching selection / search',
                                style: AppTheme.getFontStyle(
                                  fontSize: 12 * scale,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredStudents.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                thickness: 1,
                                color: isDark ? Colors.white10 : Colors.grey.shade200,
                              ),
                              itemBuilder: (context, idx) {
                                final s = filteredStudents[idx];
                                final isSelected = selectedStudentIdsInDialog.contains(s.id);
                                final ctrl = controllers[s.id] ?? TextEditingController();
                                final isLast = idx == filteredStudents.length - 1;
                                final fNode = focusNodes.putIfAbsent(s.id, () => FocusNode());

                                String studentSubtitle = '';
                                if (selectedSubDeptId != null) {
                                  final sub = s.subDepartments?.where(
                                    (sub) => sub.subDepartmentId == selectedSubDeptId || (selectedSubDeptName != null && sub.subDepartmentName == selectedSubDeptName),
                                  ).firstOrNull;
                                  studentSubtitle = 'GR: ${s.grNo ?? s.registrationNumber} • Sub-Dept: $selectedSubDeptName • Class: ${sub?.className ?? s.className ?? "N/A"}${sub?.division != null && sub!.division!.isNotEmpty ? " (Div: ${sub.division})" : ""}';
                                } else {
                                  final deptStr = s.departmentName ?? _getDeptDisplayForClass(s.className) ?? '';
                                  final deptPart = deptStr.isNotEmpty ? ' • Dept: $deptStr' : '';
                                  studentSubtitle = 'GR: ${s.grNo ?? s.registrationNumber}$deptPart • Class: ${s.className ?? "N/A"}${s.division != null && s.division!.isNotEmpty ? " (Div: ${s.division})" : ""}';
                                }

                                return InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isSelected) {
                                        selectedStudentIdsInDialog.remove(s.id);
                                      } else {
                                        selectedStudentIdsInDialog.add(s.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    color: isSelected
                                        ? AppTheme.primaryColor.withAlpha(isDark ? 30 : 15)
                                        : Colors.transparent,
                                    padding: EdgeInsets.symmetric(vertical: 3 * scale, horizontal: 2 * scale),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24 * scale,
                                          height: 24 * scale,
                                          child: Focus(
                                            skipTraversal: true,
                                            child: Checkbox(
                                              value: isSelected,
                                              onChanged: (val) {
                                                setDialogState(() {
                                                  if (val == true) {
                                                    selectedStudentIdsInDialog.add(s.id);
                                                  } else {
                                                    selectedStudentIdsInDialog.remove(s.id);
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 18 * scale,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${idx + 1}',
                                            style: AppTheme.getFontStyle(
                                              fontSize: 10 * scale,
                                              color: Colors.grey.shade500,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 4 * scale),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _displayName(s),
                                                style: AppTheme.getFontStyle(
                                                  fontSize: 11.5 * scale,
                                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                                  color: isDark ? Colors.white : Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                              SizedBox(height: 1 * scale),
                                              Text(
                                                studentSubtitle,
                                                style: AppTheme.getFontStyle(
                                                  fontSize: 9.5 * scale,
                                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 4 * scale),
                                        SizedBox(
                                          width: (66 * scale).clamp(50.0, 78.0),
                                          child: TextField(
                                            controller: ctrl,
                                            focusNode: fNode,
                                            textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
                                            onSubmitted: (_) {
                                              if (!isLast) {
                                                final nextStudent = filteredStudents[idx + 1];
                                                focusNodes.putIfAbsent(nextStudent.id, () => FocusNode()).requestFocus();
                                              }
                                            },
                                            keyboardType: TextInputType.text,
                                            style: AppTheme.getFontStyle(
                                              fontSize: 11 * scale,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                            textAlign: TextAlign.center,
                                            decoration: InputDecoration(
                                              hintText: selectedSubDeptId != null ? 'Sub Roll' : 'Roll No',
                                              hintStyle: AppTheme.getFontStyle(
                                                fontSize: 9.5 * scale,
                                                color: isDark ? Colors.white30 : Colors.grey.shade400,
                                              ),
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 4 * scale),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6 * scale)),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(6 * scale),
                                                borderSide: BorderSide(
                                                  color: isSelected
                                                      ? AppTheme.primaryColor
                                                      : (isDark ? Colors.white24 : Colors.grey.shade400),
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(6 * scale),
                                                borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: Container(
                padding: EdgeInsets.fromLTRB(14 * scale, 6 * scale, 14 * scale, 12 * scale),
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
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(
                        context.tr('cancel'),
                        style: AppTheme.getFontStyle(fontSize: 12 * scale, color: isDark ? Colors.white70 : Colors.grey.shade700),
                      ),
                    ),
                    SizedBox(width: 8 * scale),
                    FilledButton.icon(
                      icon: Icon(Icons.check_circle_outline_rounded, size: 15 * scale),
                      label: Text(
                        selectedStudentIdsInDialog.isEmpty
                            ? 'Apply & Save'
                            : 'Apply & Save (${selectedStudentIdsInDialog.length})',
                        style: AppTheme.getFontStyle(fontSize: 12 * scale),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0D6B4E),
                        padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                      ),
                      onPressed: selectedStudentIdsInDialog.isEmpty
                          ? null
                          : () async {
                              final repo = StudentRepository(ApiClient());
                              final targetIds = selectedStudentIdsInDialog.toList();

                              // 1. Assign Division if provided
                              final divVal = divisionCtrl.text.trim().isNotEmpty
                                  ? divisionCtrl.text.trim()
                                  : (selectedDivision == 'Custom...' ? '' : (selectedDivision ?? ''));

                              if (divVal.isNotEmpty) {
                                try {
                                  await repo.bulkAssignDivision(
                                    targetIds,
                                    divVal,
                                    subDepartmentId: selectedSubDeptId,
                                    subDepartmentName: selectedSubDeptName,
                                  );
                                } catch (e) {
                                  debugPrint('Failed bulk assign division: $e');
                                }
                              }

                              // 2. Assign Roll Numbers for selected students
                              final rollData = <Map<String, String>>[];
                              for (final id in targetIds) {
                                final text = controllers[id]?.text.trim() ?? '';
                                rollData.add({
                                  'studentId': id,
                                  'rollNumber': text,
                                });
                              }

                              try {
                                await repo.bulkAssignRollNumbers(
                                  rollData,
                                  subDepartmentId: selectedSubDeptId,
                                  subDepartmentName: selectedSubDeptName,
                                );
                                if (!mounted) return;
                                Navigator.pop(dialogContext);
                                final scopeLabel = selectedSubDeptName != null ? ' for $selectedSubDeptName' : '';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      divVal.isNotEmpty
                                          ? 'Division "$divVal" and Roll Numbers applied$scopeLabel to ${targetIds.length} selected students!'
                                          : 'Roll Numbers applied$scopeLabel to ${targetIds.length} selected students!',
                                    ),
                                    backgroundColor: const Color(0xFF0D6B4E),
                                  ),
                                );
                                setState(() {
                                  _isSelectionMode = false;
                                  _selectedStudentIds.clear();
                                });
                                studentsBloc.add(LoadStudents());
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error saving roll numbers: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showPrintIdCardDialog(List<Student> allStudents) {
    // Extract unique class names
    final classNames = allStudents
        .map((s) => s.className ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    String? selectedDeptId;
    String? selectedSubDeptId;
    String? selectedClass;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final scale = (screenWidth / 380.0).clamp(0.70, 1.0);

          // Get available sub-departments
          List<Map<String, dynamic>> availableSubDepts = [];
          if (selectedDeptId != null) {
            final mainDept = _allDepartments.where(
              (d) => d['id']?.toString() == selectedDeptId,
            ).firstOrNull;
            if (mainDept != null) {
              availableSubDepts = ((mainDept['sub_departments'] as List?) ??
                      _allDepartments.where((d) => d['parent_id']?.toString() == selectedDeptId).toList())
                  .cast<Map<String, dynamic>>();
            }
          }

          // Filter available classes
          List<String> availableClasses = [];
          if (selectedSubDeptId != null) {
            availableClasses = _academicHierarchy
                .where((cls) => cls['department_id']?.toString() == selectedSubDeptId)
                .map((cls) => cls['name']?.toString())
                .where((n) => n != null && n.isNotEmpty)
                .cast<String>()
                .toSet()
                .toList()..sort();
          } else if (selectedDeptId != null) {
            final subIds = availableSubDepts.map((s) => s['id']?.toString()).where((id) => id != null).toSet();
            availableClasses = _academicHierarchy
                .where((cls) {
                  final dId = cls['department_id']?.toString();
                  return dId == selectedDeptId || subIds.contains(dId);
                })
                .map((cls) => cls['name']?.toString())
                .where((n) => n != null && n.isNotEmpty)
                .cast<String>()
                .toSet()
                .toList()..sort();
          } else {
            availableClasses = classNames;
          }

          final filteredCount = selectedClass != null
              ? allStudents.where((s) => s.className == selectedClass).length
              : 0;

          return MovableResizableDialog(
            initialWidth: 500,
            initialHeight: 460,
            minWidth: 360,
            minHeight: 300,
            headerLeading: Container(
              padding: EdgeInsets.all(6 * scale),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.badge_rounded, color: Colors.white, size: (20 * scale).clamp(16.0, 24.0)),
            ),
            title: Text(
              context.tr('print_student_id_cards_title'),
              style: AppTheme.getFontStyle(
                fontSize: (16 * scale).clamp(12.0, 18.0),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            content: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('print_student_id_cards_subtitle'),
                      style: AppTheme.getFontStyle(
                        fontSize: (11.5 * scale).clamp(9.0, 13.0),
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 12 * scale),

                    // Department Dropdown
                    DropdownButtonFormField<String?>(
                      initialValue: selectedDeptId,
                      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                      style: AppTheme.getFontStyle(
                        fontSize: (12.5 * scale).clamp(10.0, 14.0),
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        labelText: context.tr('department'),
                        labelStyle: TextStyle(
                          fontSize: (11 * scale).clamp(9.0, 13.0),
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                        prefixIcon: Icon(Icons.business_center_rounded, size: (18 * scale).clamp(14.0, 20.0)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10 * scale),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10 * scale,
                          vertical: (10 * scale).clamp(6.0, 12.0),
                        ),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All Departments')),
                        ..._allDepartments.where((d) => d['parent_id'] == null).map((d) => DropdownMenuItem<String?>(
                              value: d['id'].toString(),
                              child: Text(d['name'] ?? ''),
                            )),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedDeptId = val;
                          selectedSubDeptId = null;
                          selectedClass = null;
                        });
                      },
                    ),

                    // Sub-Department Dropdown (if available)
                    if (availableSubDepts.isNotEmpty) ...[
                      SizedBox(height: 10 * scale),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('idcard_subdept_${selectedDeptId ?? 'none'}'),
                        initialValue: selectedSubDeptId,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: AppTheme.getFontStyle(
                          fontSize: (12.5 * scale).clamp(10.0, 14.0),
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          labelText: context.tr('sub_department'),
                          labelStyle: TextStyle(
                            fontSize: (11 * scale).clamp(9.0, 13.0),
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          prefixIcon: Icon(Icons.subdirectory_arrow_right_rounded, size: (18 * scale).clamp(14.0, 20.0)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10 * scale),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10 * scale,
                            vertical: (10 * scale).clamp(6.0, 12.0),
                          ),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Sub-Departments')),
                          ...availableSubDepts.map((s) => DropdownMenuItem<String?>(
                                value: s['id'].toString(),
                                child: Text(s['name'] ?? ''),
                              )),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            selectedSubDeptId = val;
                            selectedClass = null;
                          });
                        },
                      ),
                    ],

                    SizedBox(height: 10 * scale),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('idcard_class_${selectedDeptId ?? 'all'}_${selectedSubDeptId ?? 'all'}'),
                      initialValue: availableClasses.contains(selectedClass) ? selectedClass : null,
                      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                      style: AppTheme.getFontStyle(
                        fontSize: (12.5 * scale).clamp(10.0, 14.0),
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        labelText: context.tr('select_class'),
                        labelStyle: TextStyle(
                          fontSize: (11 * scale).clamp(9.0, 13.0),
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                        prefixIcon: Icon(Icons.class_rounded, size: (18 * scale).clamp(14.0, 20.0)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10 * scale),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10 * scale,
                          vertical: (10 * scale).clamp(6.0, 12.0),
                        ),
                        isDense: true,
                      ),
                      items: availableClasses
                          .map((c) => DropdownMenuItem<String?>(
                                value: c,
                                child: Text(
                                  c,
                                  style: AppTheme.getFontStyle(
                                    fontSize: (12.5 * scale).clamp(10.0, 14.0),
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() => selectedClass = val);
                      },
                    ),
                    if (selectedClass != null) ...[
                      SizedBox(height: 10 * scale),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(8 * scale),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: (14 * scale).clamp(11.0, 16.0), color: AppTheme.primaryColor),
                            SizedBox(width: 6 * scale),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$filteredCount ${context.tr('students_found')}',
                                  style: AppTheme.getFontStyle(
                                    fontSize: (11.5 * scale).clamp(9.0, 13.0),
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
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
            actions: Container(
              padding: EdgeInsets.fromLTRB(14 * scale, 8 * scale, 14 * scale, 12 * scale),
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
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      context.tr('cancel'),
                      style: AppTheme.getFontStyle(
                        fontSize: (12 * scale).clamp(9.5, 13.0),
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  FilledButton.icon(
                    onPressed: selectedClass == null
                        ? null
                        : () {
                            final filtered = allStudents
                                .where((s) => s.className == selectedClass)
                                .toList();
                            Navigator.pop(dialogContext);
                            // Open template builder in bulk mode
                            if (_ensureFeatureAccess('students_id_card', 'ID Card Builder & Designer')) {
                              StudentIdCardBuilderDialog.showBulk(context, filtered, allStudents: allStudents);
                            }
                          },
                    icon: Icon(Icons.design_services_rounded, size: (15 * scale).clamp(12.0, 18.0)),
                    label: Text(
                      'Design & Print',
                      style: AppTheme.getFontStyle(
                        fontSize: (12 * scale).clamp(9.5, 13.0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteStudent(Student student) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('confirm_delete'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          context.tr('delete_student_confirm_msg').replaceAll('{name}', student.fullName),
          style: AppTheme.getFontStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<StudentsBloc>().add(DeleteStudent(student.id));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('${student.fullName} ${context.tr('deleted_successfully')}'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  void _showBulkDeleteConfirmDialog() {
    if (_selectedStudentIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('confirm_delete'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedStudentIds.length} selected students? This action cannot be undone and will delete all their details.',
          style: AppTheme.getFontStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<StudentsBloc>().add(BulkDeleteStudents(List.from(_selectedStudentIds)));
              Navigator.pop(ctx);
              setState(() {
                _isSelectionMode = false;
                _selectedStudentIds.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text('Students deleted successfully'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        return Column(
          children: [
            // TabBar (Matched with Staff Page Navigation Style)
            Container(
              margin: EdgeInsets.fromLTRB(
                isCompact ? (8.0 * scale) : 24,
                isCompact ? (6.0 * scale) : 16,
                isCompact ? (8.0 * scale) : 24,
                0,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12 * scale),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12 * scale),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
                labelStyle: AppTheme.getFontStyle(
                  fontSize: isCompact ? (11.0 * scale) : 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: AppTheme.getFontStyle(
                  fontSize: isCompact ? (11.0 * scale) : 13,
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(
                    height: isCompact ? (38.0 * scale) : 46.0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_rounded, size: isCompact ? (14.0 * scale) : 16),
                        SizedBox(width: isCompact ? (4.0 * scale) : 6),
                        Flexible(
                          child: Text(
                            context.tr('students'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    height: isCompact ? (38.0 * scale) : 46.0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tune_rounded, size: isCompact ? (14.0 * scale) : 16),
                        SizedBox(width: isCompact ? (4.0 * scale) : 6),
                        const Flexible(
                          child: Text(
                            'Tools & Operations',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _KeepAlivePageWrapper(child: _buildStudentsListTab(isDark)),
                  _KeepAlivePageWrapper(child: _buildToolsTab(isDark)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Students List Tab ───────────────────────────────────────────────────────
  Widget _buildStudentsListTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final isMedium = width >= 700 && width < 1100;
        final isWide = width >= 1100;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 0 : 24,
            vertical: isCompact ? 0 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isCompact) ...[
                _buildHeader(isDark, false, scale),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: BlocBuilder<StudentsBloc, StudentsState>(
                  builder: (context, state) {
                    if (state is StudentsLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is StudentsError) {
                      return _buildError(state.message);
                    }
                    final rawStudents = state is StudentsLoaded
                        ? state.students
                        : <Student>[];
                    final students = _filterStudentList(rawStudents);

                    if (isCompact) {
                      return CustomScrollView(
                        key: const PageStorageKey<String>('students_compact_scroll_view'),
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 8 * scale, 0),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeader(isDark, true, scale),
                                  SizedBox(height: 10 * scale),
                                  if (_isSelectionMode) ...[
                                    _buildCompactSelectionBar(isDark, scale, students),
                                    SizedBox(height: 10 * scale),
                                  ],
                                  _buildStatsRow(students, isDark, true),
                                  SizedBox(height: 10 * scale),
                                  _buildSearchBar(isDark, true, isWide, rawStudents),
                                  SizedBox(height: 10 * scale),
                                ],
                              ),
                            ),
                          ),
                          if (students.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmpty(),
                            )
                          else if (_viewMode == 'table')
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                              sliver: SliverToBoxAdapter(
                                child: _buildTableView(students, isDark, false),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    return Padding(
                                      padding: EdgeInsets.only(bottom: 10 * scale),
                                      child: _StudentCard(
                                        student: students[index],
                                        isDark: isDark,
                                        scale: scale,
                                        deptDisplay: _getStudentAcademicDisplay(students[index]),
                                        isSelectionMode: _isSelectionMode,
                                        isSelected: _selectedStudentIds.contains(students[index].id),
                                        onSelectChanged: (val) => _toggleSelection(students[index].id),
                                        onView: () => _openStudentProfile(students[index].id, initialStudent: students[index]),
                                        onEdit: () => _showAddEditDialog(students[index]),
                                        onDelete: () => _deleteStudent(students[index]),
                                      ),
                                    );
                                  },
                                  childCount: students.length,
                                ),
                              ),
                            ),
                        ],
                      );
                    }

                    // Desktop / Tablet layout
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isSelectionMode) ...[
                          _buildDesktopSelectionBar(isDark, students),
                          const SizedBox(height: 16),
                        ],
                        _buildStatsRow(students, isDark, false),
                        const SizedBox(height: 16),
                        _buildSearchBar(isDark, false, isWide, rawStudents),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              if (students.isEmpty) {
                                return _buildEmpty();
                              }
                              final effectiveMode = isWide ? _viewMode : 'card';
                              if (effectiveMode == 'card') {
                                return _buildCardGrid(
                                  students,
                                  isDark,
                                  isCompact,
                                  isMedium,
                                  isWide,
                                );
                              }
                              return _buildTableView(students, isDark, isWide);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tools & Operations Tab ─────────────────────────────────────────────────
  Widget _buildToolsTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final isWide = width >= 1100;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        return BlocBuilder<StudentsBloc, StudentsState>(
          builder: (context, state) {
            final rawStudents = state is StudentsLoaded
                ? state.students
                : <Student>[];

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 8 * scale : 24,
                vertical: isCompact ? 8 * scale : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isCompact) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(isDark ? 40 : 20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: AppTheme.primaryColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Student Tools & Operations',
                                style: AppTheme.getFontStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Assign roll numbers, import/export data, configure statuses, G.R. format, and print ID cards',
                                style: AppTheme.getFontStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  _buildToolsPage(isDark, isCompact, isWide, scale, rawStudents),
                  SizedBox(height: 20 * scale),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Selection Bars ──────────────────────────────────────────────────────────
  Widget _buildCompactSelectionBar(bool isDark, double scale, List<Student> students) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 8 * scale,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(25),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(
          color: AppTheme.primaryColor.withAlpha(50),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedStudentIds.length} Selected',
            style: AppTheme.getFontStyle(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              setState(() {
                if (_selectedStudentIds.length == students.length) {
                  _selectedStudentIds.clear();
                } else {
                  _selectedStudentIds = students.map((s) => s.id).toList();
                }
              });
            },
            icon: Icon(
              _selectedStudentIds.length == students.length && students.isNotEmpty
                  ? Icons.select_all_rounded
                  : Icons.select_all_outlined,
              size: 18 * scale,
              color: AppTheme.primaryColor,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: _selectedStudentIds.length == students.length
                ? 'Deselect All'
                : 'Select All',
          ),
          SizedBox(width: 8 * scale),
          if (_selectedStudentIds.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: _showBulkAssignCategoryDialog,
              icon: Icon(Icons.category, size: 14 * scale),
              label: Text(
                context.tr('assign_category'),
                style: AppTheme.getFontStyle(fontSize: 11 * scale),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6B4E),
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 6 * scale,
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
            FilledButton.icon(
              onPressed: _showBulkAssignStatusDialog,
              icon: Icon(Icons.label_important_rounded, size: 14 * scale),
              label: Text(
                'Assign Status',
                style: AppTheme.getFontStyle(fontSize: 11 * scale),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 6 * scale,
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
            FilledButton.icon(
              onPressed: _showBulkPromoteDialog,
              icon: Icon(Icons.school_rounded, size: 14 * scale),
              label: Text(
                'Promote',
                style: AppTheme.getFontStyle(fontSize: 11 * scale),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0288D1),
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 6 * scale,
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
          ],
          IconButton(
            onPressed: _selectedStudentIds.isEmpty
                ? null
                : _showBulkDeleteConfirmDialog,
            icon: Icon(
              Icons.delete_sweep_rounded,
              color: _selectedStudentIds.isEmpty
                  ? (isDark ? Colors.white24 : Colors.grey.shade400)
                  : Colors.redAccent,
              size: 20 * scale,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete Selected',
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSelectionBar(bool isDark, List<Student> students) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryColor.withAlpha(50),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedStudentIds.length} ${context.tr('selected')}',
            style: AppTheme.getFontStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                if (_selectedStudentIds.length == students.length) {
                  _selectedStudentIds.clear();
                } else {
                  _selectedStudentIds = students.map((s) => s.id).toList();
                }
              });
            },
            icon: Icon(
              _selectedStudentIds.length == students.length && students.isNotEmpty
                  ? Icons.deselect_rounded
                  : Icons.select_all_rounded,
              size: 16,
            ),
            label: Text(
              _selectedStudentIds.length == students.length && students.isNotEmpty
                  ? 'Deselect All'
                  : 'Select All',
              style: AppTheme.getFontStyle(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const Spacer(),
          if (_selectedStudentIds.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: _showBulkAssignCategoryDialog,
              icon: const Icon(Icons.category, size: 18),
              label: Text(context.tr('assign_category')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6B4E),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _showBulkAssignStatusDialog,
              icon: const Icon(Icons.label_important_rounded, size: 18),
              label: const Text('Assign Status'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _showBulkPromoteDialog,
              icon: const Icon(Icons.school_rounded, size: 18),
              label: const Text('Promote / Saalana Tarqqi'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0288D1),
              ),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.icon(
            onPressed: _selectedStudentIds.isEmpty
                ? null
                : _showBulkDeleteConfirmDialog,
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Delete Selected'),
            style: FilledButton.styleFrom(
              backgroundColor: _selectedStudentIds.isEmpty
                  ? (isDark ? Colors.white24 : Colors.grey.shade400)
                  : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, bool isCompact, double scale) {
    if (isCompact) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('students'),
                  style: AppTheme.getFontStyle(
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  context.tr('manage_students_subtitle'),
                  style: AppTheme.getFontStyle(
                    fontSize: 11 * scale,
                    color: Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 8 * scale),
          // Bulk Selection Toggle
          IconButton(
            onPressed: _toggleSelectionMode,
            icon: Icon(
              _isSelectionMode ? Icons.cancel : Icons.checklist_rounded,
              size: 20 * scale,
            ),
            color: _isSelectionMode ? Colors.red : AppTheme.primaryColor,
            style: IconButton.styleFrom(
              side: BorderSide(
                color: _isSelectionMode
                    ? Colors.red.withAlpha(80)
                    : AppTheme.primaryColor.withAlpha(80),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              padding: EdgeInsets.all(8 * scale),
            ),
            tooltip: 'Bulk Select',
          ),
          SizedBox(width: 8 * scale),
          // Add Student Button
          IconButton(
            onPressed: () => _showAddEditDialog(),
            icon: Icon(Icons.add_rounded, size: 20 * scale),
            color: Colors.white,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              padding: EdgeInsets.all(8 * scale),
            ),
            tooltip: context.tr('add_student'),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isNarrow = availableWidth < 1000;

        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('students'),
              style: AppTheme.getFontStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              ),
            ),
            Text(
              context.tr('manage_students_subtitle'),
              style: AppTheme.getFontStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        );

        final actions = <Widget>[
          OutlinedButton.icon(
            onPressed: _toggleSelectionMode,
            icon: Icon(
              _isSelectionMode ? Icons.cancel : Icons.checklist_rounded,
              size: 18,
            ),
            label: Text(
              _isSelectionMode ? 'Cancel Selection' : 'Select Multiple',
              style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _isSelectionMode ? Colors.red : AppTheme.primaryColor,
              side: BorderSide(
                color: _isSelectionMode ? Colors.red : AppTheme.primaryColor,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _ViewToggle(
            mode: _viewMode,
            onChanged: (m) => setState(() => _viewMode = m),
            isDark: isDark,
          ),
          const SizedBox(width: 12),
          // Add Student button
          FilledButton.icon(
            onPressed: () => _showAddEditDialog(),
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: Text(
              context.tr('add_student'),
              style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ];

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleWidget,
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            titleWidget,
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Dedicated Tools & Operations Page ──────────────────────────────────
  Widget _buildToolsPage(bool isDark, bool isCompact, bool isWide, double scale, List<Student> students) {
    final tools = [
      _StudentToolItem(
        title: 'Academic History & Progression Explorer',
        description: 'Search & explore student historical archives by Year, Class, Department, Date & Status with full exam marks, fees & expenses.',
        icon: Icons.history_edu_rounded,
        color: const Color(0xFF0D6B4E),
        badgeText: 'Archives & History',
        buttonLabel: 'Explore History',
        onTap: () {
          AcademicHistoryExplorerDialog.show(context);
        },
      ),

      _StudentToolItem(
        title: 'Assign Roll Numbers & Division',
        description: 'Auto-assign or manually configure roll numbers and division sections for students by class.',
        icon: Icons.format_list_numbered_rounded,
        color: const Color(0xFF1565C0),
        badgeText: 'Academic',
        buttonLabel: 'Assign Roll & Division',
        onTap: () {
          if (!_ensureFeatureAccess('students_edit', 'Assign Roll Numbers & Division')) return;
          if (students.isNotEmpty) {
            _showAssignRollNumberDialog(students);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No students available to assign roll numbers.')),
            );
          }
        },
      ),
      _StudentToolItem(
        title: 'Import Excel / CSV',
        description: 'Bulk import new student records, contact details, and classes from .xlsx or .csv spreadsheets.',
        icon: Icons.file_upload_rounded,
        color: const Color(0xFF0D6B4E),
        badgeText: 'Data Import',
        buttonLabel: 'Import Excel',
        onTap: () {
          if (!_ensureFeatureAccess('students_excel_import', 'Import from Excel')) return;
          _showImportExcelDialog(students);
        },
      ),
      _StudentToolItem(
        title: 'Export Excel / CSV',
        description: 'Export all student records with fee structures, admission dates, and academic details to Excel.',
        icon: Icons.file_download_rounded,
        color: const Color(0xFF1565C0),
        badgeText: 'Reports',
        buttonLabel: 'Export Excel',
        onTap: () {
          if (!_ensureFeatureAccess('students_excel_export', 'Export to Excel')) return;
          _exportToExcel(students);
        },
      ),
      _StudentToolItem(
        title: 'Status Categories',
        description: 'Create and customize student enrollment statuses like Active, Inactive, Farar, Graduated, etc.',
        icon: Icons.label_rounded,
        color: const Color(0xFF6A1B9A),
        badgeText: 'Enrollment',
        buttonLabel: 'Manage Statuses',
        onTap: () {
          if (!_ensureFeatureAccess('students_edit', 'Status Categories')) return;
          ManageStatusCategoriesDialog.show(context);
        },
      ),
      _StudentToolItem(
        title: 'Gender Options',
        description: 'Customize gender categories (Male, Female, Other, etc.) used across student registration and forms.',
        icon: Icons.wc_rounded,
        color: const Color(0xFF00897B),
        badgeText: 'Demographics',
        buttonLabel: 'Manage Genders',
        onTap: () {
          if (!_ensureFeatureAccess('students_edit', 'Gender Options')) return;
          ManageFormOptionsDialog.show(
            context: context,
            title: 'Manage Genders',
            icon: Icons.wc_rounded,
            themeColor: const Color(0xFF00897B),
            getOptions: StudentFormOptionsSettings.getGenders,
            saveOptions: StudentFormOptionsSettings.saveGenders,
          );
        },
      ),
      _StudentToolItem(
        title: 'Admission Types',
        description: 'Configure admission categories (New, Old, Promoted, Hosteller, Day Scholar, etc.) for students.',
        icon: Icons.how_to_reg_rounded,
        color: const Color(0xFFE65100),
        badgeText: 'Admissions',
        buttonLabel: 'Manage Types',
        onTap: () {
          if (!_ensureFeatureAccess('students_admission', 'Admission Types')) return;
          ManageFormOptionsDialog.show(
            context: context,
            title: 'Manage Admission Types',
            icon: Icons.how_to_reg_rounded,
            themeColor: const Color(0xFFE65100),
            getOptions: StudentFormOptionsSettings.getAdmissionTypes,
            saveOptions: StudentFormOptionsSettings.saveAdmissionTypes,
          );
        },
      ),
      _StudentToolItem(
        title: 'G.R. Number Format',
        description: 'Configure dynamic General Registration (G.R.) number prefixes, suffixes, digit length, and auto-generation.',
        icon: Icons.settings_suggest_rounded,
        color: const Color(0xFFD4AF37),
        badgeText: 'Auto-ID',
        buttonLabel: 'Format Settings',
        onTap: () {
          if (_ensureFeatureAccess('students_gr_no_config', 'GR Number Auto Config')) {
            GrNoConfigDialog.show(context);
          }
        },
      ),
      _StudentToolItem(
        title: 'Print Student ID Cards',
        description: 'Batch print professional student ID cards with barcodes, photos, and customizable templates.',
        icon: Icons.badge_rounded,
        color: AppTheme.primaryColor,
        badgeText: 'ID Printing',
        buttonLabel: 'Print ID Cards',
        onTap: () {
          if (!_ensureFeatureAccess('students_id_card_print', 'ID Card Printing')) return;
          if (students.isNotEmpty) {
            _showPrintIdCardDialog(students);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No students available to print ID cards.')),
            );
          }
        },
      ),
    ];

    if (isCompact) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tools.length,
        separatorBuilder: (context, index) => SizedBox(height: 12 * scale),
        itemBuilder: (context, index) {
          return _buildToolCard(tools[index], isDark, scale);
        },
      );
    }

    final crossAxisCount = isWide ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: isWide ? 1.85 : 1.65,
      ),
      itemCount: tools.length,
      itemBuilder: (context, index) {
        return _buildToolCard(tools[index], isDark, 1.0);
      },
    );
  }

  Widget _buildToolCard(_StudentToolItem tool, bool isDark, double scale) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tool.onTap,
        borderRadius: BorderRadius.circular(16 * scale),
        child: Container(
          padding: EdgeInsets.all(16 * scale),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: tool.color.withAlpha(isDark ? 16 : 8),
                blurRadius: 12 * scale,
                offset: Offset(0, 4 * scale),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 8 * scale,
                offset: Offset(0, 2 * scale),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44 * scale,
                    height: 44 * scale,
                    decoration: BoxDecoration(
                      color: tool.color.withAlpha(isDark ? 40 : 20),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(
                        color: tool.color.withAlpha(isDark ? 80 : 50),
                      ),
                    ),
                    child: Icon(
                      tool.icon,
                      color: tool.color,
                      size: 22 * scale,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                tool.title,
                                style: AppTheme.getFontStyle(
                                  fontSize: 15 * scale,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6 * scale,
                                vertical: 2 * scale,
                              ),
                              decoration: BoxDecoration(
                                color: tool.color.withAlpha(isDark ? 30 : 15),
                                borderRadius: BorderRadius.circular(6 * scale),
                              ),
                              child: Text(
                                tool.badgeText,
                                style: AppTheme.getFontStyle(
                                  fontSize: 9.5 * scale,
                                  fontWeight: FontWeight.w700,
                                  color: tool.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6 * scale),
                        Text(
                          tool.description,
                          style: AppTheme.getFontStyle(
                            fontSize: 11.5 * scale,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12 * scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: tool.onTap,
                    icon: Icon(tool.icon, size: 14 * scale),
                    label: Text(
                      tool.buttonLabel,
                      style: AppTheme.getFontStyle(
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tool.color,
                      side: BorderSide(color: tool.color),
                      padding: EdgeInsets.symmetric(
                        horizontal: 14 * scale,
                        vertical: 8 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stats Row ────────────────────────────────────────────────────────────
  Widget _buildStatsRow(List<Student> students, bool isDark, bool isCompact) {
    final configs = _statCardConfigs.length == 4
        ? _statCardConfigs
        : [
            StudentStatCardConfig(
              id: 'card_1',
              type: 'total',
              label: context.tr('total'),
              filterValue: null,
              iconCodePoint: Icons.people_alt_rounded.codePoint,
              colorValue: 0xFF0D6B4E,
            ),
            StudentStatCardConfig(
              id: 'card_2',
              type: 'status',
              label: context.tr('active'),
              filterValue: 'Active',
              iconCodePoint: Icons.check_circle_outline_rounded.codePoint,
              colorValue: 0xFF1565C0,
            ),
            StudentStatCardConfig(
              id: 'card_3',
              type: 'gender',
              label: context.tr('male'),
              filterValue: 'Male',
              iconCodePoint: Icons.male_rounded.codePoint,
              colorValue: 0xFF6A1B9A,
            ),
            StudentStatCardConfig(
              id: 'card_4',
              type: 'gender',
              label: context.tr('female'),
              filterValue: 'Female',
              iconCodePoint: Icons.female_rounded.codePoint,
              colorValue: 0xFFC62828,
            ),
          ];

    final stats = configs.asMap().entries.map((entry) {
      final idx = entry.key;
      final config = entry.value;
      final count = _calculateStatCount(students, config);
      return _StatInfo(
        config.label,
        count.toString(),
        config.icon,
        config.color,
        onTap: () => _onStatCardTapped(config),
        onSettingsTap: () => _showQuickEditSingleCardDialog(idx, students),
      );
    }).toList();

    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);

    final customizeButton = InkWell(
      onTap: () => _showCustomizeStatCardsDialog(students),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 13 * scale,
              color: isDark ? Colors.white60 : const Color(0xFF0D6B4E),
            ),
            SizedBox(width: 4 * scale),
            Text(
              'Customize Cards',
              style: AppTheme.getFontStyle(
                fontSize: 11 * scale,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF0D6B4E),
              ),
            ),
          ],
        ),
      ),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STUDENT METRICS',
                style: AppTheme.getFontStyle(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  letterSpacing: 0.5,
                ),
              ),
              customizeButton,
            ],
          ),
          SizedBox(height: 6 * scale),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8 * scale,
            mainAxisSpacing: 8 * scale,
            childAspectRatio: 2.3,
            children: stats
                .map((s) => _MiniStatCard(info: s, isDark: isDark, scale: scale))
                .toList(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SUMMARY STATS',
              style: AppTheme.getFontStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            customizeButton,
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: stats
              .map(
                (s) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _MiniStatCard(info: s, isDark: isDark),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  void _showQuickEditSingleCardDialog(int cardIndex, List<Student> allStudents) {
    _showCustomizeStatCardsDialog(allStudents, initialCardIndex: cardIndex);
  }

  Future<void> _showCustomizeStatCardsDialog(List<Student> allStudents, {int initialCardIndex = 0}) async {
    List<String> statusList = [];
    List<String> genderList = [];
    List<String> categoryList = [];
    List<String> deptList = [];
    List<String> conditionList = [];

    try {
      final savedStatuses = await StudentStatusSettings.getStatuses();
      final studentStatuses = allStudents
          .map((s) => s.studentStatus?.trim())
          .where((st) => st != null && st.isNotEmpty)
          .cast<String>()
          .toSet();
      statusList = {...savedStatuses, ...studentStatuses, 'Active', 'Inactive'}.toList()..sort();
    } catch (_) {
      statusList = ['Active', 'Inactive', 'Graduated', 'Passed Out', 'Suspended', 'On Leave', 'Transferred'];
    }

    try {
      final savedGenders = await StudentFormOptionsSettings.getGenders();
      final studentGenders = allStudents
          .map((s) => s.gender?.trim())
          .where((g) => g != null && g.isNotEmpty)
          .cast<String>()
          .toSet();
      genderList = {...savedGenders, ...studentGenders, 'Male', 'Female', 'Other'}.toList()..sort();
    } catch (_) {
      genderList = ['Male', 'Female', 'Ladka', 'Ladki', 'Other'];
    }

    categoryList = allStudents
        .map((s) => s.category?.trim())
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();
    if (categoryList.isEmpty) {
      categoryList = ['Muqeem', 'Ghair Muqeem', 'Resident', 'Day Scholar'];
    }

    deptList = _allDepartments
        .map((d) => d['name']?.toString().trim())
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();
    if (deptList.isEmpty) {
      deptList = allStudents
          .map((s) => s.departmentName?.trim())
          .where((d) => d != null && d.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList()..sort();
    }

    try {
      final savedConditions = await StudentFormOptionsSettings.getConditions();
      final studentConditions = allStudents
          .map((s) => s.conditionType?.trim())
          .where((c) => c != null && c.isNotEmpty)
          .cast<String>()
          .toSet();
      conditionList = {...savedConditions, ...studentConditions}.toList()..sort();
    } catch (_) {
      conditionList = ['Regular', 'Scholarship', 'Partial', 'Concession', 'Orphan Free', 'Staff Child'];
    }

    List<StudentStatCardConfig> tempConfigs = _statCardConfigs.map((c) => c.copyWith()).toList();
    if (tempConfigs.length < 4) {
      await _initDefaultStatCardConfigs();
      tempConfigs = _statCardConfigs.map((c) => c.copyWith()).toList();
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        int selectedIndex = initialCardIndex.clamp(0, 3);
        final titleControllers = [
          TextEditingController(text: tempConfigs[0].label),
          TextEditingController(text: tempConfigs[1].label),
          TextEditingController(text: tempConfigs[2].label),
          TextEditingController(text: tempConfigs[3].label),
        ];

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
            final screenWidth = MediaQuery.of(dialogCtx).size.width;
            final isMobile = screenWidth < 600;
            final currentCard = tempConfigs[selectedIndex];
            final currentTitleCtrl = titleControllers[selectedIndex];

            final colorList = const [
              Color(0xFF0D6B4E), // Madarsa Green
              Color(0xFF1565C0), // Blue
              Color(0xFF6A1B9A), // Purple
              Color(0xFFC62828), // Crimson Red
              Color(0xFFE65100), // Amber
              Color(0xFF00695C), // Teal
              Color(0xFF00838F), // Cyan
              Color(0xFF283593), // Indigo
              Color(0xFFAD1457), // Rose Pink
              Color(0xFF4E342E), // Brown
            ];

            final iconList = const [
              Icons.people_alt_rounded,
              Icons.male_rounded,
              Icons.female_rounded,
              Icons.check_circle_outline_rounded,
              Icons.cancel_outlined,
              Icons.school_rounded,
              Icons.menu_book_rounded,
              Icons.phone_android_rounded,
              Icons.badge_rounded,
              Icons.payments_rounded,
              Icons.star_rounded,
              Icons.location_on_rounded,
            ];

            return MovableResizableDialog(
              initialWidth: isMobile ? screenWidth * 0.94 : 640,
              initialHeight: 640,
              minWidth: 400,
              minHeight: 380,
              headerLeading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customize Summary Cards',
                    style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    '4 Summary cards ko apni marzi se configure karein',
                    style: AppTheme.getFontStyle(fontSize: 11, color: Colors.white.withAlpha(180)),
                  ),
                ],
              ),
              content: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Live Preview Section
                      Text(
                        'LIVE PREVIEW (REAL-TIME COUNTS)',
                        style: AppTheme.getFontStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(4, (i) {
                          final cfg = tempConfigs[i];
                          final count = _calculateStatCount(allStudents, cfg);
                          final isSelected = i == selectedIndex;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() => selectedIndex = i);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? cfg.color : (isDark ? Colors.white12 : Colors.grey.shade300),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(cfg.icon, color: cfg.color, size: 16),
                                      const SizedBox(height: 4),
                                      Text(
                                        count.toString(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        cfg.label,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? cfg.color : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Card Selector Tabs
                      Row(
                        children: List.generate(4, (i) {
                          final isSelected = i == selectedIndex;
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: i < 3 ? 6 : 0),
                              child: ChoiceChip(
                                label: Center(
                                  child: Text(
                                    'Card ${i + 1}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: tempConfigs[i].color.withAlpha(40),
                                onSelected: (val) {
                                  if (val) setDialogState(() => selectedIndex = i);
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),

                      // Metric Type Selector
                      Text(
                        '1. Metric Type (Kis cheez ka count dekhna he?)',
                        style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: currentCard.type,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'total', child: Text('Total Students (Kul Talba)')),
                          DropdownMenuItem(value: 'status', child: Text('Student Status (Active, Inactive, etc.)')),
                          DropdownMenuItem(value: 'gender', child: Text('Gender / Jins (Male, Female, Ladka, Ladki)')),
                          DropdownMenuItem(value: 'category', child: Text('Category (Muqeem, Resident, etc.)')),
                          DropdownMenuItem(value: 'department', child: Text('Department / Shoba')),
                          DropdownMenuItem(value: 'condition', child: Text('Fee Condition (Regular, Free, etc.)')),
                          DropdownMenuItem(value: 'with_mobile', child: Text('With Mobile Number')),
                          DropdownMenuItem(value: 'without_mobile', child: Text('Without Mobile Number')),
                          DropdownMenuItem(value: 'with_aadhaar', child: Text('With Aadhaar Number')),
                          DropdownMenuItem(value: 'without_aadhaar', child: Text('Without Aadhaar Number')),
                        ],
                        onChanged: (newType) {
                          if (newType == null) return;
                          String newLabel = currentCard.label;
                          String? newFilter = currentCard.filterValue;
                          int iconCode = currentCard.iconCodePoint;
                          int colVal = currentCard.colorValue;

                          if (newType == 'total') {
                            newLabel = 'Total';
                            newFilter = null;
                            iconCode = Icons.people_alt_rounded.codePoint;
                            colVal = 0xFF0D6B4E;
                          } else if (newType == 'status') {
                            newFilter = statusList.isNotEmpty ? statusList.first : 'Active';
                            newLabel = newFilter;
                            iconCode = Icons.check_circle_outline_rounded.codePoint;
                            colVal = 0xFF1565C0;
                          } else if (newType == 'gender') {
                            newFilter = genderList.isNotEmpty ? genderList.first : 'Male';
                            newLabel = newFilter;
                            iconCode = Icons.male_rounded.codePoint;
                            colVal = 0xFF6A1B9A;
                          } else if (newType == 'category') {
                            newFilter = categoryList.isNotEmpty ? categoryList.first : 'Muqeem';
                            newLabel = newFilter;
                            iconCode = Icons.school_rounded.codePoint;
                            colVal = 0xFFE65100;
                          } else if (newType == 'department') {
                            newFilter = deptList.isNotEmpty ? deptList.first : 'Hifz';
                            newLabel = newFilter;
                            iconCode = Icons.menu_book_rounded.codePoint;
                            colVal = 0xFF00695C;
                          } else if (newType == 'condition') {
                            newFilter = conditionList.isNotEmpty ? conditionList.first : 'Regular';
                            newLabel = newFilter;
                            iconCode = Icons.payments_rounded.codePoint;
                            colVal = 0xFF283593;
                          } else if (newType == 'with_mobile') {
                            newLabel = 'With Mobile';
                            newFilter = null;
                            iconCode = Icons.phone_android_rounded.codePoint;
                            colVal = 0xFF00838F;
                          } else if (newType == 'without_mobile') {
                            newLabel = 'No Mobile';
                            newFilter = null;
                            iconCode = Icons.phone_android_rounded.codePoint;
                            colVal = 0xFFC62828;
                          } else if (newType == 'with_aadhaar') {
                            newLabel = 'With Aadhaar';
                            newFilter = null;
                            iconCode = Icons.badge_rounded.codePoint;
                            colVal = 0xFF00695C;
                          } else if (newType == 'without_aadhaar') {
                            newLabel = 'No Aadhaar';
                            newFilter = null;
                            iconCode = Icons.badge_rounded.codePoint;
                            colVal = 0xFFAD1457;
                          }

                          currentTitleCtrl.text = newLabel;
                          setDialogState(() {
                            tempConfigs[selectedIndex] = currentCard.copyWith(
                              type: newType,
                              label: newLabel,
                              filterValue: newFilter,
                              iconCodePoint: iconCode,
                              colorValue: colVal,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Target Filter Value Dropdown
                      if (currentCard.type == 'status' ||
                          currentCard.type == 'gender' ||
                          currentCard.type == 'category' ||
                          currentCard.type == 'department' ||
                          currentCard.type == 'condition') ...[
                        Text(
                          '2. Select Target ${currentCard.type.toUpperCase()} to Match',
                          style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (ctx) {
                            List<String> items = [];
                            if (currentCard.type == 'status') items = statusList;
                            if (currentCard.type == 'gender') items = genderList;
                            if (currentCard.type == 'category') items = categoryList;
                            if (currentCard.type == 'department') items = deptList;
                            if (currentCard.type == 'condition') items = conditionList;

                            final currentVal = currentCard.filterValue;
                            final valueToUse = (currentVal != null && items.contains(currentVal))
                                ? currentVal
                                : (items.isNotEmpty ? items.first : null);

                            return DropdownButtonFormField<String>(
                              initialValue: valueToUse,
                              isExpanded: true,
                              dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: items
                                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                                  .toList(),
                              onChanged: (newVal) {
                                if (newVal == null) return;
                                currentTitleCtrl.text = newVal;
                                setDialogState(() {
                                  tempConfigs[selectedIndex] = currentCard.copyWith(
                                    filterValue: newVal,
                                    label: newVal,
                                  );
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Card Label / Title
                      Text(
                        '3. Card Title / Label (Jo card par likha dikhe)',
                        style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: currentTitleCtrl,
                        decoration: InputDecoration(
                          hintText: 'e.g. Total, Active, Ladke, Hifz...',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (v) {
                          setDialogState(() {
                            tempConfigs[selectedIndex] = currentCard.copyWith(label: v.trim());
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Card Color Picker
                      Text(
                        '4. Theme Color',
                        style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: colorList.map((col) {
                          final isColSelected = currentCard.colorValue == col.toARGB32();
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                tempConfigs[selectedIndex] = currentCard.copyWith(colorValue: col.toARGB32());
                              });
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isColSelected ? Colors.white : Colors.transparent,
                                  width: 2,
                                ),
                                boxShadow: [
                                  if (isColSelected)
                                    BoxShadow(
                                      color: col.withAlpha(150),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                ],
                              ),
                              child: isColSelected
                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // Card Icon Picker
                      Text(
                        '5. Card Icon',
                        style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: iconList.map((ic) {
                          final isIconSelected = currentCard.iconCodePoint == ic.codePoint;
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                tempConfigs[selectedIndex] = currentCard.copyWith(
                                  iconCodePoint: ic.codePoint,
                                  iconFontFamily: ic.fontFamily,
                                );
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isIconSelected
                                    ? currentCard.color.withAlpha(40)
                                    : (isDark ? Colors.white10 : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isIconSelected ? currentCard.color : Colors.transparent,
                                ),
                              ),
                              child: Icon(ic, size: 18, color: isIconSelected ? currentCard.color : (isDark ? Colors.white70 : Colors.black54)),
                            ),
                          );
                        }).toList(),
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
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await _initDefaultStatCardConfigs();
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                      },
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('Reset Defaults'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final finalConfigs = List.generate(4, (i) {
                          final ctrlText = titleControllers[i].text.trim();
                          return tempConfigs[i].copyWith(
                            label: ctrlText.isNotEmpty ? ctrlText : tempConfigs[i].label,
                          );
                        });
                        await _saveStatCardConfigs(finalConfigs);
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Save & Apply'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
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

  Widget _buildActiveFilterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 12, color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context, List<Student> allStudents) {
    final rawClasses = allStudents
        .map((s) => s.className?.trim())
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet();

    // Order classes by _academicHierarchy progression order
    final classes = <String>[];
    for (final cls in _academicHierarchy) {
      final n = cls['name']?.toString().trim();
      if (n != null && n.isNotEmpty && rawClasses.contains(n) && !classes.contains(n)) {
        classes.add(n);
      }
    }
    for (final c in rawClasses) {
      if (!classes.contains(c)) classes.add(c);
    }

    final villages = allStudents
        .map((s) => s.village)
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    final districts = allStudents
        .map((s) => s.district)
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    final states = allStudents
        .map((s) => s.state)
        .where((st) => st != null && st.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    final categories = allStudents
        .map((s) => s.category)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    final divisions = allStudents
        .map((s) => s.division)
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    String? tempDepartment = _filterDepartment;
    String? tempSubDepartment = _filterSubDepartment;
    String? tempClass = _filterClass;
    String? tempVillage = _filterVillage;
    String? tempDistrict = _filterDistrict;
    String? tempState = _filterState;
    String? tempCategory = _filterCategory;
    String? tempDivision = _filterDivision;
    String? tempGender = _filterGender;
    String? tempStatus = _filterStatus;

    if (tempClass != null && !classes.contains(tempClass)) {
      classes.add(tempClass);
    }
    if (tempVillage != null && !villages.contains(tempVillage)) {
      villages.add(tempVillage);
      villages.sort();
    }
    if (tempDistrict != null && !districts.contains(tempDistrict)) {
      districts.add(tempDistrict);
      districts.sort();
    }
    if (tempState != null && !states.contains(tempState)) {
      states.add(tempState);
      states.sort();
    }
    if (tempCategory != null && !categories.contains(tempCategory)) {
      categories.add(tempCategory);
      categories.sort();
    }
    if (tempDivision != null && !divisions.contains(tempDivision)) {
      divisions.add(tempDivision);
      divisions.sort();
    }

    final filterGenders = <String>{
      ...allStudents.map((s) => s.gender?.trim()).where((g) => g != null && g.isNotEmpty).cast<String>(),
      'Male',
      'Female',
      'Ladka',
      'Ladki',
    }.toList()..sort();

    final filterStatuses = <String>{
      ...allStudents.map((s) => s.studentStatus?.trim()).where((st) => st != null && st.isNotEmpty).cast<String>(),
      'Active',
      'Inactive',
      'Graduated',
      'Passed Out',
    }.toList()..sort();

    final minAgeCtrl = TextEditingController(text: _filterMinAge ?? '');
    final maxAgeCtrl = TextEditingController(text: _filterMaxAge ?? '');

    // Helper: get sub-departments for a main department
    List<Map<String, dynamic>> getAvailableSubDepts(String? deptId) {
      if (deptId == null) return [];
      final mainDept = _allDepartments.where(
        (d) => d['id']?.toString() == deptId,
      ).firstOrNull;
      if (mainDept == null) return [];
      return ((mainDept['sub_departments'] as List?) ??
              _allDepartments.where((d) => d['parent_id']?.toString() == deptId).toList())
          .cast<Map<String, dynamic>>();
    }

    // Helper: get classes filtered by selected department and sub-department preserving progression order
    List<String> getFilteredClasses(String? deptId, String? subDeptId) {
      if (subDeptId != null) {
        final res = <String>[];
        for (final cls in _academicHierarchy) {
          if (cls['department_id']?.toString() == subDeptId) {
            final n = cls['name']?.toString().trim();
            if (n != null && n.isNotEmpty && !res.contains(n)) {
              res.add(n);
            }
          }
        }
        return res;
      }
      if (deptId != null) {
        final subDepts = getAvailableSubDepts(deptId);
        final subIds = subDepts.map((s) => s['id']?.toString()).where((id) => id != null).toSet();
        final res = <String>[];
        for (final cls in _academicHierarchy) {
          final dId = cls['department_id']?.toString();
          if (dId == deptId || subIds.contains(dId)) {
            final n = cls['name']?.toString().trim();
            if (n != null && n.isNotEmpty && !res.contains(n)) {
              res.add(n);
            }
          }
        }
        return res;
      }
      return classes;
    }

    // Helper: get divisions filtered by selected class or current filtered classes
    List<String> getFilteredDivisions(String? clsName, List<String> availableClasses) {
      final divSet = <String>{};
      if (clsName != null) {
        final clsNode = _academicHierarchy.where(
          (c) => c['name']?.toString() == clsName,
        ).firstOrNull;
        if (clsNode != null && clsNode['courses'] is List) {
          for (final course in (clsNode['courses'] as List)) {
            final n = course['name']?.toString();
            if (n != null && n.trim().isNotEmpty) divSet.add(n.trim());
          }
        }
      } else {
        for (final cls in _academicHierarchy) {
          final cName = cls['name']?.toString();
          if (cName != null && availableClasses.contains(cName)) {
            if (cls['courses'] is List) {
              for (final course in (cls['courses'] as List)) {
                final n = course['name']?.toString();
                if (n != null && n.trim().isNotEmpty) divSet.add(n.trim());
              }
            }
          }
        }
      }
      final result = divSet.toList()..sort();
      return result.isNotEmpty ? result : divisions;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final scale = (screenWidth / 380.0).clamp(0.70, 1.0);

            InputDecoration dropdownDeco(String hint) {
              return InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: (11 * scale).clamp(9.0, 12.5),
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8 * scale,
                  vertical: (8 * scale).clamp(5.0, 10.0),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                isDense: true,
              );
            }

            TextStyle itemStyle() {
              return AppTheme.getFontStyle(
                fontSize: (11.5 * scale).clamp(9.5, 13.0),
                color: isDark ? Colors.white : Colors.black87,
              );
            }

            final availableSubDepts = getAvailableSubDepts(tempDepartment);
            final filteredClasses = getFilteredClasses(tempDepartment, tempSubDepartment);
            final filteredDivisions = getFilteredDivisions(tempClass, filteredClasses);

            return MovableResizableDialog(
              initialWidth: 500,
              initialHeight: 580,
              minWidth: 360,
              minHeight: 320,
              headerLeading: Container(
                padding: EdgeInsets.all(5 * scale),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.filter_alt_rounded, color: Colors.white, size: (20 * scale).clamp(16.0, 22.0)),
              ),
              title: Text(
                'Filter Students List',
                style: AppTheme.getFontStyle(
                  fontSize: (16 * scale).clamp(12.0, 18.0),
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              content: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. Department', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempDepartment,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Departments'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Departments', style: itemStyle())),
                          ..._allDepartments.where((d) => d['parent_id'] == null).map((d) => DropdownMenuItem<String?>(
                                value: d['id'].toString(),
                                child: Text(d['name'] ?? '', style: itemStyle()),
                              )),
                        ],
                        onChanged: (v) => setModalState(() {
                          tempDepartment = v;
                          tempSubDepartment = null;
                          final newClasses = getFilteredClasses(v, null);
                          if (tempClass != null && !newClasses.contains(tempClass)) {
                            tempClass = null;
                            tempDivision = null;
                          }
                          final newDivs = getFilteredDivisions(tempClass, newClasses);
                          if (tempDivision != null && !newDivs.contains(tempDivision)) {
                            tempDivision = null;
                          }
                        }),
                      ),
                      SizedBox(height: 10 * scale),

                      if (availableSubDepts.isNotEmpty) ...[
                        Text('2. Sub-Department', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                        SizedBox(height: 4 * scale),
                        DropdownButtonFormField<String?>(
                          key: ValueKey('subdept_${tempDepartment ?? 'none'}'),
                          initialValue: tempSubDepartment,
                          isExpanded: true,
                          dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                          style: itemStyle(),
                          decoration: dropdownDeco('All Sub-Departments'),
                          items: [
                            DropdownMenuItem<String?>(value: null, child: Text('All Sub-Departments', style: itemStyle())),
                            ...availableSubDepts.map((s) => DropdownMenuItem<String?>(
                                  value: s['id'].toString(),
                                  child: Text(s['name'] ?? '', style: itemStyle()),
                                )),
                          ],
                          onChanged: (v) => setModalState(() {
                            tempSubDepartment = v;
                            final newClasses = getFilteredClasses(tempDepartment, v);
                            if (tempClass != null && !newClasses.contains(tempClass)) {
                              tempClass = null;
                              tempDivision = null;
                            }
                            final newDivs = getFilteredDivisions(tempClass, newClasses);
                            if (tempDivision != null && !newDivs.contains(tempDivision)) {
                              tempDivision = null;
                            }
                          }),
                        ),
                        SizedBox(height: 10 * scale),
                      ],

                      Text('${availableSubDepts.isNotEmpty ? '3' : '2'}. Class', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('class_${tempDepartment ?? 'none'}_${tempSubDepartment ?? 'none'}'),
                        initialValue: tempClass,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Classes'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Classes', style: itemStyle())),
                          ...filteredClasses.map((cls) => DropdownMenuItem<String?>(
                                value: cls,
                                child: Text(cls, style: itemStyle()),
                              )),
                        ],
                        onChanged: (v) => setModalState(() {
                          tempClass = v;
                          final newDivs = getFilteredDivisions(v, filteredClasses);
                          if (tempDivision != null && !newDivs.contains(tempDivision)) {
                            tempDivision = null;
                          }
                        }),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '4' : '3'}. Division', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        key: ValueKey('div_${tempClass ?? 'none'}_${tempDepartment ?? 'none'}_${tempSubDepartment ?? 'none'}'),
                        initialValue: tempDivision,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Divisions'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Divisions', style: itemStyle())),
                          ...filteredDivisions.map((div) => DropdownMenuItem<String?>(
                                value: div,
                                child: Text(div, style: itemStyle()),
                              )),
                        ],
                        onChanged: (v) => setModalState(() => tempDivision = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '5' : '4'}. Village', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempVillage,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Villages'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Villages', style: itemStyle())),
                          ...villages.map((v) => DropdownMenuItem<String?>(value: v, child: Text(v, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempVillage = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '6' : '5'}. District', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempDistrict,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Districts'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Districts', style: itemStyle())),
                          ...districts.map((d) => DropdownMenuItem<String?>(value: d, child: Text(d, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempDistrict = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '7' : '6'}. State', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempState,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All States'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All States', style: itemStyle())),
                          ...states.map((st) => DropdownMenuItem<String?>(value: st, child: Text(st, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempState = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '8' : '7'}. Category', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempCategory,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Categories'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Categories', style: itemStyle())),
                          ...categories.map((cat) => DropdownMenuItem<String?>(value: cat, child: Text(cat, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempCategory = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '9' : '8'}. Gender', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempGender,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Genders'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Genders', style: itemStyle())),
                          ...filterGenders.map((g) => DropdownMenuItem<String?>(value: g.toLowerCase(), child: Text(g, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempGender = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '10' : '9'}. Status', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        initialValue: tempStatus,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Statuses'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Statuses', style: itemStyle())),
                          ...filterStatuses.map((st) => DropdownMenuItem<String?>(value: st.toLowerCase(), child: Text(st, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempStatus = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('${availableSubDepts.isNotEmpty ? '11' : '10'}. Age Range (Years)', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: minAgeCtrl,
                              keyboardType: TextInputType.number,
                              style: itemStyle(),
                              decoration: dropdownDeco('Min Age (e.g. 5)'),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6 * scale),
                            child: Text('-', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: maxAgeCtrl,
                              keyboardType: TextInputType.number,
                              style: itemStyle(),
                              decoration: dropdownDeco('Max Age (e.g. 18)'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: Container(
                padding: EdgeInsets.fromLTRB(14 * scale, 8 * scale, 14 * scale, 12 * scale),
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
                      onPressed: () {
                        setModalState(() {
                          tempDepartment = null;
                          tempSubDepartment = null;
                          tempClass = null;
                          tempVillage = null;
                          tempDistrict = null;
                          tempState = null;
                          tempCategory = null;
                          tempDivision = null;
                          tempGender = null;
                          tempStatus = null;
                          minAgeCtrl.clear();
                          maxAgeCtrl.clear();
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('Reset', style: TextStyle(color: Colors.red.shade400, fontSize: (11.5 * scale).clamp(9.0, 12.5))),
                    ),
                    SizedBox(width: 6 * scale),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(context.tr('cancel'), style: TextStyle(fontSize: (11.5 * scale).clamp(9.0, 12.5), color: isDark ? Colors.white70 : Colors.grey[700])),
                    ),
                    SizedBox(width: 6 * scale),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          _filterDepartment = tempDepartment;
                          _filterSubDepartment = tempSubDepartment;
                          _filterClass = tempClass;
                          _filterVillage = tempVillage;
                          _filterDistrict = tempDistrict;
                          _filterState = tempState;
                          _filterCategory = tempCategory;
                          _filterDivision = tempDivision;
                          _filterGender = tempGender;
                          _filterStatus = tempStatus;
                          _filterMinAge = minAgeCtrl.text.trim().isEmpty ? null : minAgeCtrl.text.trim();
                          _filterMaxAge = maxAgeCtrl.text.trim().isEmpty ? null : maxAgeCtrl.text.trim();
                        });
                        Navigator.pop(dialogContext);
                      },
                      child: Text('Apply Filters', style: TextStyle(fontSize: (11.5 * scale).clamp(9.0, 12.5), fontWeight: FontWeight.w600)),
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

  // ── Search & Filter Bar ──────────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark, bool isCompact, bool isWide, [List<Student> allStudents = const []]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: AppTheme.getFontStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: isCompact
                        ? '${context.tr('search')}...'
                        : context.tr('search_students_hint'),
                    hintStyle: AppTheme.getFontStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _showFilterDialog(context, allStudents),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _activeFilterCount > 0
                        ? AppTheme.primaryColor.withAlpha(isDark ? 50 : 25)
                        : (isDark ? Colors.white.withAlpha(8) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(8),
                    border: _activeFilterCount > 0
                        ? Border.all(color: AppTheme.primaryColor)
                        : Border.all(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _activeFilterCount > 0
                            ? Icons.filter_alt_rounded
                            : Icons.filter_alt_outlined,
                        size: 18,
                        color: _activeFilterCount > 0
                            ? AppTheme.primaryColor
                            : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _activeFilterCount > 0 ? 'Filter ($_activeFilterCount)' : 'Filter',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _activeFilterCount > 0
                              ? AppTheme.primaryColor
                              : (isDark ? Colors.grey.shade300 : const Color(0xFF1A1A2E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Active Filter Chips Bar
        if (_activeFilterCount > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Active Filters:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              if (_filterDepartment != null)
                _buildActiveFilterChip(
                  'Dept: ${_allDepartments.where((d) => d['id']?.toString() == _filterDepartment).firstOrNull?['name'] ?? _filterDepartment}',
                  () => setState(() {
                    _filterDepartment = null;
                    _filterSubDepartment = null;
                  }),
                ),
              if (_filterSubDepartment != null)
                _buildActiveFilterChip(
                  'Sub-Dept: ${_allDepartments.where((d) => d['id']?.toString() == _filterSubDepartment).firstOrNull?['name'] ?? _filterSubDepartment}',
                  () => setState(() => _filterSubDepartment = null),
                ),
              if (_filterClass != null)
                _buildActiveFilterChip('Class: $_filterClass', () => setState(() => _filterClass = null)),
              if (_filterVillage != null)
                _buildActiveFilterChip('Village: $_filterVillage', () => setState(() => _filterVillage = null)),
              if (_filterDistrict != null)
                _buildActiveFilterChip('District: $_filterDistrict', () => setState(() => _filterDistrict = null)),
              if (_filterState != null)
                _buildActiveFilterChip('State: $_filterState', () => setState(() => _filterState = null)),
              if (_filterCategory != null)
                _buildActiveFilterChip('Category: $_filterCategory', () => setState(() => _filterCategory = null)),
              if (_filterDivision != null)
                _buildActiveFilterChip('Division: $_filterDivision', () => setState(() => _filterDivision = null)),
              if (_filterGender != null)
                _buildActiveFilterChip('Gender: $_filterGender', () => setState(() => _filterGender = null)),
              if (_filterStatus != null)
                _buildActiveFilterChip('Status: $_filterStatus', () => setState(() => _filterStatus = null)),
              if (_filterMinAge != null || _filterMaxAge != null)
                _buildActiveFilterChip(
                  'Age: ${_filterMinAge ?? '0'} - ${_filterMaxAge ?? '∞'} Yrs',
                  () => setState(() {
                    _filterMinAge = null;
                    _filterMaxAge = null;
                  }),
                ),
              InkWell(
                onTap: _clearAllFilters,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Clear All',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Card Grid View ────────────────────────────────────────────────────────
  Widget _buildCardGrid(
    List<Student> students,
    bool isDark,
    bool isCompact,
    bool isMedium,
    bool isWide,
  ) {
    if (isCompact) {
      return ListView.separated(
        key: const PageStorageKey<String>('students_card_list_view'),
        itemCount: students.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _StudentCard(
            student: students[index],
            isDark: isDark,
            deptDisplay: _getStudentAcademicDisplay(students[index]),
            isSelectionMode: _isSelectionMode,
            isSelected: _selectedStudentIds.contains(students[index].id),
            onSelectChanged: (val) => _toggleSelection(students[index].id),
            onView: () => _openStudentProfile(students[index].id, initialStudent: students[index]),
            onEdit: () => _showAddEditDialog(students[index]),
            onDelete: () => _deleteStudent(students[index]),
          );
        },
      );
    }
    final crossAxis = isMedium ? 2 : isWide ? 3 : 2;
    return GridView.builder(
      key: const PageStorageKey<String>('students_card_grid_view'),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxis,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isWide ? 3.0 : 2.8,
      ),
      itemCount: students.length,
      itemBuilder: (context, index) {
        return _StudentCard(
          student: students[index],
          isDark: isDark,
          deptDisplay: _getStudentAcademicDisplay(students[index]),
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedStudentIds.contains(students[index].id),
          onSelectChanged: (val) => _toggleSelection(students[index].id),
          onView: () => _openStudentProfile(students[index].id, initialStudent: students[index]),
          onEdit: () => _showAddEditDialog(students[index]),
          onDelete: () => _deleteStudent(students[index]),
        );
      },
    );
  }
  TextStyle _mobileHeaderStyle(bool isDark, double scale) {
    return AppTheme.getFontStyle(
      fontSize: 11 * scale,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white70 : const Color(0xFF0D6B4E),
    );
  }

  TextStyle _mobileCellStyle(bool isDark, double scale, {bool bold = false, bool muted = false, Color? color}) {
    return AppTheme.getFontStyle(
      fontSize: 11 * scale,
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      color: color ?? (muted
          ? (isDark ? Colors.grey.shade500 : Colors.grey.shade600)
          : (isDark ? Colors.white : const Color(0xFF1A1A2E))),
    );
  }

  // ── Table View ────────────────────────────────────────────────────────────
  Widget _buildTableView(List<Student> students, bool isDark, bool isWide) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 700;
    final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

    if (isCompact) {
      // Mobile full 8-column scrollable table with touch & mouse drag support
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(bottom: 12 * scale),
              child: Container(
                width: 900 * scale,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(12 * scale),
                  border: Border.all(
                    color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
                  ),
                  boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 8 * scale,
                offset: Offset(0, 2 * scale),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E2E3E), const Color(0xFF2A2A3E)]
                          : [const Color(0xFF0D6B4E).withAlpha(20), const Color(0xFF14A06E).withAlpha(10)],
                    ),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 12 * scale),
                  child: Row(
                    children: [
                      if (_isSelectionMode)
                        SizedBox(
                          width: 36 * scale,
                          child: Center(child: Text('', style: TextStyle(fontSize: 11 * scale))),
                        ),
                      SizedBox(width: 36 * scale, child: Text('#', style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 90 * scale, child: Text(context.tr('gr_no'), style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 140 * scale, child: Text(context.tr('name'), style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 130 * scale, child: Text(context.tr('village'), style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 80 * scale, child: Text(context.tr('class_name'), style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 95 * scale, child: Text(context.tr('category'), style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 105 * scale, child: Text(context.tr('mobile'), style: _mobileHeaderStyle(isDark, scale))),
                      SizedBox(width: 100 * scale, child: Center(child: Text(context.tr('status'), style: _mobileHeaderStyle(isDark, scale)))),
                      SizedBox(width: 110 * scale, child: Center(child: Text(context.tr('actions'), style: _mobileHeaderStyle(isDark, scale)))),
                    ],
                  ),
                ),
                // Rows
                ...students.asMap().entries.map((entry) {
                  final index = entry.key;
                  final s = entry.value;
                  final isOdd = index.isOdd;
                  final academicDisplay = _getStudentAcademicDisplay(s);
                  return Container(
                    decoration: BoxDecoration(
                      color: isOdd
                          ? (isDark ? Colors.white.withAlpha(3) : Colors.grey.shade50)
                          : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? Colors.white.withAlpha(6) : Colors.grey.shade100,
                          width: 1,
                        ),
                      ),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 10 * scale),
                    child: Row(
                      children: [
                        if (_isSelectionMode)
                          SizedBox(
                            width: 36 * scale,
                            child: Checkbox(
                              value: _selectedStudentIds.contains(s.id),
                              onChanged: (val) => _toggleSelection(s.id),
                            ),
                          ),
                        SizedBox(
                          width: 36 * scale,
                          child: Text('${index + 1}', style: _mobileCellStyle(isDark, scale, muted: true)),
                        ),
                        SizedBox(
                          width: 90 * scale,
                          child: Text(s.grNo ?? s.registrationNumber, style: _mobileCellStyle(isDark, scale, bold: true, color: AppTheme.primaryColor)),
                        ),
                        SizedBox(
                          width: 140 * scale,
                          child: Text(_displayName(s), style: _mobileCellStyle(isDark, scale, bold: true), overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 130 * scale,
                          child: Text(s.village ?? '-', style: _mobileCellStyle(isDark, scale), overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 105 * scale,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${s.className ?? 'N/A'}${s.division != null && s.division!.isNotEmpty ? ' (${s.division})' : ''}',
                                style: _mobileCellStyle(isDark, scale),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (academicDisplay != null)
                                Text(
                                  academicDisplay,
                                  style: AppTheme.getFontStyle(
                                    fontSize: (8.5 * scale).clamp(7.0, 11.0),
                                    color: const Color(0xFF1565C0),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 95 * scale,
                          child: Text(s.category ?? 'N/A', style: _mobileCellStyle(isDark, scale), overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 105 * scale,
                          child: Text(s.mobileNo ?? '-', style: _mobileCellStyle(isDark, scale), overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 100 * scale,
                          child: Center(child: _StatusBadge(student: s)),
                        ),
                        SizedBox(
                          width: 110 * scale,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () => _openStudentProfile(s.id, initialStudent: s),
                                child: Tooltip(
                                  message: 'View Profile',
                                  child: Icon(Icons.remove_red_eye_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                                ),
                              ),
                              SizedBox(width: 8 * scale),
                              GestureDetector(
                                onTap: () => _showAddEditDialog(s),
                                child: Tooltip(
                                  message: 'Edit Student',
                                  child: Icon(Icons.edit_rounded, size: 16 * scale, color: const Color(0xFF1565C0)),
                                ),
                              ),
                              SizedBox(width: 8 * scale),
                              GestureDetector(
                                onTap: () {
                                  if (_ensureFeatureAccess('students_id_card', 'ID Card Builder & Designer')) {
                                    StudentIdCardBuilderDialog.show(context, s);
                                  }
                                },
                                child: Tooltip(
                                  message: 'Print ID Card',
                                  child: Icon(Icons.badge_rounded, size: 16 * scale, color: const Color(0xFF0D6B4E)),
                                ),
                              ),
                              SizedBox(width: 8 * scale),
                              GestureDetector(
                                onTap: () {
                                  if (_ensureFeatureAccess('students_delete', 'Delete / Archive Student')) {
                                    _deleteStudent(s);
                                  }
                                },
                                child: Tooltip(
                                  message: 'Delete Student',
                                  child: Icon(Icons.delete_rounded, size: 16 * scale, color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // Footer
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
                  child: Text(
                    'Showing ${students.length} students',
                    style: AppTheme.getFontStyle(
                      fontSize: 11 * scale,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    ),
    );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Table Header
            Container(
              color: isDark
                  ? const Color(0xFF2A2A3E)
                  : AppTheme.primaryColor.withAlpha(12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (_isSelectionMode)
                    const SizedBox(
                      width: 48,
                      child: Center(child: _TableHeader('', flex: 1)),
                    ),
                  const _TableHeader('#', flex: 1),
                  _TableHeader(context.tr('gr_no').toUpperCase(), flex: 2),
                  const _TableHeader('ROLL NO', flex: 2),
                  _TableHeader(context.tr('name').toUpperCase(), flex: 4),
                  _TableHeader(context.tr('class_name').toUpperCase(), flex: 3),
                  if (!isCompact) _TableHeader(context.tr('village').toUpperCase(), flex: 3),
                  if (!isCompact) _TableHeader(context.tr('category').toUpperCase(), flex: 2),
                  if (isWide) _TableHeader(context.tr('mobile').toUpperCase(), flex: 3),
                  _TableHeader(context.tr('status').toUpperCase(), flex: 2),
                  _TableHeader(context.tr('actions').toUpperCase(), flex: 3, center: true),
                ],
              ),
            ),
            // Table Rows
            Expanded(
              child: ListView.separated(
                key: const PageStorageKey<String>('students_desktop_table_view'),
                itemCount: students.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withAlpha(6)
                      : Colors.grey.shade100,
                ),
                itemBuilder: (context, index) {
                  final s = students[index];
                  final isOdd = index.isOdd;
                  final academicDisplay = _getStudentAcademicDisplay(s);

                  return Container(
                    color: isOdd
                        ? (isDark
                              ? Colors.white.withAlpha(3)
                              : Colors.grey.shade50)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        if (_isSelectionMode)
                          SizedBox(
                            width: 48,
                            child: Checkbox(
                              value: _selectedStudentIds.contains(s.id),
                              onChanged: (val) => _toggleSelection(s.id),
                            ),
                          ),
                        _TableCell(
                          '${index + 1}',
                          flex: 1,
                          muted: true,
                          isDark: isDark,
                        ),
                        _TableCell(
                          s.grNo ?? s.registrationNumber,
                          flex: 2,
                          bold: true,
                          isDark: isDark,
                          color: AppTheme.primaryColor,
                        ),
                        _TableCell(
                          s.rollNumber ?? '-',
                          flex: 2,
                          bold: true,
                          isDark: isDark,
                        ),
                        // Name column with circle avatar
                        Expanded(
                          flex: 4,
                          child: Row(
                            children: [
                              _StudentAvatar(
                                student: s,
                                isDark: isDark,
                                size: 32,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _displayName(s),
                                  style: AppTheme.getFontStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1A2E),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Class / Academic column
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${s.className ?? 'N/A'}${s.division != null && s.division!.isNotEmpty ? ' (${s.division})' : ''}',
                                style: AppTheme.getFontStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white70 : const Color(0xFF1A1A2E),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (academicDisplay != null)
                                Text(
                                  academicDisplay,
                                  style: AppTheme.getFontStyle(
                                    fontSize: 10,
                                    color: const Color(0xFF1565C0),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (!isCompact)
                          _TableCell(
                            s.village ?? '-',
                            flex: 3,
                            isDark: isDark,
                          ),
                        if (!isCompact)
                          _TableCell(
                            s.category ?? 'N/A',
                            flex: 2,
                            isDark: isDark,
                          ),
                        if (isWide)
                          _TableCell(
                            s.mobileNo ?? '-',
                            flex: 3,
                            isDark: isDark,
                          ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusBadge(student: s),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove_red_eye_rounded, size: 16, color: AppTheme.primaryColor),
                                tooltip: context.tr('view'),
                                onPressed: () => _openStudentProfile(s.id, initialStudent: s),
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 16, color: Color(0xFF1565C0)),
                                tooltip: context.tr('edit'),
                                onPressed: () => _showAddEditDialog(s),
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.badge_rounded, size: 16, color: Color(0xFF0D6B4E)),
                                tooltip: 'Print ID Card',
                                onPressed: () {
                                  if (_ensureFeatureAccess('students_id_card', 'ID Card Builder & Designer')) {
                                    StudentIdCardBuilderDialog.show(context, s);
                                  }
                                },
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                                tooltip: context.tr('delete'),
                                onPressed: () {
                                  if (_ensureFeatureAccess('students_delete', 'Delete / Archive Student')) {
                                    _deleteStudent(s);
                                  }
                                },
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withAlpha(8)
                        : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Showing ${students.length} student${students.length != 1 ? 's' : ''}',
                    style: AppTheme.getFontStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade500,
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

  // ── Error State ───────────────────────────────────────────────────────────
  Widget _buildError(String message) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withAlpha(15),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 28,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: AppTheme.getFontStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.read<StudentsBloc>().add(LoadStudents()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withAlpha(15),
              ),
              child: Icon(
                Icons.school_rounded,
                size: 32,
                color: AppTheme.primaryColor.withAlpha(120),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _searchQuery.isEmpty
                  ? 'No students yet'
                  : 'No results for "$_searchQuery"',
              style: AppTheme.getFontStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isEmpty
                  ? 'Click "Add Student" to create your first entry'
                  : 'Try a different search term',
              style: AppTheme.getFontStyle(fontSize: 12.5, color: Colors.grey),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(context.tr('add_student')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Helper Widgets ───────────────────────────────────────────────────────────

class StudentStatCardConfig {
  final String id;
  final String type; // 'total', 'status', 'gender', 'category', 'department', 'condition', 'with_mobile', 'without_mobile', 'with_aadhaar', 'without_aadhaar'
  final String label;
  final String? filterValue;
  final int iconCodePoint;
  final String? iconFontFamily;
  final int colorValue;

  const StudentStatCardConfig({
    required this.id,
    required this.type,
    required this.label,
    this.filterValue,
    this.iconCodePoint = 0xe491,
    this.iconFontFamily,
    this.colorValue = 0xFF0D6B4E,
  });

  IconData get icon => IconData(iconCodePoint, fontFamily: iconFontFamily ?? 'MaterialIcons');
  Color get color => Color(colorValue);

  StudentStatCardConfig copyWith({
    String? id,
    String? type,
    String? label,
    String? filterValue,
    int? iconCodePoint,
    String? iconFontFamily,
    int? colorValue,
  }) {
    return StudentStatCardConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      filterValue: filterValue ?? this.filterValue,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'filterValue': filterValue,
    'iconCodePoint': iconCodePoint,
    'iconFontFamily': iconFontFamily,
    'colorValue': colorValue,
  };

  factory StudentStatCardConfig.fromJson(Map<String, dynamic> json) {
    return StudentStatCardConfig(
      id: json['id'] as String? ?? 'card',
      type: json['type'] as String? ?? 'total',
      label: json['label'] as String? ?? 'Total',
      filterValue: json['filterValue'] as String?,
      iconCodePoint: json['iconCodePoint'] as int? ?? 0xe491,
      iconFontFamily: json['iconFontFamily'] as String?,
      colorValue: json['colorValue'] as int? ?? 0xFF0D6B4E,
    );
  }
}

class _StatInfo {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onSettingsTap;
  const _StatInfo(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.onTap,
    this.onSettingsTap,
  });
}

class _MiniStatCard extends StatelessWidget {
  final _StatInfo info;
  final bool isDark;
  final double scale;

  const _MiniStatCard({
    required this.info,
    required this.isDark,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: info.onTap,
        onLongPress: info.onSettingsTap,
        borderRadius: BorderRadius.circular(12 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 10 * scale,
            vertical: 8 * scale,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(12 * scale),
            border: Border.all(
              color: isDark ? info.color.withAlpha(35) : info.color.withAlpha(25),
            ),
            boxShadow: [
              BoxShadow(
                color: info.color.withAlpha(isDark ? 16 : 10),
                blurRadius: 10 * scale,
                offset: Offset(0, 3 * scale),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34 * scale,
                height: 34 * scale,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10 * scale),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      info.color.withAlpha(isDark ? 55 : 30),
                      info.color.withAlpha(isDark ? 35 : 15),
                    ],
                  ),
                ),
                child: Icon(info.icon, color: info.color, size: 18 * scale),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      info.value,
                      style: AppTheme.getFontStyle(
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        height: 1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      info.label,
                      style: AppTheme.getFontStyle(
                        fontSize: 10 * scale,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (info.onSettingsTap != null)
                GestureDetector(
                  onTap: info.onSettingsTap,
                  child: Padding(
                    padding: EdgeInsets.all(2 * scale),
                    child: Icon(
                      Icons.settings_outlined,
                      size: 13 * scale,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  final bool? isDark;
  const _ViewToggle({required this.mode, required this.onChanged, this.isDark});

  @override
  Widget build(BuildContext context) {
    final effectiveDark = isDark ?? (Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        color: effectiveDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleBtn(
            icon: Icons.view_list_rounded,
            active: mode == 'table',
            isDark: effectiveDark,
            onTap: () => onChanged('table'),
          ),
          _ToggleBtn(
            icon: Icons.view_module_rounded,
            active: mode == 'card',
            isDark: effectiveDark,
            onTap: () => onChanged('card'),
          ),
        ],
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;
  const _ToggleBtn({
    required this.icon,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? (isDark
                    ? AppTheme.primaryColor.withAlpha(60)
                    : AppTheme.primaryColor)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active
              ? Colors.white
              : (isDark ? Colors.grey.shade500 : Colors.grey.shade500),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String label;
  final int flex;
  final bool center;
  const _TableHeader(this.label, {required this.flex, this.center = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: AppTheme.getFontStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryColor,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final int flex;
  final bool bold;
  final bool muted;
  final bool isDark;
  final Color? color;
  const _TableCell(
    this.text, {
    required this.flex,
    required this.isDark,
    this.bold = false,
    this.muted = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppTheme.getFontStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color:
              color ??
              (muted
                  ? (isDark ? Colors.grey.shade600 : Colors.grey.shade400)
                  : (isDark
                        ? Colors.white.withAlpha(220)
                        : const Color(0xFF3A3A5C))),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Student student;
  const _StatusBadge({required this.student});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 380.0).clamp(0.70, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayStatus = student.studentStatus ?? (student.isActive ? 'Active' : 'Inactive');

    final Color mainColor = StudentStatusSettings.getStatusColorSync(displayStatus);
    final Color bgColor = mainColor.withAlpha(isDark ? 40 : 25);
    final Color borderColor = mainColor.withAlpha(isDark ? 90 : 70);

    return Tooltip(
      message: 'Click to change status ($displayStatus)',
      child: InkWell(
        onTap: () => _showQuickStatusPicker(context, student),
        borderRadius: BorderRadius.circular(16 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: (8 * scale).clamp(6.0, 10.0),
            vertical: (3 * scale).clamp(2.0, 4.5),
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(
              color: borderColor,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: (7 * scale).clamp(6.0, 8.0),
                height: (7 * scale).clamp(6.0, 8.0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor,
                ),
              ),
              SizedBox(width: 4 * scale),
              Text(
                displayStatus,
                style: AppTheme.getFontStyle(
                  fontSize: (11.5 * scale).clamp(10.0, 12.5),
                  fontWeight: FontWeight.w700,
                  color: isDark ? mainColor.withAlpha(240) : mainColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showQuickStatusPicker(BuildContext context, Student student) async {
  final statuses = await StudentStatusSettings.getStatuses();
  if (!context.mounted) return;

  final currentSt = student.studentStatus ?? (student.isActive ? 'Active' : 'Inactive');

  showDialog(
    context: context,
    builder: (dialogCtx) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return MovableResizableDialog(
        initialWidth: 460,
        initialHeight: 320,
        minWidth: 340,
        minHeight: 250,
        headerLeading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(25),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.label_important_rounded, color: Colors.white, size: 18),
        ),
        title: Text(
          'Status: ${student.fullName}',
          style: AppTheme.getFontStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        content: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select status category:',
                  style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: statuses.map((st) {
                    final isSelected = st.toLowerCase() == currentSt.toLowerCase();
                    final col = StudentStatusSettings.getStatusColorSync(st);
                    return ChoiceChip(
                      avatar: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : col,
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text(st),
                      selected: isSelected,
                      selectedColor: col,
                      backgroundColor: col.withAlpha(isDark ? 35 : 20),
                      side: BorderSide(color: isSelected ? col : col.withAlpha(80)),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white : col),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                      onSelected: (val) {
                        if (val) {
                          Navigator.pop(dialogCtx);
                          final updated = student.copyWith(
                            studentStatus: st,
                            isActive: st.toLowerCase() != 'inactive',
                          );
                          context.read<StudentsBloc>().add(UpdateStudent(updated));
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        actions: Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  ManageStatusCategoriesDialog.show(context);
                },
                icon: const Icon(Icons.settings_suggest_rounded, size: 16, color: Color(0xFF0D6B4E)),
                label: const Text('⚙️ Manage Categories', style: TextStyle(color: Color(0xFF0D6B4E), fontSize: 12)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _StudentCard extends StatelessWidget {
  final Student student;
  final bool isDark;
  final double scale;
  final String? deptDisplay;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectChanged;

  const _StudentCard({
    required this.student,
    required this.isDark,
    this.scale = 1.0,
    this.deptDisplay,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isSelectionMode
              ? () => onSelectChanged?.call(!isSelected)
              : onView,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              if (isSelectionMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: onSelectChanged,
                ),
                const SizedBox(width: 8),
              ],
              // Avatar
              _StudentAvatar(
                student: student,
                isDark: isDark,
                size: 44,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _StudentsScreenState._displayName(student),
                      style: AppTheme.getFontStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // GR No Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(isDark ? 30 : 12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'GR: ${student.grNo ?? student.registrationNumber}',
                            style: AppTheme.getFontStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        // Roll No Badge
                        if (student.rollNumber != null && student.rollNumber!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.amber.shade900.withAlpha(80)
                                  : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? Colors.amber.shade700 : Colors.amber.shade400,
                              ),
                            ),
                            child: Text(
                              'Roll: ${student.rollNumber}',
                              style: AppTheme.getFontStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.amber.shade200
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        // Class & Division Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${student.className ?? 'N/A'}${student.division != null && student.division!.isNotEmpty ? ' (${student.division})' : ''}',
                            style: AppTheme.getFontStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        // Department Badge
                        if (deptDisplay != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0).withAlpha(isDark ? 30 : 15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              deptDisplay!,
                              style: AppTheme.getFontStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1565C0),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        // Status Badge
                        _StatusBadge(student: student),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) {
                  if (value == 'view') onView();
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                  if (value == 'id_card') {
                    final licenseState = context.read<LicenseCubit>().state;
                    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
                    if (!license.hasFeatureAccess('students_id_card')) {
                      UpgradePlanDialog.show(context, highlightModule: 'ID Card Builder & Designer');
                    } else {
                      StudentIdCardBuilderDialog.show(context, student);
                    }
                  }
                  if (value == 'status') {
                    final statusStr = student.studentStatus?.toLowerCase() ?? 'active';
                    final isAct = statusStr == 'active' || student.isActive;
                    final updated = student.copyWith(
                      studentStatus: isAct ? 'Inactive' : 'Active',
                      isActive: !isAct,
                    );
                    context.read<StudentsBloc>().add(UpdateStudent(updated));
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.remove_red_eye_rounded, color: AppTheme.primaryColor, size: 16),
                        const SizedBox(width: 8),
                        Text(context.tr('view')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_rounded, color: Color(0xFF1565C0), size: 16),
                        const SizedBox(width: 8),
                        Text(context.tr('edit')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'id_card',
                    child: Row(
                      children: [
                        const Icon(Icons.badge_rounded, color: Color(0xFF0D6B4E), size: 16),
                        const SizedBox(width: 8),
                        const Text('Print ID Card'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'status',
                    child: Row(
                      children: [
                        Icon(
                          (student.studentStatus?.toLowerCase() == 'active' || student.isActive)
                              ? Icons.cancel_outlined
                              : Icons.check_circle_outline,
                          color: (student.studentStatus?.toLowerCase() == 'active' || student.isActive)
                              ? Colors.red
                              : Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (student.studentStatus?.toLowerCase() == 'active' || student.isActive)
                              ? 'Mark Inactive'
                              : 'Mark Active',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_rounded, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text(context.tr('delete'), style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}

class _ExcelImportModal extends StatefulWidget {
  final StudentRepository studentRepository;
  final VoidCallback onImportSuccess;

  const _ExcelImportModal({
    required this.studentRepository,
    required this.onImportSuccess,
  });

  @override
  State<_ExcelImportModal> createState() => _ExcelImportModalState();
}

class _ExcelImportModalState extends State<_ExcelImportModal> {
  bool _isImporting = false;
  ImportResult? _result;

  Future<void> _pickAndImport() async {
    final picker = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
    );

    if (picker == null || picker.files.isEmpty || picker.files.single.path == null) {
      return;
    }

    setState(() {
      _isImporting = true;
      _result = null;
    });

    try {
      final file = File(picker.files.single.path!);
      final res = await StudentExcelService.importStudentsFromCsv(
        file: file,
        repository: widget.studentRepository,
      );

      if (mounted) {
        setState(() {
          _result = res;
          _isImporting = false;
        });
        if (res.importedCount > 0) {
          widget.onImportSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _result = ImportResult(
            totalRows: 0,
            importedCount: 0,
            skippedCount: 0,
            errors: ['Failed to read or parse file: $e'],
          );
        });
      }
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final path = await StudentExcelService.saveSampleTemplate();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sample Excel Template saved: $path'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () {
                launchUrl(Uri.file(path));
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save sample template: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MovableResizableDialog(
      initialWidth: 540,
      initialHeight: 520,
      minWidth: 380,
      minHeight: 320,
      headerLeading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.file_upload_rounded, color: Colors.white, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bulk Import Students (Excel / CSV)',
            style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            'Import multiple student records instantly',
            style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.white.withAlpha(180)),
          ),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isImporting) ...[
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 14),
                        Text('Importing students from file... Please wait.'),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  elevation: 0,
                  color: isDark ? const Color(0xFF28283C) : Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.note_add_rounded, color: Color(0xFF0D6B4E)),
                          title: const Text('Pick Excel / CSV File', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Select .csv or .xlsx file containing student records'),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                          onTap: _pickAndImport,
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.download_rounded, color: Colors.blue),
                          title: const Text('Download Sample Excel Template', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Download standard column headers format file'),
                          trailing: const Icon(Icons.downloading_rounded, size: 20, color: Colors.blue),
                          onTap: _downloadTemplate,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_result != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _result!.importedCount > 0
                          ? Colors.green.withValues(alpha: isDark ? 0.2 : 0.1)
                          : Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _result!.importedCount > 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _result!.importedCount > 0 ? Icons.check_circle_rounded : Icons.error_rounded,
                              color: _result!.importedCount > 0 ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Import Summary',
                              style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('• Total Rows: ${_result!.totalRows}'),
                        Text('• Successfully Imported / Updated: ${_result!.importedCount}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        Text('• Skipped / Failed: ${_result!.skippedCount}'),
                        if (_result!.errors.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Issues encountered:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade400)),
                          const SizedBox(height: 4),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              child: Text(
                                _result!.errors.take(8).join('\n'),
                                style: const TextStyle(fontSize: 10.5, color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
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
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkAssignStatusModal extends StatefulWidget {
  final List<String> studentIds;
  final StudentRepository repository;
  final VoidCallback onSuccess;

  const _BulkAssignStatusModal({
    required this.studentIds,
    required this.repository,
    required this.onSuccess,
  });

  @override
  State<_BulkAssignStatusModal> createState() => _BulkAssignStatusModalState();
}

class _BulkAssignStatusModalState extends State<_BulkAssignStatusModal> {
  List<String> _statuses = [];
  String _selectedStatus = 'Active';
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final list = await StudentStatusSettings.getStatuses();
    if (mounted) {
      setState(() {
        _statuses = list;
        if (!_statuses.contains(_selectedStatus) && _statuses.isNotEmpty) {
          _selectedStatus = _statuses.first;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _applyStatus() async {
    setState(() => _isSubmitting = true);
    try {
      await widget.repository.bulkAssignStatus(widget.studentIds, _selectedStatus);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to "$_selectedStatus" for ${widget.studentIds.length} students'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openManageCategories() async {
    await ManageStatusCategoriesDialog.show(context);
    _loadStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MovableResizableDialog(
      initialWidth: 500,
      initialHeight: 400,
      minWidth: 380,
      minHeight: 280,
      headerLeading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.label_important_rounded, color: Colors.white, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bulk Assign Status',
            style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            'Assign status to ${widget.studentIds.length} selected students',
            style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.white.withAlpha(180)),
          ),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text(
                  'Select Status Category:',
                  style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _statuses.map((st) {
                    final isSelected = st == _selectedStatus;
                    final col = StudentStatusSettings.getStatusColorSync(st);
                    return ChoiceChip(
                      avatar: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : col,
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text(st),
                      selected: isSelected,
                      selectedColor: col,
                      backgroundColor: col.withAlpha(isDark ? 35 : 20),
                      side: BorderSide(color: isSelected ? col : col.withAlpha(80)),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white : col),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedStatus = st);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _openManageCategories,
                  icon: const Icon(Icons.palette_rounded, size: 16, color: Color(0xFF0D6B4E)),
                  label: const Text('⚙️ Manage Statuses & Colors', style: TextStyle(color: Color(0xFF0D6B4E))),
                ),
              ],
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
              onPressed: _isSubmitting || _isLoading ? null : _applyStatus,
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: Text('Apply to (${widget.studentIds.length})'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6B4E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkPromoteModal extends StatefulWidget {
  final List<Student> selectedStudents;
  final StudentRepository repository;
  final VoidCallback onSuccess;

  const _BulkPromoteModal({
    required this.selectedStudents,
    required this.repository,
    required this.onSuccess,
  });

  @override
  State<_BulkPromoteModal> createState() => _BulkPromoteModalState();
}

class _BulkPromoteModalState extends State<_BulkPromoteModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _academicYearController;
  late TextEditingController _hijriYearController;
  late TextEditingController _divisionController;
  late TextEditingController _remarksController;

  String _selectedStatus = 'Promoted';
  String? _selectedClass;
  List<String> _classes = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _academicYearController = TextEditingController(text: '${now.year}-${now.year + 1}');
    _hijriYearController = TextEditingController(text: '${now.year - 579}-${now.year - 578} H');
    _divisionController = TextEditingController();
    _remarksController = TextEditingController();
    _loadClasses();
  }

  @override
  void dispose() {
    _academicYearController.dispose();
    _hijriYearController.dispose();
    _divisionController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final rawList = await DatabaseHelper().getDistinctClassNames();
      if (mounted) {
        final list = <String>[];
        final seen = <String>{};
        for (final c in rawList) {
          final trimmed = c.trim();
          if (trimmed.isNotEmpty && !seen.contains(trimmed.toLowerCase())) {
            seen.add(trimmed.toLowerCase());
            list.add(trimmed);
          }
        }

        setState(() {
          _classes = list;
          if (_classes.isNotEmpty) {
            _selectedClass = _classes.first;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyPromotion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final targetClass = (_selectedStatus == 'Farigh')
          ? 'Farigh'
          : (_selectedClass ?? 'Promoted Class');

      await widget.repository.bulkPromoteStudents(
        students: widget.selectedStudents,
        academicYear: _academicYearController.text.trim(),
        academicYearHijri: _hijriYearController.text.trim().isNotEmpty ? _hijriYearController.text.trim() : null,
        targetClass: targetClass,
        targetDivision: _divisionController.text.trim().isNotEmpty ? _divisionController.text.trim() : null,
        status: _selectedStatus,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedStatus == 'Farigh'
                  ? 'Successfully marked ${widget.selectedStudents.length} students as Farigh (Graduated)!'
                  : 'Successfully promoted ${widget.selectedStudents.length} students to "$targetClass" for ${_academicYearController.text.trim()}!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to promote students: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MovableResizableDialog(
      initialWidth: 540,
      initialHeight: 560,
      minWidth: 420,
      minHeight: 440,
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
            'Annual Promotion (Saalana Taraqqi)',
            style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            'Promote & archive ${widget.selectedStudents.length} selected students',
            style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.white.withAlpha(180)),
          ),
        ],
      ),
      content: _isLoading
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
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
                        color: isDark ? Colors.white.withAlpha(10) : const Color(0xFFE1F5FE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFB3E5FC)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0288D1), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Automated Academic Archive',
                                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Selected ${widget.selectedStudents.length} students ki is saal ki attendance aur exam marks automatic record banke save ho jayenge, aur student aagli class me darj ho jayenge.',
                                  style: AppTheme.getFontStyle(fontSize: 11, color: isDark ? Colors.white70 : const Color(0xFF01579B)),
                                ),
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
                        labelText: 'Action / Promotion Type *',
                        prefixIcon: Icon(Icons.trending_up_rounded, size: 18),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Promoted', child: Text('Promote to Next Class (Aagli Jama\'at)')),
                        DropdownMenuItem(value: 'Farigh', child: Text('Graduate / Farigh (فارغ)')),
                        DropdownMenuItem(value: 'Repeated', child: Text('Repeat Current Class (Dobaara Usi me)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedStatus = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    if (_selectedStatus != 'Farigh') ...[
                      Builder(
                        builder: (context) {
                          final distinctClasses = _classes
                              .map((c) => c.trim())
                              .where((c) => c.isNotEmpty)
                              .toSet()
                              .toList();

                          final currentValue = distinctClasses.contains(_selectedClass)
                              ? _selectedClass
                              : (distinctClasses.isNotEmpty ? distinctClasses.first : null);

                          return DropdownButtonFormField<String>(
                            initialValue: currentValue,
                            decoration: const InputDecoration(
                              labelText: 'Target Class *',
                              prefixIcon: Icon(Icons.class_outlined, size: 18),
                            ),
                            items: distinctClasses.map((c) {
                              return DropdownMenuItem(value: c, child: Text(c));
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedClass = val);
                            },
                            validator: (v) => (_selectedStatus != 'Farigh' && (v == null || v.isEmpty))
                                ? 'Please select target class'
                                : null,
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _divisionController,
                        decoration: const InputDecoration(
                          labelText: 'Target Division (Optional)',
                          hintText: 'Leave empty to keep existing divisions',
                          prefixIcon: Icon(Icons.grid_view_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _remarksController,
                      decoration: const InputDecoration(
                        labelText: 'Remarks / Notes (Optional)',
                        hintText: 'e.g. Annual Promotion 2026',
                        prefixIcon: Icon(Icons.note_alt_outlined, size: 18),
                      ),
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
              onPressed: _isSubmitting || _isLoading ? null : _applyPromotion,
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upgrade_rounded, size: 18),
              label: Text('Promote (${widget.selectedStudents.length}) Students'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0288D1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentToolItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String badgeText;
  final String buttonLabel;
  final VoidCallback onTap;

  const _StudentToolItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.badgeText,
    required this.buttonLabel,
    required this.onTap,
  });
}

class _StudentAvatar extends StatelessWidget {
  final Student student;
  final bool isDark;
  final double size;

  const _StudentAvatar({
    required this.student,
    required this.isDark,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final photo = student.photoPath?.trim();
    final hasPhoto = photo != null && photo.isNotEmpty;

    if (!hasPhoto) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.primaryColor.withAlpha(isDark ? 40 : 22),
          border: Border.all(
            color: AppTheme.primaryColor.withAlpha(60),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            student.fullName.trim().isNotEmpty
                ? student.fullName.trim()[0].toUpperCase()
                : '?',
            style: AppTheme.getFontStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.38,
            ),
          ),
        ),
      );
    }

    String fullUrl;
    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      fullUrl = photo;
    } else {
      final base = ApiConstants.baseUrl.replaceAll('/api', '');
      final p = photo.startsWith('/') ? photo : '/$photo';
      fullUrl = '$base$p';
    }

    final cachePx = (size * 2.5).toInt();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.primaryColor.withAlpha(90),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.network(
          fullUrl,
          width: size,
          height: size,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
          filterQuality: FilterQuality.medium,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: size,
              height: size,
              color: AppTheme.primaryColor.withAlpha(isDark ? 40 : 22),
              child: Center(
                child: Text(
                  student.fullName.trim().isNotEmpty
                      ? student.fullName.trim()[0].toUpperCase()
                      : '?',
                  style: AppTheme.getFontStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.38,
                  ),
                ),
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: size,
              height: size,
              color: AppTheme.primaryColor.withAlpha(isDark ? 30 : 15),
              child: Center(
                child: SizedBox(
                  width: size * 0.4,
                  height: size * 0.4,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _KeepAlivePageWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAlivePageWrapper({required this.child});

  @override
  State<_KeepAlivePageWrapper> createState() => _KeepAlivePageWrapperState();
}

class _KeepAlivePageWrapperState extends State<_KeepAlivePageWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}



