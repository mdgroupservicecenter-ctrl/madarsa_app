import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_date_helper.dart';
import '../../../core/utils/hijri_cubit.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../auth/presentation/bloc/auth_state.dart';
import 'bloc/dashboard_bloc.dart';
import 'bloc/dashboard_event.dart';
import 'bloc/dashboard_state.dart';
import '../data/services/dashboard_config_service.dart';
import 'widgets/customize_dashboard_dialog.dart';
import 'widgets/dashboard_watch_weather_widget.dart';
import 'widgets/dashboard_staff_analytics_widget.dart';
import 'widgets/dashboard_student_analytics_widget.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(String module)? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<DashboardCardConfig> _cards = [];

  @override
  void initState() {
    super.initState();
    _loadCustomCards();
  }

  Future<void> _loadCustomCards() async {
    final loaded = await DashboardConfigService.loadCards();
    if (mounted) {
      setState(() {
        _cards = loaded;
      });
    }
  }

  void _openCustomizeDialog(BuildContext context, DashboardLoaded? loadedState) {
    CustomizeDashboardDialog.show(
      context: context,
      currentCards: _cards,
      dashboardState: loadedState,
      onSaved: (updated) {
        setState(() {
          _cards = updated;
        });
      },
    );
  }

  Widget _buildDynamicSection({
    required String title,
    required String category,
    required DashboardLoaded state,
    required bool isDark,
    bool showCustomizeButton = false,
    int? overrideCrossAxisCount,
  }) {
    final sectionCards = _cards.where((c) => c.isVisible && c.category == category).toList();
    if (sectionCards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          label: title,
          isDark: isDark,
          action: showCustomizeButton
              ? OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    side: const BorderSide(color: Color(0xFF0F766E)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(
                    context.tr('customize_cards'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openCustomizeDialog(context, state),
                )
              : null,
        ),
        const SizedBox(height: 14),
        _ResponsiveStatsGrid(
          isDark: isDark,
          overrideCrossAxisCount: overrideCrossAxisCount,
          children: sectionCards.map((card) {
            final val = DashboardConfigService.getCardDisplayValue(card.id, state);
            return _StatCard(
              icon: card.icon,
              label: card.getDisplayTitle(context),
              value: val,
              gradient: card.gradient,
              subtitleIcon: Icons.insights_rounded,
              subtitle: card.getDisplaySubtitle(context),
              isDark: isDark,
              onTap: () => widget.onNavigate?.call(card.targetModule),
              onCustomize: () => _openCustomizeDialog(context, state),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = context.watch<AuthBloc>().state;
    final userName = authState is AuthAuthenticated ? authState.fullName : 'User';

    final now = DateTime.now();
    final langCode = Localizations.localeOf(context).languageCode;
    final gregorian = AppDateHelper.formatGregorian(now, langCode);
    final timeOfDay = now.hour < 12
        ? context.tr('good_morning')
        : now.hour < 17
            ? context.tr('good_afternoon')
            : context.tr('good_evening');

    return BlocBuilder<HijriCubit, HijriState>(
      builder: (context, hijriState) {
        final hijriStr = AppDateHelper.formatHijri(
          now,
          langCode,
          adjustment: hijriState.adjustment,
        );

        return BlocBuilder<DashboardBloc, DashboardState>(
          builder: (context, state) {
            int hostelOccupiedBeds = 0;
            int hostelTotalBeds = 0;
            int kitchenLowStock = 0;
            int generalLowStock = 0;
            List<dynamic> recentActivity = [];
            bool isLoading = state is DashboardLoading;

            if (state is DashboardLoaded) {
              hostelOccupiedBeds = state.hostelOccupiedBeds;
              hostelTotalBeds = state.hostelTotalBeds;
              kitchenLowStock = state.kitchenLowStock;
              generalLowStock = state.generalLowStock;
              recentActivity = state.recentActivity;
            }

            return RefreshIndicator(
              onRefresh: () async {
                context.read<DashboardBloc>().add(LoadDashboardData());
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero Banner ──────────────────────────────────────
                    RepaintBoundary(
                      child: _HeroBanner(
                        isDark: isDark,
                        userName: userName,
                        gregorian: gregorian,
                        hijriStr: hijriStr,
                        timeOfDay: timeOfDay,
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 28),

                          if (isLoading)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else if (state is DashboardLoaded) ...[
                            // ── DYNAMIC SECTION 1: STUDENT & STAFF ANALYTICS SIDE BY SIDE ──
                            RepaintBoundary(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final availableWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 800.0;
                                  final isDesktop = availableWidth >= 960;

                                  if (isDesktop) {
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Left half: Student Analytics & Overview
                                        Expanded(
                                          child: DashboardStudentAnalyticsWidget(
                                            isDark: isDark,
                                            totalStudentsFallback: state.totalStudents,
                                            attendancePercentageFallback: state.attendancePercentage,
                                            onNavigate: widget.onNavigate,
                                            fixedHeight: 330,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        // Right half: Staff Analytics & Overview
                                        Expanded(
                                          child: DashboardStaffAnalyticsWidget(
                                            isDark: isDark,
                                            totalStaffFallback: state.totalStaff,
                                            onNavigate: widget.onNavigate,
                                            fixedHeight: 330,
                                          ),
                                        ),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        DashboardStudentAnalyticsWidget(
                                          isDark: isDark,
                                          totalStudentsFallback: state.totalStudents,
                                          attendancePercentageFallback: state.attendancePercentage,
                                          onNavigate: widget.onNavigate,
                                          fixedHeight: 330,
                                        ),
                                        const SizedBox(height: 22),
                                        DashboardStaffAnalyticsWidget(
                                          isDark: isDark,
                                          totalStaffFallback: state.totalStaff,
                                          onNavigate: widget.onNavigate,
                                          fixedHeight: 330,
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 22),

                            // ── SECTION 2: FINANCIAL LEDGER & ACCOUNTS ──
                            RepaintBoundary(
                              child: _buildDynamicSection(
                                title: context.tr('financial_ledger_and_accounts'),
                                category: 'Finance',
                                state: state,
                                isDark: isDark,
                              ),
                            ),

                            // ── SECTION 3: ACADEMIC & CURRICULUM ──
                            RepaintBoundary(
                              child: _buildDynamicSection(
                                title: context.tr('academic_and_curriculum'),
                                category: 'Academic',
                                state: state,
                                isDark: isDark,
                              ),
                            ),


                            // ── SECTION 3: FACILITIES & INVENTORY ──────────────
                            RepaintBoundary(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _SectionLabel(
                                    label: context.tr('facilities_resource_alerts'),
                                    isDark: isDark,
                                  ),
                                  const SizedBox(height: 14),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isSmall = constraints.maxWidth < 800;
                                      return GridView.count(
                                        crossAxisCount: isSmall ? 1 : 3,
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                        childAspectRatio: isSmall ? 2.5 : 2.0,
                                        children: [
                                          // Hostel occupancy progress card
                                          _HostelProgressCard(
                                            occupied: hostelOccupiedBeds,
                                            total: hostelTotalBeds,
                                            isDark: isDark,
                                            onTap: () => widget.onNavigate?.call('hostel'),
                                          ),
                                          // Kitchen stock alert card
                                          _InventoryAlertCard(
                                            title: context.tr('kitchen_ration_inventory'),
                                            lowCount: kitchenLowStock,
                                            icon: Icons.restaurant_menu_rounded,
                                            color: Colors.orange,
                                            isDark: isDark,
                                            onTap: () => widget.onNavigate?.call('kitchen'),
                                          ),
                                          // General stock alert card
                                          _InventoryAlertCard(
                                            title: context.tr('general_stock_inventory'),
                                            lowCount: generalLowStock,
                                            icon: Icons.inventory_2_rounded,
                                            color: Colors.teal,
                                            isDark: isDark,
                                            onTap: () => widget.onNavigate?.call('kitchen'),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 32),

                          // ── Quick Actions ────────────────────────────
                          RepaintBoundary(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionLabel(
                                  label: context.tr('quick_actions'),
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 14),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final crossAxisCount = constraints.maxWidth < 600
                                        ? 2
                                        : constraints.maxWidth < 900
                                            ? 3
                                            : 4;
                                    return GridView.count(
                                      crossAxisCount: crossAxisCount,
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio: 2.4,
                                      children: [
                                        _QuickAction(
                                          icon: Icons.person_add_alt_1_rounded,
                                          label: context.tr('add_student'),
                                          color: const Color(0xFF0D6B4E),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('students'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.how_to_reg_rounded,
                                          label: context.tr('attendance'),
                                          color: const Color(0xFFE65100),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('attendance'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.payments_rounded,
                                          label: context.tr('collect_fee'),
                                          color: const Color(0xFF1565C0),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('fees'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.hotel_rounded,
                                          label: context.tr('hostel_rooms'),
                                          color: const Color(0xFF6A1B9A),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('hostel'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.kitchen_rounded,
                                          label: context.tr('ration_and_stock'),
                                          color: const Color(0xFF00838F),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('kitchen'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.bar_chart_rounded,
                                          label: context.tr('reports'),
                                          color: const Color(0xFF558B2F),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('reports'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.school_rounded,
                                          label: context.tr('exam_results'),
                                          color: const Color(0xFFC62828),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('exams'),
                                        ),
                                        _QuickAction(
                                          icon: Icons.settings_rounded,
                                          label: context.tr('settings'),
                                          color: const Color(0xFF455A64),
                                          isDark: isDark,
                                          onTap: () => widget.onNavigate?.call('settings'),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ── Recent Activity ──────────────────────────
                          RepaintBoundary(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _SectionLabel(
                                      label: context.tr('recent_activity'),
                                      isDark: isDark,
                                    ),
                                    TextButton.icon(
                                      onPressed: () {},
                                      icon: Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                        color: AppTheme.primaryColor,
                                      ),
                                      label: Text(
                                        context.tr('view_all'),
                                        style: AppTheme.getFontStyle(
                                          color: AppTheme.primaryColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                if (recentActivity.isEmpty)
                                  _EmptyActivity(isDark: isDark)
                                else
                                  _ActivityFeed(
                                    activities: recentActivity,
                                    isDark: isDark,
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
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
}

// ── RESPONSIVE GRID WRAPPER ──────────────────────────────────────────────────
class _ResponsiveStatsGrid extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  final int? overrideCrossAxisCount;

  const _ResponsiveStatsGrid({
    required this.children,
    required this.isDark,
    this.overrideCrossAxisCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 800.0;
        
        // More columns on desktop so cards are compact in width (~200px - 230px each)
        int crossAxisCount;
        if (overrideCrossAxisCount != null && availableWidth >= 550) {
          crossAxisCount = overrideCrossAxisCount!;
        } else if (availableWidth < 450) {
          crossAxisCount = 1;
        } else if (availableWidth < 680) {
          crossAxisCount = 2;
        } else if (availableWidth < 920) {
          crossAxisCount = 3;
        } else if (availableWidth < 1180) {
          crossAxisCount = 4;
        } else if (availableWidth < 1440) {
          crossAxisCount = 5;
        } else {
          crossAxisCount = 6;
        }

        const spacing = 12.0;
        final totalSpacing = spacing * (crossAxisCount - 1);
        final cardWidth = (availableWidth - totalSpacing) / crossAxisCount;

        // Target compact card height: 110px ensures zero overflow and snug zero-gap fit
        const targetHeight = 110.0;
        final childAspectRatio = (cardWidth > 0 && targetHeight > 0)
            ? (cardWidth / targetHeight)
            : 2.0;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: childAspectRatio,
          children: children,
        );
      },
    );
  }
}

// ── Hero Banner ──────────────────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  final bool isDark;
  final String userName;
  final String gregorian;
  final String hijriStr;
  final String timeOfDay;

  const _HeroBanner({
    required this.isDark,
    required this.userName,
    required this.gregorian,
    required this.hijriStr,
    required this.timeOfDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF043927), Color(0xFF065f46), Color(0xFF0D9669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF043927).withAlpha(120),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -60,
            top: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withAlpha(isDark ? 8 : 18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -40,
            bottom: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD700).withAlpha(isDark ? 15 : 25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.06,
              child: const Icon(
                Icons.mosque_rounded,
                size: 200,
                color: Colors.white,
              ),
            ),
          ),
          Positioned.fill(
            child: const RepaintBoundary(
              child: CustomPaint(painter: _PatternPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 2, 28, 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 840;

                final greetingWidget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withAlpha(30),
                            border: Border.all(
                              color: Colors.white.withAlpha(70),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                timeOfDay,
                                style: AppTheme.getFontStyle(
                                  fontSize: 15,
                                  color: Colors.white.withAlpha(200),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                userName,
                                style: AppTheme.getFontStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('welcome_subtitle'),
                      style: AppTheme.getFontStyle(
                        fontSize: 14,
                        color: Colors.white.withAlpha(170),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );

                if (isDesktop) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: greetingWidget,
                      ),
                      const SizedBox(width: 16),
                      // Integrated Watch, Dates, Salat & Weather (Fits in original banner size!)
                      DashboardWatchWeatherWidget(
                        isDark: isDark,
                        hijriDate: hijriStr,
                      ),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      greetingWidget,
                      const SizedBox(height: 14),
                      Center(
                        child: DashboardWatchWeatherWidget(
                          isDark: isDark,
                          hijriDate: hijriStr,
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Label ────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  final Widget? action;
  const _SectionLabel({required this.label, required this.isDark, this.action});

  @override
  Widget build(BuildContext context) {
    final titleWidget = Row(
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
        Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            letterSpacing: -0.3,
          ),
        ),
      ],
    );

    if (action != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          titleWidget,
          action!,
        ],
      );
    }

    return titleWidget;
  }
}

// ── Stat Card ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final LinearGradient gradient;
  final IconData subtitleIcon;
  final String subtitle;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onCustomize;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    required this.subtitleIcon,
    required this.subtitle,
    required this.isDark,
    this.onTap,
    this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = gradient.colors.first;
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: gradient,
            boxShadow: [
              BoxShadow(
                color: cardColor.withAlpha(60),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -10,
                bottom: -12,
                child: Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(15),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onCustomize != null)
                      IconButton(
                        icon: const Icon(Icons.edit_note_rounded, color: Colors.white70, size: 19),
                        tooltip: context.tr('customize_edit_card'),
                        onPressed: onCustomize,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      ),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(25),
                      ),
                      child: Icon(icon, color: Colors.white, size: 17),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 58),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              style: AppTheme.getFontStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            color: Colors.white.withAlpha(220),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              subtitleIcon,
                              size: 11,
                              color: Colors.white.withAlpha(160),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                subtitle,
                                style: AppTheme.getFontStyle(
                                  fontSize: 11,
                                  color: Colors.white.withAlpha(160),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

// ── HOSTEL OCCUPANCY PROGRESS CARD ───────────────────────────────────────────
class _HostelProgressCard extends StatelessWidget {
  final int occupied;
  final int total;
  final bool isDark;
  final VoidCallback onTap;

  const _HostelProgressCard({
    required this.occupied,
    required this.total,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double percent = total > 0 ? (occupied / total) : 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade100,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 25 : 6),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.purple.withAlpha(isDark ? 40 : 18),
                  ),
                  child: const Icon(Icons.hotel_rounded, color: Colors.purple, size: 20),
                ),
                Text(
                  context.tr('hostel_stays'),
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$occupied / $total ${context.tr('beds')}',
              style: AppTheme.getFontStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 8,
                backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                color: Colors.purple,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(percent * 100).toStringAsFixed(0)}% ${context.tr('occupancy_rate')}',
                  style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                ),
                Icon(Icons.arrow_right_alt_rounded, size: 16, color: Colors.purple.shade600),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── INVENTORY ALERT CARD ─────────────────────────────────────────────────────
class _InventoryAlertCard extends StatelessWidget {
  final String title;
  final int lowCount;
  final IconData icon;
  final MaterialColor color;
  final bool isDark;
  final VoidCallback onTap;

  const _InventoryAlertCard({
    required this.title,
    required this.lowCount,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlert = lowCount > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasAlert 
                ? Colors.redAccent.withAlpha(isDark ? 80 : 120)
                : isDark ? Colors.white.withAlpha(12) : Colors.grey.shade100,
            width: hasAlert ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: hasAlert 
                  ? Colors.redAccent.withAlpha(isDark ? 10 : 8)
                  : Colors.black.withAlpha(isDark ? 25 : 6),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: color.withAlpha(isDark ? 40 : 18),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Text(
                  title,
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasAlert ? '$lowCount ${context.tr('items_low')}' : context.tr('all_items_safe'),
              style: AppTheme.getFontStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: hasAlert 
                    ? Colors.redAccent 
                    : isDark ? Colors.green.shade400 : Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasAlert 
                    ? Colors.redAccent.withAlpha(30) 
                    : Colors.green.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasAlert ? Colors.redAccent : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasAlert ? context.tr('needs_attention') : context.tr('healthy_inventory'),
                    style: AppTheme.getFontStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasAlert ? Colors.redAccent : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ── Quick Action ─────────────────────────────────────────────────────────────
class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: RepaintBoundary(
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: widget.isDark ? const Color(0xFF1E1E2E) : Colors.white,
              border: Border.all(
                color: widget.isDark ? Colors.white.withAlpha(12) : Colors.grey.shade100,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withAlpha(widget.isDark ? 20 : 15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(widget.isDark ? 30 : 6),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: widget.color.withAlpha(widget.isDark ? 40 : 22),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.label,
                            style: AppTheme.getFontStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.isDark ? Colors.white.withAlpha(220) : const Color(0xFF1A1A2E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: widget.isDark ? Colors.white.withAlpha(60) : Colors.grey.shade300,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty Activity ───────────────────────────────────────────────────────────
class _EmptyActivity extends StatelessWidget {
  final bool isDark;
  const _EmptyActivity({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade50,
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withAlpha(15),
            ),
            child: Icon(
              Icons.history_toggle_off_rounded,
              size: 32,
              color: AppTheme.primaryColor.withAlpha(120),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('no_recent_activity'),
            style: AppTheme.getFontStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('actions_will_appear_here'),
            style: AppTheme.getFontStyle(
              fontSize: 13,
              color: isDark ? Colors.white30 : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity Feed ────────────────────────────────────────────────────────────
class _ActivityFeed extends StatelessWidget {
  final List<dynamic> activities;
  final bool isDark;
  const _ActivityFeed({required this.activities, required this.isDark});

  IconData _iconForAction(String? action) {
    final a = (action ?? '').toLowerCase();
    if (a.contains('add') || a.contains('creat')) return Icons.add_circle_outline_rounded;
    if (a.contains('update') || a.contains('edit')) return Icons.edit_note_rounded;
    if (a.contains('delete') || a.contains('remov')) return Icons.delete_outline_rounded;
    if (a.contains('fee') || a.contains('pay')) return Icons.payments_rounded;
    if (a.contains('attend')) return Icons.fact_check_rounded;
    return Icons.flash_on_rounded;
  }

  Color _colorForAction(String? action) {
    final a = (action ?? '').toLowerCase();
    if (a.contains('add') || a.contains('creat')) return const Color(0xFF0D6B4E);
    if (a.contains('update') || a.contains('edit')) return const Color(0xFF1565C0);
    if (a.contains('delete') || a.contains('remov')) return const Color(0xFFC62828);
    if (a.contains('fee') || a.contains('pay')) return const Color(0xFF6A1B9A);
    if (a.contains('attend')) return const Color(0xFFE65100);
    return AppTheme.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 25 : 6),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade100,
        ),
        itemBuilder: (context, index) {
          final activity = activities[index];
          final action = activity['action'] as String?;
          final color = _colorForAction(action);
          final icon = _iconForAction(action);
          final timeStr = activity['created_at']?.toString().split(' ').last ?? '';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withAlpha(isDark ? 40 : 18),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action ?? 'Activity',
                        style: AppTheme.getFontStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if ((activity['details'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          activity['details'] ?? '',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timeStr,
                    style: AppTheme.getFontStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Decorative Pattern Painter ───────────────────────────────────────────────
class _PatternPainter extends CustomPainter {
  const _PatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;
    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint..style = PaintingStyle.fill);
        if (x + spacing / 2 < size.width && y + spacing / 2 < size.height) {
          canvas.drawCircle(
            Offset(x + spacing / 2, y + spacing / 2),
            1.5,
            paint..style = PaintingStyle.fill,
          );
        }
      }
    }

    final arcPaint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 3; i++) {
      final radius = 80.0 + i * 50;
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width * 0.75, -20),
          radius: radius,
        ),
        math.pi * 0.3,
        math.pi * 1.2,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

