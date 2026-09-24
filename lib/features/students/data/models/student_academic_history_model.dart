import 'dart:convert';

class StudentAcademicHistory {
  final String id;
  final String studentId;
  final String academicYear;
  final String? academicYearHijri;
  final String? classId;
  final String className;
  final String? departmentId;
  final String? departmentName;
  final String? division;
  final String? rollNumber;
  final int totalAttendanceDays;
  final int presentDays;
  final double attendancePercentage;
  final double totalMarks;
  final double obtainedMarks;
  final double examPercentage;
  final String? resultGrade;
  final String status; // 'Promoted', 'Repeated', 'Farigh', 'Khariz', 'Active'
  final String? remarks;
  final String? promotedAt;
  final String? createdAt;
  final String? booksMarksJson;
  final double feeTotal;
  final double feePaid;
  final double feePending;
  final double perStudentExpense;
  final String? metadataJson;

  StudentAcademicHistory({
    required this.id,
    required this.studentId,
    required this.academicYear,
    this.academicYearHijri,
    this.classId,
    required this.className,
    this.departmentId,
    this.departmentName,
    this.division,
    this.rollNumber,
    this.totalAttendanceDays = 0,
    this.presentDays = 0,
    this.attendancePercentage = 0.0,
    this.totalMarks = 0.0,
    this.obtainedMarks = 0.0,
    this.examPercentage = 0.0,
    this.resultGrade,
    this.status = 'Promoted',
    this.remarks,
    this.promotedAt,
    this.createdAt,
    this.booksMarksJson,
    this.feeTotal = 0.0,
    this.feePaid = 0.0,
    this.feePending = 0.0,
    this.perStudentExpense = 0.0,
    this.metadataJson,
  });

  factory StudentAcademicHistory.fromJson(Map<String, dynamic> json) {
    return StudentAcademicHistory(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      academicYear: json['academic_year']?.toString() ?? '',
      academicYearHijri: json['academic_year_hijri']?.toString(),
      classId: json['class_id']?.toString(),
      className: json['class_name']?.toString() ?? '-',
      departmentId: json['department_id']?.toString(),
      departmentName: json['department_name']?.toString(),
      division: json['division']?.toString(),
      rollNumber: json['roll_number']?.toString(),
      totalAttendanceDays: (json['total_attendance_days'] as num?)?.toInt() ?? 0,
      presentDays: (json['present_days'] as num?)?.toInt() ?? 0,
      attendancePercentage: (json['attendance_percentage'] as num?)?.toDouble() ?? 0.0,
      totalMarks: (json['total_marks'] as num?)?.toDouble() ?? 0.0,
      obtainedMarks: (json['obtained_marks'] as num?)?.toDouble() ?? 0.0,
      examPercentage: (json['exam_percentage'] as num?)?.toDouble() ?? 0.0,
      resultGrade: json['result_grade']?.toString(),
      status: json['status']?.toString() ?? 'Promoted',
      remarks: json['remarks']?.toString(),
      promotedAt: json['promoted_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      booksMarksJson: json['books_marks_json']?.toString(),
      feeTotal: (json['fee_total'] as num?)?.toDouble() ?? 0.0,
      feePaid: (json['fee_paid'] as num?)?.toDouble() ?? 0.0,
      feePending: (json['fee_pending'] as num?)?.toDouble() ?? 0.0,
      perStudentExpense: (json['per_student_expense'] as num?)?.toDouble() ?? 0.0,
      metadataJson: json['metadata_json']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_id': studentId,
      'academic_year': academicYear,
      'academic_year_hijri': academicYearHijri,
      'class_id': classId,
      'class_name': className,
      'department_id': departmentId,
      'department_name': departmentName,
      'division': division,
      'roll_number': rollNumber,
      'total_attendance_days': totalAttendanceDays,
      'present_days': presentDays,
      'attendance_percentage': attendancePercentage,
      'total_marks': totalMarks,
      'obtained_marks': obtainedMarks,
      'exam_percentage': examPercentage,
      'result_grade': resultGrade,
      'status': status,
      'remarks': remarks,
      'promoted_at': promotedAt,
      'created_at': createdAt,
      'books_marks_json': booksMarksJson,
      'fee_total': feeTotal,
      'fee_paid': feePaid,
      'fee_pending': feePending,
      'per_student_expense': perStudentExpense,
      'metadata_json': metadataJson,
    };
  }

  List<Map<String, dynamic>> get parsedBooksAndMarks {
    if (booksMarksJson == null || booksMarksJson!.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(booksMarksJson!);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  Map<String, dynamic> get parsedMetadata {
    if (metadataJson == null || metadataJson!.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(metadataJson!);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  List<Map<String, dynamic>> get parsedAttendanceRecords {
    final meta = parsedMetadata;
    final list = meta['attendance_records'];
    if (list is List) {
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> get parsedMonthlySummary {
    final meta = parsedMetadata;
    final list = meta['attendance_monthly_summary'];
    if (list is List) {
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> get parsedFeePayments {
    final meta = parsedMetadata;
    final list = meta['fee_payments'];
    if (list is List) {
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> get parsedFeeBreakdown {
    final meta = parsedMetadata;
    final list = meta['fee_breakdown'];
    if (list is List) {
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return [];
  }

  StudentAcademicHistory copyWith({
    String? id,
    String? studentId,
    String? academicYear,
    String? academicYearHijri,
    String? classId,
    String? className,
    String? departmentId,
    String? departmentName,
    String? division,
    String? rollNumber,
    int? totalAttendanceDays,
    int? presentDays,
    double? attendancePercentage,
    double? totalMarks,
    double? obtainedMarks,
    double? examPercentage,
    String? resultGrade,
    String? status,
    String? remarks,
    String? promotedAt,
    String? createdAt,
    String? booksMarksJson,
    double? feeTotal,
    double? feePaid,
    double? feePending,
    double? perStudentExpense,
    String? metadataJson,
  }) {
    return StudentAcademicHistory(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      academicYear: academicYear ?? this.academicYear,
      academicYearHijri: academicYearHijri ?? this.academicYearHijri,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      division: division ?? this.division,
      rollNumber: rollNumber ?? this.rollNumber,
      totalAttendanceDays: totalAttendanceDays ?? this.totalAttendanceDays,
      presentDays: presentDays ?? this.presentDays,
      attendancePercentage: attendancePercentage ?? this.attendancePercentage,
      totalMarks: totalMarks ?? this.totalMarks,
      obtainedMarks: obtainedMarks ?? this.obtainedMarks,
      examPercentage: examPercentage ?? this.examPercentage,
      resultGrade: resultGrade ?? this.resultGrade,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      promotedAt: promotedAt ?? this.promotedAt,
      createdAt: createdAt ?? this.createdAt,
      booksMarksJson: booksMarksJson ?? this.booksMarksJson,
      feeTotal: feeTotal ?? this.feeTotal,
      feePaid: feePaid ?? this.feePaid,
      feePending: feePending ?? this.feePending,
      perStudentExpense: perStudentExpense ?? this.perStudentExpense,
      metadataJson: metadataJson ?? this.metadataJson,
    );
  }
}
