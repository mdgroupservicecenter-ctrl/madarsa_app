import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/storage/database_helper.dart';
import '../models/student_model.dart';
import '../models/student_academic_history_model.dart';

class StudentRepository {
  final ApiClient _apiClient;

  StudentRepository(this._apiClient);

  Future<List<Student>> getAllStudents() async {
    try {
      final response = await _apiClient.get('/students');
      return (response.data as List)
          .map((json) => Student.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to load students: $e');
    }
  }

  Future<List<Student>> searchStudents(
    String query, {
    int? minAge,
    int? maxAge,
    String? gender,
    String? className,
    bool excludeAllocated = false,
  }) async {
    try {
      final Map<String, String> params = {'q': query};
      if (minAge != null) params['min_age'] = minAge.toString();
      if (maxAge != null) params['max_age'] = maxAge.toString();
      if (gender != null && gender.isNotEmpty) params['gender'] = gender;
      if (className != null && className.isNotEmpty) params['class_name'] = className;
      if (excludeAllocated) params['exclude_allocated'] = 'true';

      final response = await _apiClient.get(
        '/students/search',
        queryParams: params,
      );
      return (response.data as List)
          .map((json) => Student.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Failed to search students: $e');
    }
  }

  Future<Student> getStudentById(String id) async {
    try {
      final response = await _apiClient.get('/students/$id');
      return Student.fromJson(response.data);
    } catch (e) {
      try {
        final db = await DatabaseHelper().database;
        final list = await db.query('students', where: 'id = ?', whereArgs: [id]);
        if (list.isNotEmpty) {
          return Student.fromJson(Map<String, dynamic>.from(list.first));
        }
      } catch (_) {}
      throw Exception('Failed to load student details: $e');
    }
  }

  Future<Student> getStudentByGRNo(String grNo) async {
    try {
      final response = await _apiClient.get('/students/gr/$grNo');
      return Student.fromJson(response.data);
    } catch (e) {
      try {
        final db = await DatabaseHelper().database;
        final list = await db.query('students', where: 'gr_no = ?', whereArgs: [grNo]);
        if (list.isNotEmpty) {
          return Student.fromJson(Map<String, dynamic>.from(list.first));
        }
      } catch (_) {}
      throw Exception('Failed to load student by GR.NO: $e');
    }
  }

  Future<String> getNextGRNo() async {
    try {
      final response = await _apiClient.get('/students/next-gr');
      return response.data['gr_no'];
    } catch (e) {
      throw Exception('Failed to get next GR.NO: $e');
    }
  }

  Future<Map<String, dynamic>> getAgeCalculation(
    String dob, {
    String? date,
  }) async {
    try {
      final response = await _apiClient.get(
        '/students/age-calc',
        queryParams: {'dob': dob, if (date != null) 'date': date},
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to calculate age: $e');
    }
  }

  Future<void> createStudent(Student student) async {
    try {
      final res = await _apiClient.post('/students', data: student.toJson());
      if (res.data is Map<String, dynamic> && res.data['data'] is Map<String, dynamic>) {
        await FirebaseService.syncStudent(Map<String, dynamic>.from(res.data['data']));
      }
    } catch (e) {
      throw Exception('Failed to create student: $e');
    }
  }

  Future<void> updateStudent(Student student) async {
    try {
      final res = await _apiClient.put('/students/${student.id}', data: student.toJson());
      if (res.data is Map<String, dynamic> && res.data['data'] is Map<String, dynamic>) {
        await FirebaseService.syncStudent(Map<String, dynamic>.from(res.data['data']));
      } else {
        await FirebaseService.syncStudent(student.toJson());
      }
    } catch (e) {
      throw Exception('Failed to update student: $e');
    }
  }

  Future<void> deleteStudent(String id) async {
    try {
      await _apiClient.delete('/students/$id');
      await FirebaseService.recordDeletionAndSync('students', id);
    } catch (e) {
      throw Exception('Failed to delete student: $e');
    }
  }

  Future<void> uploadDocument(
    String studentId,
    String documentName,
    String filePath,
  ) async {
    try {
      FormData formData = FormData.fromMap({
        'document_name': documentName,
        'document': await MultipartFile.fromFile(filePath),
      });

      await _apiClient.post('/students/$studentId/documents', data: formData);
      try {
        final s = await getStudentById(studentId);
        await FirebaseService.syncStudent(s.toJson());
      } catch (_) {}
    } catch (e) {
      throw Exception('Failed to upload document: $e');
    }
  }

  Future<void> deleteDocument(String studentId, String documentId) async {
    try {
      await _apiClient.delete('/students/$studentId/documents/$documentId');
      try {
        final s = await getStudentById(studentId);
        await FirebaseService.syncStudent(s.toJson());
      } catch (_) {}
    } catch (e) {
      throw Exception('Failed to delete document: $e');
    }
  }

  Future<void> bulkAssignCategory(List<String> studentIds, String category) async {
    try {
      await _apiClient.post('/students/bulk-assign-category', data: {
        'studentIds': studentIds,
        'category': category,
      });
      for (final id in studentIds) {
        try {
          final s = await getStudentById(id);
          await FirebaseService.syncStudent(s.toJson());
        } catch (_) {}
      }
    } catch (e) {
      throw Exception('Failed to bulk assign category: $e');
    }
  }

  Future<void> bulkAssignDivision(
    List<String> studentIds,
    String division, {
    String? subDepartmentId,
    String? subDepartmentName,
  }) async {
    try {
      await _apiClient.post('/students/bulk-assign-division', data: {
        'studentIds': studentIds,
        'division': division,
        if (subDepartmentId != null) 'subDepartmentId': subDepartmentId,
        if (subDepartmentName != null) 'subDepartmentName': subDepartmentName,
      });
      for (final id in studentIds) {
        try {
          final s = await getStudentById(id);
          await FirebaseService.syncStudent(s.toJson());
        } catch (_) {}
      }
    } catch (e) {
      throw Exception('Failed to bulk assign division: $e');
    }
  }

  Future<void> bulkDeleteStudents(List<String> studentIds) async {
    try {
      await _apiClient.post('/students/bulk-delete', data: {
        'studentIds': studentIds,
      });
      for (final id in studentIds) {
        await FirebaseService.recordDeletionAndSync('students', id);
      }
    } catch (e) {
      throw Exception('Failed to bulk delete students: $e');
    }
  }

  Future<void> bulkAssignRollNumbers(
    List<Map<String, String>> rollNumbers, {
    String? subDepartmentId,
    String? subDepartmentName,
  }) async {
    try {
      await _apiClient.post('/students/bulk-assign-roll-numbers', data: {
        'rollNumbers': rollNumbers,
        if (subDepartmentId != null) 'subDepartmentId': subDepartmentId,
        if (subDepartmentName != null) 'subDepartmentName': subDepartmentName,
      });
      for (final item in rollNumbers) {
        final id = item['studentId'];
        if (id != null && id.isNotEmpty) {
          try {
            final s = await getStudentById(id);
            await FirebaseService.syncStudent(s.toJson());
          } catch (_) {}
        }
      }
    } catch (e) {
      throw Exception('Failed to assign roll numbers: $e');
    }
  }

  Future<void> bulkAssignStatus(List<String> studentIds, String status) async {
    try {
      await _apiClient.post('/students/bulk-assign-status', data: {
        'studentIds': studentIds,
        'status': status,
      });
      for (final id in studentIds) {
        try {
          final s = await getStudentById(id);
          await FirebaseService.syncStudent(s.toJson());
        } catch (_) {}
      }
    } catch (e) {
      throw Exception('Failed to bulk assign status: $e');
    }
  }

  // ─── Academic History & Promotion Methods ───────────────────

  Future<List<StudentAcademicHistory>> getStudentAcademicHistory(String studentId) async {
    final list = <StudentAcademicHistory>[];

    // 1. Local SQLite Database
    try {
      final dbRows = await DatabaseHelper().getStudentAcademicHistory(studentId);
      for (final r in dbRows) {
        list.add(StudentAcademicHistory.fromJson(r));
      }
    } catch (_) {}

    // 2. Fallback to API if empty
    if (list.isEmpty) {
      try {
        final res = await _apiClient.get('/students/$studentId/academic-history');
        if (res.data != null && res.data is List) {
          for (final item in (res.data as List)) {
            final entry = StudentAcademicHistory.fromJson(Map<String, dynamic>.from(item));
            list.add(entry);
            try {
              await DatabaseHelper().insertAcademicHistory(entry.toJson());
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    // 3. Fallback to Firebase Firestore Cloud if still empty
    if (list.isEmpty) {
      try {
        final cloudItems = await FirebaseService.fetchStudentAcademicHistoryFromCloud(studentId);
        for (final item in cloudItems) {
          final entry = StudentAcademicHistory.fromJson(item);
          list.add(entry);
          try {
            await DatabaseHelper().insertAcademicHistory(entry.toJson());
          } catch (_) {}
        }
      } catch (_) {}
    }

    return list;
  }

  Future<void> recordAcademicPromotion({
    required Student student,
    required String academicYear,
    String? academicYearHijri,
    required String targetClass,
    String? targetDepartmentId,
    String? targetDepartmentName,
    String? targetDivision,
    String? targetRollNumber,
    String? status, // 'Promoted', 'Repeated', 'Farigh', 'Khariz', 'Active', 'Archived'
    String? remarks,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final historyId = 'hist_${student.id}_${DateTime.now().millisecondsSinceEpoch}';

    // Auto-resolve target department from Progression Series if not explicitly given
    String? resolvedDeptName = targetDepartmentName;
    String? resolvedDeptId = targetDepartmentId;
    if ((resolvedDeptName == null || resolvedDeptName.isEmpty) && status != 'Repeated') {
      try {
        final prog = await DatabaseHelper().getNextProgressionForStudent(
          currentClass: student.className,
          currentDepartment: student.departmentName,
        );
        if (prog['next_class'] == targetClass && prog['next_department'] != null && prog['next_department']!.isNotEmpty) {
          resolvedDeptName = prog['next_department'];
        }
      } catch (_) {}
    }

    if (resolvedDeptName != null && resolvedDeptName.isNotEmpty && (resolvedDeptId == null || resolvedDeptId.isEmpty)) {
      try {
        final db = await DatabaseHelper().database;
        final deptRow = await db.query(
          'departments',
          columns: ['id'],
          where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
          whereArgs: [resolvedDeptName],
          limit: 1,
        );
        if (deptRow.isNotEmpty) {
          resolvedDeptId = deptRow.first['id']?.toString();
        }
      } catch (_) {}
    }

    // 1. Calculate historical attendance & exam marks for the student
    final summary = await DatabaseHelper().calculateStudentAcademicSummary(
      student.id,
      academicYear: academicYear,
      classId: student.className,
      fallbackMonthlyFees: student.monthlyFees,
      fallbackAdmissionFee: student.admissionFee,
      fallbackBookFee: student.bookFee,
      fallbackFeeStructure: student.feeStructure,
    );

    final history = StudentAcademicHistory(
      id: historyId,
      studentId: student.id,
      academicYear: academicYear,
      academicYearHijri: academicYearHijri,
      classId: student.className,
      className: student.className ?? 'Class 1',
      departmentId: student.departmentId,
      departmentName: student.departmentName,
      division: student.division,
      rollNumber: student.rollNumber,
      totalAttendanceDays: (summary['total_attendance_days'] as num?)?.toInt() ?? 0,
      presentDays: (summary['present_days'] as num?)?.toInt() ?? 0,
      attendancePercentage: (summary['attendance_percentage'] as num?)?.toDouble() ?? 0.0,
      totalMarks: (summary['total_marks'] as num?)?.toDouble() ?? 0.0,
      obtainedMarks: (summary['obtained_marks'] as num?)?.toDouble() ?? 0.0,
      examPercentage: (summary['exam_percentage'] as num?)?.toDouble() ?? 0.0,
      resultGrade: summary['result_grade']?.toString(),
      status: status ?? (targetClass.toLowerCase() == 'farigh' ? 'Farigh' : 'Promoted'),
      remarks: remarks ?? 'Promoted from ${student.className ?? "previous class"} to $targetClass',
      promotedAt: nowIso,
      createdAt: nowIso,
      booksMarksJson: summary['books_marks_json']?.toString(),
      feeTotal: (summary['fee_total'] as num?)?.toDouble() ?? 0.0,
      feePaid: (summary['fee_paid'] as num?)?.toDouble() ?? 0.0,
      feePending: (summary['fee_pending'] as num?)?.toDouble() ?? 0.0,
      perStudentExpense: (summary['per_student_expense'] as num?)?.toDouble() ?? 0.0,
      metadataJson: jsonEncode({
        'attendance_records': summary['attendance_records'] ?? [],
        'attendance_monthly_summary': summary['attendance_monthly_summary'] ?? [],
        'fee_payments': summary['fee_payments'] ?? [],
        'fee_breakdown': summary['fee_breakdown'] ?? [],
      }),
    );

    // 2. Save history entry to local SQLite
    await DatabaseHelper().insertAcademicHistory(history.toJson());

    // 3. Update student's current class, department, division, and status
    final updatedStudentMap = student.toJson();
    if (status == 'Farigh') {
      updatedStudentMap['student_status'] = 'Farigh';
      updatedStudentMap['is_active'] = 1;
    } else if (status == 'Active' || status == 'Archived') {
      // Snapshot only, preserve class/department
    } else {
      updatedStudentMap['class_name'] = targetClass;
      if (resolvedDeptName != null && resolvedDeptName.isNotEmpty) {
        updatedStudentMap['department_name'] = resolvedDeptName;
      }
      if (resolvedDeptId != null && resolvedDeptId.isNotEmpty) {
        updatedStudentMap['department_id'] = resolvedDeptId;
      }
      if (targetDivision != null && targetDivision.isNotEmpty) {
        updatedStudentMap['division'] = targetDivision;
      }
      if (targetRollNumber != null && targetRollNumber.isNotEmpty) {
        updatedStudentMap['roll_number'] = targetRollNumber;
      }
      if (status != null && status.isNotEmpty) {
        updatedStudentMap['student_status'] = status;
      }
    }
    updatedStudentMap['updated_at'] = nowIso;

    // 4. Update in local SQLite
    try {
      final db = await DatabaseHelper().database;
      final updateFields = <String, dynamic>{
        'updated_at': nowIso,
      };
      if (status == 'Farigh') {
        updateFields['student_status'] = 'Farigh';
      } else if (status != 'Active' && status != 'Archived') {
        updateFields['class_name'] = targetClass;
        if (resolvedDeptName != null && resolvedDeptName.isNotEmpty) {
          updateFields['department_name'] = resolvedDeptName;
        }
        if (resolvedDeptId != null && resolvedDeptId.isNotEmpty) {
          updateFields['department_id'] = resolvedDeptId;
        }
        if (targetDivision != null && targetDivision.isNotEmpty) {
          updateFields['division'] = targetDivision;
        }
        if (targetRollNumber != null && targetRollNumber.isNotEmpty) {
          updateFields['roll_number'] = targetRollNumber;
        }
        if (status != null && status.isNotEmpty) {
          updateFields['student_status'] = status;
        }
      }

      await db.update(
        'students',
        updateFields,
        where: 'id = ?',
        whereArgs: [student.id],
      );
    } catch (_) {}

    // 5. Sync to Online REST API Server
    try {
      await _apiClient.put('/students/${student.id}', data: updatedStudentMap);
    } catch (_) {}

    try {
      await _apiClient.post('/students/${student.id}/academic-history', data: history.toJson());
    } catch (_) {}

    // 6. Sync to Online Firebase Firestore Cloud
    try {
      await FirebaseService.syncStudent(updatedStudentMap);
    } catch (_) {}

    try {
      await FirebaseService.syncStudentAcademicHistory(history.toJson());
    } catch (_) {}
  }

  Future<void> bulkPromoteStudents({
    required List<Student> students,
    required String academicYear,
    String? academicYearHijri,
    required String targetClass,
    String? targetDepartmentId,
    String? targetDepartmentName,
    String? targetDivision,
    String? status,
  }) async {
    for (final s in students) {
      await recordAcademicPromotion(
        student: s,
        academicYear: academicYear,
        academicYearHijri: academicYearHijri,
        targetClass: targetClass,
        targetDepartmentId: targetDepartmentId,
        targetDepartmentName: targetDepartmentName,
        targetDivision: targetDivision,
        status: status,
      );
    }

    try {
      await _apiClient.post('/students/bulk-promote', data: {
        'studentIds': students.map((s) => s.id).toList(),
        'academicYear': academicYear,
        'academicYearHijri': academicYearHijri,
        'targetClass': targetClass,
        'targetDepartmentId': targetDepartmentId,
        'targetDepartmentName': targetDepartmentName,
        'targetDivision': targetDivision,
        'status': status ?? 'Promoted',
      });
    } catch (_) {}
  }

  Future<void> deleteAcademicHistory(String historyId) async {
    await DatabaseHelper().deleteAcademicHistory(historyId);
    try {
      await _apiClient.delete('/students/academic-history/$historyId');
    } catch (_) {}
    try {
      await FirebaseService.deleteStudentAcademicHistoryFromCloud(historyId);
    } catch (_) {}
  }
}
