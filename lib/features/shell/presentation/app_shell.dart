import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_cubit.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/branding/app_branding.dart';
import '../../../core/branding/app_branding_cubit.dart';
import '../../../shared/widgets/app_logo_widget.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../../auth/presentation/bloc/auth_event.dart';
import '../../auth/presentation/bloc/auth_state.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../dashboard/data/repositories/dashboard_repository.dart';
import '../../dashboard/presentation/bloc/dashboard_bloc.dart';
import '../../dashboard/presentation/bloc/dashboard_event.dart';
import '../../students/presentation/screens/students_screen.dart';
import '../../students/presentation/bloc/students_bloc.dart';
import '../../students/data/repositories/student_repository.dart';
import '../../staff/presentation/bloc/staff_bloc.dart';
import '../../staff/presentation/screens/staff_screen.dart';
import '../../staff/data/repositories/staff_repository.dart';
import '../../users/presentation/bloc/users_bloc.dart';
import '../../users/presentation/screens/users_screen.dart';
import '../../roles_permissions/presentation/bloc/roles_bloc.dart';
import '../../roles_permissions/presentation/screens/roles_screen.dart';
import '../../settings/presentation/screens/settings_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../reports/data/repositories/reports_repository.dart';
import '../../reports/presentation/bloc/reports_bloc.dart';
import '../../classes/presentation/classes_screen.dart';
import '../../exams/presentation/screens/exams_screen.dart';
import '../../exams/presentation/bloc/exam_bloc.dart';
import '../../exams/data/repositories/exam_local_repository.dart';
import '../../attendance/presentation/bloc/attendance_bloc.dart';
import '../../attendance/presentation/screens/attendance_screen.dart';
import '../../attendance/data/repositories/attendance_repository.dart';
import '../../fees/presentation/screens/fees_screen.dart';
import '../../fees/presentation/bloc/fees_bloc.dart';
import '../../fees/data/repositories/fees_repository.dart';
import '../../kitchen/presentation/screens/kitchen_screen.dart';
import '../../kitchen/presentation/bloc/kitchen_bloc.dart';
import '../../kitchen/data/repositories/kitchen_repository.dart';
import '../../purchases/presentation/screens/purchases_screen.dart';
import '../../purchases/presentation/bloc/purchases_bloc.dart';
import '../../purchases/data/repositories/purchases_repository.dart';
import '../../hostel/presentation/screens/hostel_screen.dart';
import '../../hostel/presentation/bloc/hostel_bloc.dart';
import '../../hostel/data/repositories/hostel_repository.dart';
import '../../library/presentation/screens/library_screen.dart';
import '../../library/presentation/bloc/library_bloc.dart';
import '../../library/data/repositories/library_repository.dart';
import '../../contributors/presentation/screens/contributors_screen.dart';
import '../../contributors/presentation/bloc/contributors_bloc.dart';
import '../../contributors/data/repositories/contributor_repository.dart';
import '../../../core/network/api_client.dart';
import '../../../core/licensing/license_cubit.dart';
import '../../../core/licensing/license_model.dart';
import '../../licensing/presentation/upgrade_plan_dialog.dart';
import '../../../core/services/app_update_service.dart';
import '../../settings/presentation/widgets/app_update_dialog.dart';
import '../../card_designer/presentation/screens/card_designer_screen.dart';
import '../../../core/shortcuts/app_keyboard_shortcuts.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  late final ExamBloc _examBloc;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _examBloc = ExamBloc(ExamLocalRepository());
    _checkForUpdatesSilently();
  }

  Future<void> _checkForUpdatesSilently() async {
    final autoCheck = await AppUpdateService.isAutoCheckEnabled();
    if (!autoCheck) return;

    // Wait 3 seconds for UI to settle
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      final info = await AppUpdateService.checkForUpdate();
      if (info != null && info.hasUpdate && mounted) {
        AppUpdateDialog.show(context, info);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _examBloc.close();
    super.dispose();
  }

  // Navigation items with their modules for permission checking
  static const List<_NavItem> _navItems = [
    _NavItem(
      icon: Icons.dashboard_rounded,
      label: 'dashboard',
      module: 'dashboard',
      category: 'Main',
    ),

    // Academic Section
    _NavItem(
      icon: Icons.school_rounded,
      label: 'students',
      module: 'students',
      category: 'Academic',
    ),
    _NavItem(
      icon: Icons.badge_rounded,
      label: 'staff',
      module: 'staff',
      category: 'Academic',
    ),
    _NavItem(
      icon: Icons.class_rounded,
      label: 'classes',
      module: 'classes',
      category: 'Academic',
    ),
    _NavItem(
      icon: Icons.quiz_rounded,
      label: 'exams',
      module: 'exams',
      category: 'Academic',
    ),
    _NavItem(
      icon: Icons.style_rounded,
      label: 'card_designer',
      module: 'card_designer',
      category: 'Academic',
    ),

    // Management Section
    _NavItem(
      icon: Icons.people_rounded,
      label: 'staff',
      module: 'staff',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.fact_check_rounded,
      label: 'attendance',
      module: 'attendance',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.payments_rounded,
      label: 'fees',
      module: 'fees',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.analytics_rounded,
      label: 'kitchen',
      module: 'kitchen',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.shopping_bag_rounded,
      label: 'purchases',
      module: 'purchases',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.hotel_rounded,
      label: 'hostel',
      module: 'hostel',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.local_library_rounded,
      label: 'library',
      module: 'library',
      category: 'Management',
    ),
    _NavItem(
      icon: Icons.volunteer_activism_rounded,
      label: 'contributors',
      module: 'contributors',
      category: 'Management',
    ),

    // System Section
    _NavItem(
      icon: Icons.bar_chart_rounded,
      label: 'reports',
      module: 'reports',
      category: 'System',
    ),
    _NavItem(
      icon: Icons.admin_panel_settings_rounded,
      label: 'roles',
      module: 'roles',
      category: 'System',
    ),
    _NavItem(
      icon: Icons.manage_accounts_rounded,
      label: 'users',
      module: 'users',
      category: 'System',
    ),
    _NavItem(
      icon: Icons.settings_rounded,
      label: 'settings',
      module: 'settings',
      category: 'System',
    ),
  ];

  List<_NavItem> _getVisibleItems(AuthAuthenticated authState) {
    return _navItems.where((item) {
      if (item.module == 'dashboard' || item.module == 'card_designer') return true;
      return authState.hasPermission(item.module, 'view');
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > Breakpoints.tablet;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = context.watch<AuthBloc>().state;

    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final visibleItems = _getVisibleItems(authState);
    if (visibleItems.isEmpty) {
      return _buildNoAccessScaffold(isDark);
    }
    if (_selectedIndex >= visibleItems.length) {
      _selectedIndex = 0;
    }
    final currentItem = visibleItems[_selectedIndex];

    return AppKeyboardShortcuts(
      searchFocusNode: _searchFocusNode,
      onNavigateIndex: (index) {
        if (index >= 0 && index < visibleItems.length) {
          setState(() => _selectedIndex = index);
        }
      },
      onNavigateModule: (module) {
        final idx = visibleItems.indexWhere((i) => i.module == module);
        if (idx != -1) {
          setState(() => _selectedIndex = idx);
        }
      },
      onRefresh: () {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refreshed / ریفریش کر دیا گیا'),
            duration: Duration(milliseconds: 900),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onToggleTheme: () => context.read<ThemeCubit>().toggleTheme(),
      onToggleLanguage: () {
        final currentLocale = context.read<LocaleCubit>().state.locale.languageCode;
        final codes = ['en', 'ur', 'hi', 'gu'];
        final nextIndex = (codes.indexOf(currentLocale) + 1) % codes.length;
        context.read<LocaleCubit>().changeLocale(codes[nextIndex]);
      },
      onCheckUpdates: () async {
        final navContext = context;
        try {
          final info = await AppUpdateService.checkForUpdate();
          if (info != null && navContext.mounted) {
            AppUpdateDialog.show(navContext, info);
          }
        } catch (_) {}
      },
      child: Scaffold(
        body: Row(
          children: [
            // Sidebar for desktop
            if (isDesktop) _buildSidebar(isDark, visibleItems, authState),
            // Main Content
            Expanded(
              child: Column(
                children: [
                  if (isDesktop) _buildTopBar(isDark, authState, currentItem),
                  Expanded(child: _buildContent(visibleItems)),
                ],
              ),
            ),
          ],
        ),
        // Bottom Nav for mobile
        bottomNavigationBar: isDesktop
            ? null
            : _buildBottomNav(isDark, visibleItems),
      ),
    );
  }

  Widget _buildNoAccessScaffold(bool isDark) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                'No modules assigned',
                style: AppTheme.getFontStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your account is active but no dashboard modules are currently enabled for your roles.',
                textAlign: TextAlign.center,
                style: AppTheme.getFontStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () =>
                    context.read<AuthBloc>().add(AuthLogoutRequested()),
                icon: const Icon(Icons.logout_rounded),
                label: Text(context.tr('logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(
    bool isDark,
    List<_NavItem> items,
    AuthAuthenticated authState,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 260,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12121F) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 10),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Brand Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withAlpha(220),
                ],
              ),
            ),
            child: Row(
              children: [
                const AppLogoWidget(
                  size: 42,
                  iconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BlocBuilder<AppBrandingCubit, AppBranding>(
                    builder: (context, branding) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            branding.appNameUrdu,
                            style: AppTheme.getFontStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            branding.appNameEnglish,
                            style: AppTheme.getFontStyle(
                              fontSize: 11,
                              color: Colors.white.withAlpha(180),
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              children: _buildGroupedNav(items, isDark),
            ),
          ),
          // User Info at bottom
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryColor.withAlpha(30),
                  child: Text(
                    authState.fullName.isNotEmpty ? authState.fullName[0].toUpperCase() : 'A',
                    style: AppTheme.getFontStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authState.fullName,
                        style: AppTheme.getFontStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        authState.primaryRoleName,
                        style: AppTheme.getFontStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                  onPressed: () => _showLogoutDialog(),
                  tooltip: context.tr('logout'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    bool isDark,
    AuthAuthenticated authState,
    _NavItem currentItem,
  ) {
    final isDesktop = MediaQuery.of(context).size.width > Breakpoints.tablet;
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161625) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          // Page Title
          Text(
            context.tr(currentItem.label),
            style: AppTheme.getFontStyle(
              fontSize: isDesktop ? 20 : 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          const Spacer(),
          // Search
          if (isDesktop) ...[
            Container(
              width: 220,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFF0F2F5),
              ),
              child: TextField(
                focusNode: _searchFocusNode,
                style: AppTheme.getFontStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '${context.tr('search')} (Ctrl+F)',
                  hintStyle: AppTheme.getFontStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Active Subscription / License Pill
          Builder(
            builder: (ctx) {
              final licState = ctx.watch<LicenseCubit>().state;
              final license = licState is LicenseLoaded
                  ? licState.license
                  : AppLicense.defaultTrial();
              final tier = license.tier;
              final text = license.isLifetime
                  ? '⭐ LIFETIME'
                  : (license.isExpired
                      ? '⚠️ EXPIRED'
                      : '${tier.displayName.toUpperCase()} (${license.daysRemaining}d)');
              return Tooltip(
                message: 'Click to view subscription / upgrade plan',
                child: InkWell(
                  onTap: () => UpgradePlanDialog.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: tier.color.withAlpha(isDark ? 40 : 25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tier.color.withAlpha(120),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tier.icon, size: 14, color: tier.color),
                        const SizedBox(width: 5),
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: tier.color,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          if (isDesktop) ...[
            // Theme Toggle
            IconButton(
              icon: Icon(
                context.watch<ThemeCubit>().isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                size: 20,
              ),
              onPressed: () => context.read<ThemeCubit>().toggleTheme(),
              tooltip: context.tr('dark_mode'),
            ),
            // Language Selector
            PopupMenuButton<String>(
              icon: const Icon(Icons.language_rounded, size: 20),
              tooltip: context.tr('language'),
              onSelected: (code) {
                context.read<LocaleCubit>().changeLocale(code);
              },
              itemBuilder: (context) {
                return LocaleCubit.supportedLanguages.map((lang) {
                  return PopupMenuItem(
                    value: lang['code'],
                    child: Text(
                      '${lang['nativeName']} (${lang['name']})',
                      style: AppTheme.getFontStyle(fontSize: 14),
                    ),
                  );
                }).toList();
              },
            ),
            // Keyboard Shortcuts Guide
            IconButton(
              icon: Icon(
                Icons.keyboard_outlined,
                size: 20,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              onPressed: () => KeyboardShortcutsDialog.show(context),
              tooltip: 'Keyboard Shortcuts (F1 / Ctrl+/)',
            ),
            // Notifications
            IconButton(
              icon: Badge(
                smallSize: 8,
                backgroundColor: AppTheme.errorColor,
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 20,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              onPressed: () {},
              tooltip: context.tr('notifications'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomNav(bool isDark, List<_NavItem> items) {
    // Show max 5 items in bottom nav
    final bottomItems = items.length > 5 ? items.sublist(0, 5) : items;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161625) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex < bottomItems.length ? _selectedIndex : 0,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: isDark
            ? AppTheme.primaryLight
            : AppTheme.primaryColor,
        unselectedItemColor: isDark
            ? Colors.grey.shade600
            : Colors.grey.shade500,
        selectedLabelStyle: AppTheme.getFontStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTheme.getFontStyle(fontSize: 10),
        items: bottomItems.map((item) {
          return BottomNavigationBarItem(
            icon: Icon(item.icon),
            label: context.tr(item.label),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContent(List<_NavItem> items) {
    if (_selectedIndex >= items.length) return const SizedBox();

    final currentItem = items[_selectedIndex];
    final licenseState = context.watch<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded
        ? licenseState.license
        : AppLicense.defaultTrial();

    if (!license.hasModuleAccess(currentItem.module)) {
      return _buildLockedModuleView(currentItem, license);
    }

    switch (currentItem.module) {
      case 'dashboard':
        return BlocProvider(
          create: (context) =>
              DashboardBloc(repository: DashboardRepository(ApiClient()))
                ..add(LoadDashboardData()),
          child: DashboardScreen(
            onNavigate: (module) {
              final idx = items.indexWhere((i) => i.module == module);
              if (idx != -1) setState(() => _selectedIndex = idx);
            },
          ),
        );
      case 'students':
        return BlocProvider(
          create: (context) =>
              StudentsBloc(repository: StudentRepository(ApiClient())),
          child: const StudentsScreen(),
        );
      case 'staff':
        return BlocProvider(
          create: (context) =>
              StaffBloc(repository: StaffRepository(ApiClient()))
                ..add(LoadStaff()),
          child: const StaffScreen(),
        );
      case 'users':
        return BlocProvider(
          create: (context) => UsersBloc(),
          child: const UsersScreen(),
        );
      case 'roles':
        return BlocProvider(
          create: (context) => RolesBloc(),
          child: const RolesScreen(),
        );
      case 'classes':
        return const ClassesScreen();
      case 'exams':
        return BlocProvider.value(value: _examBloc, child: const ExamsScreen());
      case 'attendance':
        return BlocProvider(
          create: (context) =>
              AttendanceBloc(repository: AttendanceRepository(ApiClient())),
          child: const AttendanceScreen(),
        );
      case 'fees':
        return BlocProvider(
          create: (context) => FeesBloc(repository: FeesRepository(ApiClient())),
          child: const FeesScreen(),
        );
      case 'kitchen':
        return MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) => KitchenBloc(repository: KitchenRepository(ApiClient())),
            ),
            BlocProvider(
              create: (context) => PurchasesBloc(repository: PurchasesRepository(ApiClient()))..add(LoadPurchasesData()),
            ),
          ],
          child: const KitchenScreen(),
        );
      case 'purchases':
        return BlocProvider(
          create: (context) => PurchasesBloc(repository: PurchasesRepository(ApiClient())),
          child: const PurchasesScreen(),
        );
      case 'hostel':
        return BlocProvider(
          create: (context) => HostelBloc(
            repository: HostelRepository(ApiClient()),
          )..add(LoadHostelData()),
          child: const HostelScreen(),
        );
      case 'library':
        return BlocProvider(
          create: (context) => LibraryBloc(
            repository: LibraryRepository(ApiClient()),
          )..add(LoadLibraryData()),
          child: const LibraryScreen(),
        );
      case 'contributors':
        return BlocProvider(
          create: (context) => ContributorsBloc(
            repository: ContributorRepository(ApiClient()),
          )..add(LoadContributors()),
          child: const ContributorsScreen(),
        );
      case 'settings':
        return const SettingsScreen();
      case 'reports':
        return BlocProvider(
          create: (context) => ReportsBloc(ReportsRepository(ApiClient())),
          child: const ReportsScreen(),
        );
      case 'card_designer':
        return const CardDesignerScreen();
      default:
        return _buildPlaceholder(currentItem);
    }
  }

  Widget _buildPlaceholder(_NavItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDark ? AppTheme.primaryLight : AppTheme.primaryColor)
                  .withAlpha(20),
            ),
            child: Icon(
              item.icon,
              size: 40,
              color: isDark ? AppTheme.primaryLight : AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr(item.label),
            style: AppTheme.getFontStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('module_available_soon'),
            style: AppTheme.getFontStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedModuleView(_NavItem item, AppLicense license) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final minTier = AppLicense.minimumTierForModule(item.module);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: minTier.color.withAlpha(isDark ? 40 : 25),
                shape: BoxShape.circle,
                border: Border.all(color: minTier.color.withAlpha(100), width: 1.5),
              ),
              child: Icon(Icons.lock_rounded, size: 44, color: minTier.color),
            ),
            const SizedBox(height: 20),
            Text(
              '${context.tr(item.label)} is Locked',
              style: AppTheme.getFontStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This module requires an active ${minTier.displayName} or Lifetime License. Upgrade now to unlock full access.',
              textAlign: TextAlign.center,
              style: AppTheme.getFontStyle(
                fontSize: 13.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => UpgradePlanDialog.show(context, highlightModule: item.label),
              icon: const Icon(Icons.stars_rounded, size: 18),
              label: Text('Upgrade to ${minTier.displayName}'),
              style: FilledButton.styleFrom(
                backgroundColor: minTier.color,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('logout'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: AppTheme.getFontStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthBloc>().add(AuthLogoutRequested());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: Text(context.tr('logout')),
          ),
        ],
      ),
    );
  }
  List<Widget> _buildGroupedNav(List<_NavItem> items, bool isDark) {
    final licenseState = context.watch<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded
        ? licenseState.license
        : AppLicense.defaultTrial();

    String currentCategory = '';
    final List<Widget> grouped = [];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final isLocked = !license.hasModuleAccess(item.module);
      final minTier = AppLicense.minimumTierForModule(item.module);

      if (item.category != currentCategory) {
        currentCategory = item.category;
        grouped.add(
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 16, bottom: 8),
            child: Text(
              context.tr(currentCategory.toLowerCase()).toUpperCase(),
              style: AppTheme.getFontStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                letterSpacing: 1.5,
              ),
            ),
          ),
        );
      }

      final isSelected = _selectedIndex == i;
      grouped.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (isLocked) {
                  UpgradePlanDialog.show(context, highlightModule: item.label);
                } else {
                  setState(() => _selectedIndex = i);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isSelected
                      ? (isDark
                            ? AppTheme.primaryLight.withAlpha(25)
                            : AppTheme.primaryColor.withAlpha(15))
                      : Colors.transparent,
                  border: isSelected
                      ? Border.all(
                          color: isDark
                              ? AppTheme.primaryLight.withAlpha(40)
                              : AppTheme.primaryColor.withAlpha(30),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 20,
                      color: isLocked
                          ? (isDark ? Colors.grey.shade600 : Colors.grey.shade400)
                          : (isSelected
                              ? (isDark
                                    ? AppTheme.primaryLight
                                    : AppTheme.primaryColor)
                              : (isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade600)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr(item.label),
                        style: AppTheme.getFontStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isLocked
                              ? (isDark ? Colors.grey.shade500 : Colors.grey.shade600)
                              : (isSelected
                                  ? (isDark
                                        ? AppTheme.primaryLight
                                        : AppTheme.primaryColor)
                                  : (isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade700)),
                        ),
                      ),
                    ),
                    if (isLocked) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: minTier.color.withAlpha(isDark ? 40 : 20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: minTier.color.withAlpha(90), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded, size: 10, color: minTier.color),
                            const SizedBox(width: 2.5),
                            Text(
                              minTier.displayName.split(' ').first.toUpperCase(),
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: minTier.color,
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
          ),
        ),
      );
    }
    return grouped;
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String module;
  final String category;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.module,
    required this.category,
  });
}
