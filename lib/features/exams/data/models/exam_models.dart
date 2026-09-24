class Exam {
  final int? id;
  final String name;
  final String? startDate;
  final String? endDate;
  final String status;
  final String? createdAt;

  Exam({
    this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.status = 'DRAFT',
    this.createdAt,
  });

  factory Exam.fromJson(Map<String, dynamic> json) {
    return Exam(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      name: json['name'] ?? '',
      startDate: json['start_date'],
      endDate: json['end_date'],
      status: json['status'] ?? 'DRAFT',
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'start_date': startDate,
      'end_date': endDate,
      'status': status,
    };
  }
}

class ExamSchedule {
  final int? id;
  final int examId;
  final String classId;
  final String bookId;
  final String? examDate;
  final String? startTime;
  final String? endTime;
  final int maxMarks;
  final int? passingMarks;
  final String? className;
  final String? bookName;
  final int? studentCount;
  final String? departmentId;
  final String? departmentName;
  final String? parentDepartmentName;

  ExamSchedule({
    this.id,
    required this.examId,
    required this.classId,
    required this.bookId,
    this.examDate,
    this.startTime,
    this.endTime,
    required this.maxMarks,
    this.passingMarks,
    this.className,
    this.bookName,
    this.studentCount,
    this.departmentId,
    this.departmentName,
    this.parentDepartmentName,
  });

  factory ExamSchedule.fromJson(Map<String, dynamic> json) {
    return ExamSchedule(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      examId: json['exam_id'] is int
          ? json['exam_id']
          : int.tryParse('${json['exam_id']}') ?? 0,
      classId: '${json['class_id']}',
      bookId: '${json['book_id']}',
      examDate: json['exam_date'],
      startTime: json['start_time'],
      endTime: json['end_time'],
      maxMarks: json['max_marks'] ?? 100,
      passingMarks: json['passing_marks'],
      className: json['class_name'],
      bookName: json['book_name'],
      studentCount: json['student_count'] is int
          ? json['student_count']
          : (json['student_qty'] is int ? json['student_qty'] : int.tryParse('${json['student_count'] ?? json['student_qty'] ?? json['qty']}')),
      departmentId: json['department_id']?.toString(),
      departmentName: json['department_name']?.toString(),
      parentDepartmentName: json['parent_department_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'exam_id': examId,
      'class_id': classId,
      'book_id': bookId,
      'exam_date': examDate,
      'start_time': startTime,
      'end_time': endTime,
      'max_marks': maxMarks,
      'passing_marks': passingMarks,
      'class_name': className,
      'book_name': bookName,
      'student_count': studentCount,
      if (departmentId != null) 'department_id': departmentId,
      if (departmentName != null) 'department_name': departmentName,
      if (parentDepartmentName != null) 'parent_department_name': parentDepartmentName,
    };
  }
}

class ExamHall {
  final int? id;
  final String name;
  final int totalRows;
  final int totalColumns;
  final int totalCapacity;
  final bool isActive;

  ExamHall({
    this.id,
    required this.name,
    required this.totalRows,
    required this.totalColumns,
    int? totalCapacity,
    this.isActive = true,
  }) : totalCapacity = totalCapacity ?? (totalRows * totalColumns);

