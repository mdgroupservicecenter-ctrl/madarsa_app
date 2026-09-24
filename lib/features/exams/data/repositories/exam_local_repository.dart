import '../../../../core/storage/database_helper.dart';
import '../models/exam_models.dart';
import '../algorithm/seating_models.dart';

class ExamLocalRepository {
  final DatabaseHelper _db = DatabaseHelper();

  // ═══════════════════════════════════════════════════════════════
  //  EXAMS
  // ═══════════════════════════════════════════════════════════════

  Future<List<Exam>> getExams() async {
    final db = await _db.database;
    final rows = await db.query('exams', orderBy: 'created_at DESC');
    return rows.map((r) => Exam.fromJson(r)).toList();
  }

  Future<int> createExam(Exam exam) async {
    final db = await _db.database;
    final id = exam.id ?? DateTime.now().millisecondsSinceEpoch;
    final map = exam.toJson();
    map['id'] = id.toString();
    await db.insert('exams', map);
    return id;
  }

  Future<void> updateExam(Exam exam) async {
    final db = await _db.database;
    final map = exam.toJson();
    await db.update('exams', map, where: 'id = ? OR id = ?', whereArgs: [exam.id, exam.id.toString()]);
  }

  Future<void> deleteExam(int id) async {
    final db = await _db.database;
    await db.delete('exams', where: 'id = ? OR id = ?', whereArgs: [id, id.toString()]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  EXAM SCHEDULES
  // ═══════════════════════════════════════════════════════════════

  Future<List<ExamSchedule>> getSchedules(int examId) async {
    final db = await _db.database;
    final rows = await db.query('exam_schedules',
        where: 'exam_id = ? OR exam_id = ?', whereArgs: [examId, examId.toString()], orderBy: 'exam_date, start_time');
    return rows.map((r) => ExamSchedule.fromJson(r)).toList();
  }

  Future<List<ExamSchedule>> getSchedulesByDate(int examId, String date) async {
    final db = await _db.database;
    final rows = await db.query('exam_schedules',
        where: 'exam_id = ? AND exam_date = ?',
        whereArgs: [examId, date],
        orderBy: 'start_time');
    return rows.map((r) => ExamSchedule.fromJson(r)).toList();
  }

  Future<void> _ensureScheduleColumns(dynamic db) async {
    try {
      await db.execute('ALTER TABLE exam_schedules ADD COLUMN department_id TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE exam_schedules ADD COLUMN department_name TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE exam_schedules ADD COLUMN parent_department_name TEXT');
    } catch (_) {}
  }

  Future<int> createSchedule(ExamSchedule schedule) async {
    final db = await _db.database;
    final id = schedule.id ?? DateTime.now().millisecondsSinceEpoch;
    final map = schedule.toJson();
    map['id'] = id.toString();
    map['exam_id'] = schedule.examId.toString();
    try {
      await db.insert('exam_schedules', map);
      return id;
    } catch (e) {
      await _ensureScheduleColumns(db);
      map.remove('student_count');
      try {
        await db.insert('exam_schedules', map);
        return id;
      } catch (_) {
        map.remove('department_id');
        map.remove('department_name');
        map.remove('parent_department_name');
        await db.insert('exam_schedules', map);
        return id;
      }
    }
  }

  Future<void> updateSchedule(ExamSchedule schedule) async {
    final db = await _db.database;
    final map = schedule.toJson();
    map['exam_id'] = schedule.examId.toString();
    try {
      await db.update('exam_schedules', map,
          where: 'id = ? OR id = ?', whereArgs: [schedule.id, schedule.id.toString()]);
    } catch (e) {
      await _ensureScheduleColumns(db);
      map.remove('student_count');
      try {
        await db.update('exam_schedules', map,
            where: 'id = ? OR id = ?', whereArgs: [schedule.id, schedule.id.toString()]);
      } catch (_) {
        map.remove('department_id');
        map.remove('department_name');
        map.remove('parent_department_name');
        await db.update('exam_schedules', map,
            where: 'id = ? OR id = ?', whereArgs: [schedule.id, schedule.id.toString()]);
      }
    }
  }

  Future<void> deleteSchedule(int id) async {
    final db = await _db.database;
    await db.delete('exam_schedules', where: 'id = ? OR id = ?', whereArgs: [id, id.toString()]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  EXAM HALLS
  // ═══════════════════════════════════════════════════════════════

  Future<List<ExamHall>> getHalls() async {
    final db = await _db.database;
    final rows = await db.query('exam_halls', orderBy: 'name');
    return rows.map((r) => ExamHall.fromJson(r)).toList();
  }

  Future<int> createHall(ExamHall hall) async {
    final db = await _db.database;
    final id = hall.id ?? DateTime.now().millisecondsSinceEpoch;
    final map = hall.toJson();
    map['id'] = id.toString();
    await db.insert('exam_halls', map);
    return id;
  }

  Future<void> updateHall(ExamHall hall) async {
    final db = await _db.database;
    await db.update('exam_halls', hall.toJson(), where: 'id = ?', whereArgs: [hall.id]);
  }

  Future<void> deleteHall(int id) async {
    final db = await _db.database;
    await db.delete('exam_halls', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEATING ARRANGEMENTS
  // ═══════════════════════════════════════════════════════════════

  Future<List<SeatingArrangement>> getSeating(int examId, {int? hallId, String? sessionDate}) async {
    final db = await _db.database;
    String where = 'exam_id = ?';
    List<dynamic> args = [examId];
    if (hallId != null) {
      where += ' AND hall_id = ?';
      args.add(hallId);
    }
    if (sessionDate != null) {
      where += ' AND session_date = ?';
      args.add(sessionDate);
    }
    final rows = await db.query('seating_arrangements',
        where: where, whereArgs: args, orderBy: 'seat_number');
    return rows.map((r) => SeatingArrangement.fromJson(r)).toList();
  }

  Future<List<SeatingArrangement>> getSeatingForSession(int examId, String sessionDate, String? sessionTime) async {
    final db = await _db.database;
    String where = 'exam_id = ? AND session_date = ?';
    List<dynamic> args = [examId, sessionDate];
    if (sessionTime != null && sessionTime.trim().isNotEmpty) {
      where += ' AND session_time = ?';
      args.add(sessionTime.trim());
    }
    final rows = await db.query('seating_arrangements', where: where, whereArgs: args);
    return rows.map((r) => SeatingArrangement.fromJson(r)).toList();
  }

  Future<void> deleteHallSeatingForSession(int examId, int hallId, String sessionDate, String? sessionTime) async {
    final db = await _db.database;
    String where = 'exam_id = ? AND hall_id = ? AND session_date = ?';
    List<dynamic> args = [examId, hallId, sessionDate];
    if (sessionTime != null && sessionTime.trim().isNotEmpty) {
      where += ' AND session_time = ?';
      args.add(sessionTime.trim());
    }
    await db.delete('seating_arrangements', where: where, whereArgs: args);
    try {
      await db.delete('seat_history', where: 'exam_id = ? AND hall_id = ? AND session_date = ?', whereArgs: [examId, hallId, sessionDate]);
    } catch (_) {}
  }

  Future<void> saveSeatingBatch(List<SeatingArrangement> arrangements) async {
    final db = await _db.database;

    // Failsafe: Ensure roll_number column exists in table before batch insert
    try {
      await db.execute('ALTER TABLE seating_arrangements ADD COLUMN roll_number TEXT');
    } catch (_) {}

    final batch = db.batch();
    for (final a in arrangements) {
      batch.insert('seating_arrangements', a.toJson());
    }
    try {
      await batch.commit(noResult: true);
    } catch (e) {
      // Fallback: If old schema without roll_number column persists, strip roll_number key and re-insert
      final fallbackBatch = db.batch();
      for (final a in arrangements) {
        final jsonMap = a.toJson();
        jsonMap.remove('roll_number');
        fallbackBatch.insert('seating_arrangements', jsonMap);
      }
      await fallbackBatch.commit(noResult: true);
    }
  }

  String _normalizeUrdu(String text) {
    return text
        .replaceAll('ں', 'ن')
        .replaceAll('آ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ى', 'ی')
        .replaceAll('ئ', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ہ', 'ه')
        .replaceAll('\u064B', '')
        .replaceAll('\u064C', '')
        .replaceAll('\u064D', '')
        .replaceAll('\u064E', '')
        .replaceAll('\u064F', '')
        .replaceAll('\u0650', '')
        .replaceAll('\u0651', '')
        .replaceAll('\u0652', '')
        .trim()
        .toLowerCase();
  }

  Future<void> clearSeating(int examId, {int? hallId, String? sessionDate, List<String>? bookIds, String? classId}) async {
    final db = await _db.database;

    String selectWhere = 'exam_id = ?';
    List<dynamic> selectArgs = [examId];
    if (hallId != null) {
      selectWhere += ' AND hall_id = ?';
      selectArgs.add(hallId);
    }

    final rows = await db.query('seating_arrangements', where: selectWhere, whereArgs: selectArgs);
    if (rows.isEmpty) return;

    final targetClassNorm = classId != null && classId.trim().isNotEmpty ? _normalizeUrdu(classId) : '';
    final targetBookNorms = bookIds != null && bookIds.isNotEmpty
        ? bookIds.map((b) => _normalizeUrdu(b)).where((b) => b.isNotEmpty).toList()
        : <String>[];

    final idsToDelete = <dynamic>[];

    for (final row in rows) {
      final rId = row['id'];
      final rClassId = _normalizeUrdu('${row['class_id'] ?? ''}');
      final rClassName = _normalizeUrdu('${row['class_name'] ?? ''}');
      final rBookId = _normalizeUrdu('${row['book_id'] ?? ''}');
      final rBookName = _normalizeUrdu('${row['book_name'] ?? ''}');

      // Class filter check (if classId provided)
      if (targetClassNorm.isNotEmpty) {
        final matchesClass = rClassId == targetClassNorm ||
            rClassName == targetClassNorm ||
            (rClassId.isNotEmpty && (rClassId.contains(targetClassNorm) || targetClassNorm.contains(rClassId))) ||
            (rClassName.isNotEmpty && (rClassName.contains(targetClassNorm) || targetClassNorm.contains(rClassName)));
        if (!matchesClass) continue;
      }

      // Book filter check (if bookIds provided)
      if (targetBookNorms.isNotEmpty) {
        final matchesBook = targetBookNorms.any((tb) =>
            tb == rBookId ||
            tb == rBookName ||
            (rBookId.isNotEmpty && (rBookId.contains(tb) || tb.contains(rBookId))) ||
            (rBookName.isNotEmpty && (rBookName.contains(tb) || tb.contains(rBookName)))
        );
        if (!matchesBook) continue;
      }

      if (rId != null) {
        idsToDelete.add(rId);
      }
    }

    if (idsToDelete.isNotEmpty) {
      final batch = db.batch();
      for (final id in idsToDelete) {
        batch.delete('seating_arrangements', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  SEAT HISTORY
  // ═══════════════════════════════════════════════════════════════

  Future<void> _ensureSeatHistoryTable(dynamic db) async {
    try {
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
          created_at TEXT DEFAULT (datetime('now'))
        )
      ''');
    } catch (_) {}
  }

  Future<List<SeatHistoryEntry>> getSeatHistory({
    required int hallId,
    List<String>? studentIds,
  }) async {
    final db = await _db.database;
    await _ensureSeatHistoryTable(db);
    String where = 'hall_id = ?';
    List<dynamic> args = [hallId];
    if (studentIds != null && studentIds.isNotEmpty) {
      final placeholders = List.filled(studentIds.length, '?').join(',');
      where += ' AND student_id IN ($placeholders)';
      args.addAll(studentIds);
    }
    try {
      final rows = await db.query('seat_history', where: where, whereArgs: args);
      return rows
          .map((r) => SeatHistoryEntry(
                studentId: '${r['student_id']}',
                bookId: '${r['book_id']}',
                hallId: int.tryParse('${r['hall_id']}') ?? 0,
                seatRow: int.tryParse('${r['seat_row']}') ?? 0,
                seatColumn: int.tryParse('${r['seat_column']}') ?? 0,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSeatHistory(List<SeatingArrangement> arrangements, int examId) async {
    final db = await _db.database;
    await _ensureSeatHistoryTable(db);
    try {
      final batch = db.batch();
      for (final a in arrangements) {
        batch.insert('seat_history', {
          'student_id': a.studentId,
          'book_id': a.bookId,
          'hall_id': a.hallId,
          'seat_row': a.seatRow,
          'seat_column': a.seatColumn,
          'exam_id': examId,
          'session_date': a.sessionDate,
        });
      }
      await batch.commit(noResult: true);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  //  MARKS
  // ═══════════════════════════════════════════════════════════════

  int _compareGrNo(String? aStr, String? bStr) {
    if (aStr == null || aStr.trim().isEmpty) return (bStr == null || bStr.trim().isEmpty) ? 0 : 1;
    if (bStr == null || bStr.trim().isEmpty) return -1;
    final cleanA = aStr.trim();
    final cleanB = bStr.trim();
    final numA = int.tryParse(cleanA.replaceAll(RegExp(r'\D'), ''));
    final numB = int.tryParse(cleanB.replaceAll(RegExp(r'\D'), ''));
    if (numA != null && numB != null && numA != numB) {
      return numA.compareTo(numB);
    }
    return cleanA.compareTo(cleanB);
  }

  int _compareRollNumber(String? rollA, String? rollB, String? grA, String? grB) {
    final cleanA = (rollA ?? '').trim();
    final cleanB = (rollB ?? '').trim();

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

    return _compareGrNo(grA, grB);
  }

  Future<List<ExamMark>> getMarks(int scheduleId) async {
    final db = await _db.database;
    final rows = await db.query('exam_marks',
        where: 'schedule_id = ?',
        whereArgs: [scheduleId]);
    final list = rows.map((r) => ExamMark.fromJson(r)).toList();
    list.sort((a, b) => _compareRollNumber(a.rollNumber, b.rollNumber, a.registrationNumber, b.registrationNumber));
    return list;
  }

  Future<List<ExamMark>> getMarksByExamAndStudent(int examId, String studentId) async {
    final db = await _db.database;
    final rows = await db.query('exam_marks',
        where: 'exam_id = ? AND student_id = ?', whereArgs: [examId, studentId]);
    return rows.map((r) => ExamMark.fromJson(r)).toList();
  }

  Future<List<ExamMark>> getAllMarksByExam(int examId) async {
    final db = await _db.database;
    final rows = await db.query('exam_marks',
        where: 'exam_id = ?',
        whereArgs: [examId]);
    final list = rows.map((r) => ExamMark.fromJson(r)).toList();
    list.sort((a, b) => _compareRollNumber(a.rollNumber, b.rollNumber, a.registrationNumber, b.registrationNumber));
    return list;
  }

  Future<void> saveMarksBatch(List<ExamMark> marks) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final m in marks) {
      if (m.id != null) {
        batch.update('exam_marks', m.toJson(), where: 'id = ?', whereArgs: [m.id]);
      } else {
        batch.insert('exam_marks', m.toJson());
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> initMarksForSchedule(int examId, int scheduleId, ExamSchedule schedule,
      List<Map<String, dynamic>> students) async {
    final db = await _db.database;
    final existing = await db.query('exam_marks',
        where: 'schedule_id = ?', whereArgs: [scheduleId], columns: ['student_id']);
    final existingIds = existing.map((r) => '${r['student_id']}').toSet();

    final sortedStudents = List<Map<String, dynamic>>.from(students);
    sortedStudents.sort((a, b) {
      final rollA = _extractRollNo(a, schedule.departmentId);
      final rollB = _extractRollNo(b, schedule.departmentId);
      final grA = (a['registration_number'] ?? a['gr_no'] ?? '').toString();
      final grB = (b['registration_number'] ?? b['gr_no'] ?? '').toString();
      return _compareRollNumber(rollA, rollB, grA, grB);
    });

    final batch = db.batch();
    for (final s in sortedStudents) {
      final sid = '${s['id']}';
      if (existingIds.contains(sid)) continue;

      final rollNo = _extractRollNo(s, schedule.departmentId);
      final division = _extractDivision(s, schedule.departmentId);

      batch.insert('exam_marks', {
        'exam_id': examId,
        'schedule_id': scheduleId,
        'student_id': sid,
        'student_name': s['full_name'] ?? s['name'] ?? '',
        'registration_number': s['registration_number'] ?? s['gr_no'] ?? '',
        'roll_number': rollNo,
        'division': division,
        'book_id': schedule.bookId,
        'book_name': schedule.bookName,
        'class_id': schedule.classId,
        'class_name': schedule.className,
        'max_marks': schedule.maxMarks,
        'marks_obtained': null,
        'is_absent': 0,
      });
    }
    await batch.commit(noResult: true);
  }

  String? _extractRollNo(Map<String, dynamic> s, String? targetDeptId) {
    final subDepts = s['sub_departments'] ?? s['subDepartments'];
    if (subDepts is List && subDepts.isNotEmpty) {
      if (targetDeptId != null && targetDeptId.trim().isNotEmpty) {
        for (final sd in subDepts) {
          if (sd is Map) {
            final sdId = '${sd['sub_department_id'] ?? sd['id'] ?? ''}'.trim();
            if (sdId == targetDeptId.trim()) {
              final r = sd['roll_number']?.toString() ?? sd['rollNumber']?.toString();
              if (r != null && r.trim().isNotEmpty) return r.trim();
            }
          }
        }
      }
      for (final sd in subDepts) {
        if (sd is Map) {
          final r = sd['roll_number']?.toString() ?? sd['rollNumber']?.toString();
          if (r != null && r.trim().isNotEmpty) return r.trim();
        }
      }
    }
    final direct = s['roll_number']?.toString() ?? s['rollNumber']?.toString() ?? s['roll_no']?.toString();
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    return null;
  }

  String? _extractDivision(Map<String, dynamic> s, String? targetDeptId) {
    final subDepts = s['sub_departments'] ?? s['subDepartments'];
    if (subDepts is List && subDepts.isNotEmpty) {
      if (targetDeptId != null && targetDeptId.trim().isNotEmpty) {
        for (final sd in subDepts) {
          if (sd is Map) {
            final sdId = '${sd['sub_department_id'] ?? sd['id'] ?? ''}'.trim();
            if (sdId == targetDeptId.trim()) {
              final d = sd['division']?.toString() ?? sd['section']?.toString();
              if (d != null && d.trim().isNotEmpty) return d.trim();
            }
          }
        }
      }
      for (final sd in subDepts) {
        if (sd is Map) {
          final d = sd['division']?.toString() ?? sd['section']?.toString();
          if (d != null && d.trim().isNotEmpty) return d.trim();
        }
      }
    }
    final direct = s['division']?.toString() ?? s['section']?.toString();
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  //  RESULT AGGREGATION
  // ═══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getStudentResults(int examId, String classId) async {
    final db = await _db.database;
    final isAll = classId.trim().toLowerCase() == 'all' || classId.trim().isEmpty;
    final marks = isAll
        ? await db.rawQuery('''
            SELECT em.*, 
                   COALESCE(NULLIF(em.book_name, ''), NULLIF(es.book_name, '')) as resolved_book_name
            FROM exam_marks em
            LEFT JOIN exam_schedules es ON em.schedule_id = es.id
            WHERE em.exam_id = ?
            ORDER BY em.student_name, COALESCE(NULLIF(em.book_name, ''), NULLIF(es.book_name, ''))
          ''', [examId])
        : await db.rawQuery('''
            SELECT em.*, 
                   COALESCE(NULLIF(em.book_name, ''), NULLIF(es.book_name, '')) as resolved_book_name
            FROM exam_marks em
            LEFT JOIN exam_schedules es ON em.schedule_id = es.id
            WHERE em.exam_id = ? AND em.class_id = ?
            ORDER BY em.student_name, COALESCE(NULLIF(em.book_name, ''), NULLIF(es.book_name, ''))
          ''', [examId, classId]);

    // Group by student
    final grouped = <String, List<ExamMark>>{};
    for (final row in marks) {
      final mapData = Map<String, dynamic>.from(row);
      if ((mapData['book_name'] == null || mapData['book_name'].toString().trim().isEmpty) &&
          mapData['resolved_book_name'] != null) {
        mapData['book_name'] = mapData['resolved_book_name'];
      }
      final m = ExamMark.fromJson(mapData);
      grouped.putIfAbsent(m.studentId, () => []).add(m);
    }

    final results = <Map<String, dynamic>>[];
    for (final entry in grouped.entries) {
      final studentMarks = entry.value;
      if (studentMarks.isEmpty) continue;

      double totalObtained = 0;
      int totalMax = 0;
      int absentCount = 0;

      for (final m in studentMarks) {
        totalMax += m.maxMarks;
        if (m.isAbsent) {
          absentCount++;
        } else {
          totalObtained += m.marksObtained ?? 0;
        }
      }

      final percentage = totalMax > 0 ? (totalObtained / totalMax) * 100 : 0.0;

      results.add({
        'student_id': entry.key,
        'student_name': studentMarks.first.studentName,
        'registration_number': studentMarks.first.registrationNumber,
        'class_name': studentMarks.first.className,
        'subjects': studentMarks,
        'total_obtained': totalObtained,
        'total_max': totalMax,
        'percentage': percentage,
        'absent_count': absentCount,
      });
    }

    // Calculate class-wise ranks handling ties (students with equal total marks / percentage get the same rank)
    final classGroups = <String, List<Map<String, dynamic>>>{};
    for (final r in results) {
      final cName = (r['class_name'] ?? '').toString();
      classGroups.putIfAbsent(cName, () => []).add(r);
    }

    for (final group in classGroups.values) {
      group.sort((a, b) {
        final obtA = ((a['total_obtained'] as num?) ?? 0).toDouble();
        final obtB = ((b['total_obtained'] as num?) ?? 0).toDouble();
        final cmpObt = obtB.compareTo(obtA);
        if (cmpObt != 0) return cmpObt;

        final pctA = ((a['percentage'] as num?) ?? 0).toDouble();
        final pctB = ((b['percentage'] as num?) ?? 0).toDouble();
        return pctB.compareTo(pctA);
      });

      for (int i = 0; i < group.length; i++) {
        if (i == 0) {
          group[i]['rank'] = 1;
        } else {
          final prev = group[i - 1];
          final curr = group[i];
          final prevObt = ((prev['total_obtained'] as num?) ?? 0).toDouble();
          final currObt = ((curr['total_obtained'] as num?) ?? 0).toDouble();
          final prevPct = ((prev['percentage'] as num?) ?? 0).toDouble();
          final currPct = ((curr['percentage'] as num?) ?? 0).toDouble();

          // Equal marks & percentage -> Same rank!
          if ((prevObt - currObt).abs() < 0.01 && (prevPct - currPct).abs() < 0.01) {
            curr['rank'] = prev['rank'];
          } else {
            curr['rank'] = (prev['rank'] as int) + 1;
          }
        }
      }
    }

    // Sort final results list by class name, then rank ascending
    results.sort((a, b) {
      final cA = (a['class_name'] ?? '').toString();
      final cB = (b['class_name'] ?? '').toString();
      final cmpClass = cA.compareTo(cB);
      if (cmpClass != 0) return cmpClass;
      final rA = (a['rank'] as int?) ?? 999999;
      final rB = (b['rank'] as int?) ?? 999999;
      return rA.compareTo(rB);
    });

    return results;
  }
}
