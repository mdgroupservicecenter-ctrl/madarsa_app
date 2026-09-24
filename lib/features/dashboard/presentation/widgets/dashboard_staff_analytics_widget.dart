import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/student_form_options_settings.dart';
import '../../../staff/data/models/staff_model.dart';
import '../../../staff/data/repositories/staff_repository.dart';
import '../../../staff/presentation/screens/staff_profile_screen.dart';

class DashboardStaffAnalyticsWidget extends StatefulWidget {
  final bool isDark;
  final int totalStaffFallback;
  final void Function(String module)? onNavigate;
  final double? fixedHeight;
  final List<StaffMember>? initialStaff;

  const DashboardStaffAnalyticsWidget({
    super.key,
    required this.isDark,
    this.totalStaffFallback = 0,
    this.onNavigate,
    this.fixedHeight,
    this.initialStaff,
  });

  @override
  State<DashboardStaffAnalyticsWidget> createState() => _DashboardStaffAnalyticsWidgetState();
}

class _DashboardStaffAnalyticsWidgetState extends State<DashboardStaffAnalyticsWidget> {
  List<StaffMember> _staff = [];
  bool _isLoading = true;

  // Interactive Tab & Filter State
  int _selectedTabIndex = 0; // 0: Overview & Payroll, 1: By Category, 2: Individual Staff Salary
  String _selectedCategory = 'All';
  String? _selectedStaffId;