  factory ExamHall.fromJson(Map<String, dynamic> json) {
    final rows = json['total_rows'] is int ? json['total_rows'] : (int.tryParse('${json['total_rows']}') ?? 0);
    final cols = json['total_columns'] is int ? json['total_columns'] : (int.tryParse('${json['total_columns']}') ?? 0);
    final calculated = rows * cols;
    return ExamHall(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      name: json['name'] ?? '',
      totalRows: rows,
      totalColumns: cols,
      totalCapacity: calculated > 0 ? calculated : (json['total_capacity'] ?? 0),
      isActive: json['is_active'] == 1 || json['is_active'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'total_rows': totalRows,
      'total_columns': totalColumns,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class SeatingArrangement {
  final int? id;
  final int examId;
  final int? scheduleId;
  final int hallId;
  final String studentId;
  final String bookId;
  final String classId;
  final int seatRow;
  final int seatColumn;
  final int seatNumber;
  final String? sessionDate;
  final String? sessionTime;
  final String assignmentMethod;
  final String? studentName;
  final String? registrationNumber;
  final String? rollNumber;
  final String? bookName;
  final String? className;
  final String? hallName;

  SeatingArrangement({
    this.id,
    required this.examId,
    this.scheduleId,
    required this.hallId,
    required this.studentId,
    required this.bookId,
    required this.classId,
    required this.seatRow,
    required this.seatColumn,
    required this.seatNumber,
    this.sessionDate,
    this.sessionTime,
    this.assignmentMethod = 'ANTI_ADJACENCY',
    this.studentName,
    this.registrationNumber,
    this.rollNumber,
    this.bookName,
    this.className,
    this.hallName,
  });

  factory SeatingArrangement.fromJson(Map<String, dynamic> json) {
    return SeatingArrangement(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      examId: json['exam_id'] is int
          ? json['exam_id']
          : int.tryParse('${json['exam_id']}') ?? 0,
      scheduleId: json['schedule_id'] is int
          ? json['schedule_id']
          : int.tryParse('${json['schedule_id']}'),
      hallId: json['hall_id'] is int
          ? json['hall_id']
          : int.tryParse('${json['hall_id']}') ?? 0,
      studentId: '${json['student_id']}',
      bookId: '${json['book_id']}',
      classId: '${json['class_id']}',
      seatRow: json['seat_row'] ?? 0,
      seatColumn: json['seat_column'] ?? 0,
      seatNumber: json['seat_number'] ?? 0,
      sessionDate: json['session_date'],
      sessionTime: json['session_time'],
      assignmentMethod: json['assignment_method'] ?? 'ANTI_ADJACENCY',
      studentName: json['student_name'] ?? json['full_name'] ?? json['name'] ?? json['studentName'],
      registrationNumber: json['registration_number'] ?? json['gr_no'] ?? json['grNo'] ?? json['registrationNumber'],
      rollNumber: json['roll_number'] ?? json['rollNo'] ?? json['roll_no'],
      bookName: json['book_name'] ?? json['bookName'],
      className: json['class_name'] ?? json['className'],
      hallName: json['hall_name'] ?? json['hallName'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exam_id': examId,
      'schedule_id': scheduleId,
      'hall_id': hallId,
      'student_id': studentId,
      'student_name': studentName,
      'registration_number': registrationNumber,
      'roll_number': rollNumber,
      'book_id': bookId,
      'book_name': bookName,
      'class_id': classId,
      'class_name': className,
      'seat_row': seatRow,
      'seat_column': seatColumn,
      'seat_number': seatNumber,
      'session_date': sessionDate,
      'session_time': sessionTime,
      'assignment_method': assignmentMethod,
    };
  }
}

class ExamMark {
  final int? id;
  final int examId;
  final int scheduleId;
  final String studentId;
  final String? studentName;
  final String? registrationNumber;
  final String? rollNumber;
  final String? division;
  final String bookId;
  final String? bookName;
  final String classId;
  final String? className;
  final int maxMarks;
  final double? marksObtained;
  final bool isAbsent;
  final String? remarks;
  final String? enteredBy;

  ExamMark({
    this.id,
    required this.examId,
    required this.scheduleId,
    required this.studentId,
    this.studentName,
    this.registrationNumber,
    this.rollNumber,
    this.division,
    required this.bookId,
    this.bookName,
    required this.classId,
    this.className,
    this.maxMarks = 100,
    this.marksObtained,
    this.isAbsent = false,
    this.remarks,
    this.enteredBy,
  });

  factory ExamMark.fromJson(Map<String, dynamic> json) {
    return ExamMark(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      examId: json['exam_id'] is int
          ? json['exam_id']
          : int.tryParse('${json['exam_id']}') ?? 0,
      scheduleId: json['schedule_id'] is int
          ? json['schedule_id']
          : int.tryParse('${json['schedule_id']}') ?? 0,
      studentId: '${json['student_id']}',
      studentName: json['student_name'],
      registrationNumber: json['registration_number'],
      rollNumber: json['roll_number']?.toString() ?? json['rollNumber']?.toString() ?? json['roll_no']?.toString(),
      division: json['division']?.toString() ?? json['section']?.toString(),
      bookId: '${json['book_id'] ?? json['bookId'] ?? ''}',
      bookName: json['book_name'] ?? json['bookName'] ?? json['subject_name'] ?? json['subjectName'] ?? json['subject'] ?? json['name'] ?? json['title'],
      classId: '${json['class_id'] ?? json['classId'] ?? ''}',
      className: json['class_name'],
      maxMarks: json['max_marks'] ?? 100,
      marksObtained: json['marks_obtained'] != null
          ? (json['marks_obtained'] as num).toDouble()
          : null,
      isAbsent: json['is_absent'] == 1 || json['is_absent'] == true,
      remarks: json['remarks'],
      enteredBy: json['entered_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'exam_id': examId,
      'schedule_id': scheduleId,
      'student_id': studentId,
      'student_name': studentName,
      'registration_number': registrationNumber,
      if (rollNumber != null) 'roll_number': rollNumber,
      if (division != null) 'division': division,
      'book_id': bookId,
      'book_name': bookName,
      'class_id': classId,
      'class_name': className,
      'max_marks': maxMarks,
      'marks_obtained': marksObtained,
      'is_absent': isAbsent ? 1 : 0,
      'remarks': remarks,
      'entered_by': enteredBy,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  ExamMark copyWith({
    int? id,
    int? examId,
    int? scheduleId,
    String? studentId,
    String? studentName,
    String? registrationNumber,
    String? rollNumber,
    String? division,
    String? bookId,
    String? bookName,
    String? classId,
    String? className,
    int? maxMarks,
    double? marksObtained,
    bool? isAbsent,
    String? remarks,
    String? enteredBy,
  }) {
    return ExamMark(
      id: id ?? this.id,
      examId: examId ?? this.examId,
      scheduleId: scheduleId ?? this.scheduleId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      rollNumber: rollNumber ?? this.rollNumber,
      division: division ?? this.division,
      bookId: bookId ?? this.bookId,
      bookName: bookName ?? this.bookName,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      maxMarks: maxMarks ?? this.maxMarks,
      marksObtained: marksObtained ?? this.marksObtained,
      isAbsent: isAbsent ?? this.isAbsent,
      remarks: remarks ?? this.remarks,
      enteredBy: enteredBy ?? this.enteredBy,
    );
  }

  static int compareRollNumber(ExamMark a, ExamMark b) {
    final cleanA = (a.rollNumber ?? '').trim();
    final cleanB = (b.rollNumber ?? '').trim();

    if (cleanA.isNotEmpty && cleanB.isNotEmpty) {
      final numA = int.tryParse(cleanA);
      final numB = int.tryParse(cleanB);
      if (numA != null && numB != null) {
        if (numA != numB) return numA.compareTo(numB);
      } else {
        final cmp = cleanA.compareTo(cleanB);
        if (cmp != 0) return cmp;
      }
    } else if (cleanA.isNotEmpty) {
      return -1;
    } else if (cleanB.isNotEmpty) {
      return 1;
    }

    final grA = (a.registrationNumber ?? '').trim();
    final grB = (b.registrationNumber ?? '').trim();
    final numGrA = int.tryParse(grA.replaceAll(RegExp(r'\D'), ''));
    final numGrB = int.tryParse(grB.replaceAll(RegExp(r'\D'), ''));
    if (numGrA != null && numGrB != null && numGrA != numGrB) {
      return numGrA.compareTo(numGrB);
    }
    return grA.compareTo(grB);
  }
}

