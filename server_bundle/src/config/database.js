const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

function resolveDatabasePath() {
  if (process.env.DB_PATH) {
    return path.resolve(__dirname, '../../', process.env.DB_PATH);
  }

  if (process.platform === 'darwin') {
    const homeDir = process.env.HOME || ('/Users/' + (process.env.USER || 'default'));
    const appSupportDir = path.join(homeDir, 'Library', 'Application Support', 'MadarsaManagement');
    try {
      if (!fs.existsSync(appSupportDir)) {
        fs.mkdirSync(appSupportDir, { recursive: true });
      }
    } catch (e) {
      console.error('Failed to create App Support directory on macOS:', e.message);
    }

    const targetDb = path.join(appSupportDir, 'database.sqlite');
    // If not exists in Application Support, copy from bundle seed if available
    if (!fs.existsSync(targetDb)) {
      const seedDb = path.resolve(__dirname, '../../database.sqlite');
      if (fs.existsSync(seedDb)) {
        try {
          fs.copyFileSync(seedDb, targetDb);
          console.log(`[Database] Seed database copied to writable macOS path: ${targetDb}`);
        } catch (e) {
          console.warn(`[Database] Could not copy seed database: ${e.message}`);
          return seedDb;
        }
      }
    }
    return targetDb;
  }

  return path.resolve(__dirname, '../../database.sqlite');
}

const dbPath = resolveDatabasePath();
console.log(`[Database] Connected to SQLite database: ${dbPath}`);
const db = new Database(dbPath);

const RBAC_MODULES = [
  'dashboard',
  'students',
  'staff',
  'attendance',
  'fees',
  'classes',
  'exams',
  'kitchen',
  'purchases',
  'hostel',
  'library',
  'reports',
  'notifications',
  'roles',
  'settings',
  'users',
];
const RBAC_ACTIONS = ['view', 'create', 'edit', 'delete'];
const CUSTOM_ROLES = [
  { name: 'Teacher', desc: 'Can manage classes, attendance, exams' },
  { name: 'Student', desc: 'Can view own profile, timetable, marks' },
  { name: 'Parent', desc: 'Can view child details, attendance, fees' },
  { name: 'Kitchen Staff (Bavarchi)', desc: 'Can manage daily food menu, ration' },
  { name: 'Nazim-e-Matbakh', desc: 'Kitchen admin, controls menu & stock' },
  { name: 'Office Staff', desc: 'General office management activities' },
];

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

