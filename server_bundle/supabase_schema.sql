-- =====================================================================
-- Madarsa Management System - Complete PostgreSQL Schema for Supabase
-- Run this script in your Supabase Project -> SQL Editor -> New Query -> Run
-- =====================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Users Table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    full_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    avatar TEXT,
    role_id TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ
);

-- 2. Roles Table
CREATE TABLE IF NOT EXISTS roles (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    permissions TEXT,
    is_system INTEGER DEFAULT 0,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Departments
CREATE TABLE IF NOT EXISTS departments (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    head_name TEXT,
    parent_id TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Classes
CREATE TABLE IF NOT EXISTS classes (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    duration TEXT,
    department_id TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Courses & Books
CREATE TABLE IF NOT EXISTS courses (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT NOT NULL,
    code TEXT UNIQUE,
    department_id TEXT,
    description TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS books (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    title TEXT,
    name TEXT,
    course_id TEXT,
    author TEXT,
    description TEXT,
    category TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS class_courses (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    class_id TEXT NOT NULL,
    course_id TEXT NOT NULL,
    academic_year TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS course_books (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    class_course_id TEXT,
    book_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Students Table
CREATE TABLE IF NOT EXISTS students (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
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
    admission_date TEXT,
    admission_date_h TEXT,
    admission_time_age TEXT,
    now_age TEXT,
    condition_type TEXT DEFAULT 'Regular',
    monthly_fees NUMERIC DEFAULT 0,
    admission_fee NUMERIC DEFAULT 0,
    book_fee NUMERIC DEFAULT 0,
    fee_structure TEXT,
    gender TEXT,
    enrollment_date TEXT,
    is_active INTEGER DEFAULT 1,
    category TEXT,
    division TEXT,
    contributor_id TEXT,
    contributor_name TEXT,
    contributor_amount NUMERIC DEFAULT 0,
    staff_id TEXT,
    staff_name TEXT,
    face_data TEXT,
    fingerprint_data TEXT,
    biometric_enrolled_at TEXT,
    photo_path TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pg_students_active ON students(is_active);
CREATE INDEX IF NOT EXISTS idx_pg_students_class ON students(class_name);
CREATE INDEX IF NOT EXISTS idx_pg_students_gr ON students(gr_no);

-- 7. Staff & Teachers
CREATE TABLE IF NOT EXISTS staff (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
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
    salary NUMERIC DEFAULT 0,
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
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS staff_types (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS qualifications (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Attendance (Students & Staff)
CREATE TABLE IF NOT EXISTS attendance (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    student_id TEXT NOT NULL,
    date TEXT NOT NULL,
    status TEXT NOT NULL,
    remarks TEXT,
    check_in_time TEXT,
    check_out_time TEXT,
    verification_method TEXT DEFAULT 'Manual',
    shift_id TEXT DEFAULT '',
    shift_name TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pg_attendance_student_date ON attendance(student_id, date);

CREATE TABLE IF NOT EXISTS period_attendance (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    student_id TEXT NOT NULL,
    class_id TEXT NOT NULL,
    period_id TEXT,
    period_number INTEGER NOT NULL,
    date TEXT NOT NULL,
    status TEXT NOT NULL,
    time TEXT,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(student_id, date, period_number)
);

CREATE TABLE IF NOT EXISTS staff_attendance (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    staff_id TEXT NOT NULL,
    date TEXT NOT NULL,
    status TEXT NOT NULL,
    check_in_time TEXT,
    check_out_time TEXT,
    remarks TEXT,
    verification_method TEXT DEFAULT 'Manual',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Fees & Contributions
CREATE TABLE IF NOT EXISTS fee_types (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    billing_type TEXT DEFAULT 'monthly',
    default_months INTEGER DEFAULT 12,
    default_amount NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fees (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    student_id TEXT NOT NULL,
    amount NUMERIC NOT NULL,
    payment_date TEXT,
    fee_type TEXT NOT NULL,
    status TEXT NOT NULL,
    receipt_no TEXT,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pg_fees_student ON fees(student_id, status);

CREATE TABLE IF NOT EXISTS contributors (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    address TEXT,
    pan_no TEXT,
    aadhaar_no TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS donation_types (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS donations (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    receipt_no TEXT,
    donor_name TEXT,
    donor_phone TEXT,
    village TEXT,
    taluka TEXT,
    district TEXT,
    state TEXT,
    country TEXT DEFAULT 'India',
    pin_code TEXT,
    amount NUMERIC NOT NULL,
    donation_type TEXT NOT NULL,
    payment_method TEXT DEFAULT 'Cash',
    payment_date TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Hostel (Dar-ul-Iqama)
CREATE TABLE IF NOT EXISTS hostels (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT NOT NULL,
    description TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hostel_rooms (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    hostel_id TEXT NOT NULL,
    room_number TEXT NOT NULL,
    capacity INTEGER DEFAULT 4,
    floor TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS hostel_allocations (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    hostel_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    student_id TEXT NOT NULL,
    allocated_at TIMESTAMPTZ DEFAULT NOW(),
    vacated_at TIMESTAMPTZ,
    status TEXT DEFAULT 'Active'
);

-- 11. Kitchen (Matbakh)
CREATE TABLE IF NOT EXISTS kitchen_menu (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    day_of_week TEXT NOT NULL,
    meal_type TEXT NOT NULL,
    items TEXT NOT NULL,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS kitchen_stock (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    item_name TEXT UNIQUE NOT NULL,
    quantity NUMERIC DEFAULT 0,
    unit TEXT NOT NULL DEFAULT 'Kg',
    min_threshold NUMERIC DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS kitchen_stock_transactions (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    stock_id TEXT NOT NULL,
    transaction_type TEXT NOT NULL,
    quantity NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    remarks TEXT,
    transaction_date TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. Library (Kutub Khana)
CREATE TABLE IF NOT EXISTS library_categories (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT NOT NULL,
    description TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS library_books (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    accession_no TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    author TEXT,
    category_id TEXT,
    publisher TEXT,
    isbn TEXT,
    total_copies INTEGER DEFAULT 1,
    available_copies INTEGER DEFAULT 1,
    is_active INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS library_issues (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    book_id TEXT NOT NULL,
    user_type TEXT NOT NULL,
    user_id TEXT NOT NULL,
    issue_date TEXT NOT NULL,
    due_date TEXT NOT NULL,
    return_date TEXT,
    status TEXT DEFAULT 'Issued',
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. Exams & Anti-Cheating Seating
CREATE TABLE IF NOT EXISTS exams (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT NOT NULL,
    start_date TEXT,
    end_date TEXT,
    status TEXT DEFAULT 'DRAFT',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS exam_schedules (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    exam_id TEXT NOT NULL,
    class_id TEXT NOT NULL,
    class_name TEXT,
    book_id TEXT NOT NULL,
    book_name TEXT,
    exam_date TEXT,
    start_time TEXT,
    end_time TEXT,
    max_marks INTEGER DEFAULT 100,
    passing_marks INTEGER,
    department_id TEXT,
    department_name TEXT,
    parent_department_name TEXT
);

CREATE TABLE IF NOT EXISTS exam_halls (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    name TEXT NOT NULL,
    total_rows INTEGER NOT NULL,
    total_columns INTEGER NOT NULL,
    is_active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS seating_arrangements (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    exam_id TEXT NOT NULL,
    schedule_id TEXT,
    hall_id TEXT NOT NULL,
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
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS exam_marks (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    exam_id TEXT NOT NULL,
    schedule_id TEXT,
    student_id TEXT NOT NULL,
    student_name TEXT,
    registration_number TEXT,
    roll_number TEXT,
    division TEXT,
    book_id TEXT NOT NULL,
    book_name TEXT,
    class_id TEXT NOT NULL,
    class_name TEXT,
    max_marks NUMERIC DEFAULT 100,
    marks_obtained NUMERIC,
    is_absent INTEGER DEFAULT 0,
    remarks TEXT,
    entered_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. Academic Years & Promotion History
CREATE TABLE IF NOT EXISTS academic_years (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    year_name TEXT UNIQUE NOT NULL,
    year_name_hijri TEXT,
    start_date TEXT,
    end_date TEXT,
    is_current INTEGER DEFAULT 0,
    auto_promote_enabled INTEGER DEFAULT 1,
    passing_percentage NUMERIC DEFAULT 40.0,
    annual_student_expense NUMERIC DEFAULT 15000.0,
    auto_promoted_at TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS student_academic_history (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
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
    attendance_percentage NUMERIC DEFAULT 0,
    total_marks NUMERIC DEFAULT 0,
    obtained_marks NUMERIC DEFAULT 0,
    exam_percentage NUMERIC DEFAULT 0,
    result_grade TEXT,
    status TEXT NOT NULL DEFAULT 'Promoted',
    remarks TEXT,
    books_marks_json TEXT,
    fee_total NUMERIC DEFAULT 0,
    fee_paid NUMERIC DEFAULT 0,
    fee_pending NUMERIC DEFAULT 0,
    per_student_expense NUMERIC DEFAULT 0,
    metadata_json TEXT,
    promoted_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. Licenses & Devices (SaaS System)
CREATE TABLE IF NOT EXISTS licenses (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    license_key TEXT UNIQUE NOT NULL,
    customer_name TEXT NOT NULL,
    institution_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    tier TEXT NOT NULL DEFAULT 'pro',
    custom_modules TEXT,
    max_devices INTEGER DEFAULT 1,
    max_students INTEGER DEFAULT 0,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    price NUMERIC DEFAULT 0,
    status TEXT DEFAULT 'active',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS license_devices (
    id TEXT PRIMARY KEY DEFAULT uuid_generate_v4()::TEXT,
    license_id TEXT REFERENCES licenses(id) ON DELETE CASCADE,
    hwid TEXT NOT NULL,
    device_name TEXT,
    os_info TEXT,
    ip_address TEXT,
    first_activated_at TIMESTAMPTZ DEFAULT NOW(),
    last_heartbeat_at TIMESTAMPTZ DEFAULT NOW(),
    is_blocked INTEGER DEFAULT 0,
    UNIQUE(license_id, hwid)
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security (RLS) policies or leave open for anon/service_role
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;

-- Allow authenticated and service_role full access
DROP POLICY IF EXISTS "Public Read/Write Access" ON students;
CREATE POLICY "Public Read/Write Access" ON students FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public Read/Write Access" ON staff;
CREATE POLICY "Public Read/Write Access" ON staff FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public Read/Write Access" ON attendance;
CREATE POLICY "Public Read/Write Access" ON attendance FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public Read/Write Access" ON fees;
CREATE POLICY "Public Read/Write Access" ON fees FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public Read/Write Access" ON classes;
CREATE POLICY "Public Read/Write Access" ON classes FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public Read/Write Access" ON users;
CREATE POLICY "Public Read/Write Access" ON users FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public Read/Write Access" ON licenses;
CREATE POLICY "Public Read/Write Access" ON licenses FOR ALL USING (true) WITH CHECK (true);
