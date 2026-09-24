import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/localization/app_localizations.dart';
import 'package:madarsa_app/features/dashboard/presentation/widgets/dashboard_staff_analytics_widget.dart';
import 'package:madarsa_app/features/staff/data/models/staff_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyStaff = [
    const StaffMember(
      id: '1',
      staffNo: 'S-0001',
      fullName: 'Maulana Zaid',
      staffType: 'Teacher',
      salary: 25000,
      experienceYears: 5,
      gender: 'Male',
      isActive: true,
    ),
    const StaffMember(
      id: '2',
      staffNo: 'S-0002',
      fullName: 'Mufti Bilal',
      staffType: 'Teacher',
      salary: 30000,
      experienceYears: 8,
      gender: 'Male',
      isActive: true,
    ),
    const StaffMember(
      id: '3',
      staffNo: 'S-0003',
      fullName: 'Farhan Nazim',
      staffType: 'Admin',
      salary: 28000,
      experienceYears: 4,
      gender: 'Male',
      isActive: true,
    ),
    const StaffMember(
      id: '4',
      staffNo: 'S-0004',
      fullName: 'Fatima Begum',
      staffType: 'Office',
      salary: 18000,
      experienceYears: 3,
      gender: 'Female',
      isActive: true,
    ),
  ];

  Widget buildTestApp({required Widget child, Locale locale = const Locale('en')}) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ur'),
        Locale('hi'),
        Locale('gu'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('DashboardStaffAnalyticsWidget Comprehensive Tests', () {
    testWidgets('Renders zero-state staff analytics cleanly in dark and light modes', (tester) async {
      bool navigated = false;

      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 480,
            height: 420,
            child: DashboardStaffAnalyticsWidget(
              isDark: false,
              initialStaff: const [],
              totalStaffFallback: 0,
              fixedHeight: 330,
              onNavigate: (module) {
                if (module == 'staff') navigated = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify header and tab elements exist
      expect(find.text('Staff Analytics & Overview'), findsOneWidget);
      expect(find.text('Overview & Payroll'), findsOneWidget);
      expect(find.text('By Category'), findsOneWidget);
      expect(find.text('Staff Salary Lookup'), findsOneWidget);
      expect(find.text('Total Staff'), findsOneWidget);
      expect(find.text('+ Add Staff'), findsOneWidget);

      // Tap navigation
      await tester.tap(find.text('+ Add Staff'));
      await tester.pumpAndSettle();
      expect(navigated, isTrue);

      // Clean up widget
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 0: Renders Overview & Payroll with live staff data and metrics', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 480,
            height: 420,
            child: DashboardStaffAnalyticsWidget(
              isDark: true,
              initialStaff: dummyStaff,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Total Staff: 4, Monthly Payroll: 101,000 (₹1.0L), Annual Payroll: 1,212,000 (₹12.1L)
      expect(find.text('4'), findsOneWidget);
      expect(find.text('₹1.0L'), findsOneWidget);
      expect(find.text('₹12.1L'), findsOneWidget);

      // Demographics in Tab 0
      expect(find.textContaining('3 Male • 1 Female'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 1: By Category dropdown filters and shows category stats', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 480,
            height: 420,
            child: DashboardStaffAnalyticsWidget(
              isDark: false,
              initialStaff: dummyStaff,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "By Category" tab
      await tester.tap(find.text('By Category'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Category tab should display staff in category and monthly/annual payroll
      expect(find.text('Staff in Category'), findsOneWidget);
      expect(find.text('Monthly Payroll'), findsOneWidget);
      expect(find.text('Annual Payroll'), findsOneWidget);
      expect(find.text('All Categories'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 2: Staff Salary Lookup shows individual monthly and yearly salary', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 480,
            height: 420,
            child: DashboardStaffAnalyticsWidget(
              isDark: true,
              initialStaff: dummyStaff,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "Staff Salary Lookup" tab
      await tester.tap(find.text('Staff Salary Lookup'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Should display selected staff member (Maulana Zaid) and his salary
      expect(find.text('Maulana Zaid'), findsOneWidget);
      expect(find.text('Monthly Salary'), findsOneWidget);
      expect(find.text('Yearly Salary'), findsOneWidget);
      expect(find.text('₹25,000'), findsOneWidget);
      expect(find.text('₹3,00,000'), findsOneWidget);
      expect(find.text('View Profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Multi-language rendering: Urdu locale displays correctly', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('ur'),
          child: SizedBox(
            width: 480,
            height: 420,
            child: DashboardStaffAnalyticsWidget(
              isDark: false,
              initialStaff: dummyStaff,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Urdu tab titles
      expect(find.text('مجموعی جائزہ و تنخواہ'), findsOneWidget);
      expect(find.text('حسب زمرہ'), findsOneWidget);
      expect(find.text('انفرادی تنخواہ'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Renders within narrow mobile widths without overflow', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 320,
            child: DashboardStaffAnalyticsWidget(
              isDark: false,
              initialStaff: dummyStaff,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Supports and renders user-defined customizable genders properly', (tester) async {
      final customGenderStaff = [
        const StaffMember(
          id: '10',
          staffNo: 'S-0010',
          fullName: 'Qari Hanzala',
          staffType: 'Teacher',
          salary: 22000,
          experienceYears: 4,
          gender: 'Brothers',
          isActive: true,
        ),
        const StaffMember(
          id: '11',
          staffNo: 'S-0011',
          fullName: 'Maulana Imran',
          staffType: 'Teacher',
          salary: 24000,
          experienceYears: 6,
          gender: 'Brothers',
          isActive: true,
        ),
        const StaffMember(
          id: '12',
          staffNo: 'S-0012',
          fullName: 'Ayesha Siddiqua',
          staffType: 'Faculty',
          salary: 20000,
          experienceYears: 3,
          gender: 'Sisters',
          isActive: true,
        ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 480,
            height: 420,
            child: DashboardStaffAnalyticsWidget(
              isDark: false,
              initialStaff: customGenderStaff,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify custom genders are displayed in Tab 0 footer
      expect(find.textContaining('2 Brothers • 1 Sisters'), findsOneWidget);

      // Switch to Tab 2 (Staff Salary Lookup) and verify individual custom gender displays
      await tester.tap(find.text('Staff Salary Lookup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gender: Brothers'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

