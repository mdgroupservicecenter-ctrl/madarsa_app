import 'designer_template_model.dart';

/// Represents a dynamic data placeholder that can be placed on a design
class DataToken {
  final String key;
  final String labelEn;
  final String labelUr;
  final String sampleValue;
  final String category;

  const DataToken({
    required this.key,
    required this.labelEn,
    required this.labelUr,
    required this.sampleValue,
    required this.category,
  });
}

/// Helper providing all available data tokens and sample data sets for document preview
class SampleDocumentData {
  /// All available tokens across all modules
  static const List<DataToken> allTokens = [
    // ── Institution Tokens ──
    DataToken(
      key: '{{madarsa.name}}',
      labelEn: 'Madarsa Name',
      labelUr: 'نام مدرسہ / ادارہ',
      sampleValue: 'جامعہ اسلامیہ دارالعلوم',
      category: 'Institution',
    ),
    DataToken(
      key: '{{madarsa.address}}',
      labelEn: 'Madarsa Address',
      labelUr: 'پتہ مدرسہ',
      sampleValue: 'قاسم العلوم روڈ، گجرات، ہند',
      category: 'Institution',
    ),
    DataToken(
      key: '{{madarsa.phone}}',
      labelEn: 'Madarsa Phone',
      labelUr: 'فون نمبر مدرسہ',
      sampleValue: '+91 98765 43210',
      category: 'Institution',
    ),
    DataToken(
      key: '{{madarsa.reg_no}}',
      labelEn: 'Registration / Trust No.',
      labelUr: 'رجسٹریشن نمبر',
      sampleValue: 'REG-GUJ-2024/786',
      category: 'Institution',
    ),

    // ── Student Tokens ──
    DataToken(
      key: '{{student.name}}',
      labelEn: 'Student Full Name',
      labelUr: 'نام طالب علم (مکمل)',
      sampleValue: 'محمد زید بن خالد انصاری',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.gr_no}}',
      labelEn: 'GR. Number',
      labelUr: 'جی آر نمبر (GR. No.)',
      sampleValue: 'GR-1045',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.roll_no}}',
      labelEn: 'Roll Number',
      labelUr: 'رول نمبر (Roll No.)',
      sampleValue: '25',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.father_name}}',
      labelEn: 'Father Name',
      labelUr: 'ولدیت (والد کا نام)',
      sampleValue: 'خالد احمد انصاری',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.class_name}}',
      labelEn: 'Class / Jamat',
      labelUr: 'جماعت / درجہ',
      sampleValue: 'درجہ رابعہ (عالمیت)',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.dob}}',
      labelEn: 'Date of Birth',
      labelUr: 'تاریخ پیدائش',
      sampleValue: '12/05/2006',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.phone}}',
      labelEn: 'Student / Guardian Phone',
      labelUr: 'موبائل نمبر',
      sampleValue: '+91 98234 56789',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.address}}',
      labelEn: 'Residential Address',
      labelUr: 'مکمل پتہ',
      sampleValue: 'محلہ مدینہ، شاہ عالم روڈ، احمد آباد',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.blood_group}}',
      labelEn: 'Blood Group',
      labelUr: 'بلڈ گروپ',
      sampleValue: 'B+',
      category: 'Student',
    ),
    DataToken(
      key: '{{student.admission_date}}',
      labelEn: 'Admission Date',
      labelUr: 'تاریخ داخلہ',
      sampleValue: '10/06/2022',
      category: 'Student',
    ),

    // ── Staff Tokens ──
    DataToken(
      key: '{{staff.name}}',
      labelEn: 'Staff Name',
      labelUr: 'نام استاد / ملازم',
      sampleValue: 'مولانا عبد الرحیم قاسمی',
      category: 'Staff',
    ),
    DataToken(
      key: '{{staff.id}}',
      labelEn: 'Staff ID / Code',
      labelUr: 'ملازم کوڈ / آئی ڈی',
      sampleValue: 'STF-042',
      category: 'Staff',
    ),
    DataToken(
      key: '{{staff.designation}}',
      labelEn: 'Designation / Post',
      labelUr: 'عہدہ / منصب',
      sampleValue: 'استاذ حدیث و فقہ',
      category: 'Staff',
    ),
    DataToken(
      key: '{{staff.department}}',
      labelEn: 'Department',
      labelUr: 'شعبہ',
      sampleValue: 'شعبہ عالیہ و تخصص',
      category: 'Staff',
    ),
    DataToken(
      key: '{{staff.joining_date}}',
      labelEn: 'Joining Date',
      labelUr: 'تاریخ شمولیت',
      sampleValue: '01/08/2018',
      category: 'Staff',
    ),
    DataToken(
      key: '{{staff.phone}}',
      labelEn: 'Staff Phone',
      labelUr: 'رابطہ نمبر',
      sampleValue: '+91 91234 56780',
      category: 'Staff',
    ),

    // ── Exam & Result Tokens ──
    DataToken(
      key: '{{exam.name}}',
      labelEn: 'Exam Name',
      labelUr: 'نام امتحان',
      sampleValue: 'سالانہ امتحان (١٤٤٦ھ - ٢٠٢٥ء)',
      category: 'Exam',
    ),
    DataToken(
      key: '{{exam.total_marks}}',
      labelEn: 'Total Marks (Max)',
      labelUr: 'کل نمبرات',
      sampleValue: '600',
      category: 'Exam',
    ),
    DataToken(
      key: '{{exam.obtained_marks}}',
      labelEn: 'Obtained Marks',
      labelUr: 'حاصل کردہ نمبرات',
      sampleValue: '542',
      category: 'Exam',
    ),
    DataToken(
      key: '{{exam.percentage}}',
      labelEn: 'Percentage (%)',
      labelUr: 'فیصد (Percentage)',
      sampleValue: '90.33%',
      category: 'Exam',
    ),
    DataToken(
      key: '{{exam.grade}}',
      labelEn: 'Overall Grade / Position',
      labelUr: 'درجہ / پوزیشن',
      sampleValue: 'ممتاز (A+ First Position)',
      category: 'Exam',
    ),
    DataToken(
      key: '{{exam.session_date}}',
      labelEn: 'Exam Session Date',
      labelUr: 'تاریخ امتحان',
      sampleValue: '25/03/2025',
      category: 'Exam',
    ),

    // ── Certificate & Sanad Tokens ──
    DataToken(
      key: '{{cert.title}}',
      labelEn: 'Certificate Title',
      labelUr: 'عنوان سند',
      sampleValue: 'سند الفراغ فی درس نظامی (عالمیت)',
      category: 'Certificate',
    ),
    DataToken(
      key: '{{cert.completion_year}}',
      labelEn: 'Year of Completion',
      labelUr: 'سال تکمیل',
      sampleValue: '١٤٤٦ھ / ٢٠٢٥ء',
      category: 'Certificate',
    ),
    DataToken(
      key: '{{cert.serial_no}}',
      labelEn: 'Certificate Serial No.',
      labelUr: 'سند نمبر / رجسٹریشن نمبر',
      sampleValue: 'SANAD-2025-089',
      category: 'Certificate',
    ),
    DataToken(
      key: '{{cert.issue_date}}',
      labelEn: 'Issue Date',
      labelUr: 'تاریخ اجراء',
      sampleValue: '15/04/2025',
      category: 'Certificate',
    ),

    // ── Fees & Receipt Tokens ──
    DataToken(
      key: '{{fee.receipt_no}}',
      labelEn: 'Receipt Number',
      labelUr: 'رسید نمبر',
      sampleValue: 'RCP-2025-0348',
      category: 'Fee',
    ),
    DataToken(
      key: '{{fee.month_year}}',
      labelEn: 'Fee Month / Period',
      labelUr: 'ماہانہ فیس کی مدت',
      sampleValue: 'مارچ ٢٠٢٥ء (شوال ١٤٤٦ھ)',
      category: 'Fee',
    ),
    DataToken(
      key: '{{fee.amount_paid}}',
      labelEn: 'Total Amount Paid (₹)',
      labelUr: 'ادا شدہ رقم',
      sampleValue: '₹ 2,500',
      category: 'Fee',
    ),
    DataToken(
      key: '{{fee.balance}}',
      labelEn: 'Remaining Balance (₹)',
      labelUr: 'بقایا رقم',
      sampleValue: '₹ 0.00',
      category: 'Fee',
    ),
    DataToken(
      key: '{{fee.payment_mode}}',
      labelEn: 'Payment Mode',
      labelUr: 'طریقہ ادائیگی',
      sampleValue: 'Cash / نقدی',
      category: 'Fee',
    ),

    // ── Sale & Purchase Bill Tokens ──
    DataToken(
      key: '{{bill.invoice_no}}',
      labelEn: 'Invoice / Bill Number',
      labelUr: 'بل / انوائس نمبر',
      sampleValue: 'INV-2025-0112',
      category: 'Billing',
    ),
    DataToken(
      key: '{{bill.party_name}}',
      labelEn: 'Customer / Vendor Name',
      labelUr: 'خریدار / دکاندار کا نام',
      sampleValue: 'مکتبہ رحمانیہ کتب خانہ',
      category: 'Billing',
    ),
    DataToken(
      key: '{{bill.grand_total}}',
      labelEn: 'Grand Total Amount (₹)',
      labelUr: 'کل رقم (Grand Total)',
      sampleValue: '₹ 14,850',
      category: 'Billing',
    ),
    DataToken(
      key: '{{bill.tax_discount}}',
      labelEn: 'Tax / Discount',
      labelUr: 'رعایت / ٹیکس',
      sampleValue: 'رعایت 5% (₹ 750)',
      category: 'Billing',
    ),

    // ── Library Tokens ──
    DataToken(
      key: '{{lib.card_no}}',
      labelEn: 'Library Card Number',
      labelUr: 'لائبریری کارڈ نمبر',
      sampleValue: 'LIB-CARD-058',
      category: 'Library',
    ),
    DataToken(
      key: '{{lib.valid_upto}}',
      labelEn: 'Valid Upto Date',
      labelUr: 'میعاد ختم ہونے کی تاریخ',
      sampleValue: '31/12/2025',
      category: 'Library',
    ),
    DataToken(
      key: '{{lib.book_limit}}',
      labelEn: 'Max Book Issue Limit',
      labelUr: 'کتاب اجراء کی حد',
      sampleValue: '2 Books (14 Days)',
      category: 'Library',
    ),
  ];

  /// Returns tokens relevant for a specific document type
  static List<DataToken> getTokensForDocumentType(DocumentType docType) {
    switch (docType) {
      case DocumentType.studentIdCard:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Student').toList();
      case DocumentType.staffIdCard:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Staff').toList();
      case DocumentType.resultCard:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Student' || t.category == 'Exam').toList();
      case DocumentType.certificate:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Student' || t.category == 'Certificate').toList();
      case DocumentType.feeReceipt:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Student' || t.category == 'Fee').toList();
      case DocumentType.purchaseBill:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Billing').toList();
      case DocumentType.libraryCard:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Student' || t.category == 'Staff' || t.category == 'Library').toList();
      case DocumentType.admitCard:
        return allTokens.where((t) => t.category == 'Institution' || t.category == 'Student' || t.category == 'Exam').toList();
      case DocumentType.custom:
        return allTokens;
    }
  }

  /// Sample realistic marks table for Marksheets
  static final List<Map<String, dynamic>> sampleSubjectsTable = [
    {'no': '1', 'book': 'صحیح البخاری', 'max': '100', 'obtained': '96', 'grade': 'ممتاز'},
    {'no': '2', 'book': 'صحیح مسلم', 'max': '100', 'obtained': '92', 'grade': 'ممتاز'},
    {'no': '3', 'book': 'سنن الترمذی', 'max': '100', 'obtained': '89', 'grade': 'جید جدا'},
    {'no': '4', 'book': 'سنن ابی داؤد', 'max': '100', 'obtained': '88', 'grade': 'جید جدا'},
    {'no': '5', 'book': 'الہدایۃ (فقہ حنفی)', 'max': '100', 'obtained': '91', 'grade': 'ممتاز'},
    {'no': '6', 'book': 'تفسیر جلالین', 'max': '100', 'obtained': '86', 'grade': 'جید جدا'},
  ];

  /// Sample fee heads breakdown table
  static final List<Map<String, dynamic>> sampleFeeBreakdownTable = [
    {'no': '1', 'head': 'ماہانہ تعلیمی فیس (Monthly Tuition)', 'amount': '₹ 1,500'},
    {'no': '2', 'head': 'دار الاقامہ و طعام (Hostel & Mess)', 'amount': '₹ 800'},
    {'no': '3', 'head': 'امتحانی فیس (Examination Fee)', 'amount': '₹ 200'},
  ];

  /// Sample invoice items table
  static final List<Map<String, dynamic>> sampleInvoiceItemsTable = [
    {'no': '1', 'item': 'کتاب صحیح البخاری (جلد 1 تا 3)', 'qty': '5', 'rate': '₹ 1,200', 'total': '₹ 6,000'},
    {'no': '2', 'item': 'مختصر القدوری (مترجم)', 'qty': '10', 'rate': '₹ 350', 'total': '₹ 3,500'},
    {'no': '3', 'item': 'مدرسہ ڈائری و رجسٹرات', 'qty': '20', 'rate': '₹ 250', 'total': '₹ 5,000'},
  ];

  /// Replaces all dynamic tokens in a given text with their sample values
  static String resolveTokens(String rawText) {
    String resolved = rawText;
    for (final t in allTokens) {
      resolved = resolved.replaceAll(t.key, t.sampleValue);
    }
    return resolved;
  }

  /// Map of all token keys to sample values
  static Map<String, String> get sampleTokensMap {
    final map = <String, String>{};
    for (final t in allTokens) {
      map[t.key] = t.sampleValue;
    }
    return map;
  }
}
