import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/services/gr_no_settings.dart';
import '../models/student_model.dart';
import '../repositories/student_repository.dart';

class ImportResult {
  final int totalRows;
  final int importedCount;
  final int skippedCount;
  final List<String> errors;

  ImportResult({
    required this.totalRows,
    required this.importedCount,
    required this.skippedCount,
    required this.errors,
  });
}

class StudentExcelService {
  static const List<String> headers = [
    'GR No',
    'Roll Number',
    'Full Name',
    'Father Name',
    'Surname',
    'Grandfather Name',
    'Gender',
    'Date of Birth',
    'Age at Admission',
    'Current Age',
    'Department',
    'Class Name',
    'Division',
    'Sub Departments',
    'Category',
    'Status',
    'Admission Type',
    'Admission Date (AD)',
    'Admission Date (Hijri)',
    'Enrollment Date',
    'Condition Type',
    'Standard / Full Fees (₹)',
    'Staff / Contributor Name',
    'Concession / Discount Amount (₹)',
    'Net Calculated Monthly Fees (₹)',
    'Total Attendance (Days)',
    'Pending Fees (₹)',
    'Mobile No',
    'Aadhaar No',
    'Village',
    'Taluka',
    'District',
    'State',
    'Pin Code',
    'Address',
    'Photo Path',
  ];

  /// Escapes field string for CSV formatting
  static String _escapeCsv(String? val) {
    if (val == null) return '""';
    String clean = val.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    if (clean.contains(',') || clean.contains('"') || clean.contains(';')) {
      clean = clean.replaceAll('"', '""');
      return '"$clean"';
    }
    return '"$clean"';
  }

