import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/database_helper.dart';
import '../models/attendance_models.dart';

class AttendanceRepository {
  final ApiClient _apiClient;

  AttendanceRepository(this._apiClient);

  Future<List<StudentAttendance>> getStudentAttendance({
    required String className,
    required String date,
    String? shiftId,
  }) async {
    final queryParams = {'class_name': className, 'date': date};
    if (shiftId != null && shiftId.isNotEmpty) {
      queryParams['shift_id'] = shiftId;
    }
    final response = await _apiClient.get(
      '/attendance/students',
      queryParams: queryParams,
    );
    final data = response.data as List<dynamic>;
    return data.map((json) => StudentAttendance.fromJson(json)).toList();
  }

  Future<void> saveStudentAttendance({
    required String className,
    required String date,
    required List<StudentAttendance> attendanceList,
    String? shiftId,
    String? shiftName,
  }) async {
    await _apiClient.post(
      '/attendance/students',
      data: {
        'class_name': className,
        'date': date,
        if (shiftId != null && shiftId.isNotEmpty) 'shift_id': shiftId,
        if (shiftName != null && shiftName.isNotEmpty) 'shift_name': shiftName,
        'attendanceList': attendanceList.map((item) => item.toJson()).toList(),
      },
    );

    // Cache to local SQLite attendance table
    try {
      final db = await DatabaseHelper().database;
      for (final s in attendanceList) {
        final sId = s.shiftId.isNotEmpty ? s.shiftId : (shiftId ?? '');
        final sName = s.shiftName.isNotEmpty ? s.shiftName : (shiftName ?? '');
        if (s.status == null || s.status!.isEmpty || s.status == 'unmarked' || s.status == 'reset') {
          await db.delete(
            'attendance',
            where: 'student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = \'\'))',
            whereArgs: [s.id, date, sId, sId],
          );
        } else {
          await db.rawInsert('''
            INSERT OR REPLACE INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method, shift_id, shift_name)
            VALUES (
              COALESCE((SELECT id FROM attendance WHERE student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = ''))), ?),
              ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
          ''', [
            s.id, date, sId, sId, 'att_${s.id}_${date}_$sId',
            s.id, date, s.status, s.remarks, s.checkInTime, s.checkOutTime, s.verificationMethod, sId, sName
          ]);
        }
      }
    } catch (_) {}
  }

  Future<List<StaffAttendance>> getStaffAttendance({
    required String date,
  }) async {
    final response = await _apiClient.get(
      '/attendance/staff',
      queryParams: {'date': date},
    );
    final data = response.data as List<dynamic>;
    return data.map((json) => StaffAttendance.fromJson(json)).toList();
  }

  Future<void> saveStaffAttendance({
    required String date,
    required List<StaffAttendance> attendanceList,
  }) async {
    await _apiClient.post(
      '/attendance/staff',
      data: {
        'date': date,
        'attendanceList': attendanceList.map((item) => item.toJson()).toList(),
      },
    );
  }

