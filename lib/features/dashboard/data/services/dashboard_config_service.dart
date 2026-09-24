import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../presentation/bloc/dashboard_state.dart';

class DashboardCardConfig {
  final String id;
  final String defaultTitle;
  String? customTitle;
  final String defaultSubtitle;
  String? customSubtitle;
  final String category;
  final IconData icon;
  final List<Color> gradientColors;
  final String targetModule;
  bool isVisible;
  int order;

  DashboardCardConfig({
    required this.id,
    required this.defaultTitle,
    this.customTitle,
    required this.defaultSubtitle,
    this.customSubtitle,
    required this.category,
    required this.icon,
    required this.gradientColors,
    required this.targetModule,
    this.isVisible = true,
    this.order = 0,
  });

  String get title => (customTitle != null && customTitle!.trim().isNotEmpty)
      ? customTitle!.trim()
      : defaultTitle;

  String get subtitle => (customSubtitle != null && customSubtitle!.trim().isNotEmpty)
      ? customSubtitle!.trim()
      : defaultSubtitle;

  String getDisplayTitle(BuildContext context) {
    if (customTitle != null && customTitle!.trim().isNotEmpty) {
      return customTitle!.trim();
    }
    final key = 'card_title_$id';
    final localized = context.tr(key);
    return (localized.isNotEmpty && localized != key) ? localized : defaultTitle;
  }

  String getDisplaySubtitle(BuildContext context) {
    if (customSubtitle != null && customSubtitle!.trim().isNotEmpty) {
      return customSubtitle!.trim();
    }
    final key = 'card_sub_$id';
    final localized = context.tr(key);
    return (localized.isNotEmpty && localized != key) ? localized : defaultSubtitle;
  }

  LinearGradient get gradient => LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'customTitle': customTitle,
        'customSubtitle': customSubtitle,
        'isVisible': isVisible,
        'order': order,
      };

  DashboardCardConfig copyWith({
    String? customTitle,
    String? customSubtitle,
    bool? isVisible,
    int? order,
  }) {
    return DashboardCardConfig(
      id: id,
      defaultTitle: defaultTitle,
      customTitle: customTitle ?? this.customTitle,
      defaultSubtitle: defaultSubtitle,
      customSubtitle: customSubtitle ?? this.customSubtitle,
      category: category,
      icon: icon,
      gradientColors: gradientColors,
      targetModule: targetModule,
      isVisible: isVisible ?? this.isVisible,
      order: order ?? this.order,
    );
  }
}

class DashboardConfigService {
  static const String _prefKey = 'dashboard_custom_cards_config_v2';