  /// Parses entire CSV content into rows and columns, respecting multiline quoted strings and escaped quotes
  static List<List<String>> _parseCsv(String content) {
    final List<List<String>> rows = [];
    final StringBuffer currentField = StringBuffer();
    final List<String> currentRow = [];
    bool inQuotes = false;

    final cleanContent = content.replaceFirst('\uFEFF', '');

    for (int i = 0; i < cleanContent.length; i++) {
      final char = cleanContent[i];

      if (char == '"') {
        if (inQuotes && i + 1 < cleanContent.length && cleanContent[i + 1] == '"') {
          currentField.write('"');
          i++; // Skip escaped quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if ((char == ',' || char == '\t' || char == ';') && !inQuotes) {
        currentRow.add(currentField.toString().trim());
        currentField.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < cleanContent.length && cleanContent[i + 1] == '\n') {
          i++; // Skip \r\n
        }
        currentRow.add(currentField.toString().trim());
        currentField.clear();

        if (currentRow.any((c) => c.isNotEmpty)) {
          rows.add(List.from(currentRow));
        }
        currentRow.clear();
      } else {
        currentField.write(char);
      }
    }

    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString().trim());
      if (currentRow.any((c) => c.isNotEmpty)) {
        rows.add(List.from(currentRow));
      }
    }

    return rows;
  }

  /// Exports student list to CSV / Excel compatible file with ALL profile columns & complete fee breakdown
  static Future<String?> exportStudentsToCsv(List<Student> students) async {
    final StringBuffer buffer = StringBuffer();
    
    // Add UTF-8 BOM for Microsoft Excel auto-detecting Unicode
    buffer.write('\uFEFF');

    // Header line
    buffer.writeln(headers.map(_escapeCsv).join(','));

    // Data lines
    for (final s in students) {
      final double baseFee = (s.monthlyFees ?? 0.0) + (s.contributorAmount ?? 0.0);
      final double discountAmt = s.contributorAmount ?? 0.0;
      final double netMonthlyFee = s.monthlyFees ?? 0.0;
      final String staffOrContribName = s.contributorName ?? s.contributorId ?? '';

      String formattedSubDepts = '';
      if (s.subDepartments != null && s.subDepartments!.isNotEmpty) {
        formattedSubDepts = s.subDepartments!.map((sub) {
          final parts = <String>[];
          if (sub.className != null && sub.className!.isNotEmpty) {
            parts.add('Class: ${sub.className}');
          }
          if (sub.division != null && sub.division!.isNotEmpty) {
            parts.add('Div: ${sub.division}');
          }
          final details = parts.isNotEmpty ? ' (${parts.join(', ')})' : '';
          return '${sub.subDepartmentName ?? ''}$details';
        }).join('; ');
      }

      final row = [
        s.grNo ?? s.registrationNumber,
        s.rollNumber ?? '',
        s.fullName,
        s.fatherName ?? '',
        s.surname ?? '',
        s.grandFatherName ?? '',
        s.gender ?? '',
        s.dateOfBirth ?? '',
        s.admissionTimeAge ?? '',
        s.nowAge ?? '',
        s.departmentName ?? '',
        s.className ?? '',
        s.division ?? '',
        formattedSubDepts,
        s.category ?? '',
        s.studentStatus ?? (s.isActive ? 'Active' : 'Inactive'),
        s.admissionType ?? 'New',
        s.admissionDate ?? '',
        s.admissionDateH ?? '',
        s.enrollmentDate ?? '',
        s.conditionType ?? 'Regular',
        baseFee > 0 ? baseFee.toStringAsFixed(2) : (s.monthlyFees?.toStringAsFixed(2) ?? '0.00'),
        staffOrContribName,
        discountAmt > 0 ? discountAmt.toStringAsFixed(2) : '0.00',
        netMonthlyFee.toStringAsFixed(2),
        s.totalAttendance.toString(),
        s.pendingFees.toString(),
        s.mobileNo ?? '',
        s.aadhaarNo ?? '',
        s.village ?? '',
        s.taluka ?? '',
        s.district ?? '',
        s.state ?? '',
        s.pinCode ?? '',
        s.address ?? '',
        s.photoPath ?? '',
      ];
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final defaultFileName = 'Students_Profile_Export_$nowStr.csv';

    String? savePath;
    if (kIsWeb) {
      return null;
    } else {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Students Export File',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (savePath == null) {
        // Fallback: save to Downloads / Documents folder
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        savePath = '${dir.path}${Platform.pathSeparator}$defaultFileName';
      }
    }

    final file = File(savePath);
    await file.writeAsString(buffer.toString(), encoding: utf8);
    return savePath;
  }

  /// Downloads / Saves Sample Excel CSV Template
  static Future<String?> saveSampleTemplate() async {
    final StringBuffer buffer = StringBuffer();
    buffer.write('\uFEFF');
    buffer.writeln(headers.map(_escapeCsv).join(','));

    // Sample Row 1
    final sample1 = [
      'A26-0001',
      '101',
      'Mohammad Ali',
      'Ibrahim',
      'Khan',
      'Ahmed',
      'Male',
      '2012-05-15',
      '10 Y 2 M',
      '14 Y 3 M',
      'Primary Education',
      'Class 1',
      'A',
      'Hifz (Class: Hifz-1, Div: A); Tajweed (Class: Tajweed-1, Div: B)',
      'General',
      'Active',
      'New',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      '1447-08-15',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'Regular',
      '500.00',
      '',
      '0.00',
      '500.00',
      '180',
      '0',
      '9876543210',
      '123456789012',
      'Palanpur',
      'Palanpur',
      'Banaskantha',
      'Gujarat',
      '385001',
      'Main Road, Palanpur',
      '',
    ];

    // Sample Row 2 (Staff Child or Partial)
    final sample2 = [
      'A26-0002',
      '102',
      'Fatima Bibi',
      'Rashid',
      'Shaikh',
      'Usman',
      'Female',
      '2013-08-20',
      '9 Y 5 M',
      '13 Y 0 M',
      'Higher Education',
      'Class 1',
      'B',
      'Qirat (Class: Qirat-1, Div: A)',
      'General',
      'Active',
      'New',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      '1447-08-15',
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'Staff Child',
      '500.00',
      'Maulana Rashid',
      '200.00',
      '300.00',
      '175',
      '0',
      '9876543211',
      '123456789013',
      'Deesa',
      'Deesa',
      'Banaskantha',
      'Gujarat',
      '385535',
      'Station Road, Deesa',
      '',
    ];

    buffer.writeln(sample1.map(_escapeCsv).join(','));
    buffer.writeln(sample2.map(_escapeCsv).join(','));

    String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Sample Student Import Template',
      fileName: 'Sample_Student_Import_Template.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (savePath == null) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      savePath = '${dir.path}${Platform.pathSeparator}Sample_Student_Import_Template.csv';
    }

    final file = File(savePath);
    await file.writeAsString(buffer.toString(), encoding: utf8);
    return savePath;
  }

  /// Helper to normalize any date format (DD-MM-YYYY, DD/MM/YYYY, YYYY-MM-DD) to YYYY-MM-DD
  static String _normalizeDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final str = raw.trim();
    
    // DD-MM-YYYY or DD/MM/YYYY
    final dmyMatch = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(str);
    if (dmyMatch != null) {
      final d = dmyMatch.group(1)!.padLeft(2, '0');
      final m = dmyMatch.group(2)!.padLeft(2, '0');
      final y = dmyMatch.group(3)!;
      return '$y-$m-$d';
    }

    // YYYY-MM-DD or YYYY/MM/DD
    final ymdMatch = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(str);
    if (ymdMatch != null) {
      final y = ymdMatch.group(1)!;
      final m = ymdMatch.group(2)!.padLeft(2, '0');
      final d = ymdMatch.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }

    return str;
  }

  /// Helper to compute age from normalized birth date and target date
  static String _computeAge(String dobStr, [String? targetDateStr]) {
    try {
      final normDob = _normalizeDate(dobStr);
      if (normDob.isEmpty) return '';
      final birth = DateTime.parse(normDob);

      DateTime target;
      if (targetDateStr != null && targetDateStr.isNotEmpty) {
        final normTarget = _normalizeDate(targetDateStr);
        target = DateTime.tryParse(normTarget) ?? DateTime.now();
      } else {
        target = DateTime.now();
      }

      int years = target.year - birth.year;
      int months = target.month - birth.month;
      int days = target.day - birth.day;

      if (days < 0) {
        months--;
        final prevMonth = DateTime(target.year, target.month, 0);
        days += prevMonth.day;
      }
      if (months < 0) {
        years--;
        months += 12;
      }

      String res = '';
      if (days > 0) res += '${days}Days ';
      if (months > 0) res += '${months}Months ';
      if (years > 0) res += '${years}Years';

      return res.trim().isEmpty ? '0Days' : res.trim();
    } catch (e) {
      return '';
    }
  }

  /// Helper to clean scientific exponential notation (e.g. 4.94097E+11), floating decimals, and non-digits
  static String _cleanAadhaar(String raw) {
    if (raw.isEmpty) return '';
    String s = raw.trim();
    if (s.toLowerCase().contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) {
        s = d.toStringAsFixed(0);
      }
    }
    if (s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    final digitsOnly = s.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 12) {
      return '${digitsOnly.substring(0, 4)} ${digitsOnly.substring(4, 8)} ${digitsOnly.substring(8)}';
    }
    return digitsOnly.isNotEmpty ? digitsOnly : s;
  }

  static String _cleanMobile(String raw) {
    if (raw.isEmpty) return '';
    String s = raw.trim();
    if (s.toLowerCase().contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) {
        s = d.toStringAsFixed(0);
      }
    }
    if (s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    final digitsOnly = s.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10) {
      return '+91 ${digitsOnly.substring(0, 3)} ${digitsOnly.substring(3, 6)} ${digitsOnly.substring(6)}';
    } else if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
      final d10 = digitsOnly.substring(2);
      return '+91 ${d10.substring(0, 3)} ${d10.substring(3, 6)} ${d10.substring(6)}';
    }
    return s;
  }

  static String _cleanPincode(String raw) {
    if (raw.isEmpty) return '';
    String s = raw.trim();
    if (s.toLowerCase().contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) {
        s = d.toStringAsFixed(0);
      }
    }
    if (s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    final digitsOnly = s.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.isNotEmpty ? digitsOnly : s;
  }

  static double? _parseAmount(String raw) {
    if (raw.isEmpty) return null;
    String s = raw.replaceAll('₹', '').replaceAll(',', '').replaceAll(' ', '').trim();
    if (s.toLowerCase().contains('e+')) {
      final d = double.tryParse(s);
      if (d != null) return d;
    }
    return double.tryParse(s.replaceAll(RegExp(r'[^\d.]'), ''));
  }

  /// Helper to parse sub-departments from CSV cell
  static List<StudentSubDepartment>? _parseSubDepartments(String raw) {
    if (raw.trim().isEmpty) return null;
    final str = raw.trim();

    // 1. Try JSON decoding first if it starts with [
    if (str.startsWith('[')) {
      try {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          return decoded.map((i) => StudentSubDepartment.fromJson(Map<String, dynamic>.from(i))).toList();
        }
      } catch (_) {}
    }

    // 2. Format: "Hifz (Class: Class 1, Div: A); Tajweed (Class: Class 2, Div: B)" or "Hifz; Tajweed"
    final List<StudentSubDepartment> results = [];
    final items = str.split(RegExp(r'[;,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty);

    for (final item in items) {
      final match = RegExp(r'^([^(\n]+)(?:\((.*)\))?$').firstMatch(item);
      if (match != null) {
        final name = match.group(1)?.trim() ?? '';
        final details = match.group(2)?.trim() ?? '';

        String? cls;
        String? div;

        if (details.isNotEmpty) {
          final detailParts = details.split(',').map((p) => p.trim());
          for (final part in detailParts) {
            if (part.toLowerCase().startsWith('class:') || part.toLowerCase().startsWith('cls:')) {
              cls = part.substring(part.indexOf(':') + 1).trim();
            } else if (part.toLowerCase().startsWith('div:') || part.toLowerCase().startsWith('sec:')) {
              div = part.substring(part.indexOf(':') + 1).trim();
            } else if (cls == null) {
              cls = part;
            } else if (div == null) {
              div = part;
            }
          }
        }

        if (name.isNotEmpty) {
          results.add(StudentSubDepartment(
            subDepartmentName: name,
            className: cls,
            division: div,
          ));
        }
      }
    }

    return results.isNotEmpty ? results : null;
  }

  /// Imports students from picked CSV / Excel file
  static Future<ImportResult> importStudentsFromCsv({
    required File file,
    required StudentRepository repository,
  }) async {
    final content = await file.readAsString(encoding: utf8);
    final allRows = _parseCsv(content);

    if (allRows.isEmpty) {
      return ImportResult(
        totalRows: 0,
        importedCount: 0,
        skippedCount: 0,
        errors: ['The selected file is empty.'],
      );
    }

    // Load existing GR numbers & GR settings for auto-generating missing GR numbers
    final existingStudents = await repository.getAllStudents();
    final Set<String> allActiveGrNos = existingStudents
        .map((s) => (s.grNo ?? s.registrationNumber).trim().toLowerCase())
        .where((g) => g.isNotEmpty)
        .toSet();

    final List<String> activeGrList = existingStudents
        .map((s) => (s.grNo ?? s.registrationNumber).trim())
        .where((g) => g.isNotEmpty)
        .toList();

    final grSettings = await GrNoSettings.loadSettings();

    // Determine header mapping
    final headerCols = allRows.first.map((h) => h.toLowerCase().trim()).toList();

    bool hasHeader = headerCols.any((h) => h.contains('name') || h.contains('gr') || h.contains('dob') || h.contains('roll') || h.contains('fee') || h.contains('طالب') || h.contains('داخلہ'));
    int startIndex = hasHeader ? 1 : 0;

    int grIdx = -1;
    int rollIdx = -1;
    int nameIdx = -1;
    int fatherIdx = -1;
    int surnameIdx = -1;
    int grandFatherIdx = -1;
    int genderIdx = -1;
    int dobIdx = -1;
    int admAgeIdx = -1;
    int nowAgeIdx = -1;
    int deptIdx = -1;
    int classIdx = -1;
    int divIdx = -1;
    int subDeptIdx = -1;
    int catIdx = -1;
    int statusIdx = -1;
    int admTypeIdx = -1;
    int admDateIdx = -1;
    int admDateHIdx = -1;
    int condIdx = -1;
    int standardFeesIdx = -1;
    int netFeesIdx = -1;
    int feesIdx = -1;
    int contribNameIdx = -1;
    int contribAmtIdx = -1;
    int attendanceIdx = -1;
    int pendingFeesIdx = -1;
    int mobileIdx = -1;
    int aadhaarIdx = -1;
    int villageIdx = -1;
    int talukaIdx = -1;
    int districtIdx = -1;
    int stateIdx = -1;
    int pinIdx = -1;
    int addressIdx = -1;

    for (int col = 0; col < headerCols.length; col++) {
      final h = headerCols[col];

      // 1. Grandfather Name (Must check before Father and GR!)
      if (h.contains('grand') || h.contains('دادا') || h.contains('جد')) {
        grandFatherIdx = col;
      }
      // 2. Father Name (Must not contain grand)
      else if ((h.contains('father') && !h.contains('grand')) || (h.contains('والد') && !h.contains('والدہ')) || h.contains('پدر')) {
        fatherIdx = col;
      }
      // 3. Surname / Caste (Must check before generic Name because 'surname' ends with 'name'!)
      else if (h.contains('surname') || h.contains('قوم') || h.contains('ذات') || h.contains('caste') || h.contains('last name') || h.contains('خاندان') || h.contains('قبیلہ') || h.contains('سرنیم') || h.contains('لقب')) {
        surnameIdx = col;
      }
      // 4. Sub-Department (Must check before Class and Department!)
      else if (h.contains('sub_dept') || h.contains('sub dept') || h.contains('sub department') || h.contains('ذیلی شعبہ') || h.contains('sub department')) {
        subDeptIdx = col;
      }
      // 5. Department (Must check before Class and generic Name!)
      else if (h.contains('department') || h.contains('dept') || (h.contains('شعبہ') && !h.contains('ذیلی'))) {
        deptIdx = col;
      }
      // 6. Class / Grade / Darja (Must check before Name and GR!)
      else if (h.contains('class') || h.contains('darja') || (h.contains('grade') && !h.contains('grand')) || h.contains('درجہ') || h.contains('جماعت') || (h.contains('standard') && !h.contains('fee'))) {
        classIdx = col;
      }
      // 7. Staff / Contributor Name / Amount
      else if (h.contains('staff') || h.contains('contributor') || h.contains('sponsor') || h.contains('kofil') || h.contains('کفیل') || h.contains('استاذ') || h.contains('رعایت کنندہ')) {
        if (h.contains('amount') || h.contains('rupee') || h.contains('₹') || h.contains('discount') || h.contains('concession')) {
          contribAmtIdx = col;
        } else {
          contribNameIdx = col;
        }
      }
      // 6. Full Name / Student Name (Explicitly exclude surname, father, grand, class, staff)
      else if (h.contains('full name') || h.contains('student name') || h.contains('first name') || h.contains('طالب علم') || h.contains('طالب') || h.contains('شاگرد') || (h.contains('name') && !h.contains('class') && !h.contains('father') && !h.contains('grand') && !h.contains('staff') && !h.contains('contributor') && !h.contains('surname') && !h.contains('last') && !h.contains('sur name')) || h == 'نام' || h == 'اسم') {
        nameIdx = col;
      }
      // 7. GR / Registration Number / Admission No (Exclude grand, grade, progress, background)
      else if ((h.contains('gr') && !h.contains('grand') && !h.contains('grade')) ||
               h.contains('g.r') ||
               h.contains('admission no') ||
               h.contains('dakhla no') ||
               h.contains('داخلہ نمبر') ||
               h.contains('رجسٹریشن') ||
               h.contains('جی آر') ||
               h == 'sr no' || h == 's.no' || h == 'sr. no' || h == 'sr.' || h == 'serial no' || h == 'serial' ||
               h.contains('reg no') || h.contains('registration no') || h.contains('registration number') || (h.contains('reg') && !h.contains('regular'))) {
        grIdx = col;
      }
      // 8. Roll Number
      else if (h.contains('roll') || h.contains('رول')) {
        rollIdx = col;
      }
      // 9. Gender
      else if (h.contains('gender') || h.contains('sex') || h.contains('jins') || h.contains('جنس')) {
        genderIdx = col;
      }
      // 10. Date of Birth
      else if (h.contains('birth') || h.contains('dob') || h.contains('d.o.b') || h.contains('تاریخ پیدائش') || h.contains('janam')) {
        dobIdx = col;
      }
      // 11. Hijri Date
      else if (h.contains('hijri') || h.contains('islami') || h.contains('ہجری')) {
        admDateHIdx = col;
      }
      // 12. Admission Date
      else if ((h.contains('admission') && h.contains('date')) || (h.contains('dakhla') && h.contains('tarikh')) || h.contains('تاریخ داخلہ') || h.contains('تاریخ اندراج') || h.contains('adm_date') || h.contains('joining date') || h.contains('enroll')) {
        admDateIdx = col;
      }
      // 13. Age
      else if (h.contains('admission time age') || h.contains('age at admission') || h.contains('عمر بوقت داخلہ')) {
        admAgeIdx = col;
      } else if (h.contains('now age') || h.contains('current age') || h.contains('موجودہ عمر') || (h.contains('age') && !h.contains('admission'))) {
        nowAgeIdx = col;
      }
      // 14. Division
      else if (h.contains('div') || h.contains('section') || h.contains('شعبہ') || h.contains('سیکشن') || h.contains('tukdi')) {
        divIdx = col;
      }
      // 15. Category
      else if (h.contains('cat') || h.contains('قسم') || h.contains('category')) {
        catIdx = col;
      }
      // 16. Status
      else if (h.contains('status') || h.contains('halat') || h.contains('حالت')) {
        statusIdx = col;
      }
      // 17. Admission Type
      else if (h.contains('admission type') || h.contains('adm_type') || h.contains('قسم داخلہ')) {
        admTypeIdx = col;
      }
      // 18. Condition Type
      else if (h.contains('condition') || h.contains('shart') || h.contains('شرط')) {
        condIdx = col;
      }
      // 19. Fees
      else if (h.contains('standard') || h.contains('full fee') || h.contains('base fee') || h.contains('مکمل فیس') || h.contains('اصل فیس')) {
        standardFeesIdx = col;
      } else if (h.contains('net') || h.contains('calculated') || h.contains('خالص فیس')) {
        netFeesIdx = col;
      } else if (h.contains('concession') || h.contains('discount') || h.contains('contributor amount') || h.contains('riayat') || h.contains('رعایت')) {
        contribAmtIdx = col;
      } else if (h.contains('pending') || h.contains('due') || h.contains('بقایا')) {
        pendingFeesIdx = col;
      } else if (h.contains('fee') || h.contains('monthly') || h.contains('فیس') || h.contains('ماہانہ')) {
        feesIdx = col;
      }
      // 20. Attendance
      else if (h.contains('attendance') || h.contains('hazri') || h.contains('حاضری')) {
        attendanceIdx = col;
      }
      // 21. Mobile
      else if (h.contains('mobile') || h.contains('phone') || h.contains('contact') || h.contains('موبائل') || h.contains('فون')) {
        mobileIdx = col;
      }
      // 22. Aadhaar
      else if (h.contains('aadhaar') || h.contains('adhar') || h.contains('uid') || h.contains('آدھار')) {
        aadhaarIdx = col;
      }
      // 23. Address fields
      else if (h.contains('village') || h.contains('gaon') || h.contains('city') || h.contains('گاؤں') || h.contains('شہر')) {
        villageIdx = col;
      } else if (h.contains('taluka') || h.contains('tahsil') || h.contains('block') || h.contains('تحصیل')) {
        talukaIdx = col;
      } else if (h.contains('district') || h.contains('zila') || h.contains('ضلع')) {
        districtIdx = col;
      } else if (h.contains('state') || h.contains('subah') || h.contains('rajya') || h.contains('صوبہ') || h.contains('ریاست')) {
        stateIdx = col;
      } else if (h.contains('pin') || h.contains('postal') || h.contains('zip') || h.contains('پن کوڈ')) {
        pinIdx = col;
      } else if (h.contains('address') || h.contains('pata') || h.contains('address line') || h.contains('پتہ')) {
        addressIdx = col;
      }
    }

    // If header indices not found and standard columns exist, apply positional defaults
    if (headerCols.length >= 12) {
      if (grIdx == -1) grIdx = 0;
      if (rollIdx == -1 && (headerCols.length > 1 && headerCols[1].contains('roll'))) rollIdx = 1;
      if (nameIdx == -1) nameIdx = 2;
      if (fatherIdx == -1) fatherIdx = 3;
      if (surnameIdx == -1) surnameIdx = 4;
      if (grandFatherIdx == -1) grandFatherIdx = 5;
      if (genderIdx == -1) genderIdx = 6;
      if (dobIdx == -1) dobIdx = 7;
      if (classIdx == -1) classIdx = 10;
      if (divIdx == -1) divIdx = 11;
      if (catIdx == -1) catIdx = 12;
      if (statusIdx == -1) statusIdx = 13;
    } else if (headerCols.length >= 6) {
      if (grIdx == -1) grIdx = 0;
      if (rollIdx == -1 && (headerCols.length > 1 && headerCols[1].contains('roll'))) rollIdx = 1;
      if (nameIdx == -1) nameIdx = 2;
      if (fatherIdx == -1) fatherIdx = 3;
      if (surnameIdx == -1) surnameIdx = 4;
      if (grandFatherIdx == -1) grandFatherIdx = 5;
    }

    if (nameIdx == -1) {
      nameIdx = headerCols.indexWhere((h) => (h.contains('name') && !h.contains('class') && !h.contains('father') && !h.contains('grand')) || h.contains('طالب'));
    }

    int imported = 0;
    int skipped = 0;
    final List<String> errors = [];

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (int i = startIndex; i < allRows.length; i++) {
      final cols = allRows[i];
      if (cols.isEmpty || !cols.any((c) => c.trim().isNotEmpty)) continue;

      String getCol(int idx) {
        if (idx >= 0 && idx < cols.length) {
          return cols[idx].trim();
        }
        return '';
      }

      String fullName = nameIdx >= 0 ? getCol(nameIdx) : '';
      if (fullName.isEmpty) {
        // Resilient fallback: check other text columns if nameIdx was empty
        for (int c = 0; c < cols.length; c++) {
          if (c != grIdx && c != rollIdx && c != classIdx && c != mobileIdx && c != aadhaarIdx && c != pinIdx) {
            final val = cols[c].trim();
            if (val.isNotEmpty && val != '-' && !RegExp(r'^[0-9.\-+₹\s]+$').hasMatch(val)) {
              fullName = val;
              break;
            }
          }
        }
      }

      if (fullName.isEmpty) {
        skipped++;
        errors.add('Row ${i + 1}: Skipped due to missing Full Name');
        continue;
      }

      String grNo = grIdx >= 0 ? getCol(grIdx) : (cols.isNotEmpty ? cols[0] : '');
      if (grNo.isEmpty || grNo == fullName) {
        // Auto generate GR number in series if missing
        grNo = GrNoGenerator.generateNextGrNo(
          existingGrNos: activeGrList,
          settings: grSettings,
        );
      }
      allActiveGrNos.add(grNo.trim().toLowerCase());
      activeGrList.add(grNo.trim());

      String rollNumber = rollIdx >= 0 ? getCol(rollIdx) : '';
      if (rollNumber.isNotEmpty &&
          (RegExp(r'^\d{4}[-\/\.]\d{1,2}[-\/\.]\d{1,2}').hasMatch(rollNumber.trim()) ||
           RegExp(r'^\d{1,2}[-\/\.]\d{1,2}[-\/\.]\d{2,4}').hasMatch(rollNumber.trim()))) {
        rollNumber = '';
      }
      final fatherName = fatherIdx >= 0 ? getCol(fatherIdx) : '';
      final surname = surnameIdx >= 0 ? getCol(surnameIdx) : '';
      final grandFatherName = grandFatherIdx >= 0 ? getCol(grandFatherIdx) : '';
      
      final rawDob = dobIdx >= 0 ? getCol(dobIdx) : '';
      final normDob = _normalizeDate(rawDob);

      final gender = genderIdx >= 0 ? getCol(genderIdx) : 'Male';
      final className = classIdx >= 0 ? getCol(classIdx) : '';
      final division = divIdx >= 0 ? getCol(divIdx) : '';
      final category = catIdx >= 0 ? getCol(catIdx) : '';
      final status = statusIdx >= 0 && getCol(statusIdx).isNotEmpty ? getCol(statusIdx) : 'Active';
      final admissionType = admTypeIdx >= 0 ? getCol(admTypeIdx) : 'New';
      
      final rawAdmDate = admDateIdx >= 0 && getCol(admDateIdx).isNotEmpty ? getCol(admDateIdx) : today;
      final normAdmDate = _normalizeDate(rawAdmDate);

      final admissionDateH = admDateHIdx >= 0 ? getCol(admDateHIdx) : '';
      final conditionType = condIdx >= 0 && getCol(condIdx).isNotEmpty ? getCol(condIdx) : 'Regular';

      // ── Fee Calculation ──
      final double? netFeesVal = netFeesIdx >= 0 ? _parseAmount(getCol(netFeesIdx)) : null;
      final double? stdFeesVal = standardFeesIdx >= 0 ? _parseAmount(getCol(standardFeesIdx)) : null;
      final double? genFeesVal = feesIdx >= 0 ? _parseAmount(getCol(feesIdx)) : null;
      final double? discVal = contribAmtIdx >= 0 ? _parseAmount(getCol(contribAmtIdx)) : null;
      final String contribName = contribNameIdx >= 0 ? getCol(contribNameIdx) : '';

      double? finalMonthlyFees;
      double? finalContribAmt = discVal;

      if (netFeesVal != null && netFeesVal > 0) {
        finalMonthlyFees = netFeesVal;
      } else if (genFeesVal != null && genFeesVal > 0) {
        finalMonthlyFees = genFeesVal;
      } else if (stdFeesVal != null && stdFeesVal > 0) {
        if (discVal != null && discVal > 0) {
          finalMonthlyFees = (stdFeesVal - discVal).clamp(0.0, double.infinity);
        } else {
          finalMonthlyFees = stdFeesVal;
        }
      } else {
        finalMonthlyFees = 0.0;
      }

      // ── Age Calculation ──
      final calcAdmAge = _computeAge(normDob, normAdmDate);
      final calcNowAge = _computeAge(normDob);

      final String finalAdmAge = (admAgeIdx >= 0 && getCol(admAgeIdx).isNotEmpty && getCol(admAgeIdx) != '0Days')
          ? getCol(admAgeIdx)
          : calcAdmAge;

      final String finalNowAge = (nowAgeIdx >= 0 && getCol(nowAgeIdx).isNotEmpty && getCol(nowAgeIdx) != '0Days')
          ? getCol(nowAgeIdx)
          : calcNowAge;

      // ── Contact & Address with Scientific Notation Cleanup ──
      final mobileNo = mobileIdx >= 0 ? _cleanMobile(getCol(mobileIdx)) : '';
      final aadhaarNo = aadhaarIdx >= 0 ? _cleanAadhaar(getCol(aadhaarIdx)) : '';
      final village = villageIdx >= 0 ? getCol(villageIdx) : '';
      final taluka = talukaIdx >= 0 ? getCol(talukaIdx) : '';
      final district = districtIdx >= 0 ? getCol(districtIdx) : '';
      final state = stateIdx >= 0 ? getCol(stateIdx) : '';
      final pinCode = pinIdx >= 0 ? _cleanPincode(getCol(pinIdx)) : '';
      final address = addressIdx >= 0 ? getCol(addressIdx) : '';
      final attendance = attendanceIdx >= 0 ? (int.tryParse(getCol(attendanceIdx)) ?? 0) : 0;
      final pendingFees = pendingFeesIdx >= 0 ? (_parseAmount(getCol(pendingFeesIdx)) ?? 0.0) : 0.0;
      final departmentName = deptIdx >= 0 && getCol(deptIdx).isNotEmpty ? getCol(deptIdx) : null;
      final rawSubDepts = subDeptIdx >= 0 ? getCol(subDeptIdx) : '';
      final parsedSubDepts = _parseSubDepartments(rawSubDepts);

      final newStudent = Student(
        id: '', // Server will generate UUID or match by GR.NO.
        grNo: grNo,
        registrationNumber: grNo,
        rollNumber: rollNumber.isNotEmpty ? rollNumber : null,
        fullName: fullName,
        fatherName: fatherName.isNotEmpty ? fatherName : null,
        surname: surname.isNotEmpty ? surname : null,
        grandFatherName: grandFatherName.isNotEmpty ? grandFatherName : null,
        dateOfBirth: normDob.isNotEmpty ? normDob : null,
        gender: gender.isNotEmpty ? gender : 'Male',
        departmentName: departmentName,
        className: className.isNotEmpty ? className : null,
        division: division.isNotEmpty ? division : null,
        subDepartments: parsedSubDepts,
        category: category.isNotEmpty ? category : null,
        studentStatus: status,
        admissionType: admissionType.isNotEmpty ? admissionType : 'New',
        admissionDate: normAdmDate.isNotEmpty ? normAdmDate : today,
        admissionDateH: admissionDateH.isNotEmpty ? admissionDateH : null,
        conditionType: conditionType,
        monthlyFees: finalMonthlyFees,
        contributorName: contribName.isNotEmpty ? contribName : null,
        contributorAmount: finalContribAmt,
        admissionTimeAge: finalAdmAge.isNotEmpty ? finalAdmAge : null,
        nowAge: finalNowAge.isNotEmpty ? finalNowAge : null,
        totalAttendance: attendance,
        pendingFees: pendingFees,
        mobileNo: mobileNo.isNotEmpty ? mobileNo : null,
        aadhaarNo: aadhaarNo.isNotEmpty ? aadhaarNo : null,
        village: village.isNotEmpty ? village : null,
        taluka: taluka.isNotEmpty ? taluka : null,
        district: district.isNotEmpty ? district : null,
        state: state.isNotEmpty ? state : null,
        pinCode: pinCode.isNotEmpty ? pinCode : null,
        address: address.isNotEmpty ? address : null,
      );

      try {
        await repository.createStudent(newStudent);
        imported++;
      } catch (e) {
        skipped++;
        // Clean error string
        String errStr = e.toString();
        if (errStr.contains('message:')) {
          final m = RegExp(r'"message":\s*"([^"]+)"').firstMatch(errStr);
          if (m != null) errStr = m.group(1)!;
        }
        errors.add('Row ${i + 1} ($fullName): $errStr');
      }
    }

    return ImportResult(
      totalRows: allRows.length - startIndex,
      importedCount: imported,
      skippedCount: skipped,
      errors: errors,
    );
  }
}
