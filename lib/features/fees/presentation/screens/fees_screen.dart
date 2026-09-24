import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../bloc/fees_bloc.dart';
import '../../data/models/fee_models.dart';
import '../../data/repositories/fees_repository.dart';
import '../../../../core/services/fee_condition_settings.dart';
import '../../../../core/services/donation_receipt_settings.dart';
import '../../../../core/services/pincode_lookup_service.dart';
import '../widgets/donation_receipt_config_dialog.dart';
import '../../../../core/widgets/app_date_range_picker.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';

class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key});

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String? _selectedClassFilter;
  String _selectedFeeStatusFilter = 'all'; // 'all', 'pending', 'paid'
  int _currentPage = 0;
  int _rowsPerPage = 25;

  // Donation Ledger Filters & Sorting
  String _donationSortMode = 'newest';
  String? _donationCategoryFilter;
  DateTimeRange? _donationDateRange;
  String _donationViewMode = 'donors'; // 'donors' (unique donors) or 'receipts' (all flat receipts)

  // Horizontal scroll controllers for lag-free wide tables
  final ScrollController _studentHorizScrollCtrl = ScrollController();
  final ScrollController _donationsHorizScrollCtrl = ScrollController();

  // ── Performance & Zero-Lag Memoization Cache ───────────────────────────
  bool _filterDueThisMonth = false;
  String get _currentMonthName => DateFormat('MMMM').format(DateTime.now());
  List<StudentFeeSummary>? _cachedRawSummaries;
  String _cachedSearchQuery = '';
  String? _cachedClassFilter;
  String? _cachedFeeStatusFilter;
  bool _cachedFilterDueThisMonth = false;
  List<StudentFeeSummary> _cachedFilteredSummaries = const [];
  List<String> _cachedAvailableClasses = const [];
  int _cachedTotalStudents = 0;
  int _cachedAllCount = 0;
  int _cachedPendingCount = 0;
  int _cachedPaidCount = 0;
  double _cachedTotalExpected = 0.0;
  double _cachedTotalPaid = 0.0;
  double _cachedTotalPending = 0.0;
  int _cachedMonthDueStudents = 0;
  double _cachedMonthDueTotal = 0.0;

  void _updateMemoizedData(FeesLoaded state) {
    if (identical(_cachedRawSummaries, state.summaries) &&
        _cachedSearchQuery == _searchQuery &&
        _cachedClassFilter == _selectedClassFilter &&
        _cachedFilterDueThisMonth == _filterDueThisMonth &&
        _cachedFeeStatusFilter == _selectedFeeStatusFilter) {
      return;
    }

    _cachedRawSummaries = state.summaries;
    _cachedSearchQuery = _searchQuery;
    _cachedClassFilter = _selectedClassFilter;
    _cachedFeeStatusFilter = _selectedFeeStatusFilter;
    _cachedFilterDueThisMonth = _filterDueThisMonth;

    // Available classes (sorted)
    _cachedAvailableClasses = state.summaries
        .map((s) => s.className?.trim())
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();

    // Summary KPI totals & Status Counts (computed once)
    double exp = 0;
    double paid = 0;
    double pend = 0;
    int monthDueCount = 0;
    double monthDueSum = 0;
    int allCount = 0;
    int pendingCount = 0;
    int paidCount = 0;
    final currentMonth = _currentMonthName;

    for (final s in state.summaries) {
      exp += s.totalExpected;
      paid += s.totalPaid;
      pend += s.totalPending;
      allCount++;
      if (s.totalPending > 0) {
        pendingCount++;
      } else {
        paidCount++;
      }

      bool studentHasDue = false;
      for (final h in s.feeHeads) {
        if (h.isDueInMonth(currentMonth) && h.totalPending > 0) {
          studentHasDue = true;
          monthDueSum += h.totalPending;
        }
      }
      if (studentHasDue) monthDueCount++;
    }
    _cachedTotalStudents = state.summaries.length;
    _cachedAllCount = allCount;
    _cachedPendingCount = pendingCount;
    _cachedPaidCount = paidCount;
    _cachedTotalExpected = exp;
    _cachedTotalPaid = paid;
    _cachedTotalPending = pend;
    _cachedMonthDueStudents = monthDueCount;
    _cachedMonthDueTotal = monthDueSum;

    // Filtered summaries (matches student name, father name, surname, class, GR.No, fee types, month alert, and status filter)
    final q = _searchQuery.toLowerCase().trim();
    _cachedFilteredSummaries = state.summaries.where((s) {
      if (_selectedClassFilter != null && _selectedClassFilter != 'All') {
        if ((s.className ?? '').trim() != _selectedClassFilter!.trim()) return false;
      }
      if (_selectedFeeStatusFilter == 'pending') {
        if (s.totalPending <= 0) return false;
      } else if (_selectedFeeStatusFilter == 'paid') {
        if (s.totalPending > 0) return false;
      }
      if (_filterDueThisMonth) {
        final hasMonthDue = s.feeHeads.any((h) => h.isDueInMonth(currentMonth) && h.totalPending > 0);
        if (!hasMonthDue) return false;
      }
      if (q.isNotEmpty) {
        return s.displayName.toLowerCase().contains(q) ||
               (s.className ?? '').toLowerCase().contains(q) ||
               (s.grNo ?? '').toLowerCase().contains(q) ||
               s.feeTypesDisplay.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentPage = 0;
        });
      }
    });
    context.read<FeesBloc>().add(LoadFeesData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _studentHorizScrollCtrl.dispose();
    _donationsHorizScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocListener<FeesBloc, FeesState>(
      listener: (context, state) {
        if (state is FeesLoaded && state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(state.actionMessage!),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 20),
              _buildTabBarContainer(isDark),
              const SizedBox(height: 20),
              Expanded(
                child: BlocBuilder<FeesBloc, FeesState>(
                  builder: (context, state) {
                    if (state is FeesLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is FeesError) {
                      return _buildErrorState(state.message);
                    }
                    if (state is FeesLoaded) {
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildStudentFeesTab(state, isDark),
                          _buildDonationsTab(state, isDark),
                        ],
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('fees'),
            style: AppTheme.getFontStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              letterSpacing: -0.5,
            ),
          ),
          Text(
            'Manage student fees, pending dues, and donations',
            style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Payment History & Receipts
                _buildHeaderAction(Icons.receipt_long_rounded, 'Payment History & Receipts', Colors.teal.shade700, () {
                  _showAllPaymentsSearchDialog();
                }),
                const SizedBox(width: 8),
                // Receipt Settings Button
                _buildHeaderAction(Icons.tune_rounded, 'Receipt Settings', Colors.blueGrey, () {
                  DonationReceiptConfigDialog.show(context, title: 'FEE & DONATION RECEIPT CONFIG');
                }),
                const SizedBox(width: 8),
                // Manage Donation Types
                _buildHeaderAction(Icons.volunteer_activism_rounded, context.tr('donation_types'), Colors.orange, () {
                  final state = context.read<FeesBloc>().state;
                  if (state is FeesLoaded) _showManageDonationTypesDialog(state.donationTypes);
                }),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final state = context.read<FeesBloc>().state;
                    if (state is FeesLoaded) {
                      _showRecordDonationDialog(state.donationTypes);
                    }
                  },
                  icon: const Icon(Icons.favorite_rounded, size: 16),
                  label: Text(context.tr('record_donation'), style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
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
                context.tr('fees'),
                style: AppTheme.getFontStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Manage student fees, pending dues, and donations',
                style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        // Payment History & Receipts
        _buildHeaderAction(Icons.receipt_long_rounded, 'Payment History & Receipts', Colors.teal.shade700, () {
          _showAllPaymentsSearchDialog();
        }),
        const SizedBox(width: 8),
        // Receipt Settings Button
        _buildHeaderAction(Icons.tune_rounded, 'Receipt Settings', Colors.blueGrey, () {
          DonationReceiptConfigDialog.show(context, title: 'FEE & DONATION RECEIPT CONFIG');
        }),
        const SizedBox(width: 8),
        // Manage Donation Types
        _buildHeaderAction(Icons.volunteer_activism_rounded, context.tr('donation_types'), Colors.orange, () {
          final state = context.read<FeesBloc>().state;
          if (state is FeesLoaded) _showManageDonationTypesDialog(state.donationTypes);
        }),
        const SizedBox(width: 8),
        // Record Donation
        FilledButton.icon(
          onPressed: () {
            final state = context.read<FeesBloc>().state;
            if (state is FeesLoaded) {
              _showRecordDonationDialog(state.donationTypes);
            }
          },
          icon: const Icon(Icons.favorite_rounded, size: 16),
          label: Text(context.tr('record_donation'), style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: color.withAlpha(80)),
      ),
    );
  }

  Widget _buildTabBarContainer(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade200),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: AppTheme.primaryColor,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14),
        tabs: [
          Tab(text: context.tr('student_fees')),
          Tab(text: context.tr('donation_ledger')),
        ],
      ),
    );
  }

  // ── FINANCIAL SUMMARY KPI CARDS ─────────────────────────────────
  Widget _buildSummaryCards(FeesLoaded state, bool isDark) {
    _updateMemoizedData(state);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final cardWidth = isNarrow ? double.infinity : (constraints.maxWidth - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStatCard('Total Students', '$_cachedTotalStudents', Icons.groups_rounded, Colors.blue, isDark, cardWidth),
            _buildStatCard('Total Expected', '₹${NumberFormat('#,##,###').format(_cachedTotalExpected)}', Icons.account_balance_wallet_rounded, Colors.indigo, isDark, cardWidth),
            _buildStatCard('Total Collected', '₹${NumberFormat('#,##,###').format(_cachedTotalPaid)}', Icons.check_circle_rounded, Colors.green, isDark, cardWidth),
            _buildStatCard('Pending Dues', '₹${NumberFormat('#,##,###').format(_cachedTotalPending)}', Icons.warning_rounded, Colors.orange.shade800, isDark, cardWidth),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold),
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

  // ── CURRENT MONTH DUE ALERT BANNER ──────────────────────────────
  Widget _buildCurrentMonthDueAlertBanner(bool isDark) {
    if (_cachedMonthDueStudents == 0 && !_filterDueThisMonth) return const SizedBox.shrink();
    final currentMonth = _currentMonthName;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _filterDueThisMonth
            ? Colors.orange.withAlpha(isDark ? 40 : 25)
            : (isDark ? const Color(0xFF241E18) : const Color(0xFFFFFBEB)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _filterDueThisMonth ? Colors.orange : Colors.amber.shade300,
          width: _filterDueThisMonth ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_active_rounded, color: Colors.orange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Month Alert: $currentMonth Fees Due',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.orange.shade200 : const Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_cachedMonthDueStudents Students',
                        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${NumberFormat('#,##,###').format(_cachedMonthDueTotal)} total dues for $currentMonth. Heads scheduled for this month are highlighted with 🔔.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : const Color(0xFF78350F),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                _filterDueThisMonth = !_filterDueThisMonth;
                _currentPage = 0;
              });
            },
            icon: Icon(_filterDueThisMonth ? Icons.close_rounded : Icons.filter_alt_rounded, size: 15),
            label: Text(
              _filterDueThisMonth ? 'Show All Students' : 'View Due Students',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _filterDueThisMonth ? Colors.grey.shade700 : Colors.orange.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ── FEE STATUS SWITCHER BUTTONS ──────────────────────────────
  Widget _buildFeeStatusTabItem(
    String label,
    IconData icon,
    String mode,
    bool isDark,
    Color activeColor, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isSelected = _selectedFeeStatusFilter == mode;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFeeStatusFilter = mode;
          _currentPage = 0;
        });
      },
      borderRadius: BorderRadius.horizontal(
        left: isFirst ? const Radius.circular(7) : Radius.zero,
        right: isLast ? const Radius.circular(7) : Radius.zero,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(7) : Radius.zero,
            right: isLast ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SEARCH & FILTER BAR WITH STATUS TOGGLE ───────────────────────────
  Widget _buildSearchBar(bool isDark, String hint, {List<String>? availableClasses}) {
    final statusSwitcher = Container(
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
        color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFeeStatusTabItem('All ($_cachedAllCount)', Icons.groups_rounded, 'all', isDark, AppTheme.primaryColor, isFirst: true),
          _buildFeeStatusTabItem('Pending Dues ($_cachedPendingCount)', Icons.warning_rounded, 'pending', isDark, Colors.deepOrange),
          _buildFeeStatusTabItem('Fully Paid ($_cachedPaidCount)', Icons.check_circle_rounded, 'paid', isDark, Colors.green, isLast: true),
        ],
      ),
    );

    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: statusSwitcher,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: AppTheme.getFontStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade400),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _searchQuery = '';
                        _currentPage = 0;
                      });
                    },
                  ),
                if (availableClasses != null && availableClasses.isNotEmpty) ...[
                  Container(height: 24, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  DropdownButton<String>(
                    value: _selectedClassFilter ?? 'All',
                    underline: const SizedBox(),
                    isDense: true,
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
                    items: [
                      const DropdownMenuItem(value: 'All', child: Text('All Classes')),
                      ...availableClasses.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedClassFilter = val;
                        _currentPage = 0;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Status Filter Segment
          statusSwitcher,
          const SizedBox(width: 10),
          Container(height: 24, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 2)),
          const SizedBox(width: 8),
          Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppTheme.getFontStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _searchQuery = '';
                  _currentPage = 0;
                });
              },
            ),
          if (availableClasses != null && availableClasses.isNotEmpty) ...[
            Container(height: 24, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 8)),
            Icon(Icons.filter_alt_rounded, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: _selectedClassFilter ?? 'All',
              underline: const SizedBox(),
              isDense: true,
              style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87),
              items: [
                const DropdownMenuItem(value: 'All', child: Text('All Classes')),
                ...availableClasses.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedClassFilter = val;
                  _currentPage = 0;
                });
              },
            ),
          ],
          const SizedBox(width: 8),
          Container(height: 24, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 4)),
          // Fee Conditions shortcut
          Tooltip(
            message: 'Manage Fee Conditions (Edit / Delete / Add)',
            child: InkWell(
              onTap: () async {
                await ManageFeeConditionsDialog.show(context, initialTabIndex: 0);
                if (mounted) context.read<FeesBloc>().add(LoadFeesData());
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD4AF37).withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.tune_rounded, size: 14, color: Color(0xFFD4AF37)),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('fee_conditions'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Fee Types shortcut
          Tooltip(
            message: 'Manage Fee Types (Edit / Delete / Add)',
            child: InkWell(
              onTap: () async {
                await ManageFeeConditionsDialog.show(context, initialTabIndex: 1);
                if (mounted) context.read<FeesBloc>().add(LoadFeesData());
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withAlpha(60)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.category_rounded, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('fee_types'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _searchQuery = val.trim();
          _currentPage = 0;
        });
      }
    });
  }

  // ── PAGINATION CONTROLS ─────────────────────────────────────────
  Widget _buildPaginationBar({
    required int totalItems,
    required int currentPage,
    required int rowsPerPage,
    required ValueChanged<int> onPageChanged,
    required ValueChanged<int> onRowsPerPageChanged,
    required bool isDark,
  }) {
    if (totalItems == 0) return const SizedBox.shrink();

    final totalPages = (totalItems / rowsPerPage).ceil();
    final startItem = (currentPage * rowsPerPage) + 1;
    final endItem = ((currentPage + 1) * rowsPerPage > totalItems) ? totalItems : (currentPage + 1) * rowsPerPage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Showing $startItem - $endItem of $totalItems',
                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 16),
              Text(
                'Rows per page:',
                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: rowsPerPage,
                underline: const SizedBox(),
                isDense: true,
                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15')),
                  DropdownMenuItem(value: 25, child: Text('25')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 100, child: Text('100')),
                ],
                onChanged: (val) {
                  if (val != null) onRowsPerPageChanged(val);
                },
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page_rounded, size: 20),
                tooltip: 'First Page',
                onPressed: currentPage > 0 ? () => onPageChanged(0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                tooltip: 'Previous Page',
                onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Page ${currentPage + 1} of ${totalPages > 0 ? totalPages : 1}',
                  style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                tooltip: 'Next Page',
                onPressed: currentPage < totalPages - 1 ? () => onPageChanged(currentPage + 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page_rounded, size: 20),
                tooltip: 'Last Page',
                onPressed: currentPage < totalPages - 1 ? () => onPageChanged(totalPages - 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TABLE HEADER CELL HELPER ────────────────────────────────────
  Widget _buildTableHeaderCell(String title, {required double width, Alignment alignment = Alignment.centerLeft}) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: alignment,
        child: Text(
          title.toUpperCase(),
          style: AppTheme.getFontStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
            letterSpacing: 0.5,
            color: Colors.grey.shade600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  static String _formatFeeDiscountBadge(double disc, double? orig, String? tag) {
    if (tag != null && tag.isNotEmpty && tag.contains('%')) return tag;
    final baseAmt = (orig != null && orig > 0) ? orig : 0.0;
    if (baseAmt > 0 && disc > 0) {
      final pct = (disc / baseAmt) * 100.0;
      String pctStr = pct.toStringAsFixed(pct < 1 ? 2 : 1);
      if (pct == pct.truncateToDouble()) {
        pctStr = '${pct.toInt()}%';
      } else if (pctStr.contains('.')) {
        pctStr = '${pctStr.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}%';
      } else {
        pctStr = '$pctStr%';
      }
      if (tag != null && tag.isNotEmpty) return '$tag ($pctStr)';
      return '-₹${disc.toStringAsFixed(0)} ($pctStr)';
    }
    if (tag != null && tag.isNotEmpty) return tag;
    return '-₹${disc.toStringAsFixed(0)}';
  }

  // ── FEE TYPES CHIP CELL ─────────────────────────────────────────
  Widget _buildFeeTypesCell(StudentFeeSummary s) {
    if (s.feeHeads.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withAlpha(15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Tuition Fee',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final displayHeads = s.feeHeads.take(4).toList();
    final remainingCount = s.feeHeads.length - displayHeads.length;

    return Center(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 5,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...displayHeads.map((h) {
              final isPaid = h.totalPending <= 0 && h.totalExpected > 0;
              final hasDisc = h.discountAmount != null && h.discountAmount! > 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isPaid ? Colors.green.withAlpha(15) : AppTheme.primaryColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isPaid ? Colors.green.withAlpha(50) : AppTheme.primaryColor.withAlpha(40),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${h.feeTypeName}${h.amount > 0 ? ': ₹${h.amount.toStringAsFixed(0)}' : ''}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isPaid ? Colors.green.shade800 : AppTheme.primaryColor,
                      ),
                    ),
                    if (h.isDueInMonth(_currentMonthName) && h.totalPending > 0) ...[
                      const SizedBox(width: 3),
                      Tooltip(
                        message: 'Due in $_currentMonthName (${h.monthsDisplay})',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_active_rounded, size: 8.5, color: Colors.orange.shade900),
                              const SizedBox(width: 1),
                              Text(
                                'Due',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (hasDisc) ...[
                      const SizedBox(width: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          _formatFeeDiscountBadge(h.discountAmount!, h.originalAmount, h.discountTag),
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (remainingCount > 0)
              Tooltip(
                message: s.feeHeads.map((h) {
                  final discText = (h.discountAmount != null && h.discountAmount! > 0)
                      ? ' [Disc: ${_formatFeeDiscountBadge(h.discountAmount!, h.originalAmount, h.discountTag)}]'
                      : '';
                  return '${h.feeTypeName}: ₹${h.amount.toStringAsFixed(0)}$discText (${h.billingType}) - Due: ₹${h.totalPending.toStringAsFixed(0)}';
                }).join('\n'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade400, width: 0.8),
                  ),
                  child: Text(
                    '+$remainingCount',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── STUDENT FEES TAB (VIRTUALIZED & LAG-FREE) ───────────────────
  Widget _buildStudentFeesTab(FeesLoaded state, bool isDark) {
    _updateMemoizedData(state);

    final filtered = _cachedFilteredSummaries;
    final totalCount = filtered.length;
    final totalPages = (totalCount / _rowsPerPage).ceil();
    final safePage = totalPages > 0 ? _currentPage.clamp(0, totalPages - 1) : 0;
    final startIndex = safePage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage > totalCount) ? totalCount : startIndex + _rowsPerPage;
    final pageItems = (startIndex < totalCount) ? filtered.sublist(startIndex, endIndex) : <StudentFeeSummary>[];

    String emptyMsg = 'No student fee records found.';
    if (_selectedFeeStatusFilter == 'pending') {
      emptyMsg = 'No students with pending balance.';
    } else if (_selectedFeeStatusFilter == 'paid') {
      emptyMsg = 'No students with fully paid fees found.';
    }

    return Column(
      children: [
        _buildSummaryCards(state, isDark),
        const SizedBox(height: 12),
        _buildCurrentMonthDueAlertBanner(isDark),
        _buildSearchBar(isDark, context.tr('search_students_fees_hint'), availableClasses: _cachedAvailableClasses),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(emptyMsg)
              : Column(
                  children: [
                    Expanded(
                      child: _buildStudentFeesVirtualizedTable(
                        items: pageItems,
                        startIndex: startIndex,
                        state: state,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPaginationBar(
                      totalItems: totalCount,
                      currentPage: safePage,
                      rowsPerPage: _rowsPerPage,
                      onPageChanged: (p) => setState(() => _currentPage = p),
                      onRowsPerPageChanged: (r) => setState(() {
                        _rowsPerPage = r;
                        _currentPage = 0;
                      }),
                      isDark: isDark,
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ── VIRTUALIZED STUDENT FEES TABLE ──────────────────────────────
  Widget _buildStudentFeesVirtualizedTable({
    required List<StudentFeeSummary> items,
    required int startIndex,
    required FeesLoaded state,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Generous minimum width for narrow screens so content doesn't truncate
        const double minWidth = 1460.0;
        final effectiveWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
        final availableWidth = effectiveWidth - 32.0; // 16px horizontal padding on both sides

        // Compact/Fixed width columns (Index, GR No, Class, Actions)
        const double colIndex = 48.0;
        const double colGrNo = 100.0;
        const double colClass = 105.0;
        const double colActions = 125.0;
        const double fixedTotal = colIndex + colGrNo + colClass + colActions; // 378.0

        // Flexible columns distributed proportionally across remaining width:
        // Name, Fee Type, Monthly Fee, Total Expected, Paid, Pending
        const double baseName = 230.0;
        const double baseFeeType = 360.0; // Increased base width so fee badges never cramp
        const double baseMonthlyFee = 115.0;
        const double baseTotalExpected = 135.0;
        const double basePaid = 105.0;
        const double basePending = 115.0;
        const double baseFlexTotal = baseName + baseFeeType + baseMonthlyFee + baseTotalExpected + basePaid + basePending; // 1060.0

        final flexibleWidth = availableWidth - fixedTotal;
        final flexRatio = math.max(1.0, flexibleWidth / baseFlexTotal);

        final colName = baseName * flexRatio;
        final colFeeType = baseFeeType * flexRatio;
        final colMonthlyFee = baseMonthlyFee * flexRatio;
        final colTotalExpected = baseTotalExpected * flexRatio;
        final colPaid = basePaid * flexRatio;
        // Remaining exact width allocated to Pending dues column to guarantee zero rounding gap
        final colPending = flexibleWidth - (colName + colFeeType + colMonthlyFee + colTotalExpected + colPaid);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: Scrollbar(
                controller: _studentHorizScrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _studentHorizScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    width: effectiveWidth,
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          height: 46,
                          color: isDark ? const Color(0xFF2A2A3E) : AppTheme.primaryColor.withAlpha(12),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildTableHeaderCell('#', width: colIndex),
                              _buildTableHeaderCell(context.tr('gr_no'), width: colGrNo),
                              _buildTableHeaderCell(context.tr('name'), width: colName),
                              _buildTableHeaderCell(context.tr('class'), width: colClass),
                              _buildTableHeaderCell('Fee Type', width: colFeeType),
                              _buildTableHeaderCell('Monthly Fee', width: colMonthlyFee),
                              _buildTableHeaderCell('Total Expected', width: colTotalExpected),
                              _buildTableHeaderCell('Paid', width: colPaid),
                              _buildTableHeaderCell('Pending', width: colPending),
                              _buildTableHeaderCell(context.tr('actions'), width: colActions, alignment: Alignment.center),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                        // Virtualized Rows
                        Expanded(
                          child: ListView.separated(
                            key: const PageStorageKey<String>('fees_student_virtualized_list'),
                            itemCount: items.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark ? Colors.white.withAlpha(6) : Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final s = items[index];
                              final isOdd = index.isOdd;
                              return Container(
                                height: 56,
                                color: isOdd
                                    ? (isDark ? Colors.white.withAlpha(3) : Colors.grey.shade50)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    // #
                                    SizedBox(
                                      width: colIndex,
                                      child: Text(
                                        '${startIndex + index + 1}',
                                        style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ),
                                    // GR.No
                                    SizedBox(
                                      width: colGrNo,
                                      child: Text(
                                        s.grNo ?? '-',
                                        style: AppTheme.getFontStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Full Name: Student Name + Father Name + Surname ek sath!
                                    SizedBox(
                                      width: colName,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: AppTheme.primaryColor.withAlpha(20),
                                            child: Text(
                                              s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : 'S',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  s.displayName,
                                                  style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                                if (s.mobileNo != null && s.mobileNo!.isNotEmpty)
                                                  Text(
                                                    s.mobileNo!,
                                                    style: AppTheme.getFontStyle(fontSize: 10.5, color: Colors.grey.shade500),
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Class
                                    SizedBox(
                                      width: colClass,
                                      child: Text(
                                        s.className ?? '-',
                                        style: AppTheme.getFontStyle(fontSize: 12.5),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // Fee Type(s)
                                    SizedBox(
                                      width: colFeeType,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: ClipRect(
                                          child: _buildFeeTypesCell(s),
                                        ),
                                      ),
                                    ),
                                    // Monthly Fee
                                    SizedBox(
                                      width: colMonthlyFee,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          s.monthlyFees > 0 ? '₹${s.monthlyFees.toStringAsFixed(0)}' : '-',
                                          style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ),
                                    // Total Expected
                                    SizedBox(
                                      width: colTotalExpected,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '₹${s.totalExpected.toStringAsFixed(0)}',
                                            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                          ),
                                          if (s.totalDiscount > 0)
                                            Container(
                                              margin: const EdgeInsets.only(top: 2),
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                _formatFeeDiscountBadge(s.totalDiscount, s.totalExpected + s.totalDiscount, ''),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red.shade700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Paid
                                    SizedBox(
                                      width: colPaid,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withAlpha(15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '₹${s.totalPaid.toStringAsFixed(0)}',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Pending
                                    SizedBox(
                                      width: colPending,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: s.totalPending > 0
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withAlpha(15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '₹${s.totalPending.toStringAsFixed(0)}',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              )
                                            : Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.withAlpha(15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.check_circle_rounded, size: 12, color: Colors.green.shade700),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Cleared',
                                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                    ),
                                    // Actions
                                    SizedBox(
                                      width: colActions,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.history_rounded, size: 18, color: Colors.blue),
                                            tooltip: context.tr('payment_history'),
                                            onPressed: () => _showPaymentHistoryDialog(s),
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: Icon(Icons.payment_rounded, size: 18, color: AppTheme.primaryColor),
                                            tooltip: context.tr('pay_fee'),
                                            onPressed: () => _showPayFeeDialog(s, state.feeTypes),
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: const Icon(Icons.receipt_long_rounded, size: 18, color: Colors.deepOrange),
                                            tooltip: context.tr('generate_receipt'),
                                            onPressed: () => _showGenerateReceiptDialog(s),
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── DONATIONS TAB (VIRTUALIZED & ADVANCED FILTERING) ───────────────
  Widget _buildDonationsTab(FeesLoaded state, bool isDark) {
    // 1. Group raw donations into unique DonorSummary objects
    final allDonors = DonorSummary.groupDonationsByDonor(state.donations);

    // 2. Compute Top Summary Metrics
    final totalCollected = state.donations.fold<double>(0.0, (sum, d) => sum + d.amount);
    final totalCount = state.donations.length;
    final uniqueDonorsCount = allDonors.length;
    final highestSingle = state.donations.isEmpty
        ? 0.0
        : state.donations.map((d) => d.amount).fold<double>(0.0, (prev, amt) => amt > prev ? amt : prev);

    if (_donationViewMode == 'donors') {
      // ─── UNIQUE DONORS VIEW (Default) ───────────────────────────
      List<DonorSummary> filteredDonors = List.of(allDonors);

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        filteredDonors = filteredDonors.where((donor) {
          final nameMatch = donor.donorName.toLowerCase().contains(q);
          final phoneMatch = (donor.donorPhone ?? '').toLowerCase().contains(q);
          final villageMatch = (donor.village ?? '').toLowerCase().contains(q);
          final talukaMatch = (donor.taluka ?? '').toLowerCase().contains(q);
          final distMatch = (donor.district ?? '').toLowerCase().contains(q);
          final stateMatch = (donor.state ?? '').toLowerCase().contains(q);
          final rcptMatch = donor.donations.any((d) =>
              (d.receiptNo ?? '').toLowerCase().contains(q) ||
              d.displayReceiptNo.toLowerCase().contains(q));
          final typeMatch = donor.donations.any((d) => d.donationType.toLowerCase().contains(q));
          return nameMatch || phoneMatch || villageMatch || talukaMatch || distMatch || stateMatch || rcptMatch || typeMatch;
        }).toList();
      }

      // Category filter
      if (_donationCategoryFilter != null && _donationCategoryFilter != 'All') {
        final cat = _donationCategoryFilter!.toLowerCase();
        filteredDonors = filteredDonors.where((donor) {
          return donor.donations.any((d) => d.donationType.toLowerCase() == cat);
        }).toList();
      }

      // Date range filter
      if (_donationDateRange != null) {
        final start = DateTime(_donationDateRange!.start.year, _donationDateRange!.start.month, _donationDateRange!.start.day);
        final end = DateTime(_donationDateRange!.end.year, _donationDateRange!.end.month, _donationDateRange!.end.day);
        filteredDonors = filteredDonors.where((donor) {
          return donor.donations.any((d) {
            if (d.paymentDate == null) return false;
            final dt = DateTime.tryParse(d.paymentDate!);
            if (dt == null) return false;
            final dOnly = DateTime(dt.year, dt.month, dt.day);
            return !dOnly.isBefore(start) && !dOnly.isAfter(end);
          });
        }).toList();
      }

      // Sorting
      if (_donationSortMode == 'highest') {
        filteredDonors.sort((a, b) => b.totalDonated.compareTo(a.totalDonated));
      } else if (_donationSortMode == 'lowest') {
        filteredDonors.sort((a, b) => a.totalDonated.compareTo(b.totalDonated));
      } else if (_donationSortMode == 'oldest') {
        filteredDonors.sort((a, b) {
          final da = a.latestDonation.paymentDate != null ? DateTime.tryParse(a.latestDonation.paymentDate!) : null;
          final db = b.latestDonation.paymentDate != null ? DateTime.tryParse(b.latestDonation.paymentDate!) : null;
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
      } else if (_donationSortMode == 'top_donors') {
        filteredDonors.sort((a, b) => b.totalDonated.compareTo(a.totalDonated));
        if (filteredDonors.length > 10) filteredDonors = filteredDonors.sublist(0, 10);
      } else if (_donationSortMode == 'name') {
        filteredDonors.sort((a, b) => a.donorName.toLowerCase().compareTo(b.donorName.toLowerCase()));
      } else {
        // Default: newest contribution first
        filteredDonors.sort((a, b) {
          final da = a.latestDonation.paymentDate != null ? DateTime.tryParse(a.latestDonation.paymentDate!) : null;
          final db = b.latestDonation.paymentDate != null ? DateTime.tryParse(b.latestDonation.paymentDate!) : null;
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
      }

      final totalFilteredCount = filteredDonors.length;
      final totalPages = (totalFilteredCount / _rowsPerPage).ceil();
      final safePage = totalPages > 0 ? _currentPage.clamp(0, totalPages - 1) : 0;
      final startIndex = safePage * _rowsPerPage;
      final endIndex = (startIndex + _rowsPerPage > totalFilteredCount) ? totalFilteredCount : startIndex + _rowsPerPage;
      final pageDonors = (startIndex < totalFilteredCount) ? filteredDonors.sublist(startIndex, endIndex) : <DonorSummary>[];

      return Column(
        children: [
          // Top 4 Donation Summary Metric Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final cardWidth = isNarrow ? double.infinity : (constraints.maxWidth - 36) / 4;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCard('Total Collected', '₹${NumberFormat('#,##,###').format(totalCollected)}', Icons.volunteer_activism_rounded, Colors.green, isDark, cardWidth),
                  _buildStatCard('Total Receipts', '$totalCount Receipts', Icons.receipt_long_rounded, Colors.blue, isDark, cardWidth),
                  _buildStatCard('Unique Donors', '$uniqueDonorsCount Donors', Icons.people_alt_rounded, Colors.purple, isDark, cardWidth),
                  _buildStatCard('Highest Donation', '₹${NumberFormat('#,##,###').format(highestSingle)}', Icons.star_rounded, Colors.amber.shade800, isDark, cardWidth),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Search & Filter Toolbar
          _buildDonationFilterToolbar(
            state,
            isDark,
            uniqueDonorsCount: uniqueDonorsCount,
            totalReceiptsCount: totalCount,
          ),
          const SizedBox(height: 12),

          // Table
          Expanded(
            child: filteredDonors.isEmpty
                ? _buildEmptyState('No donors found matching criteria.')
                : Column(
                    children: [
                      Expanded(
                        child: _buildDonorsVirtualizedTable(
                          items: pageDonors,
                          state: state,
                          isDark: isDark,
                        ),
                      ),
                      if (totalFilteredCount > _rowsPerPage) ...[
                        const SizedBox(height: 8),
                        _buildPaginationBar(
                          totalItems: totalFilteredCount,
                          currentPage: safePage,
                          rowsPerPage: _rowsPerPage,
                          onPageChanged: (p) => setState(() => _currentPage = p),
                          onRowsPerPageChanged: (r) => setState(() {
                            _rowsPerPage = r;
                            _currentPage = 0;
                          }),
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      );
    } else {
      // ─── ALL RECEIPTS VIEW (Flat Raw Receipts Ledger) ───────────
      List<Donation> filtered = List.of(state.donations);

      // Text search filter across all fields
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        filtered = filtered.where((d) {
          return (d.donorName ?? '').toLowerCase().contains(q) ||
                 (d.donorPhone ?? '').toLowerCase().contains(q) ||
                 (d.receiptNo ?? '').toLowerCase().contains(q) ||
                 d.displayReceiptNo.toLowerCase().contains(q) ||
                 (d.village ?? '').toLowerCase().contains(q) ||
                 (d.taluka ?? '').toLowerCase().contains(q) ||
                 (d.district ?? '').toLowerCase().contains(q) ||
                 (d.state ?? '').toLowerCase().contains(q) ||
                 (d.country ?? '').toLowerCase().contains(q) ||
                 d.donationType.toLowerCase().contains(q) ||
                 d.paymentMethod.toLowerCase().contains(q);
        }).toList();
      }

      // Category filter
      if (_donationCategoryFilter != null && _donationCategoryFilter != 'All') {
        filtered = filtered.where((d) => d.donationType.toLowerCase() == _donationCategoryFilter!.toLowerCase()).toList();
      }

      // Date range filter
      if (_donationDateRange != null) {
        filtered = filtered.where((d) {
          if (d.paymentDate == null) return false;
          final dt = DateTime.tryParse(d.paymentDate!);
          if (dt == null) return false;
          final dateOnly = DateTime(dt.year, dt.month, dt.day);
          final start = DateTime(_donationDateRange!.start.year, _donationDateRange!.start.month, _donationDateRange!.start.day);
          final end = DateTime(_donationDateRange!.end.year, _donationDateRange!.end.month, _donationDateRange!.end.day);
          return !dateOnly.isBefore(start) && !dateOnly.isAfter(end);
        }).toList();
      }

      // Sorting & Ranking
      if (_donationSortMode == 'highest') {
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
      } else if (_donationSortMode == 'lowest') {
        filtered.sort((a, b) => a.amount.compareTo(b.amount));
      } else if (_donationSortMode == 'oldest') {
        filtered.sort((a, b) {
          final da = a.paymentDate != null ? DateTime.tryParse(a.paymentDate!) : null;
          final db = b.paymentDate != null ? DateTime.tryParse(b.paymentDate!) : null;
          if (da == null || db == null) return 0;
          return da.compareTo(db);
        });
      } else if (_donationSortMode == 'top_donations') {
        filtered.sort((a, b) => b.amount.compareTo(a.amount));
        if (filtered.length > 10) filtered = filtered.sublist(0, 10);
      } else if (_donationSortMode == 'name') {
        filtered.sort((a, b) => (a.donorName ?? '').toLowerCase().compareTo((b.donorName ?? '').toLowerCase()));
      } else {
        // Default: newest first
        filtered.sort((a, b) {
          final da = a.paymentDate != null ? DateTime.tryParse(a.paymentDate!) : null;
          final db = b.paymentDate != null ? DateTime.tryParse(b.paymentDate!) : null;
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
      }

      final totalFilteredCount = filtered.length;
      final totalPages = (totalFilteredCount / _rowsPerPage).ceil();
      final safePage = totalPages > 0 ? _currentPage.clamp(0, totalPages - 1) : 0;
      final startIndex = safePage * _rowsPerPage;
      final endIndex = (startIndex + _rowsPerPage > totalFilteredCount) ? totalFilteredCount : startIndex + _rowsPerPage;
      final pageItems = (startIndex < totalFilteredCount) ? filtered.sublist(startIndex, endIndex) : <Donation>[];

      return Column(
        children: [
          // Top 4 Donation Summary Metric Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              final cardWidth = isNarrow ? double.infinity : (constraints.maxWidth - 36) / 4;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCard('Total Collected', '₹${NumberFormat('#,##,###').format(totalCollected)}', Icons.volunteer_activism_rounded, Colors.green, isDark, cardWidth),
                  _buildStatCard('Total Receipts', '$totalCount Receipts', Icons.receipt_long_rounded, Colors.blue, isDark, cardWidth),
                  _buildStatCard('Unique Donors', '$uniqueDonorsCount Donors', Icons.people_alt_rounded, Colors.purple, isDark, cardWidth),
                  _buildStatCard('Highest Donation', '₹${NumberFormat('#,##,###').format(highestSingle)}', Icons.star_rounded, Colors.amber.shade800, isDark, cardWidth),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Search & Filter Toolbar
          _buildDonationFilterToolbar(
            state,
            isDark,
            uniqueDonorsCount: uniqueDonorsCount,
            totalReceiptsCount: totalCount,
          ),
          const SizedBox(height: 12),

          // Table
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState('No donation records found matching criteria.')
                : Column(
                    children: [
                      Expanded(
                        child: _buildDonationsVirtualizedTable(
                          items: pageItems,
                          isDark: isDark,
                        ),
                      ),
                      if (totalFilteredCount > _rowsPerPage) ...[
                        const SizedBox(height: 8),
                        _buildPaginationBar(
                          totalItems: totalFilteredCount,
                          currentPage: safePage,
                          rowsPerPage: _rowsPerPage,
                          onPageChanged: (p) => setState(() => _currentPage = p),
                          onRowsPerPageChanged: (r) => setState(() {
                            _rowsPerPage = r;
                            _currentPage = 0;
                          }),
                          isDark: isDark,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      );
    }
  }

  // ── DONATIONS SEARCH & FILTER TOOLBAR ──────────────────────────────
  Widget _buildDonationFilterToolbar(
    FeesLoaded state,
    bool isDark, {
    int uniqueDonorsCount = 0,
    int totalReceiptsCount = 0,
  }) {
    final categories = ['All', ...state.donationTypes.map((t) => t.name)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // View Switcher (Donors vs All Receipts)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _donationViewMode = 'donors';
                    _currentPage = 0;
                  }),
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _donationViewMode == 'donors' ? AppTheme.primaryColor : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.people_alt_rounded,
                          size: 14,
                          color: _donationViewMode == 'donors' ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Donors ($uniqueDonorsCount)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _donationViewMode == 'donors' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() {
                    _donationViewMode = 'receipts';
                    _currentPage = 0;
                  }),
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _donationViewMode == 'receipts' ? AppTheme.primaryColor : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 14,
                          color: _donationViewMode == 'receipts' ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'All Receipts ($totalReceiptsCount)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _donationViewMode == 'receipts' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search input field
          SizedBox(
            width: 250,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                  setState(() {
                    _searchQuery = val;
                    _currentPage = 0;
                  });
                });
              },
              decoration: InputDecoration(
                hintText: _donationViewMode == 'donors' ? 'Search donor, phone, village...' : 'Search receipt, donor, city...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchQuery = '';
                            _currentPage = 0;
                          });
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
              ),
              style: AppTheme.getFontStyle(fontSize: 12.5),
            ),
          ),

          // Sort & Rank Filter Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _donationSortMode,
                isDense: true,
                dropdownColor: isDark ? const Color(0xFF262638) : Colors.white,
                items: const [
                  DropdownMenuItem(value: 'newest', child: Text('⏱ Newest First', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'oldest', child: Text('⏳ Oldest First', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'highest', child: Text('⬆ Highest Amount', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'lowest', child: Text('⬇ Lowest Amount', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'name', child: Text('🔤 Donor Name (A-Z)', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'top_donors', child: Text('🏆 Top 10 Donors', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'top_donations', child: Text('💎 Top 10 Single Donations', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _donationSortMode = val;
                      _currentPage = 0;
                    });
                  }
                },
              ),
            ),
          ),

          // Category Filter Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _donationCategoryFilter ?? 'All',
                isDense: true,
                dropdownColor: isDark ? const Color(0xFF262638) : Colors.white,
                items: categories.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(cat == 'All' ? '📂 All Categories' : '🏷 $cat', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _donationCategoryFilter = (val == 'All') ? null : val;
                    _currentPage = 0;
                  });
                },
              ),
            ),
          ),

          // Date Range Picker Button
          OutlinedButton.icon(
            icon: Icon(
              Icons.date_range_rounded,
              size: 15,
              color: _donationDateRange != null ? AppTheme.primaryColor : Colors.grey.shade600,
            ),
            label: Text(
              _donationDateRange != null
                  ? '${DateFormat('dd MMM').format(_donationDateRange!.start)} - ${DateFormat('dd MMM').format(_donationDateRange!.end)}'
                  : 'Date Range',
              style: TextStyle(
                fontSize: 12,
                fontWeight: _donationDateRange != null ? FontWeight.bold : FontWeight.normal,
                color: _donationDateRange != null ? AppTheme.primaryColor : null,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              side: BorderSide(
                color: _donationDateRange != null ? AppTheme.primaryColor : (isDark ? Colors.white12 : Colors.grey.shade300),
              ),
            ),
            onPressed: () async {
              final picked = await AppDateRangePicker.show(
                context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                initialDateRange: _donationDateRange,
                title: 'Donation Date Filter',
              );
              if (picked != null) {
                setState(() {
                  _donationDateRange = picked;
                  _currentPage = 0;
                });
              }
            },
          ),
          if (_donationDateRange != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              tooltip: 'Clear Date Filter',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => setState(() {
                _donationDateRange = null;
                _currentPage = 0;
              }),
            ),
        ],
      ),
    );
  }

  // ── VIRTUALIZED UNIQUE DONORS TABLE ─────────────────────────────
  Widget _buildDonorsVirtualizedTable({
    required List<DonorSummary> items,
    required FeesLoaded state,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minWidth = 1420.0;
        final effectiveWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
        final availableWidth = effectiveWidth - 32.0;

        // Fixed/compact columns
        const double colIndex = 48.0;
        const double colMobile = 125.0;
        const double colState = 115.0;
        const double colDonations = 110.0;
        const double colActions = 130.0;
        const double fixedTotal = colIndex + colMobile + colState + colDonations + colActions; // 528.0

        // Flexible columns
        const double baseName = 240.0;
        const double baseVillage = 140.0;
        const double baseTaluka = 160.0;
        const double baseTotalDonated = 140.0;
        const double baseLastDonation = 170.0;
        const double baseFlexTotal = baseName + baseVillage + baseTaluka + baseTotalDonated + baseLastDonation; // 850.0

        final flexibleWidth = availableWidth - fixedTotal;
        final flexRatio = math.max(1.0, flexibleWidth / baseFlexTotal);

        final colName = baseName * flexRatio;
        final colVillage = baseVillage * flexRatio;
        final colTaluka = baseTaluka * flexRatio;
        final colTotalDonated = baseTotalDonated * flexRatio;
        final colLastDonation = flexibleWidth - (colName + colVillage + colTaluka + colTotalDonated);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: Scrollbar(
                controller: _donationsHorizScrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _donationsHorizScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    width: effectiveWidth,
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          height: 46,
                          color: isDark ? const Color(0xFF2A2A3E) : Colors.indigo.withAlpha(12),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildTableHeaderCell('#', width: colIndex),
                              _buildTableHeaderCell('Donor Name', width: colName),
                              _buildTableHeaderCell('Mobile', width: colMobile),
                              _buildTableHeaderCell('Village', width: colVillage),
                              _buildTableHeaderCell('Taluka / District', width: colTaluka),
                              _buildTableHeaderCell('State', width: colState),
                              _buildTableHeaderCell('Total Donated', width: colTotalDonated),
                              _buildTableHeaderCell('Donations', width: colDonations),
                              _buildTableHeaderCell('Last Donation', width: colLastDonation),
                              _buildTableHeaderCell('Actions', width: colActions, alignment: Alignment.center),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                        // Virtualized Rows
                        Expanded(
                          child: ListView.separated(
                            key: const PageStorageKey<String>('fees_donors_unique_virtualized_list'),
                            itemCount: items.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark ? Colors.white.withAlpha(6) : Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final donor = items[index];
                              final isOdd = index.isOdd;
                              final latest = donor.latestDonation;
                              final dateStr = latest.paymentDate != null
                                  ? DateFormat('dd MMM yyyy').format(DateTime.tryParse(latest.paymentDate!) ?? DateTime.now())
                                  : '-';

                              return Container(
                                height: 56,
                                color: isOdd
                                    ? (isDark ? Colors.white.withAlpha(3) : Colors.grey.shade50)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    // 1. # Index
                                    SizedBox(
                                      width: colIndex,
                                      child: Text(
                                        '${(_currentPage * _rowsPerPage) + index + 1}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ),
                                    // 2. Donor Name
                                    SizedBox(
                                      width: colName,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: Colors.green.withAlpha(25),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                donor.donorName.isNotEmpty ? donor.donorName[0].toUpperCase() : 'D',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  donor.donorName,
                                                  style: AppTheme.getFontStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  'Latest Rec: #${latest.displayReceiptNo}',
                                                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 3. Mobile
                                    SizedBox(
                                      width: colMobile,
                                      child: Text(
                                        donor.displayPhone,
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 4. Village
                                    SizedBox(
                                      width: colVillage,
                                      child: Text(
                                        donor.village?.trim().isNotEmpty == true ? donor.village!.trim() : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 5. Taluka / District
                                    SizedBox(
                                      width: colTaluka,
                                      child: Text(
                                        [donor.taluka, donor.district].where((p) => p != null && p.trim().isNotEmpty).join(', ').isNotEmpty
                                            ? [donor.taluka, donor.district].where((p) => p != null && p.trim().isNotEmpty).join(', ')
                                            : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 6. State
                                    SizedBox(
                                      width: colState,
                                      child: Text(
                                        donor.state?.trim().isNotEmpty == true ? donor.state!.trim() : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 7. Total Donated
                                    SizedBox(
                                      width: colTotalDonated,
                                      child: Text(
                                        '₹${NumberFormat('#,##,###').format(donor.totalDonated)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                    // 8. Donations Count
                                    SizedBox(
                                      width: colDonations,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor.withAlpha(20),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${donor.totalCount} ${donor.totalCount == 1 ? "Donation" : "Donations"}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // 9. Last Donation
                                    SizedBox(
                                      width: colLastDonation,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            dateStr,
                                            style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.withAlpha(15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              latest.donationType,
                                              style: TextStyle(fontSize: 10, color: Colors.teal.shade800, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 10. Actions
                                    SizedBox(
                                      width: colActions,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          // History Button
                                          IconButton(
                                            icon: const Icon(Icons.history_rounded, size: 19, color: Colors.blue),
                                            tooltip: 'Payment History',
                                            onPressed: () => _showDonorPaymentHistoryDialog(donor),
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                          const SizedBox(width: 4),
                                          // Pay / Add Donation Button
                                          IconButton(
                                            icon: Icon(Icons.payment_rounded, size: 19, color: AppTheme.primaryColor),
                                            tooltip: 'Pay / Add Donation',
                                            onPressed: () => _showRecordDonationDialog(state.donationTypes, prefillDonor: donor),
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                          const SizedBox(width: 4),
                                          // Print Latest Receipt Button
                                          IconButton(
                                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 19, color: Colors.red),
                                            tooltip: 'Print Latest Receipt',
                                            onPressed: () {
                                              ReceiptPdfGenerator.printDonationReceipt(
                                                receiptNo: latest.displayReceiptNo,
                                                donorName: latest.donorName,
                                                donorPhone: latest.donorPhone,
                                                village: latest.village,
                                                taluka: latest.taluka,
                                                district: latest.district,
                                                state: latest.state,
                                                country: latest.country,
                                                pinCode: latest.pinCode,
                                                amount: latest.amount,
                                                donationType: latest.donationType,
                                                paymentMethod: latest.paymentMethod,
                                                date: latest.paymentDate ?? DateTime.now().toIso8601String(),
                                              );
                                            },
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── VIRTUALIZED DONATIONS TABLE ─────────────────────────────────
  Widget _buildDonationsVirtualizedTable({
    required List<Donation> items,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minWidth = 1460.0;
        final effectiveWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
        final availableWidth = effectiveWidth - 32.0;

        // Fixed/compact columns
        const double colCountry = 90.0;
        const double colCategory = 120.0;
        const double colAmount = 110.0;
        const double colMethod = 120.0;
        const double colDate = 120.0;
        const double colActions = 90.0;
        const double fixedTotal = colCountry + colCategory + colAmount + colMethod + colDate + colActions; // 650.0

        // Flexible columns
        const double baseReceiptNo = 130.0;
        const double baseName = 190.0;
        const double baseVillage = 130.0;
        const double baseTaluka = 120.0;
        const double baseDistrict = 120.0;
        const double baseState = 120.0;
        const double baseFlexTotal = baseReceiptNo + baseName + baseVillage + baseTaluka + baseDistrict + baseState; // 810.0

        final flexibleWidth = availableWidth - fixedTotal;
        final flexRatio = math.max(1.0, flexibleWidth / baseFlexTotal);

        final colReceiptNo = baseReceiptNo * flexRatio;
        final colName = baseName * flexRatio;
        final colVillage = baseVillage * flexRatio;
        final colTaluka = baseTaluka * flexRatio;
        final colDistrict = baseDistrict * flexRatio;
        final colState = flexibleWidth - (colReceiptNo + colName + colVillage + colTaluka + colDistrict);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 20 : 5),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: Scrollbar(
                controller: _donationsHorizScrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _donationsHorizScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    width: effectiveWidth,
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          height: 46,
                          color: isDark ? const Color(0xFF2A2A3E) : Colors.indigo.withAlpha(12),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _buildTableHeaderCell('Receipt No', width: colReceiptNo),
                              _buildTableHeaderCell('Donor Name', width: colName),
                              _buildTableHeaderCell('Village', width: colVillage),
                              _buildTableHeaderCell('Taluka', width: colTaluka),
                              _buildTableHeaderCell('District', width: colDistrict),
                              _buildTableHeaderCell('State', width: colState),
                              _buildTableHeaderCell('Country', width: colCountry),
                              _buildTableHeaderCell('Category', width: colCategory),
                              _buildTableHeaderCell('Amount', width: colAmount),
                              _buildTableHeaderCell('Payment Method', width: colMethod),
                              _buildTableHeaderCell('Date', width: colDate),
                              _buildTableHeaderCell('Actions', width: colActions, alignment: Alignment.center),
                            ],
                          ),
                        ),
                        Divider(height: 1, thickness: 1, color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                        // Virtualized Rows
                        Expanded(
                          child: ListView.separated(
                            key: const PageStorageKey<String>('fees_donations_virtualized_list'),
                            itemCount: items.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark ? Colors.white.withAlpha(6) : Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final d = items[index];
                              final isOdd = index.isOdd;
                              final dateStr = d.paymentDate != null
                                  ? DateFormat('MMM dd, yyyy').format(DateTime.tryParse(d.paymentDate!) ?? DateTime.now())
                                  : '-';

                              return Container(
                                height: 54,
                                color: isOdd
                                    ? (isDark ? Colors.white.withAlpha(3) : Colors.grey.shade50)
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    // 1. Receipt No
                                    SizedBox(
                                      width: colReceiptNo,
                                      child: Text(
                                        d.displayReceiptNo,
                                        style: AppTheme.getFontStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 2. Donor Name & Contact
                                    SizedBox(
                                      width: colName,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.donorName ?? 'Anonymous (Lillah)',
                                            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (d.donorPhone != null && d.donorPhone!.trim().isNotEmpty)
                                            Text(
                                              d.donorPhone!,
                                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    // 3. Village
                                    SizedBox(
                                      width: colVillage,
                                      child: Text(
                                        (d.village != null && d.village!.trim().isNotEmpty) ? d.village! : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 4. Taluka
                                    SizedBox(
                                      width: colTaluka,
                                      child: Text(
                                        (d.taluka != null && d.taluka!.trim().isNotEmpty) ? d.taluka! : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 5. District
                                    SizedBox(
                                      width: colDistrict,
                                      child: Text(
                                        (d.district != null && d.district!.trim().isNotEmpty) ? d.district! : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 6. State
                                    SizedBox(
                                      width: colState,
                                      child: Text(
                                        (d.state != null && d.state!.trim().isNotEmpty) ? d.state! : '-',
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 7. Country
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        (d.country != null && d.country!.trim().isNotEmpty) ? d.country! : 'India',
                                        style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 8. Category
                                    SizedBox(
                                      width: 120,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withAlpha(15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          d.donationType,
                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.blue),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    // 9. Amount
                                    SizedBox(
                                      width: 110,
                                      child: Text(
                                        '₹${d.amount.toStringAsFixed(0)}',
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.green),
                                      ),
                                    ),
                                    // 10. Payment Method
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        d.paymentMethod,
                                        style: AppTheme.getFontStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 11. Date
                                    SizedBox(
                                      width: 120,
                                      child: Text(
                                        dateStr,
                                        style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    // 12. Action (Receipt & Delete)
                                    SizedBox(
                                      width: 90,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                            tooltip: 'Print Receipt',
                                            onPressed: () {
                                              ReceiptPdfGenerator.printDonationReceipt(
                                                receiptNo: d.displayReceiptNo,
                                                donorName: d.donorName,
                                                donorPhone: d.donorPhone,
                                                village: d.village,
                                                taluka: d.taluka,
                                                district: d.district,
                                                state: d.state,
                                                country: d.country,
                                                pinCode: d.pinCode,
                                                amount: d.amount,
                                                donationType: d.donationType,
                                                paymentMethod: d.paymentMethod,
                                                date: d.paymentDate ?? DateTime.now().toIso8601String(),
                                              );
                                            },
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade700),
                                            tooltip: 'Delete Donation',
                                            onPressed: () => _confirmDeleteDonation(d),
                                            splashRadius: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── PAY FEE DIALOG ─────────────────────────────────────────────
  void _showPayFeeDialog(StudentFeeSummary student, List<FeeType> feeTypes) async {
    if (!_ensureFeatureAccess('fees_collect', 'Fee Collection & Receipts')) return;

    final formKey = GlobalKey<FormState>();
    final remarksController = TextEditingController();

    DateTime selectedDateTime = DateTime.now();
    final initialReceiptNo = await DonationReceiptSettings.getNextUnifiedReceiptNo(
      receiptType: 'fee',
      targetDate: selectedDateTime,
    );
    final receiptNoController = TextEditingController(text: initialReceiptNo);

    // Select initial fee head: pick first pending head, or first head, or first feeType, or 'Monthly Fees'
    String selectedFeeType = 'Monthly Fees';
    double initialAmount = student.monthlyFees;
    if (student.feeHeads.isNotEmpty) {
      final pendingHead = student.feeHeads.where((h) => h.totalPending > 0).firstOrNull;
      final head = pendingHead ?? student.feeHeads.first;
      selectedFeeType = head.feeTypeName;
      if (head.totalPending > 0) {
        initialAmount = head.totalPending;
      } else if (head.amount > 0) {
        initialAmount = head.amount;
      }
    } else if (feeTypes.isNotEmpty) {
      selectedFeeType = feeTypes.first.name;
    }

    final amountController = TextEditingController(text: initialAmount.toStringAsFixed(0));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Record Fee Payment', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Student info
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.primaryColor.withAlpha(30)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${student.displayName}  (${student.className ?? "-"})',
                                style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 4),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  Text('GR: ${student.grNo ?? "-"}  •  Monthly Fee: ₹${student.monthlyFees.toStringAsFixed(0)}',
                                    style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  if (student.totalDiscount > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(color: Colors.red.shade200, width: 0.5),
                                      ),
                                      child: Text(
                                        'Disc: ${_formatFeeDiscountBadge(student.totalDiscount, student.totalExpected + student.totalDiscount, '')}',
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text('Outstanding Balance: ₹${student.totalPending.toStringAsFixed(0)}',
                          style: AppTheme.getFontStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 13)),
                        if (student.feeHeads.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text('Fee Head Balances (Tap to Select):',
                                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Text(
                                'Selected: $selectedFeeType',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: student.feeHeads.map((head) {
                              final isSelected = head.feeTypeName.toLowerCase() == selectedFeeType.toLowerCase();
                              final isPaid = head.totalPending <= 0 && head.totalExpected > 0;
                              return InkWell(
                                onTap: () {
                                  setModalState(() {
                                    selectedFeeType = head.feeTypeName;
                                    if (head.totalPending > 0) {
                                      amountController.text = head.totalPending.toStringAsFixed(0);
                                    } else if (head.amount > 0) {
                                      amountController.text = head.amount.toStringAsFixed(0);
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primaryColor.withAlpha(28)
                                        : (isPaid ? Colors.green.withAlpha(15) : Colors.grey.withAlpha(15)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primaryColor
                                          : (isPaid ? Colors.green.withAlpha(70) : Colors.grey.shade300),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isSelected) ...[
                                            Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.primaryColor),
                                            const SizedBox(width: 3),
                                          ],
                                          Text(
                                            head.feeTypeName,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected ? AppTheme.primaryColor : Colors.black87,
                                            ),
                                          ),
                                          if (head.isDueInMonth(_currentMonthName) && head.totalPending > 0) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.notifications_active_rounded, size: 9, color: Colors.orange.shade900),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    'Due this month',
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.orange.shade900,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (head.discountAmount != null && head.discountAmount! > 0) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                _formatFeeDiscountBadge(head.discountAmount!, head.originalAmount, head.discountTag),
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Paid: ₹${head.totalPaid.toStringAsFixed(0)} • Due: ₹${head.totalPending.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: head.totalPending > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (head.monthsList.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          '🗓 ${head.monthsDisplay}',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ] else if (feeTypes.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('Fee Type (Tap to Select):',
                            style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: feeTypes.map((t) {
                              final isSelected = t.name.toLowerCase() == selectedFeeType.toLowerCase();
                              return ChoiceChip(
                                label: Text(t.name, style: TextStyle(fontSize: 11.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                selected: isSelected,
                                onSelected: (val) {
                                  if (val) {
                                    setModalState(() => selectedFeeType = t.name);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // ── RECEIPT NO & PAYMENT DATE ROW ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Receipt Number
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: receiptNoController,
                                decoration: InputDecoration(
                                  labelText: 'Receipt No *',
                                  hintText: 'e.g. 00001',
                                  prefixIcon: const Icon(Icons.receipt_long_rounded, size: 18),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.settings_suggest_rounded, color: Color(0xFFD4AF37), size: 20),
                                    tooltip: 'Customize Receipt Number Format',
                                    onPressed: () async {
                                      final newSettings = await DonationReceiptConfigDialog.show(
                                        context,
                                        title: 'FEE & DONATION RECEIPT CONFIG',
                                      );
                                      if (newSettings != null) {
                                        final regen = await DonationReceiptSettings.getNextUnifiedReceiptNo(
                                          receiptType: 'fee',
                                          settings: newSettings,
                                          targetDate: selectedDateTime,
                                        );
                                        setModalState(() {
                                          receiptNoController.text = regen;
                                        });
                                      }
                                    },
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Payment Date
                            Expanded(
                              flex: 2,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  final pickedDate = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDateTime,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (pickedDate != null) {
                                    setModalState(() {
                                      selectedDateTime = DateTime(
                                        pickedDate.year, pickedDate.month, pickedDate.day,
                                        selectedDateTime.hour, selectedDateTime.minute,
                                      );
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Date',
                                    prefixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  child: Text(
                                    DateFormat('dd MMM yyyy').format(selectedDateTime),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Amount field (pre-filled with selected fee head pending or 1 month fee, user can edit)
                        TextFormField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: context.tr('amount_inr'), helperText: context.tr('by_default_1_month_fee')),
                          style: AppTheme.getFontStyle(fontSize: 14),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            final amt = double.tryParse(val);
                            if (amt == null || amt <= 0) return context.tr('enter_valid_positive_number');
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: remarksController,
                          decoration: const InputDecoration(labelText: 'Remarks (Optional)'),
                          style: AppTheme.getFontStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dContext), child: Text(context.tr('cancel'))),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      final amount = double.parse(amountController.text);
                      final receiptNo = receiptNoController.text.trim();
                      context.read<FeesBloc>().add(PayStudentFee(
                        studentId: student.id,
                        amount: amount,
                        feeType: selectedFeeType,
                        remarks: remarksController.text,
                        receiptNo: receiptNo.isNotEmpty ? receiptNo : null,
                      ));
                      Navigator.pop(dContext);

                      ReceiptPdfGenerator.printFeeReceipt(
                        studentName: student.displayName,
                        grNo: student.grNo ?? '-',
                        className: student.className ?? '-',
                        amountPaid: amount,
                        feeType: selectedFeeType,
                        remainingBalance: student.totalPending - amount,
                        date: selectedDateTime.toIso8601String(),
                        receiptNo: receiptNo.isNotEmpty ? receiptNo : null,
                      );
                    }
                  },
                  child: Text(context.tr('record_print')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── PAYMENT HISTORY DIALOG ─────────────────────────────────────
  void _showPaymentHistoryDialog(StudentFeeSummary student) {
    showDialog(
      context: context,
      builder: (dContext) => _PaymentHistoryDialog(
        student: student,
        repository: FeesRepository(ApiClient()),
      ),
    );
  }

  // ─── GLOBAL ALL PAYMENTS & RECEIPTS SEARCH DIALOG ───────────────
  void _showAllPaymentsSearchDialog() {
    showDialog(
      context: context,
      builder: (dContext) => _AllPaymentsSearchDialog(
        repository: FeesRepository(ApiClient()),
      ),
    );
  }

  // ─── CONFIRM DELETE DONATION ────────────────────────────────────
  Future<bool> _confirmDeleteDonation(Donation d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Delete Donation Record', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kya aap waqai is donation record ko delete karna chahte hain?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Donor: ${d.donorName ?? "Anonymous"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('• Receipt No: #${d.displayReceiptNo}', style: const TextStyle(fontSize: 12)),
                  Text('• Category: ${d.donationType}', style: const TextStyle(fontSize: 12)),
                  Text('• Amount: ₹${d.amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                  if (d.paymentDate != null)
                    Text('• Date: ${DateFormat("dd MMM yyyy, hh:mm a").format(DateTime.tryParse(d.paymentDate!) ?? DateTime.now())}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: Is donation ko delete karne se total collected amount aur statistics automatically update ho jayenge.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nahi / Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Haan, Delete Karein'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      context.read<FeesBloc>().add(DeleteDonation(d.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Donation receipt #${d.displayReceiptNo} delete ho gayi.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    }
    return false;
  }

  // ─── DONOR PAYMENT HISTORY DIALOG ───────────────────────────────
  void _showDonorPaymentHistoryDialog(DonorSummary donor) {
    showDialog(
      context: context,
      builder: (dContext) => _DonorPaymentHistoryDialog(
        donor: donor,
        onDeleteDonation: (d) => _confirmDeleteDonation(d),
        onPayDonation: () {
          final state = context.read<FeesBloc>().state;
          if (state is FeesLoaded) {
            _showRecordDonationDialog(state.donationTypes, prefillDonor: donor);
          }
        },
      ),
    );
  }
}

class _PaymentHistoryDialog extends StatefulWidget {
  final StudentFeeSummary student;
  final FeesRepository repository;

  const _PaymentHistoryDialog({
    required this.student,
    required this.repository,
  });

  @override
  State<_PaymentHistoryDialog> createState() => _PaymentHistoryDialogState();
}

class _PaymentHistoryDialogState extends State<_PaymentHistoryDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<FeePayment> _payments = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime? _selectedDate;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<FeePayment> get _filteredPayments {
    final query = _searchQuery.trim().toLowerCase();
    return _payments.where((p) {
      if (query.isNotEmpty) {
        final rcpt = (p.receiptNo ?? '').toLowerCase();
        final type = p.feeType.toLowerCase();
        final remarks = (p.remarks ?? '').toLowerCase();
        final amountStr = p.amount.toStringAsFixed(0);
        final matches = rcpt.contains(query) ||
            type.contains(query) ||
            remarks.contains(query) ||
            amountStr == query;
        if (!matches) return false;
      }

      if (_selectedDate != null) {
        DateTime? dt;
        if (p.createdAt != null && p.createdAt!.trim().isNotEmpty) {
          String raw = p.createdAt!.trim();
          if (raw.length == 19 && raw.contains(' ') && !raw.contains('T')) {
            raw = '${raw.replaceFirst(' ', 'T')}Z';
          }
          dt = DateTime.tryParse(raw)?.toLocal();
        }
        if (dt == null && p.paymentDate != null && p.paymentDate!.trim().isNotEmpty) {
          dt = DateTime.tryParse(p.paymentDate!.trim());
        }

        if (dt == null) return false;
        if (dt.year != _selectedDate!.year ||
            dt.month != _selectedDate!.month ||
            dt.day != _selectedDate!.day) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await widget.repository.getStudentPayments(
        widget.student.id,
        grNo: widget.student.grNo,
      );
      if (mounted) {
        setState(() {
          _payments = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.9).clamp(340.0, 580.0);
    final dialogHeight = (size.height * 0.8).clamp(420.0, 580.0);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded, color: AppTheme.primaryColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Payment History',
                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  '${student.displayName} • GR: ${student.grNo ?? "-"} • ${student.className ?? "-"}',
                  style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _isLoading
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primaryColor),
                      const SizedBox(height: 16),
                      Text('Loading payment history...', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              )
            : _errorMessage != null && _payments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 40),
                          const SizedBox(height: 10),
                          const Text('Failed to load history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_errorMessage!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _loadHistory,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Summary KPI Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Total Paid', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text('₹${student.totalPaid.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                              ],
                            ),
                            Container(height: 24, width: 1, color: Colors.grey.shade300),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Pending Dues', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text('₹${student.totalPending.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: student.totalPending > 0 ? Colors.red.shade700 : Colors.green.shade700)),
                              ],
                            ),
                            Container(height: 24, width: 1, color: Colors.grey.shade300),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Transactions', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text('${_payments.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Itemized fee heads if available
                      if (student.feeHeads.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryColor.withAlpha(30)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Fee Head Balances:',
                                style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: student.feeHeads.map((h) {
                                  final isCleared = h.totalPending <= 0 && h.totalExpected > 0;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isCleared ? Colors.green.shade50 : Colors.white,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: isCleared ? Colors.green.shade200 : Colors.grey.shade300, width: 0.8),
                                    ),
                                    child: Text(
                                      '${h.feeTypeName}: Paid ₹${h.totalPaid.toStringAsFixed(0)} / Due ₹${h.totalPending.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isCleared ? Colors.green.shade800 : (h.totalPending > 0 ? Colors.red.shade800 : Colors.black87),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Search by Receipt No & Date Filter Row
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            // Search field (Receipt No, Fee Type, Note)
                            Expanded(
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  children: [
                                    Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchCtrl,
                                        style: const TextStyle(fontSize: 12.5),
                                        decoration: const InputDecoration(
                                          hintText: 'Search Receipt No., note...',
                                          hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _searchQuery = val;
                                          });
                                        },
                                      ),
                                    ),
                                    if (_searchQuery.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          _searchCtrl.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                        child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade600),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Date Filter Button
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: AppTheme.primaryColor,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setState(() {
                                    _selectedDate = picked;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _selectedDate != null
                                      ? AppTheme.primaryColor.withAlpha(20)
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selectedDate != null
                                        ? AppTheme.primaryColor
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_today_rounded,
                                      size: 14,
                                      color: _selectedDate != null ? AppTheme.primaryColor : Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _selectedDate != null
                                          ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                                          : 'Filter Date',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.w500,
                                        color: _selectedDate != null ? AppTheme.primaryColor : Colors.grey.shade800,
                                      ),
                                    ),
                                    if (_selectedDate != null) ...[
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _selectedDate = null;
                                          });
                                        },
                                        child: Icon(Icons.close_rounded, size: 14, color: AppTheme.primaryColor),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Filter Status / Clear Row
                      if (_searchQuery.isNotEmpty || _selectedDate != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Showing ${_filteredPayments.length} of ${_payments.length} transactions',
                                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                              ),
                              InkWell(
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _selectedDate = null;
                                  });
                                },
                                child: Text(
                                  'Clear filters',
                                  style: TextStyle(fontSize: 10.5, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Payments List
                      Expanded(
                        child: _payments.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 44, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text('No fee payments recorded.', style: AppTheme.getFontStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text('Payments recorded for this student will appear here with date and time.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                  ],
                                ),
                              )
                            : _filteredPayments.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                                        const SizedBox(height: 8),
                                        Text('No matching transactions found',
                                          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
                                        const SizedBox(height: 4),
                                        Text(
                                          _selectedDate != null && _searchQuery.isNotEmpty
                                              ? 'No receipts matching "$_searchQuery" on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}.'
                                              : _selectedDate != null
                                                  ? 'No receipts found on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}.'
                                                  : 'No receipts or payments matching "$_searchQuery".',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                        const SizedBox(height: 10),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              _selectedDate = null;
                                            });
                                          },
                                          icon: const Icon(Icons.refresh_rounded, size: 14),
                                          label: const Text('Reset Filters', style: TextStyle(fontSize: 11.5)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _filteredPayments.length,
                                    separatorBuilder: (context, index) => const Divider(height: 8),
                                    itemBuilder: (context, idx) {
                                      final p = _filteredPayments[idx];

                                  // Format Date and Time accurately
                                  DateTime? dt;
                                  if (p.createdAt != null && p.createdAt!.trim().isNotEmpty) {
                                    String raw = p.createdAt!.trim();
                                    if (raw.length == 19 && raw.contains(' ') && !raw.contains('T')) {
                                      raw = '${raw.replaceFirst(' ', 'T')}Z';
                                    }
                                    dt = DateTime.tryParse(raw)?.toLocal();
                                  }
                                  if (dt == null && p.paymentDate != null && p.paymentDate!.trim().isNotEmpty) {
                                    dt = DateTime.tryParse(p.paymentDate!.trim());
                                  }

                                  String dateTimeStr = '-';
                                  if (dt != null) {
                                    final hasTime = (p.createdAt != null && p.createdAt!.trim().isNotEmpty) ||
                                        (dt.hour != 0 || dt.minute != 0 || dt.second != 0);
                                    dateTimeStr = hasTime
                                        ? DateFormat('dd MMM yyyy, hh:mm a').format(dt)
                                        : DateFormat('dd MMM yyyy').format(dt);
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.green.shade200),
                                          ),
                                          child: Icon(Icons.check_rounded, color: Colors.green.shade700, size: 16),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    p.feeType.isNotEmpty ? p.feeType : 'Fee Payment',
                                                    style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.shade100,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      p.status.isNotEmpty ? p.status : 'Paid',
                                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(Icons.access_time_rounded, size: 11, color: Colors.grey.shade600),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    dateTimeStr,
                                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                              if (p.remarks != null && p.remarks!.trim().isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Note: ${p.remarks!.trim()}',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                              if (p.receiptNo != null && p.receiptNo!.trim().isNotEmpty) ...[
                                                const SizedBox(height: 1),
                                                Text(
                                                  'Rcpt: #${p.receiptNo!.trim()}',
                                                  style: TextStyle(fontSize: 9.5, color: Colors.blueGrey.shade600),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '₹${p.amount.toStringAsFixed(0)}',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.green.shade800),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                                                  tooltip: 'Print Receipt',
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                                  splashRadius: 16,
                                                  onPressed: () {
                                                    ReceiptPdfGenerator.printFeeReceipt(
                                                      studentName: student.displayName,
                                                      grNo: student.grNo ?? '-',
                                                      className: student.className ?? '-',
                                                      amountPaid: p.amount,
                                                      feeType: p.feeType,
                                                      remainingBalance: student.totalPending,
                                                      date: p.createdAt ?? p.paymentDate ?? DateTime.now().toIso8601String(),
                                                      receiptNo: p.receiptNo,
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 18),
                                                  tooltip: 'Delete Payment Entry',
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                                  splashRadius: 16,
                                                  onPressed: () => _confirmDeletePayment(p),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('close'), style: AppTheme.getFontStyle()),
        ),
      ],
    );
  }

  Future<void> _confirmDeletePayment(FeePayment p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Delete Fee Payment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kya aap waqai is fee payment entry ko delete karna chahte hain?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Student: ${widget.student.displayName}', style: const TextStyle(fontSize: 12)),
                  Text('• Fee Type: ${p.feeType.isNotEmpty ? p.feeType : "Fee Payment"}', style: const TextStyle(fontSize: 12)),
                  Text('• Amount: ₹${p.amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                  if (p.receiptNo != null && p.receiptNo!.trim().isNotEmpty)
                    Text('• Receipt No: #${p.receiptNo}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: Is payment ko delete karne se student ki paid aur pending balance automatically update ho jayegi.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _payments.removeWhere((item) => item.id == p.id);
      });
      try {
        await widget.repository.deleteFeePayment(p.id);
        if (mounted) {
          context.read<FeesBloc>().add(LoadFeesData());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('Fee payment of ₹${p.amount.toStringAsFixed(0)} deleted successfully.'),
                ],
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class _AllPaymentsSearchDialog extends StatefulWidget {
  final FeesRepository repository;

  const _AllPaymentsSearchDialog({required this.repository});

  @override
  State<_AllPaymentsSearchDialog> createState() => _AllPaymentsSearchDialogState();
}

class _AllPaymentsSearchDialogState extends State<_AllPaymentsSearchDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allPayments = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadAllPayments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllPayments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await widget.repository.getAllFeePayments();
      if (mounted) {
        setState(() {
          _allPayments = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPayments {
    final query = _searchQuery.trim().toLowerCase();
    return _allPayments.where((r) {
      if (query.isNotEmpty) {
        final rcpt = (r['receipt_no']?.toString() ?? '').toLowerCase();
        final sName = (r['student_name']?.toString() ?? '').toLowerCase();
        final gr = (r['gr_no']?.toString() ?? '').toLowerCase();
        final cName = (r['class_name']?.toString() ?? '').toLowerCase();
        final feeType = (r['fee_type']?.toString() ?? '').toLowerCase();
        final remarks = (r['remarks']?.toString() ?? '').toLowerCase();
        final amt = (r['amount']?.toString() ?? '');

        final match = rcpt.contains(query) ||
            sName.contains(query) ||
            gr.contains(query) ||
            cName.contains(query) ||
            feeType.contains(query) ||
            remarks.contains(query) ||
            amt == query;
        if (!match) return false;
      }

      if (_selectedDate != null) {
        DateTime? dt;
        final cDate = r['created_at']?.toString() ?? '';
        final pDate = r['payment_date']?.toString() ?? '';
        if (cDate.trim().isNotEmpty) {
          String raw = cDate.trim();
          if (raw.length == 19 && raw.contains(' ') && !raw.contains('T')) {
            raw = '${raw.replaceFirst(' ', 'T')}Z';
          }
          dt = DateTime.tryParse(raw)?.toLocal();
        }
        if (dt == null && pDate.trim().isNotEmpty) {
          dt = DateTime.tryParse(pDate.trim());
        }

        if (dt == null) return false;
        if (dt.year != _selectedDate!.year ||
            dt.month != _selectedDate!.month ||
            dt.day != _selectedDate!.day) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.9).clamp(380.0, 750.0);
    final dialogHeight = (size.height * 0.82).clamp(450.0, 620.0);

    final filtered = _filteredPayments;
    final totalCollected = filtered.fold<double>(0.0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0.0));

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_rounded, color: Colors.teal.shade700, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Payment History & Receipts',
                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  'Search fee payments by Receipt No., student name, GR No., or date',
                  style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primaryColor),
                    const SizedBox(height: 16),
                    Text('Loading all payment receipts...', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              )
            : _errorMessage != null && _allPayments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 40),
                        const SizedBox(height: 10),
                        const Text('Failed to load receipts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(_errorMessage!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _loadAllPayments,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Search and Date Filter Row
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                children: [
                                  Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        hintText: 'Search Receipt No, Student Name, GR No...',
                                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: (val) {
                                        setState(() {
                                          _searchQuery = val;
                                        });
                                      },
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                      },
                                      child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade600),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Date Filter Button
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: ColorScheme.light(
                                        primary: AppTheme.primaryColor,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: _selectedDate != null
                                    ? Colors.teal.shade50
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _selectedDate != null
                                      ? Colors.teal.shade400
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 15,
                                    color: _selectedDate != null ? Colors.teal.shade700 : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedDate != null
                                        ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                                        : 'Filter Date',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.w500,
                                      color: _selectedDate != null ? Colors.teal.shade800 : Colors.grey.shade800,
                                    ),
                                  ),
                                  if (_selectedDate != null) ...[
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedDate = null;
                                        });
                                      },
                                      child: Icon(Icons.close_rounded, size: 14, color: Colors.teal.shade800),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Metrics & Filter Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Matching: ',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                Text(
                                  '${filtered.length} receipt${filtered.length == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'Total: ',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                Text(
                                  '₹${NumberFormat('#,##,###').format(totalCollected)}',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                                ),
                              ],
                            ),
                            if (_searchQuery.isNotEmpty || _selectedDate != null)
                              InkWell(
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _selectedDate = null;
                                  });
                                },
                                child: Text(
                                  'Clear all filters',
                                  style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Receipts List
                      Expanded(
                        child: _allPayments.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.receipt_long_outlined, size: 44, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text('No fee payments recorded yet.', style: AppTheme.getFontStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              )
                            : filtered.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                                        const SizedBox(height: 8),
                                        Text('No receipts match your search',
                                          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
                                        const SizedBox(height: 4),
                                        Text(
                                          _selectedDate != null && _searchQuery.isNotEmpty
                                              ? 'No receipts matching "$_searchQuery" on ${DateFormat('dd MMM yyyy').format(_selectedDate!)}.'
                                              : _selectedDate != null
                                                  ? 'No receipts found for ${DateFormat('dd MMM yyyy').format(_selectedDate!)}.'
                                                  : 'No receipts matching "$_searchQuery".',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        ),
                                        const SizedBox(height: 10),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              _selectedDate = null;
                                            });
                                          },
                                          icon: const Icon(Icons.refresh_rounded, size: 14),
                                          label: const Text('Reset Filters', style: TextStyle(fontSize: 11.5)),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (context, index) => const Divider(height: 8),
                                    itemBuilder: (context, idx) {
                                      final r = filtered[idx];

                                      final studentName = r['student_name']?.toString() ?? 'Student';
                                      final grNo = r['gr_no']?.toString() ?? '-';
                                      final className = r['class_name']?.toString() ?? '-';
                                      final feeType = r['fee_type']?.toString() ?? 'Fee Payment';
                                      final rcptNo = r['receipt_no']?.toString();
                                      final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
                                      final remarks = r['remarks']?.toString();
                                      final createdAt = r['created_at']?.toString();
                                      final paymentDate = r['payment_date']?.toString();

                                      DateTime? dt;
                                      if (createdAt != null && createdAt.trim().isNotEmpty) {
                                        String raw = createdAt.trim();
                                        if (raw.length == 19 && raw.contains(' ') && !raw.contains('T')) {
                                          raw = '${raw.replaceFirst(' ', 'T')}Z';
                                        }
                                        dt = DateTime.tryParse(raw)?.toLocal();
                                      }
                                      if (dt == null && paymentDate != null && paymentDate.trim().isNotEmpty) {
                                        dt = DateTime.tryParse(paymentDate.trim());
                                      }

                                      String dateTimeStr = '-';
                                      if (dt != null) {
                                        final hasTime = (createdAt != null && createdAt.trim().isNotEmpty) ||
                                            (dt.hour != 0 || dt.minute != 0 || dt.second != 0);
                                        dateTimeStr = hasTime
                                            ? DateFormat('dd MMM yyyy, hh:mm a').format(dt)
                                            : DateFormat('dd MMM yyyy').format(dt);
                                      }

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.grey.shade200),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.shade50,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.teal.shade200),
                                              ),
                                              child: Icon(Icons.receipt_rounded, color: Colors.teal.shade700, size: 16),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      if (rcptNo != null && rcptNo.trim().isNotEmpty) ...[
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blueGrey.shade50,
                                                            borderRadius: BorderRadius.circular(4),
                                                            border: Border.all(color: Colors.blueGrey.shade200),
                                                          ),
                                                          child: Text(
                                                            '#$rcptNo',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.blueGrey.shade800,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                      ],
                                                      Text(
                                                        feeType,
                                                        style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '$studentName • GR: $grNo • $className',
                                                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.access_time_rounded, size: 11, color: Colors.grey.shade500),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        dateTimeStr,
                                                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                                                      ),
                                                      if (remarks != null && remarks.trim().isNotEmpty) ...[
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            '• ${remarks.trim()}',
                                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '₹${amount.toStringAsFixed(0)}',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green.shade800),
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                                                      tooltip: 'Print Receipt',
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                                      splashRadius: 16,
                                                      onPressed: () {
                                                        ReceiptPdfGenerator.printFeeReceipt(
                                                          studentName: studentName,
                                                          grNo: grNo,
                                                          className: className,
                                                          amountPaid: amount,
                                                          feeType: feeType,
                                                          remainingBalance: 0.0,
                                                          date: createdAt ?? paymentDate ?? DateTime.now().toIso8601String(),
                                                          receiptNo: rcptNo,
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(width: 4),
                                                    IconButton(
                                                      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 18),
                                                      tooltip: 'Delete Receipt Entry',
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                                      splashRadius: 16,
                                                      onPressed: () => _confirmDeletePaymentEntry(r),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('close'), style: AppTheme.getFontStyle()),
        ),
      ],
    );
  }

  Future<void> _confirmDeletePaymentEntry(Map<String, dynamic> r) async {
    final paymentId = r['id']?.toString() ?? '';
    final studentName = r['student_name']?.toString() ?? 'Student';
    final feeType = r['fee_type']?.toString() ?? 'Fee Payment';
    final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
    final rcptNo = r['receipt_no']?.toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Delete Fee Receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kya aap waqai is fee payment receipt ko delete karna chahte hain?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Student: $studentName', style: const TextStyle(fontSize: 12)),
                  Text('• Fee Type: $feeType', style: const TextStyle(fontSize: 12)),
                  Text('• Amount: ₹${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                  if (rcptNo != null && rcptNo.trim().isNotEmpty)
                    Text('• Receipt No: #$rcptNo', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: Delete karne ke baad student ki summary fees me iska hisab update ho jayega.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_rounded, size: 16),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted && paymentId.isNotEmpty) {
      setState(() {
        _allPayments.removeWhere((item) => item['id']?.toString() == paymentId);
      });
      try {
        await widget.repository.deleteFeePayment(paymentId);
        if (mounted) {
          context.read<FeesBloc>().add(LoadFeesData());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Receipt #${rcptNo ?? paymentId} deleted successfully.'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

class _DonorPaymentHistoryDialog extends StatefulWidget {
  final DonorSummary donor;
  final Future<bool> Function(Donation d) onDeleteDonation;
  final VoidCallback onPayDonation;

  const _DonorPaymentHistoryDialog({
    required this.donor,
    required this.onDeleteDonation,
    required this.onPayDonation,
  });

  @override
  State<_DonorPaymentHistoryDialog> createState() => _DonorPaymentHistoryDialogState();
}

class _DonorPaymentHistoryDialogState extends State<_DonorPaymentHistoryDialog> {
  late List<Donation> _donations;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _donations = List.of(widget.donor.donations);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Donation> get _filteredDonations {
    return _donations.where((d) {
      if (_selectedDate != null) {
        DateTime? dt;
        if (d.paymentDate != null && d.paymentDate!.trim().isNotEmpty) {
          dt = DateTime.tryParse(d.paymentDate!.trim());
        }
        if (dt != null) {
          final isSameDay = dt.year == _selectedDate!.year &&
              dt.month == _selectedDate!.month &&
              dt.day == _selectedDate!.day;
          if (!isSameDay) return false;
        } else {
          return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final rcpt = (d.receiptNo ?? '').toLowerCase();
        final dispRcpt = d.displayReceiptNo.toLowerCase();
        final type = d.donationType.toLowerCase();
        final method = d.paymentMethod.toLowerCase();
        final amt = d.amount.toString();
        if (!rcpt.contains(q) && !dispRcpt.contains(q) && !type.contains(q) && !method.contains(q) && !amt.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalDonated = _donations.fold<double>(0.0, (s, d) => s + d.amount);
    final filtered = _filteredDonations;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volunteer_activism_rounded, color: Colors.green, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Donation Payment History',
                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${widget.donor.donorName}${widget.donor.displayPhone != '-' ? ' • ${widget.donor.displayPhone}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KPI Summary Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF26263A) : Colors.green.shade50.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white12 : Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Donated',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '₹${NumberFormat('#,##,###').format(totalDonated)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 28, width: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contributions',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${_donations.length} ${_donations.length == 1 ? 'Receipt' : 'Receipts'}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                  ),
                  if (widget.donor.fullLocation != '-') ...[
                    Container(height: 28, width: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Location',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            widget.donor.fullLocation,
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search & Date Filter Row
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      style: AppTheme.getFontStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: 'Search Receipt No, Category, Amount...',
                        hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade400),
                        prefixIcon: const Icon(Icons.search_rounded, size: 16),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 14),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Date filter button
                OutlinedButton.icon(
                  icon: Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: _selectedDate != null ? AppTheme.primaryColor : Colors.grey.shade600,
                  ),
                  label: Text(
                    _selectedDate != null
                        ? DateFormat('dd MMM yyyy').format(_selectedDate!)
                        : 'Filter Date',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.normal,
                      color: _selectedDate != null ? AppTheme.primaryColor : null,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(
                      color: _selectedDate != null ? AppTheme.primaryColor : (isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                ),
                if (_selectedDate != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    tooltip: 'Clear Date Filter',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: () => setState(() => _selectedDate = null),
                  ),
              ],
            ),

            // Active Filter Indicator
            if (_searchQuery.isNotEmpty || _selectedDate != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${filtered.length} of ${_donations.length} donations',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                  InkWell(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() {
                        _searchQuery = '';
                        _selectedDate = null;
                      });
                    },
                    child: const Text(
                      'Clear Filters',
                      style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),

            // List of Donations
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 36, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            _donations.isEmpty
                                ? 'No donations recorded for this donor.'
                                : 'No donations match your search/filter.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                          ),
                          if (_searchQuery.isNotEmpty || _selectedDate != null) ...[
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _selectedDate = null;
                                });
                              },
                              child: const Text('Reset Filters', style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.separated(
                      key: const PageStorageKey<String>('donor_history_dialog_list'),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final d = filtered[idx];
                        final dateStr = d.paymentDate != null
                            ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.tryParse(d.paymentDate!) ?? DateTime.now())
                            : '-';

                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.volunteer_activism_rounded, color: Colors.green, size: 16),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          d.donationType,
                                          style: AppTheme.getFontStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor.withAlpha(15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '#${d.displayReceiptNo}',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.primaryColor,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Paid via ${d.paymentMethod} on $dateStr',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${d.amount.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
                              ),
                              const SizedBox(width: 8),
                              // Print PDF Receipt Button
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                                tooltip: 'Print Receipt',
                                onPressed: () {
                                  ReceiptPdfGenerator.printDonationReceipt(
                                    receiptNo: d.displayReceiptNo,
                                    donorName: d.donorName,
                                    donorPhone: d.donorPhone,
                                    village: d.village,
                                    taluka: d.taluka,
                                    district: d.district,
                                    state: d.state,
                                    country: d.country,
                                    pinCode: d.pinCode,
                                    amount: d.amount,
                                    donationType: d.donationType,
                                    paymentMethod: d.paymentMethod,
                                    date: d.paymentDate ?? DateTime.now().toIso8601String(),
                                  );
                                },
                                splashRadius: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                              const SizedBox(width: 4),
                              // Delete Button
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 18),
                                tooltip: 'Delete Donation',
                                onPressed: () async {
                                  final deleted = await widget.onDeleteDonation(d);
                                  if (deleted == true) {
                                    setState(() {
                                      _donations.remove(d);
                                    });
                                  }
                                },
                                splashRadius: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          icon: const Icon(Icons.payment_rounded, size: 16),
          label: const Text('Pay / Add Donation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          onPressed: () {
            Navigator.pop(context);
            widget.onPayDonation();
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

extension _FeesScreenStateExt on _FeesScreenState {

  // ─── DONOR PAST HISTORY DIALOG ────────────────────────────────────
  void _showDonorHistoryDetailsDialog(BuildContext context, String donorName, List<Donation> donations) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = donations.fold<double>(0.0, (s, d) => s + d.amount);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.withAlpha(20), shape: BoxShape.circle),
                  child: const Icon(Icons.history_edu_rounded, color: Colors.green, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Donation History — $donorName',
                        style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Total Donated: ₹${NumberFormat('#,##,###').format(total)} in ${donations.length} contributions',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 380),
              child: donations.isEmpty
                  ? Center(child: Text('No previous donations recorded.', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: donations.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final d = donations[idx];
                        final dateStr = d.paymentDate != null
                            ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.tryParse(d.paymentDate!) ?? DateTime.now())
                            : '-';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(color: Colors.green.withAlpha(15), shape: BoxShape.circle),
                            child: const Icon(Icons.volunteer_activism_rounded, color: Colors.green, size: 16),
                          ),
                          title: Row(
                            children: [
                              Text(d.donationType, style: AppTheme.getFontStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withAlpha(15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  d.displayReceiptNo,
                                  style: TextStyle(fontSize: 10.5, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text('Paid via ${d.paymentMethod} on $dateStr', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              if (d.fullLocation != '-')
                                Text('📍 ${d.fullLocation}', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹${d.amount.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 18),
                                tooltip: 'Print Receipt',
                                onPressed: () {
                                  ReceiptPdfGenerator.printDonationReceipt(
                                    receiptNo: d.displayReceiptNo,
                                    donorName: d.donorName,
                                    donorPhone: d.donorPhone,
                                    village: d.village,
                                    taluka: d.taluka,
                                    district: d.district,
                                    state: d.state,
                                    country: d.country,
                                    pinCode: d.pinCode,
                                    amount: d.amount,
                                    donationType: d.donationType,
                                    paymentMethod: d.paymentMethod,
                                    date: d.paymentDate ?? DateTime.now().toIso8601String(),
                                  );
                                },
                                splashRadius: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 18),
                                tooltip: 'Delete Donation',
                                onPressed: () async {
                                  final deleted = await _confirmDeleteDonation(d);
                                  if (deleted == true) {
                                    donations.remove(d);
                                    setDialogState(() {});
                                  }
                                },
                                splashRadius: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }

  // ─── RECORD DONATION DIALOG ─────────────────────────────────────
  void _showRecordDonationDialog(List<DonationType> types, {DonorSummary? prefillDonor}) async {
    final state = context.read<FeesBloc>().state;
    final List<Donation> pastDonations = state is FeesLoaded ? state.donations : [];

    // Group past donations by donor name for history & autocompletion
    final Map<String, List<Donation>> donorHistoryMap = {};
    for (final d in pastDonations) {
      final name = (d.donorName ?? '').trim();
      if (name.isNotEmpty) {
        donorHistoryMap.putIfAbsent(name.toLowerCase(), () => []).add(d);
      }
    }

    DateTime selectedDateTime = DateTime.now();
    final initialReceiptNo = await DonationReceiptSettings.getNextUnifiedReceiptNo(
      receiptType: 'donation',
      targetDate: selectedDateTime,
      additionalInMemory: pastDonations.map((d) => d.displayReceiptNo).toList(),
    );

    final formKey = GlobalKey<FormState>();
    final receiptNoController = TextEditingController(text: initialReceiptNo);
    final donorNameController = TextEditingController(text: prefillDonor?.donorName ?? '');
    final donorPhoneController = TextEditingController(text: prefillDonor?.donorPhone ?? '');
    final pinCodeController = TextEditingController(text: prefillDonor?.pinCode ?? '');
    final villageController = TextEditingController(text: prefillDonor?.village ?? '');
    final talukaController = TextEditingController(text: prefillDonor?.taluka ?? '');
    final districtController = TextEditingController(text: prefillDonor?.district ?? '');
    final stateController = TextEditingController(text: prefillDonor?.state ?? '');
    final countryController = TextEditingController(text: prefillDonor?.country ?? 'India');
    final amountController = TextEditingController();

    String? selectedType = types.isNotEmpty ? types[0].name : null;
    String paymentMethod = 'Cash';
    bool isFetchingPin = false;
    String lastFetchedPin = '';
    List<String> pincodeVillages = [];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;

            // Check if current donor name matches any existing donor
            final currentDonorKey = donorNameController.text.trim().toLowerCase();
            final List<Donation>? matchingDonations = currentDonorKey.isNotEmpty ? donorHistoryMap[currentDonorKey] : null;
            final double donorPastTotal = matchingDonations?.fold<double>(0.0, (s, d) => s + d.amount) ?? 0.0;
            final Donation? latestDonation = matchingDonations?.isNotEmpty == true ? matchingDonations!.first : null;

            // Autocomplete suggestions
            final donorSuggestions = currentDonorKey.isNotEmpty
                ? donorHistoryMap.keys.where((k) => k.contains(currentDonorKey) && k != currentDonorKey).take(5).toList()
                : <String>[];

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.volunteer_activism_rounded, color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          prefillDonor != null
                              ? 'Record Donation — ${prefillDonor.donorName}'
                              : 'Record Donation Collection',
                          style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          prefillDonor != null
                              ? 'Recording payment for existing donor'
                              : 'Fill donor details, receipt number & address',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Container(
                width: 620,
                constraints: const BoxConstraints(maxHeight: 640),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── RECEIPT NO & DATE/TIME ROW ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Receipt Number
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: receiptNoController,
                                decoration: InputDecoration(
                                  labelText: 'Receipt No *',
                                  hintText: 'e.g. DN-00001',
                                  prefixIcon: const Icon(Icons.receipt_long_rounded, size: 18),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.settings_suggest_rounded, color: Color(0xFFD4AF37), size: 20),
                                    tooltip: 'Customize Receipt Number Format',
                                    onPressed: () async {
                                      final newSettings = await DonationReceiptConfigDialog.show(
                                        context,
                                        title: 'DONATION & FEE RECEIPT CONFIG',
                                      );
                                      if (newSettings != null) {
                                        final regen = await DonationReceiptSettings.getNextUnifiedReceiptNo(
                                          receiptType: 'donation',
                                          settings: newSettings,
                                          targetDate: selectedDateTime,
                                          additionalInMemory: pastDonations.map((d) => d.displayReceiptNo).toList(),
                                        );
                                        setModalState(() {
                                          receiptNoController.text = regen;
                                        });
                                      }
                                    },
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Date & Time Picker
                            Expanded(
                              flex: 3,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () async {
                                  final pickedDate = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDateTime,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (pickedDate != null && ctx.mounted) {
                                    final pickedTime = await showTimePicker(
                                      context: ctx,
                                      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                                    );
                                    setModalState(() {
                                      selectedDateTime = DateTime(
                                        pickedDate.year,
                                        pickedDate.month,
                                        pickedDate.day,
                                        pickedTime?.hour ?? selectedDateTime.hour,
                                        pickedTime?.minute ?? selectedDateTime.minute,
                                      );
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 18, color: Colors.blue),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Date & Time', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                            Text(
                                              DateFormat('dd MMM yyyy, hh:mm a').format(selectedDateTime),
                                              style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // ── DONOR NAME & PHONE ROW ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Donor Name with autocompletion
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: donorNameController,
                                decoration: InputDecoration(
                                  labelText: context.tr('donor_name_optional'),
                                  hintText: 'Search or enter donor name...',
                                  prefixIcon: const Icon(Icons.person_rounded, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                                onChanged: (_) => setModalState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Donor Phone
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: donorPhoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: context.tr('donor_phone_optional'),
                                  hintText: '10-digit mobile',
                                  prefixIcon: const Icon(Icons.phone_rounded, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        // Suggestions chips if user is typing
                        if (donorSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: donorSuggestions.map((key) {
                              final match = donorHistoryMap[key]?.first;
                              final name = match?.donorName ?? key;
                              final total = donorHistoryMap[key]?.fold<double>(0.0, (s, d) => s + d.amount) ?? 0;
                              return ActionChip(
                                avatar: const Icon(Icons.history_rounded, size: 14, color: Colors.green),
                                label: Text('$name (₹${total.toStringAsFixed(0)})', style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setModalState(() {
                                    donorNameController.text = name;
                                    if (match != null) {
                                      if (match.donorPhone != null) donorPhoneController.text = match.donorPhone!;
                                      if (match.pinCode != null) pinCodeController.text = match.pinCode!;
                                      if (match.village != null) villageController.text = match.village!;
                                      if (match.taluka != null) talukaController.text = match.taluka!;
                                      if (match.district != null) districtController.text = match.district!;
                                      if (match.state != null) stateController.text = match.state!;
                                      if (match.country != null) countryController.text = match.country!;
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        // ── EXISTING DONOR HISTORY INSPECTION CARD ──
                        if (matchingDonations != null && matchingDonations.isNotEmpty && latestDonation != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F2E1B) : const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? const Color(0xFF166534) : const Color(0xFFA7F3D0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.verified_user_rounded, color: Colors.green, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Existing Donor Found: ${latestDonation.donorName}',
                                        style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '₹${NumberFormat('#,##,###').format(donorPastTotal)} Total (${matchingDonations.length} Contrib)',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Last Donated: ₹${latestDonation.amount.toStringAsFixed(0)} on ${DateFormat('dd MMM yyyy').format(DateTime.tryParse(latestDonation.paymentDate ?? '') ?? DateTime.now())} • ${latestDonation.donationType} • Receipt: ${latestDonation.displayReceiptNo}',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        // Auto-fill address details from latest donation
                                        setModalState(() {
                                          if (latestDonation.donorPhone != null) donorPhoneController.text = latestDonation.donorPhone!;
                                          if (latestDonation.pinCode != null) pinCodeController.text = latestDonation.pinCode!;
                                          if (latestDonation.village != null) villageController.text = latestDonation.village!;
                                          if (latestDonation.taluka != null) talukaController.text = latestDonation.taluka!;
                                          if (latestDonation.district != null) districtController.text = latestDonation.district!;
                                          if (latestDonation.state != null) stateController.text = latestDonation.state!;
                                          if (latestDonation.country != null) countryController.text = latestDonation.country!;
                                        });
                                      },
                                      child: const Text('↻ Auto-fill last address', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.history_rounded, size: 14),
                                      label: Text('View All (${matchingDonations.length}) Records', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                      onPressed: () {
                                        _showDonorHistoryDetailsDialog(context, latestDonation.donorName ?? 'Donor', matchingDonations);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // ── ADDRESS SECTION HEADER ──
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 16, color: Colors.orange),
                            const SizedBox(width: 6),
                            Text('Donor Address & Location', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // ── PINCODE & VILLAGE ROW ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pincode with Auto-Lookup
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: pinCodeController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: 'Pincode (6 Digits)',
                                  hintText: 'e.g. 385001',
                                  counterText: '',
                                  prefixIcon: const Icon(Icons.pin_drop_rounded, size: 18),
                                  suffixIcon: isFetchingPin
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                        )
                                      : null,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                                onChanged: (pin) async {
                                  final clean = pin.trim();
                                  if (clean.length == 6 && clean != lastFetchedPin) {
                                    lastFetchedPin = clean;
                                    setModalState(() => isFetchingPin = true);
                                    try {
                                      final res = await PincodeLookupService.lookup(clean);
                                      if (res != null) {
                                        setModalState(() {
                                          if (res.taluka.isNotEmpty) talukaController.text = res.taluka;
                                          if (res.district.isNotEmpty) districtController.text = res.district;
                                          if (res.state.isNotEmpty) stateController.text = res.state;
                                          if (res.country.isNotEmpty) countryController.text = res.country;
                                          pincodeVillages = res.villages;
                                          if (res.villages.isNotEmpty) {
                                            villageController.text = res.villages.first;
                                          }
                                        });
                                      }
                                    } finally {
                                      setModalState(() => isFetchingPin = false);
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Village
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: villageController,
                                decoration: InputDecoration(
                                  labelText: 'Village / City',
                                  hintText: 'Enter village or city',
                                  prefixIcon: const Icon(Icons.holiday_village_rounded, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        // Village suggestions from pincode
                        if (pincodeVillages.length > 1) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: pincodeVillages.take(8).map((v) {
                              final isSelected = villageController.text.trim().toLowerCase() == v.toLowerCase();
                              return ActionChip(
                                label: Text(v, style: TextStyle(fontSize: 10.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                backgroundColor: isSelected ? Colors.green.withAlpha(40) : null,
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setModalState(() {
                                    villageController.text = v;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        const SizedBox(height: 10),

                        // ── TALUKA & DISTRICT ROW ──
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: talukaController,
                                decoration: InputDecoration(
                                  labelText: 'Taluka / Tehsil',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: districtController,
                                decoration: InputDecoration(
                                  labelText: 'District',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // ── STATE & COUNTRY ROW ──
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: stateController,
                                decoration: InputDecoration(
                                  labelText: 'State',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: countryController,
                                decoration: InputDecoration(
                                  labelText: 'Country',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // ── CONTRIBUTION & PAYMENT ROW ──
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Amount
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: amountController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Amount (₹) *',
                                  prefixIcon: const Icon(Icons.currency_rupee_rounded, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                validator: (val) {
                                  if (val == null || val.isEmpty) return 'Required';
                                  final amt = double.tryParse(val);
                                  if (amt == null || amt <= 0) return context.tr('enter_valid_positive_number');
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Category
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedType,
                                decoration: InputDecoration(
                                  labelText: 'Category *',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: types.map((t) => DropdownMenuItem(value: t.name, child: Text(t.name, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (val) {
                                  if (val != null) setModalState(() => selectedType = val);
                                },
                                validator: (val) => val == null ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Payment Method
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: paymentMethod,
                                decoration: InputDecoration(
                                  labelText: context.tr('payment_method'),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: ['Cash', 'Online (UPI/Bank)', 'Cheque']
                                    .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setModalState(() => paymentMethod = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dContext),
                  child: Text(context.tr('cancel')),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: Text(context.tr('record_print')),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    if (formKey.currentState!.validate() && selectedType != null) {
                      final amount = double.parse(amountController.text);
                      final finalReceiptNo = receiptNoController.text.trim();
                      final finalDonorName = donorNameController.text.trim().isEmpty ? null : donorNameController.text.trim();
                      final finalDonorPhone = donorPhoneController.text.trim().isEmpty ? null : donorPhoneController.text.trim();
                      final finalVillage = villageController.text.trim().isEmpty ? null : villageController.text.trim();
                      final finalTaluka = talukaController.text.trim().isEmpty ? null : talukaController.text.trim();
                      final finalDistrict = districtController.text.trim().isEmpty ? null : districtController.text.trim();
                      final finalState = stateController.text.trim().isEmpty ? null : stateController.text.trim();
                      final finalCountry = countryController.text.trim().isEmpty ? 'India' : countryController.text.trim();
                      final finalPinCode = pinCodeController.text.trim().isEmpty ? null : pinCodeController.text.trim();
                      final finalDateStr = selectedDateTime.toIso8601String();

                      context.read<FeesBloc>().add(RecordDonation(
                        receiptNo: finalReceiptNo,
                        donorName: finalDonorName,
                        donorPhone: finalDonorPhone,
                        village: finalVillage,
                        taluka: finalTaluka,
                        district: finalDistrict,
                        state: finalState,
                        country: finalCountry,
                        pinCode: finalPinCode,
                        amount: amount,
                        donationType: selectedType!,
                        paymentMethod: paymentMethod,
                        paymentDate: finalDateStr,
                      ));
                      Navigator.pop(dContext);

                      ReceiptPdfGenerator.printDonationReceipt(
                        receiptNo: finalReceiptNo,
                        donorName: finalDonorName,
                        donorPhone: finalDonorPhone,
                        village: finalVillage,
                        taluka: finalTaluka,
                        district: finalDistrict,
                        state: finalState,
                        country: finalCountry,
                        pinCode: finalPinCode,
                        amount: amount,
                        donationType: selectedType!,
                        paymentMethod: paymentMethod,
                        date: finalDateStr,
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }


  // ─── MANAGE DONATION TYPES DIALOG ───────────────────────────────
  void _showManageDonationTypesDialog(List<DonationType> donationTypes) {
    final bloc = context.read<FeesBloc>();
    showDialog(
      context: context,
      builder: (dContext) {
        return BlocProvider.value(
          value: bloc,
          child: BlocBuilder<FeesBloc, FeesState>(
            builder: (ctx, state) {
              final types = state is FeesLoaded ? state.donationTypes : donationTypes;
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.volunteer_activism_rounded, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('Manage Donation Types', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add_circle_rounded, color: Colors.green),
                      onPressed: () => _showAddEditTypeDialog(
                        title: context.tr('add_donation_type'),
                        onSave: (name) => bloc.add(AddDonationType(name)),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 420,
                  height: 300,
                  child: types.isEmpty
                      ? Center(child: Text('No donation types. Add one!', style: AppTheme.getFontStyle(color: Colors.grey.shade500)))
                      : ListView.separated(
                          itemCount: types.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final t = types[idx];
                            return ListTile(
                              title: Text(t.name, style: AppTheme.getFontStyle(fontSize: 14)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.orange),
                                    onPressed: () => _showAddEditTypeDialog(
                                      title: context.tr('edit_donation_type'),
                                      initialValue: t.name,
                                      onSave: (name) => bloc.add(UpdateDonationType(t.id, name)),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                    onPressed: () => _confirmDelete(
                                      'Delete "${t.name}"?',
                                      () => bloc.add(DeleteDonationType(t.id)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dContext), child: Text(context.tr('close'))),
                ],
              );
            },
          ),
        );
      },
    );
  }



  // ─── GENERIC ADD/EDIT TYPE DIALOG ───────────────────────────────
  void _showAddEditTypeDialog({
    required String title,
    String? initialValue,
    required void Function(String name) onSave,
  }) {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(text: initialValue ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(labelText: context.tr('name'), hintText: context.tr('enter_name')),
            style: AppTheme.getFontStyle(fontSize: 14),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                onSave(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: Text(initialValue == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  // ─── CONFIRM DELETE HELPER ──────────────────────────────────────
  void _confirmDelete(String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('confirm_delete')),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  // ─── GENERATE RECEIPT DIALOG ────────────────────────────────────
  void _showGenerateReceiptDialog(StudentFeeSummary student) async {
    if (!_ensureFeatureAccess('fees_receipt_print', 'Fee Receipt Printing')) return;

    showDialog(
      context: context,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiClient().get('/fees/student/${student.id}');
      if (!mounted) return;
      Navigator.pop(context);

      final List data = response.data ?? [];
      final payments = data.map((json) => FeePayment.fromJson(json)).toList();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Generate Receipt', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${student.displayName} (${student.className ?? "-"})',
                      style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary receipt button
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ReceiptPdfGenerator.printFeeReceipt(
                        studentName: student.displayName,
                        grNo: student.grNo ?? '-',
                        className: student.className ?? '-',
                        amountPaid: student.totalPaid,
                        feeType: 'Total Summary',
                        remainingBalance: student.totalPending,
                        date: DateTime.now().toIso8601String(),
                      );
                    },
                    icon: const Icon(Icons.summarize_rounded, color: Colors.deepOrange),
                    label: Text(
                      'Summary Receipt  —  Paid: ₹${student.totalPaid.toStringAsFixed(0)}  |  Pending: ₹${student.totalPending.toStringAsFixed(0)}',
                      style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      side: const BorderSide(color: Colors.deepOrange),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Individual Payment Receipts:', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Expanded(
                  child: payments.isEmpty
                      ? Center(child: Text('No payments recorded yet.', style: AppTheme.getFontStyle(color: Colors.grey.shade500)))
                      : ListView.separated(
                          itemCount: payments.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final p = payments[idx];
                            final dateStr = p.paymentDate != null
                                ? DateFormat('MMM dd, yyyy').format(DateTime.parse(p.paymentDate!))
                                : '-';
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(20),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check_rounded, color: Colors.green, size: 18),
                              ),
                              title: Text('${p.feeType}  —  ₹${p.amount.toStringAsFixed(0)}',
                                style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text('Paid on $dateStr',
                                style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade500)),
                              trailing: FilledButton.tonalIcon(
                                onPressed: () {
                                  ReceiptPdfGenerator.printFeeReceipt(
                                    studentName: student.displayName,
                                    grNo: student.grNo ?? '-',
                                    className: student.className ?? '-',
                                    amountPaid: p.amount,
                                    feeType: p.feeType,
                                    remainingBalance: student.totalPending,
                                    date: p.paymentDate ?? DateTime.now().toIso8601String(),
                                    receiptNo: p.receiptNo,
                                  );
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                                label: Text('PDF', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade50,
                                  foregroundColor: Colors.red.shade700,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dContext),
              child: Text(context.tr('close'), style: AppTheme.getFontStyle()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load payments: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── HELPERS ────────────────────────────────────────────────────
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.payment_rounded, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: AppTheme.getFontStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, style: AppTheme.getFontStyle(color: Colors.red)),
        ],
      ),
    );
  }
}