  static List<DashboardCardConfig> getDefaultCatalog() {
    return [
      // ── Administration & Attendance ──
      DashboardCardConfig(
        id: 'students',
        defaultTitle: 'Total Enrolled Students',
        defaultSubtitle: 'Active Admissions',
        category: 'Administration',
        icon: Icons.people_alt_rounded,
        gradientColors: const [Color(0xFF0D6B4E), Color(0xFF1AAE7C)],
        targetModule: 'students',
        isVisible: true,
        order: 1,
      ),
      DashboardCardConfig(
        id: 'staff',
        defaultTitle: 'Total Active Staff',
        defaultSubtitle: 'Faculty & Office Staff',
        category: 'Administration',
        icon: Icons.badge_rounded,
        gradientColors: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
        targetModule: 'staff',
        isVisible: true,
        order: 2,
      ),
      DashboardCardConfig(
        id: 'attendance',
        defaultTitle: 'Average Attendance',
        defaultSubtitle: 'Today\'s Attendance %',
        category: 'Administration',
        icon: Icons.fact_check_rounded,
        gradientColors: const [Color(0xFFE65100), Color(0xFFFF8F00)],
        targetModule: 'attendance',
        isVisible: true,
        order: 3,
      ),
      DashboardCardConfig(
        id: 'classes',
        defaultTitle: 'Active Classes',
        defaultSubtitle: 'Sections Configured',
        category: 'Administration',
        icon: Icons.class_rounded,
        gradientColors: const [Color(0xFF00838F), Color(0xFF00ACC1)],
        targetModule: 'classes',
        isVisible: true,
        order: 4,
      ),
      DashboardCardConfig(
        id: 'new_admissions',
        defaultTitle: 'New Admissions',
        defaultSubtitle: 'This Month',
        category: 'Administration',
        icon: Icons.person_add_alt_1_rounded,
        gradientColors: const [Color(0xFF00796B), Color(0xFF48A999)],
        targetModule: 'students',
        isVisible: true,
        order: 5,
      ),
      DashboardCardConfig(
        id: 'system_users',
        defaultTitle: 'System Users',
        defaultSubtitle: 'Active Portals',
        category: 'Administration',
        icon: Icons.manage_accounts_rounded,
        gradientColors: const [Color(0xFF455A64), Color(0xFF78909C)],
        targetModule: 'users',
        isVisible: true,
        order: 6,
      ),

      // ── Financial Ledger & Accounts ──
      DashboardCardConfig(
        id: 'pending_fees',
        defaultTitle: 'Pending School Fees',
        defaultSubtitle: 'Fees Due to Collect',
        category: 'Finance',
        icon: Icons.account_balance_wallet_rounded,
        gradientColors: const [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
        targetModule: 'fees',
        isVisible: true,
        order: 7,
      ),
      DashboardCardConfig(
        id: 'donations',
        defaultTitle: 'Donations Collected',
        defaultSubtitle: 'Lillah, Sadqa & Zakat',
        category: 'Finance',
        icon: Icons.volunteer_activism_rounded,
        gradientColors: const [Color(0xFF00695C), Color(0xFF00BFA5)],
        targetModule: 'contributors',
        isVisible: true,
        order: 8,
      ),
      DashboardCardConfig(
        id: 'purchases',
        defaultTitle: 'Purchase Expenses',
        defaultSubtitle: 'Ration & General Spent',
        category: 'Finance',
        icon: Icons.shopping_bag_rounded,
        gradientColors: const [Color(0xFFC62828), Color(0xFFEF5350)],
        targetModule: 'purchases',
        isVisible: true,
        order: 9,
      ),
      DashboardCardConfig(
        id: 'sales',
        defaultTitle: 'Sales Revenue',
        defaultSubtitle: 'Kitchen Sales & Income',
        category: 'Finance',
        icon: Icons.sell_rounded,
        gradientColors: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
        targetModule: 'purchases',
        isVisible: true,
        order: 10,
      ),

      // ── Academic & Exams ──
      DashboardCardConfig(
        id: 'exams',
        defaultTitle: 'Exams Configured',
        defaultSubtitle: 'Scheduled Terminals',
        category: 'Academic',
        icon: Icons.quiz_rounded,
        gradientColors: const [Color(0xFF4A148C), Color(0xFF7B1FA2)],
        targetModule: 'exams',
        isVisible: true,
        order: 11,
      ),
      DashboardCardConfig(
        id: 'courses',
        defaultTitle: 'Active Courses',
        defaultSubtitle: 'Curriculum Subjects',
        category: 'Academic',
        icon: Icons.menu_book_rounded,
        gradientColors: const [Color(0xFF283593), Color(0xFF5C6BC0)],
        targetModule: 'classes',
        isVisible: true,
        order: 12,
      ),
      DashboardCardConfig(
        id: 'library_books',
        defaultTitle: 'Library Catalog',
        defaultSubtitle: 'Total Volumes',
        category: 'Academic',
        icon: Icons.local_library_rounded,
        gradientColors: const [Color(0xFFAD1457), Color(0xFFEC407A)],
        targetModule: 'library',
        isVisible: true,
        order: 13,
      ),
      DashboardCardConfig(
        id: 'issued_books',
        defaultTitle: 'Issued Books',
        defaultSubtitle: 'With Students & Staff',
        category: 'Academic',
        icon: Icons.bookmark_added_rounded,
        gradientColors: const [Color(0xFF880E4F), Color(0xFFC2185B)],
        targetModule: 'library',
        isVisible: true,
        order: 14,
      ),

      // ── Facilities & Inventory ──
      DashboardCardConfig(
        id: 'hostel_beds',
        defaultTitle: 'Hostel Occupancy',
        defaultSubtitle: 'Occupied vs Total Beds',
        category: 'Facilities',
        icon: Icons.hotel_rounded,
        gradientColors: const [Color(0xFF1565C0), Color(0xFF1E88E5)],
        targetModule: 'hostel',
        isVisible: true,
        order: 15,
      ),
      DashboardCardConfig(
        id: 'kitchen_stock',
        defaultTitle: 'Kitchen Stock Alerts',
        defaultSubtitle: 'Low Ration Items',
        category: 'Facilities',
        icon: Icons.restaurant_menu_rounded,
        gradientColors: const [Color(0xFFD84315), Color(0xFFFF7043)],
        targetModule: 'kitchen',
        isVisible: true,
        order: 16,
      ),
      DashboardCardConfig(
        id: 'general_stock',
        defaultTitle: 'General Inventory Alerts',
        defaultSubtitle: 'Low Stock Assets',
        category: 'Facilities',
        icon: Icons.inventory_2_rounded,
        gradientColors: const [Color(0xFF00695C), Color(0xFF26A69A)],
        targetModule: 'kitchen',
        isVisible: true,
        order: 17,
      ),
    ];
  }

  static Future<List<DashboardCardConfig>> loadCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      final catalog = getDefaultCatalog();

      if (raw == null || raw.trim().isEmpty) {
        return catalog;
      }

      final List<dynamic> list = jsonDecode(raw);
      final map = <String, Map<String, dynamic>>{};
      for (final item in list) {
        if (item is Map && item.containsKey('id')) {
          map[item['id'].toString()] = Map<String, dynamic>.from(item);
        }
      }

      for (final card in catalog) {
        if (map.containsKey(card.id)) {
          final saved = map[card.id]!;
          if (saved['customTitle'] != null) {
            card.customTitle = saved['customTitle'].toString();
          }
          if (saved['customSubtitle'] != null) {
            card.customSubtitle = saved['customSubtitle'].toString();
          }
          if (saved['isVisible'] != null) {
            card.isVisible = saved['isVisible'] == true;
          }
          if (saved['order'] != null && saved['order'] is num) {
            card.order = (saved['order'] as num).toInt();
          }
        }
      }

      catalog.sort((a, b) => a.order.compareTo(b.order));
      return catalog;
    } catch (e) {
      debugPrint('Error loading dashboard cards: $e');
      return getDefaultCatalog();
    }
  }

  static Future<void> saveCards(List<DashboardCardConfig> cards) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = cards.map((c) => c.toJson()).toList();
      await prefs.setString(_prefKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving dashboard cards: $e');
    }
  }

  static Future<List<DashboardCardConfig>> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
    return getDefaultCatalog();
  }

  static String getCardDisplayValue(String id, DashboardLoaded state) {
    switch (id) {
      case 'students':
        return state.totalStudents.toString();
      case 'staff':
        return state.totalStaff.toString();
      case 'attendance':
        return state.attendancePercentage;
      case 'classes':
        return state.activeClasses.toString();
      case 'new_admissions':
        return state.newAdmissionsThisMonth > 0
            ? state.newAdmissionsThisMonth.toString()
            : state.totalStudents.toString();
      case 'system_users':
        return state.totalUsers > 0 ? state.totalUsers.toString() : 'Active';
      case 'pending_fees':
        return '₹${state.pendingFees.toStringAsFixed(0)}';
      case 'donations':
        return '₹${state.totalDonations.toStringAsFixed(0)}';
      case 'purchases':
        return '₹${state.totalPurchases.toStringAsFixed(0)}';
      case 'sales':
        return '₹${state.totalSales.toStringAsFixed(0)}';
      case 'exams':
        return state.totalExams > 0 ? state.totalExams.toString() : 'Active';
      case 'courses':
        return state.totalCourses > 0 ? state.totalCourses.toString() : state.activeClasses.toString();
      case 'library_books':
        return state.totalBooks > 0 ? state.totalBooks.toString() : 'Available';
      case 'issued_books':
        return state.issuedBooks.toString();
      case 'hostel_beds':
        return '${state.hostelOccupiedBeds}/${state.hostelTotalBeds > 0 ? state.hostelTotalBeds : 0}';
      case 'kitchen_stock':
        return state.kitchenLowStock.toString();
      case 'general_stock':
        return state.generalLowStock.toString();
      default:
        return '0';
    }
  }
}