  Future<Map<String, dynamic>> scanAttendance(String code) async {
    final response = await _apiClient.post(
      '/attendance/scan',
      data: {'code': code},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> saveSingleStudentAttendance({
    required String studentId,
    required String date,
    required String status,
    String? remarks,
    String? checkInTime,
    String? checkOutTime,
    String verificationMethod = 'Manual',
    String? shiftId,
    String? shiftName,
  }) async {
    final sId = shiftId ?? '';
    final sName = shiftName ?? '';
    try {
      await _apiClient.post(
        '/attendance/students/auto-save',
        data: {
          'student_id': studentId,
          'date': date,
          'status': status,
          'remarks': remarks ?? '',
          'check_in_time': checkInTime ?? '',
          'check_out_time': checkOutTime ?? '',
          'verification_method': verificationMethod,
          'shift_id': sId,
          'shift_name': sName,
        },
      );
    } catch (_) {}

    // Cache to SQLite
    try {
      final db = await DatabaseHelper().database;
      if (status.isEmpty || status == 'unmarked' || status == 'reset') {
        await db.delete(
          'attendance',
          where: 'student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = \'\'))',
          whereArgs: [studentId, date, sId, sId],
        );
      } else {
        await db.rawInsert('''
          INSERT OR REPLACE INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method, shift_id, shift_name)
          VALUES (
            COALESCE((SELECT id FROM attendance WHERE student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = ''))), ?),
            ?, ?, ?, ?, ?, ?, ?, ?, ?
          )
        ''', [
          studentId, date, sId, sId, 'att_${studentId}_${date}_$sId',
          studentId, date, status, remarks ?? '', checkInTime ?? '', checkOutTime ?? '', verificationMethod, sId, sName,
        ]);
      }
    } catch (_) {}
  }

  // ─── Period-Wise Attendance Methods ────────────────────────────────
  Future<List<PeriodAttendanceRecord>> getPeriodAttendance({
    String? classId,
    String? className,
    required String date,
    required int periodNumber,
  }) async {
    try {
      final response = await _apiClient.get(
        '/attendance/periods',
        queryParams: {
          if (classId != null && classId.isNotEmpty) 'class_id': classId,
          if (className != null && className.isNotEmpty) 'class_name': className,
          'date': date,
          'period_number': periodNumber.toString(),
        },
      );
      final data = response.data as List<dynamic>;
      return data.map((j) => PeriodAttendanceRecord.fromJson(j)).toList();
    } catch (_) {
      try {
        final db = await DatabaseHelper().database;
        final rows = await db.rawQuery('''
          SELECT * FROM period_attendance 
          WHERE date = ? AND period_number = ?
          ${classId != null && classId.isNotEmpty ? 'AND class_id = ?' : ''}
        ''', [date, periodNumber, if (classId != null && classId.isNotEmpty) classId]);
        return rows.map((j) => PeriodAttendanceRecord.fromJson(j)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> saveSinglePeriodAttendance({
    required String studentId,
    required String classId,
    String? periodId,
    required int periodNumber,
    required String date,
    required String status,
    String? time,
    String? remarks,
  }) async {
    try {
      await _apiClient.post(
        '/attendance/periods/auto-save',
        data: {
          'student_id': studentId,
          'class_id': classId,
          'period_id': periodId ?? '',
          'period_number': periodNumber,
          'date': date,
          'status': status,
          'time': time ?? '',
          'remarks': remarks ?? '',
        },
      );
    } catch (_) {}

    // Cache to SQLite
    try {
      final db = await DatabaseHelper().database;
      await db.rawInsert('''
        INSERT OR REPLACE INTO period_attendance (id, student_id, class_id, period_id, period_number, date, status, time, remarks)
        VALUES (
          COALESCE((SELECT id FROM period_attendance WHERE student_id = ? AND date = ? AND period_number = ?), ?),
          ?, ?, ?, ?, ?, ?, ?, ?
        )
      ''', [
        studentId, date, periodNumber, 'patt_${studentId}_${date}_$periodNumber',
        studentId, classId, periodId ?? '', periodNumber, date, status, time ?? '', remarks ?? ''
      ]);

      // Auto-Bridge to Daily Madarsa Shift Attendance in SQLite:
      // If student was present/late in period, ensure daily attendance record exists with check-in/out
      if (status == 'Present' || status == 'Late') {
        final effectiveTime = time ?? '';
        final dailyRows = await db.rawQuery(
          'SELECT id, check_in_time, check_out_time, remarks FROM attendance WHERE student_id = ? AND date = ?',
          [studentId, date],
        );
        if (dailyRows.isEmpty) {
          await db.rawInsert('''
            INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''', [
            'att_${studentId}_$date', studentId, date, status,
            'Auto-bridged from Period $periodNumber (Check-In)',
            effectiveTime, effectiveTime, 'Period Bridge'
          ]);
        } else {
          final row = dailyRows.first;
          final existingIn = row['check_in_time']?.toString() ?? '';
          final existingOut = row['check_out_time']?.toString() ?? '';
          final existingRemarks = row['remarks']?.toString() ?? '';
          final attId = row['id'];

          final newIn = existingIn.isEmpty ? effectiveTime : existingIn;
          final bool shouldUpdateOut = existingOut.isEmpty || existingRemarks.contains('Period Bridge');
          final newOut = shouldUpdateOut ? effectiveTime : existingOut;
          final newRemarks = existingIn.isEmpty
              ? 'Auto-bridged from Period $periodNumber (Check-In)'
              : (shouldUpdateOut ? 'Auto-bridged from Period $periodNumber (Latest Period Scan)' : existingRemarks);

          if (newIn != existingIn || newOut != existingOut) {
            await db.rawUpdate('''
              UPDATE attendance 
              SET check_in_time = ?, check_out_time = ?, remarks = ?, verification_method = COALESCE(verification_method, 'Period Bridge')
              WHERE id = ?
            ''', [newIn, newOut, newRemarks, attId]);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> bulkPeriodAttendance({
    required String classId,
    String? periodId,
    required int periodNumber,
    required String date,
    required String status,
    required List<String> studentIds,
  }) async {
    await _apiClient.post(
      '/attendance/periods/bulk',
      data: {
        'class_id': classId,
        'period_id': periodId ?? '',
        'period_number': periodNumber,
        'date': date,
        'status': status,
        'student_ids': studentIds,
      },
    );

    // Cache to SQLite
    try {
      final db = await DatabaseHelper().database;
      for (final sId in studentIds) {
        await db.rawInsert('''
          INSERT OR REPLACE INTO period_attendance (id, student_id, class_id, period_id, period_number, date, status, time)
          VALUES (
            COALESCE((SELECT id FROM period_attendance WHERE student_id = ? AND date = ? AND period_number = ?), ?),
            ?, ?, ?, ?, ?, ?, ?
          )
        ''', [
          sId, date, periodNumber, 'patt_${sId}_${date}_$periodNumber',
          sId, classId, periodId ?? '', periodNumber, date, status, ''
        ]);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> biometricScan({
    required String studentId,
    required String biometricType,
    String deviceMode = 'mobile',
  }) async {
    final response = await _apiClient.post(
      '/attendance/biometric/scan',
      data: {
        'student_id': studentId,
        'biometric_type': biometricType,
        'device_mode': deviceMode,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> enrollStudentBiometric({
    required String studentId,
    required String biometricType,
    required String templateData,
    String? photoPath,
  }) async {
    // 1. Always update local SQLite so offline or local enrollment is immediately saved
    try {
      final db = await DatabaseHelper().database;
      if (biometricType == 'Face') {
        if (photoPath != null && photoPath.isNotEmpty) {
          await db.rawUpdate(
            'UPDATE students SET face_data = ?, photo_path = ?, biometric_enrolled_at = CURRENT_TIMESTAMP WHERE id = ?',
            [templateData, photoPath, studentId],
          );
        } else {
          await db.rawUpdate(
            'UPDATE students SET face_data = ?, biometric_enrolled_at = CURRENT_TIMESTAMP WHERE id = ?',
            [templateData, studentId],
          );
        }
      } else if (biometricType == 'Fingerprint') {
        await db.rawUpdate(
          'UPDATE students SET fingerprint_data = ?, biometric_enrolled_at = CURRENT_TIMESTAMP WHERE id = ?',
          [templateData, studentId],
        );
      }
    } catch (e) {
      debugPrint('Local SQLite enrollment update error: $e');
    }

    // 2. Sync to backend API if reachable
    try {
      final payload = <String, dynamic>{
        'student_id': studentId,
        'biometric_type': biometricType,
        'template_data': templateData,
      };
      if (photoPath != null && photoPath.isNotEmpty) {
        payload['photo_path'] = photoPath;
      }
      await _apiClient.post(
        '/attendance/biometric/enroll',
        data: payload,
      );
    } catch (e) {
      debugPrint('Remote biometric enrollment sync warning: $e');
    }
  }

  /// Clears biometric enrolled data (face / fingerprint) for a student from local SQLite and backend
  Future<void> clearStudentBiometric({
    required String studentId,
    required String biometricType, // 'Face', 'Fingerprint', or 'Both'
  }) async {
    // 1. Update local SQLite database
    try {
      final db = await DatabaseHelper().database;
      if (biometricType.toLowerCase().contains('face')) {
        await db.rawUpdate(
          'UPDATE students SET face_data = NULL, photo_path = NULL WHERE id = ?',
          [studentId],
        );
      } else if (biometricType.toLowerCase().contains('finger')) {
        await db.rawUpdate(
          'UPDATE students SET fingerprint_data = NULL WHERE id = ?',
          [studentId],
        );
      } else {
        await db.rawUpdate(
          'UPDATE students SET face_data = NULL, photo_path = NULL, fingerprint_data = NULL WHERE id = ?',
          [studentId],
        );
      }
    } catch (e) {
      debugPrint('Local SQLite clear biometric error: $e');
    }

    // 2. Sync deletion to backend API
    try {
      await _apiClient.post(
        '/attendance/biometric/clear',
        data: {
          'student_id': studentId,
          'biometric_type': biometricType,
        },
      );
    } catch (e) {
      debugPrint('Remote biometric clear sync warning: $e');
    }
  }
}