function initializeDatabase() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      full_name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      avatar TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS roles (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      is_system INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS permissions (
      id TEXT PRIMARY KEY,
      module TEXT NOT NULL,
      action TEXT NOT NULL,
      description TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(module, action)
    );

    CREATE TABLE IF NOT EXISTS role_permissions (
      role_id TEXT NOT NULL,
      permission_id TEXT NOT NULL,
      PRIMARY KEY (role_id, permission_id),
      FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
      FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS user_roles (
      user_id TEXT NOT NULL,
      role_id TEXT NOT NULL,
      PRIMARY KEY (user_id, role_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS activity_logs (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      action TEXT NOT NULL,
      module TEXT,
      details TEXT,
      ip_address TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT,
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS licenses (
      id TEXT PRIMARY KEY,
      license_key TEXT UNIQUE NOT NULL,
      customer_name TEXT NOT NULL,
      institution_name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      tier TEXT NOT NULL DEFAULT 'pro',
      custom_modules TEXT,
      max_devices INTEGER DEFAULT 1,
      max_students INTEGER DEFAULT 0,
      issued_at TEXT NOT NULL,
      expires_at TEXT,
      price REAL DEFAULT 0,
      status TEXT DEFAULT 'active',
      notes TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS license_devices (
      id TEXT PRIMARY KEY,
      license_id TEXT NOT NULL,
      hwid TEXT NOT NULL,
      device_name TEXT,
      os_info TEXT,
      ip_address TEXT,
      first_activated_at TEXT DEFAULT (datetime('now')),
      last_heartbeat_at TEXT DEFAULT (datetime('now')),
      is_blocked INTEGER DEFAULT 0,
      FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE,
      UNIQUE(license_id, hwid)
    );

    CREATE TABLE IF NOT EXISTS subscription_plans (
      id TEXT PRIMARY KEY,
      plan_code TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      price REAL DEFAULT 0,
      validity_days INTEGER DEFAULT 365,
      max_devices INTEGER DEFAULT 1,
      is_lifetime INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      sort_order INTEGER DEFAULT 0,
      features_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS license_logs (
      id TEXT PRIMARY KEY,
      license_id TEXT,
      hwid TEXT,
      event_type TEXT NOT NULL,
      details TEXT,
      ip_address TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

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
      mobile_no TEXT,
      aadhaar_no TEXT,
      class_name TEXT,
      student_status TEXT DEFAULT 'Old',
      admission_type TEXT DEFAULT 'New',
      admission_date TEXT DEFAULT (date('now')),
      admission_date_h TEXT,
      condition_type TEXT DEFAULT 'Regular',
      monthly_fees REAL DEFAULT 0,
      gender TEXT,
      enrollment_date TEXT DEFAULT (date('now')),
      is_active INTEGER DEFAULT 1,
      category TEXT,
      division TEXT,
      face_data TEXT,
      fingerprint_data TEXT,
      biometric_enrolled_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS pin_codes (
      id TEXT PRIMARY KEY,
      pin_code TEXT NOT NULL,
      village TEXT,
      taluka TEXT,
      district TEXT,
      state TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS student_documents (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      document_name TEXT NOT NULL,
      file_path TEXT NOT NULL,
      uploaded_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS attendance (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      date TEXT NOT NULL,
      status TEXT CHECK(status IN ('Present', 'Absent', 'Late')) NOT NULL,
      remarks TEXT,
      check_in_time TEXT,
      check_out_time TEXT,
      verification_method TEXT DEFAULT 'Manual',
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS staff_attendance (
      id TEXT PRIMARY KEY,
      staff_id TEXT NOT NULL,
      date TEXT NOT NULL,
      status TEXT CHECK(status IN ('Present', 'Absent', 'Late')) NOT NULL,
      check_in_time TEXT,
      remarks TEXT,
      verification_method TEXT CHECK(verification_method IN ('Face', 'Fingerprint', 'Manual', 'Mobile')) DEFAULT 'Manual',
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS fees (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      amount REAL NOT NULL,
      payment_date TEXT,
      fee_type TEXT NOT NULL,
      status TEXT CHECK(status IN ('Paid', 'Pending')) NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS donation_types (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS donations (
      id TEXT PRIMARY KEY,
      receipt_no TEXT,
      donor_name TEXT,
      donor_phone TEXT,
      village TEXT,
      taluka TEXT,
      district TEXT,
      state TEXT,
      country TEXT DEFAULT 'India',
      pin_code TEXT,
      amount REAL NOT NULL,
      donation_type TEXT NOT NULL,
      payment_method TEXT DEFAULT 'Cash',
      payment_date TEXT DEFAULT (date('now')),
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS fee_types (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS admissions (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      parent_name TEXT NOT NULL,
      date_of_birth TEXT NOT NULL,
      gender TEXT NOT NULL,
      class_name TEXT NOT NULL,
      phone TEXT NOT NULL,
      address TEXT,
      status TEXT CHECK(status IN ('Pending', 'Approved', 'Rejected')) DEFAULT 'Pending',
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS classes (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      duration TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS gallery (
      id TEXT PRIMARY KEY,
      title TEXT,
      image_path TEXT NOT NULL,
      category TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

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
      is_active INTEGER DEFAULT 1,
      note TEXT,
      role_id TEXT,
      user_id TEXT,
      photo_path TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS staff_documents (
      id TEXT PRIMARY KEY,
      staff_id TEXT NOT NULL,
      document_name TEXT NOT NULL,
      document_type TEXT,
      file_path TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS staff_types (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS qualifications (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS departments (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      head_name TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS courses (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS books (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      author TEXT,
      category TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS class_courses (
      id TEXT PRIMARY KEY,
      class_id TEXT NOT NULL,
      course_id TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
      FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE,
      UNIQUE(class_id, course_id)
    );

    CREATE TABLE IF NOT EXISTS course_books (
      id TEXT PRIMARY KEY,
      class_course_id TEXT NOT NULL,
      book_id TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (class_course_id) REFERENCES class_courses(id) ON DELETE CASCADE,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
      UNIQUE(class_course_id, book_id)
    );

    CREATE TABLE IF NOT EXISTS staff_books (
      id TEXT PRIMARY KEY,
      staff_id TEXT NOT NULL,
      course_book_id TEXT NOT NULL,
      assigned_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE,
      FOREIGN KEY (course_book_id) REFERENCES course_books(id) ON DELETE CASCADE,
      UNIQUE(staff_id, course_book_id)
    );

    CREATE TABLE IF NOT EXISTS exams (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      start_date TEXT,
      end_date TEXT,
      status TEXT DEFAULT 'DRAFT',
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS exam_schedules (
      id TEXT PRIMARY KEY,
      exam_id TEXT REFERENCES exams(id) ON DELETE CASCADE,
      class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,
      book_id TEXT REFERENCES books(id) ON DELETE CASCADE,
      exam_date TEXT,
      start_time TEXT,
      end_time TEXT,
      max_marks INTEGER NOT NULL,
      passing_marks INTEGER,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS exam_halls (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      total_rows INTEGER,
      total_columns INTEGER,
      total_capacity INTEGER,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS seating_arrangements (
      id TEXT PRIMARY KEY,
      exam_id TEXT REFERENCES exams(id) ON DELETE CASCADE,
      hall_id TEXT REFERENCES exam_halls(id) ON DELETE CASCADE,
      student_id TEXT REFERENCES students(id) ON DELETE CASCADE,
      book_id TEXT REFERENCES books(id),
      seat_row INTEGER,
      seat_column INTEGER,
      seat_number INTEGER,
      session_date TEXT,
      session_time TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(student_id, book_id, exam_id)
    );

    CREATE TABLE IF NOT EXISTS seat_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id TEXT,
      book_id TEXT,
      hall_id INTEGER,
      seat_row INTEGER,
      seat_column INTEGER,
      exam_id INTEGER,
      session_date TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_seat_history_hall_student ON seat_history(hall_id, student_id);

    CREATE TABLE IF NOT EXISTS exam_results (
      id TEXT PRIMARY KEY,
      exam_id TEXT NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
      student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
      book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      marks_obtained REAL NOT NULL DEFAULT 0,
      max_marks REAL NOT NULL DEFAULT 100,
      passing_marks REAL NOT NULL DEFAULT 40,
      grade TEXT,
      remarks TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(exam_id, student_id, book_id)
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS contributors (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      address TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_contributors_phone ON contributors(phone);

    CREATE TABLE IF NOT EXISTS academic_years (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      hijri_name TEXT,
      start_date TEXT,
      end_date TEXT,
      is_current INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

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
      promoted_at TEXT DEFAULT (datetime('now')),
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS idx_student_history_student ON student_academic_history(student_id);
    CREATE INDEX IF NOT EXISTS idx_student_history_year ON student_academic_history(academic_year);
  `);

  try {
    db.prepare('ALTER TABLE students ADD COLUMN address TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN contributor_id TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN contributor_amount REAL DEFAULT 0').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE attendance ADD COLUMN check_in_time TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE attendance ADD COLUMN check_out_time TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE staff_attendance ADD COLUMN check_out_time TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE attendance ADD COLUMN shift_id TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE attendance ADD COLUMN shift_name TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS period_attendance (
      id TEXT PRIMARY KEY,
      student_id TEXT NOT NULL,
      class_id TEXT NOT NULL,
      period_id TEXT,
      period_number INTEGER NOT NULL,
      date TEXT NOT NULL,
      status TEXT CHECK(status IN ('Present', 'Absent', 'Late')) NOT NULL,
      time TEXT,
      remarks TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
      UNIQUE(student_id, date, period_number)
    );
    CREATE INDEX IF NOT EXISTS idx_period_att_class_date ON period_attendance(class_id, date, period_number);
  `);

  try {
    db.prepare('ALTER TABLE students ADD COLUMN admission_fee REAL DEFAULT 0').run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE students ADD COLUMN book_fee REAL DEFAULT 0').run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE students ADD COLUMN fee_structure TEXT').run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE students ADD COLUMN face_data TEXT').run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE students ADD COLUMN fingerprint_data TEXT').run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE students ADD COLUMN biometric_enrolled_at TEXT').run();
  } catch (e) {}

  try {
    db.prepare("ALTER TABLE fee_types ADD COLUMN billing_type TEXT DEFAULT 'monthly'").run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE fee_types ADD COLUMN default_months INTEGER DEFAULT 12').run();
  } catch (e) {}

  try {
    db.prepare('ALTER TABLE fee_types ADD COLUMN default_amount REAL DEFAULT 0').run();
  } catch (e) {}

  const histCols = [
    { name: 'fee_total', type: 'REAL DEFAULT 0' },
    { name: 'fee_paid', type: 'REAL DEFAULT 0' },
    { name: 'fee_pending', type: 'REAL DEFAULT 0' },
    { name: 'per_student_expense', type: 'REAL DEFAULT 0' },
    { name: 'books_marks_json', type: 'TEXT' },
    { name: 'metadata_json', type: 'TEXT' }
  ];
  for (const col of histCols) {
    try {
      db.prepare(`ALTER TABLE student_academic_history ADD COLUMN ${col.name} ${col.type}`).run();
    } catch (e) {
      // Ignore if column already exists
    }
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS class_book_periods (
      id TEXT PRIMARY KEY,
      class_id TEXT NOT NULL,
      book_id TEXT NOT NULL,
      period_number INTEGER NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
      FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
      UNIQUE(class_id, book_id, period_number)
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS madarsa_shifts (
      id TEXT PRIMARY KEY,
      shift_name TEXT NOT NULL,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      sort_order INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS kitchen_menu (
      id TEXT PRIMARY KEY,
      day_of_week TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      items TEXT NOT NULL,
      notes TEXT,
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(day_of_week, meal_type)
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS kitchen_stock (
      id TEXT PRIMARY KEY,
      item_name TEXT UNIQUE NOT NULL,
      quantity REAL DEFAULT 0,
      unit TEXT NOT NULL,
      min_threshold REAL DEFAULT 0,
      updated_at TEXT DEFAULT (datetime('now'))
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS kitchen_stock_transactions (
      id TEXT PRIMARY KEY,
      stock_id TEXT NOT NULL,
      transaction_type TEXT NOT NULL,
      quantity REAL NOT NULL,
      unit TEXT NOT NULL,
      remarks TEXT,
      transaction_date TEXT DEFAULT (date('now')),
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (stock_id) REFERENCES kitchen_stock(id) ON DELETE CASCADE
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS kitchen_expenses (
      id TEXT PRIMARY KEY,
      item_name TEXT NOT NULL,
      amount REAL NOT NULL,
      expense_date TEXT NOT NULL,
      remarks TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS kitchen_meal_plans (
      id TEXT PRIMARY KEY,
      plan_date TEXT NOT NULL,
      meal_type TEXT NOT NULL,
      menu_items TEXT NOT NULL,
      expected_count INTEGER DEFAULT 0,
      status TEXT DEFAULT 'Planned',
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(plan_date, meal_type)
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS units (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS general_stock (
      id TEXT PRIMARY KEY,
      item_name TEXT UNIQUE NOT NULL,
      quantity REAL NOT NULL DEFAULT 0.0,
      unit TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'General',
      min_threshold REAL NOT NULL DEFAULT 0.0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS general_stock_transactions (
      id TEXT PRIMARY KEY,
      stock_id TEXT NOT NULL,
      transaction_type TEXT NOT NULL, -- 'In' or 'Out'
      quantity REAL NOT NULL,
      unit TEXT NOT NULL,
      remarks TEXT,
      transaction_date TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (stock_id) REFERENCES general_stock(id) ON DELETE CASCADE
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS purchase_categories (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS purchase_sell_transactions (
      id TEXT PRIMARY KEY,
      receipt_no TEXT NOT NULL,
      type TEXT NOT NULL, -- 'Purchase' or 'Sell'
      category TEXT NOT NULL DEFAULT 'Other',
      transaction_date TEXT NOT NULL, -- YYYY-MM-DD
      contact_person TEXT,
      total_price REAL NOT NULL,
      remarks TEXT,
      items_json TEXT NOT NULL, -- JSON array of items: [{"item_name":"...","quantity":1.0,"unit":"...","price_per_unit":1.0,"total_price":1.0}]
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  try {
    db.prepare('ALTER TABLE books ADD COLUMN category TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }
  
  try {
    db.prepare('ALTER TABLE students ADD COLUMN category TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN division TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN roll_number TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN department_id TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN department_name TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE students ADD COLUMN sub_departments TEXT').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE classes ADD COLUMN department_id TEXT REFERENCES departments(id) ON DELETE SET NULL').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    db.prepare('ALTER TABLE departments ADD COLUMN parent_id TEXT REFERENCES departments(id) ON DELETE SET NULL').run();
  } catch (e) {
    // Ignore if column already exists
  }

  try {
    const indexes = db.pragma('index_list(classes)');
    const hasUnique = indexes.some(idx => idx.unique == 1 && idx.origin !== 'pk');
    if (hasUnique) {
      db.exec(`
        CREATE TABLE IF NOT EXISTS classes_non_unique (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          duration TEXT,
          department_id TEXT,
          is_active INTEGER DEFAULT 1,
          created_at TEXT DEFAULT (datetime('now'))
        );
        INSERT OR IGNORE INTO classes_non_unique (id, name, description, duration, department_id, is_active, created_at)
        SELECT id, name, description, duration, department_id, is_active, created_at FROM classes;
        DROP TABLE classes;
        ALTER TABLE classes_non_unique RENAME TO classes;
      `);
    }
  } catch (e) {
    // Migration already ran or handled
  }

  db.exec(`
    CREATE TABLE IF NOT EXISTS hostels (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS hostel_rooms (
      id TEXT PRIMARY KEY,
      hostel_id TEXT NOT NULL,
      room_number TEXT NOT NULL,
      description TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (hostel_id) REFERENCES hostels(id) ON DELETE CASCADE,
      UNIQUE(hostel_id, room_number)
    );

    CREATE TABLE IF NOT EXISTS hostel_beds (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL,
      bed_number TEXT NOT NULL,
      description TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (room_id) REFERENCES hostel_rooms(id) ON DELETE CASCADE,
      UNIQUE(room_id, bed_number)
    );

    CREATE TABLE IF NOT EXISTS hostel_allocations (
      id TEXT PRIMARY KEY,
      bed_id TEXT NOT NULL,
      student_id TEXT NOT NULL,
      allocation_date TEXT NOT NULL,
      status TEXT CHECK(status IN ('Active', 'Vacated')) DEFAULT 'Active',
      vacate_date TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (bed_id) REFERENCES hostel_beds(id) ON DELETE CASCADE,
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE
    );
  `);

  db.exec(`
    CREATE TABLE IF NOT EXISTS library_settings (
      id TEXT PRIMARY KEY DEFAULT 'default',
      fine_per_day REAL DEFAULT 5.0,
      max_books_per_student INTEGER DEFAULT 3,
      default_due_days INTEGER DEFAULT 14,
      lost_book_fine REAL DEFAULT 500.0,
      lost_book_found_fine REAL DEFAULT 100.0,
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS library_categories (
      id TEXT PRIMARY KEY,
      name TEXT UNIQUE NOT NULL,
      description TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS library_books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT,
      isbn TEXT,
      category_id TEXT,
      publisher TEXT,
      language TEXT DEFAULT 'Urdu',
      total_copies INTEGER DEFAULT 1,
      available_copies INTEGER DEFAULT 1,
      shelf_location TEXT,
      description TEXT,
      added_date TEXT DEFAULT (date('now')),
      default_due_days INTEGER,
      lost_book_fine REAL,
      lost_book_found_fine REAL,
      fine_per_day REAL,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (category_id) REFERENCES library_categories(id) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS library_transactions (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      student_id TEXT,
      staff_id TEXT,
      borrower_name TEXT,
      hostel_name TEXT,
      room_number TEXT,
      bed_number TEXT,
      issue_date TEXT NOT NULL,
      due_date TEXT NOT NULL,
      return_date TEXT,
      status TEXT CHECK(status IN ('Issued', 'Returned', 'Overdue', 'Lost')) DEFAULT 'Issued',
      fine_amount REAL DEFAULT 0,
      remarks TEXT,
      issued_by TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (book_id) REFERENCES library_books(id) ON DELETE CASCADE,
      FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
      FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
    );

    INSERT OR IGNORE INTO library_settings (id) VALUES ('default');
  `);

  // Migration: add lost_book_found_fine column if missing
  try {
    const settingsCols = db.prepare("PRAGMA table_info(library_settings)").all();
    if (!settingsCols.some(c => c.name === 'lost_book_found_fine')) {
      db.prepare('ALTER TABLE library_settings ADD COLUMN lost_book_found_fine REAL DEFAULT 100.0').run();
      console.log('Added lost_book_found_fine column to library_settings');
    }
  } catch (e) {
    // column already exists
  }

  try {
    const columns = db.prepare("PRAGMA table_info(library_transactions)").all();
    const hasStaffId = columns.some(c => c.name === 'staff_id');
    const studentCol = columns.find(c => c.name === 'student_id');
    const isStudentIdNullable = studentCol && studentCol.notnull === 0;
    const hasHostelName = columns.some(c => c.name === 'hostel_name');
    const hasBorrowerName = columns.some(c => c.name === 'borrower_name');
    
    if (!hasStaffId || !isStudentIdNullable || !hasHostelName || !hasBorrowerName) {
      console.log('Migrating library_transactions table to support staff allocations and hostel/borrower details...');
      db.exec('PRAGMA foreign_keys = OFF');
      
      try {
        db.exec('DROP TABLE IF EXISTS library_transactions_old');
      } catch (e) {}

      db.exec('ALTER TABLE library_transactions RENAME TO library_transactions_old');
      db.exec(`
        CREATE TABLE library_transactions (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          student_id TEXT,
          staff_id TEXT,
          borrower_name TEXT,
          hostel_name TEXT,
          room_number TEXT,
          bed_number TEXT,
          issue_date TEXT NOT NULL,
          due_date TEXT NOT NULL,
          return_date TEXT,
          status TEXT CHECK(status IN ('Issued', 'Returned', 'Overdue', 'Lost')) DEFAULT 'Issued',
          fine_amount REAL DEFAULT 0,
          remarks TEXT,
          issued_by TEXT,
          created_at TEXT DEFAULT (datetime('now')),
          FOREIGN KEY (book_id) REFERENCES library_books(id) ON DELETE CASCADE,
          FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE,
          FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
        );
      `);
      
      const oldCols = db.prepare("PRAGMA table_info(library_transactions_old)").all();
      const oldHasStaffId = oldCols.some(c => c.name === 'staff_id');
      const oldHasHostelName = oldCols.some(c => c.name === 'hostel_name');
      const oldHasBorrowerName = oldCols.some(c => c.name === 'borrower_name');

      const staffSelect = oldHasStaffId ? 'staff_id' : 'NULL AS staff_id';
      const borrowerSelect = oldHasBorrowerName ? 'borrower_name' : 'NULL AS borrower_name';
      const hostelSelect = oldHasHostelName ? 'hostel_name, room_number, bed_number' : 'NULL AS hostel_name, NULL AS room_number, NULL AS bed_number';

      db.exec(`
        INSERT INTO library_transactions (
          id, book_id, student_id, staff_id, borrower_name, hostel_name, room_number, bed_number, issue_date, due_date, return_date, status, fine_amount, remarks, issued_by, created_at
        )
        SELECT 
          id, book_id, student_id, ${staffSelect}, ${borrowerSelect}, ${hostelSelect}, issue_date, due_date, return_date, status, fine_amount, remarks, issued_by, created_at
        FROM library_transactions_old;
      `);
      db.exec('DROP TABLE library_transactions_old');
      db.exec('PRAGMA foreign_keys = ON');
      console.log('library_transactions table migrated successfully!');
    }
  } catch (e) {
    db.exec('PRAGMA foreign_keys = ON');
    console.error('Error during library_transactions migration:', e.message);
  }

  try {
    const bookColumns = db.prepare("PRAGMA table_info(library_books)").all();
    if (!bookColumns.some(c => c.name === 'default_due_days')) {
      db.prepare('ALTER TABLE library_books ADD COLUMN default_due_days INTEGER').run();
      console.log('Added default_due_days column to library_books');
    }
    if (!bookColumns.some(c => c.name === 'lost_book_fine')) {
      db.prepare('ALTER TABLE library_books ADD COLUMN lost_book_fine REAL').run();
      console.log('Added lost_book_fine column to library_books');
    }
    if (!bookColumns.some(c => c.name === 'lost_book_found_fine')) {
      db.prepare('ALTER TABLE library_books ADD COLUMN lost_book_found_fine REAL').run();
      console.log('Added lost_book_found_fine column to library_books');
    }
    if (!bookColumns.some(c => c.name === 'fine_per_day')) {
      db.prepare('ALTER TABLE library_books ADD COLUMN fine_per_day REAL').run();
      console.log('Added fine_per_day column to library_books');
    }
  } catch (e) {
    console.error('Error migrating library_books table:', e.message);
  }

  seedDefaults();
  // seedReportsData(); // Disabled to prevent auto-recreating dummy students
}

function seedReportsData() {
  return; // Disabled to prevent auto-recreating dummy students

  console.log('Seeding dummy data for reports...');

  const students = [
    { id: uuidv4(), reg: 'REG001', name: 'Ahmad Khan', gender: 'Male', class: 'Class 1' },
    { id: uuidv4(), reg: 'REG002', name: 'Fatima Zahra', gender: 'Female', class: 'Class 1' },
    { id: uuidv4(), reg: 'REG003', name: 'Zaid Ali', gender: 'Male', class: 'Class 2' },
    { id: uuidv4(), reg: 'REG004', name: 'Maryam Bibi', gender: 'Female', class: 'Class 2' },
    { id: uuidv4(), reg: 'REG005', name: 'Omar Farooq', gender: 'Male', class: 'Class 3' },
  ];

  const insertStudent = db.prepare(`
    INSERT INTO students (id, registration_number, full_name, gender, class_name)
    VALUES (?, ?, ?, ?, ?)
  `);

  const insertAttendance = db.prepare(`
    INSERT INTO attendance (id, student_id, date, status)
    VALUES (?, ?, ?, ?)
  `);

  const insertFee = db.prepare(`
    INSERT INTO fees (id, student_id, amount, payment_date, fee_type, status)
    VALUES (?, ?, ?, ?, ?, ?)
  `);

  const transaction = db.transaction(() => {
    const today = new Date().toISOString().split('T')[0];
    const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];

    for (const s of students) {
      insertStudent.run(s.id, s.reg, s.name, s.gender, s.class);
      
      // Attendance for today and yesterday
      insertAttendance.run(uuidv4(), s.id, today, Math.random() > 0.1 ? 'Present' : 'Absent');
      insertAttendance.run(uuidv4(), s.id, yesterday, Math.random() > 0.2 ? 'Present' : 'Late');

      // Fees
      insertFee.run(uuidv4(), s.id, 1500.0, today, 'Monthly Fee', 'Paid');
      insertFee.run(uuidv4(), s.id, 500.0, null, 'Admission Fee', 'Pending');
    }
  });

  transaction();
}

function seedDefaults() {
  const { v4: uuidv4 } = require('uuid');
  const bcrypt = require('bcryptjs');

  const getPermission = db.prepare(
    'SELECT id FROM permissions WHERE module = ? AND action = ?',
  );
  const insertPermission = db.prepare(`
    INSERT INTO permissions (id, module, action, description)
    VALUES (?, ?, ?, ?)
  `);
  const getRoleByName = db.prepare('SELECT id FROM roles WHERE name = ?');
  const insertRole = db.prepare(`
    INSERT INTO roles (id, name, description, is_system)
    VALUES (?, ?, ?, ?)
  `);
  const assignRolePermission = db.prepare(`
    INSERT OR IGNORE INTO role_permissions (role_id, permission_id)
    VALUES (?, ?)
  `);
  const getUserByUsername = db.prepare('SELECT id FROM users WHERE username = ?');
  const insertUser = db.prepare(`
    INSERT INTO users (id, username, password, full_name, email)
    VALUES (?, ?, ?, ?, ?)
  `);
  const assignUserRole = db.prepare(`
    INSERT OR IGNORE INTO user_roles (user_id, role_id)
    VALUES (?, ?)
  `);

  const seedTransaction = db.transaction(() => {
    let adminRole = getRoleByName.get('Admin');
    if (!adminRole) {
      const adminRoleId = uuidv4();
      insertRole.run(
        adminRoleId,
        'Admin',
        'Super Administrator with full access',
        1,
      );
      adminRole = { id: adminRoleId };
    }

    for (const moduleName of RBAC_MODULES) {
      for (const action of RBAC_ACTIONS) {
        let permission = getPermission.get(moduleName, action);
        if (!permission) {
          const permissionId = uuidv4();
          insertPermission.run(
            permissionId,
            moduleName,
            action,
            `${action} ${moduleName}`,
          );
          permission = { id: permissionId };
        }

        assignRolePermission.run(adminRole.id, permission.id);
      }
    }

    let adminUser = getUserByUsername.get('admin');
    if (!adminUser) {
      const superAdminId = uuidv4();
      const hashedPassword = bcrypt.hashSync('admin123', 10);
      insertUser.run(
        superAdminId,
        'admin',
        hashedPassword,
        'Super Admin',
        'admin@madarsa.com',
      );
      adminUser = { id: superAdminId };
      console.log('Default admin user created (username: admin, password: admin123)');
    }

    assignUserRole.run(adminUser.id, adminRole.id);

    for (const role of CUSTOM_ROLES) {
      const existingRole = getRoleByName.get(role.name);
      if (!existingRole) {
        const roleId = uuidv4();
        insertRole.run(roleId, role.name, role.desc, 0);

        // Assign default kitchen permissions to kitchen roles
        if (role.name === 'Nazim-e-Matbakh') {
          const kitPerms = db.prepare("SELECT id FROM permissions WHERE module = 'kitchen'").all();
          for (const p of kitPerms) {
            assignRolePermission.run(roleId, p.id);
          }
        } else if (role.name === 'Kitchen Staff (Bavarchi)') {
          const kitPerms = db.prepare("SELECT id FROM permissions WHERE module = 'kitchen' AND action IN ('view', 'create', 'edit')").all();
          for (const p of kitPerms) {
            assignRolePermission.run(roleId, p.id);
          }
        }
      }
    }

    // Insert Default Website Settings
    const insertSetting = db.prepare('INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)');
    insertSetting.run('website_about', 'Welcome to Jamia Islamia Madarsa, a center of excellence for Islamic education. We offer comprehensive courses in Hifz, Nazra, and Dars-e-Nizami, nurturing the next generation of scholars.');
    insertSetting.run('website_contact_phone', '+91 9876543210');
    insertSetting.run('website_contact_email', 'info@madarsa.com');
    insertSetting.run('website_address', '123 Islamic Center, Guidance City, India');
    insertSetting.run('website_map_url', 'https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d112061.09262729906!2d77.1656810237937!3d28.627259021272658!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x390cfd5b347eb62d%3A0x37205b715389640!2sDelhi!5e0!3m2!1sen!2sin!4v1709462705000!5m2!1sen!2sin');
    insertSetting.run('hijri_adjustment', '0');
    insertSetting.run('madarsa_open_time', '08:00');
    insertSetting.run('madarsa_close_time', '17:00');
    insertSetting.run('late_grace_minutes', '15');

    // Seed default madarsa shift
    const existingShifts = db.prepare('SELECT COUNT(*) as count FROM madarsa_shifts').get();
    if (existingShifts.count === 0) {
      db.prepare('INSERT INTO madarsa_shifts (id, shift_name, start_time, end_time, sort_order) VALUES (?, ?, ?, ?, ?)').run(uuidv4(), 'Morning', '08:00', '13:00', 1);
    }

    // Seed default donation categories
    const existingDonationTypes = db.prepare('SELECT COUNT(*) as count FROM donation_types').get();
    if (existingDonationTypes.count === 0) {
      const defaultTypes = ['Zakat', 'Fitrah', 'Wajib Sadqah', 'Lillah', 'Qurbani'];
      const insertDonationType = db.prepare('INSERT INTO donation_types (id, name) VALUES (?, ?)');
      for (const name of defaultTypes) {
        insertDonationType.run(uuidv4(), name);
      }
    }

    // Seed default fee types
    const existingFeeTypes = db.prepare('SELECT COUNT(*) as count FROM fee_types').get();
    if (existingFeeTypes.count === 0) {
      const defaultFeeTypes = ['Tuition Fee', 'Admission Fee', 'Exam Fee', 'Hostel Fee', 'Book Fee', 'Other'];
      const insertFeeType = db.prepare('INSERT INTO fee_types (id, name) VALUES (?, ?)');
      for (const name of defaultFeeTypes) {
        insertFeeType.run(uuidv4(), name);
      }
    }

    // Seed default kitchen weekly menus
    const existingMenu = db.prepare('SELECT COUNT(*) as count FROM kitchen_menu').get();
    if (existingMenu.count === 0) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      const meals = [
        { type: 'Breakfast', items: 'Chai, Roti, Butter', notes: 'Served at 7:30 AM' },
        { type: 'Lunch', items: 'Dal, Chawal (Rice), Aloo Sabzi', notes: 'Served at 1:30 PM' },
        { type: 'Dinner', items: 'Mutton Korma, Naan, Salad', notes: 'Special dinner served at 8:30 PM' }
      ];
      
      const insertMenu = db.prepare('INSERT INTO kitchen_menu (id, day_of_week, meal_type, items, notes) VALUES (?, ?, ?, ?, ?)');
      for (const day of days) {
        for (const meal of meals) {
          // Customize dinner slightly for Friday/Sunday
          let menuItems = meal.items;
          if (meal.type === 'Dinner') {
            if (day === 'Friday') {
              menuItems = 'Chicken Biryani, Raita, Kheer';
            } else if (day === 'Sunday') {
              menuItems = 'Dal Khichdi, Papad, Pickle';
            } else if (day === 'Monday' || day === 'Wednesday') {
              menuItems = 'Veg Korma, Roti, Rice';
            } else {
              menuItems = 'Egg Curry, Roti, Rice';
            }
          } else if (meal.type === 'Breakfast' && day === 'Sunday') {
            menuItems = 'Halwa Puri, Chai';
          }
          
          insertMenu.run(uuidv4(), day, meal.type, menuItems, meal.notes);
        }
      }
    }

    // Seed default kitchen stock/ration items
    const existingStock = db.prepare('SELECT COUNT(*) as count FROM kitchen_stock').get();
    if (existingStock.count === 0) {
      const defaultStock = [
        { name: 'Rice (Chawal)', quantity: 500.0, unit: 'kg', threshold: 50.0 },
        { name: 'Wheat Flour (Atta)', quantity: 450.0, unit: 'kg', threshold: 40.0 },
        { name: 'Sugar (Cheeni)', quantity: 120.0, unit: 'kg', threshold: 15.0 },
        { name: 'Cooking Oil', quantity: 90.0, unit: 'litre', threshold: 12.0 },
        { name: 'Moong Dal', quantity: 80.0, unit: 'kg', threshold: 10.0 },
        { name: 'Masoor Dal', quantity: 80.0, unit: 'kg', threshold: 10.0 },
        { name: 'Tea Leaves (Chai Patti)', quantity: 15.0, unit: 'kg', threshold: 3.0 }
      ];
      const insertStock = db.prepare('INSERT INTO kitchen_stock (id, item_name, quantity, unit, min_threshold) VALUES (?, ?, ?, ?, ?)');
      for (const item of defaultStock) {
        insertStock.run(uuidv4(), item.name, item.quantity, item.unit, item.threshold);
      }
    }

    // Seed default units
    const existingUnits = db.prepare('SELECT COUNT(*) as count FROM units').get();
    if (existingUnits.count === 0) {
      const defaultUnits = ['kg', 'litre', 'bag', 'packet', 'tin', 'pc', 'box', 'dozen', 'meter'];
      const insertUnit = db.prepare('INSERT INTO units (id, name) VALUES (?, ?)');
      for (const u of defaultUnits) {
        insertUnit.run(uuidv4(), u);
      }
    }

    // Seed default categories
    const existingCategories = db.prepare('SELECT COUNT(*) as count FROM purchase_categories').get();
    if (existingCategories.count === 0) {
      const defaultCategories = ['Ration', 'Furniture', 'Stationery', 'Electronics', 'Construction', 'Other'];
      const insertCategory = db.prepare('INSERT INTO purchase_categories (id, name) VALUES (?, ?)');
      for (const cat of defaultCategories) {
        insertCategory.run(uuidv4(), cat);
      }
    }

    // Seed Pin Codes (Sample data - can be expanded)
    const insertPinCode = db.prepare('INSERT OR IGNORE INTO pin_codes (id, pin_code, village, taluka, district, state) VALUES (?, ?, ?, ?, ?, ?)');
    const pinCodesData = [
      // Delhi
      ['pc1', '110001', 'Connaught Place', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc2', '110002', 'Darya Ganj', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc3', '110003', 'Civil Lines', 'New Delhi', 'North Delhi', 'Delhi'],
      ['pc4', '110005', 'Karol Bagh', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc5', '110006', 'Ram Nagar', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc6', '110007', 'Rajinder Nagar', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc7', '110008', 'Patel Nagar', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc8', '110009', 'Moti Nagar', 'New Delhi', 'West Delhi', 'Delhi'],
      ['pc9', '110010', 'Dhaula Kuan', 'New Delhi', 'South West Delhi', 'Delhi'],
      ['pc10', '110011', 'Paharganj', 'New Delhi', 'Central Delhi', 'Delhi'],
      ['pc11', '110015', 'Kirti Nagar', 'New Delhi', 'West Delhi', 'Delhi'],
      ['pc12', '110016', 'Lajpat Nagar', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc13', '110017', 'Nizamuddin', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc14', '110018', 'Mayur Vihar', 'New Delhi', 'East Delhi', 'Delhi'],
      ['pc15', '110019', 'Jangpura', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc16', '110020', 'Lajpat Nagar', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc17', '110021', 'Safdarjung', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc18', '110022', 'Malviya Nagar', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc19', '110023', 'Okhla', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc20', '110024', 'Saket', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc21', '110025', 'Hauz Khas', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc22', '110026', 'Mehrauli', 'New Delhi', 'South Delhi', 'Delhi'],
      ['pc23', '110027', 'Shalimar Bagh', 'New Delhi', 'North Delhi', 'Delhi'],
      ['pc24', '110028', 'Rohini', 'New Delhi', 'North West Delhi', 'Delhi'],
      ['pc25', '110029', 'Pitampura', 'New Delhi', 'North West Delhi', 'Delhi'],
      ['pc26', '110030', 'Vasant Vihar', 'New Delhi', 'South West Delhi', 'Delhi'],
      ['pc27', '110031', 'Narela', 'New Delhi', 'North Delhi', 'Delhi'],
      ['pc28', '110032', 'Dwarka', 'New Delhi', 'South West Delhi', 'Delhi'],
      ['pc29', '110033', 'Shahdara', 'New Delhi', 'East Delhi', 'Delhi'],
      ['pc30', '110034', 'Najafgarh', 'New Delhi', 'South West Delhi', 'Delhi'],
      // Uttar Pradesh
      ['pc31', '201301', 'Noida Sector 1', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc32', '201303', 'Noida Sector 15', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc33', '201304', 'Noida Sector 20', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc34', '201305', 'Noida Sector 30', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc35', '201306', 'Noida Sector 40', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc36', '201307', 'Noida Sector 50', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc37', '201308', 'Noida Sector 60', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc38', '201309', 'Noida Sector 70', 'Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc39', '201310', 'Greater Noida', 'Greater Noida', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc40', '201312', 'Greater Noida West', 'Dadri', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc41', '201313', 'Dadri', 'Dadri', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc42', '201314', 'Jewar', 'Jewar', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc43', '201315', 'Rabupura', 'Dadri', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc44', '201316', 'Dankaur', 'Dankaur', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc45', '201317', 'Bijnaur', 'Dadri', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc46', '201318', 'Chhapraula', 'Dadri', 'Gautam Buddha Nagar', 'Uttar Pradesh'],
      ['pc47', '221001', 'Varanasi Cantt', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc48', '221002', 'Godowlia', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc49', '221003', 'Lanka', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc50', '221004', 'Sigra', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc51', '221005', 'Chetganj', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc52', '221006', 'Bhelupur', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc53', '221007', 'Nadesar', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc54', '221008', 'Gopalpur', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc55', '221009', 'Sarnath', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      ['pc56', '221010', 'Rajatalab', 'Varanasi', 'Varanasi', 'Uttar Pradesh'],
      // Bihar
      ['pc57', '800001', 'Gandhi Maidan', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc58', '800002', 'Patna City', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc59', '800003', 'Kankarbagh', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc60', '800004', 'Raja Bazar', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc61', '800005', 'Danapur', 'Danapur', 'Patna', 'Bihar'],
      ['pc62', '800006', 'Kumhrar', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc63', '800007', 'Patna University', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc64', '800008', 'Digha', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc65', '800009', 'Rajendra Nagar', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc66', '800010', 'Boring Road', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc67', '800011', 'Beur', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc68', '800012', 'Phulwari', 'Phulwari', 'Patna', 'Bihar'],
      ['pc69', '800013', 'Mithapur', 'Patna Sadar', 'Patna', 'Bihar'],
      ['pc70', '800014', 'Patliputra', 'Patna Sadar', 'Patna', 'Bihar'],
      // Maharashtra
      ['pc71', '400001', 'Fort', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc72', '400002', 'Kalbadevi', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc73', '400003', 'Masjid Bunder', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc74', '400004', 'Girgaon', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc75', '400005', 'Colaba', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc76', '400006', 'Malabar Hill', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc77', '400007', 'Grant Road', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc78', '400008', 'Mumbai Central', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc79', '400009', 'Mazgaon', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc80', '400010', 'Byculla', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc81', '400011', 'Parel', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc82', '400012', 'Lalbaug', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc83', '400013', 'Delisle Road', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc84', '400014', 'Dadar', 'Mumbai', 'Mumbai', 'Maharashtra'],
      ['pc85', '400015', 'Sewri', 'Mumbai', 'Mumbai', 'Maharashtra'],
      // West Bengal
      ['pc86', '700001', 'BBD Bagh', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc87', '700002', 'Dharmatala', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc88', '700003', 'Bowbazar', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc89', '700004', 'Bara Bazar', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc90', '700005', 'Burrabazar', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc91', '700006', 'Amherst Street', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc92', '700007', 'Entally', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc93', '700008', 'Ballygunge', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc94', '700009', 'Park Street', 'Kolkata', 'Kolkata', 'West Bengal'],
      ['pc95', '700010', 'Chowringhee', 'Kolkata', 'Kolkata', 'West Bengal'],
      // Karnataka
      ['pc96', '560001', 'Bangalore GPO', 'Bangalore North', 'Bangalore Urban', 'Karnataka'],
      ['pc97', '560002', 'Bangalore City', 'Bangalore North', 'Bangalore Urban', 'Karnataka'],
      ['pc98', '560003', 'Malleshwaram', 'Bangalore North', 'Bangalore Urban', 'Karnataka'],
      ['pc99', '560004', 'Rajajinagar', 'Bangalore North', 'Bangalore Urban', 'Karnataka'],
      ['pc100', '560005', 'Seshadripuram', 'Bangalore North', 'Bangalore Urban', 'Karnataka'],
    ];
    for (const pc of pinCodesData) {
      insertPinCode.run(pc[0], pc[1], pc[2], pc[3], pc[4], pc[5]);
    }

    // Seed default staff types
    const insertStaffType = db.prepare(`
      INSERT OR IGNORE INTO staff_types (id, name, description)
      VALUES (?, ?, ?)
    `);
    const defaultTypes = [
      ['st1', 'Teacher', 'Teaches students'],
      ['st2', 'Bavarchi', 'Kitchen cook'],
      ['st3', 'Nazim-e-Matbakh', 'Kitchen supervisor'],
      ['st4', 'Accountant', 'Financial management'],
      ['st5', 'Worker', 'General worker'],
      ['st6', 'Office Staff', 'Office management'],
      ['st7', 'Other', 'Other staff types'],
    ];
    for (const st of defaultTypes) {
      insertStaffType.run(st[0], st[1], st[2]);
    }

    // Seed default qualifications
    const insertQualification = db.prepare(`
      INSERT OR IGNORE INTO qualifications (id, name, description)
      VALUES (?, ?, ?)
    `);
    const defaultQualifications = [
      ['q1', 'Matric', '10th standard'],
      ['q2', 'Intermediate', '12th standard'],
      ['q3', 'Bachelor', 'Bachelor degree'],
      ['q4', 'Master', 'Master degree'],
      ['q5', 'PhD', 'Doctorate'],
      ['q6', 'Hafiz', 'Quran Hafiz'],
      ['q7', 'Alim', 'Islamic scholar'],
      ['q8', 'Fazil', 'Advanced Islamic studies'],
      ['q9', 'Other', 'Other qualifications'],
    ];
    for (const q of defaultQualifications) {
      insertQualification.run(q[0], q[1], q[2]);
    }

    // Seed default departments
    const existingDepts = db.prepare('SELECT COUNT(*) as count FROM departments').get();
    if (existingDepts.count === 0) {
      const insertDept = db.prepare(`
        INSERT INTO departments (id, name, description, head_name)
        VALUES (?, ?, ?, ?)
      `);
      const defaultDepts = [
        ['dept1', 'Shouba-e-Hifz-o-Nazra', 'Department of Quranic Recitation & Memorization', 'Qari Abdul Rahman'],
        ['dept2', 'Shouba-e-Dars-e-Nizami', 'Department of Islamic Theology & Classical Studies', 'Maulana Mohammad Ali'],
        ['dept3', 'Shouba-e-Tajweed-o-Qiraat', 'Department of Advanced Quranic Phonetics & Intonation', 'Qari Hassan Ahmad'],
        ['dept4', 'Shouba-e-Aasriyat (Primary)', 'Department of Modern Academic Primary Education', 'Master Yusuf Khan'],
      ];
      for (const d of defaultDepts) {
        insertDept.run(d[0], d[1], d[2], d[3]);
      }
    }

    // Migration for licenses table
    try {
      db.exec("ALTER TABLE licenses ADD COLUMN custom_modules TEXT");
    } catch (_) {}

    // Migrations for fees table
    try { db.exec("ALTER TABLE fees ADD COLUMN receipt_no TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE fees ADD COLUMN remarks TEXT"); } catch (_) {}

    // Migrations for donations table
    try { db.exec("ALTER TABLE donations ADD COLUMN receipt_no TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE donations ADD COLUMN village TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE donations ADD COLUMN taluka TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE donations ADD COLUMN district TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE donations ADD COLUMN state TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE donations ADD COLUMN country TEXT DEFAULT 'India'"); } catch (_) {}
    try { db.exec("ALTER TABLE donations ADD COLUMN pin_code TEXT"); } catch (_) {}

    // Migrations for students biometrics
    try { db.exec("ALTER TABLE students ADD COLUMN face_data TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE students ADD COLUMN fingerprint_data TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE students ADD COLUMN biometric_enrolled_at TEXT"); } catch (_) {}

    // Migrations for attendance table
    try { db.exec("ALTER TABLE attendance ADD COLUMN check_in_time TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE attendance ADD COLUMN check_out_time TEXT"); } catch (_) {}
    try { db.exec("ALTER TABLE attendance ADD COLUMN verification_method TEXT DEFAULT 'Manual'"); } catch (_) {}

    // Seed default Seller Owner PIN if not exists
    const existingPin = db.prepare("SELECT value FROM settings WHERE key = 'seller_owner_pin'").get();
    if (!existingPin) {
      db.prepare("INSERT INTO settings (key, value, updated_at) VALUES ('seller_owner_pin', '78692', datetime('now'))").run();
    }

    // Seed default Trial Configuration if not exists
    const existingTrial = db.prepare("SELECT value FROM settings WHERE key = 'trial_config'").get();
    if (!existingTrial) {
      const defaultTrialConfig = JSON.stringify({
        duration_days: 14,
        is_enabled: true,
        features: [
          'students_view', 'students_admission', 'students_edit', 'students_id_card', 'students_id_card_print',
          'staff_view', 'staff_add', 'staff_attendance',
          'attendance_mark', 'attendance_bulk',
          'classes_manage',
          'fees_collect', 'fees_receipt_print',
          'exams_create', 'exams_marks_entry',
          'settings_profile', 'settings_hijri', 'settings_backup'
        ]
      });
      db.prepare("INSERT INTO settings (key, value, updated_at) VALUES ('trial_config', ?, datetime('now'))").run(defaultTrialConfig);
    }

    // Seed default Subscription Plans if empty
    const existingPlans = db.prepare("SELECT COUNT(*) as count FROM subscription_plans").get();
    if (existingPlans.count === 0) {
      const insertPlan = db.prepare(`
        INSERT INTO subscription_plans (
          id, plan_code, name, description, price, validity_days, max_devices, is_lifetime, is_active, sort_order, features_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      const basicFeatures = [
        'students_view', 'students_admission', 'students_edit', 'students_delete', 'students_gr_no_config',
        'staff_view', 'staff_add', 'staff_edit', 'staff_attendance',
        'attendance_mark', 'attendance_bulk', 'attendance_reports',
        'classes_manage',
        'settings_profile', 'settings_hijri', 'settings_backup'
      ];

      const mediumFeatures = [
        ...basicFeatures,
        'students_id_card', 'students_id_card_print', 'students_excel_export', 'students_certificate',
        'classes_promotion',
        'fees_collect', 'fees_structure', 'fees_discounts', 'fees_defaulters', 'fees_receipt_print',
        'exams_create', 'exams_marks_entry', 'exams_marksheet_print', 'exams_rankings'
      ];

      const { getAllFeatureIds } = require('./featureCatalog');
      const allFeatures = getAllFeatureIds();

      insertPlan.run('plan_basic', 'basic', 'Basic Plan', 'Essential Madarsa Administration (Talba, Asatiza, Haziri)', 6000, 365, 1, 0, 1, 1, JSON.stringify(basicFeatures));
      insertPlan.run('plan_medium', 'medium', 'Medium Plan', 'Complete Academic Package (Talba, Fees, Imtihaanat, ID Cards)', 12000, 365, 2, 0, 1, 2, JSON.stringify(mediumFeatures));
      insertPlan.run('plan_pro', 'pro', 'Pro Plan', 'Full Madarsa ERP with Kitchen, Hostel, Purchases, Accounts & Library', 20000, 365, 3, 0, 1, 3, JSON.stringify(allFeatures));
      insertPlan.run('plan_lifetime', 'lifetime', 'Lifetime License ⭐', 'One-time investment with permanent lifetime access & multi-PC support', 45000, 0, 5, 1, 1, 4, JSON.stringify(allFeatures));
    }

  });

  seedTransaction();
}

module.exports = { db, initializeDatabase };
