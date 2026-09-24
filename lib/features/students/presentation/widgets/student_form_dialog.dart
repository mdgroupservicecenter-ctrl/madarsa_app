import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:hijri/hijri_calendar.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../../../../core/utils/hijri_cubit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../data/models/student_model.dart';
import '../../../../features/contributors/data/models/contributor_model.dart';
import '../../../../features/fees/data/models/fee_models.dart';
import '../../../../features/fees/data/repositories/fees_repository.dart';
import '../bloc/students_bloc.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/pincode_settings.dart';
import '../../../../core/services/gr_no_settings.dart';
import '../../../../core/services/student_status_settings.dart';
import '../../../../core/services/student_form_options_settings.dart';
import '../../../../core/services/fee_condition_settings.dart';
import '../../../../features/staff/data/models/staff_model.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import 'gr_no_config_dialog.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../shared/widgets/movable_resizable_dialog.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../shared/widgets/dribbble_date_picker.dart';

class SubDeptFormEntry {
  String subDepartmentId;
  String subDepartmentName;
  String? className;
  String? division;
  bool showCustomDivisionField;
  TextEditingController customDivisionController;

  SubDeptFormEntry({
    required this.subDepartmentId,
    required this.subDepartmentName,
    this.className,
    this.division,
    this.showCustomDivisionField = false,
    TextEditingController? customDivisionController,
  }) : customDivisionController = customDivisionController ?? TextEditingController(text: division ?? '');
}

class _StudentFormFeeHead {
  final String id;
  final String title;
  final double baseAmount;
  final IconData icon;
  double discount = 0.0;
  String discountTag = '';
  final double unitAmount;
  final int monthsCount;
  final String billingType;
  final List<String> monthsList;

  _StudentFormFeeHead({
    required this.id,
    required this.title,
    required this.baseAmount,
    required this.icon,
    this.unitAmount = 0.0,
    this.monthsCount = 1,
    this.billingType = 'monthly',
    this.monthsList = const [],
  });

  double get netAmount => (baseAmount - discount).clamp(0.0, double.infinity);
  double get netUnitAmount => monthsCount > 0 ? (netAmount / monthsCount) : netAmount;

  static List<String> resolveMonthsList(
    FeeConditionFieldConfig field,
    List<BillingFrequencyOption>? frequencies,
  ) {
    if (field.monthsList.isNotEmpty) {
      return field.monthsList;
    }
    if (frequencies != null && frequencies.isNotEmpty) {
      final match = frequencies.where((freq) =>
          freq.id == field.billingType ||
          freq.name.trim().toLowerCase() == field.billingType.trim().toLowerCase()).firstOrNull;
      if (match != null && match.monthsList.isNotEmpty) {
        return match.monthsList;
      }
    }
    if (field.billingType == 'monthly') {
      return BillingFrequencyOption.allMonths;
    }
    return const [];
  }

  static int resolveMonths(
    FeeConditionFieldConfig field,
    int sessionMonths, [
    List<BillingFrequencyOption>? frequencies,
  ]) {
    if (frequencies != null && frequencies.isNotEmpty) {
      final match = frequencies.where((freq) =>
          freq.id == field.billingType ||
          freq.name.trim().toLowerCase() == field.billingType.trim().toLowerCase()).firstOrNull;
      if (match != null) {
        if (match.id == 'session' || match.name.toLowerCase() == 'session') {
          return match.months > 0 ? match.months : (sessionMonths > 0 ? sessionMonths : 10);
        }
        if (match.id == 'monthly' || match.name.toLowerCase() == 'monthly') {
          return field.billingMonths > 0
              ? field.billingMonths
              : (match.months > 1 ? match.months : (sessionMonths > 0 ? sessionMonths : 12));
        }
        return match.months > 0 ? match.months : 1;
      }
    }
    if (field.billingType == 'one_time') return 1;
    if (field.billingType == 'yearly') return 12;
    if (field.billingType == 'half_yearly') return 6;
    if (field.billingType == 'quarterly') return 3;
    if (field.billingType == 'session') return sessionMonths > 0 ? sessionMonths : 12;
    if (field.billingType == 'monthly') {
      return field.billingMonths > 0 ? field.billingMonths : (sessionMonths > 0 ? sessionMonths : 12);
    }
    return field.billingMonths > 0 ? field.billingMonths : 1;
  }
}

class StudentFormDialog extends StatefulWidget {
  final Student? student;
  final List<Map<String, dynamic>>? initialDepartments;
  final List<dynamic>? initialHierarchy;

  const StudentFormDialog({
    super.key,
    this.student,
    this.initialDepartments,
    this.initialHierarchy,
  });

  @override
  State<StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<StudentFormDialog> {
  // ── Static In-Memory Cache for Frame 0 Zero-Lag Startup ────────────────────
  static List<Map<String, dynamic>>? _cachedAllDepartments;
  static List<dynamic>? _cachedHierarchy;
  static List<Contributor>? _cachedContributors;
  static List<StaffMember>? _cachedStaffList;
  static List<String>? _cachedStatusOptions;
  static List<String>? _cachedGenders;
  static List<String>? _cachedAdmissionTypes;
  static List<String>? _cachedConditions;

  final _formKey = GlobalKey<FormState>();
  final _grNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _grandFatherNameController = TextEditingController();
  final _dobController = TextEditingController();
  final _villageController = TextEditingController();
  final _talukaController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();
  final _pinCodeController = TextEditingController();
  final _addressController = TextEditingController();
  final _mobileController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _admissionDateController = TextEditingController();
  final _admissionDateHController = TextEditingController();
  final _monthlyFeesController = TextEditingController();
  final _admissionFeeController = TextEditingController();
  final _bookFeeController = TextEditingController();
  final _monthlyFeesMonthsController = TextEditingController(text: '12');
  final _contributorAmountController = TextEditingController();
  final _totalFeesController = TextEditingController();
  final _categoryController = TextEditingController();
  final _divisionController = TextEditingController();
  int _sessionMonths = 12;

  List<FeeType> _availableFeeTypes = [];
  final Map<String, TextEditingController> _feeHeadAmountControllers = {};
  final Map<String, TextEditingController> _feeHeadMonthsControllers = {};
  final Map<String, String> _feeHeadBillingTypes = {};

  String? _selectedClass;
  String? _selectedContributorId;
  List<Contributor> _contributorsList = [];
  bool _isLoadingContributors = false;
  String _selectedStatus = 'Active';
  List<String> _statusOptions = StudentStatusSettings.defaultStatuses;
  String _admissionType = 'New';
  String _conditionType = 'Regular';
  String? _originalConditionType;
  String? _gender;
  String _admissionTimeAge = '';
  String _nowAge = '';
  bool _isLoadingGR = false;
  bool _isSubmitting = false;
  bool _isFetchingPin = false;
  String _lastFetchedPinCode = '';

  List<String> _genders = StudentFormOptionsSettings.defaultGenders;
  List<String> _admissionTypes = StudentFormOptionsSettings.defaultAdmissionTypes;
  List<String> _conditions = StudentFormOptionsSettings.defaultConditions;
  List<BillingFrequencyOption> _availableFrequencies = [];
  List<Map<String, dynamic>> _allDepartments = [];
  String? _selectedDepartmentId;
  List<Map<String, dynamic>> _availableSubDepartments = [];
  List<SubDeptFormEntry> _selectedSubDeptEntries = [];
  List<dynamic> _hierarchy = [];
  List<String> _classes = [];
  List<String> _divisions = [];
  String? _selectedDivision;
  bool _showCustomDivisionField = false;
  List<String> _villageSuggestions = [];
  // Stores ALL villages returned from pincode fetch for local filtering
  List<String> _pinCodeVillages = [];
  bool _showVillageDropdown = false;
  Timer? _villageDebounce;
  bool _ignoreVillageListener = false;
  String? _photoPath;
  bool _isUploadingPhoto = false;

  FeeConditionConfig? _activeConditionConfig;
  final Map<String, TextEditingController> _dynamicFeeControllers = {};
  final Map<String, String> _discountTargetFees = {};
  final Map<String, String> _discountModes = {};
  FeeCalculationResult? _latestFeeCalculation;
  List<StaffMember> _staffList = [];
  bool _isLoadingStaff = false;
  final Map<String, String?> _selectedStaffIds = {};
  final Map<String, String?> _selectedContributorIds = {};
  bool _isChildDialogOpen = false;

  String _getTargetFeeName(String? target) {
    if (target == null || target == 'all' || target.isEmpty) {
      return 'Total Fees';
    }
    if (target == 'monthly_fees' || target.contains('monthly') || target.contains('tuition')) {
      return 'Monthly Tuition';
    }
    if (target == 'admission_fee' || target.contains('admission') || target.contains('dakhila')) {
      return 'Admission Fee';
    }
    if (target == 'book_fee' || target.contains('book') || target.contains('kitab')) {
      return 'Book Fee';
    }
    if (_activeConditionConfig != null) {
      for (final f in _activeConditionConfig!.fields) {
        final fId = f.id.toLowerCase().trim();
        final fLabel = f.label.toLowerCase().trim();
        final fClean = fLabel.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        if (fId == target.toLowerCase() ||
            fLabel == target.toLowerCase() ||
            fClean == target.toLowerCase()) {
          return f.label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        }
      }
    }
    return target;
  }

  Future<T?> _openSubDialog<T>(Future<T?> Function() dialogOpener) async {
    setState(() => _isChildDialogOpen = true);
    try {
      return await dialogOpener();
    } finally {
      if (mounted) {
        setState(() => _isChildDialogOpen = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // 1. Frame 0 Instant In-Memory Cache Population
    _allDepartments = widget.initialDepartments ?? _cachedAllDepartments ?? [];
    _hierarchy = widget.initialHierarchy ?? _cachedHierarchy ?? [];
    if (_cachedContributors != null && _cachedContributors!.isNotEmpty) {
      _contributorsList = _cachedContributors!;
    }
    if (_cachedStaffList != null && _cachedStaffList!.isNotEmpty) {
      _staffList = _cachedStaffList!;
    }
    if (_cachedStatusOptions != null && _cachedStatusOptions!.isNotEmpty) {
      _statusOptions = _cachedStatusOptions!;
    }
    if (_cachedGenders != null && _cachedGenders!.isNotEmpty) {
      _genders = _cachedGenders!;
    }
    if (_cachedAdmissionTypes != null && _cachedAdmissionTypes!.isNotEmpty) {
      _admissionTypes = _cachedAdmissionTypes!;
    }
    if (_cachedConditions != null && _cachedConditions!.isNotEmpty) {
      _conditions = _cachedConditions!;
    }

    if (widget.student != null && widget.student!.className != null) {
      _classes = [widget.student!.className!];
      _selectedClass = widget.student!.className;
    }

    if (_allDepartments.isNotEmpty || _hierarchy.isNotEmpty) {
      _applyAcademicDataToForm();
    }

    // 2. Load background updates without blocking frame 0
    _loadAllInitialDataInBackground();

    _monthlyFeesController.addListener(_recalculateDynamicFees);
    _admissionFeeController.addListener(_recalculateDynamicFees);
    _bookFeeController.addListener(_recalculateDynamicFees);
    _monthlyFeesMonthsController.addListener(_recalculateDynamicFees);
    _contributorAmountController.addListener(_recalculateDynamicFees);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _admissionDateController.text = today;

    if (widget.student != null) {
      final s = widget.student!;
      _grNoController.text = s.grNo ?? '';
      _nameController.text = s.fullName;
      _fatherNameController.text = s.fatherName ?? '';
      _surnameController.text = s.surname ?? '';
      _grandFatherNameController.text = s.grandFatherName ?? '';
      _dobController.text = s.dateOfBirth ?? '';
      _villageController.text = s.village ?? '';
      _talukaController.text = s.taluka ?? '';
      _districtController.text = s.district ?? '';
      _stateController.text = s.state ?? '';
      _pinCodeController.text = s.pinCode ?? '';
      _addressController.text = s.address ?? '';
      
      // Clean mobile number (strip non-digits and leading country code)
      String cleanedMobile = (s.mobileNo ?? '').replaceAll(RegExp(r'\D'), '');
      if (cleanedMobile.length == 12 && cleanedMobile.startsWith('91')) {
        cleanedMobile = cleanedMobile.substring(2);
      } else if (cleanedMobile.length == 11 && cleanedMobile.startsWith('0')) {
        cleanedMobile = cleanedMobile.substring(1);
      }
      _mobileController.text = cleanedMobile;

      // Clean Aadhaar number (strip non-digits and spaces)
      _aadhaarController.text = (s.aadhaarNo ?? '').replaceAll(RegExp(r'\D'), '');

      _selectedClass = s.className;
      _selectedStatus = (s.studentStatus != null && s.studentStatus!.isNotEmpty) ? s.studentStatus! : (s.isActive ? 'Active' : 'Inactive');
      _admissionType = s.admissionType ?? 'New';
      _admissionDateController.text = s.admissionDate ?? today;
      _admissionDateHController.text = s.admissionDateH ?? '';
      _conditionType = s.conditionType ?? 'Regular';
      _originalConditionType = (s.conditionType != null && s.conditionType!.trim().isNotEmpty)
          ? s.conditionType!.trim()
          : 'Regular';

      double initialMonthly = s.monthlyFees ?? 0.0;
      double initialAdmission = s.admissionFee ?? 0.0;
      double initialBook = s.bookFee ?? 0.0;
      String? initialDiscountVal;

      if (s.feeStructure != null && s.feeStructure!.trim().isNotEmpty && s.feeStructure != 'null') {
        try {
          final decoded = jsonDecode(s.feeStructure!);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final orig = (item['original_amount'] as num?)?.toDouble();
                final name = (item['fee_type_name'] ?? item['fee_type'])?.toString().toLowerCase().trim() ?? '';
                if (orig != null && orig > 0) {
                  if (name.contains('month') || name.contains('tuition')) {
                    initialMonthly = orig;
                  } else if (name.contains('admission') || name.contains('dakhila')) {
                    initialAdmission = orig;
                  } else if (name.contains('book') || name.contains('kitab')) {
                    initialBook = orig;
                  }
                }
                if (item['discount_input'] != null && item['discount_input'].toString().isNotEmpty) {
                  initialDiscountVal = item['discount_input'].toString();
                }
              }
            }
          }
        } catch (_) {}
      }

      _monthlyFeesController.text = initialMonthly > 0 ? initialMonthly.toStringAsFixed(0) : '';
      _admissionFeeController.text = initialAdmission > 0 ? initialAdmission.toStringAsFixed(0) : '';
      _bookFeeController.text = initialBook > 0 ? initialBook.toStringAsFixed(0) : '';
      _selectedContributorId = s.contributorId;
      _contributorAmountController.text = initialDiscountVal ??
          (s.contributorAmount != null && s.contributorAmount! > 0
              ? s.contributorAmount!.toStringAsFixed(0)
              : '');
      _categoryController.text = s.category ?? '';
      _divisionController.text = s.division ?? '';
      _selectedDivision = s.division;
      if (_selectedDivision != null && _selectedDivision!.isNotEmpty) {
        _divisions = [_selectedDivision!];
      }
      _gender = s.gender;
      _admissionTimeAge = s.admissionTimeAge ?? '';
      _nowAge = s.nowAge ?? '';
      _photoPath = s.photoPath;
    } else {
      _getNextGRNo();
    }

    _dobController.addListener(_calculateAges);
    _admissionDateController.addListener(_calculateAges);
    _admissionDateController.addListener(_updateHijriDate);
    _pinCodeController.addListener(_onPinCodeChanged);
    _villageController.addListener(_onVillageChanged);
    _monthlyFeesController.addListener(() {
      _updateTotalFees();
      setState(() {});
    });
    _admissionFeeController.addListener(() {
      _updateTotalFees();
      setState(() {});
    });
    _bookFeeController.addListener(() {
      _updateTotalFees();
      setState(() {});
    });
    _monthlyFeesMonthsController.addListener(() {
      _updateTotalFees();
      setState(() {});
    });
    _contributorAmountController.addListener(() {
      _updateTotalFees();
      setState(() {});
    });
    _updateTotalFees();

    // Initial Hijri date for new students
    if (widget.student == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateHijriDate());
    }
  }

  void _updateHijriDate() {
    if (_admissionDateController.text.isEmpty) return;
    try {
      final date = DateTime.parse(_admissionDateController.text);
      final adjustment = context.read<HijriCubit>().state.adjustment;
      final hijri = HijriCalendar.fromDate(
        date.add(Duration(days: adjustment)),
      );
      setState(() {
        _admissionDateHController.text =
            '${hijri.hDay}/${hijri.hMonth}/${hijri.hYear}';
      });
    } catch (e) {
      // Invalid date
    }
  }

  Future<void> _loadAllInitialDataInBackground() async {
    try {
      await Future.wait([
        _loadAcademicData(),
        _loadContributors(),
        _loadStaffMembers(),
        _loadStatuses(),
        _loadFormOptions(),
        _loadFeeTypes(),
      ]);
    } catch (e) {
      debugPrint('Background form data sync: $e');
    }
  }