  // Customizable Gender Options (Loaded dynamically from user settings + staff records)
  List<String> _customGenders = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialStaff != null) {
      _staff = widget.initialStaff!;
      _isLoading = false;
      _syncGendersFromStaff();
      if (_staff.isNotEmpty) {
        _selectedStaffId = _staff.first.id;
      }
    } else {
      _loadStaffData();
    }
    _loadCustomGenders();
  }

  @override
  void didUpdateWidget(covariant DashboardStaffAnalyticsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStaff != oldWidget.initialStaff) {
      _staff = widget.initialStaff ?? [];
      _syncGendersFromStaff();
    }
  }

  Future<void> _loadStaffData() async {
    try {
      final repo = StaffRepository(ApiClient());
      final list = await repo.getAll();
      if (mounted) {
        setState(() {
          _staff = list;
          _isLoading = false;
          _syncGendersFromStaff();
          if (_staff.isNotEmpty && _selectedStaffId == null) {
            _selectedStaffId = _staff.first.id;
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

  void _syncGendersFromStaff() {
    final set = <String>{..._customGenders};
    for (final s in _staff) {
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
      for (final s in _staff) {
        final g = s.gender?.trim();
        if (g != null && g.isNotEmpty) set.add(g);
      }
      if (mounted && set.isNotEmpty) {
        setState(() {
          _customGenders = set.toList();
        });
      }
    } catch (_) {
      _syncGendersFromStaff();
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
    // Return user-defined custom gender name as-is
    return clean;
  }

  Map<String, int> _getGenderCounts(List<StaffMember> staffList) {
    final Map<String, int> counts = {};

    // Initialize with configured custom genders
    for (final cg in _customGenders) {
      final clean = cg.trim();
      if (clean.isNotEmpty && !counts.containsKey(clean)) {
        counts[clean] = 0;
      }
    }

    // Count staff records matching gender
    for (final s in staffList) {
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

  String _getGenderDisplayString(List<StaffMember> staffList, BuildContext context) {
    if (staffList.isEmpty) return context.tr('gender_distribution');

    final counts = _getGenderCounts(staffList);
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

  List<String> _getUniqueCategories() {
    final Set<String> categories = {};
    for (final s in _staff) {
      final type = s.staffType.trim();
      if (type.isNotEmpty) {
        categories.add(type);
      }
    }
    final list = categories.toList()..sort();
    return ['All', ...list];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final totalStaff = _staff.isNotEmpty ? _staff.length : widget.totalStaffFallback;

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
      child: _isLoading && _staff.isEmpty && widget.totalStaffFallback == 0
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
                // ── Interactive 3-Tab Selector ──
                _buildTabBar(isDark),
                const SizedBox(height: 10),

                // ── Tab Body Content ──
                if (widget.fixedHeight != null)
                  Expanded(
                    child: _buildActiveTabBody(isDark, totalStaff),
                  )
                else
                  _buildActiveTabBody(isDark, totalStaff),
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
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        context.tr('staff_analytics_overview'),
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
                onTap: () => widget.onNavigate?.call('staff'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('view_staff'),
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: AppTheme.primaryColor,
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
      (icon: Icons.analytics_rounded, label: context.tr('tab_overview')),
      (icon: Icons.category_rounded, label: context.tr('tab_by_category')),
      (icon: Icons.badge_rounded, label: context.tr('tab_staff_salary')),
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
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? AppTheme.primaryColor : Colors.white)
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
                          ? (isDark ? Colors.white : AppTheme.primaryColor)
                          : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tab.label,
                        style: AppTheme.getFontStyle(
                          fontSize: 10.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Colors.white : AppTheme.primaryColor)
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

  Widget _buildActiveTabBody(bool isDark, int totalStaff) {
    switch (_selectedTabIndex) {
      case 1:
        return _buildCategoryTab(isDark, totalStaff);
      case 2:
        return _buildSalaryLookupTab(isDark, totalStaff);
      case 0:
      default:
        return _buildOverviewTab(isDark, totalStaff);
    }
  }

  // ── Tab 0: Overview & Payroll ──────────────────────────────────────────────
  Widget _buildOverviewTab(bool isDark, int totalStaff) {
    final activeStaff = _staff.where((s) => s.isActive).length;
    final activeRate = totalStaff > 0 ? ((activeStaff / totalStaff) * 100).round() : 0;

    final teachers = _staff.where((s) {
      final t = s.staffType.toLowerCase();
      return t.contains('teacher') || t.contains('qari') || t.contains('alim') || t.contains('faculty');
    }).length;

    final admin = _staff.where((s) {
      final t = s.staffType.toLowerCase();
      return t.contains('admin') || t.contains('nazim') || t.contains('principal') || t.contains('manager');
    }).length;

    final office = _staff.where((s) {
      final t = s.staffType.toLowerCase();
      return t.contains('office') || t.contains('account') || t.contains('clerk');
    }).length;

    final support = (totalStaff - teachers - admin - office).clamp(0, totalStaff);

    // Total monthly & yearly payroll
    final totalMonthlyPayroll = _staff
        .where((s) => s.isActive)
        .fold<double>(0.0, (sum, s) => sum + s.salary);
    final totalYearlyPayroll = totalMonthlyPayroll * 12;

    final monthlyStr = _formatCurrency(totalMonthlyPayroll, compact: true);
    final yearlyStr = _formatCurrency(totalYearlyPayroll, compact: true);

    final staffWithExp = _staff.where((s) => s.experienceYears > 0).toList();
    final avgExp = staffWithExp.isNotEmpty
        ? staffWithExp.fold<int>(0, (sum, s) => sum + s.experienceYears) / staffWithExp.length
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── 1. Top KPI Row: Total Staff, Monthly Payroll, Annual Payroll ──
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                label: context.tr('total_staff'),
                value: totalStaff.toString(),
                subValue: totalStaff > 0 ? '$activeRate% ${context.tr('active')}' : '0 ${context.tr('active')}',
                icon: Icons.groups_rounded,
                accentColor: const Color(0xFF2563EB),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                label: context.tr('payroll'),
                value: monthlyStr,
                subValue: context.tr('monthly'),
                icon: Icons.payments_rounded,
                accentColor: const Color(0xFF0D9488),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                label: context.tr('annual_payroll'),
                value: yearlyStr,
                subValue: context.tr('yearly_salary'),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF7C3AED),
                isDark: isDark,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── 2. Department & Role Distribution ──
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    context.tr('dept_role_breakdown'),
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
                  totalStaff > 0 ? '$totalStaff ${context.tr('members')}' : context.tr('no_records_yet'),
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
                child: totalStaff == 0
                    ? Container(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade300)
                    : Row(
                        children: [
                          if (teachers > 0)
                            Expanded(
                              flex: teachers,
                              child: Container(color: const Color(0xFF0D9488)),
                            ),
                          if (admin > 0)
                            Expanded(
                              flex: admin,
                              child: Container(color: const Color(0xFF2563EB)),
                            ),
                          if (office > 0)
                            Expanded(
                              flex: office,
                              child: Container(color: const Color(0xFFF59E0B)),
                            ),
                          if (support > 0)
                            Expanded(
                              flex: support,
                              child: Container(color: const Color(0xFF8B5CF6)),
                            ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 5),

            // Legend Chips
            if (totalStaff == 0)
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
                children: [
                  _buildLegendItem(context.tr('teachers'), teachers, totalStaff, const Color(0xFF0D9488), isDark),
                  _buildLegendItem(context.tr('admin'), admin, totalStaff, const Color(0xFF2563EB), isDark),
                  _buildLegendItem(context.tr('office'), office, totalStaff, const Color(0xFFF59E0B), isDark),
                  if (support > 0)
                    _buildLegendItem(context.tr('support'), support, totalStaff, const Color(0xFF8B5CF6), isDark),
                ],
              ),
          ],
        ),

        const SizedBox(height: 6),

        // ── 3. Bottom Demographics & Quick Link (Customizable Genders) ──
        _buildDemographicsFooter(
          isDark: isDark,
          genderSummaryText: _getGenderDisplayString(_staff, context),
          avgExp: avgExp,
          totalStaff: totalStaff,
        ),
      ],
    );
  }

  // ── Tab 1: By Category ─────────────────────────────────────────────────────
  Widget _buildCategoryTab(bool isDark, int totalStaff) {
    final categories = _getUniqueCategories();
    final effectiveCategory = categories.contains(_selectedCategory) ? _selectedCategory : 'All';

    final filteredStaff = effectiveCategory == 'All'
        ? _staff
        : _staff.where((s) => s.staffType.toLowerCase().trim() == effectiveCategory.toLowerCase().trim()).toList();

    final catTotal = filteredStaff.length;
    final catActive = filteredStaff.where((s) => s.isActive).length;
    final catMonthlyPayroll = filteredStaff.where((s) => s.isActive).fold<double>(0.0, (sum, s) => sum + s.salary);
    final catYearlyPayroll = catMonthlyPayroll * 12;
    final catAvgSalary = catActive > 0 ? catMonthlyPayroll / catActive : 0.0;

    final monthlyStr = _formatCurrency(catMonthlyPayroll, compact: true);
    final yearlyStr = _formatCurrency(catYearlyPayroll, compact: true);
    final avgSalaryStr = _formatCurrency(catAvgSalary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── Category Dropdown Selector ──
        Container(
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
              value: effectiveCategory,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor, size: 20),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              style: AppTheme.getFontStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
              items: categories.map((cat) {
                final count = cat == 'All'
                    ? _staff.length
                    : _staff.where((s) => s.staffType.toLowerCase().trim() == cat.toLowerCase().trim()).length;
                final label = cat == 'All' ? context.tr('all_categories') : cat;
                return DropdownMenuItem<String>(
                  value: cat,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withAlpha(isDark ? 40 : 20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$count',
                          style: AppTheme.getFontStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
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

        const SizedBox(height: 6),

        // ── 3 Category Metric Tiles ──
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                label: context.tr('staff_in_category'),
                value: catTotal.toString(),
                subValue: '$catActive ${context.tr('active')}',
                icon: Icons.person_pin_rounded,
                accentColor: const Color(0xFF2563EB),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                label: context.tr('monthly_payroll'),
                value: monthlyStr,
                subValue: context.tr('monthly'),
                icon: Icons.payments_rounded,
                accentColor: const Color(0xFF0D9488),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                label: context.tr('annual_payroll'),
                value: yearlyStr,
                subValue: context.tr('yearly_salary'),
                icon: Icons.account_balance_wallet_rounded,
                accentColor: const Color(0xFF7C3AED),
                isDark: isDark,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── Category Insights & Demographics Row (Customizable Genders) ──
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
              // Average salary
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on_outlined, size: 14, color: const Color(0xFF0D9488)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${context.tr('avg_salary')}: $avgSalaryStr',
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
              // Category Gender (Customizable)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wc_rounded, size: 14, color: const Color(0xFF2563EB)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        catTotal > 0
                            ? _getGenderDisplayString(filteredStaff, context)
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
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 2: Individual Staff Salary Lookup ───────────────────────────────────
  Widget _buildSalaryLookupTab(bool isDark, int totalStaff) {
    if (_staff.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 30, color: isDark ? Colors.white38 : Colors.grey.shade400),
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

    final effectiveStaffId = (_selectedStaffId != null && _staff.any((s) => s.id == _selectedStaffId))
        ? _selectedStaffId!
        : _staff.first.id;

    final selectedStaff = _staff.firstWhere(
      (s) => s.id == effectiveStaffId,
      orElse: () => _staff.first,
    );

    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final monthlySalaryStr = currencyFormatter.format(selectedStaff.salary);
    final yearlySalaryStr = currencyFormatter.format(selectedStaff.salary * 12);

    final staffGenderStr = (selectedStaff.gender != null && selectedStaff.gender!.trim().isNotEmpty)
        ? _localizeGender(selectedStaff.gender!.trim(), context)
        : '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // ── Staff Dropdown Picker ──
        Container(
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
              value: effectiveStaffId,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor, size: 20),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              onChanged: (val) {
                if (val != null) setState(() => _selectedStaffId = val);
              },
              items: _staff.map((s) {
                return DropdownMenuItem<String>(
                  value: s.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.isActive ? const Color(0xFF10B981) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${s.staffNo} - ${s.fullName} (${s.staffType})',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
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
            ),
          ),
        ),

        const SizedBox(height: 6),

        // ── Profile Header & View Profile Button ──
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryColor.withAlpha(isDark ? 60 : 30),
              child: Text(
                selectedStaff.fullName.isNotEmpty ? selectedStaff.fullName[0].toUpperCase() : 'S',
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
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
                          selectedStaff.fullName,
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
                          color: (selectedStaff.isActive ? const Color(0xFF10B981) : Colors.grey).withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          selectedStaff.isActive ? context.tr('active') : 'Inactive',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: selectedStaff.isActive ? const Color(0xFF10B981) : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${selectedStaff.staffNo} • ${selectedStaff.staffType}',
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
                    builder: (_) => StaffProfileScreen(
                      staffId: selectedStaff.id,
                      onBack: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(isDark ? 40 : 15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryColor.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('view_profile'),
                      style: AppTheme.getFontStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.open_in_new_rounded, size: 11, color: AppTheme.primaryColor),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── Highlight Badges: Monthly Salary & Yearly Salary ──
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF064E3B).withAlpha(120), const Color(0xFF065F46).withAlpha(100)]
                        : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF10B981).withAlpha(isDark ? 60 : 40),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.payments_rounded, size: 13, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            context.tr('monthly_salary'),
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      monthlySalaryStr,
                      style: AppTheme.getFontStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF064E3B),
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF312E81).withAlpha(120), const Color(0xFF3730A3).withAlpha(100)]
                        : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withAlpha(isDark ? 60 : 40),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, size: 13, color: Color(0xFF6366F1)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            context.tr('yearly_salary'),
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF3730A3),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      yearlySalaryStr,
                      style: AppTheme.getFontStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF312E81),
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // ── Staff Demographics & Details Row (Dynamic Custom Gender) ──
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
                child: Text(
                  '${context.tr('gender')}: $staffGenderStr',
                  style: AppTheme.getFontStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${selectedStaff.experienceYears} ${context.tr('years')}',
                  style: AppTheme.getFontStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selectedStaff.mobileNo != null && selectedStaff.mobileNo!.isNotEmpty) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '📱 ${selectedStaff.mobileNo}',
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: accentColor.withAlpha(isDark ? 30 : 15),
        borderRadius: BorderRadius.circular(12),
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
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.getFontStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTheme.getFontStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            subValue,
            style: AppTheme.getFontStyle(
              fontSize: 9,
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
    required double avgExp,
    required int totalStaff,
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
              Icon(
                Icons.wc_rounded,
                size: 13,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
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
                Icon(
                  Icons.work_history_rounded,
                  size: 12,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    totalStaff > 0 && avgExp > 0
                        ? '${avgExp.toStringAsFixed(1)} ${context.tr('years')}'
                        : context.tr('faculty'),
                    style: AppTheme.getFontStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              InkWell(
                onTap: () => widget.onNavigate?.call('staff'),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        totalStaff == 0 ? '+ ${context.tr('add_staff')}' : context.tr('manage_staff'),
                        style: AppTheme.getFontStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 11,
                        color: AppTheme.primaryColor,
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
