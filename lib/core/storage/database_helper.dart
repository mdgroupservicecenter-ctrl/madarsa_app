import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../services/firebase_service.dart';
import '../network/api_client.dart';
import '../../features/students/data/models/student_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<String> _resolveDatabasePath() async {
    if (Platform.isWindows || Platform.isMacOS) {
      // 1. Primary Live Project Database on D: drive (Windows development)
      const directPath = r'D:\MD Group\backend\database.sqlite';
      if (Platform.isWindows && File(directPath).existsSync()) {
        return directPath;
      }

      // 2. Current Working Directory paths
      final cwdBackend = join(Directory.current.path, 'backend', 'database.sqlite');
      if (File(cwdBackend).existsSync()) return cwdBackend;

      final cwdParentBackend = normalize(join(Directory.current.path, '..', 'backend', 'database.sqlite'));
      if (File(cwdParentBackend).existsSync()) return cwdParentBackend;

      final cwdServer = join(Directory.current.path, 'server', 'database.sqlite');
      if (File(cwdServer).existsSync()) return cwdServer;

      // 3. Check relative to executable parent
      final exeDir = File(Platform.resolvedExecutable).parent.path;

      final backendDbAppParent = normalize(join(exeDir, '..', 'backend', 'database.sqlite'));
      if (File(backendDbAppParent).existsSync()) return backendDbAppParent;

      final backendDbExeDir = join(exeDir, 'backend', 'database.sqlite');
      if (File(backendDbExeDir).existsSync()) return backendDbExeDir;

      final serverDbAppParent = normalize(join(exeDir, '..', 'server', 'database.sqlite'));
      if (File(serverDbAppParent).existsSync()) return serverDbAppParent;

      final serverDbExeDir = join(exeDir, 'server', 'database.sqlite');
      if (File(serverDbExeDir).existsSync()) return serverDbExeDir;

      // macOS writable Application Support directory & bundle seed copy
      if (Platform.isMacOS) {
        final homeDir = Platform.environment['HOME'] ?? '';
        if (homeDir.isNotEmpty) {
          final macUserDb = join(homeDir, 'Library', 'Application Support', 'MadarsaManagement', 'database.sqlite');
          if (File(macUserDb).existsSync()) {
            return macUserDb;
          }
          final macBundleServerDb = normalize(join(exeDir, '..', 'Resources', 'server', 'database.sqlite'));
          if (File(macBundleServerDb).existsSync()) {
            try {
              final targetDir = Directory(join(homeDir, 'Library', 'Application Support', 'MadarsaManagement'));
              if (!targetDir.existsSync()) {
                targetDir.createSync(recursive: true);
              }
              File(macBundleServerDb).copySync(macUserDb);
              return macUserDb;
            } catch (_) {
              return macBundleServerDb;
            }
          }
        }
      }

      // 4. Standard Windows Installed path fallback
      if (Platform.isWindows) {
        const installedServerDb = r'C:\Program Files\Madarsa Management System\server\database.sqlite';
        if (File(installedServerDb).existsSync()) return installedServerDb;
      }

      // 5. Fallback to AppData / Application Support directory
      final appDocDir = await getApplicationSupportDirectory();
      final dbDir = Directory(join(appDocDir.path, 'databases'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      return join(dbDir.path, 'madarsa_management.db');
    } else {
      final dbPath = await getDatabasesPath();
      return join(dbPath, 'madarsa_management.db');
    }
  }

  Future<Database> _initDatabase() async {
    // Initialize FFI for Windows / Linux / macOS desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = await _resolveDatabasePath();

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _ensureAllTablesExist(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureAllTablesExist(db);
      },
      onOpen: (db) async {
        await _ensureAllTablesExist(db);
      },
    );
  }

  Future<void> _ensureAllTablesExist(Database db) async {
    await _createAllTables(db);
    await _ensureAllColumns(db);
    try {
      final count = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM users")) ?? 0;
      if (count == 0) {
        await _seedInitialData(db);
      }
    } catch (_) {}
  }

  Future<void> _ensureAllColumns(Database db) async {
    final migrations = [
      'ALTER TABLE classes ADD COLUMN department_id TEXT;',
      'ALTER TABLE classes ADD COLUMN duration TEXT;',
      'ALTER TABLE classes ADD COLUMN description TEXT;',
      'ALTER TABLE classes ADD COLUMN is_active INTEGER DEFAULT 1;',

      'ALTER TABLE departments ADD COLUMN parent_id TEXT;',
      'ALTER TABLE departments ADD COLUMN head_name TEXT;',
      'ALTER TABLE departments ADD COLUMN description TEXT;',
      'ALTER TABLE departments ADD COLUMN is_active INTEGER DEFAULT 1;',

      'ALTER TABLE courses ADD COLUMN department_id TEXT;',
      'ALTER TABLE courses ADD COLUMN code TEXT;',
      'ALTER TABLE courses ADD COLUMN description TEXT;',
      'ALTER TABLE courses ADD COLUMN is_active INTEGER DEFAULT 1;',

      'ALTER TABLE books ADD COLUMN course_id TEXT;',
      'ALTER TABLE books ADD COLUMN author TEXT;',
      'ALTER TABLE books ADD COLUMN description TEXT;',
      'ALTER TABLE books ADD COLUMN name TEXT;',
      'ALTER TABLE books ADD COLUMN title TEXT;',
      'ALTER TABLE books ADD COLUMN category TEXT;',
      'ALTER TABLE books ADD COLUMN is_active INTEGER DEFAULT 1;',

      'ALTER TABLE students ADD COLUMN department_id TEXT;',
      'ALTER TABLE students ADD COLUMN sub_department_id TEXT;',
      'ALTER TABLE students ADD COLUMN roll_number TEXT;',
      'ALTER TABLE students ADD COLUMN sub_departments TEXT;',
      'ALTER TABLE students ADD COLUMN photo_path TEXT;',
      'ALTER TABLE students ADD COLUMN contributor_id TEXT;',
      'ALTER TABLE students ADD COLUMN contributor_amount REAL DEFAULT 0;',
      'ALTER TABLE students ADD COLUMN contributor_name TEXT;',
      'ALTER TABLE students ADD COLUMN address TEXT;',
      'ALTER TABLE students ADD COLUMN admission_time_age TEXT;',
      'ALTER TABLE students ADD COLUMN now_age TEXT;',
      'ALTER TABLE students ADD COLUMN department_name TEXT;',
      'ALTER TABLE students ADD COLUMN division TEXT;',
      'ALTER TABLE students ADD COLUMN category TEXT;',
      'ALTER TABLE students ADD COLUMN admission_date_h TEXT;',
      'ALTER TABLE students ADD COLUMN condition_type TEXT DEFAULT "Regular";',
      'ALTER TABLE students ADD COLUMN student_status TEXT DEFAULT "Old";',
      'ALTER TABLE students ADD COLUMN admission_type TEXT DEFAULT "New";',
      'ALTER TABLE students ADD COLUMN monthly_fees REAL DEFAULT 0;',
      'ALTER TABLE students ADD COLUMN staff_id TEXT;',
      'ALTER TABLE students ADD COLUMN staff_name TEXT;',

      'ALTER TABLE staff ADD COLUMN joining_date_h TEXT;',
      'ALTER TABLE staff ADD COLUMN salary REAL DEFAULT 0;',
      'ALTER TABLE staff ADD COLUMN pin_code TEXT;',
      'ALTER TABLE staff ADD COLUMN emergency_contact TEXT;',
      'ALTER TABLE staff ADD COLUMN address TEXT;',
      'ALTER TABLE staff ADD COLUMN note TEXT;',
      'ALTER TABLE staff ADD COLUMN role_id TEXT;',
      'ALTER TABLE staff ADD COLUMN user_id TEXT;',
      'ALTER TABLE staff ADD COLUMN photo_path TEXT;',
      'ALTER TABLE staff ADD COLUMN assigned_books TEXT;',
      'ALTER TABLE users ADD COLUMN role_id TEXT;',
      'ALTER TABLE users ADD COLUMN last_login TEXT;',
      'ALTER TABLE roles ADD COLUMN permissions TEXT;',
      'ALTER TABLE exam_marks ADD COLUMN roll_number TEXT;',
      'ALTER TABLE exam_marks ADD COLUMN division TEXT;',
      'CREATE INDEX IF NOT EXISTS idx_fees_student_status ON fees(student_id, status);',
      'CREATE INDEX IF NOT EXISTS idx_students_active ON students(is_active);',
      'CREATE INDEX IF NOT EXISTS idx_students_class ON students(class_name);',
      'CREATE TABLE IF NOT EXISTS academic_years (id TEXT PRIMARY KEY, year_name TEXT UNIQUE NOT NULL, year_name_hijri TEXT, start_date TEXT, end_date TEXT, is_current INTEGER DEFAULT 0, created_at TEXT DEFAULT CURRENT_TIMESTAMP);',
      'ALTER TABLE academic_years ADD COLUMN auto_promote_enabled INTEGER DEFAULT 1;',
      'ALTER TABLE academic_years ADD COLUMN passing_percentage REAL DEFAULT 40.0;',
      'ALTER TABLE academic_years ADD COLUMN annual_student_expense REAL DEFAULT 15000.0;',
      'ALTER TABLE academic_years ADD COLUMN auto_promoted_at TEXT;',

      'CREATE TABLE IF NOT EXISTS student_academic_history (id TEXT PRIMARY KEY, student_id TEXT NOT NULL, academic_year TEXT NOT NULL, academic_year_hijri TEXT, class_id TEXT, class_name TEXT NOT NULL, department_id TEXT, department_name TEXT, division TEXT, roll_number TEXT, total_attendance_days INTEGER DEFAULT 0, present_days INTEGER DEFAULT 0, attendance_percentage REAL DEFAULT 0, total_marks REAL DEFAULT 0, obtained_marks REAL DEFAULT 0, exam_percentage REAL DEFAULT 0, result_grade TEXT, status TEXT NOT NULL DEFAULT "Promoted", remarks TEXT, promoted_at TEXT DEFAULT CURRENT_TIMESTAMP, created_at TEXT DEFAULT CURRENT_TIMESTAMP, updated_at TEXT DEFAULT CURRENT_TIMESTAMP);',
      'ALTER TABLE student_academic_history ADD COLUMN books_marks_json TEXT;',
      'ALTER TABLE student_academic_history ADD COLUMN fee_total REAL DEFAULT 0;',
      'ALTER TABLE student_academic_history ADD COLUMN fee_paid REAL DEFAULT 0;',
      'ALTER TABLE student_academic_history ADD COLUMN fee_pending REAL DEFAULT 0;',
      'ALTER TABLE student_academic_history ADD COLUMN per_student_expense REAL DEFAULT 0;',
      'ALTER TABLE student_academic_history ADD COLUMN metadata_json TEXT;',
      'CREATE INDEX IF NOT EXISTS idx_student_history_student ON student_academic_history(student_id);',
      'CREATE INDEX IF NOT EXISTS idx_student_history_year ON student_academic_history(academic_year);',

      'CREATE TABLE IF NOT EXISTS vacations (id TEXT PRIMARY KEY, academic_year_id TEXT, title TEXT NOT NULL, title_urdu TEXT, start_date TEXT NOT NULL, end_date TEXT NOT NULL, start_date_hijri TEXT, end_date_hijri TEXT, vacation_type TEXT DEFAULT "General", total_days INTEGER DEFAULT 0, remarks TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP, updated_at TEXT DEFAULT CURRENT_TIMESTAMP);',
      'CREATE INDEX IF NOT EXISTS idx_vacations_year ON vacations(academic_year_id);',
      'CREATE INDEX IF NOT EXISTS idx_vacations_dates ON vacations(start_date, end_date);',

      'ALTER TABLE students ADD COLUMN admission_fee REAL DEFAULT 0;',
      'ALTER TABLE students ADD COLUMN book_fee REAL DEFAULT 0;',
      'ALTER TABLE students ADD COLUMN fee_structure TEXT;',
      'CREATE TABLE IF NOT EXISTS fee_types (id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, billing_type TEXT DEFAULT "monthly", default_months INTEGER DEFAULT 12, default_amount REAL DEFAULT 0, created_at TEXT DEFAULT CURRENT_TIMESTAMP);',
      'ALTER TABLE fee_types ADD COLUMN billing_type TEXT DEFAULT "monthly";',
      'ALTER TABLE fee_types ADD COLUMN default_months INTEGER DEFAULT 12;',
      'ALTER TABLE fee_types ADD COLUMN default_amount REAL DEFAULT 0;',
      'ALTER TABLE fees ADD COLUMN receipt_no TEXT;',
      'ALTER TABLE fees ADD COLUMN remarks TEXT;',

      'CREATE TABLE IF NOT EXISTS donation_types (id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP);',
      'CREATE TABLE IF NOT EXISTS donations (id TEXT PRIMARY KEY, receipt_no TEXT, donor_name TEXT, donor_phone TEXT, village TEXT, taluka TEXT, district TEXT, state TEXT, country TEXT DEFAULT "India", pin_code TEXT, amount REAL NOT NULL, donation_type TEXT NOT NULL, payment_method TEXT DEFAULT "Cash", payment_date TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP);',
      'ALTER TABLE donations ADD COLUMN receipt_no TEXT;',
      'ALTER TABLE donations ADD COLUMN village TEXT;',
      'ALTER TABLE donations ADD COLUMN taluka TEXT;',
      'ALTER TABLE donations ADD COLUMN district TEXT;',
      'ALTER TABLE donations ADD COLUMN state TEXT;',
      'ALTER TABLE donations ADD COLUMN country TEXT DEFAULT "India";',
      'ALTER TABLE donations ADD COLUMN pin_code TEXT;',
      'ALTER TABLE students ADD COLUMN face_data TEXT;',
      'ALTER TABLE students ADD COLUMN fingerprint_data TEXT;',
      'ALTER TABLE students ADD COLUMN biometric_enrolled_at TEXT;',
      'ALTER TABLE attendance ADD COLUMN check_in_time TEXT;',
      'ALTER TABLE attendance ADD COLUMN check_out_time TEXT;',
      'ALTER TABLE attendance ADD COLUMN verification_method TEXT DEFAULT "Manual";',
    ];

    for (final sql in migrations) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already exists or table not ready, safely ignore
      }
    }
  }

  Future<void> _createAllTables(Database db) async {
    // ─── Roles Table ───────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT,
        permissions TEXT NOT NULL,
        is_system INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // ─── Users Table ───────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        full_name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        avatar TEXT,
        role_id INTEGER,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        last_login TEXT
      )
    ''');

    // ─── Students Table ────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS students (
        id TEXT PRIMARY KEY,
        gr_no TEXT UNIQUE,
        registration_number TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        father_name TEXT,
        surname TEXT,
        grand_father_name TEXT,
        date_of_birth TEXT,
        village TEXT,
        taluka TEXT,
        district TEXT,
        state TEXT,
        pin_code TEXT,
        address TEXT,
        mobile_no TEXT,
        aadhaar_no TEXT,
        class_name TEXT,
        department_id TEXT,
        sub_department_id TEXT,
        department_name TEXT,
        roll_number TEXT,
        sub_departments TEXT,
        student_status TEXT DEFAULT 'Old',
        admission_type TEXT DEFAULT 'New',
        admission_date TEXT DEFAULT (date('now')),
        admission_date_h TEXT,
        admission_time_age TEXT,
        now_age TEXT,
        condition_type TEXT DEFAULT 'Regular',
        monthly_fees REAL DEFAULT 0,
        gender TEXT,
        enrollment_date TEXT DEFAULT (date('now')),
        is_active INTEGER DEFAULT 1,
        category TEXT,
        division TEXT,
        contributor_id TEXT,
        contributor_name TEXT,
        contributor_amount REAL DEFAULT 0,
        staff_id TEXT,
        staff_name TEXT,
        admission_fee REAL DEFAULT 0,
        book_fee REAL DEFAULT 0,
        fee_structure TEXT,
        photo_path TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Staff Table ───────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff (
        id TEXT PRIMARY KEY,
        staff_no TEXT UNIQUE NOT NULL,
        full_name TEXT NOT NULL,
        father_name TEXT,
        surname TEXT,
        date_of_birth TEXT,
        gender TEXT,
        staff_type TEXT NOT NULL DEFAULT 'Teacher',
        qualification TEXT,
        experience_years INTEGER DEFAULT 0,
        joining_date TEXT,
        joining_date_h TEXT,
        salary REAL DEFAULT 0,
        mobile_no TEXT,
        aadhaar_no TEXT,
        village TEXT,
        taluka TEXT,
        district TEXT,
        state TEXT,
        pin_code TEXT,
        emergency_contact TEXT,
        address TEXT,
        note TEXT,
        role_id TEXT,
        user_id TEXT,
        photo_path TEXT,
        assigned_books TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Staff Types & Qualifications Tables ──────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_types (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS qualifications (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Attendance Table ──────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        remarks TEXT,
        check_in_time TEXT,
        check_out_time TEXT,
        verification_method TEXT DEFAULT 'Manual',
        shift_id TEXT DEFAULT '',
        shift_name TEXT DEFAULT '',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    try {
      await db.execute("ALTER TABLE attendance ADD COLUMN shift_id TEXT DEFAULT ''");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE attendance ADD COLUMN shift_name TEXT DEFAULT ''");
    } catch (_) {}

    // ─── Period Attendance Table ───────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS period_attendance (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        class_id TEXT NOT NULL,
        period_id TEXT,
        period_number INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        time TEXT,
        remarks TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(student_id, date, period_number)
      )
    ''');

    // ─── Staff Attendance Table ────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_attendance (
        id TEXT PRIMARY KEY,
        staff_id TEXT NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        check_in_time TEXT,
        check_out_time TEXT,
        remarks TEXT,
        verification_method TEXT DEFAULT 'Manual',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Fees Table ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fees (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_date TEXT,
        fee_type TEXT NOT NULL,
        status TEXT NOT NULL,
        receipt_no TEXT,
        remarks TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS fee_types (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        billing_type TEXT DEFAULT 'monthly',
        default_months INTEGER DEFAULT 12,
        default_amount REAL DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Classes & Academic ────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS classes (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        description TEXT,
        duration TEXT,
        department_id TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS departments (
        id TEXT PRIMARY KEY,
        name TEXT UNIQUE NOT NULL,
        description TEXT,
        head_name TEXT,
        parent_id TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS courses (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT UNIQUE,
        department_id TEXT,
        description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS books (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        course_id TEXT,
        author TEXT,
        description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_courses (
        id TEXT PRIMARY KEY,
        class_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        academic_year TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_course_books (
        id TEXT PRIMARY KEY,
        class_course_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_books (
        id TEXT PRIMARY KEY,
        class_course_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_periods (
        id TEXT PRIMARY KEY,
        class_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        period_number INTEGER,
        start_time TEXT,
        end_time TEXT,
        teacher_name TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Contributors Table ────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS contributors (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        pan_no TEXT,
        aadhaar_no TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Settings Table ────────────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Hostel Module Tables ──────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hostels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hostel_rooms (
        id TEXT PRIMARY KEY,
        hostel_id TEXT NOT NULL,
        room_number TEXT NOT NULL,
        capacity INTEGER DEFAULT 4,
        floor TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hostel_allocations (
        id TEXT PRIMARY KEY,
        hostel_id TEXT NOT NULL,
        room_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        allocated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        vacated_at TEXT,
        status TEXT DEFAULT 'Active'
      )
    ''');

    // ─── Kitchen Module Tables ─────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kitchen_menu (
        id TEXT PRIMARY KEY,
        day_of_week TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        items TEXT NOT NULL,
        notes TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS kitchen_ration_stock (
        id TEXT PRIMARY KEY,
        item_name TEXT NOT NULL,
        category TEXT,
        quantity REAL DEFAULT 0,
        unit TEXT DEFAULT 'Kg',
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS kitchen_ration_issues (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        issue_date TEXT NOT NULL,
        meal_type TEXT,
        remarks TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Purchases & Sells Module Tables ───────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id TEXT PRIMARY KEY,
        receipt_no TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        transaction_date TEXT NOT NULL,
        contact_person TEXT,
        total_amount REAL DEFAULT 0,
        remarks TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id TEXT PRIMARY KEY,
        purchase_id TEXT NOT NULL,
        item_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL
      )
    ''');

    // ─── Library Module Tables ─────────────────────────────────
    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_books (
        id TEXT PRIMARY KEY,
        accession_no TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        category_id TEXT,
        publisher TEXT,
        isbn TEXT,
        total_copies INTEGER DEFAULT 1,
        available_copies INTEGER DEFAULT 1,
        is_active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS library_issues (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        user_type TEXT NOT NULL,
        user_id TEXT NOT NULL,
        issue_date TEXT NOT NULL,
        due_date TEXT NOT NULL,
        return_date TEXT,
        status TEXT DEFAULT 'Issued',
        remarks TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // ─── Exam Module Tables ────────────────────────────────────
    await _createExamTables(db);

    // ─── Academic History & Promotion Tables ────────────────────
    await _createAcademicHistoryTables(db);
  }

  Future<void> _createExamTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        start_date TEXT,
        end_date TEXT,
        status TEXT DEFAULT 'DRAFT',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exam_id INTEGER NOT NULL,
        class_id TEXT NOT NULL,
        class_name TEXT,
        book_id TEXT NOT NULL,
        book_name TEXT,
        exam_date TEXT,
        start_time TEXT,
        end_time TEXT,
        max_marks INTEGER NOT NULL DEFAULT 100,
        passing_marks INTEGER,
        department_id TEXT,
        department_name TEXT,
        parent_department_name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_halls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_rows INTEGER NOT NULL,
        total_columns INTEGER NOT NULL,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS seating_arrangements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exam_id INTEGER NOT NULL,
        schedule_id INTEGER,
        hall_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        registration_number TEXT,
        roll_number TEXT,
        book_id TEXT NOT NULL,
        book_name TEXT,
        class_id TEXT NOT NULL,
        class_name TEXT,
        seat_row INTEGER NOT NULL,
        seat_column INTEGER NOT NULL,
        seat_number INTEGER NOT NULL,
        assignment_method TEXT DEFAULT 'ANTI_ADJACENCY',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS seat_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT,
        book_id TEXT,
        hall_id INTEGER,
        seat_row INTEGER,
        seat_column INTEGER,
        exam_id INTEGER,
        session_date TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_seat_history_hall_student ON seat_history(hall_id, student_id)');
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_marks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exam_id INTEGER NOT NULL,
        schedule_id INTEGER NOT NULL,
        student_id TEXT NOT NULL,
        student_name TEXT,
        registration_number TEXT,
        roll_number TEXT,
        division TEXT,
        book_id TEXT NOT NULL,
        book_name TEXT,
        class_id TEXT NOT NULL,
        class_name TEXT,
        max_marks INTEGER DEFAULT 100,
        marks_obtained REAL,
        is_absent INTEGER DEFAULT 0,
        remarks TEXT,
        entered_by TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now().toIso8601String();

    // Roles
    final superAdminRoleId = await db.insert('roles', {
      'name': 'Super Admin',
      'description': 'Full access to all modules and settings.',
      'permissions': '{"all": ["view", "create", "edit", "delete"]}',
      'is_system': 1,
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('roles', {
      'name': 'Teacher',
      'description': 'Manage attendance and view student data.',
      'permissions': '{"students": ["view"], "attendance": ["view", "create", "edit"]}',
      'is_system': 1,
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Default Super Admin User
    await db.insert('users', {
      'id': 'admin_local_1',
      'username': 'admin',
      'password': 'admin123',
      'full_name': 'Super Administrator',
      'email': 'admin@madarsa.com',
      'role_id': superAdminRoleId,
      'is_active': 1,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Default Departments
    await db.insert('departments', {
      'id': 'dept1',
      'name': 'Shouba-e-Hifz-o-Nazra',
      'description': 'Department of Quranic Recitation & Memorization',
      'head_name': 'Qari Abdul Rahman',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('departments', {
      'id': 'dept2',
      'name': 'Shouba-e-Dars-e-Nizami',
      'description': 'Department of Islamic Theology & Classical Studies',
      'head_name': 'Maulana Mohammad Ali',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Default Classes
    await db.insert('classes', {
      'id': 'cls1',
      'name': 'Hifz 1',
      'description': 'Quran Memorization Class 1',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('classes', {
      'id': 'cls2',
      'name': 'Awwal (Dars-e-Nizami 1st Year)',
      'description': 'First Year Alim Course',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Default Hostel
    await db.insert('hostels', {
      'id': 'hostel_1',
      'name': 'Dar-ul-Iqama (Main Hostel)',
      'description': 'Main Residential Building for Students',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('hostel_rooms', {
      'id': 'room_101',
      'hostel_id': 'hostel_1',
      'room_number': '101',
      'capacity': 6,
      'floor': 'Ground Floor',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    // Default Library Category
    await db.insert('library_categories', {
      'id': 'cat_quran',
      'name': 'Tafseer & Quranic Sciences',
      'description': 'Books on Quran translation and commentary',
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _createAcademicHistoryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS academic_years (
        id TEXT PRIMARY KEY,
        year_name TEXT UNIQUE NOT NULL,
        year_name_hijri TEXT,
        start_date TEXT,
        end_date TEXT,
        is_current INTEGER DEFAULT 0,
        auto_promote_enabled INTEGER DEFAULT 1,
        passing_percentage REAL DEFAULT 40.0,
        annual_student_expense REAL DEFAULT 15000.0,
        auto_promoted_at TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_academic_history (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        academic_year TEXT NOT NULL,
        academic_year_hijri TEXT,
        class_id TEXT,
        class_name TEXT NOT NULL,
        department_id TEXT,
        department_name TEXT,
        division TEXT,
        roll_number TEXT,
        total_attendance_days INTEGER DEFAULT 0,
        present_days INTEGER DEFAULT 0,
        attendance_percentage REAL DEFAULT 0,
        total_marks REAL DEFAULT 0,
        obtained_marks REAL DEFAULT 0,
        exam_percentage REAL DEFAULT 0,
        result_grade TEXT,
        status TEXT NOT NULL DEFAULT 'Promoted',
        remarks TEXT,
        promoted_at TEXT DEFAULT CURRENT_TIMESTAMP,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        books_marks_json TEXT,
        fee_total REAL DEFAULT 0,
        fee_paid REAL DEFAULT 0,
        fee_pending REAL DEFAULT 0,
        per_student_expense REAL DEFAULT 0,
        metadata_json TEXT
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_history_student ON student_academic_history(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_history_year ON student_academic_history(academic_year)');
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vacations (
        id TEXT PRIMARY KEY,
        academic_year_id TEXT,
        title TEXT NOT NULL,
        title_urdu TEXT,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        start_date_hijri TEXT,
        end_date_hijri TEXT,
        vacation_type TEXT DEFAULT 'General',
        total_days INTEGER DEFAULT 0,
        remarks TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vacations_year ON vacations(academic_year_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vacations_dates ON vacations(start_date, end_date)');
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS department_progression_series (
        id TEXT PRIMARY KEY,
        department_name TEXT NOT NULL UNIQUE,
        series_order INTEGER DEFAULT 0,
        is_final_department INTEGER DEFAULT 0,
        remarks TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_dept_progression_order ON department_progression_series(series_order)');
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS class_progression_series (
        id TEXT PRIMARY KEY,
        department_name TEXT NOT NULL DEFAULT '',
        class_name TEXT NOT NULL,
        class_order INTEGER DEFAULT 0,
        series_order INTEGER DEFAULT 0,
        is_last_in_dept INTEGER DEFAULT 0,
        is_final_year INTEGER DEFAULT 0,
        next_department_name TEXT,
        next_class_name TEXT,
        remarks TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_class_progression_dept ON class_progression_series(department_name, class_order)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_class_progression_order ON class_progression_series(series_order)');
    } catch (_) {}

    // Safe migration alters if table was created in previous migration
    try {
      await db.execute("ALTER TABLE class_progression_series ADD COLUMN class_order INTEGER DEFAULT 0");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE class_progression_series ADD COLUMN is_last_in_dept INTEGER DEFAULT 0");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE class_progression_series ADD COLUMN next_department_name TEXT");
    } catch (_) {}
  }

  // ─── Direct Student Persistence Helpers (Offline First) ───────
  Future<void> saveStudentDirectly(Map<String, dynamic> rawData) async {
    final db = await database;
    final Map<String, dynamic> cleanMap = Map<String, dynamic>.from(rawData);

    // Remove complex nested objects that aren't SQLite columns
    cleanMap.remove('documents');
    if (cleanMap['sub_departments'] != null && cleanMap['sub_departments'] is! String) {
      try {
        cleanMap['sub_departments'] = jsonEncode(cleanMap['sub_departments']);
      } catch (_) {
        cleanMap['sub_departments'] = null;
      }
    }
    if (cleanMap['is_active'] is bool) {
      cleanMap['is_active'] = cleanMap['is_active'] == true ? 1 : 0;
    }

    // Filter by columns that actually exist in the students table
    final tableInfo = await db.rawQuery("PRAGMA table_info(students)");
    final validColumns = tableInfo.map((c) => c['name']?.toString()).whereType<String>().toSet();

    final toSave = <String, dynamic>{};
    for (final entry in cleanMap.entries) {
      if (validColumns.contains(entry.key)) {
        toSave[entry.key] = entry.value;
      }
    }

    final id = toSave['id']?.toString().trim();
    final grNo = toSave['gr_no']?.toString().trim();

    if (id != null && id.isNotEmpty) {
      final existing = await db.query('students', where: 'id = ?', whereArgs: [id]);
      if (existing.isNotEmpty) {
        await db.update('students', toSave, where: 'id = ?', whereArgs: [id]);
        return;
      }
    }
    if (grNo != null && grNo.isNotEmpty) {
      final existingGr = await db.query('students', where: 'gr_no = ?', whereArgs: [grNo]);
      if (existingGr.isNotEmpty) {
        await db.update('students', toSave, where: 'gr_no = ?', whereArgs: [grNo]);
        return;
      }
    }
    await db.insert('students', toSave, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getStudentDirectly(String id) async {
    final db = await database;
    final rows = await db.query('students', where: 'id = ? OR gr_no = ?', whereArgs: [id, id], limit: 1);
    if (rows.isNotEmpty) return rows.first;
    return null;
  }

  Future<List<Student>> getStudentsForStaff({
    required String staffId,
    String? staffNo,
    String? staffName,
  }) async {
    final cleanStaffId = staffId.trim().toLowerCase();
    final cleanStaffNo = staffNo?.trim().toLowerCase() ?? '';
    final cleanStaffName = staffName?.trim().toLowerCase() ?? '';

    final List<Map<String, dynamic>> rawRows = [];
    final seenIds = <String>{};

    // 1. Check REST API first if server is running
    try {
      final response = await ApiClient().get('/students');
      if (response.data is List) {
        for (final item in response.data) {
          if (item is Map) {
            rawRows.add(Map<String, dynamic>.from(item));
          }
        }
      }
    } catch (_) {}

    // 2. Query Local SQLite database
    try {
      final db = await database;
      final localRows = await db.query('students');
      for (final r in localRows) {
        final id = r['id']?.toString() ?? '';
        if (!rawRows.any((x) => x['id']?.toString() == id)) {
          rawRows.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (_) {}

    final List<Student> matchingStudents = [];

    for (final row in rawRows) {
      final sId = row['id']?.toString() ?? '';
      if (sId.isEmpty || seenIds.contains(sId)) continue;

      final sStaffId = (row['staff_id']?.toString() ?? '').trim().toLowerCase();
      final sStaffName = (row['staff_name']?.toString() ?? '').trim().toLowerCase();
      final contribId = (row['contributor_id']?.toString() ?? '').trim().toLowerCase();
      final contribName = (row['contributor_name']?.toString() ?? '').trim().toLowerCase();
      final fatherName = (row['father_name']?.toString() ?? '').trim().toLowerCase();
      final condType = (row['condition_type']?.toString() ?? '').trim().toLowerCase();
      final feeStructure = row['fee_structure']?.toString() ?? '';

      bool isMatch = false;

      // Match 1: Direct match on staff_id
      if (cleanStaffId.isNotEmpty && (sStaffId == cleanStaffId || sStaffId.contains(cleanStaffId))) {
        isMatch = true;
      } else if (cleanStaffNo.isNotEmpty && sStaffId == cleanStaffNo) {
        isMatch = true;
      }
      // Match 2: Direct match on contributor_id
      else if (cleanStaffId.isNotEmpty && (contribId == cleanStaffId || contribId.contains(cleanStaffId))) {
        isMatch = true;
      } else if (cleanStaffNo.isNotEmpty && contribId == cleanStaffNo) {
        isMatch = true;
      }
      // Match 3: Name match on staff_name or contributor_name
      else if (cleanStaffName.isNotEmpty && (sStaffName == cleanStaffName || contribName == cleanStaffName)) {
        isMatch = true;
      }
      // Match 4: Father name match if condition mentions staff
      else if (condType.contains('staff') && cleanStaffName.isNotEmpty && fatherName.isNotEmpty &&
          (fatherName == cleanStaffName || cleanStaffName.contains(fatherName) || fatherName.contains(cleanStaffName))) {
        isMatch = true;
      }
      // Match 5: Check inside fee_structure JSON
      else if (feeStructure.isNotEmpty) {
        final feeLower = feeStructure.toLowerCase();
        if (cleanStaffId.isNotEmpty && feeLower.contains(cleanStaffId)) {
          isMatch = true;
        } else if (cleanStaffNo.isNotEmpty && feeLower.contains(cleanStaffNo)) {
          isMatch = true;
        }
      }

      if (isMatch) {
        seenIds.add(sId);
        try {
          matchingStudents.add(Student.fromJson(row));
        } catch (_) {}
      }
    }

    matchingStudents.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return matchingStudents;
  }

  Future<List<Student>> getStudentsForContributor({
    required String contributorId,
    String? contributorName,
  }) async {
    final cleanContribId = contributorId.trim().toLowerCase();
    final cleanContribName = contributorName?.trim().toLowerCase() ?? '';

    if (cleanContribId.isEmpty && cleanContribName.isEmpty) {
      return [];
    }

    final List<Map<String, dynamic>> rawRows = [];
    final seenIds = <String>{};

    // 1. Check REST API first if server is running
    try {
      final response = await ApiClient().get('/students');
      if (response.data is List) {
        for (final item in response.data) {
          if (item is Map) {
            rawRows.add(Map<String, dynamic>.from(item));
          }
        }
      }
    } catch (_) {}

    // 2. Query Local SQLite database
    try {
      final db = await database;
      final localRows = await db.query('students');
      for (final r in localRows) {
        final id = r['id']?.toString() ?? '';
        if (!rawRows.any((x) => x['id']?.toString() == id)) {
          rawRows.add(Map<String, dynamic>.from(r));
        }
      }
    } catch (_) {}

    final List<Student> matchingStudents = [];

    for (final row in rawRows) {
      final sId = row['id']?.toString() ?? '';
      if (sId.isEmpty || seenIds.contains(sId)) continue;

      final sContribId = (row['contributor_id']?.toString() ?? '').trim().toLowerCase();
      final sContribName = (row['contributor_name']?.toString() ?? '').trim().toLowerCase();
      final feeStructure = row['fee_structure']?.toString() ?? '';

      bool isMatch = false;

      // Match 1: Direct exact match on contributor_id (both must be non-empty)
      if (cleanContribId.isNotEmpty && sContribId.isNotEmpty && sContribId == cleanContribId) {
        isMatch = true;
      }
      // Match 2: Exact match on contributor_name (both MUST be non-empty)
      else if (cleanContribName.isNotEmpty && sContribName.isNotEmpty && sContribName == cleanContribName) {
        isMatch = true;
      }
      // Match 3: Check inside fee_structure JSON
      else if (feeStructure.isNotEmpty) {
        try {
          final decoded = jsonDecode(feeStructure);
          if (decoded is Map) {
            final fId = (decoded['contributor_id']?.toString() ?? '').trim().toLowerCase();
            final fName = (decoded['contributor_name']?.toString() ?? '').trim().toLowerCase();
            if (cleanContribId.isNotEmpty && fId.isNotEmpty && fId == cleanContribId) {
              isMatch = true;
            } else if (cleanContribName.isNotEmpty && fName.isNotEmpty && fName == cleanContribName) {
              isMatch = true;
            }
          }
        } catch (_) {}
      }

      if (isMatch) {
        seenIds.add(sId);
        try {
          matchingStudents.add(Student.fromJson(row));
        } catch (_) {}
      }
    }

    matchingStudents.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return matchingStudents;
  }

  // ─── Academic History & Promotion Helpers ───────────────────
  Future<List<Map<String, dynamic>>> getStudentAcademicHistory(String studentId) async {
    final db = await database;
    return await db.query(
      'student_academic_history',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'created_at DESC, academic_year DESC',
    );
  }

  Future<int> insertAcademicHistory(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(
      'student_academic_history',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateAcademicHistory(String id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'student_academic_history',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAcademicHistory(String id) async {
    final db = await database;
    return await db.delete(
      'student_academic_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> calculateStudentAcademicSummary(
    String studentId, {
    String? academicYear,
    String? classId,
    double? fallbackMonthlyFees,
    double? fallbackAdmissionFee,
    double? fallbackBookFee,
    String? fallbackFeeStructure,
    Map<String, dynamic>? sessionConfig,
  }) async {
    final db = await database;
    int totalAtt = 0;
    int presentAtt = 0;
    double attPct = 0.0;

    // 1. Fetch live attendance from backend REST API & sync to local SQLite
    bool fetchedOnlineAtt = false;
    List<Map<String, dynamic>> allAttendanceRecords = [];
    List<Map<String, dynamic>> monthlyAttendanceSummary = [];
    List<Map<String, dynamic>> allFeePayments = [];

    try {
      final attRes = await ApiClient().get('/attendance/student/$studentId');
      if (attRes.data is Map) {
        final data = attRes.data as Map;
        totalAtt = (data['total_days'] as num?)?.toInt() ?? 0;
        presentAtt = (data['present_days'] as num?)?.toInt() ?? 0;
        attPct = (data['percentage'] as num?)?.toDouble() ?? (totalAtt > 0 ? double.parse(((presentAtt / totalAtt) * 100).toStringAsFixed(1)) : 0.0);
        fetchedOnlineAtt = true;

        final records = data['records'] as List?;
        if (records != null) {
          allAttendanceRecords = List<Map<String, dynamic>>.from(records);
          for (final r in records) {
            try {
              await db.insert('attendance', {
                'id': r['id']?.toString() ?? 'att_${DateTime.now().millisecondsSinceEpoch}',
                'student_id': studentId,
                'date': r['date']?.toString() ?? DateTime.now().toIso8601String().split('T')[0],
                'status': r['status']?.toString() ?? 'Present',
                'remarks': r['remarks']?.toString() ?? '',
                'check_in_time': r['check_in_time']?.toString() ?? '',
                'check_out_time': r['check_out_time']?.toString() ?? '',
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            } catch (_) {}
          }
        }
        final mSum = data['monthly_summary'] as List?;
        if (mSum != null) {
          monthlyAttendanceSummary = List<Map<String, dynamic>>.from(mSum);
        }
      }
    } catch (_) {}

    // Fallback to local SQLite attendance table if offline
    if (!fetchedOnlineAtt) {
      try {
        final attRows = await db.rawQuery(
          "SELECT status, COUNT(*) as cnt FROM attendance WHERE student_id = ? GROUP BY status",
          [studentId],
        );
        for (final r in attRows) {
          final cnt = (r['cnt'] as num?)?.toInt() ?? 0;
          totalAtt += cnt;
          final st = (r['status']?.toString() ?? '').toLowerCase();
          if (st == 'present' || st == 'p' || st == 'hazir') {
            presentAtt += cnt;
          }
        }
        if (totalAtt > 0) {
          attPct = double.parse(((presentAtt / totalAtt) * 100).toStringAsFixed(1));
        }
        final localRecords = await db.query(
          'attendance',
          where: 'student_id = ?',
          whereArgs: [studentId],
          orderBy: 'date DESC',
        );
        allAttendanceRecords = List<Map<String, dynamic>>.from(localRecords);
      } catch (_) {}
    }

    double totalMax = 0.0;
    double totalObt = 0.0;
    double examPct = 0.0;
    String grade = '-';
    final List<Map<String, dynamic>> booksList = [];

    try {
      List<Map<String, dynamic>> markRows;
      if (classId != null && classId.isNotEmpty) {
        markRows = await db.rawQuery('''
          SELECT m.max_marks, m.marks_obtained, m.is_absent, m.book_id, m.book_name, m.exam_id, e.name as exam_name
          FROM exam_marks m
          LEFT JOIN exams e ON e.id = m.exam_id
          WHERE m.student_id = ? AND (m.class_id = ? OR m.class_name = ?)
          ORDER BY m.book_name ASC, m.exam_id ASC
        ''', [studentId, classId, classId]);
      } else {
        markRows = await db.rawQuery('''
          SELECT m.max_marks, m.marks_obtained, m.is_absent, m.book_id, m.book_name, m.exam_id, e.name as exam_name
          FROM exam_marks m
          LEFT JOIN exams e ON e.id = m.exam_id
          WHERE m.student_id = ?
          ORDER BY m.book_name ASC, m.exam_id ASC
        ''', [studentId]);
      }

      final Map<String, Map<String, dynamic>> bookGroup = {};
      for (final m in markRows) {
        final bName = m['book_name']?.toString().trim() ?? 'General';
        if (!bookGroup.containsKey(bName)) {
          bookGroup[bName] = {
            'book_id': m['book_id']?.toString() ?? '',
            'book_name': bName,
            'exams': <Map<String, dynamic>>[],
            'total_max': 0.0,
            'total_obtained': 0.0,
          };
        }
        final maxM = (m['max_marks'] as num?)?.toDouble() ?? 100.0;
        final obtM = (m['marks_obtained'] as num?)?.toDouble() ?? 0.0;
        final isAbs = m['is_absent'] == 1;
        final exName = m['exam_name']?.toString().trim() ?? 'Exam ${m['exam_id']}';

        totalMax += maxM;
        if (!isAbs) {
          totalObt += obtM;
        }

        (bookGroup[bName]!['exams'] as List<Map<String, dynamic>>).add({
          'exam_id': m['exam_id']?.toString(),
          'exam_name': exName,
          'max_marks': maxM,
          'marks_obtained': isAbs ? 0.0 : obtM,
          'is_absent': isAbs,
          'percentage': maxM > 0 ? double.parse(((obtM / maxM) * 100).toStringAsFixed(1)) : 0.0,
        });
        bookGroup[bName]!['total_max'] = (bookGroup[bName]!['total_max'] as double) + maxM;
        bookGroup[bName]!['total_obtained'] = (bookGroup[bName]!['total_obtained'] as double) + (isAbs ? 0.0 : obtM);
      }

      for (final bg in bookGroup.values) {
        final bMax = bg['total_max'] as double;
        final bObt = bg['total_obtained'] as double;
        bg['percentage'] = bMax > 0 ? double.parse(((bObt / bMax) * 100).toStringAsFixed(1)) : 0.0;
        booksList.add(bg);
      }

      if (totalMax > 0) {
        examPct = double.parse(((totalObt / totalMax) * 100).toStringAsFixed(1));
        if (examPct >= 85) {
          grade = 'Mumtaz (A+)';
        } else if (examPct >= 70) {
          grade = 'Jayyid Jiddan (A)';
        } else if (examPct >= 60) {
          grade = 'Jayyid (B)';
        } else if (examPct >= 45) {
          grade = 'Maqbool (C)';
        } else {
          grade = 'Rasib (Fail)';
        }
      }
    } catch (_) {}

    // Fees & Expense calculation (Dynamic based on Madarsah Start/End Dates & Online REST API sync)
    double feeTotal = 0.0;
    double feePaid = 0.0;
    double feePending = 0.0;
    int totalPendingMonths = 0;
    int totalPaidMonths = 0;
    double perStudentExpense = 15000.0;
    List<Map<String, dynamic>> feeBreakdownList = [];

    try {
      final cfg = sessionConfig ?? await getCurrentAcademicSessionConfig();
      if (cfg['annual_student_expense'] != null) {
        perStudentExpense = (cfg['annual_student_expense'] as num).toDouble();
      }

      // Calculate academic session months from Madarsah Start Date and End Date
      final startDateStr = cfg['start_date']?.toString();
      final endDateStr = cfg['end_date']?.toString();
      int sessionMonths = 12;
      if (startDateStr != null && endDateStr != null) {
        try {
          final start = DateTime.parse(startDateStr.trim());
          final end = DateTime.parse(endDateStr.trim());
          if (!end.isBefore(start)) {
            int m = (end.year - start.year) * 12 + (end.month - start.month);
            if (end.day >= 15) m += 1;
            if (start.day > 20) m -= 1;
            if (m > 0) sessionMonths = m;
          }
        } catch (_) {}
      }

      // 1. Resolve Monthly Fees, Admission Fee, Book Fee, Fee Structure (from parameter, local db, or API)
      double monthlyFees = (fallbackMonthlyFees != null && fallbackMonthlyFees > 0) ? fallbackMonthlyFees : 0.0;
      double admissionFee = (fallbackAdmissionFee != null && fallbackAdmissionFee > 0) ? fallbackAdmissionFee : 0.0;
      double bookFee = (fallbackBookFee != null && fallbackBookFee > 0) ? fallbackBookFee : 0.0;
      String? feeStructureStr = (fallbackFeeStructure != null && fallbackFeeStructure.trim().isNotEmpty && fallbackFeeStructure != 'null') ? fallbackFeeStructure : null;

      try {
        final sRows = await db.query('students', columns: ['monthly_fees', 'admission_fee', 'book_fee', 'fee_structure'], where: 'id = ?', whereArgs: [studentId]);
        if (sRows.isNotEmpty) {
          if (monthlyFees <= 0) {
            monthlyFees = (sRows.first['monthly_fees'] as num?)?.toDouble() ?? 0.0;
          }
          if (admissionFee <= 0) {
            admissionFee = (sRows.first['admission_fee'] as num?)?.toDouble() ?? 0.0;
          }
          if (bookFee <= 0) {
            bookFee = (sRows.first['book_fee'] as num?)?.toDouble() ?? 0.0;
          }
          if (feeStructureStr == null) {
            feeStructureStr = sRows.first['fee_structure']?.toString();
          }
        }
      } catch (_) {}

      if (monthlyFees <= 0 || (admissionFee <= 0 && bookFee <= 0 && feeStructureStr == null)) {
        try {
          final sRes = await ApiClient().get('/students/$studentId');
          if (sRes.data is Map) {
            final d = sRes.data as Map;
            if (monthlyFees <= 0 && d['monthly_fees'] != null) {
              monthlyFees = (d['monthly_fees'] as num).toDouble();
            }
            if (admissionFee <= 0 && d['admission_fee'] != null) {
              admissionFee = (d['admission_fee'] as num).toDouble();
            }
            if (bookFee <= 0 && d['book_fee'] != null) {
              bookFee = (d['book_fee'] as num).toDouble();
            }
            if (feeStructureStr == null && d['fee_structure'] != null) {
              feeStructureStr = d['fee_structure']?.toString();
            }
          }
        } catch (_) {}
      }

      // 2. Fetch fee payments: Fetch online API AND local SQLite, merge without duplicates
      final Set<String> seenPaymentKeys = {};
      allFeePayments = [];

      try {
        final feeRes = await ApiClient().get('/fees/student/$studentId');
        if (feeRes.data is List) {
          for (final p in (feeRes.data as List)) {
            final pMap = p is Map<String, dynamic> ? Map<String, dynamic>.from(p) : (p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{});
            final pId = pMap['id']?.toString() ?? 'fee_${pMap['payment_date']}_${pMap['amount']}';
            seenPaymentKeys.add(pId);
            allFeePayments.add(pMap);

            // Cache to local SQLite fees table
            try {
              final amt = (pMap['amount'] as num?)?.toDouble() ?? 0.0;
              await db.insert('fees', {
                'id': pId,
                'student_id': studentId,
                'amount': amt,
                'payment_date': pMap['payment_date']?.toString() ?? DateTime.now().toIso8601String().split('T')[0],
                'fee_type': pMap['fee_type']?.toString() ?? 'Fee',
                'status': pMap['status']?.toString() ?? 'Paid',
                'remarks': pMap['remarks']?.toString(),
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            } catch (_) {}
          }
        }
      } catch (_) {}

      // Always merge local SQLite fees table records so offline payments are never lost
      try {
        final localFeeRows = await db.query(
          'fees',
          where: 'student_id = ?',
          whereArgs: [studentId],
          orderBy: 'payment_date DESC',
        );
        for (final r in localFeeRows) {
          final rId = r['id']?.toString() ?? '';
          final rKey = rId.isNotEmpty ? rId : 'fee_${r['payment_date']}_${r['amount']}_${r['fee_type']}';
          if (!seenPaymentKeys.contains(rId) && !seenPaymentKeys.contains(rKey)) {
            seenPaymentKeys.add(rKey);
            allFeePayments.add(Map<String, dynamic>.from(r));
          }
        }
      } catch (_) {}

      // Sort payments newest first
      allFeePayments.sort((a, b) {
        final dA = a['payment_date']?.toString() ?? '';
        final dB = b['payment_date']?.toString() ?? '';
        return dB.compareTo(dA);
      });

      // Compute total fee paid across all completed payments
      feePaid = 0.0;
      for (final p in allFeePayments) {
        final st = (p['status']?.toString() ?? '').toLowerCase();
        if (st == 'paid' || st == 'completed' || st.isEmpty) {
          feePaid += (p['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      // 3. Compute Itemized Fee Breakdown based on feeStructure or individual fee heads
      feeBreakdownList = [];

      if (feeStructureStr != null && feeStructureStr.trim().isNotEmpty && feeStructureStr.trim() != 'null') {
        try {
          final decoded = jsonDecode(feeStructureStr);
          if (decoded is List && decoded.isNotEmpty) {
            for (final item in decoded) {
              final name = item['fee_type_name']?.toString() ?? item['fee_type']?.toString() ?? 'Fee';
              final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
              final billing = item['billing_type']?.toString() ?? 'monthly';
              final rawMonths = item['months_list'] ?? item['specific_months'];
              List<String> monthsList = [];
              if (rawMonths is List) {
                monthsList = rawMonths.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
              }
              final months = (item['months_count'] as num?)?.toInt() ?? (monthsList.isNotEmpty ? monthsList.length : (billing == 'monthly' ? sessionMonths : 1));
              final expected = billing == 'monthly' ? amt * months : amt;

              double paid = 0.0;
              final key = name.toLowerCase().trim();
              for (final p in allFeePayments) {
                final st = (p['status']?.toString() ?? '').toLowerCase();
                if (st == 'paid' || st == 'completed' || st.isEmpty) {
                  final pType = (p['fee_type']?.toString() ?? '').toLowerCase().trim();
                  if (pType == key || pType.contains(key) || key.contains(pType) || (key.contains('tuition') && pType.contains('fee'))) {
                    paid += (p['amount'] as num?)?.toDouble() ?? 0.0;
                  }
                }
              }

              final pending = (expected - paid).clamp(0.0, double.infinity);
              final origAmt = (item['original_amount'] as num?)?.toDouble() ?? amt;
              final discAmt = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
              final discTag = item['discount_tag']?.toString() ?? '';

              int paidMonths = 0;
              int pendingMonths = 0;
              if (billing == 'monthly') {
                paidMonths = amt > 0 ? (paid / amt).floor() : 0;
                if (paidMonths > months) paidMonths = months;
                pendingMonths = (months - paidMonths).clamp(0, months);
              } else {
                paidMonths = (paid >= expected && expected > 0) ? 1 : 0;
                pendingMonths = (expected - paid) > 0 ? 1 : 0;
              }

              feeBreakdownList.add({
                'fee_type_id': item['fee_type_id'],
                'fee_type_name': name,
                'amount': amt,
                'original_amount': origAmt,
                'discount_amount': discAmt,
                'discount_tag': discTag,
                'billing_type': billing,
                'months_count': months,
                'months_list': monthsList,
                'paid_months': paidMonths,
                'pending_months': pendingMonths,
                'total_expected': expected,
                'total_paid': paid,
                'total_pending': pending,
              });
            }
          }
        } catch (_) {}
      }

      if (feeBreakdownList.isEmpty) {
        double tuitionPaid = 0.0;
        double admissionPaid = 0.0;
        double bookPaid = 0.0;
        for (final p in allFeePayments) {
          final st = (p['status']?.toString() ?? '').toLowerCase();
          if (st == 'paid' || st == 'completed' || st.isEmpty) {
            final pType = (p['fee_type']?.toString() ?? '').toLowerCase().trim();
            final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
            if (pType.contains('admission') || pType.contains('dakhila')) {
              admissionPaid += amt;
            } else if (pType.contains('book') || pType.contains('kitab')) {
              bookPaid += amt;
            } else {
              tuitionPaid += amt;
            }
          }
        }

        final tExp = monthlyFees * sessionMonths;
        final tPaidMonths = monthlyFees > 0 ? (tuitionPaid / monthlyFees).floor().clamp(0, sessionMonths) : 0;
        final tPendingMonths = (sessionMonths - tPaidMonths).clamp(0, sessionMonths);
        feeBreakdownList.add({
          'fee_type_name': 'Tuition Fee',
          'amount': monthlyFees,
          'billing_type': 'monthly',
          'months_count': sessionMonths,
          'months_list': <String>[],
          'paid_months': tPaidMonths,
          'pending_months': tPendingMonths,
          'total_expected': tExp,
          'total_paid': tuitionPaid,
          'total_pending': (tExp - tuitionPaid).clamp(0.0, double.infinity),
        });

        if (admissionFee > 0) {
          final aPending = (admissionFee - admissionPaid).clamp(0.0, double.infinity);
          feeBreakdownList.add({
            'fee_type_name': 'Admission Fee',
            'amount': admissionFee,
            'billing_type': 'one_time',
            'months_count': 1,
            'months_list': <String>[],
            'paid_months': admissionPaid >= admissionFee ? 1 : 0,
            'pending_months': aPending > 0 ? 1 : 0,
            'total_expected': admissionFee,
            'total_paid': admissionPaid,
            'total_pending': aPending,
          });
        }

        if (bookFee > 0) {
          final bPending = (bookFee - bookPaid).clamp(0.0, double.infinity);
          feeBreakdownList.add({
            'fee_type_name': 'Book Fee',
            'amount': bookFee,
            'billing_type': 'yearly',
            'months_count': 1,
            'months_list': <String>[],
            'paid_months': bookPaid >= bookFee ? 1 : 0,
            'pending_months': bPending > 0 ? 1 : 0,
            'total_expected': bookFee,
            'total_paid': bookPaid,
            'total_pending': bPending,
          });
        }
      }

      // Calculate total pending months across monthly fee heads
      totalPendingMonths = 0;
      totalPaidMonths = 0;
      for (final h in feeBreakdownList) {
        if (h['billing_type'] == 'monthly') {
          totalPendingMonths += (h['pending_months'] as num?)?.toInt() ?? 0;
          totalPaidMonths += (h['paid_months'] as num?)?.toInt() ?? 0;
        }
      }

      feeTotal = feeBreakdownList.fold<double>(0.0, (sum, h) => sum + (h['total_expected'] as num).toDouble());
      feePaid = feeBreakdownList.fold<double>(0.0, (sum, h) => sum + (h['total_paid'] as num).toDouble());
      if (feeTotal <= 0 && feePaid > 0) {
        feeTotal = feePaid;
      }
      feePending = (feeTotal - feePaid).clamp(0.0, double.infinity);
    } catch (_) {}

    return {
      'total_attendance_days': totalAtt,
      'present_days': presentAtt,
      'attendance_percentage': attPct,
      'attendance_records': allAttendanceRecords,
      'attendance_monthly_summary': monthlyAttendanceSummary,
      'total_marks': totalMax,
      'obtained_marks': totalObt,
      'exam_percentage': examPct,
      'result_grade': grade,
      'books_marks': booksList,
      'books_marks_json': jsonEncode(booksList),
      'fee_total': feeTotal,
      'fee_paid': feePaid,
      'fee_pending': feePending,
      'fee_pending_months': totalPendingMonths,
      'fee_paid_months': totalPaidMonths,
      'fee_payments': allFeePayments,
      'fee_breakdown': feeBreakdownList,
      'per_student_expense': perStudentExpense,
    };
  }

  // ─── Fee Types Helpers ─────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getFeeTypes() async {
    final db = await database;
    try {
      return await db.query('fee_types', orderBy: 'name ASC');
    } catch (_) {
      return [];
    }
  }

  Future<int> insertFeeType(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('fee_types', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateFeeType(String id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update('fee_types', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteFeeType(String id) async {
    final db = await database;
    return await db.delete('fee_types', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Vacations (تعطیلات) Helpers ─────────────────────────────
  Future<List<Map<String, dynamic>>> getVacations({String? academicYearId}) async {
    final db = await database;
    try {
      if (academicYearId != null && academicYearId.isNotEmpty) {
        return await db.query(
          'vacations',
          where: 'academic_year_id = ?',
          whereArgs: [academicYearId],
          orderBy: 'start_date ASC',
        );
      }
      return await db.query('vacations', orderBy: 'start_date ASC');
    } catch (_) {
      return [];
    }
  }

  Future<int> insertVacation(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('vacations', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateVacation(String id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update('vacations', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteVacation(String id) async {
    final db = await database;
    return await db.delete('vacations', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Academic Session & Config Helpers ───────────────────────
  Future<Map<String, dynamic>> getCurrentAcademicSessionConfig() async {
    final db = await database;
    try {
      final rows = await db.query('academic_years', where: 'is_current = 1', limit: 1);
      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first);
      }
    } catch (_) {}

    final now = DateTime.now();
    return {
      'id': 'session_${now.year}',
      'year_name': '${now.year}-${now.year + 1}',
      'year_name_hijri': '${now.year - 579}-${now.year - 578} H',
      'start_date': '${now.year}-06-01',
      'end_date': '${now.year + 1}-04-30',
      'auto_promote_enabled': 1,
      'passing_percentage': 40.0,
      'annual_student_expense': 15000.0,
      'is_current': 1,
    };
  }

  Future<void> saveAcademicSessionConfig(Map<String, dynamic> config) async {
    final db = await database;
    final existing = await getCurrentAcademicSessionConfig();
    final updated = Map<String, dynamic>.from(existing)..addAll(config);
    final id = updated['id']?.toString() ?? 'session_${DateTime.now().year}';
    updated['id'] = id;
    updated['is_current'] = 1;

    await db.insert('academic_years', updated, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── Progression Map Helper ─────────────────────────────────
  // ─── Multi-Department & Class Progression Helper ────────────
  Future<String> getNextClassProgression(String? currentClass, List<String> availableClasses, {String? currentDepartment}) async {
    final res = await getNextProgressionForStudent(
      currentClass: currentClass,
      currentDepartment: currentDepartment,
      availableClasses: availableClasses,
    );
    return res['next_class'] ?? 'Farigh';
  }

  Future<Map<String, String?>> getNextProgressionForStudent({
    required String? currentClass,
    String? currentDepartment,
    List<String> availableClasses = const [],
  }) async {
    if (currentClass == null || currentClass.trim().isEmpty) {
      return {
        'next_class': availableClasses.isNotEmpty ? availableClasses.first : 'Awwal',
        'next_department': currentDepartment,
      };
    }
    final c = currentClass.trim();
    final d = (currentDepartment != null && currentDepartment.trim().isNotEmpty) ? currentDepartment.trim() : null;

    final db = await database;

    // 1. Check user-configured Class Progression Series from Database
    try {
      List<Map<String, dynamic>> classRows = [];
      if (d != null) {
        classRows = await db.query(
          'class_progression_series',
          where: 'LOWER(TRIM(class_name)) = LOWER(TRIM(?)) AND LOWER(TRIM(department_name)) = LOWER(TRIM(?))',
          whereArgs: [c, d],
          limit: 1,
        );
      }
      if (classRows.isEmpty) {
        classRows = await db.query(
          'class_progression_series',
          where: 'LOWER(TRIM(class_name)) = LOWER(TRIM(?))',
          whereArgs: [c],
          limit: 1,
        );
      }

      if (classRows.isNotEmpty) {
        final row = classRows.first;
        final rowDept = row['department_name']?.toString().trim() ?? (d ?? '');
        final isFinalYear = (row['is_final_year'] as num?)?.toInt() == 1;
        final isLastInDept = (row['is_last_in_dept'] as num?)?.toInt() == 1;
        final explicitNextClass = row['next_class_name']?.toString().trim();
        final explicitNextDept = row['next_department_name']?.toString().trim();

        // If explicitly graduation / final year
        if (isFinalYear || explicitNextClass == 'Farigh' || explicitNextClass == 'Graduated' || (explicitNextClass != null && explicitNextClass.contains('فارغ'))) {
          return {'next_class': 'Farigh', 'next_department': rowDept};
        }

        // If explicit next class is set (and not Farigh / None)
        if (explicitNextClass != null && explicitNextClass.isNotEmpty && explicitNextClass != 'None' && explicitNextClass != '-') {
          return {
            'next_class': explicitNextClass,
            'next_department': (explicitNextDept != null && explicitNextDept.isNotEmpty) ? explicitNextDept : rowDept,
          };
        }

        final curClassOrder = (row['class_order'] as num?)?.toInt() ?? 0;

        // Check if there is a next class within the same department
        if (!isLastInDept && rowDept.isNotEmpty) {
          final higherClassesInDept = await db.query(
            'class_progression_series',
            where: 'LOWER(TRIM(department_name)) = LOWER(TRIM(?)) AND class_order > ?',
            whereArgs: [rowDept, curClassOrder],
            orderBy: 'class_order ASC',
            limit: 1,
          );

          if (higherClassesInDept.isNotEmpty) {
            final nextClassName = higherClassesInDept.first['class_name']?.toString() ?? '';
            return {
              'next_class': nextClassName,
              'next_department': rowDept,
            };
          }
        }

        // Department finished! Look up the next department in department_progression_series!
        int curDeptOrder = 0;
        if (rowDept.isNotEmpty) {
          final deptRows = await db.query(
            'department_progression_series',
            where: 'LOWER(TRIM(department_name)) = LOWER(TRIM(?))',
            whereArgs: [rowDept],
            limit: 1,
          );
          if (deptRows.isNotEmpty) {
            curDeptOrder = (deptRows.first['series_order'] as num?)?.toInt() ?? 0;
            final isFinalDept = (deptRows.first['is_final_department'] as num?)?.toInt() == 1;
            if (isFinalDept) {
              return {'next_class': 'Farigh', 'next_department': rowDept};
            }
          }
        }

        // Find the next department with series_order > curDeptOrder
        final nextDeptRows = await db.query(
          'department_progression_series',
          where: 'series_order > ?',
          whereArgs: [curDeptOrder],
          orderBy: 'series_order ASC',
          limit: 1,
        );

        if (nextDeptRows.isNotEmpty) {
          final nextDeptName = nextDeptRows.first['department_name']?.toString() ?? '';
          // Find Class 1 of this next department
          final firstClassOfNextDept = await db.query(
            'class_progression_series',
            where: 'LOWER(TRIM(department_name)) = LOWER(TRIM(?))',
            whereArgs: [nextDeptName],
            orderBy: 'class_order ASC',
            limit: 1,
          );

          if (firstClassOfNextDept.isNotEmpty) {
            final nextClassName = firstClassOfNextDept.first['class_name']?.toString() ?? '';
            return {
              'next_class': nextClassName,
              'next_department': nextDeptName,
            };
          } else {
            return {
              'next_class': 'Class 1',
              'next_department': nextDeptName,
            };
          }
        } else {
          // No more departments -> Student is Farigh / Graduated!
          return {'next_class': 'Farigh', 'next_department': rowDept};
        }
      }
    } catch (_) {}

    // 2. Fallback to default standard Islamic Madarsa sequence chain
    final fallbackNext = _getDefaultNextClass(c, availableClasses);
    return {
      'next_class': fallbackNext,
      'next_department': d,
    };
  }

  // ─── Department Progression Series CRUD ──────────────────────
  Future<List<Map<String, dynamic>>> getDepartmentProgressionSeries() async {
    final db = await database;
    try {
      final realDepts = await db.rawQuery(
        "SELECT id, name as department_name FROM departments WHERE (parent_id IS NULL OR parent_id = '' OR parent_id = 'null') AND is_active = 1 ORDER BY created_at ASC",
      );

      final rows = await db.query('department_progression_series', orderBy: 'series_order ASC, department_name ASC');

      if (realDepts.isNotEmpty) {
        final realDeptNames = realDepts
            .map((d) => d['department_name']?.toString().trim().toLowerCase())
            .whereType<String>()
            .toSet();

        final validRows = rows.where((r) {
          final dName = r['department_name']?.toString().trim().toLowerCase();
          return dName != null && realDeptNames.contains(dName);
        }).toList();

        if (validRows.isNotEmpty) {
          return validRows;
        }

        // Progression series is either empty or contained old dummy rows -> seed from real departments!
        final List<Map<String, dynamic>> seeded = [];
        for (int i = 0; i < realDepts.length; i++) {
          final r = realDepts[i];
          seeded.add({
            'id': 'dps_${r['id']}',
            'department_name': r['department_name'],
            'series_order': i + 1,
            'is_final_department': i == realDepts.length - 1 ? 1 : 0,
          });
        }
        await saveDepartmentProgressionSeries(seeded);
        return seeded;
      } else if (rows.isNotEmpty) {
        return rows;
      }
    } catch (_) {}

    return [];
  }

  Future<void> saveDepartmentProgressionSeries(List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('department_progression_series');
      for (final item in items) {
        final id = item['id']?.toString() ?? 'dps_${DateTime.now().millisecondsSinceEpoch}_${item['department_name']}';
        final map = Map<String, dynamic>.from(item);
        map['id'] = id;
        map['updated_at'] = DateTime.now().toIso8601String();
        await txn.insert('department_progression_series', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteDepartmentProgressionItem(String id) async {
    final db = await database;
    await db.delete('department_progression_series', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Class Progression Series CRUD ──────────────────────────
  Future<List<Map<String, dynamic>>> getClassProgressionSeries({String? departmentName}) async {
    final db = await database;
    try {
      final String whereClause = (departmentName != null && departmentName.trim().isNotEmpty)
          ? 'WHERE LOWER(TRIM(c.department_name)) = LOWER(TRIM(?))'
          : '';
      final List<dynamic> whereArgs = (departmentName != null && departmentName.trim().isNotEmpty)
          ? [departmentName.trim()]
          : [];

      final rows = await db.rawQuery('''
        SELECT c.*, COALESCE(d.series_order, 999) as dept_order
        FROM class_progression_series c
        LEFT JOIN department_progression_series d ON LOWER(TRIM(d.department_name)) = LOWER(TRIM(c.department_name))
        $whereClause
        ORDER BY dept_order ASC, c.class_order ASC, c.class_name ASC
      ''', whereArgs);

      if (rows.isNotEmpty) {
        return rows;
      }
    } catch (_) {}

    return [];
  }

  String _getDefaultNextClass(String cName, List<String> allClasses) {
    const chain = {
      'تختی': 'قاعدہ',
      'قاعدہ': 'عمّہ پارہ',
      'عمّہ پارہ': 'پہلا حصہ',
      'پہلا حصہ': 'دسرا حصہ',
      'دسرا حصہ': 'تسرا حصہ',
      'تسرا حصہ': 'چوتھا حصہ',
      'چوتھا حصہ': 'بہشتی زیور',
      'بہشتی زیور': 'فارسی اوّل',
      'ناظرہ': 'حفظ',
      'حفظ': 'Farigh',
      'فارسی اول': 'فارسی دوم',
      'فارسی اوّل': 'فارسی دوم',
      'فارسی دوم': 'عربی اول',
      'عربی اول': 'عربی دوم',
      'عربی دوم': 'عربی سوم',
      'عربی سوم': 'عربی چہارم',
      'عربی چہارم': 'عربی پنجم',
      'عربی پنجم': 'عربی ششم',
      'عربی ششم': 'عربی ہفتم',
      'عربی ہفتم': 'دورۂ حدیث شریف',
      'دورۂ حدیث': 'Farigh',
      'دورۂ حدیث شریف': 'Farigh',
      'Awwal': 'Domi',
      'Domi': 'Soem',
      'Soem': 'Chaharum',
      'Chaharum': 'Panjum',
      'Panjum': 'Alimiyat',
    };

    if (chain.containsKey(cName)) return chain[cName]!;
    final idx = allClasses.indexOf(cName);
    if (idx != -1 && idx + 1 < allClasses.length) return allClasses[idx + 1];
    return 'Farigh';
  }

  Future<void> saveClassProgressionSeries(List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('class_progression_series');
      for (final item in items) {
        final id = item['id']?.toString() ?? 'cps_${DateTime.now().millisecondsSinceEpoch}_${item['class_name']}';
        final map = Map<String, dynamic>.from(item);
        map['id'] = id;
        map['updated_at'] = DateTime.now().toIso8601String();
        await txn.insert('class_progression_series', map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteClassProgressionItem(String id) async {
    final db = await database;
    await db.delete('class_progression_series', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Automatic Year-End Promotion Runner ──────────────────────
  Future<Map<String, dynamic>> executeAutomaticYearEndPromotion({
    double? passingPercentage,
    String? academicYear,
    bool force = false,
  }) async {
    final db = await database;
    final config = await getCurrentAcademicSessionConfig();
    final effectivePassPct = passingPercentage ?? (config['passing_percentage'] as num?)?.toDouble() ?? 40.0;
    final yearName = academicYear ?? config['year_name']?.toString() ?? '${DateTime.now().year}-${DateTime.now().year + 1}';
    final hijriYear = config['year_name_hijri']?.toString();
    final endDateStr = config['end_date']?.toString();

    // If not forced, check if today >= session end date
    if (!force && endDateStr != null && endDateStr.isNotEmpty) {
      try {
        final endDate = DateTime.parse(endDateStr);
        final today = DateTime.now();
        final isTodayAfterOrEqual = DateTime(today.year, today.month, today.day)
            .isAfter(DateTime(endDate.year, endDate.month, endDate.day).subtract(const Duration(seconds: 1)));
        if (!isTodayAfterOrEqual) {
          return {
            'success': false,
            'reason': 'Session has not ended yet. End date is $endDateStr.',
            'promoted_count': 0,
            'repeated_count': 0,
            'farigh_count': 0,
            'total_students': 0,
          };
        }
      } catch (_) {}
    }

    final students = await db.query('students', where: 'is_active = 1');
    final classes = await getDistinctClassNames();

    int promotedCount = 0;
    int repeatedCount = 0;
    int farighCount = 0;

    for (final s in students) {
      final studentId = s['id']?.toString() ?? '';
      if (studentId.isEmpty) continue;

      final curClass = s['class_name']?.toString().trim();
      final summary = await calculateStudentAcademicSummary(
        studentId,
        academicYear: yearName,
        classId: curClass,
        fallbackMonthlyFees: (s['monthly_fees'] as num?)?.toDouble(),
      );

      final examPct = (summary['exam_percentage'] as num?)?.toDouble() ?? 0.0;
      final totalMarks = (summary['total_marks'] as num?)?.toDouble() ?? 0.0;
      final isPassed = totalMarks == 0.0 || examPct >= effectivePassPct;

      String nextClass = curClass ?? 'Next Class';
      String? nextDept = s['department_name']?.toString().trim();
      String status = 'Promoted';

      if (isPassed) {
        final prog = await getNextProgressionForStudent(
          currentClass: curClass,
          currentDepartment: s['department_name']?.toString().trim(),
          availableClasses: classes,
        );
        nextClass = prog['next_class'] ?? curClass ?? '';
        nextDept = prog['next_department'] ?? s['department_name']?.toString().trim();

        if (nextClass == 'Farigh' || nextClass.toLowerCase().contains('farigh')) {
          status = 'Farigh';
          farighCount++;
        } else {
          promotedCount++;
        }
      } else {
        status = 'Repeated';
        nextClass = curClass ?? '';
        repeatedCount++;
      }

      final historyId = 'hist_${studentId}_${yearName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      final historyMap = <String, dynamic>{
        'id': historyId,
        'student_id': studentId,
        'academic_year': yearName,
        'academic_year_hijri': hijriYear,
        'class_id': curClass,
        'class_name': curClass ?? '-',
        'department_id': s['department_id'],
        'department_name': s['department_name'],
        'division': s['division'],
        'roll_number': s['roll_number'],
        'total_attendance_days': summary['total_attendance_days'] ?? 0,
        'present_days': summary['present_days'] ?? 0,
        'attendance_percentage': summary['attendance_percentage'] ?? 0.0,
        'total_marks': summary['total_marks'] ?? 0.0,
        'obtained_marks': summary['obtained_marks'] ?? 0.0,
        'exam_percentage': summary['exam_percentage'] ?? 0.0,
        'result_grade': summary['result_grade'] ?? '-',
        'status': status,
        'remarks': isPassed ? 'Auto-promoted at session end' : 'Repeated due to exam result (< $effectivePassPct%)',
        'promoted_at': DateTime.now().toIso8601String(),
        'books_marks_json': summary['books_marks_json'],
        'fee_total': summary['fee_total'] ?? 0.0,
        'fee_paid': summary['fee_paid'] ?? 0.0,
        'fee_pending': summary['fee_pending'] ?? 0.0,
        'per_student_expense': summary['per_student_expense'] ?? 0.0,
      };
      await insertAcademicHistory(historyMap);

      // Cloud & REST API Sync for academic history
      try {
        await FirebaseService.syncStudentAcademicHistory(historyMap);
      } catch (_) {}
      try {
        await ApiClient().post('/students/$studentId/academic-history', data: historyMap);
      } catch (_) {}

      if (status == 'Promoted') {
        final updateMap = <String, dynamic>{
          'class_name': nextClass,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (nextDept != null && nextDept.isNotEmpty) {
          updateMap['department_name'] = nextDept;
          try {
            final deptRow = await db.query(
              'departments',
              columns: ['id'],
              where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
              whereArgs: [nextDept],
              limit: 1,
            );
            if (deptRow.isNotEmpty) {
              updateMap['department_id'] = deptRow.first['id']?.toString();
            }
          } catch (_) {}
        }
        await db.update(
          'students',
          updateMap,
          where: 'id = ?',
          whereArgs: [studentId],
        );

        // Cloud & REST API Sync for updated student
        try {
          final studentRow = await db.query('students', where: 'id = ?', whereArgs: [studentId], limit: 1);
          if (studentRow.isNotEmpty) {
            final stMap = Map<String, dynamic>.from(studentRow.first);
            await FirebaseService.syncStudent(stMap);
            try {
              await ApiClient().put('/students/$studentId', data: stMap);
            } catch (_) {}
          }
        } catch (_) {}
      } else if (status == 'Farigh') {
        await db.update(
          'students',
          {'student_status': 'Graduated', 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [studentId],
        );
        try {
          final studentRow = await db.query('students', where: 'id = ?', whereArgs: [studentId], limit: 1);
          if (studentRow.isNotEmpty) {
            final stMap = Map<String, dynamic>.from(studentRow.first);
            await FirebaseService.syncStudent(stMap);
            try {
              await ApiClient().put('/students/$studentId', data: stMap);
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    final nowIso = DateTime.now().toIso8601String();
    await saveAcademicSessionConfig({'auto_promoted_at': nowIso});
    try {
      final updatedConfig = await getCurrentAcademicSessionConfig();
      await FirebaseService.syncAcademicSessionConfig(updatedConfig);
    } catch (_) {}

    return {
      'success': true,
      'promoted_count': promotedCount,
      'repeated_count': repeatedCount,
      'farigh_count': farighCount,
      'total_students': students.length,
      'executed_at': nowIso,
    };
  }

  Future<Map<String, dynamic>?> checkAndTriggerAutoPromotionIfNeeded() async {
    try {
      final config = await getCurrentAcademicSessionConfig();
      final isEnabled = (config['auto_promote_enabled'] as num?)?.toInt() == 1;
      final autoPromotedAt = config['auto_promoted_at']?.toString();
      final endDateStr = config['end_date']?.toString();

      if (!isEnabled || (autoPromotedAt != null && autoPromotedAt.isNotEmpty) || endDateStr == null || endDateStr.isEmpty) {
        return null;
      }

      final endDate = DateTime.parse(endDateStr);
      final today = DateTime.now();
      final isEnded = DateTime(today.year, today.month, today.day)
          .isAfter(DateTime(endDate.year, endDate.month, endDate.day).subtract(const Duration(seconds: 1)));

      if (isEnded) {
        return await executeAutomaticYearEndPromotion(force: true);
      }
    } catch (_) {}
    return null;
  }

  // ─── Query Academic History for Explorer (Tools & Operations) ──
  Future<List<Map<String, dynamic>>> queryAcademicHistory({
    String? studentId,
    String? className,
    String? departmentId,
    String? academicYear,
    String? status,
    String? searchQuery,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (studentId != null && studentId.trim().isNotEmpty) {
      conditions.add('h.student_id = ?');
      args.add(studentId.trim());
    }
    if (className != null && className.trim().isNotEmpty && className != 'All') {
      conditions.add('h.class_name = ?');
      args.add(className.trim());
    }
    if (departmentId != null && departmentId.trim().isNotEmpty && departmentId != 'All') {
      conditions.add('(h.department_id = ? OR h.department_name = ?)');
      args.add(departmentId.trim());
      args.add(departmentId.trim());
    }
    if (academicYear != null && academicYear.trim().isNotEmpty && academicYear != 'All') {
      conditions.add('h.academic_year = ?');
      args.add(academicYear.trim());
    }
    if (status != null && status.trim().isNotEmpty && status != 'All') {
      conditions.add('h.status = ?');
      args.add(status.trim());
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('(s.full_name LIKE ? OR s.registration_number LIKE ? OR s.gr_no LIKE ? OR h.roll_number LIKE ?)');
      final term = '%${searchQuery.trim()}%';
      args.addAll([term, term, term, term]);
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

    final sql = '''
      SELECT h.*, 
             s.full_name as student_full_name, 
             s.father_name as student_father_name, 
             s.registration_number as student_registration_number,
             s.gr_no as student_gr_no,
             s.photo_path as student_photo_path
      FROM student_academic_history h
      LEFT JOIN students s ON s.id = h.student_id
      $whereClause
      ORDER BY h.academic_year DESC, h.class_name ASC, h.roll_number ASC
    ''';

    try {
      return await db.rawQuery(sql, args);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllAcademicYears() async {
    final db = await database;
    try {
      final list = await db.query('academic_years', orderBy: 'year_name DESC');
      if (list.isNotEmpty) return list;
    } catch (_) {}

    final now = DateTime.now().year;
    return [
      {'id': 'yr_$now', 'year_name': '$now-${now + 1}', 'year_name_hijri': '${now - 579}-${now - 578} H', 'is_current': 1},
      {'id': 'yr_${now - 1}', 'year_name': '${now - 1}-$now', 'year_name_hijri': '${now - 580}-${now - 579} H', 'is_current': 0},
      {'id': 'yr_${now - 2}', 'year_name': '${now - 2}-${now - 1}', 'year_name_hijri': '${now - 581}-${now - 580} H', 'is_current': 0},
      {'id': 'yr_${now + 1}', 'year_name': '${now + 1}-${now + 2}', 'year_name_hijri': '${now - 578}-${now - 577} H', 'is_current': 0},
    ];
  }

  Future<int> insertAcademicYear(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert(
      'academic_years',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> getDistinctClassNames({String? departmentName}) async {
    final db = await database;
    final List<String> orderedClasses = [];
    final Set<String> seen = <String>{};

    // 1. From class_progression_series ordered by dept_order ASC, class_order ASC
    try {
      final String whereClause = (departmentName != null && departmentName.trim().isNotEmpty)
          ? 'WHERE LOWER(TRIM(c.department_name)) = LOWER(TRIM(?))'
          : '';
      final List<dynamic> whereArgs = (departmentName != null && departmentName.trim().isNotEmpty)
          ? [departmentName.trim()]
          : [];

      final seriesClasses = await db.rawQuery('''
        SELECT c.class_name, COALESCE(d.series_order, 999) as dept_order, c.class_order
        FROM class_progression_series c
        LEFT JOIN department_progression_series d ON LOWER(TRIM(d.department_name)) = LOWER(TRIM(c.department_name))
        $whereClause
        ORDER BY dept_order ASC, c.class_order ASC, c.class_name ASC
      ''', whereArgs);

      for (final r in seriesClasses) {
        final cName = r['class_name']?.toString().trim();
        if (cName != null && cName.isNotEmpty && !seen.contains(cName.toLowerCase())) {
          seen.add(cName.toLowerCase());
          orderedClasses.add(cName);
        }
      }
    } catch (_) {}

    // 2. From classes table (active class names)
    try {
      final clsResults = await db.rawQuery(
        "SELECT DISTINCT name FROM classes WHERE is_active = 1 AND name IS NOT NULL AND LENGTH(TRIM(name)) > 0 ORDER BY name ASC",
      );
      for (final r in clsResults) {
        final n = r['name']?.toString().trim();
        if (n != null && n.isNotEmpty && !seen.contains(n.toLowerCase())) {
          seen.add(n.toLowerCase());
          orderedClasses.add(n);
        }
      }
    } catch (_) {}

    // 3. From students table (class names currently assigned)
    try {
      final stuResults = await db.rawQuery(
        "SELECT DISTINCT class_name FROM students WHERE class_name IS NOT NULL AND LENGTH(TRIM(class_name)) > 0 ORDER BY class_name ASC",
      );
      for (final r in stuResults) {
        final n = r['class_name']?.toString().trim();
        if (n != null && n.isNotEmpty && !seen.contains(n.toLowerCase())) {
          seen.add(n.toLowerCase());
          orderedClasses.add(n);
        }
      }
    } catch (_) {}

    if (orderedClasses.isNotEmpty) {
      return orderedClasses;
    }

    return ['تختی', 'قاعدہ', 'عمّہ پارہ', 'پہلا حصہ', 'ناظرہ', 'حفظ', 'فارسی اول', 'فارسی دوم', 'عربی اول', 'عربی دوم', 'عربی سوم', 'عربی چہارم', 'عربی پنجم', 'عربی ششم', 'عربی ہفتم', 'دورۂ حدیث شریف'];
  }

  Future<List<String>> getDistinctDepartments() async {
    final db = await database;
    final List<String> orderedDepts = [];
    final Set<String> seen = <String>{};

    // 1. From department_progression_series ordered by series_order ASC
    try {
      final seriesDepts = await db.query(
        'department_progression_series',
        orderBy: 'series_order ASC, department_name ASC',
      );
      for (final r in seriesDepts) {
        final d = r['department_name']?.toString().trim();
        if (d != null && d.isNotEmpty && !seen.contains(d.toLowerCase())) {
          seen.add(d.toLowerCase());
          orderedDepts.add(d);
        }
      }
    } catch (_) {}

    // 2. From students table
    try {
      final res = await db.rawQuery(
        "SELECT DISTINCT department_name FROM students WHERE department_name IS NOT NULL AND LENGTH(TRIM(department_name)) > 0 ORDER BY department_name ASC",
      );
      for (final r in res) {
        final d = r['department_name']?.toString().trim();
        if (d != null && d.isNotEmpty && !seen.contains(d.toLowerCase())) {
          seen.add(d.toLowerCase());
          orderedDepts.add(d);
        }
      }
    } catch (_) {}

    // 3. From student_academic_history table
    try {
      final resHist = await db.rawQuery(
        "SELECT DISTINCT department_name FROM student_academic_history WHERE department_name IS NOT NULL AND LENGTH(TRIM(department_name)) > 0 ORDER BY department_name ASC",
      );
      for (final r in resHist) {
        final d = r['department_name']?.toString().trim();
        if (d != null && d.isNotEmpty && !seen.contains(d.toLowerCase())) {
          seen.add(d.toLowerCase());
          orderedDepts.add(d);
        }
      }
    } catch (_) {}

    if (orderedDepts.isNotEmpty) {
      return orderedDepts;
    }

    return ['دینیات (Diniyat)', 'حفظ و ناظرہ (Hifz & Nazra)', 'فارسی (Farsi)', 'درسِ نظامی / عالمیت (Alimiyat)'];
  }

  Future<File> getDatabaseFile() async {
    final path = await _resolveDatabasePath();
    return File(path);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