  Future<void> _loadFeeTypes() async {
    try {
      final dbTypes = await DatabaseHelper().getFeeTypes();
      List<FeeType> list = [];
      if (dbTypes.isNotEmpty) {
        list = dbTypes.map((row) => FeeType(
          id: row['id']?.toString() ?? '',
          name: row['name']?.toString() ?? '',
          billingType: row['billing_type']?.toString() ?? 'monthly',
          defaultMonths: (row['default_months'] as num?)?.toInt() ?? 12,
          defaultAmount: (row['default_amount'] as num?)?.toDouble() ?? 0.0,
        )).toList();
      } else {
        try {
          list = await FeesRepository(ApiClient()).getFeeTypes();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _availableFeeTypes = list;
          for (final t in _availableFeeTypes) {
            if (!_feeHeadAmountControllers.containsKey(t.id)) {
              final defaultVal = t.defaultAmount > 0 ? t.defaultAmount.toStringAsFixed(0) : '';
              final ctrl = TextEditingController(text: defaultVal);
              ctrl.addListener(_recalculateDynamicFees);
              _feeHeadAmountControllers[t.id] = ctrl;
            }
            if (!_feeHeadMonthsControllers.containsKey(t.id)) {
              final monthsVal = t.defaultMonths.toString();
              final ctrl = TextEditingController(text: monthsVal);
              ctrl.addListener(_recalculateDynamicFees);
              _feeHeadMonthsControllers[t.id] = ctrl;
            }
            _feeHeadBillingTypes[t.id] = t.billingType;
          }

          // Pre-populate if student has feeStructure
          if (widget.student != null && widget.student!.feeStructure != null) {
            try {
              final decoded = jsonDecode(widget.student!.feeStructure!);
              if (decoded is List) {
                for (final item in decoded) {
                  final tId = item['fee_type_id']?.toString();
                  final tName = (item['fee_type_name'] ?? item['fee_type'])?.toString().toLowerCase().trim();
                  final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                  final origAmt = (item['original_amount'] as num?)?.toDouble() ?? amt;
                  final months = (item['months_count'] as num?)?.toInt() ?? 12;

                  if (tName == 'admission fee' || tName == 'dakhila fee') {
                    if (origAmt > 0) {
                      _admissionFeeController.text = origAmt.toStringAsFixed(0);
                    }
                  } else if (tName == 'book fee' || tName == 'kitab fee') {
                    if (origAmt > 0) {
                      _bookFeeController.text = origAmt.toStringAsFixed(0);
                    }
                  } else if (tName == 'tuition fee' || tName == 'monthly fee' || tName == 'monthly tuition fee') {
                    if (origAmt > 0) {
                      _monthlyFeesController.text = origAmt.toStringAsFixed(0);
                    }
                    _monthlyFeesMonthsController.text = months.toString();
                  }

                  if (tId != null) {
                    if (_feeHeadAmountControllers.containsKey(tId)) {
                      if (origAmt > 0) {
                        _feeHeadAmountControllers[tId]!.text = origAmt.toStringAsFixed(0);
                      }
                      if (_feeHeadMonthsControllers.containsKey(tId)) {
                        _feeHeadMonthsControllers[tId]!.text = months.toString();
                      }
                    }
                    if (amt > 0 || item['raw_input'] != null || item['discount_value'] != null) {
                      final dynCtrl = _getDynamicController(tId);
                      if (dynCtrl.text.isEmpty) {
                        final rawVal = item['raw_input']?.toString() ??
                            (item['discount_value'] != null
                                ? (item['discount_value'] as num).toDouble().toStringAsFixed(0)
                                : amt.toStringAsFixed(0));
                        dynCtrl.text = rawVal;
                      }
                    }
                    final targetFee = item['target_fee']?.toString();
                    if (targetFee != null && targetFee.isNotEmpty) {
                      _discountTargetFees[tId] = targetFee;
                    }
                  }
                }
              }
            } catch (_) {}
          }
          _fillDefaultAmounts();
        });
        _recalculateDynamicFees();
      }
    } catch (e) {
      debugPrint('Error loading fee types in student form: $e');
    }
  }

  Future<void> _loadAcademicData() async {
    try {
      final deptResponse = await ApiClient().get('/academic/departments');
      final hierResponse = await ApiClient().get('/academic/hierarchy');
      if (mounted) {
        final depts = (deptResponse.data as List).cast<Map<String, dynamic>>();
        final hierarchy = (hierResponse.data as List).cast<dynamic>();

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

        // Sort hierarchy by Class Progression Series order
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

          hierarchy.sort((a, b) {
            final nameA = (a['name']?.toString().trim() ?? '').toLowerCase();
            final nameB = (b['name']?.toString().trim() ?? '').toLowerCase();
            final ordA = classOrderMap[nameA] ?? 999999;
            final ordB = classOrderMap[nameB] ?? 999999;
            if (ordA != ordB) return ordA.compareTo(ordB);
            return nameA.compareTo(nameB);
          });
        } catch (_) {}

        _allDepartments = depts;
        _hierarchy = hierarchy;
        _cachedAllDepartments = depts;
        _cachedHierarchy = hierarchy;

        _applyAcademicDataToForm();
      }
    } catch (e) {
      debugPrint('Failed to load academic hierarchy: $e');
    }
  }

  void _applyAcademicDataToForm() {
    // Auto-detect department and sub-departments if editing student
    if (widget.student != null) {
      if (widget.student!.departmentId != null && widget.student!.departmentId!.isNotEmpty) {
        _selectedDepartmentId = widget.student!.departmentId;
      } else if (widget.student!.className != null) {
        final studentClass = widget.student!.className!;
        final classNode = _hierarchy.where(
          (c) => c['name']?.toString() == studentClass,
        ).firstOrNull;
        if (classNode != null) {
          final deptId = classNode['department_id']?.toString();
          final parentDeptId = classNode['department_parent_id']?.toString();
          if (parentDeptId != null) {
            _selectedDepartmentId = parentDeptId;
          } else if (deptId != null) {
            _selectedDepartmentId = deptId;
          }
        }
      }

      _selectedClass = widget.student!.className;
      _selectedDivision = widget.student!.division;

      _updateAvailableSubDeptsAndClasses(resetClass: false);
      _updateDivisionsList();

      // Populate existing sub-departments
      if (widget.student!.subDepartments != null && widget.student!.subDepartments!.isNotEmpty) {
        _selectedSubDeptEntries = widget.student!.subDepartments!.map((s) {
          final subDivs = _getDivisionsForClass(s.className ?? _selectedClass);
          final isCustom = s.division != null && s.division!.isNotEmpty && !subDivs.contains(s.division);
          return SubDeptFormEntry(
            subDepartmentId: s.subDepartmentId ?? '',
            subDepartmentName: s.subDepartmentName ?? '',
            className: s.className ?? _selectedClass,
            division: isCustom ? 'Custom...' : s.division,
            showCustomDivisionField: isCustom,
            customDivisionController: TextEditingController(text: s.division ?? ''),
          );
        }).toList();
      }
    } else {
      _updateAvailableSubDeptsAndClasses(resetClass: false);
      _updateDivisionsList();
    }
  }

  void _updateAvailableSubDeptsAndClasses({bool resetClass = true}) {
    List<Map<String, dynamic>> subDepts = [];
    List<String> filteredClasses = [];

    if (_selectedDepartmentId != null) {
      final mainDept = _allDepartments.where(
        (d) => d['id']?.toString() == _selectedDepartmentId,
      ).firstOrNull;
      if (mainDept != null) {
        subDepts = ((mainDept['sub_departments'] as List?) ??
                _allDepartments.where((d) => d['parent_id']?.toString() == _selectedDepartmentId).toList())
            .cast<Map<String, dynamic>>();
      }

      // Classes belonging to this main department
      filteredClasses = _hierarchy
          .where((cls) => cls['department_id']?.toString() == _selectedDepartmentId)
          .map((cls) => cls['name']?.toString())
          .where((n) => n != null && n.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      // If no direct classes in main dept, include classes belonging to its sub-departments
      if (filteredClasses.isEmpty) {
        final subDeptIds = subDepts.map((s) => s['id']?.toString()).where((id) => id != null).toSet();
        filteredClasses = _hierarchy
            .where((cls) {
              final dId = cls['department_id']?.toString();
              return subDeptIds.contains(dId);
            })
            .map((cls) => cls['name']?.toString())
            .where((n) => n != null && n.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();
      }
    } else {
      // No department selected: all classes
      filteredClasses = _hierarchy
          .map((cls) => cls['name']?.toString())
          .where((n) => n != null && n.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
    }

    // Preserve student's class if editing
    if (widget.student != null && widget.student!.className != null) {
      final sClass = widget.student!.className!;
      if (_selectedClass == sClass && !filteredClasses.contains(sClass)) {
        filteredClasses.add(sClass);
      }
    }

    setState(() {
      _availableSubDepartments = subDepts;
      _classes = filteredClasses;
      if (resetClass && _selectedClass != null && !_classes.contains(_selectedClass)) {
        _selectedClass = _classes.isNotEmpty ? _classes.first : null;
        _selectedDivision = null;
        _divisionController.clear();
        _divisions = [];
      }
    });
  }

  List<String> _getClassesForSubDept(String subDeptId) {
    final list = _hierarchy
        .where((cls) => cls['department_id']?.toString() == subDeptId)
        .map((cls) => cls['name']?.toString())
        .where((n) => n != null && n.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    list.sort();
    if (list.isEmpty) {
      return List<String>.from(_classes);
    }
    return list;
  }

  List<String> _getDivisionsForClass(String? clsName) {
    if (clsName == null) return [];
    final classNode = _hierarchy.where(
      (c) => c['name']?.toString() == clsName,
    ).firstOrNull;
    if (classNode != null && classNode['courses'] is List) {
      final courses = classNode['courses'] as List;
      final divs = courses
          .map((c) => c['name']?.toString())
          .where((n) => n != null && n.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
      divs.sort();
      return divs;
    }
    return [];
  }

  void _toggleSubDepartment(Map<String, dynamic> subDept) {
    final subId = subDept['id'].toString();
    final subName = subDept['name']?.toString() ?? '';
    final existingIdx = _selectedSubDeptEntries.indexWhere((e) => e.subDepartmentId == subId);

    setState(() {
      if (existingIdx != -1) {
        _selectedSubDeptEntries.removeAt(existingIdx);
      } else {
        final subClasses = _getClassesForSubDept(subId);
        final defaultClass = (subClasses.contains(_selectedClass)
            ? _selectedClass
            : (subClasses.isNotEmpty ? subClasses.first : _selectedClass));
        final subDivs = _getDivisionsForClass(defaultClass);
        final defaultDiv = subDivs.isNotEmpty ? subDivs.first : null;

        _selectedSubDeptEntries.add(
          SubDeptFormEntry(
            subDepartmentId: subId,
            subDepartmentName: subName,
            className: defaultClass,
            division: defaultDiv,
            customDivisionController: TextEditingController(text: defaultDiv ?? ''),
          ),
        );
      }
    });
  }

  void _updateDivisionsList() {
    List<String> classDivisions = [];
    if (_selectedClass != null) {
      final classNode = _hierarchy.where(
        (c) => c['name']?.toString() == _selectedClass,
      ).firstOrNull;
      if (classNode != null && classNode['courses'] != null) {
        final courses = classNode['courses'] as List;
        classDivisions = courses
            .map((c) => c['name']?.toString())
            .where((n) => n != null && n.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();
      }
    }

    classDivisions.sort();

    // Also add the student's current division if it's not in the list
    if (widget.student != null && widget.student!.division != null) {
      final studentDiv = widget.student!.division!;
      if (studentDiv.isNotEmpty && !classDivisions.contains(studentDiv)) {
        classDivisions.add(studentDiv);
        classDivisions.sort();
      }
    }

    setState(() {
      _divisions = classDivisions;
      if (_selectedDivision != null &&
          _selectedDivision != 'Custom...' &&
          !_divisions.contains(_selectedDivision)) {
        _selectedDivision = null;
        _divisionController.clear();
      }
    });
  }

  Future<void> _getNextGRNo({String? lastSavedGrNo}) async {
    try {
      final studentState = context.read<StudentsBloc>().state;
      final existingGrNos = <String>[];
      if (studentState is StudentsLoaded && studentState.students.isNotEmpty) {
        for (final s in studentState.students) {
          final g = (s.grNo ?? s.registrationNumber).toString().trim();
          if (g.isNotEmpty) existingGrNos.add(g);
        }
      }
      if (lastSavedGrNo != null && lastSavedGrNo.trim().isNotEmpty) {
        existingGrNos.add(lastSavedGrNo.trim());
      }

      if (existingGrNos.isNotEmpty) {
        final settings = await GrNoSettings.loadSettings();
        final nextGr = GrNoGenerator.generateNextGrNo(
          existingGrNos: existingGrNos,
          settings: settings,
        );
        if (mounted) {
          setState(() {
            _grNoController.text = nextGr;
            _isLoadingGR = false;
          });
        }
        return;
      }
    } catch (_) {}

    setState(() => _isLoadingGR = true);
    try {
      final settings = await GrNoSettings.loadSettings();
      final response = await ApiClient().get('/students/next-gr');
      if (response.statusCode == 200 && response.data != null && response.data['next_gr_no'] != null) {
        var serverNextGr = response.data['next_gr_no'].toString();
        if (lastSavedGrNo != null && lastSavedGrNo.trim().isNotEmpty && serverNextGr == lastSavedGrNo.trim()) {
          serverNextGr = GrNoGenerator.generateNextGrNo(
            existingGrNos: [lastSavedGrNo.trim()],
            settings: settings,
          );
        }
        if (mounted) {
          setState(() {
            _grNoController.text = serverNextGr;
            _isLoadingGR = false;
          });
        }
        return;
      }

      if (mounted) {
        final defaultGr = (lastSavedGrNo != null && lastSavedGrNo.trim().isNotEmpty)
            ? GrNoGenerator.generateNextGrNo(
                existingGrNos: [lastSavedGrNo.trim()],
                settings: settings,
              )
            : settings.buildGrNo(settings.startingNumber);
        setState(() {
          _grNoController.text = defaultGr;
          _isLoadingGR = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final settings = await GrNoSettings.loadSettings();
        final fallbackGr = (lastSavedGrNo != null && lastSavedGrNo.trim().isNotEmpty)
            ? GrNoGenerator.generateNextGrNo(
                existingGrNos: [lastSavedGrNo.trim()],
                settings: settings,
              )
            : settings.buildGrNo(settings.startingNumber);
        setState(() {
          _grNoController.text = fallbackGr;
          _isLoadingGR = false;
        });
      }
    }
  }

  Future<void> _fetchStudentByGRNo(String grNo) async {
    setState(() => _isLoadingGR = true);
    try {
      final response = await ApiClient().get('/students/gr/$grNo');
      if (response.statusCode == 200) {
        final data = response.data;
        if (mounted) {
          setState(() {
            _nameController.text = data['full_name'] ?? '';
            _fatherNameController.text = data['father_name'] ?? '';
            _surnameController.text = data['surname'] ?? '';
            _grandFatherNameController.text = data['grand_father_name'] ?? '';
            _dobController.text = data['date_of_birth'] ?? '';
            _villageController.text = data['village'] ?? '';
            _talukaController.text = data['taluka'] ?? '';
            _districtController.text = data['district'] ?? '';
            _stateController.text = data['state'] ?? '';
            _pinCodeController.text = data['pin_code'] ?? '';
            _addressController.text = data['address'] ?? '';
            _mobileController.text = data['mobile_no'] ?? '';
            _aadhaarController.text = data['aadhaar_no'] ?? '';
            _selectedClass = data['class_name'];
            _admissionType = data['admission_type'] ?? 'New';
            _admissionDateController.text = data['admission_date'] ?? '';
            _admissionDateHController.text = data['admission_date_h'] ?? '';
            _conditionType = data['condition_type'] ?? 'Regular';
            _originalConditionType = (data['condition_type'] != null && data['condition_type'].toString().trim().isNotEmpty)
                ? data['condition_type'].toString().trim()
                : 'Regular';
            _monthlyFeesController.text =
                data['monthly_fees']?.toString() ?? '';
            _categoryController.text = data['category'] ?? '';
            _divisionController.text = data['division'] ?? '';
            _gender = data['gender'];
            _calculateAges();
            _isLoadingGR = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('student_data_loaded')),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingGR = false);
    }
  }

  void _onPinCodeChanged() {
    final pinCode = _pinCodeController.text.trim();
    if (pinCode.length == 6 && pinCode != _lastFetchedPinCode) {
      _lastFetchedPinCode = pinCode;
      _fetchPinCodeDetails(pinCode);
    } else if (pinCode.length != 6) {
      _lastFetchedPinCode = '';
      // Clear pincode-based village cache so global search is used
      if (_pinCodeVillages.isNotEmpty) {
        setState(() => _pinCodeVillages = []);
      }
    }
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _fetchPinCodeDetails(String pinCode) async {
    if (pinCode.length != 6) return;
    setState(() => _isFetchingPin = true);
    
    bool fetched = false;
    final provider = await PincodeSettings.getProvider();

    // 1. Custom Provider Fetch
    if (provider == 'custom') {
      try {
        final customUrlPattern = await PincodeSettings.getCustomUrl();
        if (customUrlPattern.isNotEmpty) {
          final apiKey = await PincodeSettings.getApiKey();
          final url = customUrlPattern
              .replaceAll('{pincode}', pinCode)
              .replaceAll('{apiKey}', apiKey);

          debugPrint('Pincode custom fetch URL: $url');
          final res = await Dio().get(url);
          if (res.statusCode == 200 && res.data != null) {
            final jsonPayload = res.data;

            final mapTalukaKey = await PincodeSettings.getMapTaluka();
            final mapDistrictKey = await PincodeSettings.getMapDistrict();
            final mapStateKey = await PincodeSettings.getMapState();
            final mapVillageKey = await PincodeSettings.getMapVillage();

            final rawTaluka = PincodeSettings.findKeyInJson(jsonPayload, mapTalukaKey);
            final rawDistrict = PincodeSettings.findKeyInJson(jsonPayload, mapDistrictKey);
            final rawState = PincodeSettings.findKeyInJson(jsonPayload, mapStateKey);
            final rawVillages = PincodeSettings.extractVillages(jsonPayload, mapVillageKey);

            String talukaVal = rawTaluka != null ? _toTitleCase(rawTaluka.toString()) : '';
            String districtVal = rawDistrict != null ? _toTitleCase(rawDistrict.toString()) : '';
            String stateVal = rawState != null ? _toTitleCase(rawState.toString()) : '';
            final villages = rawVillages.map((v) {
              final clean = v.replaceAll(RegExp(r'\s+(H\.O|B\.O|S\.O|C\.O|R\.S|E\.O)$', caseSensitive: false), '').trim();
              return _toTitleCase(clean);
            }).toSet().toList()..sort();

            _ignoreVillageListener = true;
            setState(() {
              _pinCodeVillages = villages;
              if (talukaVal.isNotEmpty && talukaVal.toUpperCase() != 'NA') {
                _talukaController.text = talukaVal;
              }
              if (districtVal.isNotEmpty && districtVal.toUpperCase() != 'NA') {
                _districtController.text = districtVal;
              }
              if (stateVal.isNotEmpty && stateVal.toUpperCase() != 'NA') {
                _stateController.text = stateVal;
              }
              if (villages.isNotEmpty) {
                _villageController.text = villages[0];
                _villageSuggestions = villages;
                _showVillageDropdown = villages.length > 1;
              }
            });
            _ignoreVillageListener = false;
            fetched = true;
          }
        }
      } catch (e) {
        debugPrint('Custom Pincode API call failed: $e');
      }
    }

    // 2. Try Official data.gov.in API with user's API Key
    if (!fetched && provider == 'datagov') {
      try {
        final apiKey = await PincodeSettings.getApiKey();
        const resourceId = '6176ee09-3d56-4a3b-8115-21841576b2f6';
        final url = 'https://api.data.gov.in/resource/$resourceId?api-key=$apiKey&format=json&limit=50&filters[pincode]=$pinCode';
        
        debugPrint('Pincode datagov fetch URL: $url');
        final res = await Dio().get(url);
        if (res.statusCode == 200 && res.data != null && res.data['records'] != null) {
          final List records = res.data['records'];
          if (records.isNotEmpty) {
            final villagesSet = <String>{};
            String foundTaluk = '';
            String foundDistrict = '';
            String foundState = '';

            for (final r in records) {
              final rawOffice = r['officename']?.toString().trim() ?? '';
              if (rawOffice.isNotEmpty) {
                final cleanName = rawOffice.replaceAll(RegExp(r'\s+(H\.O|B\.O|S\.O|C\.O|R\.S|E\.O)$', caseSensitive: false), '').trim();
                villagesSet.add(_toTitleCase(cleanName));
              }

              if (foundTaluk.isEmpty) {
                final t = r['taluk']?.toString().trim();
                if (t != null && t.isNotEmpty && t.toUpperCase() != 'NA') {
                  foundTaluk = _toTitleCase(t);
                }
              }

              if (foundDistrict.isEmpty) {
                final d = r['districtname']?.toString().trim();
                if (d != null && d.isNotEmpty && d.toUpperCase() != 'NA') {
                  foundDistrict = _toTitleCase(d);
                }
              }

              if (foundState.isEmpty) {
                final st = r['statename']?.toString().trim();
                if (st != null && st.isNotEmpty && st.toUpperCase() != 'NA') {
                  foundState = _toTitleCase(st);
                }
              }
            }

            final villages = villagesSet.toList()..sort();

            _ignoreVillageListener = true;
            setState(() {
              _pinCodeVillages = villages;
              if (foundTaluk.isNotEmpty) _talukaController.text = foundTaluk;
              if (foundDistrict.isNotEmpty) _districtController.text = foundDistrict;
              if (foundState.isNotEmpty) _stateController.text = foundState;

              if (villages.isNotEmpty) {
                _villageController.text = villages[0];
                _villageSuggestions = villages;
                _showVillageDropdown = villages.length > 1;
              }
            });
            _ignoreVillageListener = false;
            fetched = true;
          }
        }
      } catch (e) {
        debugPrint('data.gov.in Pincode API call failed: $e');
      }
    }

    // 3. Fallback to postalpincode.in API if provider is postalpincode OR datagov using default key
    final apiKey = await PincodeSettings.getApiKey();
    final isDefaultKey = apiKey == PincodeSettings.defaultApiKey;
    if (!fetched && (provider == 'postalpincode' || (provider == 'datagov' && isDefaultKey))) {
      try {
        debugPrint('Pincode fallback/postalpincode fetch...');
        final res = await Dio().get('https://api.postalpincode.in/pincode/$pinCode');
        final List records = res.data;
        if (records.isNotEmpty && records[0]['Status'] == 'Success') {
          final postOffices = records[0]['PostOffice'] as List;
          if (postOffices.isNotEmpty) {
            final first = postOffices[0];
            final villages = postOffices.map((p) => p['Name'] as String).toSet().toList()..sort();

            _ignoreVillageListener = true;
            setState(() {
              _pinCodeVillages = villages;
              final rawTaluk = first['Taluk']?.toString().trim();
              final rawBlock = first['Block']?.toString().trim();
              String talukaVal = '';
              if (rawBlock != null && rawBlock.isNotEmpty && rawBlock.toUpperCase() != 'NA') {
                talukaVal = rawBlock;
              } else if (rawTaluk != null && rawTaluk.isNotEmpty && rawTaluk.toUpperCase() != 'NA') {
                talukaVal = rawTaluk;
              }
              _talukaController.text = talukaVal;
              _districtController.text = first['District'] ?? '';
              _stateController.text = first['State'] ?? '';
              if (villages.isNotEmpty) {
                _villageController.text = villages[0];
                _villageSuggestions = villages;
                _showVillageDropdown = villages.length > 1;
              }
            });
            _ignoreVillageListener = false;
          }
        }
      } catch (e) {
        debugPrint('Fallback Pincode API call failed: $e');
      }
    }

    if (mounted) setState(() => _isFetchingPin = false);
  }

  void _onVillageChanged() {
    if (_ignoreVillageListener) return;
    final text = _villageController.text;
    if (_pinCodeVillages.isEmpty) {
      setState(() {
        _villageSuggestions = [];
        _showVillageDropdown = false;
      });
      return;
    }
    if (text.isEmpty) {
      setState(() {
        _villageSuggestions = _pinCodeVillages;
        _showVillageDropdown = true;
      });
      return;
    }
    final filtered = _pinCodeVillages
        .where((v) => v.toLowerCase().contains(text.toLowerCase()))
        .toList();
    setState(() {
      _villageSuggestions = filtered;
      _showVillageDropdown = filtered.isNotEmpty;
    });
  }

  void _selectVillage(String village) {
    _ignoreVillageListener = true;
    setState(() {
      _villageController.text = village;
      _showVillageDropdown = false;
    });
    _ignoreVillageListener = false;
  }

  void _calculateAges() {
    final dobStr = _dobController.text;
    if (dobStr.isEmpty) return;

    try {
      final dob = DateTime.parse(dobStr);
      final admissionDateStr = _admissionDateController.text;
      final admissionDate = admissionDateStr.isNotEmpty
          ? DateTime.parse(admissionDateStr)
          : DateTime.now();
      final today = DateTime.now();

      final admissionAge = _calculateAge(dob, admissionDate);
      final nowAge = _calculateAge(dob, today);

      if (mounted) {
        setState(() {
          _admissionTimeAge = admissionAge;
          _nowAge = nowAge;
        });
      }
    } catch (e) {
      // Invalid date format
    }
  }

  String _calculateAge(DateTime birth, DateTime to) {
    int years = to.year - birth.year;
    int months = to.month - birth.month;
    int days = to.day - birth.day;

    if (days < 0) {
      months--;
      final prevMonth = DateTime(to.year, to.month, 0);
      days += prevMonth.day;
    }
    if (months < 0) {
      years--;
      months += 12;
    }

    String result = '';
    if (days > 0) result += '${days}Days ';
    if (months > 0) result += '${months}Months ';
    if (years > 0) result += '${years}Years';

    // If it's fully 0 days
    if (result.isEmpty) return '0Days';

    return result.trim();
  }

  String _formatAgeString(BuildContext context, String rawAge) {
    if (rawAge.isEmpty) return '';
    return rawAge
        .replaceAll('Days', ' ${context.tr('days')}')
        .replaceAll('Months', ' ${context.tr('months')}')
        .replaceAll('Years', ' ${context.tr('years')}');
  }

  Future<void> _selectDate(TextEditingController controller) async {
    DateTime initial = DateTime.now();
    if (controller.text.isNotEmpty) {
      final txt = controller.text.trim();
      try {
        if (txt.contains('/')) {
          final parts = txt.split('/');
          if (parts.length == 3) {
            initial = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        } else if (txt.contains('-')) {
          initial = DateTime.parse(txt);
        }
      } catch (_) {}
    }

    final picked = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      title: 'Select Date',
    );

    if (picked != null && mounted) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
        _calculateAges();
      });
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isUploadingPhoto = true;
        });

        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;

        final formData = FormData.fromMap({
          'photo': await MultipartFile.fromFile(filePath, filename: fileName),
        });

        final response = await ApiClient().post('/upload-photo', data: formData);
        
        if (response.statusCode == 200 && response.data != null) {
          setState(() {
            _photoPath = response.data['photo_path'];
            _isUploadingPhoto = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('photo_uploaded_success'))),
          );
        } else {
          throw Exception('Failed to upload photo');
        }
      }
    } catch (e) {
      setState(() {
        _isUploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading photo: $e')),
      );
    }
  }

  void _submit() {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    final requiredFeature = widget.student == null ? 'students_admission' : 'students_edit';
    if (!license.hasFeatureAccess(requiredFeature)) {
      _openSubDialog(() => UpgradePlanDialog.show(context, highlightModule: widget.student == null ? 'New Admission' : 'Edit Student', barrierColor: Colors.transparent));
      return;
    }

    if (_formKey.currentState!.validate()) {
      // Clean data before submission
      final mobileCleaned = _mobileController.text.replaceAll(
        RegExp(r'\D'),
        '',
      );
      String mobileFinal = mobileCleaned;
      if (mobileCleaned.length == 10) {
        mobileFinal =
            '+91 ${mobileCleaned.substring(0, 3)} ${mobileCleaned.substring(3, 6)} ${mobileCleaned.substring(6)}';
      }

      final aadhaarCleaned = _aadhaarController.text.replaceAll(
        RegExp(r'\D'),
        '',
      );
      String aadhaarFinal = aadhaarCleaned;
      if (aadhaarCleaned.length == 12) {
        aadhaarFinal =
            '${aadhaarCleaned.substring(0, 4)} ${aadhaarCleaned.substring(4, 8)} ${aadhaarCleaned.substring(8)}';
      }

      // Get selected staff or contributor ID and Name
      String? finalContributorId = _selectedContributorId;
      String? finalContributorName;
      String? finalStaffId;
      String? finalStaffName;

      if (_activeConditionConfig != null) {
        for (final f in _activeConditionConfig!.fields) {
          if (f.isContributor) {
            final contribId = _selectedContributorIds[f.id] ?? _selectedContributorId;
            if (contribId != null && contribId.isNotEmpty) {
              finalContributorId = contribId;
              final contribMatch = _contributorsList.where((c) => c.id == contribId || c.name == contribId);
              if (contribMatch.isNotEmpty) {
                finalContributorName = contribMatch.first.name;
              } else {
                finalContributorName = contribId;
              }
              break;
            }
          } else if (f.isStaff) {
            final selectedStaffId = _selectedStaffIds[f.id];
            if (selectedStaffId != null && selectedStaffId.isNotEmpty) {
              finalContributorId = selectedStaffId;
              finalStaffId = selectedStaffId;
              final staffMatch = _staffList.where((s) => s.id == selectedStaffId || s.staffNo == selectedStaffId);
              if (staffMatch.isNotEmpty) {
                finalContributorName = staffMatch.first.fullName;
                finalStaffName = staffMatch.first.fullName;
              } else {
                finalContributorName = selectedStaffId;
                finalStaffName = selectedStaffId;
              }
              break;
            }
          }
        }
      }

      // Calculate itemized fees and discounts across all fee heads
      final List<_StudentFormFeeHead> feeHeads = [];

      if (_activeConditionConfig != null) {
        for (final f in _activeConditionConfig!.fields) {
          if (f.fieldType == 'number' && f.mathAction == 'add') {
            final ctrl = _getDynamicController(f.id);
            double val = double.tryParse(ctrl.text.trim()) ?? 0.0;
            final fLower = '${f.id} ${f.label}'.toLowerCase();
            if (val <= 0) {
              if (fLower.contains('monthly') || fLower.contains('tuition')) {
                val = double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
              } else if (fLower.contains('admission') || fLower.contains('dakhila')) {
                val = double.tryParse(_admissionFeeController.text.trim()) ?? 0.0;
              } else if (fLower.contains('book') || fLower.contains('kitab')) {
                val = double.tryParse(_bookFeeController.text.trim()) ?? 0.0;
              }
            }

            IconData icon = Icons.receipt_rounded;
            if (fLower.contains('monthly') || fLower.contains('tuition')) {
              icon = Icons.calendar_month_rounded;
            } else if (fLower.contains('admission') || fLower.contains('dakhila')) {
              icon = Icons.school_rounded;
            } else if (fLower.contains('book') || fLower.contains('kitab')) {
              icon = Icons.menu_book_rounded;
            } else if (fLower.contains('exam') || fLower.contains('imtihan')) {
              icon = Icons.assignment_rounded;
            }

            final m = _StudentFormFeeHead.resolveMonths(f, _sessionMonths, _availableFrequencies);
            final mList = _StudentFormFeeHead.resolveMonthsList(f, _availableFrequencies);
            final cleanTitle = f.label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
            feeHeads.add(_StudentFormFeeHead(
              id: f.id,
              title: cleanTitle,
              baseAmount: val * m,
              unitAmount: val,
              monthsCount: m,
              billingType: f.billingType,
              monthsList: mList,
              icon: icon,
            ));
          }
        }
      }

      final hasMonthly = feeHeads.any((h) =>
          h.id == 'monthly_fees' ||
          h.id.contains('month') ||
          h.title.toLowerCase().contains('month') ||
          h.title.toLowerCase().contains('tuition'));
      final monthlyTuitionVal = double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
      if (!hasMonthly && monthlyTuitionVal > 0) {
        final m = _sessionMonths > 0 ? _sessionMonths : 12;
        feeHeads.insert(
          0,
          _StudentFormFeeHead(
            id: 'monthly_fees',
            title: 'Monthly Tuition Fee',
            baseAmount: monthlyTuitionVal * m,
            unitAmount: monthlyTuitionVal,
            monthsCount: m,
            billingType: 'monthly',
            monthsList: BillingFrequencyOption.allMonths,
            icon: Icons.calendar_month_rounded,
          ),
        );
      }

      final hasAdmission = feeHeads.any((h) =>
          h.id == 'admission_fee' ||
          h.id.contains('admission') ||
          h.title.toLowerCase().contains('admission') ||
          h.title.toLowerCase().contains('dakhila'));
      final rawAdmissionFeeVal = double.tryParse(_admissionFeeController.text.trim()) ?? 0.0;
      if (!hasAdmission && rawAdmissionFeeVal > 0) {
        feeHeads.add(
          _StudentFormFeeHead(
            id: 'admission_fee',
            title: 'Admission Fee',
            baseAmount: rawAdmissionFeeVal,
            unitAmount: rawAdmissionFeeVal,
            monthsCount: 1,
            billingType: 'one_time',
            icon: Icons.school_rounded,
          ),
        );
      }

      final hasBook = feeHeads.any((h) =>
          h.id == 'book_fee' ||
          h.id.contains('book') ||
          h.title.toLowerCase().contains('book') ||
          h.title.toLowerCase().contains('kitab'));
      final rawBookFeeVal = double.tryParse(_bookFeeController.text.trim()) ?? 0.0;
      if (!hasBook && rawBookFeeVal > 0) {
        feeHeads.add(
          _StudentFormFeeHead(
            id: 'book_fee',
            title: 'Book Fee',
            baseAmount: rawBookFeeVal,
            unitAmount: rawBookFeeVal,
            monthsCount: 1,
            billingType: 'one_time',
            icon: Icons.menu_book_rounded,
          ),
        );
      }

      final double totalGrossVal = feeHeads.fold<double>(0.0, (sum, h) => sum + h.baseAmount);

      if (_activeConditionConfig != null) {
        for (final f in _activeConditionConfig!.fields) {
          if (f.fieldType == 'number' && f.isDeduction) {
            final raw = _getDynamicController(f.id).text.trim();
            if (raw.isEmpty) continue;

            final clean = raw.replaceAll('%', '').trim();
            final numVal = double.tryParse(clean) ?? 0.0;
            if (numVal <= 0.0) continue;

            final mode = _discountModes[f.id] ?? (f.discountMode == 'percentage' ? 'percentage' : 'flat');
            final isPercent = (mode == 'percentage') || raw.contains('%');
            final target = (_discountTargetFees[f.id] ?? f.targetFeeField).toLowerCase().trim();
            final dedMonths = _StudentFormFeeHead.resolveMonths(f, _sessionMonths, _availableFrequencies);

            if (target == 'all' || target.isEmpty) {
              final double effDiscount = isPercent
                  ? numVal
                  : (f.billingType == 'monthly' ? numVal * dedMonths : numVal);
              _distributeAllTargetDiscount(
                activeHeads: feeHeads.where((h) => h.baseAmount > 0).toList(),
                totalGross: totalGrossVal,
                numVal: effDiscount,
                isPercent: isPercent,
              );
            } else {
              _StudentFormFeeHead? targetHead;
              for (final head in feeHeads) {
                final hId = head.id.toLowerCase().trim();
                final hTitle = head.title.toLowerCase().trim();
                if (hId == target || hTitle == target) {
                  targetHead = head;
                  break;
                }
                if (target == 'monthly_fees' && (hId.contains('month') || hTitle.contains('month') || hTitle.contains('tuition'))) {
                  targetHead = head;
                  break;
                }
                if (target == 'admission_fee' && (hId.contains('admission') || hTitle.contains('admission') || hTitle.contains('dakhila'))) {
                  targetHead = head;
                  break;
                }
                if (target == 'book_fee' && (hId.contains('book') || hTitle.contains('book') || hTitle.contains('kitab'))) {
                  targetHead = head;
                  break;
                }
              }

              if (targetHead != null) {
                double headDisc = 0.0;
                String headTag = '';
                if (isPercent) {
                  headDisc = (targetHead.baseAmount * numVal) / 100.0;
                  final pctStr = numVal.truncateToDouble() == numVal
                      ? '${numVal.toInt()}%'
                      : (numVal < 1 ? '${numVal.toStringAsFixed(2)}%' : '${numVal.toStringAsFixed(1)}%');
                  headTag = '-₹${headDisc.toStringAsFixed(0)} ($pctStr)';
                } else {
                  final double effVal = f.billingType == 'monthly' ? (numVal * dedMonths) : numVal;
                  headDisc = effVal.clamp(0.0, targetHead.baseAmount);
                  final pct = targetHead.baseAmount > 0 ? (headDisc / targetHead.baseAmount) * 100.0 : 0.0;
                  final pctStr = pct.truncateToDouble() == pct
                      ? '${pct.toInt()}%'
                      : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
                  headTag = f.billingType == 'monthly' && dedMonths > 1
                      ? '-₹${headDisc.toStringAsFixed(0)} ($dedMonths mo × ₹${numVal.toStringAsFixed(0)})'
                      : (pct > 0 ? '-₹${headDisc.toStringAsFixed(0)} ($pctStr)' : '-₹${headDisc.toStringAsFixed(0)}');
                }
                targetHead.discount += headDisc;
                targetHead.discountTag = headTag;
              }
            }
          }
        }
      } else {
        final contribAmt = double.tryParse(_contributorAmountController.text.trim()) ?? 0.0;
        if (contribAmt > 0 && feeHeads.isNotEmpty) {
          final m = feeHeads.first.monthsCount > 0 ? feeHeads.first.monthsCount : 1;
          final effDisc = feeHeads.first.billingType == 'monthly' ? (contribAmt * m) : contribAmt;
          feeHeads.first.discount = effDisc.clamp(0.0, feeHeads.first.baseAmount);
          final pct = feeHeads.first.baseAmount > 0 ? (feeHeads.first.discount / feeHeads.first.baseAmount) * 100.0 : 0.0;
          final pctStr = pct.truncateToDouble() == pct
              ? '${pct.toInt()}%'
              : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
          feeHeads.first.discountTag = pct > 0
              ? '-₹${feeHeads.first.discount.toStringAsFixed(0)} ($pctStr)'
              : '-₹${feeHeads.first.discount.toStringAsFixed(0)}';
        }
      }

      final double totalDiscountVal = feeHeads.fold<double>(0.0, (sum, h) => sum + h.discount);

      // Extract specific fee heads for Student model fields
      final monthlyHead = feeHeads.where((h) =>
          h.id == 'monthly_fees' ||
          h.id.contains('month') ||
          h.title.toLowerCase().contains('month') ||
          h.title.toLowerCase().contains('tuition')).firstOrNull;
      final admissionHead = feeHeads.where((h) =>
          h.id == 'admission_fee' ||
          h.id.contains('admission') ||
          h.title.toLowerCase().contains('admission') ||
          h.title.toLowerCase().contains('dakhila')).firstOrNull;
      final bookHead = feeHeads.where((h) =>
          h.id == 'book_fee' ||
          h.id.contains('book') ||
          h.title.toLowerCase().contains('book') ||
          h.title.toLowerCase().contains('kitab')).firstOrNull;

      final double finalMonthlyFees = monthlyHead != null
          ? monthlyHead.netUnitAmount
          : (double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0);
      final double? admissionFeeVal = (admissionHead != null && admissionHead.baseAmount > 0) ? admissionHead.baseAmount : null;
      final double? bookFeeVal = (bookHead != null && bookHead.baseAmount > 0) ? bookHead.baseAmount : null;
      // Extract specific contributor or staff amount if configured in condition
      double? specificContributorAmount;
      if (_activeConditionConfig != null) {
        for (final f in _activeConditionConfig!.fields) {
          final isContribOrStaffAmount = f.fieldType == 'number' &&
              (f.fieldSource == 'contributor' ||
               f.fieldSource == 'staff' ||
               f.isContributor ||
               f.isStaff ||
               f.id == 'contributor_amount' ||
               f.id.startsWith('contributor_amount') ||
               f.id == 'staff_discount' ||
               f.id.startsWith('staff_amount') ||
               f.label.toLowerCase().contains('contributor') ||
               f.label.toLowerCase().contains('staff'));
          if (isContribOrStaffAmount) {
            final ctrl = _getDynamicController(f.id);
            final raw = ctrl.text.trim().replaceAll('%', '').replaceAll(',', '');
            final val = double.tryParse(raw);
            if (val != null && val > 0) {
              specificContributorAmount = val;
              break;
            }
          }
        }
      }

      final double? finalContributorAmount = specificContributorAmount ??
          (totalDiscountVal > 0
              ? totalDiscountVal
              : (double.tryParse(_contributorAmountController.text.trim()) != null &&
                      (double.tryParse(_contributorAmountController.text.trim())! > 0)
                  ? double.tryParse(_contributorAmountController.text.trim())
                  : null));

      String? savedDiscountInput;
      String? savedDiscountMode;
      String? savedDiscountTarget;
      if (_activeConditionConfig != null) {
        for (final f in _activeConditionConfig!.fields) {
          if (f.fieldType == 'number' && f.isDeduction) {
            final raw = _getDynamicController(f.id).text.trim();
            if (raw.isNotEmpty) {
              savedDiscountInput = raw.replaceAll('%', '').trim();
              savedDiscountMode = _discountModes[f.id] ?? (f.discountMode == 'percentage' ? 'percentage' : 'flat');
              savedDiscountTarget = (_discountTargetFees[f.id] ?? f.targetFeeField).toLowerCase().trim();
              break;
            }
          }
        }
      }

      final List<Map<String, dynamic>> feeStructureList = [];
      for (final head in feeHeads) {
        if (head.baseAmount > 0) {
          final isMonthly = head.billingType == 'monthly' ||
              head.id == 'monthly_fees' ||
              head.title.toLowerCase().contains('month') ||
              head.title.toLowerCase().contains('tuition');
          final mCount = head.monthsCount;
          feeStructureList.add({
            'fee_type_id': head.id,
            'fee_type_name': head.title,
            'amount': isMonthly ? head.netUnitAmount : head.netAmount,
            'original_amount': head.baseAmount,
            'unit_amount': head.unitAmount,
            'discount_amount': head.discount,
            'discount_tag': head.discountTag,
            'net_amount': head.netAmount,
            'billing_type': head.billingType,
            'months_count': mCount,
            'months_list': head.monthsList,
            'total_expected': head.netAmount,
            if (savedDiscountInput != null) 'discount_input': savedDiscountInput,
            if (savedDiscountMode != null) 'discount_mode': savedDiscountMode,
            if (savedDiscountTarget != null) 'discount_target': savedDiscountTarget,
            if (finalStaffId != null) 'staff_id': finalStaffId,
            if (finalStaffName != null) 'staff_name': finalStaffName,
          });
        }
      }
      final feeStructureStr = feeStructureList.isNotEmpty ? jsonEncode(feeStructureList) : null;

      final subDepartmentsData = _selectedSubDeptEntries.map((e) {
        final divVal = e.showCustomDivisionField
            ? e.customDivisionController.text.trim()
            : (e.division ?? '');
        return StudentSubDepartment(
          subDepartmentId: e.subDepartmentId,
          subDepartmentName: e.subDepartmentName,
          className: e.className ?? '',
          division: divVal,
        );
      }).toList();

      final deptObj = _allDepartments.where(
        (d) => d['id']?.toString() == _selectedDepartmentId,
      ).firstOrNull;
      final departmentName = deptObj != null ? deptObj['name']?.toString() : null;

      final existingId = widget.student?.id.trim();
      final currentGrNo = _grNoController.text.trim();
      final cleanGr = currentGrNo.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final studentId = (existingId != null && existingId.isNotEmpty)
          ? existingId
          : 'std_${DateTime.now().millisecondsSinceEpoch}_$cleanGr';

      final student = Student(
        id: studentId,
        grNo: _grNoController.text,
        registrationNumber: _grNoController.text,
        fullName: _nameController.text,
        fatherName: _fatherNameController.text,
        surname: _surnameController.text,
        grandFatherName: _grandFatherNameController.text,
        dateOfBirth: _dobController.text,
        village: _villageController.text,
        taluka: _talukaController.text,
        district: _districtController.text,
        state: _stateController.text,
        pinCode: _pinCodeController.text,
        address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        mobileNo: mobileFinal,
        aadhaarNo: aadhaarFinal,
        className: _selectedClass,
        studentStatus: _selectedStatus,
        admissionType: _admissionType,
        admissionDate: _admissionDateController.text,
        admissionDateH: _admissionDateHController.text,
        conditionType: _conditionType,
        monthlyFees: finalMonthlyFees,
        gender: _gender,
        category: _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : null,
        division: _divisionController.text.trim().isNotEmpty ? _divisionController.text.trim() : null,
        enrollmentDate: _admissionDateController.text,
        isActive: _selectedStatus.toLowerCase() != 'inactive',
        admissionTimeAge: _admissionTimeAge,
        nowAge: _nowAge,
        photoPath: _photoPath,
        contributorId: finalContributorId,
        contributorAmount: finalContributorAmount,
        departmentId: _selectedDepartmentId,
        departmentName: departmentName,
        subDepartments: subDepartmentsData,
        admissionFee: admissionFeeVal,
        bookFee: bookFeeVal,
        feeStructure: feeStructureStr,
        staffId: finalStaffId,
        staffName: finalStaffName,
      );

      setState(() => _isSubmitting = true);

      final api = ApiClient();
      Future<void> saveCall() async {
        final studentData = student.toJson();
        if (finalContributorName != null && finalContributorName.isNotEmpty) {
          studentData['contributor_name'] = finalContributorName;
        }
        if (finalStaffId != null && finalStaffId.isNotEmpty) {
          studentData['staff_id'] = finalStaffId;
        }
        if (finalStaffName != null && finalStaffName.isNotEmpty) {
          studentData['staff_name'] = finalStaffName;
        }

        // 1. Direct Local SQLite Save (Offline First guarantee)
        bool localSuccess = false;
        try {
          await DatabaseHelper().saveStudentDirectly(studentData);
          localSuccess = true;
        } catch (dbErr) {
          debugPrint('Local SQLite direct save note: $dbErr');
        }

        // 2. Direct Cloud Sync (Firebase Firestore)
        try {
          unawaited(FirebaseService.syncStudent(studentData));
        } catch (fbErr) {
          debugPrint('Firebase student sync note: $fbErr');
        }

        // 3. Backend API Sync (if backend server is running)
        try {
          if (widget.student == null) {
            await api.post('/students', data: studentData);
          } else {
            await api.put('/students/${student.id}', data: studentData);
          }
        } catch (apiErr) {
          debugPrint('Backend server API note (offline mode): $apiErr');
          if (!localSuccess) {
            rethrow;
          }
        }
      }

      saveCall().then((_) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          context.read<StudentsBloc>().add(LoadStudents(silent: true));

          if (widget.student == null) {
            // New Student creation: Keep form open, advance GR No., and reset fields for the next student entry!
            _clearFields(fetchNextGr: true, lastSavedGrNo: currentGrNo);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Student created successfully. Ready for next entry!'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          } else {
            // Edit Student: Keep form open, stop loading and show confirmation!
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Student updated successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      }).catchError((e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          String errorMsg = 'Failed to save student';
          if (e is DioException && e.response != null) {
            errorMsg = e.response?.data['message'] ?? e.response?.data['error'] ?? errorMsg;
          } else {
            errorMsg = e.toString().replaceAll('Exception: ', '');
          }

          // Custom localization mapping for duplicate GR number
          if (errorMsg.contains('GR.NO. already exists')) {
            errorMsg = 'This GR Number already exists. Please choose a unique GR Number.';
          }
          
          showDialog(
            context: context,
            barrierColor: Colors.transparent,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
                  const SizedBox(width: 10),
                  Text('Error', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(errorMsg, style: AppTheme.getFontStyle()),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      });
    }
  }

  void _clearFields({bool fetchNextGr = true, String? lastSavedGrNo}) {
    _formKey.currentState?.reset();
    _grNoController.clear();
    _nameController.clear();
    _fatherNameController.clear();
    _surnameController.clear();
    _grandFatherNameController.clear();
    _dobController.clear();
    _villageController.clear();
    _talukaController.clear();
    _districtController.clear();
    _stateController.clear();
    _pinCodeController.clear();
    _addressController.clear();
    _mobileController.clear();
    _aadhaarController.clear();
    _admissionDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _admissionDateHController.clear();
    _monthlyFeesController.clear();
    _admissionFeeController.clear();
    _bookFeeController.clear();
    _monthlyFeesMonthsController.text = '12';
    _contributorAmountController.clear();
    _totalFeesController.clear();
    for (final ctrl in _feeHeadAmountControllers.values) {
      ctrl.clear();
    }
    for (final ctrl in _dynamicFeeControllers.values) {
      ctrl.clear();
    }
    _selectedStaffIds.clear();
    _selectedContributorIds.clear();

    setState(() {
      _isSubmitting = false;
      _photoPath = null;
      _selectedDepartmentId = null;
      _selectedSubDeptEntries.clear();
      _availableSubDepartments = [];
      _selectedClass = null;
      _selectedDivision = null;
      _divisionController.clear();
      _categoryController.clear();
      _showCustomDivisionField = false;
      _selectedContributorId = null;
      _admissionType = 'New';
      _conditionType = 'Regular';
      _originalConditionType = null;
      _gender = null;
      _admissionTimeAge = '';
      _nowAge = '';
      _lastFetchedPinCode = '';
      _pinCodeVillages = [];
      _villageSuggestions = [];
      _showVillageDropdown = false;
    });

    _updateAvailableSubDeptsAndClasses(resetClass: false);
    _updateDivisionsList();
    _updateHijriDate();

    if (fetchNextGr) {
      _getNextGRNo(lastSavedGrNo: lastSavedGrNo);
    }
  }

  @override
  void dispose() {
    _villageDebounce?.cancel();
    _grNoController.dispose();
    _nameController.dispose();
    _fatherNameController.dispose();
    _surnameController.dispose();
    _grandFatherNameController.dispose();
    _dobController.dispose();
    _villageController.dispose();
    _talukaController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _pinCodeController.dispose();
    _addressController.dispose();
    _mobileController.dispose();
    _aadhaarController.dispose();
    _admissionDateController.dispose();
    _admissionDateHController.dispose();
    _monthlyFeesController.dispose();
    _admissionFeeController.dispose();
    _bookFeeController.dispose();
    _monthlyFeesMonthsController.dispose();
    for (final ctrl in _feeHeadAmountControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _feeHeadMonthsControllers.values) {
      ctrl.dispose();
    }
    _contributorAmountController.dispose();
    _totalFeesController.dispose();
    super.dispose();
  }

  void _updateTotalFees() {
    _totalFeesController.text = _totalFees.toStringAsFixed(0);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isEdit = widget.student != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final formContent = DefaultTextEditingShortcuts(
      child: Form(
        key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                      // Section 1 — Basic Info
                      _sectionTitle('Basic Information', Icons.person_rounded, isDark),
                      const SizedBox(height: 14),
                      context.isMobile
                          ? Column(
                              children: [
                                Center(
                                  child: GestureDetector(
                                    onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                                    child: Container(
                                      width: 110,
                                      height: 130,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white10 : Colors.black.withAlpha(5),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                                          width: 1.5,
                                        ),
                                        image: _photoPath != null
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                  '${ApiConstants.baseUrl.replaceAll("/api", "")}$_photoPath',
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                      ),
                                      child: _photoPath == null
                                          ? Center(
                                              child: _isUploadingPhoto
                                                  ? const CircularProgressIndicator()
                                                  : Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(
                                                          Icons.add_a_photo_rounded,
                                                          size: 26,
                                                          color: AppTheme.primaryColor,
                                                        ),
                                                        const SizedBox(height: 6),
                                                        Text(
                                                          'Upload Photo',
                                                          textAlign: TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: isDark ? Colors.white70 : Colors.black54,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _buildField(
                                  label: context.tr('gr_no_dot'),
                                  controller: _grNoController,
                                  icon: Icons.badge_rounded,
                                  isDark: isDark,
                                  flex: 1,
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                  suffix: _isLoadingGR
                                      ? const SizedBox(
                                          width: 16, height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : GestureDetector(
                                          onTap: () {
                                            final grNo = _grNoController.text.trim();
                                            if (grNo.isNotEmpty) _fetchStudentByGRNo(grNo);
                                          },
                                          child: Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryColor),
                                        ),
                                ),
                                const SizedBox(height: 12),
                                 _buildStatusDropdownTile(isDark),
                                const SizedBox(height: 12),
                                _buildDropdownField(
                                  label: '${context.tr('gender')} *',
                                  value: _gender,
                                  items: _genders,
                                  icon: Icons.wc_rounded,
                                  isDark: isDark,
                                  flex: 1,
                                  onChanged: (v) => setState(() => _gender = v),
                                  validator: (v) => v == null ? 'Required' : null,
                                ),
                                const SizedBox(height: 14),
                                _buildField(
                                  label: '${context.tr('name')} *',
                                  controller: _nameController,
                                  icon: Icons.person_outline_rounded,
                                  isDark: isDark,
                                  flex: 2,
                                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                ),
                                const SizedBox(height: 14),
                                _buildField(
                                  label: '${context.tr('father_name')} *',
                                  controller: _fatherNameController,
                                  icon: Icons.person_outline_rounded,
                                  isDark: isDark,
                                  flex: 2,
                                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Photo Uploader Widget
                                GestureDetector(
                                  onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 120,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white10 : Colors.black.withAlpha(12),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isDark ? Colors.white24 : Colors.black12,
                                            width: 2,
                                          ),
                                          image: _photoPath != null
                                              ? DecorationImage(
                                                  image: NetworkImage(
                                                    '${ApiConstants.baseUrl.replaceAll("/api", "")}$_photoPath',
                                                  ),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: _photoPath == null
                                            ? Center(
                                                child: _isUploadingPhoto
                                                    ? const CircularProgressIndicator()
                                                    : Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          Icon(
                                                            Icons.add_a_photo_rounded,
                                                            size: 32,
                                                            color: isDark ? Colors.white70 : Colors.black54,
                                                          ),
                                                          const SizedBox(height: 8),
                                                          Text(
                                                            'Upload Photo',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: isDark ? Colors.white70 : Colors.black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              )
                                            : null,
                                      ),
                                      if (_photoPath != null)
                                        Positioned(
                                          bottom: 4,
                                          right: 4,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.edit,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                // Fields
                                Expanded(
                                  child: Column(
                                    children: [
                                      _buildRow(children: [
                                        _buildField(
                                          label: context.tr('gr_no_dot'),
                                          controller: _grNoController,
                                          icon: Icons.badge_rounded,
                                          isDark: isDark,
                                          flex: 1,
                                          validator: (v) => v!.isEmpty ? 'Required' : null,
                                          suffix: _isLoadingGR
                                              ? const SizedBox(
                                                  width: 16, height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'Configure G.R. No. Format Series',
                                                      icon: const Icon(Icons.settings_rounded, size: 18, color: AppTheme.primaryColor),
                                                      onPressed: () async {
                                                        final res = await _openSubDialog(() => GrNoConfigDialog.show(context, barrierColor: Colors.transparent));
                                                        if (res != null) {
                                                          _getNextGRNo();
                                                        }
                                                      },
                                                    ),
                                                    GestureDetector(
                                                      onTap: () {
                                                        final grNo = _grNoController.text.trim();
                                                        if (grNo.isNotEmpty) _fetchStudentByGRNo(grNo);
                                                      },
                                                      child: Icon(Icons.search_rounded, size: 18, color: AppTheme.primaryColor),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                        const SizedBox(width: 16),
                                         _buildStatusDropdownTile(isDark),
                                        const SizedBox(width: 16),
                                        _buildDropdownField(
                                          label: '${context.tr('gender')} *',
                                          value: _gender,
                                          items: _genders,
                                          icon: Icons.wc_rounded,
                                          isDark: isDark,
                                          flex: 1,
                                          onChanged: (v) => setState(() => _gender = v),
                                          validator: (v) => v == null ? 'Required' : null,
                                          suffix: IconButton(
                                            tooltip: 'Add / Edit Gender Options',
                                            icon: const Icon(Icons.settings_suggest_rounded, size: 18, color: Color(0xFF0D6B4E)),
                                            onPressed: () async {
                                              await _openSubDialog(() => ManageFormOptionsDialog.show(
                                                context: context,
                                                title: 'Manage Gender Options',
                                                icon: Icons.wc_rounded,
                                                themeColor: const Color(0xFF0D6B4E),
                                                getOptions: StudentFormOptionsSettings.getGenders,
                                                saveOptions: StudentFormOptionsSettings.saveGenders,
                                                barrierColor: Colors.transparent,
                                              ));
                                              _loadFormOptions();
                                            },
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: 14),
                                      _buildRow(children: [
                                        _buildField(
                                          label: '${context.tr('name')} *',
                                          controller: _nameController,
                                          icon: Icons.person_outline_rounded,
                                          isDark: isDark,
                                          flex: 2,
                                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                        ),
                                        const SizedBox(width: 16),
                                        _buildField(
                                          label: '${context.tr('father_name')} *',
                                          controller: _fatherNameController,
                                          icon: Icons.family_restroom_rounded,
                                          isDark: isDark,
                                          flex: 2,
                                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildField(
                          label: '${context.tr('surname')} *',
                          controller: _surnameController,
                          icon: Icons.abc_rounded,
                          isDark: isDark,
                          flex: 1,
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(width: 16),
                        _buildField(
                          label: context.tr('grand_father_name'),
                          controller: _grandFatherNameController,
                          icon: Icons.elderly_rounded,
                          isDark: isDark,
                          flex: 2,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildDateField(
                          label: '${context.tr('date_of_birth')} *',
                          controller: _dobController,
                          isDark: isDark,
                          flex: 1,
                          onTap: () => _selectDate(_dobController),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(width: 16),
                        _buildField(
                          label: context.tr('category'),
                          controller: _categoryController,
                          icon: Icons.category_rounded,
                          isDark: isDark,
                          flex: 1,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildDropdownFieldWithItems<String?>(
                          label: context.tr('department'),
                          value: _selectedDepartmentId,
                          items: _buildMainDeptDropdownItems(),
                          icon: Icons.business_center_rounded,
                          isDark: isDark,
                          flex: 1,
                          onChanged: (v) {
                            setState(() {
                              _selectedDepartmentId = v;
                              _selectedSubDeptEntries.clear();
                            });
                            _updateAvailableSubDeptsAndClasses();
                            _updateDivisionsList();
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildDropdownField(
                          label: '${context.tr('class_name')} *',
                          value: _selectedClass,
                          items: _classes,
                          icon: Icons.class_rounded,
                          isDark: isDark,
                          flex: 1,
                          onChanged: (v) {
                            setState(() {
                              _selectedClass = v;
                            });
                            _updateDivisionsList();
                          },
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildDropdownField(
                          label: context.tr('division'),
                          value: _divisions.contains(_selectedDivision) ? _selectedDivision : (_selectedDivision != null ? 'Custom...' : null),
                          items: [..._divisions, 'Custom...'],
                          icon: Icons.grid_view_rounded,
                          isDark: isDark,
                          flex: 1,
                          onChanged: (v) {
                            setState(() {
                              _selectedDivision = v;
                              if (v == 'Custom...') {
                                _showCustomDivisionField = true;
                                _divisionController.clear();
                              } else {
                                _showCustomDivisionField = false;
                                _divisionController.text = v ?? '';
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 16),
                        const Spacer(),
                      ]),
                      if (_showCustomDivisionField) ...[
                        const SizedBox(height: 14),
                        _buildRow(children: [
                          _buildField(
                            label: 'Custom Main Division Name',
                            controller: _divisionController,
                            icon: Icons.edit_note_rounded,
                            isDark: isDark,
                            flex: 1,
                          ),
                          const SizedBox(width: 16),
                          const Spacer(),
                        ]),
                      ],
                      _buildSubDepartmentsSection(isDark),

                      const SizedBox(height: 24),
                      // Section 2 — Admission
                      _sectionTitle('Admission Details', Icons.school_rounded, isDark),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildDropdownField(
                          label: context.tr('admission_type'),
                          value: _admissionType,
                          items: _admissionTypes,
                          icon: Icons.login_rounded,
                          isDark: isDark,
                          flex: 1,
                          onChanged: (v) => setState(() => _admissionType = v!),
                          suffix: IconButton(
                            tooltip: 'Add / Edit Admission Types',
                            icon: const Icon(Icons.settings_suggest_rounded, size: 18, color: Color(0xFF1565C0)),
                            onPressed: () async {
                              await _openSubDialog(() => ManageFormOptionsDialog.show(
                                context: context,
                                title: 'Manage Admission Types',
                                icon: Icons.login_rounded,
                                themeColor: const Color(0xFF1565C0),
                                getOptions: StudentFormOptionsSettings.getAdmissionTypes,
                                saveOptions: StudentFormOptionsSettings.saveAdmissionTypes,
                                barrierColor: Colors.transparent,
                              ));
                              _loadFormOptions();
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        _buildDateField(
                          label: context.tr('admission_date'),
                          controller: _admissionDateController,
                          isDark: isDark,
                          flex: 1,
                          onTap: () => _selectDate(_admissionDateController),
                        ),
                        const SizedBox(width: 16),
                        _buildField(
                          label: context.tr('admission_date_hijri'),
                          controller: _admissionDateHController,
                          icon: Icons.mosque_rounded,
                          isDark: isDark,
                          flex: 1,
                          readOnly: true,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      // Age info box
                      Builder(
                        builder: (context) {
                          final width = MediaQuery.of(context).size.width;
                          final scale = (width / 375.0).clamp(0.75, 1.0);
                          return Container(
                            padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2A2A3E) : AppTheme.primaryColor.withAlpha(12),
                              borderRadius: BorderRadius.circular(12 * scale),
                              border: Border.all(
                                color: isDark ? Colors.white.withAlpha(15) : AppTheme.primaryColor.withAlpha(30),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.cake_rounded, size: 18 * scale, color: AppTheme.primaryColor),
                                SizedBox(width: 10 * scale),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.tr('admission_time_age'),
                                              style: AppTheme.getFontStyle(
                                                fontSize: 10 * scale,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                              ),
                                            ),
                                            SizedBox(height: 2 * scale),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                _admissionTimeAge.isNotEmpty
                                                    ? _formatAgeString(context, _admissionTimeAge)
                                                    : context.tr('enter_dob_admission_date'),
                                                style: AppTheme.getFontStyle(
                                                  fontSize: 12 * scale,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(width: 1, height: 28 * scale, color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade300),
                                      SizedBox(width: 10 * scale),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.tr('now_age'),
                                              style: AppTheme.getFontStyle(
                                                fontSize: 10 * scale,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                              ),
                                            ),
                                            SizedBox(height: 2 * scale),
                                            FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                _nowAge.isNotEmpty
                                                    ? _formatAgeString(context, _nowAge)
                                                    : context.tr('enter_dob'),
                                                style: AppTheme.getFontStyle(
                                                  fontSize: 12 * scale,
                                                  fontWeight: FontWeight.w700,
                                                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),
                      // Section 3 — Contact
                      _sectionTitle('Contact Details', Icons.contact_phone_rounded, isDark),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildField(
                          label: '${context.tr('mobile')} *',
                          controller: _mobileController,
                          icon: Icons.phone_rounded,
                          isDark: isDark,
                          flex: 1,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length != 10) return '10 digits required';
                            return null;
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildField(
                          label: '${context.tr('aadhaar_no')} *',
                          controller: _aadhaarController,
                          icon: Icons.credit_card_rounded,
                          isDark: isDark,
                          flex: 1,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(12),
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length != 12) return '12 digits required';
                            return null;
                          },
                        ),
                      ]),

                      const SizedBox(height: 24),
                      // Section 4 — Address
                      _sectionTitle('Address', Icons.location_on_rounded, isDark),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildField(
                          label: '${context.tr('address')} (${context.tr('optional')})',
                          controller: _addressController,
                          icon: Icons.home_work_rounded,
                          isDark: isDark,
                          flex: 1,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        // Pincode
                        context.isMobile
                            ? Builder(
                                builder: (context) {
                                  final width = MediaQuery.of(context).size.width;
                                  final scale = (width / 375.0).clamp(0.75, 1.0);
                                  return TextFormField(
                                    controller: _pinCodeController,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(6),
                                    ],
                                    style: AppTheme.getFontStyle(fontSize: 13 * scale),
                                    decoration: _inputDecoration(
                                      context.tr('pincode'),
                                      Icons.pin_drop_rounded,
                                      isDark,
                                      suffix: _isFetchingPin
                                          ? SizedBox(
                                              width: 16 * scale,
                                              height: 16 * scale,
                                              child: const CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : null,
                                    ),
                                  );
                                },
                              )
                            : Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _pinCodeController,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  style: AppTheme.getFontStyle(fontSize: 14),
                                  decoration: _inputDecoration(
                                    context.tr('pincode'),
                                    Icons.pin_drop_rounded,
                                    isDark,
                                    suffix: _isFetchingPin
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : null,
                                  ),
                                ),
                              ),
                        const SizedBox(width: 16),
                        // Village with dropdown
                        context.isMobile
                            ? Builder(
                                builder: (context) {
                                  final width = MediaQuery.of(context).size.width;
                                  final scale = (width / 375.0).clamp(0.75, 1.0);
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TextFormField(
                                        controller: _villageController,
                                        textInputAction: TextInputAction.next,
                                        onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                                        style: AppTheme.getFontStyle(fontSize: 13 * scale),
                                        decoration: _inputDecoration(
                                          context.tr('village'),
                                          Icons.location_city_rounded,
                                          isDark,
                                          suffix: _pinCodeVillages.isNotEmpty
                                              ? GestureDetector(
                                                  onTap: () => setState(() {
                                                    _villageSuggestions = _pinCodeVillages;
                                                    _showVillageDropdown = !_showVillageDropdown;
                                                  }),
                                                  child: Icon(
                                                    _showVillageDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                                    color: AppTheme.primaryColor,
                                                    size: 20 * scale,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                      if (_showVillageDropdown && _villageSuggestions.isNotEmpty)
                                        Container(
                                          constraints: BoxConstraints(maxHeight: 160 * scale),
                                          margin: EdgeInsets.only(top: 4 * scale),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                            borderRadius: BorderRadius.circular(10 * scale),
                                            border: Border.all(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200),
                                            boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8 * scale)],
                                          ),
                                          child: ListView(
                                            shrinkWrap: true,
                                            children: _villageSuggestions
                                                .map((v) => InkWell(
                                                      onTap: () => _selectVillage(v),
                                                      child: Padding(
                                                        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 9 * scale),
                                                        child: Text(v, style: AppTheme.getFontStyle(fontSize: 13 * scale)),
                                                      ),
                                                    ))
                                                .toList(),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              )
                            : Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextFormField(
                                      controller: _villageController,
                                      textInputAction: TextInputAction.next,
                                      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                                      style: AppTheme.getFontStyle(fontSize: 14),
                                      decoration: _inputDecoration(
                                        context.tr('village'),
                                        Icons.location_city_rounded,
                                        isDark,
                                        suffix: _pinCodeVillages.isNotEmpty
                                            ? GestureDetector(
                                                onTap: () => setState(() {
                                                  _villageSuggestions = _pinCodeVillages;
                                                  _showVillageDropdown = !_showVillageDropdown;
                                                }),
                                                child: Icon(
                                                  _showVillageDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                                  color: AppTheme.primaryColor,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                    if (_showVillageDropdown && _villageSuggestions.isNotEmpty)
                                      Container(
                                        constraints: const BoxConstraints(maxHeight: 160),
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200),
                                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8)],
                                        ),
                                        child: ListView(
                                          shrinkWrap: true,
                                          children: _villageSuggestions
                                              .map((v) => InkWell(
                                                    onTap: () => _selectVillage(v),
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                      child: Text(v, style: AppTheme.getFontStyle(fontSize: 13)),
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                        const SizedBox(width: 16),
                        _buildField(
                          label: context.tr('taluka'),
                          controller: _talukaController,
                          icon: Icons.map_rounded,
                          isDark: isDark,
                          flex: 1,
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildField(
                          label: context.tr('district'),
                          controller: _districtController,
                          icon: Icons.location_on_rounded,
                          isDark: isDark,
                          flex: 1,
                        ),
                        const SizedBox(width: 16),
                        _buildField(
                          label: context.tr('state'),
                          controller: _stateController,
                          icon: Icons.flag_rounded,
                          isDark: isDark,
                          flex: 1,
                        ),
                      ]),

                      const SizedBox(height: 24),
                      // Section 5 — Fees
                      _sectionTitle('Fees & Condition', Icons.currency_rupee_rounded, isDark),
                      const SizedBox(height: 14),
                      _buildRow(children: [
                        _buildDropdownField(
                          label: context.tr('condition'),
                          value: _conditionType,
                          items: _conditions,
                          icon: Icons.tune_rounded,
                          isDark: isDark,
                          flex: 1,
                          onChanged: (v) {
                            if (v != null && v != _conditionType) {
                              setState(() => _conditionType = v);
                              _loadActiveConditionConfig(isConditionChangedByUser: true);
                            }
                          },
                          suffix: IconButton(
                            tooltip: 'Configure Fee Conditions & Fields',
                            icon: const Icon(Icons.settings_suggest_rounded, size: 18, color: Color(0xFFD4AF37)),
                            onPressed: () async {
                              await _openSubDialog(() => ManageFeeConditionsDialog.show(context, initialTabIndex: 0, barrierColor: Colors.transparent));
                              _loadFormOptions();
                              await _loadFeeTypes();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _buildDynamicConditionFields(isDark),
                      const SizedBox(height: 16),
                      _buildNetFeeSummaryBanner(isDark),
                    ],
                  ),
                ),
              );

    final width = MediaQuery.of(context).size.width;
    final isMobile = context.isMobile || width < 700;
    final scale = isMobile ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

    final Widget mainWidget;
    if (isMobile) {
      mainWidget = Scaffold(
        backgroundColor: isDark ? const Color(0xFF141421) : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark, isEdit),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * scale,
                    vertical: 20 * scale,
                  ),
                  child: formContent,
                ),
              ),
              _buildFooter(isDark, isEdit),
            ],
          ),
        ),
      );
    } else {
      final screenSize = MediaQuery.of(context).size;
      mainWidget = MovableResizableDialog(
        initialWidth: min(920.0, screenSize.width - 24),
        initialHeight: (screenSize.height * 0.90).clamp(380.0, 850.0),
        minWidth: min(480.0, screenSize.width - 24),
        minHeight: min(380.0, screenSize.height - 24),
        borderRadius: BorderRadius.circular(24),
        headerDecoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
          ),
        ),
        headerLeading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withAlpha(25),
          ),
          child: const Icon(Icons.school_rounded, color: Colors.white, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit
                  ? context.tr('edit_student')
                  : context.tr('add_new_student'),
              style: AppTheme.getFontStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              isEdit
                  ? context.tr('update_student_details_subtitle')
                  : context.tr('add_student_details_subtitle'),
              style: AppTheme.getFontStyle(
                fontSize: 11.5,
                color: Colors.white.withAlpha(180),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: formContent,
        ),
        actions: _buildFooter(isDark, isEdit),
      );
    }

    return Visibility(
      visible: !_isChildDialogOpen,
      maintainState: true,
      maintainSize: false,
      maintainAnimation: false,
      maintainInteractivity: false,
      child: mainWidget,
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, bool isEdit) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = context.isMobile || width < 700;
    final scale = isMobile ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

    if (isMobile) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          16 * scale,
          18 * scale,
          16 * scale,
          16 * scale,
        ),
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
                    isEdit
                        ? context.tr('edit_student')
                        : context.tr('add_new_student'),
                    style: AppTheme.getFontStyle(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isEdit
                        ? context.tr('update_student_details_subtitle')
                        : context.tr('add_student_details_subtitle'),
                    style: AppTheme.getFontStyle(
                      fontSize: 12 * scale,
                      color: Colors.white.withAlpha(180),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(25),
            ),
            child:
                const Icon(Icons.school_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit
                      ? context.tr('edit_student')
                      : context.tr('add_new_student'),
                  style: AppTheme.getFontStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  isEdit
                      ? context.tr('update_student_details_subtitle')
                      : context.tr('add_student_details_subtitle'),
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    color: Colors.white.withAlpha(180),
                  ),
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
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isDark, bool isEdit) {
    if (context.isMobile) {
      final width = MediaQuery.of(context).size.width;
      final scale = (width / 375.0).clamp(0.75, 1.0);
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
          ),
        ),
        child: _isSubmitting
            ? const Center(child: CircularProgressIndicator())
            : SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D6B4E),
                    padding: EdgeInsets.symmetric(vertical: 12 * scale),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20 * scale),
                    ),
                  ),
                  child: Text(
                    isEdit ? 'Update Student' : 'Save Student',
                    style: AppTheme.getFontStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14 * scale,
                    ),
                  ),
                ),
              ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
          ),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _clearFields,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('clear')),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            label: Text(context.tr('cancel')),
          ),
          const Spacer(),
          if (_isSubmitting)
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            FilledButton.icon(
              onPressed: _submit,
              icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded),
              label: Text(
                isEdit ? context.tr('update_student') : context.tr('add_new_student'),
                style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  TextEditingController _getDynamicController(String fieldId) {
    if (fieldId == 'monthly_fees') return _monthlyFeesController;
    if (fieldId == 'contributor_amount') return _contributorAmountController;
    if (fieldId == 'admission_fee') return _admissionFeeController;
    if (fieldId == 'book_fee') return _bookFeeController;
    if (!_dynamicFeeControllers.containsKey(fieldId)) {
      final ctrl = TextEditingController();
      ctrl.addListener(_recalculateDynamicFees);
      _dynamicFeeControllers[fieldId] = ctrl;
    }
    return _dynamicFeeControllers[fieldId]!;
  }

  void _recalculateDynamicFees() {
    if (_activeConditionConfig != null) {
      final rawMap = <String, String>{};
      for (final field in _activeConditionConfig!.fields) {
        if (field.fieldType == 'number') {
          rawMap[field.id] = _getDynamicController(field.id).text;
        }
      }
      final result = FeeConditionSettings.calculateConditionFees(
        fields: _activeConditionConfig!.fields,
        rawFieldValues: rawMap,
        fieldTargets: _discountTargetFees,
        fieldDiscountModes: _discountModes,
        fallbackMonthlyFee: double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0,
        fallbackAdmissionFee: double.tryParse(_admissionFeeController.text.trim()) ?? 0.0,
        fallbackBookFee: double.tryParse(_bookFeeController.text.trim()) ?? 0.0,
        fallbackContributorAmount: (_activeConditionConfig!.fields.any((f) => f.fieldType == 'number' && f.isDeduction))
            ? (double.tryParse(_contributorAmountController.text.trim()) ?? 0.0)
            : 0.0,
        sessionMonths: _sessionMonths,
        frequencies: _availableFrequencies,
      );
      _latestFeeCalculation = result;

      final hasExplicitContribAmountField = _activeConditionConfig!.fields.any((f) => f.id == 'contributor_amount');
      if (!hasExplicitContribAmountField) {
        final hasDeductionsInConfig = _activeConditionConfig!.fields.any((f) => f.fieldType == 'number' && f.isDeduction);
        if (hasDeductionsInConfig) {
          _contributorAmountController.text = result.totalDeductions > 0 ? result.totalDeductions.toStringAsFixed(0) : '';
        } else {
          _contributorAmountController.text = '';
        }
      }

      if (mounted) {
        setState(() {
          _totalFeesController.text = result.netTotal.toStringAsFixed(0);
        });
      }
    } else {
      final monthly = double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
      final contribAmt = double.tryParse(_contributorAmountController.text.trim()) ?? 0.0;
      final netTotal = (monthly - contribAmt).clamp(0.0, double.infinity);

      if (mounted) {
        setState(() {
          _totalFeesController.text = netTotal.toStringAsFixed(0);
        });
      }
    }
  }

  Future<void> _loadFormOptions() async {
    final genders = await StudentFormOptionsSettings.getGenders();
    final admissionTypes = await StudentFormOptionsSettings.getAdmissionTypes();
    final conditionConfigs = await FeeConditionSettings.getConditionConfigs();
    final conditions = conditionConfigs.map((c) => c.conditionName).toList();

    int sessionMonths = 12;
    try {
      final sessionCfg = await DatabaseHelper().getCurrentAcademicSessionConfig();
      sessionMonths = FeeConditionSettings.calculateSessionMonths(sessionCfg);
    } catch (_) {}

    final frequencies = await BillingFrequencySettings.getFrequencies();

    _cachedGenders = genders;
    _cachedAdmissionTypes = admissionTypes;
    _cachedConditions = conditions;

    if (mounted) {
      setState(() {
        _genders = genders;
        _admissionTypes = admissionTypes;
        _conditions = conditions;
        _sessionMonths = sessionMonths;
        _availableFrequencies = frequencies;

        if (widget.student == null && (_monthlyFeesMonthsController.text.isEmpty || _monthlyFeesMonthsController.text == '12')) {
          _monthlyFeesMonthsController.text = sessionMonths.toString();
        }

        if (_gender != null && !_genders.contains(_gender)) {
          _genders.add(_gender!);
        }
        if (!_admissionTypes.contains(_admissionType)) {
          _admissionTypes.add(_admissionType);
        }
        if (!_conditions.contains(_conditionType)) {
          _conditions.add(_conditionType);
        }
      });
      _loadActiveConditionConfig();
    }
  }

  FeeType? _findMatchingFeeType(FeeConditionFieldConfig f) {
    if (f.isDeduction || f.mathAction == 'discount' || f.mathAction == 'subtract') return null;
    if (_availableFeeTypes.isEmpty) return null;
    final cleanLabel = f.label.replaceAll(RegExp(r'\(.*?\)'), '').trim().toLowerCase();

    // 1. Check if field ID directly contains the fee type id
    for (final t in _availableFeeTypes) {
      if (t.id.isNotEmpty && (f.id == t.id || f.id.contains('fee_type_field_${t.id}') || f.id.contains(t.id))) {
        return t;
      }
    }

    // 2. Check exact name/label match (case-insensitive)
    for (final t in _availableFeeTypes) {
      if (t.name.trim().toLowerCase() == cleanLabel) {
        return t;
      }
    }

    // 3. Check partial label/name match
    for (final t in _availableFeeTypes) {
      final tName = t.name.trim().toLowerCase();
      if (tName.isNotEmpty && (cleanLabel.contains(tName) || tName.contains(cleanLabel))) {
        return t;
      }
    }

    // 4. If field is monthly_fees or label contains monthly/tuition, match monthly fee type
    if (f.id == 'monthly_fees' || cleanLabel.contains('monthly') || cleanLabel.contains('tuition')) {
      final monthlyType = _availableFeeTypes.where((t) =>
        t.billingType == 'monthly' ||
        t.name.toLowerCase().contains('monthly') ||
        t.name.toLowerCase().contains('tuition')
      ).firstOrNull;
      if (monthlyType != null) return monthlyType;
    }

    // 5. If field is admission_fee, match admission fee type
    if (f.id == 'admission_fee' || cleanLabel.contains('admission') || cleanLabel.contains('dakhila')) {
      final admType = _availableFeeTypes.where((t) =>
        t.name.toLowerCase().contains('admission') ||
        t.name.toLowerCase().contains('dakhila')
      ).firstOrNull;
      if (admType != null) return admType;
    }

    // 6. If field is book_fee, match book fee type
    if (f.id == 'book_fee' || cleanLabel.contains('book') || cleanLabel.contains('kitab')) {
      final bookType = _availableFeeTypes.where((t) =>
        t.name.toLowerCase().contains('book') ||
        t.name.toLowerCase().contains('kitab')
      ).firstOrNull;
      if (bookType != null) return bookType;
    }

    return null;
  }

  void _fillDefaultAmounts() {
    if (_activeConditionConfig != null) {
      for (final f in _activeConditionConfig!.fields) {
        if (f.fieldType == 'number' && !f.isDeduction && f.mathAction != 'discount' && f.mathAction != 'subtract') {
          final ctrl = _getDynamicController(f.id);
          final text = ctrl.text.trim();
          if (text.isEmpty || text == '0') {
            final match = _findMatchingFeeType(f);
            if (match != null && match.defaultAmount > 0) {
              ctrl.text = match.defaultAmount.toStringAsFixed(0);
              if (f.id == 'monthly_fees' && (_monthlyFeesMonthsController.text.trim().isEmpty || _monthlyFeesMonthsController.text.trim() == '0')) {
                _monthlyFeesMonthsController.text = match.defaultMonths.toString();
              }
            }
          }
        }
      }
    }

    // Fallback: If monthly fees controller is still empty or '0', check default monthly fee type
    if (_monthlyFeesController.text.trim().isEmpty || _monthlyFeesController.text.trim() == '0') {
      final monthlyMatch = _availableFeeTypes.where((t) =>
        t.billingType == 'monthly' ||
        t.name.toLowerCase().contains('monthly') ||
        t.name.toLowerCase().contains('tuition')
      ).firstOrNull;
      if (monthlyMatch != null && monthlyMatch.defaultAmount > 0) {
        _monthlyFeesController.text = monthlyMatch.defaultAmount.toStringAsFixed(0);
        if (_monthlyFeesMonthsController.text.trim().isEmpty || _monthlyFeesMonthsController.text.trim() == '0') {
          _monthlyFeesMonthsController.text = monthlyMatch.defaultMonths.toString();
        }
      }
    }
  }

  Future<void> _loadActiveConditionConfig({bool isConditionChangedByUser = false}) async {
    final config = await FeeConditionSettings.getConfigFor(_conditionType);
    if (mounted) {
      setState(() {
        _activeConditionConfig = config;

        final hasDeductions = config.fields.any((f) => f.fieldType == 'number' && f.isDeduction);

        if (!hasDeductions) {
          _contributorAmountController.clear();
          _discountTargetFees.clear();
          _discountModes.clear();
          for (final entry in _dynamicFeeControllers.entries) {
            final fieldInNewConfig = config.fields.where((f) => f.id == entry.key).firstOrNull;
            if (fieldInNewConfig == null || fieldInNewConfig.isDeduction) {
              entry.value.clear();
            }
          }
        } else {
          // Initialize discount target fee and mode defaults for condition deduction fields
          for (final f in config.fields) {
            if (f.fieldType == 'number' && f.isDeduction) {
              if (isConditionChangedByUser || !_discountTargetFees.containsKey(f.id)) {
                _discountTargetFees[f.id] = f.targetFeeField.isNotEmpty ? f.targetFeeField : 'all';
              }
              if (isConditionChangedByUser || !_discountModes.containsKey(f.id)) {
                _discountModes[f.id] = f.discountMode == 'percentage' ? 'percentage' : 'flat';
              }
            }
          }
        }

        // If editing an existing student, pre-fill staff/contributor selections (on initial load)
        if (widget.student != null && !isConditionChangedByUser) {
          final s = widget.student!;
          for (final f in config.fields) {
            if (f.isContributor) {
              if (s.contributorId != null) {
                _selectedContributorId = s.contributorId;
                _selectedContributorIds[f.id] = s.contributorId;
              }
            } else if (f.isStaff) {
              if (s.staffId != null && s.staffId!.isNotEmpty) {
                _selectedStaffIds[f.id] = s.staffId;
              } else if (s.contributorId != null) {
                _selectedStaffIds[f.id] = s.contributorId;
              }
            } else if (f.fieldType == 'number' &&
                (f.fieldSource == 'contributor' ||
                 f.fieldSource == 'staff' ||
                 f.id == 'contributor_amount' ||
                 f.id.startsWith('contributor_amount') ||
                 f.id == 'staff_discount' ||
                 f.id.startsWith('staff_amount') ||
                 f.label.toLowerCase().contains('contributor') ||
                 f.label.toLowerCase().contains('staff'))) {
              final ctrl = _getDynamicController(f.id);
              if (ctrl.text.isEmpty && s.contributorAmount != null && s.contributorAmount! > 0) {
                ctrl.text = s.contributorAmount!.toStringAsFixed(0);
              }
            } else if (f.fieldType == 'number' && f.isDeduction) {
              final ctrl = _getDynamicController(f.id);
              if (ctrl.text.isEmpty) {
                String? savedDiscountInput;
                String? savedDiscountMode;
                String? savedDiscountTarget;
                if (s.feeStructure != null && s.feeStructure!.trim().isNotEmpty && s.feeStructure != 'null') {
                  try {
                    final decoded = jsonDecode(s.feeStructure!);
                    if (decoded is List) {
                      for (final item in decoded) {
                        if (item is Map && item['discount_input'] != null && item['discount_input'].toString().isNotEmpty) {
                          savedDiscountInput = item['discount_input'].toString();
                          savedDiscountMode = item['discount_mode']?.toString();
                          savedDiscountTarget = item['discount_target']?.toString();
                          break;
                        }
                      }
                    }
                  } catch (_) {}
                }

                if (savedDiscountInput != null && savedDiscountInput.isNotEmpty) {
                  ctrl.text = savedDiscountInput;
                  if (savedDiscountMode != null && savedDiscountMode.isNotEmpty) {
                    _discountModes[f.id] = savedDiscountMode;
                  }
                  if (savedDiscountTarget != null && savedDiscountTarget.isNotEmpty) {
                    _discountTargetFees[f.id] = savedDiscountTarget;
                  }
                } else if (s.contributorAmount != null && s.contributorAmount! > 0) {
                  ctrl.text = s.contributorAmount!.toStringAsFixed(0);
                }
              }

              if (ctrl.text.contains('%')) {
                _discountModes[f.id] = 'percentage';
                ctrl.text = ctrl.text.replaceAll('%', '').trim();
              }
            } else if (f.fieldType == 'number' && f.mathAction == 'add') {
              final ctrl = _getDynamicController(f.id);
              if (ctrl.text.isEmpty && s.feeStructure != null) {
                try {
                  final decoded = jsonDecode(s.feeStructure!);
                  if (decoded is List) {
                    for (final item in decoded) {
                      if (item is Map) {
                        final hId = item['fee_type_id']?.toString().toLowerCase().trim();
                        final hTitle = item['fee_type_name']?.toString().toLowerCase().trim();
                        final fId = f.id.toLowerCase().trim();
                        final fLabel = f.label.toLowerCase().trim();
                        if (hId == fId || hTitle == fLabel || (hTitle != null && fLabel.contains(hTitle))) {
                          final orig = (item['original_amount'] as num?)?.toDouble() ?? (item['amount'] as num?)?.toDouble() ?? 0.0;
                          if (orig > 0) {
                            ctrl.text = orig.toStringAsFixed(0);
                            break;
                          }
                        }
                      }
                    }
                  }
                } catch (_) {}
              }
            }
          }
        }

        // Fill default amounts for both Add and Edit student if fields are empty/zero
        _fillDefaultAmounts();
      });
      _recalculateDynamicFees();
    }
  }

  Widget _buildDynamicConditionFields(bool isDark) {
    if (_activeConditionConfig == null || _activeConditionConfig!.fields.isEmpty) {
      return const SizedBox.shrink();
    }

    final fields = _activeConditionConfig!.fields;
    if (fields.isEmpty) return const SizedBox.shrink();

    final widgets = <Widget>[];

    for (final f in fields) {
      if (f.isContributor) {
        widgets.add(
          _buildContributorDropdownField(
            key: ValueKey('contrib_${f.id}_${_selectedContributorIds[f.id] ?? _selectedContributorId}'),
            label: '${f.label} *',
            value: _selectedContributorIds[f.id] ?? _selectedContributorId,
            items: _contributorsList,
            icon: Icons.volunteer_activism_rounded,
            isDark: isDark,
            flex: 1,
            onChanged: (v) {
              setState(() {
                _selectedContributorIds[f.id] = v;
                _selectedContributorId = v;
              });
            },
            validator: (v) => v == null ? 'Required' : null,
          ),
        );
      } else if (f.isStaff) {
        widgets.add(
          _buildStaffDropdownField(
            key: ValueKey('staff_${f.id}_${_selectedStaffIds[f.id]}'),
            label: '${f.label} *',
            value: _selectedStaffIds[f.id],
            items: _staffList,
            icon: Icons.badge_rounded,
            isDark: isDark,
            flex: 1,
            onChanged: (v) => setState(() => _selectedStaffIds[f.id] = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
        );
      } else {
        final ctrl = _getDynamicController(f.id);
        final isNumber = f.fieldType == 'number';
        final math = f.mathAction;
        final isDisc = f.isDeduction;

        Color? badgeBg;
        Color? badgeText;
        String? mathLabel;

        if (math == 'add') {
          badgeBg = const Color(0xFF22C55E).withAlpha(30);
          badgeText = const Color(0xFF22C55E);
          mathLabel = '+ Add';
        } else if (math == 'discount') {
          badgeBg = const Color(0xFFE11D48).withAlpha(30);
          badgeText = const Color(0xFFE11D48);
          mathLabel = '🏷️ Disc';
        } else if (math == 'subtract') {
          badgeBg = const Color(0xFFEF4444).withAlpha(30);
          badgeText = const Color(0xFFEF4444);
          mathLabel = '- Deduct';
        } else if (math == 'multiply') {
          badgeBg = const Color(0xFFA855F7).withAlpha(30);
          badgeText = const Color(0xFFA855F7);
          mathLabel = '* Mult';
        } else if (math == 'divide') {
          badgeBg = const Color(0xFFF97316).withAlpha(30);
          badgeText = const Color(0xFFF97316);
          mathLabel = '/ Div';
        }

        final currentMode = _discountModes[f.id] ?? (f.discountMode == 'percentage' ? 'percentage' : 'flat');
        final isPercentMode = currentMode == 'percentage';
        final deductionAmt = _latestFeeCalculation?.fieldDeductions[f.id] ?? 0.0;
        if (ctrl.text.contains('%')) {
          ctrl.text = ctrl.text.replaceAll('%', '').trim();
        }

        Widget? suffixWidget;
        if (isNumber) {
          if (isDisc) {
            // Target base fee amount calculation for percentage conversion
            double targetBaseAmt = 0.0;
            final targetKey = (_discountTargetFees[f.id] ?? f.targetFeeField).toLowerCase().trim();
            if (targetKey == 'all' || targetKey.isEmpty) {
              targetBaseAmt = _latestFeeCalculation?.grossTotal ?? 0.0;
              if (targetBaseAmt <= 0) {
                targetBaseAmt = (double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0) +
                                (double.tryParse(_admissionFeeController.text.trim()) ?? 0.0) +
                                (double.tryParse(_bookFeeController.text.trim()) ?? 0.0);
              }
            } else if (targetKey == 'monthly_fees' || targetKey.contains('month') || targetKey.contains('tuition')) {
              targetBaseAmt = double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
            } else if (targetKey == 'admission_fee' || targetKey.contains('admission') || targetKey.contains('dakhila')) {
              targetBaseAmt = double.tryParse(_admissionFeeController.text.trim()) ?? 0.0;
            } else if (targetKey == 'book_fee' || targetKey.contains('book') || targetKey.contains('kitab')) {
              targetBaseAmt = double.tryParse(_bookFeeController.text.trim()) ?? 0.0;
            } else {
              final targetField = fields.where((cf) => cf.id.toLowerCase().trim() == targetKey || cf.label.toLowerCase().trim() == targetKey).firstOrNull;
              if (targetField != null) {
                targetBaseAmt = double.tryParse(_getDynamicController(targetField.id).text.trim()) ?? 0.0;
              } else {
                targetBaseAmt = double.tryParse(_getDynamicController(targetKey).text.trim()) ?? 0.0;
              }
            }

            final rawVal = double.tryParse(ctrl.text.trim()) ?? 0.0;
            String? equivBadge;
            if (rawVal > 0) {
              if (isPercentMode) {
                if (deductionAmt > 0) {
                  equivBadge = '-₹${deductionAmt.toStringAsFixed(deductionAmt.truncateToDouble() == deductionAmt ? 0 : 1)}';
                }
              } else {
                if (targetBaseAmt > 0) {
                  final pct = (rawVal / targetBaseAmt) * 100.0;
                  final pctStr = pct.truncateToDouble() == pct
                      ? '${pct.toInt()}%'
                      : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
                  equivBadge = pctStr;
                }
              }
            }

            suffixWidget = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (equivBadge != null && equivBadge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE11D48).withAlpha(40), width: 0.8),
                    ),
                    child: Text(
                      equivBadge,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE11D48),
                      ),
                    ),
                  ),
                // % and ₹ quick toggle chips
                InkWell(
                  onTap: () {
                    setState(() {
                      _discountModes[f.id] = 'percentage';
                      if (ctrl.text.contains('%')) {
                        ctrl.text = ctrl.text.replaceAll('%', '').trim();
                      }
                    });
                    _recalculateDynamicFees();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPercentMode
                          ? const Color(0xFFE11D48)
                          : (isDark ? Colors.white12 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isPercentMode
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                InkWell(
                  onTap: () {
                    setState(() {
                      _discountModes[f.id] = 'flat';
                      if (ctrl.text.contains('%')) {
                        ctrl.text = ctrl.text.replaceAll('%', '').trim();
                      }
                    });
                    _recalculateDynamicFees();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: !isPercentMode
                          ? const Color(0xFF0D6B4E)
                          : (isDark ? Colors.white12 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '₹',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: !isPercentMode
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else if (mathLabel != null) {
            suffixWidget = Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                mathLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: badgeText,
                ),
              ),
            );
          }
        }

        widgets.add(
          _buildField(
            label: f.label,
            controller: ctrl,
            icon: isNumber
                ? (isDisc ? Icons.discount_outlined : Icons.currency_rupee_rounded)
                : Icons.edit_note_rounded,
            isDark: isDark,
            flex: 1,
            keyboardType: isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            inputFormatters: isNumber
                ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
                : null,
            onChanged: isNumber ? (_) => _recalculateDynamicFees() : null,
            suffix: suffixWidget,
          ),
        );

        if (isDisc) {
          widgets.add(
            _buildDiscountTargetDropdownField(
              field: f,
              isDark: isDark,
            ),
          );
        }
      }
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < widgets.length; i += 2) {
      final chunk = widgets.sublist(i, (i + 2 > widgets.length) ? widgets.length : i + 2);
      if (chunk.length == 1) {
        rows.add(_buildRow(children: [chunk[0], const Spacer()]));
      } else {
        rows.add(_buildRow(children: [chunk[0], const SizedBox(width: 16), chunk[1]]));
      }
      rows.add(const SizedBox(height: 14));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: Color(0xFFD4AF37)),
              const SizedBox(width: 6),
              Text(
                'Condition Fields ($_conditionType)',
                style: AppTheme.getFontStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF1B382B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildDiscountTargetDropdownField({
    required FeeConditionFieldConfig field,
    required bool isDark,
  }) {
    final cleanLabel = field.label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    final currentTarget = _discountTargetFees[field.id] ?? 'all';

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'all',
        child: Text('🌐 All Fees (Total)'),
      ),
      const DropdownMenuItem(
        value: 'monthly_fees',
        child: Text('🎯 Monthly Tuition Fee'),
      ),
    ];

    final condFields = _activeConditionConfig?.fields ?? [];
    final hasAdmission = _admissionFeeController.text.trim().isNotEmpty ||
        condFields.any((cf) =>
            cf.id == 'admission_fee' ||
            cf.label.toLowerCase().contains('admission') ||
            cf.label.toLowerCase().contains('dakhila'));
    if (hasAdmission) {
      items.add(const DropdownMenuItem(
        value: 'admission_fee',
        child: Text('🎯 Admission Fee'),
      ));
    }

    final hasBook = _bookFeeController.text.trim().isNotEmpty ||
        condFields.any((cf) =>
            cf.id == 'book_fee' ||
            cf.label.toLowerCase().contains('book') ||
            cf.label.toLowerCase().contains('kitab'));
    if (hasBook) {
      items.add(const DropdownMenuItem(
        value: 'book_fee',
        child: Text('🎯 Book Fee'),
      ));
    }

    // Dynamic positive fee fields from active condition
    for (final other in condFields) {
      final oId = other.id;
      final oLabel = other.label.toLowerCase();
      if (oId != field.id &&
          other.fieldType == 'number' &&
          !other.isDeduction &&
          oId != 'monthly_fees' &&
          oId != 'admission_fee' &&
          oId != 'book_fee' &&
          !oLabel.contains('monthly') &&
          !oLabel.contains('admission') &&
          !oLabel.contains('book')) {
        final otherClean = other.label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
        items.add(DropdownMenuItem(
          value: other.id,
          child: Text('🎯 $otherClean'),
        ));
      }
    }

    // Fallback if currentTarget isn't in items
    if (!items.any((it) => it.value == currentTarget) &&
        currentTarget.isNotEmpty &&
        currentTarget != 'all') {
      items.add(DropdownMenuItem(
        value: currentTarget,
        child: Text('🎯 ${_getTargetFeeName(currentTarget)}'),
      ));
    }

    final safeValue = items.any((it) => it.value == currentTarget) ? currentTarget : 'all';

    return _buildDropdownFieldWithItems<String>(
      label: 'Apply $cleanLabel To',
      value: safeValue,
      items: items,
      icon: Icons.track_changes_rounded,
      isDark: isDark,
      flex: 1,
      onChanged: (newVal) {
        setState(() {
          _discountTargetFees[field.id] = newVal ?? 'all';
        });
        _recalculateDynamicFees();
      },
    );
  }

  static void _distributeAllTargetDiscount({
    required List<_StudentFormFeeHead> activeHeads,
    required double totalGross,
    required double numVal,
    required bool isPercent,
  }) {
    if (activeHeads.isEmpty || totalGross <= 0 || numVal <= 0) return;

    if (isPercent) {
      final double totalDiscount = (totalGross * numVal) / 100.0;
      final bool isIntDiscount = (totalDiscount - totalDiscount.roundToDouble()).abs() < 0.001;

      // Exact shares
      final List<double> exactShares = activeHeads.map((h) => (h.baseAmount * numVal) / 100.0).toList();
      final bool allExactInts = exactShares.every((s) => (s - s.roundToDouble()).abs() < 0.001);

      final pctStr = numVal.truncateToDouble() == numVal
          ? '${numVal.toInt()}%'
          : (numVal < 1 ? '${numVal.toStringAsFixed(2)}%' : '${numVal.toStringAsFixed(1)}%');

      if (allExactInts) {
        for (int i = 0; i < activeHeads.length; i++) {
          final d = exactShares[i];
          activeHeads[i].discount += d;
          activeHeads[i].discountTag = '-₹${d.toStringAsFixed(0)} ($pctStr)';
        }
        return;
      }

      if (isIntDiscount) {
        final shares = _allocateIntegerDiscount(
          heads: activeHeads,
          totalGross: totalGross,
          targetTotal: totalDiscount.round(),
        );
        for (int i = 0; i < activeHeads.length; i++) {
          final d = shares[activeHeads[i].id] ?? 0.0;
          activeHeads[i].discount += d;
          activeHeads[i].discountTag = '-₹${d.toStringAsFixed(0)} ($pctStr)';
        }
      } else {
        for (int i = 0; i < activeHeads.length; i++) {
          final d = exactShares[i];
          activeHeads[i].discount += d;
          activeHeads[i].discountTag = '-₹${d.toStringAsFixed(1)} ($pctStr)';
        }
      }
    } else {
      // Flat Rupee Discount
      final double flatDiscount = numVal.clamp(0.0, totalGross);
      final bool isIntDiscount = (flatDiscount - flatDiscount.roundToDouble()).abs() < 0.001;

      if (isIntDiscount) {
        final shares = _allocateIntegerDiscount(
          heads: activeHeads,
          totalGross: totalGross,
          targetTotal: flatDiscount.round(),
        );
        for (int i = 0; i < activeHeads.length; i++) {
          final d = shares[activeHeads[i].id] ?? 0.0;
          activeHeads[i].discount += d;
          final pct = activeHeads[i].baseAmount > 0 ? (d / activeHeads[i].baseAmount) * 100.0 : 0.0;
          final pctStr = pct.truncateToDouble() == pct
              ? '${pct.toInt()}%'
              : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
          activeHeads[i].discountTag = pct > 0
              ? '-₹${d.toStringAsFixed(0)} ($pctStr)'
              : '-₹${d.toStringAsFixed(0)}';
        }
      } else {
        for (final h in activeHeads) {
          final d = (h.baseAmount / totalGross) * flatDiscount;
          h.discount += d;
          final pct = h.baseAmount > 0 ? (d / h.baseAmount) * 100.0 : 0.0;
          final pctStr = pct.truncateToDouble() == pct
              ? '${pct.toInt()}%'
              : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
          h.discountTag = pct > 0
              ? '-₹${d.toStringAsFixed(1)} ($pctStr)'
              : '-₹${d.toStringAsFixed(1)}';
        }
      }
    }
  }

  static Map<String, double> _allocateIntegerDiscount({
    required List<_StudentFormFeeHead> heads,
    required double totalGross,
    required int targetTotal,
  }) {
    final Map<String, double> result = {};
    if (heads.isEmpty || totalGross <= 0 || targetTotal <= 0) {
      for (final h in heads) {
        result[h.id] = 0.0;
      }
      return result;
    }

    // Group heads by baseAmount so identical fees receive identical discounts
    final Map<double, List<_StudentFormFeeHead>> groups = {};
    for (final h in heads) {
      groups.putIfAbsent(h.baseAmount, () => []).add(h);
    }

    // Compute exact continuous proportion for each head
    final Map<String, double> exactShares = {};
    for (final h in heads) {
      exactShares[h.id] = (h.baseAmount / totalGross) * targetTotal;
    }

    // Initial integer assignment: round()
    final Map<String, int> intShares = {};
    for (final entry in groups.entries) {
      final baseAmt = entry.key;
      final groupList = entry.value;
      // All heads with identical baseAmount start with identical rounded share
      final rounded = ((baseAmt / totalGross) * targetTotal).round();
      for (final h in groupList) {
        intShares[h.id] = rounded;
      }
    }

    // Ensure all active heads with positive base amount receive at least 1 if targetTotal >= eligibleHeads.length
    final eligibleHeads = heads.where((h) => h.baseAmount > 0).toList();
    if (targetTotal >= eligibleHeads.length) {
      for (final h in eligibleHeads) {
        if ((intShares[h.id] ?? 0) <= 0) {
          intShares[h.id] = 1;
        }
      }
    }

    // Never exceed the head's baseAmount
    for (final h in heads) {
      final maxDisc = h.baseAmount.toInt();
      if ((intShares[h.id] ?? 0) > maxDisc) {
        intShares[h.id] = maxDisc;
      }
    }

    int currentSum = intShares.values.fold(0, (a, b) => a + b);
    int diff = currentSum - targetTotal;

    // Order heads by baseAmount descending (e.g. Monthly Fees 3500, Amount 100)
    final sortedHeads = List<_StudentFormFeeHead>.from(heads)
      ..sort((a, b) => b.baseAmount.compareTo(a.baseAmount));

    final int minAllowed = (targetTotal >= eligibleHeads.length) ? 1 : 0;

    if (diff > 0) {
      while (diff > 0) {
        _StudentFormFeeHead? candidate;
        double minError = double.infinity;

        // Prefer single unique head (groups[base].length == 1) whose discount > minAllowed
        for (final h in sortedHeads) {
          final cur = intShares[h.id] ?? 0;
          if (cur <= minAllowed) continue;
          final gSize = groups[h.baseAmount]?.length ?? 1;
          if (gSize == 1) {
            final exact = exactShares[h.id] ?? 0.0;
            final error = (exact - (cur - 1)).abs();
            if (error < minError) {
              minError = error;
              candidate = h;
            }
          }
        }

        // Fallback: pick any head with intShares > minAllowed (largest base first)
        if (candidate == null) {
          for (final h in sortedHeads) {
            final cur = intShares[h.id] ?? 0;
            if (cur > minAllowed) {
              candidate = h;
              break;
            }
          }
        }

        // Ultimate fallback if all are at minAllowed but diff still > 0
        if (candidate == null) {
          for (final h in sortedHeads) {
            if ((intShares[h.id] ?? 0) > 0) {
              candidate = h;
              break;
            }
          }
        }

        if (candidate != null) {
          intShares[candidate.id] = intShares[candidate.id]! - 1;
          diff--;
        } else {
          break;
        }
      }
    } else if (diff < 0) {
      while (diff < 0) {
        _StudentFormFeeHead? candidate;
        double minError = double.infinity;

        // Prefer single unique head (groups[base].length == 1)
        for (final h in sortedHeads) {
          final cur = intShares[h.id] ?? 0;
          if (cur >= h.baseAmount.toInt()) continue;
          final gSize = groups[h.baseAmount]?.length ?? 1;
          if (gSize == 1) {
            final exact = exactShares[h.id] ?? 0.0;
            final error = ((cur + 1) - exact).abs();
            if (error < minError) {
              minError = error;
              candidate = h;
            }
          }
        }

        // Fallback: pick any head below its base amount (largest base first)
        if (candidate == null) {
          for (final h in sortedHeads) {
            final cur = intShares[h.id] ?? 0;
            if (cur < h.baseAmount.toInt()) {
              candidate = h;
              break;
            }
          }
        }

        if (candidate != null) {
          intShares[candidate.id] = intShares[candidate.id]! + 1;
          diff++;
        } else {
          break;
        }
      }
    }

    for (final h in heads) {
      result[h.id] = (intShares[h.id] ?? 0).toDouble();
    }
    return result;
  }

  Widget _buildPreviousConditionBadge(bool isDark) {
    final orig = _originalConditionType?.trim() ?? '';
    if (orig.isEmpty) return const SizedBox.shrink();

    final current = _conditionType.trim();
    final bool isChanged = orig.toLowerCase() != current.toLowerCase();

    if (isChanged) {
      return Tooltip(
        message: 'Purani Condition: "$orig" ➔ Nayi Condition: "$current"',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF451A03).withAlpha(180) : const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFF59E0B).withAlpha(180),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swap_horiz_rounded,
                size: 15,
                color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
              ),
              const SizedBox(width: 5),
              Text(
                'Old: $orig',
                style: AppTheme.getFontStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 11,
                  color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                ),
              ),
              Text(
                'New: $current',
                style: AppTheme.getFontStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF78350F),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Student ki pehle se save shuda Fee Condition: "$orig"',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 14,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              'Old Condition: ',
              style: AppTheme.getFontStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            Text(
              orig,
              style: AppTheme.getFontStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveCalculationBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D6B4E).withAlpha(isDark ? 55 : 38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF0D6B4E).withAlpha(isDark ? 140 : 100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live Calculation',
            style: AppTheme.getFontStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF0D6B4E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetFeeSummaryBanner(bool isDark) {
    // 1. Gather all active fee heads
    final List<_StudentFormFeeHead> feeHeads = [];

    if (_activeConditionConfig != null) {
      for (final f in _activeConditionConfig!.fields) {
        if (f.fieldType == 'number' && !f.isDeduction) {
          final ctrl = _getDynamicController(f.id);
          double val = double.tryParse(ctrl.text.trim()) ?? 0.0;
          final fLower = '${f.id} ${f.label}'.toLowerCase();
          if (val <= 0) {
            if (fLower.contains('monthly') || fLower.contains('tuition')) {
              val = double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
            } else if (fLower.contains('admission') || fLower.contains('dakhila')) {
              val = double.tryParse(_admissionFeeController.text.trim()) ?? 0.0;
            } else if (fLower.contains('book') || fLower.contains('kitab')) {
              val = double.tryParse(_bookFeeController.text.trim()) ?? 0.0;
            }
          }

          IconData icon = Icons.receipt_rounded;
          if (fLower.contains('monthly') || fLower.contains('tuition')) {
            icon = Icons.calendar_month_rounded;
          } else if (fLower.contains('admission') || fLower.contains('dakhila')) {
            icon = Icons.school_rounded;
          } else if (fLower.contains('book') || fLower.contains('kitab')) {
            icon = Icons.menu_book_rounded;
          } else if (fLower.contains('exam') || fLower.contains('imtihan')) {
            icon = Icons.assignment_rounded;
          }

          final m = _StudentFormFeeHead.resolveMonths(f, _sessionMonths, _availableFrequencies);
          final mList = _StudentFormFeeHead.resolveMonthsList(f, _availableFrequencies);
          final cleanTitle = f.label.replaceAll(RegExp(r'\(.*?\)'), '').trim();
          feeHeads.add(_StudentFormFeeHead(
            id: f.id,
            title: cleanTitle,
            baseAmount: val * m,
            unitAmount: val,
            monthsCount: m,
            billingType: f.billingType,
            monthsList: mList,
            icon: icon,
          ));
        }
      }
    }

    final hasMonthly = feeHeads.any((h) =>
        h.id == 'monthly_fees' ||
        h.id.contains('month') ||
        h.title.toLowerCase().contains('month') ||
        h.title.toLowerCase().contains('tuition'));
    final monthlyTuition = double.tryParse(_monthlyFeesController.text.trim()) ?? 0.0;
    if (!hasMonthly && monthlyTuition > 0) {
      final m = _sessionMonths > 0 ? _sessionMonths : 12;
      feeHeads.insert(
        0,
        _StudentFormFeeHead(
          id: 'monthly_fees',
          title: 'Monthly Tuition Fee',
          baseAmount: monthlyTuition * m,
          unitAmount: monthlyTuition,
          monthsCount: m,
          billingType: 'monthly',
          monthsList: BillingFrequencyOption.allMonths,
          icon: Icons.calendar_month_rounded,
        ),
      );
    }

    final hasAdmission = feeHeads.any((h) =>
        h.id == 'admission_fee' ||
        h.id.contains('admission') ||
        h.title.toLowerCase().contains('admission') ||
        h.title.toLowerCase().contains('dakhila'));
    final admissionFee = double.tryParse(_admissionFeeController.text.trim()) ?? 0.0;
    if (!hasAdmission && admissionFee > 0) {
      feeHeads.add(
        _StudentFormFeeHead(
          id: 'admission_fee',
          title: 'Admission Fee',
          baseAmount: admissionFee,
          unitAmount: admissionFee,
          monthsCount: 1,
          billingType: 'one_time',
          icon: Icons.school_rounded,
        ),
      );
    }

    final hasBook = feeHeads.any((h) =>
        h.id == 'book_fee' ||
        h.id.contains('book') ||
        h.title.toLowerCase().contains('book') ||
        h.title.toLowerCase().contains('kitab'));
    final bookFee = double.tryParse(_bookFeeController.text.trim()) ?? 0.0;
    if (!hasBook && bookFee > 0) {
      feeHeads.add(
        _StudentFormFeeHead(
          id: 'book_fee',
          title: 'Book Fee',
          baseAmount: bookFee,
          unitAmount: bookFee,
          monthsCount: 1,
          billingType: 'one_time',
          icon: Icons.menu_book_rounded,
        ),
      );
    }

    final double grossTotal = feeHeads.fold<double>(0.0, (sum, h) => sum + h.baseAmount);

    // 2. Apply deductions from condition fields
    if (_activeConditionConfig != null) {
      for (final f in _activeConditionConfig!.fields) {
        if (f.fieldType == 'number' && f.isDeduction) {
          final raw = _getDynamicController(f.id).text.trim();
          if (raw.isEmpty) continue;

          final clean = raw.replaceAll('%', '').trim();
          final numVal = double.tryParse(clean) ?? 0.0;
          if (numVal <= 0.0) continue;

          final mode = _discountModes[f.id] ?? (f.discountMode == 'percentage' ? 'percentage' : 'flat');
          final isPercent = (mode == 'percentage') || raw.contains('%');
          final target = (_discountTargetFees[f.id] ?? f.targetFeeField).toLowerCase().trim();
          final dedMonths = _StudentFormFeeHead.resolveMonths(f, _sessionMonths, _availableFrequencies);

          if (target == 'all' || target.isEmpty) {
            final double effDiscount = isPercent
                ? numVal
                : (f.billingType == 'monthly' ? numVal * dedMonths : numVal);
            _distributeAllTargetDiscount(
              activeHeads: feeHeads.where((h) => h.baseAmount > 0).toList(),
              totalGross: grossTotal,
              numVal: effDiscount,
              isPercent: isPercent,
            );
          } else {
            _StudentFormFeeHead? targetHead;
            for (final head in feeHeads) {
              final hId = head.id.toLowerCase().trim();
              final hTitle = head.title.toLowerCase().trim();
              if (hId == target || hTitle == target) {
                targetHead = head;
                break;
              }
              if (target == 'monthly_fees' && (hId.contains('month') || hTitle.contains('month') || hTitle.contains('tuition'))) {
                targetHead = head;
                break;
              }
              if (target == 'admission_fee' && (hId.contains('admission') || hTitle.contains('admission') || hTitle.contains('dakhila'))) {
                targetHead = head;
                break;
              }
              if (target == 'book_fee' && (hId.contains('book') || hTitle.contains('book') || hTitle.contains('kitab'))) {
                targetHead = head;
                break;
              }
            }

            if (targetHead != null) {
              double headDisc = 0.0;
              String headTag = '';
              if (isPercent) {
                headDisc = (targetHead.baseAmount * numVal) / 100.0;
                final pctStr = numVal.truncateToDouble() == numVal
                    ? '${numVal.toInt()}%'
                    : (numVal < 1 ? '${numVal.toStringAsFixed(2)}%' : '${numVal.toStringAsFixed(1)}%');
                headTag = '-₹${headDisc.toStringAsFixed(0)} ($pctStr)';
              } else {
                final double effVal = f.billingType == 'monthly' ? (numVal * dedMonths) : numVal;
                headDisc = effVal.clamp(0.0, targetHead.baseAmount);
                final pct = targetHead.baseAmount > 0 ? (headDisc / targetHead.baseAmount) * 100.0 : 0.0;
                final pctStr = pct.truncateToDouble() == pct
                    ? '${pct.toInt()}%'
                    : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
                headTag = f.billingType == 'monthly' && dedMonths > 1
                    ? '-₹${headDisc.toStringAsFixed(0)} ($dedMonths mo × ₹${numVal.toStringAsFixed(0)})'
                    : (pct > 0 ? '-₹${headDisc.toStringAsFixed(0)} ($pctStr)' : '-₹${headDisc.toStringAsFixed(0)}');
              }
              targetHead.discount += headDisc;
              targetHead.discountTag = headTag;
            }
          }
        }
      }
    } else {
      final contribAmt = double.tryParse(_contributorAmountController.text.trim()) ?? 0.0;
      if (contribAmt > 0 && feeHeads.isNotEmpty) {
        final m = feeHeads.first.monthsCount > 0 ? feeHeads.first.monthsCount : 1;
        final effDisc = feeHeads.first.billingType == 'monthly' ? (contribAmt * m) : contribAmt;
        feeHeads.first.discount = effDisc.clamp(0.0, feeHeads.first.baseAmount);
        final pct = feeHeads.first.baseAmount > 0 ? (feeHeads.first.discount / feeHeads.first.baseAmount) * 100.0 : 0.0;
        final pctStr = pct.truncateToDouble() == pct
            ? '${pct.toInt()}%'
            : (pct < 1 ? '${pct.toStringAsFixed(2)}%' : '${pct.toStringAsFixed(1)}%');
        feeHeads.first.discountTag = pct > 0
            ? '-₹${feeHeads.first.discount.toStringAsFixed(0)} ($pctStr)'
            : '-₹${feeHeads.first.discount.toStringAsFixed(0)}';
      }
    }

    final double deductions = feeHeads.fold<double>(0.0, (sum, h) => sum + h.discount);
    final double netExpected = (grossTotal - deductions).clamp(0.0, double.infinity);

    final List<Map<String, dynamic>> breakdownRows = [];
    for (final head in feeHeads) {
      if (head.baseAmount > 0) {
        breakdownRows.add({
          'title': head.title,
          'before': head.baseAmount,
          'discount': head.discount,
          'discountTag': head.discountTag,
          'after': head.netAmount,
          'icon': head.icon,
          'unitAmount': head.unitAmount,
          'monthsCount': head.monthsCount,
          'billingType': head.billingType,
          'netUnitAmount': head.netUnitAmount,
        });
      }
    }

    final hasData = breakdownRows.isNotEmpty || grossTotal > 0 || deductions > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13241B) : const Color(0xFFF2FBF6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF1E5C40) : const Color(0xFF86EFAC),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D6B4E).withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header ──────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isCompact = constraints.maxWidth < 650;
              final bool hasOldCondition = _originalConditionType != null &&
                  _originalConditionType!.trim().isNotEmpty;

              final titleSection = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6B4E).withAlpha(isDark ? 75 : 30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF0D6B4E), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fee Breakdown & Discount Impact',
                          style: AppTheme.getFontStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF0D6B4E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Live Discount & Fee Breakdown Analysis',
                          style: AppTheme.getFontStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white60 : const Color(0xFF386B52),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final badgesSection = Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
                children: [
                  if (hasOldCondition) _buildPreviousConditionBadge(isDark),
                  _buildLiveCalculationBadge(isDark),
                ],
              );

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleSection,
                    const SizedBox(height: 8),
                    badgesSection,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: titleSection),
                  const SizedBox(width: 10),
                  badgesSection,
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Enter tuition, admission, book fees or discount to see live before/after calculation.',
                style: AppTheme.getFontStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
              ),
            )
          else ...[
            // ── Table Header ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B382B) : const Color(0xFFE2F6EC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Fee Head',
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF0D6B4E),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Original Fee',
                      textAlign: TextAlign.right,
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : const Color(0xFF333333),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Discount',
                      textAlign: TextAlign.right,
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE11D48),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Net Fee',
                      textAlign: TextAlign.right,
                      style: AppTheme.getFontStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF059669),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // ── Table Rows ───────────────────────────────────────────
            ...breakdownRows.map((row) {
              final double before = row['before'] as double;
              final double discount = row['discount'] as double;
              final String discountTag = (row['discountTag'] as String?) ?? '';
              final double after = row['after'] as double;
              final bool hasDisc = discount > 0;
              final int mCount = row['monthsCount'] as int? ?? 1;
              final double unit = row['unitAmount'] as double? ?? before;
              final double netUnit = row['netUnitAmount'] as double? ?? after;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Icon(
                            row['icon'] as IconData? ?? Icons.receipt_rounded,
                            size: 16,
                            color: const Color(0xFF0D6B4E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  row['title'] as String,
                                  style: AppTheme.getFontStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF1F2937),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (mCount > 1)
                                  Text(
                                    '$mCount Mo × ₹${unit.toStringAsFixed(0)}',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 10.5,
                                      color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '₹${before.toStringAsFixed(0)}',
                        textAlign: TextAlign.right,
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          color: hasDisc
                              ? (isDark ? Colors.white54 : Colors.grey.shade600)
                              : (isDark ? Colors.white : Colors.black87),
                          decoration: hasDisc ? TextDecoration.lineThrough : TextDecoration.none,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: hasDisc
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                                ),
                                child: Text(
                                  discountTag.isNotEmpty ? discountTag : '-₹${discount.toStringAsFixed(0)}',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              '—',
                              textAlign: TextAlign.right,
                              style: AppTheme.getFontStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white38 : Colors.grey.shade400,
                              ),
                            ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${after.toStringAsFixed(0)}',
                            textAlign: TextAlign.right,
                            style: AppTheme.getFontStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: hasDisc ? const Color(0xFF059669) : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (mCount > 1)
                            Text(
                              '₹${netUnit.toStringAsFixed(0)}/mo',
                              textAlign: TextAlign.right,
                              style: AppTheme.getFontStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF059669),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            Divider(color: isDark ? Colors.white24 : Colors.grey.shade300, height: 16),

            // ── Total Summary Row ────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E3F30) : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF2E6B50) : const Color(0xFF86EFAC),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Total Expected',
                      style: AppTheme.getFontStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '₹${grossTotal.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: AppTheme.getFontStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: deductions > 0
                            ? (isDark ? Colors.white54 : Colors.grey.shade600)
                            : (isDark ? Colors.white : Colors.black87),
                        decoration: deductions > 0 ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: deductions > 0
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                () {
                                  final totalPct = grossTotal > 0 ? (deductions / grossTotal) * 100.0 : 0.0;
                                  final pctStr = totalPct.truncateToDouble() == totalPct
                                      ? '${totalPct.toInt()}%'
                                      : (totalPct < 1 ? '${totalPct.toStringAsFixed(2)}%' : '${totalPct.toStringAsFixed(1)}%');
                                  return totalPct > 0
                                      ? '-₹${deductions.toStringAsFixed(0)} ($pctStr)'
                                      : '-₹${deductions.toStringAsFixed(0)}';
                                }(),
                                style: AppTheme.getFontStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          )
                        : Text(
                            '₹0',
                            textAlign: TextAlign.right,
                            style: AppTheme.getFontStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.grey.shade400,
                            ),
                          ),
                  ),
                  Expanded(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '₹${netExpected.toStringAsFixed(0)}',
                        textAlign: TextAlign.right,
                        style: AppTheme.getFontStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Monthly Net Payable Rate Banner ──────────────────────
            () {
              final monthlyHead = feeHeads.where((h) =>
                  h.billingType == 'monthly' ||
                  h.id == 'monthly_fees' ||
                  h.id.contains('month') ||
                  h.title.toLowerCase().contains('month') ||
                  h.title.toLowerCase().contains('tuition')).firstOrNull;
              if (monthlyHead != null && monthlyHead.monthsCount > 1) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF103426) : const Color(0xFFE6F4EA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? const Color(0xFF1B6B4A) : const Color(0xFF86EFAC),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.event_repeat_rounded, size: 16, color: Color(0xFF059669)),
                            const SizedBox(width: 6),
                            Text(
                              'Monthly Payable Rate:',
                              style: AppTheme.getFontStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹${monthlyHead.netUnitAmount.toStringAsFixed(0)} / month',
                          style: AppTheme.getFontStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }(),
          ],
        ],
      ),
    );
  }



  Future<void> _loadStatuses() async {
    final list = await StudentStatusSettings.getStatuses();
    _cachedStatusOptions = list;
    if (mounted) {
      setState(() {
        _statusOptions = list;
        if (widget.student != null && widget.student!.studentStatus != null && widget.student!.studentStatus!.isNotEmpty) {
          _selectedStatus = widget.student!.studentStatus!;
        }
        if (!_statusOptions.contains(_selectedStatus)) {
          _statusOptions.add(_selectedStatus);
        }
      });
    }
  }

  Widget _buildStatusDropdownTile(bool isDark) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final safeValue = _statusOptions.contains(_selectedStatus) ? _selectedStatus : null;

    final field = DropdownButtonFormField<String>(
      initialValue: safeValue,
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _selectedStatus = v;
          });
        }
      },
      validator: (v) => v == null ? 'Required' : null,
      isExpanded: true,
      style: AppTheme.getFontStyle(
        fontSize: 13 * scale,
        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
      ),
      decoration: _inputDecoration(
        'Status *',
        Icons.label_important_rounded,
        isDark,
        suffix: IconButton(
          tooltip: 'Add / Edit Status Categories',
          icon: const Icon(Icons.settings_suggest_rounded, size: 18, color: Color(0xFF6A1B9A)),
          onPressed: () async {
            await _openSubDialog(() => ManageStatusCategoriesDialog.show(context, barrierColor: Colors.transparent));
            _loadStatuses();
          },
        ),
      ),
      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
      items: _statusOptions
          .map((i) => DropdownMenuItem(
                value: i,
                child: Text(
                  i,
                  style: TextStyle(fontSize: 13 * scale),
                ),
              ))
          .toList(),
    );

    if (context.isMobile) return field;
    return Expanded(flex: 1, child: field);
  }

  // ── Section Title ──────────────────────────────────────────────────────────
  Widget _sectionTitle(String title, IconData icon, bool isDark) {
    final titleText = context.tr(title.toLowerCase().replaceAll(' ', '_').replaceAll('&', 'and'));
    if (context.isMobile) {
      return Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF0D6B4E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: const Color(0xFF0D6B4E)),
          const SizedBox(width: 8),
          Text(
            titleText,
            style: AppTheme.getFontStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 17, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(
          titleText,
          style: AppTheme.getFontStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }

  // ── Generic field builder ──────────────────────────────────────────────────
  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    required int flex,
    bool readOnly = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffix,
    ValueChanged<String>? onChanged,
    TextInputAction textInputAction = TextInputAction.next,
    FocusNode? focusNode,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final field = TextFormField(
      controller: controller,
      readOnly: readOnly,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      onChanged: onChanged,
      enableInteractiveSelection: true,
      contextMenuBuilder: (context, editableTextState) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: editableTextState.contextMenuButtonItems,
        );
      },
      style: AppTheme.getFontStyle(fontSize: 13 * scale),
      validator: validator,
      decoration: _inputDecoration(label, icon, isDark, suffix: suffix),
      onFieldSubmitted: (v) {
        // For GR.NO field
        if (label.startsWith('GR') && v.trim().isNotEmpty && widget.student == null) {
          _fetchStudentByGRNo(v.trim());
        }
        FocusScope.of(context).nextFocus();
      },
    );
    if (context.isMobile) return field;
    return Expanded(
      flex: flex,
      child: field,
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required bool isDark,
    required int flex,
    required VoidCallback onTap,
    String? Function(String?)? validator,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final field = TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      style: AppTheme.getFontStyle(fontSize: 13 * scale),
      validator: validator,
      decoration: _inputDecoration(
        label,
        Icons.calendar_today_rounded,
        isDark,
      ),
    );
    if (context.isMobile) return field;
    return Expanded(
      flex: flex,
      child: field,
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required bool isDark,
    required int flex,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
    Widget? suffix,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    // Ensure the current value exists in the items list to avoid crash
    final safeItems = List<String>.from(items);
    if (value != null && value.isNotEmpty && !safeItems.contains(value)) {
      safeItems.add(value);
    }
    final safeValue = (value != null && safeItems.contains(value)) ? value : null;

    final field = DropdownButtonFormField<String>(
        initialValue: safeValue,
        onChanged: onChanged,
        validator: validator,
        isExpanded: true,
        style: AppTheme.getFontStyle(
          fontSize: 13 * scale,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
        decoration: _inputDecoration(label, icon, isDark, suffix: suffix),
        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
        items: safeItems
            .map((i) => DropdownMenuItem(
                  value: i,
                  child: Text(
                    i,
                    style: TextStyle(fontSize: 13 * scale),
                  ),
                ))
            .toList(),
      );
    if (context.isMobile) return field;
    return Expanded(
      flex: flex,
      child: field,
    );
  }

  Widget _buildSubDepartmentsSection(bool isDark) {
    if (_availableSubDepartments.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);

    return Container(
      margin: EdgeInsets.only(top: 14 * scale),
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222235) : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFF1565C0).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 18 * scale, color: const Color(0xFF1565C0)),
              SizedBox(width: 6 * scale),
              Text(
                'Sub-Departments (Multiple Selection):',
                style: AppTheme.getFontStyle(
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1565C0),
                ),
              ),
            ],
          ),
          SizedBox(height: 6 * scale),
          Text(
            'Select sub-departments for this student. You can assign independent classes and divisions to each.',
            style: AppTheme.getFontStyle(
              fontSize: 11 * scale,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          SizedBox(height: 10 * scale),

          // Sub-Department Chips
          Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            children: _availableSubDepartments.map((sub) {
              final subId = sub['id'].toString();
              final isSelected = _selectedSubDeptEntries.any((e) => e.subDepartmentId == subId);
              return FilterChip(
                label: Text(
                  sub['name'] ?? '',
                  style: TextStyle(
                    fontSize: 12 * scale,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.grey.shade300 : const Color(0xFF1A1A2E)),
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF1565C0),
                checkmarkColor: Colors.white,
                backgroundColor: isDark ? const Color(0xFF2E2E42) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8 * scale),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF1565C0)
                        : (isDark ? Colors.white24 : Colors.grey.shade300),
                  ),
                ),
                onSelected: (_) => _toggleSubDepartment(sub),
              );
            }).toList(),
          ),

          // Render details for each selected sub-department
          if (_selectedSubDeptEntries.isNotEmpty) ...[
            SizedBox(height: 14 * scale),
            ..._selectedSubDeptEntries.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final subClasses = _getClassesForSubDept(item.subDepartmentId);
              final subDivs = _getDivisionsForClass(item.className);

              return Container(
                margin: EdgeInsets.only(bottom: 10 * scale),
                padding: EdgeInsets.all(10 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                  borderRadius: BorderRadius.circular(10 * scale),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6 * scale),
                          ),
                          child: Text(
                            item.subDepartmentName,
                            style: AppTheme.getFontStyle(
                              fontSize: 12 * scale,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1565C0),
                            ),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedSubDeptEntries.removeAt(index);
                            });
                          },
                          child: Padding(
                            padding: EdgeInsets.all(4 * scale),
                            child: Icon(Icons.close_rounded,
                                size: 16 * scale, color: Colors.red.shade400),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8 * scale),
                    Row(
                      children: [
                        // Sub-Department Class
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String?>(
                            initialValue: subClasses.contains(item.className) ? item.className : null,
                            dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                            style: AppTheme.getFontStyle(
                              fontSize: 12 * scale,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              labelText: '${item.subDepartmentName} Class',
                              labelStyle: TextStyle(fontSize: 11 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              prefixIcon: Icon(Icons.class_rounded, size: 16 * scale, color: const Color(0xFF1565C0)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                              isDense: true,
                            ),
                            items: subClasses.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))).toList(),
                            onChanged: (val) {
                              setState(() {
                                item.className = val;
                                final newDivs = _getDivisionsForClass(val);
                                item.division = newDivs.isNotEmpty ? newDivs.first : null;
                                item.showCustomDivisionField = false;
                                item.customDivisionController.text = item.division ?? '';
                              });
                            },
                          ),
                        ),
                        SizedBox(width: 10 * scale),
                        // Sub-Department Division
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String?>(
                            initialValue: subDivs.contains(item.division) ? item.division : (item.division != null && item.division!.isNotEmpty ? 'Custom...' : null),
                            dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                            style: AppTheme.getFontStyle(
                              fontSize: 12 * scale,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              labelText: '${item.subDepartmentName} Division',
                              labelStyle: TextStyle(fontSize: 11 * scale, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                              prefixIcon: Icon(Icons.grid_view_rounded, size: 16 * scale, color: const Color(0xFF1565C0)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                              isDense: true,
                            ),
                            items: [
                              ...subDivs.map((d) => DropdownMenuItem<String?>(value: d, child: Text(d))),
                              const DropdownMenuItem<String?>(value: 'Custom...', child: Text('Custom...')),
                            ],
                            onChanged: (val) {
                              setState(() {
                                if (val == 'Custom...') {
                                  item.showCustomDivisionField = true;
                                  item.division = 'Custom...';
                                  item.customDivisionController.clear();
                                } else {
                                  item.showCustomDivisionField = false;
                                  item.division = val;
                                  item.customDivisionController.text = val ?? '';
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (item.showCustomDivisionField) ...[
                      SizedBox(height: 8 * scale),
                      TextField(
                        controller: item.customDivisionController,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        style: AppTheme.getFontStyle(fontSize: 12 * scale),
                        decoration: InputDecoration(
                          hintText: 'Enter custom division (e.g. A-1, B-2)',
                          hintStyle: TextStyle(fontSize: 11 * scale, color: Colors.grey),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8 * scale)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  List<DropdownMenuItem<String?>> _buildMainDeptDropdownItems() {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text('All Departments', style: TextStyle(fontSize: 13 * scale)),
      ),
    ];
    final mainDepts = _allDepartments.where((d) => d['parent_id'] == null).toList();
    for (final dept in mainDepts) {
      items.add(DropdownMenuItem<String?>(
        value: dept['id'].toString(),
        child: Text(dept['name'] ?? '', style: TextStyle(fontSize: 13 * scale)),
      ));
    }
    return items;
  }

  Widget _buildDropdownFieldWithItems<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required IconData icon,
    required bool isDark,
    required int flex,
    required ValueChanged<T?> onChanged,
    String? Function(T?)? validator,
    Widget? suffix,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final exists = items.any((it) => it.value == value);
    final safeValue = exists ? value : null;

    final field = DropdownButtonFormField<T>(
      initialValue: safeValue,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      style: AppTheme.getFontStyle(
        fontSize: 13 * scale,
        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
      ),
      decoration: _inputDecoration(label, icon, isDark, suffix: suffix),
      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
      items: items,
    );
    if (context.isMobile) return field;
    return Expanded(
      flex: flex,
      child: field,
    );
  }

  InputDecoration _inputDecoration(
      String label, IconData icon, bool isDark, {Widget? suffix}) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    return InputDecoration(
      labelText: label,
      labelStyle: AppTheme.getFontStyle(
        fontSize: 12 * scale,
        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
      ),
      prefixIcon: Icon(icon, size: 16 * scale, color: AppTheme.primaryColor),
      suffixIcon: suffix != null
          ? Padding(
              padding: EdgeInsets.only(right: 8 * scale),
              child: suffix,
            )
          : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * scale),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * scale),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * scale),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10 * scale),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding:
          EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
      isDense: true,
    );
  }

  double get _totalFees {
    final monthly = double.tryParse(_monthlyFeesController.text) ?? 0.0;
    final contributor = double.tryParse(_contributorAmountController.text) ?? 0.0;
    return monthly + contributor;
  }

  Future<void> _loadStaffMembers() async {
    if (_staffList.isEmpty) {
      setState(() => _isLoadingStaff = true);
    }
    try {
      final response = await ApiClient().get('/staff');
      final raw = response.data;
      List<dynamic> data;
      if (raw is Map) {
        data = (raw['data'] as List?) ?? [];
      } else if (raw is List) {
        data = raw;
      } else {
        data = [];
      }
      final parsedStaff = data.map((e) => StaffMember.fromJson(e as Map<String, dynamic>)).toList();
      _cachedStaffList = parsedStaff;
      if (mounted) {
        setState(() {
          _staffList = parsedStaff;
          _isLoadingStaff = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load staff list: $e');
      if (mounted) setState(() => _isLoadingStaff = false);
    }
  }

  Widget _buildStaffDropdownField({
    Key? key,
    required String label,
    required String? value,
    required List<StaffMember> items,
    required IconData icon,
    required bool isDark,
    required int flex,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final safeItems = List<StaffMember>.from(items);
    final hasValue = safeItems.any((s) => s.id == value || s.fullName == value);
    final safeValue = hasValue
        ? (safeItems.firstWhere((s) => s.id == value || s.fullName == value).id)
        : null;

    final field = DropdownButtonFormField<String>(
      key: key ?? ValueKey('staff_field_${safeValue}_${safeItems.length}'),
      initialValue: safeValue,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      style: AppTheme.getFontStyle(
        fontSize: 13 * scale,
        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
      ),
      decoration: _inputDecoration(label, icon, isDark).copyWith(
        suffixIcon: _isLoadingStaff
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
      items: safeItems
          .map((s) => DropdownMenuItem(
                value: s.id,
                child: Text(
                  '${s.fullName} (${s.staffNo})',
                  style: TextStyle(fontSize: 13 * scale),
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
    );
    if (context.isMobile) return field;
    return Expanded(
      flex: flex,
      child: field,
    );
  }

  Future<void> _loadContributors() async {
    if (_contributorsList.isEmpty) {
      setState(() => _isLoadingContributors = true);
    }
    try {
      final response = await ApiClient().get('/contributors');
      if (mounted) {
        final raw = response.data;
        List<dynamic> list = [];
        if (raw is List) {
          list = raw;
        } else if (raw is Map && raw['data'] is List) {
          list = raw['data'] as List;
        }
        final apiContributors = list.map((json) => Contributor.fromJson(json as Map<String, dynamic>)).toList();
        _cachedContributors = apiContributors;
        setState(() {
          _contributorsList = apiContributors;
          _isLoadingContributors = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load contributors: $e');
      if (mounted) {
        setState(() => _isLoadingContributors = false);
      }
    }
  }

  Widget _buildContributorDropdownField({
    Key? key,
    required String label,
    required String? value,
    required List<Contributor> items,
    required IconData icon,
    required bool isDark,
    required int flex,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);
    final safeItems = List<Contributor>.from(items);
    final hasValue = safeItems.any((c) => c.id == value || c.name == value);
    final safeValue = hasValue
        ? (safeItems.firstWhere((c) => c.id == value || c.name == value).id)
        : null;

    final field = DropdownButtonFormField<String>(
        key: key ?? ValueKey('contrib_field_${safeValue}_${safeItems.length}'),
        initialValue: safeValue,
        onChanged: onChanged,
        validator: validator,
        isExpanded: true,
        style: AppTheme.getFontStyle(
          fontSize: 13 * scale,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
        decoration: _inputDecoration(label, icon, isDark).copyWith(
          suffixIcon: _isLoadingContributors
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
        items: safeItems
            .map((c) => DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    c.name,
                    style: TextStyle(fontSize: 13 * scale),
                  ),
                ))
            .toList(),
      );
    if (context.isMobile) return field;
    return Expanded(
      flex: flex,
      child: field,
    );
  }

  Widget _buildRow({required List<Widget> children}) {
    if (context.isMobile) {
      final width = MediaQuery.of(context).size.width;
      final scale = (width / 375.0).clamp(0.75, 1.0);
      final cleanChildren = children.where((c) => c is! SizedBox).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(cleanChildren.length, (idx) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: idx < cleanChildren.length - 1 ? (12 * scale) : 0,
            ),
            child: cleanChildren[idx],
          );
        }),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
