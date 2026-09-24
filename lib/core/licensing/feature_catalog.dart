class FeatureCatalog {
  static const List<Map<String, dynamic>> defaultCatalog = [
    {
      'module_id': 'students',
      'module_name': '🎓 Students Management (Talba)',
      'features': [
        {'id': 'students_view', 'name': 'Student Directory & Profiles', 'desc': 'Talba ki list aur details dekhna'},
        {'id': 'students_admission', 'name': 'New Admission Form', 'desc': 'Naye talba ka dakhila form'},
        {'id': 'students_edit', 'name': 'Edit Student Information', 'desc': 'Talba ke records me tarmeem karna'},
        {'id': 'students_delete', 'name': 'Delete / Archive Student', 'desc': 'Talba record delete ya kharij karna'},
        {'id': 'students_id_card', 'name': 'ID Card Builder & Designer', 'desc': 'ID Card ka design, colors, font set karna'},
        {'id': 'students_id_card_print', 'name': 'ID Card Printing (Single/Bulk)', 'desc': 'ID Card print karna (A4/Single)'},
        {'id': 'students_excel_export', 'name': 'Export to Excel', 'desc': 'Talba list ko Excel me export karna'},
        {'id': 'students_excel_import', 'name': 'Import from Excel', 'desc': 'Excel file se talba direct import karna'},
        {'id': 'students_gr_no_config', 'name': 'GR Number Auto Config', 'desc': 'GR Number ka format aur prefix set karna'},
        {'id': 'students_certificate', 'name': 'Bonafide / Leaving Certificate', 'desc': 'Dakhila aur Faraghat certificate print'},
      ],
    },
    {
      'module_id': 'staff',
      'module_name': '👨‍🏫 Staff & Teachers (Asatiza)',
      'features': [
        {'id': 'staff_view', 'name': 'Staff Directory & Profiles', 'desc': 'Asatiza aur staff ki list dekhna'},
        {'id': 'staff_add', 'name': 'Add New Teacher / Staff', 'desc': 'Naye ustaad ya staff ko add karna'},
        {'id': 'staff_edit', 'name': 'Edit Staff Details', 'desc': 'Staff ki maloomat edit karna'},
        {'id': 'staff_salary', 'name': 'Salary & Payslip Generation', 'desc': 'Mahana tankhwah aur slip banana'},
        {'id': 'staff_attendance', 'name': 'Staff Attendance', 'desc': 'Asatiza ki daily haziri lagana'},
      ],
    },
    {
      'module_id': 'attendance',
      'module_name': '📅 Attendance (Haziri)',
      'features': [
        {'id': 'attendance_mark', 'name': 'Daily Attendance Marking', 'desc': 'Rozana ki haziri lagana'},
        {'id': 'attendance_bulk', 'name': 'Class-wise Bulk Attendance', 'desc': 'Puri class ki ek sath haziri'},
        {'id': 'attendance_reports', 'name': 'Monthly Attendance Register', 'desc': 'Mahana haziri register aur percentage'},
      ],
    },
    {
      'module_id': 'classes',
      'module_name': '🏫 Classes & Sections (Darjaat)',
      'features': [
        {'id': 'classes_manage', 'name': 'Create & Manage Classes', 'desc': 'Darjaat aur sections banana'},
        {'id': 'classes_promotion', 'name': 'Annual Student Promotion', 'desc': 'Saalana agle darje me taraqqi dena'},
        {'id': 'classes_timetable', 'name': 'Class Timetable Setup', 'desc': 'Ghanta-war sabaq timetable'},
      ],
    },
    {
      'module_id': 'fees',
      'module_name': '💰 Fees & Receipts (Mahana Fees)',
      'features': [
        {'id': 'fees_collect', 'name': 'Fee Collection & Receipt', 'desc': 'Fees wasool karna aur raseed katna'},
        {'id': 'fees_structure', 'name': 'Custom Fee Heads & Structures', 'desc': 'Mukhtalif fees categories tay karna'},
        {'id': 'fees_discounts', 'name': 'Fee Concessions & Riayat', 'desc': 'Mustahiq talba ko riayat dena'},
        {'id': 'fees_defaulters', 'name': 'Unpaid / Defaulters List', 'desc': 'Baqaya fees walo ki fehrist'},
        {'id': 'fees_receipt_print', 'name': 'Thermal & A4 Receipt Print', 'desc': 'Thermal aur A4 raseed print karna'},
      ],
    },
    {
      'module_id': 'exams',
      'module_name': '📝 Examinations (Imtihaanat)',
      'features': [
        {'id': 'exams_create', 'name': 'Exam Creation & Schedule', 'desc': 'Imtihaan tay karna aur schedule banana'},
        {'id': 'exams_marks_entry', 'name': 'Subject-wise Marks Entry', 'desc': 'Mazameen ke number daalna'},
        {'id': 'exams_marksheet_print', 'name': 'Marksheet & Result Card Print', 'desc': 'Kashf-ud-Darjaat (Marksheet) print'},
        {'id': 'exams_rankings', 'name': 'Position & Merit Rankings', 'desc': 'Darja-war avwal, doyum, soyum nikalna'},
      ],
    },
    {
      'module_id': 'card_designer',
      'module_name': '🎨 Universal Card & Document Studio',
      'features': [
        {'id': 'card_designer', 'name': 'Universal Card & Document Studio', 'desc': 'ID cards, result cards, sanad, receipts design karna'},
        {'id': 'card_designer_export', 'name': 'Vector PDF Export & Direct Print', 'desc': 'Designs ko High-res PDF export aur direct print karna'},
      ],
    },
    {
      'module_id': 'kitchen',
      'module_name': '🍲 Expenses / Kitchen',
      'features': [
        {'id': 'kitchen_meal_plans', 'name': 'Weekly Meal Menu Planning', 'desc': 'Hafta-war khane ka menu tay karna'},
        {'id': 'kitchen_daily_issue', 'name': 'Daily Ration Issue', 'desc': 'Rozana rashan jaari karna'},
        {'id': 'kitchen_stock', 'name': 'Kitchen Stock Inventory', 'desc': 'Matbakh ka rashan balance dekhna'},
        {'id': 'kitchen_expenses', 'name': 'Kitchen Expense Reports', 'desc': 'Khorak ke kharch ka hisaab'},
      ],
    },
    {
      'module_id': 'purchases',
      'module_name': '🛒 Purchases & Accounts (Khareedari)',
      'features': [
        {'id': 'purchases_vouchers', 'name': 'Purchase Vouchers Entry', 'desc': 'Khareedari ke bil aur kharch daalna'},
        {'id': 'purchases_suppliers', 'name': 'Vendor & Supplier Ledger', 'desc': 'Dukandaro ka khata sambhalna'},
        {'id': 'purchases_inventory', 'name': 'General Stock Register', 'desc': 'Madarse ke aam saman ka register'},
        {'id': 'purchases_cashbook', 'name': 'Daily Cash Book', 'desc': 'Roznamcha aamad-o-kharch'},
      ],
    },
    {
      'module_id': 'hostel',
      'module_name': '🛏️ Hostel (Dar-ul-Iqama)',
      'features': [
        {'id': 'hostel_rooms', 'name': 'Room & Hall Management', 'desc': 'Kamro aur halls ka intezam'},
        {'id': 'hostel_bed_allotment', 'name': 'Student Bed Allotment', 'desc': 'Talba ko charpai/kamra allot karna'},
        {'id': 'hostel_gate_pass', 'name': 'Gate Pass & Outing Logs', 'desc': 'Rukhsat aur chhutti gate pass'},
      ],
    },
    {
      'module_id': 'library',
      'module_name': '📚 Library (Kutub Khana)',
      'features': [
        {'id': 'library_catalog', 'name': 'Book Catalog & Search', 'desc': 'Kitabo ka indiraaj aur talash'},
        {'id': 'library_issue_return', 'name': 'Book Issue & Return', 'desc': 'Kitabein jari karna aur wapsi'},
      ],
    },
    {
      'module_id': 'donors',
      'module_name': '🤝 Donors & Contributors (Muavineen)',
      'features': [
        {'id': 'donors_records', 'name': 'Donor Database', 'desc': 'Muavineen aur azeezan ka data'},
        {'id': 'donors_receipts', 'name': 'Donation Receipts Print', 'desc': 'Atiyyaat ki raseed banana'},
        {'id': 'donors_whatsapp', 'name': 'WhatsApp Receipt Share', 'desc': 'WhatsApp par raseed bhejna'},
      ],
    },
    {
      'module_id': 'reports',
      'module_name': '📑 Audit & Financial Reports',
      'features': [
        {'id': 'reports_financial', 'name': 'Annual Financial Audit Report', 'desc': 'Saalana aamad-o-kharch report'},
        {'id': 'reports_academic', 'name': 'Academic Performance Summary', 'desc': 'Talba ki taleemi karguzari report'},
        {'id': 'reports_export', 'name': 'Export to PDF & Excel', 'desc': 'Reports ko PDF aur Excel me lena'},
      ],
    },
    {
      'module_id': 'users',
      'module_name': '👥 Users & Roles (Sarfeen)',
      'features': [
        {'id': 'users_roles', 'name': 'Manage Roles & User Accounts', 'desc': 'Naye users aur uhday banana'},
        {'id': 'users_permissions', 'name': 'Custom Access Permissions', 'desc': 'Har user ki alag alag ijazat tay karna'},
      ],
    },
    {
      'module_id': 'settings',
      'module_name': '⚙️ System & Settings (Tanzeemaat)',
      'features': [
        {'id': 'settings_profile', 'name': 'Madarsa Profile & Logo Setup', 'desc': 'Madarse ka naam, pata aur logo lagana'},
        {'id': 'settings_hijri', 'name': 'Hijri & Islamic Calendar Setup', 'desc': 'Islami tareekh aur calendar setting'},
        {'id': 'settings_backup', 'name': 'Database Backup & Restore', 'desc': 'Data ka mehfooz backup lena aur restore karna'},
      ],
    },
  ];

  static bool isModuleId(String id) {
    return defaultCatalog.any((m) => m['module_id'] == id);
  }

  static String getFeatureName(String id) {
    for (final mod in defaultCatalog) {
      if (mod['module_id'] == id) {
        return mod['module_name'] as String;
      }
      final feats = mod['features'] as List<Map<String, dynamic>>? ?? [];
      for (final f in feats) {
        if (f['id'] == id) {
          return f['name'] as String;
        }
      }
    }
    // Fallback: title case
    final parts = id.replaceAll('_', ' ').split(' ');
    return parts.map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  static String? getFeatureDesc(String id) {
    for (final mod in defaultCatalog) {
      if (mod['module_id'] == id) return null;
      final feats = mod['features'] as List<Map<String, dynamic>>? ?? [];
      for (final f in feats) {
        if (f['id'] == id) {
          return f['desc'] as String?;
        }
      }
    }
    return null;
  }
}
