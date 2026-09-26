-- =====================================================================
-- Madarsa Management System - Complete Online Database Sync Schema
-- Run this in Supabase Dashboard -> SQL Editor -> New Query -> Run
-- =====================================================================

-- 1. FIX EXISTING TABLES COLUMNS
ALTER TABLE exam_schedules ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE exam_schedules ALTER COLUMN book_id DROP NOT NULL;

ALTER TABLE library_books DROP CONSTRAINT IF EXISTS library_books_accession_no_key;
ALTER TABLE library_books ALTER COLUMN accession_no DROP NOT NULL;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS language TEXT DEFAULT 'Urdu';
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS shelf_location TEXT;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS added_date TEXT;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS default_due_days INTEGER DEFAULT 14;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS lost_book_fine NUMERIC DEFAULT 500;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS lost_book_found_fine NUMERIC DEFAULT 100;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS fine_per_day NUMERIC DEFAULT 5;
ALTER TABLE library_books ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE contributors ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE hostel_rooms ADD COLUMN IF NOT EXISTS description TEXT;

-- 2. CREATE ALL REMAINING TABLES WITH FULL DATA CAPABILITY

-- Table: activity_logs
CREATE TABLE IF NOT EXISTS "activity_logs" (
    "id" TEXT PRIMARY KEY,
    "user_id" TEXT,
    "action" TEXT,
    "module" TEXT,
    "details" TEXT,
    "ip_address" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "activity_logs" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "activity_logs";
CREATE POLICY "Public Read/Write Access" ON "activity_logs" FOR ALL USING (true) WITH CHECK (true);

-- Table: admissions
CREATE TABLE IF NOT EXISTS "admissions" (
    "id" TEXT PRIMARY KEY,
    "full_name" TEXT,
    "parent_name" TEXT,
    "date_of_birth" TEXT,
    "gender" TEXT,
    "class_name" TEXT,
    "phone" TEXT,
    "address" TEXT,
    "status" TEXT DEFAULT 'Pending',
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "admissions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "admissions";
CREATE POLICY "Public Read/Write Access" ON "admissions" FOR ALL USING (true) WITH CHECK (true);

-- Table: class_book_periods
CREATE TABLE IF NOT EXISTS "class_book_periods" (
    "id" TEXT PRIMARY KEY,
    "class_id" TEXT,
    "book_id" TEXT,
    "period_number" INTEGER,
    "start_time" TEXT,
    "end_time" TEXT
);
ALTER TABLE "class_book_periods" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "class_book_periods";
CREATE POLICY "Public Read/Write Access" ON "class_book_periods" FOR ALL USING (true) WITH CHECK (true);

-- Table: class_course_books
CREATE TABLE IF NOT EXISTS "class_course_books" (
    "id" TEXT PRIMARY KEY,
    "class_course_id" TEXT,
    "book_id" TEXT,
    "is_active" INTEGER DEFAULT 1,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "class_course_books" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "class_course_books";
CREATE POLICY "Public Read/Write Access" ON "class_course_books" FOR ALL USING (true) WITH CHECK (true);

-- Table: class_periods
CREATE TABLE IF NOT EXISTS "class_periods" (
    "id" TEXT PRIMARY KEY,
    "class_id" TEXT,
    "book_id" TEXT,
    "period_number" INTEGER,
    "start_time" TEXT,
    "end_time" TEXT,
    "teacher_name" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "class_periods" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "class_periods";
CREATE POLICY "Public Read/Write Access" ON "class_periods" FOR ALL USING (true) WITH CHECK (true);

-- Table: class_progression_series
CREATE TABLE IF NOT EXISTS "class_progression_series" (
    "id" TEXT PRIMARY KEY,
    "department_name" TEXT DEFAULT '',
    "class_name" TEXT,
    "class_order" INTEGER DEFAULT 0,
    "series_order" INTEGER DEFAULT 0,
    "is_last_in_dept" INTEGER DEFAULT 0,
    "is_final_year" INTEGER DEFAULT 0,
    "next_department_name" TEXT,
    "next_class_name" TEXT,
    "remarks" TEXT,
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "class_progression_series" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "class_progression_series";
CREATE POLICY "Public Read/Write Access" ON "class_progression_series" FOR ALL USING (true) WITH CHECK (true);

-- Table: department_progression_series
CREATE TABLE IF NOT EXISTS "department_progression_series" (
    "id" TEXT PRIMARY KEY,
    "department_name" TEXT,
    "series_order" INTEGER DEFAULT 0,
    "is_final_department" INTEGER DEFAULT 0,
    "remarks" TEXT,
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "department_progression_series" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "department_progression_series";
CREATE POLICY "Public Read/Write Access" ON "department_progression_series" FOR ALL USING (true) WITH CHECK (true);

-- Table: exam_results
CREATE TABLE IF NOT EXISTS "exam_results" (
    "id" TEXT PRIMARY KEY,
    "exam_id" TEXT,
    "student_id" TEXT,
    "book_id" TEXT,
    "marks_obtained" NUMERIC DEFAULT 0,
    "max_marks" NUMERIC DEFAULT 100,
    "passing_marks" NUMERIC DEFAULT 40,
    "grade" TEXT,
    "remarks" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW(),
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "exam_results" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "exam_results";
CREATE POLICY "Public Read/Write Access" ON "exam_results" FOR ALL USING (true) WITH CHECK (true);

-- Table: gallery
CREATE TABLE IF NOT EXISTS "gallery" (
    "id" TEXT PRIMARY KEY,
    "title" TEXT,
    "image_path" TEXT,
    "category" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "gallery" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "gallery";
CREATE POLICY "Public Read/Write Access" ON "gallery" FOR ALL USING (true) WITH CHECK (true);

-- Table: general_stock
CREATE TABLE IF NOT EXISTS "general_stock" (
    "id" TEXT PRIMARY KEY,
    "item_name" TEXT,
    "quantity" NUMERIC DEFAULT 0.0,
    "unit" TEXT,
    "category" TEXT DEFAULT 'General',
    "min_threshold" NUMERIC DEFAULT 0.0,
    "created_at" TIMESTAMPTZ DEFAULT NOW(),
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "general_stock" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "general_stock";
CREATE POLICY "Public Read/Write Access" ON "general_stock" FOR ALL USING (true) WITH CHECK (true);

-- Table: general_stock_transactions
CREATE TABLE IF NOT EXISTS "general_stock_transactions" (
    "id" TEXT PRIMARY KEY,
    "stock_id" TEXT,
    "transaction_type" TEXT,
    "quantity" NUMERIC,
    "unit" TEXT,
    "remarks" TEXT,
    "transaction_date" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "general_stock_transactions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "general_stock_transactions";
CREATE POLICY "Public Read/Write Access" ON "general_stock_transactions" FOR ALL USING (true) WITH CHECK (true);

-- Table: hostel_beds
CREATE TABLE IF NOT EXISTS "hostel_beds" (
    "id" TEXT PRIMARY KEY,
    "room_id" TEXT,
    "bed_number" TEXT,
    "description" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "hostel_beds" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "hostel_beds";
CREATE POLICY "Public Read/Write Access" ON "hostel_beds" FOR ALL USING (true) WITH CHECK (true);

-- Table: kitchen_expenses
CREATE TABLE IF NOT EXISTS "kitchen_expenses" (
    "id" TEXT PRIMARY KEY,
    "item_name" TEXT,
    "amount" NUMERIC,
    "expense_date" TEXT,
    "remarks" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "kitchen_expenses" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "kitchen_expenses";
CREATE POLICY "Public Read/Write Access" ON "kitchen_expenses" FOR ALL USING (true) WITH CHECK (true);

-- Table: kitchen_meal_plans
CREATE TABLE IF NOT EXISTS "kitchen_meal_plans" (
    "id" TEXT PRIMARY KEY,
    "plan_date" TEXT,
    "meal_type" TEXT,
    "menu_items" TEXT,
    "expected_count" INTEGER DEFAULT 0,
    "status" TEXT DEFAULT 'Planned',
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "kitchen_meal_plans" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "kitchen_meal_plans";
CREATE POLICY "Public Read/Write Access" ON "kitchen_meal_plans" FOR ALL USING (true) WITH CHECK (true);

-- Table: kitchen_ration_issues
CREATE TABLE IF NOT EXISTS "kitchen_ration_issues" (
    "id" TEXT PRIMARY KEY,
    "item_id" TEXT,
    "quantity" NUMERIC,
    "issue_date" TEXT,
    "meal_type" TEXT,
    "remarks" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "kitchen_ration_issues" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "kitchen_ration_issues";
CREATE POLICY "Public Read/Write Access" ON "kitchen_ration_issues" FOR ALL USING (true) WITH CHECK (true);

-- Table: kitchen_ration_stock
CREATE TABLE IF NOT EXISTS "kitchen_ration_stock" (
    "id" TEXT PRIMARY KEY,
    "item_name" TEXT,
    "category" TEXT,
    "quantity" NUMERIC DEFAULT 0,
    "unit" TEXT DEFAULT 'Kg',
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "kitchen_ration_stock" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "kitchen_ration_stock";
CREATE POLICY "Public Read/Write Access" ON "kitchen_ration_stock" FOR ALL USING (true) WITH CHECK (true);

-- Table: library_settings
CREATE TABLE IF NOT EXISTS "library_settings" (
    "id" TEXT PRIMARY KEY DEFAULT 'default',
    "fine_per_day" NUMERIC DEFAULT 5.0,
    "max_books_per_student" INTEGER DEFAULT 3,
    "default_due_days" INTEGER DEFAULT 14,
    "lost_book_fine" NUMERIC DEFAULT 500.0,
    "updated_at" TIMESTAMPTZ DEFAULT NOW(),
    "lost_book_found_fine" NUMERIC DEFAULT 100.0
);
ALTER TABLE "library_settings" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "library_settings";
CREATE POLICY "Public Read/Write Access" ON "library_settings" FOR ALL USING (true) WITH CHECK (true);

-- Table: library_transactions
CREATE TABLE IF NOT EXISTS "library_transactions" (
    "id" TEXT PRIMARY KEY,
    "book_id" TEXT,
    "student_id" TEXT,
    "staff_id" TEXT,
    "borrower_name" TEXT,
    "hostel_name" TEXT,
    "room_number" TEXT,
    "bed_number" TEXT,
    "issue_date" TEXT,
    "due_date" TEXT,
    "return_date" TEXT,
    "status" TEXT DEFAULT 'Issued',
    "fine_amount" NUMERIC DEFAULT 0,
    "remarks" TEXT,
    "issued_by" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "library_transactions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "library_transactions";
CREATE POLICY "Public Read/Write Access" ON "library_transactions" FOR ALL USING (true) WITH CHECK (true);

-- Table: license_logs
CREATE TABLE IF NOT EXISTS "license_logs" (
    "id" TEXT PRIMARY KEY,
    "license_id" TEXT,
    "hwid" TEXT,
    "event_type" TEXT,
    "details" TEXT,
    "ip_address" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "license_logs" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "license_logs";
CREATE POLICY "Public Read/Write Access" ON "license_logs" FOR ALL USING (true) WITH CHECK (true);

-- Table: madarsa_shifts
CREATE TABLE IF NOT EXISTS "madarsa_shifts" (
    "id" TEXT PRIMARY KEY,
    "shift_name" TEXT,
    "start_time" TEXT,
    "end_time" TEXT,
    "sort_order" INTEGER DEFAULT 0,
    "is_active" INTEGER DEFAULT 1,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "madarsa_shifts" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "madarsa_shifts";
CREATE POLICY "Public Read/Write Access" ON "madarsa_shifts" FOR ALL USING (true) WITH CHECK (true);

-- Table: permissions
CREATE TABLE IF NOT EXISTS "permissions" (
    "id" TEXT PRIMARY KEY,
    "module" TEXT,
    "action" TEXT,
    "description" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "permissions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "permissions";
CREATE POLICY "Public Read/Write Access" ON "permissions" FOR ALL USING (true) WITH CHECK (true);

-- Table: pin_codes
CREATE TABLE IF NOT EXISTS "pin_codes" (
    "id" TEXT PRIMARY KEY,
    "pin_code" TEXT,
    "village" TEXT,
    "taluka" TEXT,
    "district" TEXT,
    "state" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "pin_codes" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "pin_codes";
CREATE POLICY "Public Read/Write Access" ON "pin_codes" FOR ALL USING (true) WITH CHECK (true);

-- Table: purchase_categories
CREATE TABLE IF NOT EXISTS "purchase_categories" (
    "id" TEXT PRIMARY KEY,
    "name" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "purchase_categories" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "purchase_categories";
CREATE POLICY "Public Read/Write Access" ON "purchase_categories" FOR ALL USING (true) WITH CHECK (true);

-- Table: purchase_items
CREATE TABLE IF NOT EXISTS "purchase_items" (
    "id" TEXT PRIMARY KEY,
    "purchase_id" TEXT,
    "item_name" TEXT,
    "quantity" NUMERIC,
    "unit_price" NUMERIC,
    "total_price" NUMERIC
);
ALTER TABLE "purchase_items" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "purchase_items";
CREATE POLICY "Public Read/Write Access" ON "purchase_items" FOR ALL USING (true) WITH CHECK (true);

-- Table: purchase_sell_transactions
CREATE TABLE IF NOT EXISTS "purchase_sell_transactions" (
    "id" TEXT PRIMARY KEY,
    "receipt_no" TEXT,
    "type" TEXT,
    "category" TEXT DEFAULT 'Other',
    "transaction_date" TEXT,
    "contact_person" TEXT,
    "total_price" NUMERIC,
    "remarks" TEXT,
    "items_json" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "purchase_sell_transactions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "purchase_sell_transactions";
CREATE POLICY "Public Read/Write Access" ON "purchase_sell_transactions" FOR ALL USING (true) WITH CHECK (true);

-- Table: purchases
CREATE TABLE IF NOT EXISTS "purchases" (
    "id" TEXT PRIMARY KEY,
    "receipt_no" TEXT,
    "type" TEXT,
    "category" TEXT,
    "transaction_date" TEXT,
    "contact_person" TEXT,
    "total_amount" NUMERIC DEFAULT 0,
    "remarks" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "purchases" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "purchases";
CREATE POLICY "Public Read/Write Access" ON "purchases" FOR ALL USING (true) WITH CHECK (true);

-- Table: role_permissions
CREATE TABLE IF NOT EXISTS "role_permissions" (
    "role_id" TEXT,
    "permission_id" TEXT,
    PRIMARY KEY ("role_id", "permission_id")
);
ALTER TABLE "role_permissions" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "role_permissions";
CREATE POLICY "Public Read/Write Access" ON "role_permissions" FOR ALL USING (true) WITH CHECK (true);

-- Table: seat_history
CREATE TABLE IF NOT EXISTS "seat_history" (
    "id" BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    "student_id" TEXT,
    "book_id" TEXT,
    "hall_id" INTEGER,
    "seat_row" INTEGER,
    "seat_column" INTEGER,
    "exam_id" INTEGER,
    "session_date" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "seat_history" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "seat_history";
CREATE POLICY "Public Read/Write Access" ON "seat_history" FOR ALL USING (true) WITH CHECK (true);

-- Table: staff_books
CREATE TABLE IF NOT EXISTS "staff_books" (
    "id" TEXT PRIMARY KEY,
    "staff_id" TEXT,
    "course_book_id" TEXT,
    "assigned_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "staff_books" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "staff_books";
CREATE POLICY "Public Read/Write Access" ON "staff_books" FOR ALL USING (true) WITH CHECK (true);

-- Table: staff_documents
CREATE TABLE IF NOT EXISTS "staff_documents" (
    "id" TEXT PRIMARY KEY,
    "staff_id" TEXT,
    "document_name" TEXT,
    "document_type" TEXT,
    "file_path" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "staff_documents" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "staff_documents";
CREATE POLICY "Public Read/Write Access" ON "staff_documents" FOR ALL USING (true) WITH CHECK (true);

-- Table: student_documents
CREATE TABLE IF NOT EXISTS "student_documents" (
    "id" TEXT PRIMARY KEY,
    "student_id" TEXT,
    "document_name" TEXT,
    "file_path" TEXT,
    "uploaded_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "student_documents" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "student_documents";
CREATE POLICY "Public Read/Write Access" ON "student_documents" FOR ALL USING (true) WITH CHECK (true);

-- Table: subscription_plans
CREATE TABLE IF NOT EXISTS "subscription_plans" (
    "id" TEXT PRIMARY KEY,
    "plan_code" TEXT,
    "name" TEXT,
    "description" TEXT,
    "price" NUMERIC DEFAULT 0,
    "validity_days" INTEGER DEFAULT 365,
    "max_devices" INTEGER DEFAULT 1,
    "is_lifetime" INTEGER DEFAULT 0,
    "is_active" INTEGER DEFAULT 1,
    "sort_order" INTEGER DEFAULT 0,
    "features_json" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW(),
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "subscription_plans" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "subscription_plans";
CREATE POLICY "Public Read/Write Access" ON "subscription_plans" FOR ALL USING (true) WITH CHECK (true);

-- Table: trial_devices
CREATE TABLE IF NOT EXISTS "trial_devices" (
    "hwid" TEXT PRIMARY KEY,
    "institution_name" TEXT,
    "device_name" TEXT,
    "os_info" TEXT,
    "ip_address" TEXT,
    "trial_installed_at" TIMESTAMPTZ DEFAULT NOW(),
    "last_heartbeat_at" TIMESTAMPTZ DEFAULT NOW(),
    "is_blocked" INTEGER DEFAULT 0,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "trial_devices" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "trial_devices";
CREATE POLICY "Public Read/Write Access" ON "trial_devices" FOR ALL USING (true) WITH CHECK (true);

-- Table: units
CREATE TABLE IF NOT EXISTS "units" (
    "id" TEXT PRIMARY KEY,
    "name" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "units" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "units";
CREATE POLICY "Public Read/Write Access" ON "units" FOR ALL USING (true) WITH CHECK (true);

-- Table: user_roles
CREATE TABLE IF NOT EXISTS "user_roles" (
    "user_id" TEXT,
    "role_id" TEXT,
    PRIMARY KEY ("user_id", "role_id")
);
ALTER TABLE "user_roles" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "user_roles";
CREATE POLICY "Public Read/Write Access" ON "user_roles" FOR ALL USING (true) WITH CHECK (true);

-- Table: vacations
CREATE TABLE IF NOT EXISTS "vacations" (
    "id" TEXT PRIMARY KEY,
    "academic_year_id" TEXT,
    "title" TEXT,
    "title_urdu" TEXT,
    "start_date" TEXT,
    "end_date" TEXT,
    "start_date_hijri" TEXT,
    "end_date_hijri" TEXT,
    "vacation_type" TEXT DEFAULT 'General',
    "total_days" INTEGER DEFAULT 0,
    "remarks" TEXT,
    "created_at" TIMESTAMPTZ DEFAULT NOW(),
    "updated_at" TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE "vacations" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Read/Write Access" ON "vacations";
CREATE POLICY "Public Read/Write Access" ON "vacations" FOR ALL USING (true) WITH CHECK (true);
