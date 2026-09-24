import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../data/models/staff_model.dart';
import '../bloc/staff_bloc.dart';
import '../widgets/staff_form_dialog.dart';
import '../widgets/staff_types_tab.dart';
import 'staff_profile_screen.dart';
import '../widgets/staff_id_card_builder_dialog.dart';
import '../../../../core/services/student_form_options_settings.dart';
import '../../../../core/services/student_status_settings.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import '../../../../core/services/firebase_service.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
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

  String _searchQuery = '';
  String? _selectedStaffId;
  String? _activeTypeFilter;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _viewMode = 'table'; // table | card
  late TabController _tabController;

  // Dynamic staff type filter chips
  List<String> _typeFilters = ['All'];

  // Multi-Filter state
  String? _filterStaffType;
  String? _filterGender;
  String? _filterStatus;
  String? _filterQualification;
  String? _filterVillage;
  String? _filterDistrict;
  String? _filterState;
  String? _filterMinSalary;
  String? _filterMaxSalary;
  String? _filterMinExp;
  String? _filterMaxExp;

  bool get _hasActiveFilters =>
      _filterStaffType != null ||
      _filterGender != null ||
      _filterStatus != null ||
      _filterQualification != null ||
      _filterVillage != null ||
      _filterDistrict != null ||
      _filterState != null ||
      _filterMinSalary != null ||
      _filterMaxSalary != null ||
      _filterMinExp != null ||
      _filterMaxExp != null ||
      _activeTypeFilter != null;

  void _clearAllFilters() {
    setState(() {
      _filterStaffType = null;
      _filterGender = null;
      _filterStatus = null;
      _filterQualification = null;
      _filterVillage = null;
      _filterDistrict = null;
      _filterState = null;
      _filterMinSalary = null;
      _filterMaxSalary = null;
      _filterMinExp = null;
      _filterMaxExp = null;
      _activeTypeFilter = null;
      _searchQuery = '';
      _searchCtrl.clear();
    });
  }

  // Customizable Stat Cards Configuration
  List<StaffStatCardConfig> _statCardConfigs = [];

  Future<void> _loadStatCardConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('staff_stat_cards_config_v2');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final list = decoded
            .map((item) => StaffStatCardConfig.fromJson(item as Map<String, dynamic>))
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
      debugPrint('Error loading staff stat cards config: $e');
    }

    await _initDefaultStatCardConfigs();
  }

  Future<void> _initDefaultStatCardConfigs() async {
    String primaryGender1 = 'Male';

    try {
      final genders = await StudentFormOptionsSettings.getGenders();
      if (genders.isNotEmpty) {
        primaryGender1 = genders[0];
      }
    } catch (_) {}

    final defaultList = [
      StaffStatCardConfig(
        id: 'card_1',
        type: 'total',
        label: 'Total Staff',
        filterValue: null,
        iconCodePoint: Icons.people_alt_rounded.codePoint,
        colorValue: 0xFF0D6B4E,
      ),
      StaffStatCardConfig(
        id: 'card_2',
        type: 'status',
        label: 'Active',
        filterValue: 'Active',
        iconCodePoint: Icons.check_circle_rounded.codePoint,
        colorValue: 0xFF1565C0,
      ),
      StaffStatCardConfig(
        id: 'card_3',
        type: 'staff_type',
        label: 'Teachers',
        filterValue: 'Teacher',
        iconCodePoint: Icons.school_rounded.codePoint,
        colorValue: 0xFF6A1B9A,
      ),
      StaffStatCardConfig(
        id: 'card_4',
        type: 'gender',
        label: primaryGender1,
        filterValue: primaryGender1,
        iconCodePoint: Icons.male_rounded.codePoint,
        colorValue: 0xFFE65100,
      ),
    ];

    if (mounted) {
      setState(() {
        _statCardConfigs = defaultList;
      });
    }
  }

  Future<void> _saveStatCardConfigs(List<StaffStatCardConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
      await prefs.setString('staff_stat_cards_config_v2', jsonStr);
      FirebaseService.syncStaffStatCardsConfig(configs.map((c) => c.toJson()).toList());
      if (mounted) {
        setState(() {
          _statCardConfigs = List.from(configs);
        });
      }
    } catch (e) {
      debugPrint('Error saving staff stat cards config: $e');
    }
  }

  int _calculateStatCount(List<StaffMember> staffList, StaffStatCardConfig config) {
    final target = (config.filterValue ?? config.label).trim().toLowerCase();

    switch (config.type) {
      case 'total':
        return staffList.length;

      case 'status':
        return staffList.where((s) {
          if (target == 'active' || target == 'chalu' || target == 'regular') {
            return s.isActive;
          }
          if (target == 'inactive' || target == 'kharij' || target == 'left') {
            return !s.isActive;
          }
          return s.isActive;
        }).length;

      case 'gender':
        return staffList.where((s) {
          final g = (s.gender ?? '').trim().toLowerCase();
          if (g.isEmpty) return false;
          if (g == target) return true;
          if ((target == 'male' || target == 'ladka' || target == 'boy' || target == 'boys' || target == 'm') &&
              (g == 'male' || g == 'ladka' || g == 'boy' || g == 'boys' || g == 'm')) {
            return true;
          }
          if ((target == 'female' || target == 'ladki' || target == 'girl' || target == 'girls' || target == 'f') &&
              (g == 'female' || g == 'ladki' || g == 'girl' || g == 'girls' || g == 'f')) {
            return true;
          }
          return false;
        }).length;

      case 'staff_type':
        return staffList.where((s) {
          final t = s.staffType.trim().toLowerCase();
          return t == target || t.contains(target);
        }).length;

      case 'qualification':
        return staffList.where((s) {
          final q = (s.qualification ?? '').trim().toLowerCase();
          return q == target || q.contains(target);
        }).length;

      case 'with_mobile':
        return staffList.where((s) => s.mobileNo != null && s.mobileNo!.trim().isNotEmpty).length;

      case 'without_mobile':
        return staffList.where((s) => s.mobileNo == null || s.mobileNo!.trim().isEmpty).length;

      case 'with_aadhaar':
        return staffList.where((s) => s.aadhaarNo != null && s.aadhaarNo!.trim().isNotEmpty).length;

      case 'without_aadhaar':
        return staffList.where((s) => s.aadhaarNo == null || s.aadhaarNo!.trim().isEmpty).length;

      case 'salary_above':
        final minSal = double.tryParse(target) ?? 10000;
        return staffList.where((s) => s.salary >= minSal).length;

      case 'exp_above':
        final minExp = int.tryParse(target) ?? 3;
        return staffList.where((s) => s.experienceYears >= minExp).length;

      default:
        return staffList.where((s) {
          final t = s.staffType.trim().toLowerCase();
          final g = (s.gender ?? '').trim().toLowerCase();
          return t == target || g == target;
        }).length;
    }
  }

  void _onStatCardTapped(StaffStatCardConfig config) {
    setState(() {
      switch (config.type) {
        case 'total':
          _clearAllFilters();
          break;
        case 'status':
          _filterStatus = (config.filterValue ?? config.label).toLowerCase();
          break;
        case 'gender':
          _filterGender = (config.filterValue ?? config.label).toLowerCase();
          break;
        case 'staff_type':
          _filterStaffType = config.filterValue ?? config.label;
          _activeTypeFilter = _filterStaffType;
          break;
        case 'qualification':
          _filterQualification = config.filterValue ?? config.label;
          break;
        default:
          break;
      }
    });
  }

  List<StaffMember> _filterStaffList(List<StaffMember> allStaff) {
    return allStaff.where((s) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matches = s.fullName.toLowerCase().contains(q) ||
            s.staffNo.toLowerCase().contains(q) ||
            (s.mobileNo != null && s.mobileNo!.contains(q)) ||
            s.staffType.toLowerCase().contains(q) ||
            (s.qualification != null && s.qualification!.toLowerCase().contains(q)) ||
            (s.village != null && s.village!.toLowerCase().contains(q)) ||
            (s.district != null && s.district!.toLowerCase().contains(q));
        if (!matches) return false;
      }

      final activeType = _filterStaffType ?? _activeTypeFilter;
      if (activeType != null && activeType != 'All') {
        if (s.staffType.trim().toLowerCase() != activeType.trim().toLowerCase()) {
          return false;
        }
      }

      if (_filterGender != null) {
        final g = (s.gender ?? '').trim().toLowerCase();
        final fg = _filterGender!.trim().toLowerCase();
        if (g != fg) {
          final isMaleFilter = fg == 'male' || fg == 'ladka' || fg == 'boy' || fg == 'boys' || fg == 'm';
          final isMaleStaff = g == 'male' || g == 'ladka' || g == 'boy' || g == 'boys' || g == 'm';
          final isFemaleFilter = fg == 'female' || fg == 'ladki' || fg == 'girl' || fg == 'girls' || fg == 'f';
          final isFemaleStaff = g == 'female' || g == 'ladki' || g == 'girl' || g == 'girls' || g == 'f';
          if (!((isMaleFilter && isMaleStaff) || (isFemaleFilter && isFemaleStaff))) {
            return false;
          }
        }
      }

      if (_filterStatus != null) {
        final fs = _filterStatus!.trim().toLowerCase();
        final isActiveFilter = fs == 'active' || fs == 'chalu' || fs == 'regular';
        final isInactiveFilter = fs == 'inactive' || fs == 'kharij' || fs == 'left';
        if (isActiveFilter && !s.isActive) return false;
        if (isInactiveFilter && s.isActive) return false;
      }

      if (_filterQualification != null && _filterQualification!.isNotEmpty) {
        if (s.qualification?.trim().toLowerCase() != _filterQualification!.trim().toLowerCase()) {
          return false;
        }
      }

      if (_filterVillage != null && _filterVillage!.isNotEmpty) {
        if (s.village != _filterVillage) return false;
      }

      if (_filterDistrict != null && _filterDistrict!.isNotEmpty) {
        if (s.district != _filterDistrict) return false;
      }

      if (_filterState != null && _filterState!.isNotEmpty) {
        if (s.state != _filterState) return false;
      }

      if (_filterMinSalary != null && _filterMinSalary!.isNotEmpty) {
        final min = double.tryParse(_filterMinSalary!);
        if (min != null && s.salary < min) return false;
      }

      if (_filterMaxSalary != null && _filterMaxSalary!.isNotEmpty) {
        final max = double.tryParse(_filterMaxSalary!);
        if (max != null && s.salary > max) return false;
      }

      if (_filterMinExp != null && _filterMinExp!.isNotEmpty) {
        final min = int.tryParse(_filterMinExp!);
        if (min != null && s.experienceYears < min) return false;
      }

      if (_filterMaxExp != null && _filterMaxExp!.isNotEmpty) {
        final max = int.tryParse(_filterMaxExp!);
        if (max != null && s.experienceYears > max) return false;
      }

      return true;
    }).toList();
  }

  void _openStaffProfile(String staffId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<StaffBloc>(),
          child: StaffProfileScreen(
            staffId: staffId,
            onBack: () {
              Navigator.of(context).pop();
              context.read<StaffBloc>().add(LoadStaff(silent: true));
            },
          ),
        ),
      ),
    );
  }

  bool _isSelectionMode = false;
  List<String> _selectedStaffIds = [];

  void _toggleSelection(String staffId) {
    setState(() {
      if (_selectedStaffIds.contains(staffId)) {
        _selectedStaffIds.remove(staffId);
      } else {
        _selectedStaffIds.add(staffId);
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedStaffIds.clear();
      }
    });
  }

  void _showBulkDeleteConfirmDialog() {
    if (_selectedStaffIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('confirm_delete'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedStaffIds.length} selected staff members? This action cannot be undone and will delete all their details.',
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
              context.read<StaffBloc>().add(BulkDeleteStaff(List.from(_selectedStaffIds)));
              Navigator.pop(ctx);
              setState(() {
                _isSelectionMode = false;
                _selectedStaffIds.clear();
              });
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context.read<StaffBloc>().add(LoadStaff());
    _loadStaffTypes();
    _loadStatCardConfigs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadStaffTypes() async {
    try {
      final resp = await ApiClient().get('/staff/types');
      final dynamic raw = resp.data;
      List types = [];
      if (raw is List) {
        types = raw;
      } else if (raw is Map && raw['data'] is List) {
        types = raw['data'];
      }
      if (mounted && types.isNotEmpty) {
        setState(() {
          _typeFilters = [
            'All',
            ...types
                .map((t) => (t is Map ? t['name'] : t.toString()).toString().trim())
                .where((s) => s.isNotEmpty)
          ];
        });
      }
    } catch (_) {}
  }

  void _onSearchChanged(String q) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _searchQuery = q);
      context.read<StaffBloc>().add(SearchStaff(q));
    });
  }

  void _applyTypeFilter(String type) {
    final filter = type == 'All' ? null : type;
    setState(() => _activeTypeFilter = filter);
    context.read<StaffBloc>().add(FilterByType(filter));
  }

  void _showForm([StaffMember? staff]) {
    if (staff == null) {
      if (!_ensureFeatureAccess('staff_add', 'Add New Staff / Teacher')) return;
    } else {
      if (!_ensureFeatureAccess('staff_edit', 'Edit Staff Details')) return;
    }

    if (MediaQuery.of(context).size.width < 700) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: context.read<StaffBloc>(),
            child: StaffFormDialog(staff: staff),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => BlocProvider.value(
          value: context.read<StaffBloc>(),
          child: StaffFormDialog(staff: staff),
        ),
      );
    }
  }

  void _deleteStaff(StaffMember staff) {
    if (!_ensureFeatureAccess('staff_edit', 'Delete / Archive Staff')) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('delete_staff'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          '${context.tr('delete')} ${staff.fullName} (${staff.staffNo})?',
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
              context.read<StaffBloc>().add(DeleteStaff(staff.id));
              Navigator.pop(context);
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

    // Profile view fallback
    if (_selectedStaffId != null) {
      return StaffProfileScreen(
        staffId: _selectedStaffId!,
        onBack: () {
          setState(() => _selectedStaffId = null);
          context.read<StaffBloc>().add(LoadStaff(silent: true));
        },
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocListener<StaffBloc, StaffState>(
      listener: (context, state) {
        if (state is StaffOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(state.message),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        if (state is StaffError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isCompact = width < 700;
          final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

          return Column(
            children: [
              // TabBar
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
                  onTap: (i) {
                    if (i == 1) _loadStaffTypes(); // Refresh types when switching
                  },
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
                              context.tr('staff_list'),
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
                          Icon(Icons.settings_rounded, size: isCompact ? (14.0 * scale) : 16),
                          SizedBox(width: isCompact ? (4.0 * scale) : 6),
                          Flexible(
                            child: Text(
                              context.tr('administration'),
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
                  children: [_buildStaffListTab(isDark), const StaffTypesTab()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStaffListTab(bool isDark) {
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
            vertical: isCompact ? 0 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isCompact) ...[
                _buildHeader(isDark, isCompact, scale),
                const SizedBox(height: 20),
              ],
              Expanded(
                child: BlocBuilder<StaffBloc, StaffState>(
                  builder: (context, state) {
                    if (state is StaffLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is StaffError) {
                      return _buildError(state.message);
                    }

                    List<StaffMember> staffList = [];
                    if (state is StaffLoaded) staffList = state.staff;
                    if (state is StaffOperationSuccess) {
                      staffList = state.staff;
                    }

                    final filteredList = _filterStaffList(staffList);

                    if (isCompact) {
                      return CustomScrollView(
                        key: const PageStorageKey('staff_compact_scroll'),
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(8 * scale, 10 * scale, 8 * scale, 0),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeader(isDark, true, scale),
                                  SizedBox(height: 10 * scale),
                                  _buildStats(staffList, isDark, true, scale),
                                  SizedBox(height: 10 * scale),
                                  if (_isSelectionMode) ...[
                                    Container(
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
                                            '${_selectedStaffIds.length} Selected',
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
                                                if (_selectedStaffIds.length == filteredList.length) {
                                                  _selectedStaffIds.clear();
                                                } else {
                                                  _selectedStaffIds = filteredList.map((s) => s.id).toList();
                                                }
                                              });
                                            },
                                            icon: Icon(
                                              _selectedStaffIds.length == filteredList.length && filteredList.isNotEmpty
                                                  ? Icons.select_all_rounded
                                                  : Icons.select_all_outlined,
                                              size: 18 * scale,
                                              color: AppTheme.primaryColor,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            tooltip: _selectedStaffIds.length == filteredList.length
                                                ? 'Deselect All'
                                                : 'Select All',
                                          ),
                                          SizedBox(width: 8 * scale),
                                          IconButton(
                                            onPressed: _selectedStaffIds.isEmpty
                                                ? null
                                                : _showBulkDeleteConfirmDialog,
                                            icon: Icon(
                                              Icons.delete_sweep_rounded,
                                              color: _selectedStaffIds.isEmpty
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
                                    ),
                                    SizedBox(height: 10 * scale),
                                  ],
                                  _buildFilterChips(isDark, true),
                                  SizedBox(height: 8 * scale),
                                  _buildSearchBar(isDark, true, isWide, allStaff: staffList),
                                  _buildActiveFilterChips(isDark),
                                  SizedBox(height: 10 * scale),
                                ],
                              ),
                            ),
                          ),
                          if (filteredList.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                                child: _buildEmpty(),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _StaffCard(
                                      staff: filteredList[i],
                                      isDark: isDark,
                                      isSelectionMode: _isSelectionMode,
                                      isSelected: _selectedStaffIds.contains(filteredList[i].id),
                                      onSelectChanged: (val) => _toggleSelection(filteredList[i].id),
                                      onView: () => _openStaffProfile(filteredList[i].id),
                                      onEdit: () => _showForm(filteredList[i]),
                                      onDelete: () => _deleteStaff(filteredList[i]),
                                    ),
                                  ),
                                  childCount: filteredList.length,
                                ),
                              ),
                            ),
                        ],
                      );
                    }

                    // Desktop/Tablet layout
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isSelectionMode) ...[
                          Container(
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
                                  '${_selectedStaffIds.length} Selected',
                                  style: AppTheme.getFontStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      if (_selectedStaffIds.length == filteredList.length) {
                                        _selectedStaffIds.clear();
                                      } else {
                                        _selectedStaffIds = filteredList.map((s) => s.id).toList();
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    _selectedStaffIds.length == filteredList.length && filteredList.isNotEmpty
                                        ? Icons.deselect_rounded
                                        : Icons.select_all_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _selectedStaffIds.length == filteredList.length && filteredList.isNotEmpty
                                        ? 'Deselect All'
                                        : 'Select All',
                                    style: AppTheme.getFontStyle(fontSize: 12),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                                const Spacer(),
                                FilledButton.icon(
                                  onPressed: _selectedStaffIds.isEmpty
                                      ? null
                                      : _showBulkDeleteConfirmDialog,
                                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                                  label: const Text('Delete Selected'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _selectedStaffIds.isEmpty
                                        ? (isDark ? Colors.white24 : Colors.grey.shade400)
                                        : Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildStats(staffList, isDark, false, 1.0),
                        const SizedBox(height: 16),
                        _buildFilterChips(isDark, false),
                        const SizedBox(height: 14),
                        _buildSearchBar(isDark, false, isWide, allStaff: staffList),
                        _buildActiveFilterChips(isDark),
                        const SizedBox(height: 16),
                        Expanded(
                          child: filteredList.isEmpty
                              ? _buildEmpty()
                              : (_viewMode == 'card'
                                  ? _buildCardGrid(
                                      filteredList,
                                      isDark,
                                      isCompact,
                                      isMedium,
                                      isWide,
                                    )
                                  : _buildTableView(filteredList, isDark, isWide)),
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

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, bool isCompact, double scale) {
    if (isCompact) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('staff_management'),
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
                  context.tr('manage_staff_subtitle'),
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
          // Print ID Cards button
          BlocBuilder<StaffBloc, StaffState>(
            builder: (context, state) {
              List<StaffMember> staffList = [];
              if (state is StaffLoaded) staffList = state.staff;
              if (state is StaffOperationSuccess) staffList = state.staff;
              if (staffList.isNotEmpty) {
                return Padding(
                  padding: EdgeInsets.only(right: 8 * scale),
                  child: IconButton(
                    onPressed: () {
                      if (_ensureFeatureAccess('staff_view', 'Staff ID Cards')) {
                        StaffIdCardBuilderDialog.showBulk(
                          context,
                          staffList,
                        );
                      }
                    },
                    icon: Icon(Icons.print_rounded, size: 20 * scale),
                    color: AppTheme.primaryColor,
                    style: IconButton.styleFrom(
                      side: BorderSide(color: AppTheme.primaryColor.withAlpha(80)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10 * scale),
                      ),
                      padding: EdgeInsets.all(8 * scale),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            onPressed: _toggleSelectionMode,
            icon: Icon(
              _isSelectionMode ? Icons.cancel : Icons.checklist_rounded,
              size: 20 * scale,
            ),
            color: _isSelectionMode
                ? Colors.red
                : AppTheme.primaryColor,
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
          IconButton(
            onPressed: () => _showForm(),
            icon: Icon(Icons.add_rounded, size: 20 * scale),
            color: Colors.white,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              padding: EdgeInsets.all(8 * scale),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('staff_management'),
                style: AppTheme.getFontStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                context.tr('manage_staff_subtitle'),
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
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
        // Print ID Cards button
        BlocBuilder<StaffBloc, StaffState>(
          builder: (context, state) {
            List<StaffMember> staffList = [];
            if (state is StaffLoaded) staffList = state.staff;
            if (state is StaffOperationSuccess) staffList = state.staff;
            if (staffList.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton.icon(
                  onPressed: () => StaffIdCardBuilderDialog.showBulk(
                    context,
                    staffList,
                  ),
                  icon: const Icon(Icons.badge_rounded, size: 18),
                  label: Text(
                    'Print ID Cards',
                    style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(color: AppTheme.primaryColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        FilledButton.icon(
          onPressed: () => _showForm(),
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: Text(
            context.tr('add_staff'),
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
      ],
    );
  }

  // ── Stats ────────────────────────────────────────────────────────────────────
  Widget _buildStats(List<StaffMember> staff, bool isDark, bool isCompact, double scale) {
    final configs = _statCardConfigs.length == 4
        ? _statCardConfigs
        : [
            StaffStatCardConfig(
              id: 'card_1',
              type: 'total',
              label: context.tr('total_staff'),
              filterValue: null,
              iconCodePoint: Icons.people_alt_rounded.codePoint,
              colorValue: 0xFF0D6B4E,
            ),
            StaffStatCardConfig(
              id: 'card_2',
              type: 'status',
              label: context.tr('active'),
              filterValue: 'Active',
              iconCodePoint: Icons.check_circle_rounded.codePoint,
              colorValue: 0xFF1565C0,
            ),
            StaffStatCardConfig(
              id: 'card_3',
              type: 'staff_type',
              label: context.tr('teachers'),
              filterValue: 'Teacher',
              iconCodePoint: Icons.school_rounded.codePoint,
              colorValue: 0xFF6A1B9A,
            ),
            StaffStatCardConfig(
              id: 'card_4',
              type: 'gender',
              label: 'Male',
              filterValue: 'Male',
              iconCodePoint: Icons.male_rounded.codePoint,
              colorValue: 0xFFE65100,
            ),
          ];

    final stats = configs.asMap().entries.map((entry) {
      final idx = entry.key;
      final config = entry.value;
      final count = _calculateStatCount(staff, config);
      return _MiniStat(
        label: config.label,
        value: count.toString(),
        icon: config.icon,
        color: config.color,
        isDark: isDark,
        scale: scale,
        onTap: () => _onStatCardTapped(config),
        onSettingsTap: () => _showQuickEditSingleCardDialog(idx, staff),
      );
    }).toList();

    final customizeButton = InkWell(
      onTap: () => _showCustomizeStatCardsDialog(staff),
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
                'STAFF METRICS',
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
            children: stats,
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
                    child: s,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  void _showQuickEditSingleCardDialog(int cardIndex, List<StaffMember> allStaff) {
    _showCustomizeStatCardsDialog(allStaff, initialCardIndex: cardIndex);
  }

  Future<void> _showCustomizeStatCardsDialog(List<StaffMember> allStaff, {int initialCardIndex = 0}) async {
    List<String> statusList = [];
    List<String> genderList = [];
    List<String> typeList = [];
    List<String> qualList = [];

    // Genders strictly from Students Page options (No extra data)
    try {
      final savedGenders = await StudentFormOptionsSettings.getGenders();
      genderList = savedGenders
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      genderList = List.from(StudentFormOptionsSettings.defaultGenders);
    }
    if (genderList.isEmpty) {
      genderList = List.from(StudentFormOptionsSettings.defaultGenders);
    }

    // Statuses strictly from Students Page options (No extra data)
    try {
      final savedStatuses = await StudentStatusSettings.getStatuses();
      statusList = savedStatuses
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      statusList = List.from(StudentStatusSettings.defaultStatuses);
    }
    if (statusList.isEmpty) {
      statusList = List.from(StudentStatusSettings.defaultStatuses);
    }

    // Staff Types strictly from Administration Page (/staff/types)
    try {
      final resp = await ApiClient().get('/staff/types');
      final dynamic raw = resp.data;
      List types = [];
      if (raw is List) {
        types = raw;
      } else if (raw is Map && raw['data'] is List) {
        types = raw['data'];
      }
      typeList = types
          .map((t) => (t is Map ? t['name'] : t.toString()).toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {}
    if (typeList.isEmpty) {
      typeList = ['Teacher', 'Bavarchi', 'Nazim-e-Matbakh', 'Accountant', 'Worker', 'Office Staff', 'Other'];
    }

    // Qualifications strictly from Administration Page (/staff/qualifications)
    try {
      final resp = await ApiClient().get('/staff/qualifications');
      final dynamic raw = resp.data;
      List quals = [];
      if (raw is List) {
        quals = raw;
      } else if (raw is Map && raw['data'] is List) {
        quals = raw['data'];
      }
      qualList = quals
          .map((q) => (q is Map ? q['name'] : q.toString()).toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {}
    if (qualList.isEmpty) {
      qualList = ['Matric', 'Intermediate', 'Bachelor', 'Master', 'PhD', 'Hafiz', 'Alim', 'Fazil', 'Other'];
    }

    List<StaffStatCardConfig> tempConfigs = _statCardConfigs.map((c) => c.copyWith()).toList();
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
              Icons.school_rounded,
              Icons.male_rounded,
              Icons.female_rounded,
              Icons.check_circle_rounded,
              Icons.cancel_outlined,
              Icons.menu_book_rounded,
              Icons.phone_android_rounded,
              Icons.badge_rounded,
              Icons.payments_rounded,
              Icons.support_agent_rounded,
              Icons.work_rounded,
            ];

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6B4E).withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF0D6B4E), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customize Staff Summary Cards',
                          style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '4 Summary cards ko apni marzi se configure karein',
                          style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              content: SizedBox(
                width: isMobile ? screenWidth * 0.92 : 560,
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
                          final count = _calculateStatCount(allStaff, cfg);
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
                        value: currentCard.type,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'total', child: Text('Total Staff (Kul Staff)')),
                          DropdownMenuItem(value: 'status', child: Text('Status (Active, Inactive, etc.)')),
                          DropdownMenuItem(value: 'staff_type', child: Text('Staff Type / Designation (Teacher, Nazim, etc.)')),
                          DropdownMenuItem(value: 'gender', child: Text('Gender / Jins (Male, Female, Ladka, Ladki)')),
                          DropdownMenuItem(value: 'qualification', child: Text('Qualification (Alim, Hafiz, MA, etc.)')),
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
                            newLabel = 'Total Staff';
                            newFilter = null;
                            iconCode = Icons.people_alt_rounded.codePoint;
                            colVal = 0xFF0D6B4E;
                          } else if (newType == 'status') {
                            newFilter = 'Active';
                            newLabel = 'Active';
                            iconCode = Icons.check_circle_rounded.codePoint;
                            colVal = 0xFF1565C0;
                          } else if (newType == 'staff_type') {
                            newFilter = typeList.isNotEmpty ? typeList.first : 'Teacher';
                            newLabel = newFilter;
                            iconCode = Icons.school_rounded.codePoint;
                            colVal = 0xFF6A1B9A;
                          } else if (newType == 'gender') {
                            newFilter = genderList.isNotEmpty ? genderList.first : 'Male';
                            newLabel = newFilter;
                            iconCode = Icons.male_rounded.codePoint;
                            colVal = 0xFFE65100;
                          } else if (newType == 'qualification') {
                            newFilter = qualList.isNotEmpty ? qualList.first : 'Alim';
                            newLabel = newFilter;
                            iconCode = Icons.menu_book_rounded.codePoint;
                            colVal = 0xFF00695C;
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
                          currentCard.type == 'staff_type' ||
                          currentCard.type == 'gender' ||
                          currentCard.type == 'qualification') ...[
                        Text(
                          '2. Select Target ${currentCard.type.toUpperCase()} to Match',
                          style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (ctx) {
                            List<String> items = [];
                            if (currentCard.type == 'status') items = statusList;
                            if (currentCard.type == 'staff_type') items = typeList;
                            if (currentCard.type == 'gender') items = genderList;
                            if (currentCard.type == 'qualification') items = qualList;

                            final currentVal = currentCard.filterValue;
                            final valueToUse = (currentVal != null && items.contains(currentVal))
                                ? currentVal
                                : (items.isNotEmpty ? items.first : null);

                            return DropdownButtonFormField<String>(
                              value: valueToUse,
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
                          hintText: 'e.g. Total, Teachers, Active, Asateza...',
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
              actions: [
                SizedBox(
                  width: double.infinity,
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
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showFilterDialog(List<StaffMember> allStaff) async {
    String? tempType = _filterStaffType ?? _activeTypeFilter;
    String? tempGender = _filterGender;
    String? tempStatus = _filterStatus;
    String? tempQual = _filterQualification;
    String? tempVillage = _filterVillage;
    String? tempDistrict = _filterDistrict;
    String? tempState = _filterState;

    final minSalCtrl = TextEditingController(text: _filterMinSalary ?? '');
    final maxSalCtrl = TextEditingController(text: _filterMaxSalary ?? '');
    final minExpCtrl = TextEditingController(text: _filterMinExp ?? '');
    final maxExpCtrl = TextEditingController(text: _filterMaxExp ?? '');

    // Genders strictly from Students Page settings (No extra data)
    List<String> genders = [];
    try {
      final savedGenders = await StudentFormOptionsSettings.getGenders();
      genders = savedGenders
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      genders = List.from(StudentFormOptionsSettings.defaultGenders);
    }
    if (genders.isEmpty) genders = List.from(StudentFormOptionsSettings.defaultGenders);

    // Statuses strictly from Students Page settings (No extra data)
    List<String> statuses = [];
    try {
      final savedStatuses = await StudentStatusSettings.getStatuses();
      statuses = savedStatuses
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      statuses = List.from(StudentStatusSettings.defaultStatuses);
    }
    if (statuses.isEmpty) statuses = List.from(StudentStatusSettings.defaultStatuses);

    // Staff Types strictly from Administration Page (No extra data)
    List<String> staffTypes = [];
    try {
      final resp = await ApiClient().get('/staff/types');
      final dynamic raw = resp.data;
      List types = [];
      if (raw is List) {
        types = raw;
      } else if (raw is Map && raw['data'] is List) {
        types = raw['data'];
      }
      staffTypes = types
          .map((t) => (t is Map ? t['name'] : t.toString()).toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {}
    if (staffTypes.isEmpty) {
      staffTypes = ['Teacher', 'Bavarchi', 'Nazim-e-Matbakh', 'Accountant', 'Worker', 'Office Staff', 'Other'];
    }

    // Qualifications strictly from Administration Page (No extra data)
    List<String> qualifications = [];
    try {
      final resp = await ApiClient().get('/staff/qualifications');
      final dynamic raw = resp.data;
      List quals = [];
      if (raw is List) {
        quals = raw;
      } else if (raw is Map && raw['data'] is List) {
        quals = raw['data'];
      }
      qualifications = quals
          .map((q) => (q is Map ? q['name'] : q.toString()).toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {}
    if (qualifications.isEmpty) {
      qualifications = ['Matric', 'Intermediate', 'Bachelor', 'Master', 'PhD', 'Hafiz', 'Alim', 'Fazil', 'Other'];
    }

    final villages = allStaff
        .map((s) => s.village?.trim())
        .where((v) => v != null && v.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    final districts = allStaff
        .map((s) => s.district?.trim())
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    final states = allStaff
        .map((s) => s.state?.trim())
        .where((st) => st != null && st.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()..sort();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
            final screenWidth = MediaQuery.of(dialogCtx).size.width;
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

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * scale)),
              backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              insetPadding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 20 * scale),
              titlePadding: EdgeInsets.fromLTRB(14 * scale, 14 * scale, 14 * scale, 6 * scale),
              contentPadding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
              actionsPadding: EdgeInsets.fromLTRB(10 * scale, 6 * scale, 10 * scale, 10 * scale),
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(5 * scale),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.filter_alt_rounded, color: AppTheme.primaryColor, size: (20 * scale).clamp(16.0, 22.0)),
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Advanced Staff Filter',
                          style: AppTheme.getFontStyle(fontSize: (15 * scale).clamp(13.0, 17.0), fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Staff records ko customize karke filter karein',
                          style: AppTheme.getFontStyle(fontSize: (10.5 * scale).clamp(9.0, 12.0), color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18 * scale),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              content: SizedBox(
                width: screenWidth < 500 ? screenWidth * 0.90 : 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Staff Type Filter
                      Text('1. Staff Type / Designation', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        value: (tempType != null && tempType != 'All' && staffTypes.contains(tempType)) ? tempType : null,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Staff Types'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Staff Types', style: itemStyle())),
                          ...staffTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempType = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('2. Gender / Jins', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        value: (tempGender != null && genders.any((g) => g.toLowerCase() == tempGender!.toLowerCase()))
                            ? tempGender
                            : null,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Genders'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Genders', style: itemStyle())),
                          ...genders.map((g) => DropdownMenuItem<String?>(value: g.toLowerCase(), child: Text(g, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempGender = v),
                      ),
                      SizedBox(height: 10 * scale),

                      Text('3. Status', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      DropdownButtonFormField<String?>(
                        value: (tempStatus != null && statuses.any((st) => st.toLowerCase() == tempStatus!.toLowerCase()))
                            ? tempStatus
                            : null,
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        style: itemStyle(),
                        decoration: dropdownDeco('All Statuses'),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text('All Statuses', style: itemStyle())),
                          ...statuses.map((st) => DropdownMenuItem<String?>(value: st.toLowerCase(), child: Text(st, style: itemStyle()))),
                        ],
                        onChanged: (v) => setModalState(() => tempStatus = v),
                      ),
                      SizedBox(height: 10 * scale),

                      if (qualifications.isNotEmpty) ...[
                        Text('4. Qualification', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                        SizedBox(height: 4 * scale),
                        DropdownButtonFormField<String?>(
                          value: tempQual,
                          isExpanded: true,
                          dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                          style: itemStyle(),
                          decoration: dropdownDeco('All Qualifications'),
                          items: [
                            DropdownMenuItem<String?>(value: null, child: Text('All Qualifications', style: itemStyle())),
                            ...qualifications.map((q) => DropdownMenuItem<String?>(value: q, child: Text(q, style: itemStyle()))),
                          ],
                          onChanged: (v) => setModalState(() => tempQual = v),
                        ),
                        SizedBox(height: 10 * scale),
                      ],

                      if (villages.isNotEmpty) ...[
                        Text('5. Village / City', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                        SizedBox(height: 4 * scale),
                        DropdownButtonFormField<String?>(
                          value: tempVillage,
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
                      ],

                      if (districts.isNotEmpty) ...[
                        Text('6. District', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                        SizedBox(height: 4 * scale),
                        DropdownButtonFormField<String?>(
                          value: tempDistrict,
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
                      ],

                      if (states.isNotEmpty) ...[
                        Text('7. State', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                        SizedBox(height: 4 * scale),
                        DropdownButtonFormField<String?>(
                          value: tempState,
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
                      ],

                      Text('8. Salary Range (₹)', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: minSalCtrl,
                              keyboardType: TextInputType.number,
                              style: itemStyle(),
                              decoration: dropdownDeco('Min Salary'),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6 * scale),
                            child: Text('-', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: maxSalCtrl,
                              keyboardType: TextInputType.number,
                              style: itemStyle(),
                              decoration: dropdownDeco('Max Salary'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10 * scale),

                      Text('9. Experience Range (Years)', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: (11.5 * scale).clamp(9.5, 13.0))),
                      SizedBox(height: 4 * scale),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: minExpCtrl,
                              keyboardType: TextInputType.number,
                              style: itemStyle(),
                              decoration: dropdownDeco('Min Years'),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6 * scale),
                            child: Text('-', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                          ),
                          Expanded(
                            child: TextField(
                              controller: maxExpCtrl,
                              keyboardType: TextInputType.number,
                              style: itemStyle(),
                              decoration: dropdownDeco('Max Years'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _clearAllFilters();
                    });
                    Navigator.pop(dialogCtx);
                  },
                  child: Text('Clear All', style: TextStyle(fontSize: (12 * scale).clamp(10.0, 14.0), color: Colors.red)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                    padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                  ),
                  onPressed: () {
                    setState(() {
                      _filterStaffType = tempType;
                      _activeTypeFilter = tempType;
                      _filterGender = tempGender;
                      _filterStatus = tempStatus;
                      _filterQualification = tempQual;
                      _filterVillage = tempVillage;
                      _filterDistrict = tempDistrict;
                      _filterState = tempState;
                      _filterMinSalary = minSalCtrl.text.trim().isNotEmpty ? minSalCtrl.text.trim() : null;
                      _filterMaxSalary = maxSalCtrl.text.trim().isNotEmpty ? maxSalCtrl.text.trim() : null;
                      _filterMinExp = minExpCtrl.text.trim().isNotEmpty ? minExpCtrl.text.trim() : null;
                      _filterMaxExp = maxExpCtrl.text.trim().isNotEmpty ? maxExpCtrl.text.trim() : null;
                    });
                    Navigator.pop(dialogCtx);
                  },
                  child: Text('Apply Filters', style: TextStyle(fontSize: (12 * scale).clamp(10.0, 14.0))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFilterChips(bool isDark) {
    if (!_hasActiveFilters) return const SizedBox.shrink();

    final chips = <Widget>[];

    void addChip(String label, VoidCallback onRemove) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Icon(Icons.close_rounded, size: 13, color: isDark ? Colors.white70 : AppTheme.primaryColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeType = _filterStaffType ?? _activeTypeFilter;
    if (activeType != null && activeType != 'All') {
      addChip('Type: $activeType', () {
        setState(() {
          _filterStaffType = null;
          _activeTypeFilter = null;
        });
      });
    }

    if (_filterGender != null) {
      addChip('Gender: ${_filterGender!.toUpperCase()}', () {
        setState(() => _filterGender = null);
      });
    }

    if (_filterStatus != null) {
      addChip('Status: ${_filterStatus!.toUpperCase()}', () {
        setState(() => _filterStatus = null);
      });
    }

    if (_filterQualification != null) {
      addChip('Qual: $_filterQualification', () {
        setState(() => _filterQualification = null);
      });
    }

    if (_filterVillage != null) {
      addChip('Village: $_filterVillage', () {
        setState(() => _filterVillage = null);
      });
    }

    if (_filterDistrict != null) {
      addChip('District: $_filterDistrict', () {
        setState(() => _filterDistrict = null);
      });
    }

    if (_filterState != null) {
      addChip('State: $_filterState', () {
        setState(() => _filterState = null);
      });
    }

    if (_filterMinSalary != null || _filterMaxSalary != null) {
      addChip('Salary: ₹${_filterMinSalary ?? '0'} - ₹${_filterMaxSalary ?? '∞'}', () {
        setState(() {
          _filterMinSalary = null;
          _filterMaxSalary = null;
        });
      });
    }

    if (_filterMinExp != null || _filterMaxExp != null) {
      addChip('Exp: ${_filterMinExp ?? '0'} - ${_filterMaxExp ?? '∞'} yrs', () {
        setState(() {
          _filterMinExp = null;
          _filterMaxExp = null;
        });
      });
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            ...chips,
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter Chips ─────────────────────────────────────────────────────────────
  Widget _buildFilterChips(bool isDark, bool isCompact) {
    if (isCompact) {
      final currentLabel = _activeTypeFilter == null
          ? context.tr('all')
          : _activeTypeFilter!;

      return Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<String>(
          onSelected: _applyTypeFilter,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          itemBuilder: (context) => _typeFilters
              .map((type) => PopupMenuItem<String>(
                    value: type,
                    child: Row(
                      children: [
                        if ((type == 'All' && _activeTypeFilter == null) ||
                            _activeTypeFilter == type)
                          Icon(Icons.check_rounded,
                              color: AppTheme.primaryColor, size: 16)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(
                          type == 'All' ? context.tr('all') : type,
                          style: AppTheme.getFontStyle(
                            fontSize: 13,
                            fontWeight: ((type == 'All' &&
                                        _activeTypeFilter == null) ||
                                    _activeTypeFilter == type)
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_list_rounded,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '${context.tr('filter')}: $currentLabel',
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _typeFilters.map((type) {
          final isActive =
              (type == 'All' && _activeTypeFilter == null) ||
              _activeTypeFilter == type;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              child: FilterChip(
                label: Text(
                  type == 'All' ? context.tr('all') : type,
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? Colors.white : null,
                  ),
                ),
                selected: isActive,
                onSelected: (_) => _applyTypeFilter(type),
                selectedColor: AppTheme.primaryColor,
                checkmarkColor: Colors.white,
                backgroundColor: isDark
                    ? const Color(0xFF1E1E2E)
                    : Colors.grey.shade100,
                side: BorderSide(
                  color: isActive
                      ? AppTheme.primaryColor
                      : isDark
                      ? Colors.white.withAlpha(15)
                      : Colors.grey.shade200,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Search Bar ────────────────────────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark, bool isCompact, bool isWide, {List<StaffMember>? allStaff}) {
    return Container(
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
              controller: _searchCtrl,
              style: AppTheme.getFontStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: isCompact
                    ? '${context.tr('search')}...'
                    : context.tr('search_staff_hint'),
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
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              onPressed: () {
                _searchCtrl.clear();
                _onSearchChanged('');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          if (allStaff != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _showFilterDialog(allStaff),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _hasActiveFilters
                      ? AppTheme.primaryColor.withAlpha(isDark ? 50 : 25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: _hasActiveFilters
                      ? Border.all(color: AppTheme.primaryColor)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hasActiveFilters
                          ? Icons.filter_alt_rounded
                          : Icons.filter_alt_outlined,
                      size: 18,
                      color: _hasActiveFilters
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 4),
                      Text(
                        'Filtered',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Card Grid ─────────────────────────────────────────────────────────────────
  Widget _buildCardGrid(
    List<StaffMember> staff,
    bool isDark,
    bool isCompact,
    bool isMedium,
    bool isWide,
  ) {
    final crossAxis = isCompact
        ? 1
        : isMedium
        ? 2
        : isWide
        ? 3
        : 2;
    return GridView.builder(
      key: const PageStorageKey('staff_grid'),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxis,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isCompact ? 3.2 : 2.2,
      ),
      itemCount: staff.length,
      itemBuilder: (context, i) => _StaffCard(
        staff: staff[i],
        isDark: isDark,
        isSelectionMode: _isSelectionMode,
        isSelected: _selectedStaffIds.contains(staff[i].id),
        onSelectChanged: (val) => _toggleSelection(staff[i].id),
        onView: () => _openStaffProfile(staff[i].id),
        onEdit: () => _showForm(staff[i]),
        onDelete: () => _deleteStaff(staff[i]),
      ),
    );
  }

  // ── Table View ────────────────────────────────────────────────────────────────
  Widget _buildTableView(List<StaffMember> staff, bool isDark, bool isWide) {
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
            // Header row
            Container(
              color: isDark
                  ? const Color(0xFF2A2A3E)
                  : AppTheme.primaryColor.withAlpha(12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (_isSelectionMode)
                    SizedBox(
                      width: 32,
                      child: Checkbox(
                        value: _selectedStaffIds.length == staff.length && staff.isNotEmpty,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedStaffIds = staff.map((st) => st.id).toList();
                            } else {
                              _selectedStaffIds.clear();
                            }
                          });
                        },
                      ),
                    ),
                  _TH('#', 1),
                  _TH(context.tr('staff_no').toUpperCase(), 2),
                  _TH(context.tr('name').toUpperCase(), 4),
                  _TH(context.tr('type').toUpperCase(), 2),
                  if (isWide) _TH('MOBILE', 2),
                  if (isWide) _TH('SALARY', 2),
                  _TH(context.tr('status').toUpperCase(), 2),
                  _TH(context.tr('actions').toUpperCase(), 3, center: true),
                ],
              ),
            ),
            // Rows
            Expanded(
              child: ListView.separated(
                key: const PageStorageKey('staff_table_list'),
                itemCount: staff.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withAlpha(6)
                      : Colors.grey.shade100,
                ),
                itemBuilder: (context, i) {
                  final s = staff[i];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSelectionMode
                          ? () => _toggleSelection(s.id)
                          : () => _openStaffProfile(s.id),
                      child: Container(
                        color: i.isOdd
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
                                width: 32,
                                child: Checkbox(
                                  value: _selectedStaffIds.contains(s.id),
                                  onChanged: (val) {
                                    _toggleSelection(s.id);
                                  },
                                ),
                              ),
                            _TC('${i + 1}', 1, isDark: isDark, muted: true),
                            _TC(
                              s.staffNo,
                              2,
                              isDark: isDark,
                              bold: true,
                              color: AppTheme.primaryColor,
                            ),
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _typeColor(
                                        s.staffType,
                                      ).withAlpha(isDark ? 40 : 22),
                                    ),
                                    child: Center(
                                      child: Text(
                                        s.initials,
                                        style: AppTheme.getFontStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _typeColor(s.staffType),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      s.fullName,
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
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _typeColor(
                                    s.staffType,
                                  ).withAlpha(isDark ? 35 : 15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  s.staffType,
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _typeColor(s.staffType),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (isWide) ...[
                              _TC(s.mobileNo ?? '-', 2, isDark: isDark),
                              _TC(
                                s.salary > 0
                                    ? '₹${s.salary.toStringAsFixed(0)}'
                                    : '-',
                                2,
                                isDark: isDark,
                              ),
                            ],
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (s.isActive
                                              ? const Color(0xFF0D6B4E)
                                              : Colors.red)
                                          .withAlpha(15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        (s.isActive
                                                ? const Color(0xFF0D6B4E)
                                                : Colors.red)
                                            .withAlpha(50),
                                  ),
                                ),
                                child: Text(
                                  s.isActive ? 'Active' : 'Inactive',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: s.isActive
                                        ? const Color(0xFF0D6B4E)
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _ActionBtn(
                                    icon: Icons.remove_red_eye_rounded,
                                    color: AppTheme.primaryColor,
                                    tooltip: context.tr('view'),
                                    onTap: () => _openStaffProfile(s.id),
                                  ),
                                  _ActionBtn(
                                    icon: Icons.edit_rounded,
                                    color: const Color(0xFF1565C0),
                                    tooltip: context.tr('edit'),
                                    onTap: () => _showForm(s),
                                  ),
                                  _ActionBtn(
                                    icon: Icons.badge_rounded,
                                    color: const Color(0xFF0D6B4E),
                                    tooltip: 'Print ID Card',
                                    onTap: () {
                                      if (_ensureFeatureAccess('staff_view', 'Staff ID Cards')) {
                                        StaffIdCardBuilderDialog.show(context, s);
                                      }
                                    },
                                  ),
                                  _ActionBtn(
                                    icon: Icons.delete_rounded,
                                    color: Colors.red,
                                    tooltip: context.tr('delete'),
                                    onTap: () => _deleteStaff(s),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Showing ${staff.length} staff member${staff.length != 1 ? 's' : ''}',
                    style: AppTheme.getFontStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
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

  Widget _buildError(String msg) {
    return Center(
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
            child: const Icon(
              Icons.error_outline_rounded,
              size: 32,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading staff',
            style: AppTheme.getFontStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            msg,
            style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.read<StaffBloc>().add(LoadStaff()),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withAlpha(15),
            ),
            child: Icon(
              Icons.badge_rounded,
              size: 40,
              color: AppTheme.primaryColor.withAlpha(120),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isEmpty
                ? 'No staff members yet'
                : 'No results for "$_searchQuery"',
            style: AppTheme.getFontStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Click "Add Staff" to add your first member'
                : 'Try a different search term',
            style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.person_add_rounded),
              label: Text(context.tr('add_staff')),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Color by type ────────────────────────────────────────────────────────────
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

// ── Helper Widgets ───────────────────────────────────────────────────────────

class StaffStatCardConfig {
  final String id;
  final String type; // 'total', 'status', 'gender', 'staff_type', 'qualification', 'with_mobile', 'without_mobile', 'with_aadhaar', 'without_aadhaar', 'salary_above', 'exp_above'
  final String label;
  final String? filterValue;
  final int iconCodePoint;
  final String? iconFontFamily;
  final int colorValue;

  const StaffStatCardConfig({
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

  StaffStatCardConfig copyWith({
    String? id,
    String? type,
    String? label,
    String? filterValue,
    int? iconCodePoint,
    String? iconFontFamily,
    int? colorValue,
  }) {
    return StaffStatCardConfig(
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

  factory StaffStatCardConfig.fromJson(Map<String, dynamic> json) {
    return StaffStatCardConfig(
      id: json['id'] as String? ?? 'card',
      type: json['type'] as String? ?? 'total',
      label: json['label'] as String? ?? 'Total Staff',
      filterValue: json['filterValue'] as String?,
      iconCodePoint: json['iconCodePoint'] as int? ?? 0xe491,
      iconFontFamily: json['iconFontFamily'] as String?,
      colorValue: json['colorValue'] as int? ?? 0xFF0D6B4E,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;
  final double scale;
  final VoidCallback? onTap;
  final VoidCallback? onSettingsTap;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.scale,
    this.onTap,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onSettingsTap,
        borderRadius: BorderRadius.circular(12 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? (8.0 * scale) : 14,
            vertical: isCompact ? (8.0 * scale) : 10,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(12 * scale),
            border: Border.all(
              color: isDark ? color.withAlpha(35) : color.withAlpha(25),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(isDark ? 16 : 10),
                blurRadius: 8 * scale,
                offset: Offset(0, 2 * scale),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: (isCompact ? 32 : 36) * scale,
                height: (isCompact ? 32 : 36) * scale,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10 * scale),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withAlpha(isDark ? 55 : 30),
                      color.withAlpha(isDark ? 35 : 15),
                    ],
                  ),
                ),
                child: Icon(icon, color: color, size: (isCompact ? 16 : 18) * scale),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: AppTheme.getFontStyle(
                        fontSize: (isCompact ? 15 : 17) * scale,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        height: 1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      label,
                      style: AppTheme.getFontStyle(
                        fontSize: (isCompact ? 9.5 : 10.5) * scale,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onSettingsTap != null)
                GestureDetector(
                  onTap: onSettingsTap,
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
  final bool isDark;
  const _ViewToggle({
    required this.mode,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TogBtn(
            icon: Icons.view_list_rounded,
            active: mode == 'table',
            isDark: isDark,
            onTap: () => onChanged('table'),
          ),
          _TogBtn(
            icon: Icons.view_module_rounded,
            active: mode == 'card',
            isDark: isDark,
            onTap: () => onChanged('card'),
          ),
        ],
      ),
    );
  }
}

class _TogBtn extends StatelessWidget {
  final IconData icon;
  final bool active, isDark;
  final VoidCallback onTap;
  const _TogBtn({
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

class _TH extends StatelessWidget {
  final String label;
  final int flex;
  final bool center;
  const _TH(this.label, this.flex, {this.center = false});

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

class _TC extends StatelessWidget {
  final String text;
  final int flex;
  final bool isDark, bold, muted;
  final Color? color;
  const _TC(
    this.text,
    this.flex, {
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

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: color.withAlpha(15),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final StaffMember staff;
  final bool isDark;
  final VoidCallback onView, onEdit, onDelete;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectChanged;

  const _StaffCard({
    required this.staff,
    required this.isDark,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(staff.staffType);
    final hasPhoto = staff.photoPath != null && staff.photoPath!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isSelectionMode
            ? () => onSelectChanged?.call(!isSelected)
            : onView,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
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
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(isDark ? 40 : 22),
                  image: hasPhoto
                      ? DecorationImage(
                          image: NetworkImage(
                            '${ApiConstants.baseUrl.replaceAll("/api", "")}${staff.photoPath}',
                          ),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: !hasPhoto
                    ? Center(
                        child: Text(
                          staff.initials,
                          style: AppTheme.getFontStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      staff.fullName,
                      style: AppTheme.getFontStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // Staff Type badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(isDark ? 30 : 12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            staff.staffType,
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                        // Staff No badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            staff.staffNo,
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (staff.isActive ? const Color(0xFF0D6B4E) : Colors.red).withAlpha(isDark ? 30 : 12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            staff.isActive ? context.tr('active') : context.tr('inactive'),
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: staff.isActive ? const Color(0xFF0D6B4E) : Colors.red,
                            ),
                          ),
                        ),
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
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_red_eye_rounded,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('view'),
                          style: AppTheme.getFontStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.edit_rounded,
                          size: 16,
                          color: Color(0xFF1565C0),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('edit'),
                          style: AppTheme.getFontStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'id_card',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.badge_rounded,
                          size: 16,
                          color: Color(0xFF0D6B4E),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ID Card',
                          style: AppTheme.getFontStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.delete_rounded,
                          size: 16,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('delete'),
                          style: AppTheme.getFontStyle(
                            fontSize: 13,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'view') onView();
                  if (v == 'edit') onEdit();
                  if (v == 'id_card') {
                    final licenseState = context.read<LicenseCubit>().state;
                    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
                    if (!license.hasFeatureAccess('staff_view')) {
                      UpgradePlanDialog.show(context, highlightModule: 'Staff ID Cards');
                    } else {
                      StaffIdCardBuilderDialog.show(context, staff);
                    }
                  }
                  if (v == 'delete') onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
