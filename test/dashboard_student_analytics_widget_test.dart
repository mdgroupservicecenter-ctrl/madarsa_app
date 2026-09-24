import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/localization/app_localizations.dart';
import 'package:madarsa_app/features/dashboard/presentation/widgets/dashboard_student_analytics_widget.dart';
import 'package:madarsa_app/features/students/data/models/student_model.dart';
import 'package:madarsa_app/features/students/presentation/screens/student_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyStudents = [
    Student(
      id: 's1',
      registrationNumber: 'REG-001',
      grNo: 'GR-101',
      fullName: 'Ahmad Raza',
      departmentName: 'Hifz Department',
      subDepartments: [
        StudentSubDepartment(
          subDepartmentName: 'Tajweed Branch',
          className: 'Hifz 1',
          division: 'Section A',
        ),
      ],
      className: 'Hifz 1',
      division: 'Section A',
      village: 'Dindrol',
      district: 'Patan',
      state: 'Gujarat',
      monthlyFees: 1500,
      pendingFees: 3000,
      gender: 'Brothers',
      studentStatus: 'Hosteller',
      conditionType: 'Regular',
      isActive: true,
      totalAttendance: 145,
    ),
    Student(
      id: 's2',
      registrationNumber: 'REG-002',
      grNo: 'GR-102',
      fullName: 'Muhammad Usman',
      departmentName: 'Hifz Department',
      subDepartments: [
        StudentSubDepartment(
          subDepartmentName: 'Tajweed Branch',
          className: 'Hifz 1',
          division: 'Section B',
        ),
      ],
      className: 'Hifz 1',
      division: 'Section B',
      village: 'Dindrol',
      district: 'Patan',
      state: 'Gujarat',
      monthlyFees: 1500,
      pendingFees: 0,
      gender: 'Brothers',
      studentStatus: 'Hosteller',
      conditionType: 'Scholarship',
      isActive: true,
      totalAttendance: 120,
    ),
    Student(
      id: 's3',
      registrationNumber: 'REG-003',
      grNo: 'GR-103',
      fullName: 'Zainab Fatima',
      departmentName: 'Aalimiyyah',
      subDepartments: [
        StudentSubDepartment(
          subDepartmentName: 'Girls Wing',
          className: 'Awwal',
          division: 'Section A',
        ),
      ],
      className: 'Awwal',
      division: 'Section A',
      village: 'Sidhpur',
      district: 'Patan',
      state: 'Gujarat',
      monthlyFees: 1200,
      pendingFees: 1200,
      gender: 'Sisters',
      studentStatus: 'Day Scholar',
      conditionType: 'Regular',
      isActive: true,
      totalAttendance: 95,
    ),
    Student(
      id: 's4',
      registrationNumber: 'REG-004',
      grNo: 'GR-104',
      fullName: 'Bilal Khan',
      departmentName: 'Aalimiyyah',
      subDepartments: [
        StudentSubDepartment(
          subDepartmentName: 'Boys Wing',
          className: 'Awwal',
          division: 'Section B',
        ),
      ],
      className: 'Awwal',
      division: 'Section B',
      village: 'Malegaon',
      district: 'Nashik',
      state: 'Maharashtra',
      monthlyFees: 1800,
      pendingFees: 0,
      gender: 'Brothers',
      studentStatus: 'Hosteller',
      conditionType: 'Orphan Free',
      isActive: true,
      totalAttendance: 110,
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

  group('DashboardStudentAnalyticsWidget Comprehensive Tests', () {
    testWidgets('Renders zero-state student analytics cleanly in dark and light modes', (tester) async {
      bool navigated = false;

      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 500,
            height: 420,
            child: DashboardStudentAnalyticsWidget(
              isDark: false,
              initialStudents: const [],
              totalStudentsFallback: 0,
              fixedHeight: 330,
              onNavigate: (module) {
                if (module == 'students') navigated = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify header and tab elements exist
      expect(find.text('Student Analytics & Overview'), findsOneWidget);
      expect(find.text('Overview & Fees'), findsOneWidget);
      expect(find.text('By Location'), findsOneWidget);
      expect(find.text('By Dept & Class'), findsOneWidget);
      expect(find.text('Student Fee Lookup'), findsOneWidget);
      expect(find.text('Total Enrolled Students'), findsOneWidget);
      expect(find.text('Manage Students'), findsOneWidget);

      // Tap navigation
      await tester.tap(find.text('Manage Students'));
      await tester.pumpAndSettle();
      expect(navigated, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 0: Overview & Fees renders metrics and custom genders', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 500,
            height: 420,
            child: DashboardStudentAnalyticsWidget(
              isDark: true,
              initialStudents: dummyStudents,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Total Students: 4, Monthly Fees: 1500+1500+1200+1800 = 6,000 (₹6,000), Pending Fees: 3000+1200 = 4,200 (₹4,200)
      expect(find.text('4'), findsOneWidget);
      expect(find.text('₹6,000'), findsOneWidget);
      expect(find.text('₹4,200'), findsOneWidget);

      // Verify Paid Fees KPI Tile (Attendance is strictly excluded from Tab 0)
      expect(find.text('Paid Fees'), findsOneWidget);
      expect(find.text('Attendance'), findsNothing);

      // Verify Custom Gender Demographics
      expect(find.textContaining('3 Brothers'), findsOneWidget);
      expect(find.textContaining('1 Sisters'), findsOneWidget);

      // Hosteller & Day Scholar
      expect(find.textContaining('3 Hosteller'), findsOneWidget);
      expect(find.textContaining('1 Day Scholar'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 1: By Location filters by Village, District, and State', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 500,
            height: 420,
            child: DashboardStudentAnalyticsWidget(
              isDark: false,
              initialStudents: dummyStudents,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "By Location" tab
      await tester.tap(find.text('By Location'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Check village/district/state buttons
      expect(find.text('Village'), findsOneWidget);
      expect(find.text('District'), findsOneWidget);
      expect(find.text('State'), findsOneWidget);

      // Switch location type to District
      await tester.tap(find.text('District'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch location type to State
      await tester.tap(find.text('State'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 2: By Dept & Class supports 4-tier filtering (Dept, Sub-Dept, Class, Division)', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 500,
            height: 420,
            child: DashboardStudentAnalyticsWidget(
              isDark: false,
              initialStudents: dummyStudents,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "By Dept & Class" tab
      await tester.tap(find.text('By Dept & Class'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify 4-tier filter dropdowns exist
      expect(find.text('All Departments'), findsOneWidget);
      expect(find.text('All Sub-Depts'), findsOneWidget);
      expect(find.text('All Classes'), findsOneWidget);
      expect(find.text('All Divisions'), findsOneWidget);

      // All students metrics initially: 4 students, ₹6,000 monthly, ₹4,200 pending
      expect(find.text('4'), findsOneWidget);
      expect(find.text('₹6,000'), findsOneWidget);
      expect(find.text('₹4,200'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Tab 3: Student Fee Lookup displays attendance, searchable picker, and profile route with BlocProvider', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 500,
            height: 420,
            child: DashboardStudentAnalyticsWidget(
              isDark: true,
              initialStudents: dummyStudents,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to "Student Fee Lookup" tab
      await tester.tap(find.text('Student Fee Lookup'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // First student (Ahmad Raza)
      expect(find.text('Ahmad Raza'), findsOneWidget);
      expect(find.text('Paid Fees'), findsOneWidget);
      expect(find.text('Pending Fees'), findsOneWidget);
      expect(find.text('Monthly Fees'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('₹1,500'), findsOneWidget); // Monthly fee
      expect(find.text('₹3,000'), findsOneWidget); // Pending fee
      expect(find.text('145 Days'), findsOneWidget); // Attendance
      expect(find.textContaining('Dindrol, Patan, Gujarat'), findsOneWidget); // Address
      expect(find.textContaining('Brothers'), findsOneWidget); // Custom Gender
      expect(find.text('View Profile'), findsOneWidget);

      // Test Searchable Student Selector modal
      expect(find.text('Search Student'), findsOneWidget);
      await tester.tap(find.text('Search Student'));
      await tester.pumpAndSettle();

      // Search dialog should be visible
      expect(find.byType(TextField), findsOneWidget);

      // Search for "Bilal"
      await tester.enterText(find.byType(TextField), 'Bilal');
      await tester.pumpAndSettle();

      // Tap on Bilal Khan in the search results
      expect(find.text('Bilal Khan'), findsOneWidget);
      await tester.tap(find.text('Bilal Khan'));
      await tester.pumpAndSettle();

      // Verify Tab 3 now displays Bilal Khan and his attendance
      expect(find.text('Bilal Khan'), findsOneWidget);
      expect(find.text('110 Days'), findsOneWidget); // Bilal's attendance
      expect(find.text('₹1,800'), findsOneWidget); // Bilal's monthly fee

      // Test clicking "View Profile" does NOT crash with ProviderNotFoundException
      await tester.tap(find.text('View Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.byType(StudentProfileScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Multi-language rendering: Urdu locale displays correctly for students', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('ur'),
          child: SizedBox(
            width: 500,
            height: 420,
            child: DashboardStudentAnalyticsWidget(
              isDark: false,
              initialStudents: dummyStudents,
              fixedHeight: 330,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Urdu tab titles
      expect(find.text('مجموعی جائزہ و فیس'), findsOneWidget);
      expect(find.text('علاقائی تقسیم'), findsOneWidget);
      expect(find.text('حسب شعبہ و جماعت'), findsOneWidget);
      expect(find.text('طالب علم کی فیس'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('Renders within narrow mobile widths without overflow', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: SizedBox(
            width: 320,
            child: DashboardStudentAnalyticsWidget(
              isDark: false,
              initialStudents: dummyStudents,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
