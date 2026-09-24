import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../data/models/attendance_models.dart';
import '../../data/repositories/attendance_repository.dart';

// ─── EVENTS ──────────────────────────────────────────────────────────────────
abstract class AttendanceEvent {}

class LoadStudentAttendance extends AttendanceEvent {
  final String className;
  final String date;
  final String? shiftId;
  LoadStudentAttendance({
    required this.className,
    required this.date,
    this.shiftId,
  });
}

class UpdateStudentStatus extends AttendanceEvent {
  final String studentId;
  final String? status;
  UpdateStudentStatus({required this.studentId, this.status});
}

class UpdateStudentRemarks extends AttendanceEvent {
  final String studentId;
  final String remarks;
  UpdateStudentRemarks({required this.studentId, required this.remarks});
}

class SaveStudentAttendanceData extends AttendanceEvent {
  final String className;
  final String date;
  final String? shiftId;
  final String? shiftName;
  SaveStudentAttendanceData({
    required this.className,
    required this.date,
    this.shiftId,
    this.shiftName,
  });
}

class UpdateStudentVerification extends AttendanceEvent {
  final String studentId;
  final String method;
  final String time;
  UpdateStudentVerification({
    required this.studentId,
    required this.method,
    required this.time,
  });
}

class BulkUpdateStudentStatus extends AttendanceEvent {
  final List<String> studentIds;
  final String status;
  final String date;
  final String? className;
  final bool autoSave;
  final String timeMode;
  final String? shiftId;
  final String? shiftName;
  BulkUpdateStudentStatus({
    required this.studentIds,
    required this.status,
    required this.date,
    this.className,
    this.autoSave = true,
    this.timeMode = 'both',
    this.shiftId,
    this.shiftName,
  });
}

class AutoSaveStudentStatus extends AttendanceEvent {
  final String studentId;
  final String status;
  final String date;
  final String? checkInTime;
  final String? checkOutTime;
  final String? remarks;
  final String verificationMethod;
  final String? shiftId;
  final String? shiftName;
  AutoSaveStudentStatus({
    required this.studentId,
    required this.status,
    required this.date,
    this.checkInTime,
    this.checkOutTime,
    this.remarks,
    this.verificationMethod = 'Manual',
    this.shiftId,
    this.shiftName,
  });
}

class LoadPeriodAttendance extends AttendanceEvent {
  final String className;
  final String date;
  final int periodNumber;
  LoadPeriodAttendance({
    required this.className,
    required this.date,
    required this.periodNumber,
  });
}

class SavePeriodAttendanceStatus extends AttendanceEvent {
  final String studentId;
  final String classId;
  final String? periodId;
  final int periodNumber;
  final String date;
  final String status;
  final String? time;
  final String? remarks;
  SavePeriodAttendanceStatus({
    required this.studentId,
    required this.classId,
    this.periodId,
    required this.periodNumber,
    required this.date,
    required this.status,
    this.time,
    this.remarks,
  });
}

class BulkUpdatePeriodAttendance extends AttendanceEvent {
  final String classId;
  final String? periodId;
  final int periodNumber;
  final String date;
  final String status;
  final List<String> studentIds;
  BulkUpdatePeriodAttendance({
    required this.classId,
    this.periodId,
    required this.periodNumber,
    required this.date,
    required this.status,
    required this.studentIds,
  });
}

class UpdateStudentFullAttendance extends AttendanceEvent {
  final String studentId;
  final String status;
  final String checkInTime;
  final String? checkOutTime;
  final String verificationMethod;
  UpdateStudentFullAttendance({
    required this.studentId,
    required this.status,
    required this.checkInTime,
    this.checkOutTime,
    required this.verificationMethod,
  });
}

class EnrollStudentBiometricData extends AttendanceEvent {
  final String studentId;
  final String biometricType;
  final String templateData;
  EnrollStudentBiometricData({
    required this.studentId,
    required this.biometricType,
    required this.templateData,
  });
}

class LoadStaffAttendance extends AttendanceEvent {
  final String date;
  LoadStaffAttendance({required this.date});
}

class UpdateStaffStatus extends AttendanceEvent {
  final String staffId;
  final String? status;
  UpdateStaffStatus({required this.staffId, this.status});
}

class UpdateStaffRemarks extends AttendanceEvent {
  final String staffId;
  final String remarks;
  UpdateStaffRemarks({required this.staffId, required this.remarks});
}

class UpdateStaffVerification extends AttendanceEvent {
  final String staffId;
  final String method;
  final String time;
  UpdateStaffVerification({
    required this.staffId,
    required this.method,
    required this.time,
  });
}

class SaveStaffAttendanceData extends AttendanceEvent {
  final String date;
  SaveStaffAttendanceData({required this.date});
}

/// Scan attendance for a person by their identifier (GR No, Staff No, etc.)
class ScanAttendance extends AttendanceEvent {
  final String scannedCode;
  final String date;
  ScanAttendance({required this.scannedCode, required this.date});
}

// ─── STATE (unified) ─────────────────────────────────────────────────────────
class AttendanceState {
  final bool studentLoading;
  final bool staffLoading;
  final bool periodLoading;
  final List<StudentAttendance> students;
  final List<StaffAttendance> staff;
  final List<PeriodAttendanceRecord> periodRecords;
  final String? error;

  // Transient flags (reset after one read)
  final bool studentSaved;
  final bool staffSaved;
  final bool periodSaved;
  final List<String> notifiedParents;
  final String? scanResult; // message after a scan

  const AttendanceState({
    this.studentLoading = false,
    this.staffLoading = false,
    this.periodLoading = false,
    this.students = const [],
    this.staff = const [],
    this.periodRecords = const [],
    this.error,
    this.studentSaved = false,
    this.staffSaved = false,
    this.periodSaved = false,
    this.notifiedParents = const [],
    this.scanResult,
  });

  AttendanceState copyWith({
    bool? studentLoading,
    bool? staffLoading,
    bool? periodLoading,
    List<StudentAttendance>? students,
    List<StaffAttendance>? staff,
    List<PeriodAttendanceRecord>? periodRecords,
    String? error,
    bool? studentSaved,
    bool? staffSaved,
    bool? periodSaved,
    List<String>? notifiedParents,
    String? scanResult,
  }) {
    return AttendanceState(
      studentLoading: studentLoading ?? this.studentLoading,
      staffLoading: staffLoading ?? this.staffLoading,
      periodLoading: periodLoading ?? this.periodLoading,
      students: students ?? this.students,
      staff: staff ?? this.staff,
      periodRecords: periodRecords ?? this.periodRecords,
      error: error,
      studentSaved: studentSaved ?? false,
      staffSaved: staffSaved ?? false,
      periodSaved: periodSaved ?? false,
      notifiedParents: notifiedParents ?? const [],
      scanResult: scanResult,
    );
  }
}

// ─── BLOC ────────────────────────────────────────────────────────────────────
class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final AttendanceRepository repository;

  AttendanceBloc({required this.repository}) : super(const AttendanceState()) {
    on<LoadStudentAttendance>(_onLoadStudentAttendance);
    on<UpdateStudentStatus>(_onUpdateStudentStatus);
    on<UpdateStudentRemarks>(_onUpdateStudentRemarks);
    on<SaveStudentAttendanceData>(_onSaveStudentAttendanceData);
    on<UpdateStudentVerification>(_onUpdateStudentVerification);
    on<BulkUpdateStudentStatus>(_onBulkUpdateStudentStatus);
    on<AutoSaveStudentStatus>(_onAutoSaveStudentStatus);
    on<UpdateStudentFullAttendance>(_onUpdateStudentFullAttendance);
    on<EnrollStudentBiometricData>(_onEnrollStudentBiometricData);

    on<LoadPeriodAttendance>(_onLoadPeriodAttendance);
    on<SavePeriodAttendanceStatus>(_onSavePeriodAttendanceStatus);
    on<BulkUpdatePeriodAttendance>(_onBulkUpdatePeriodAttendance);

    on<LoadStaffAttendance>(_onLoadStaffAttendance);
    on<UpdateStaffStatus>(_onUpdateStaffStatus);
    on<UpdateStaffRemarks>(_onUpdateStaffRemarks);
    on<UpdateStaffVerification>(_onUpdateStaffVerification);
    on<SaveStaffAttendanceData>(_onSaveStaffAttendanceData);

    on<ScanAttendance>(_onScanAttendance);
  }

  // ── Student handlers ────────────────────────────────────────────
  Future<void> _onLoadStudentAttendance(
    LoadStudentAttendance event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(studentLoading: true, error: null));
    try {
      final list = await repository.getStudentAttendance(
        className: event.className,
        date: event.date,
        shiftId: event.shiftId,
      );
      emit(state.copyWith(studentLoading: false, students: list));
    } catch (e) {
      emit(state.copyWith(studentLoading: false, error: e.toString()));
    }
  }

  void _onUpdateStudentStatus(
    UpdateStudentStatus event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StudentAttendance>.from(state.students);
    final idx = updated.indexWhere((s) => s.id == event.studentId);
    if (idx != -1) {
      updated[idx].status = event.status;
      if (event.status == 'Present' || event.status == 'Late') {
        if (updated[idx].checkInTime.isEmpty) {
          updated[idx].checkInTime = DateFormat('hh:mm:ss a').format(DateTime.now());
        }
      } else if (event.status == 'Absent') {
        updated[idx].checkInTime = '';
        updated[idx].checkOutTime = '';
      }
      emit(state.copyWith(students: updated));
    }
  }

  void _onUpdateStudentRemarks(
    UpdateStudentRemarks event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StudentAttendance>.from(state.students);
    final idx = updated.indexWhere((s) => s.id == event.studentId);
    if (idx != -1) {
      updated[idx].remarks = event.remarks;
      emit(state.copyWith(students: updated));
    }
  }

  void _onUpdateStudentVerification(
    UpdateStudentVerification event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StudentAttendance>.from(state.students);
    final idx = updated.indexWhere((s) => s.id == event.studentId);
    if (idx != -1) {
      if (updated[idx].checkInTime.isNotEmpty) {
        updated[idx].checkOutTime = event.time;
      } else {
        updated[idx].checkInTime = event.time;
        updated[idx].status = 'Present';
      }
      emit(state.copyWith(students: updated));
    }
  }

  Future<void> _onBulkUpdateStudentStatus(
    BulkUpdateStudentStatus event,
    Emitter<AttendanceState> emit,
  ) async {
    final updated = List<StudentAttendance>.from(state.students);
    final nowStr = DateFormat('hh:mm:ss a').format(DateTime.now());

    for (int i = 0; i < updated.length; i++) {
      final s = updated[i];
      if (event.studentIds.isEmpty || event.studentIds.contains(s.id)) {
        s.status = event.status;
        if (event.shiftId != null) s.shiftId = event.shiftId!;
        if (event.shiftName != null) s.shiftName = event.shiftName!;
        if (event.status == 'Present' || event.status == 'Late') {
          if (event.timeMode == 'in_only') {
            if (s.checkInTime.isEmpty) s.checkInTime = nowStr;
          } else if (event.timeMode == 'out_only') {
            s.checkOutTime = nowStr;
          } else if (event.timeMode == 'both') {
            if (s.checkInTime.isEmpty) {
              s.checkInTime = nowStr;
            } else if (s.checkOutTime.isEmpty) {
              s.checkOutTime = nowStr;
            }
          }
          if (s.verificationMethod.isEmpty) {
            s.verificationMethod = 'Bulk';
          }
        } else if (event.status == 'Absent' || event.status.isEmpty) {
          s.checkInTime = '';
          s.checkOutTime = '';
          s.verificationMethod = event.status.isEmpty ? '' : 'Bulk';
        }
      }
    }

    emit(state.copyWith(students: updated));

    if (event.autoSave && event.className != null && event.className!.isNotEmpty) {
      try {
        await repository.saveStudentAttendance(
          className: event.className!,
          date: event.date,
          attendanceList: updated,
          shiftId: event.shiftId,
          shiftName: event.shiftName,
        );
      } catch (_) {}
    }
  }

  Future<void> _onAutoSaveStudentStatus(
    AutoSaveStudentStatus event,
    Emitter<AttendanceState> emit,
  ) async {
    final updated = List<StudentAttendance>.from(state.students);
    final idx = updated.indexWhere((s) => s.id == event.studentId);
    if (idx != -1) {
      updated[idx].status = event.status;
      if (event.shiftId != null) updated[idx].shiftId = event.shiftId!;
      if (event.shiftName != null) updated[idx].shiftName = event.shiftName!;
      if (event.status == 'Present' || event.status == 'Late') {
        if (event.checkInTime != null) {
          updated[idx].checkInTime = event.checkInTime!;
        }
        if (event.checkOutTime != null) {
          updated[idx].checkOutTime = event.checkOutTime!;
        }
        updated[idx].verificationMethod = event.verificationMethod;
      } else if (event.status == 'Absent' || event.status.isEmpty) {
        updated[idx].checkInTime = '';
        updated[idx].checkOutTime = '';
        updated[idx].verificationMethod = event.status.isEmpty ? '' : event.verificationMethod;
      }
      emit(state.copyWith(students: updated));
    }

    try {
      final s = idx != -1 ? updated[idx] : null;
      await repository.saveSingleStudentAttendance(
        studentId: event.studentId,
        date: event.date,
        status: event.status,
        checkInTime: event.checkInTime ?? s?.checkInTime,
        checkOutTime: event.checkOutTime ?? s?.checkOutTime,
        remarks: event.remarks ?? s?.remarks,
        verificationMethod: event.verificationMethod,
        shiftId: event.shiftId ?? s?.shiftId,
        shiftName: event.shiftName ?? s?.shiftName,
      );
    } catch (_) {}
  }

  // ── Period Attendance Handlers ──────────────────────────────────
  Future<void> _onLoadPeriodAttendance(
    LoadPeriodAttendance event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(periodLoading: true, error: null));
    try {
      final list = await repository.getPeriodAttendance(
        className: event.className,
        date: event.date,
        periodNumber: event.periodNumber,
      );
      emit(state.copyWith(periodLoading: false, periodRecords: list));
    } catch (e) {
      emit(state.copyWith(periodLoading: false, error: e.toString()));
    }
  }

  Future<void> _onSavePeriodAttendanceStatus(
    SavePeriodAttendanceStatus event,
    Emitter<AttendanceState> emit,
  ) async {
    final updated = List<PeriodAttendanceRecord>.from(state.periodRecords);
    final nowTime = event.time ?? DateFormat('hh:mm:ss a').format(DateTime.now());
    final idx = updated.indexWhere((r) => r.studentId == event.studentId);
    if (idx != -1) {
      updated[idx] = updated[idx].copyWith(
        status: event.status,
        time: nowTime,
        remarks: event.remarks,
      );
    } else {
      updated.add(PeriodAttendanceRecord(
        studentId: event.studentId,
        classId: event.classId,
        periodId: event.periodId,
        periodNumber: event.periodNumber,
        date: event.date,
        status: event.status,
        time: nowTime,
        remarks: event.remarks ?? '',
      ));
    }
    emit(state.copyWith(periodRecords: updated));

    try {
      await repository.saveSinglePeriodAttendance(
        studentId: event.studentId,
        classId: event.classId,
        periodId: event.periodId,
        periodNumber: event.periodNumber,
        date: event.date,
        status: event.status,
        time: nowTime,
        remarks: event.remarks,
      );
    } catch (_) {}
  }

  Future<void> _onBulkUpdatePeriodAttendance(
    BulkUpdatePeriodAttendance event,
    Emitter<AttendanceState> emit,
  ) async {
    final nowTime = DateFormat('hh:mm:ss a').format(DateTime.now());
    final updated = List<PeriodAttendanceRecord>.from(state.periodRecords);

    for (final sId in event.studentIds) {
      final idx = updated.indexWhere((r) => r.studentId == sId);
      if (idx != -1) {
        updated[idx] = updated[idx].copyWith(
          status: event.status,
          time: nowTime,
        );
      } else {
        updated.add(PeriodAttendanceRecord(
          studentId: sId,
          classId: event.classId,
          periodId: event.periodId,
          periodNumber: event.periodNumber,
          date: event.date,
          status: event.status,
          time: nowTime,
        ));
      }
    }
    emit(state.copyWith(periodRecords: updated));

    try {
      await repository.bulkPeriodAttendance(
        classId: event.classId,
        periodId: event.periodId,
        periodNumber: event.periodNumber,
        date: event.date,
        status: event.status,
        studentIds: event.studentIds,
      );
    } catch (_) {}
  }

  void _onUpdateStudentFullAttendance(
    UpdateStudentFullAttendance event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StudentAttendance>.from(state.students);
    final idx = updated.indexWhere((s) => s.id == event.studentId);
    if (idx != -1) {
      updated[idx].status = event.status;
      updated[idx].checkInTime = event.checkInTime;
      if (event.checkOutTime != null) {
        updated[idx].checkOutTime = event.checkOutTime!;
      }
      updated[idx].verificationMethod = event.verificationMethod;
      emit(state.copyWith(students: updated));
    }
  }

  Future<void> _onEnrollStudentBiometricData(
    EnrollStudentBiometricData event,
    Emitter<AttendanceState> emit,
  ) async {
    final updated = List<StudentAttendance>.from(state.students);
    final idx = updated.indexWhere((s) => s.id == event.studentId);
    if (idx != -1) {
      if (event.biometricType == 'Face') {
        updated[idx].hasFaceEnrolled = true;
        updated[idx].faceData = event.templateData;
      } else {
        updated[idx].hasFingerprintEnrolled = true;
        updated[idx].fingerprintData = event.templateData;
      }
      emit(state.copyWith(students: updated));
    }
    try {
      await repository.enrollStudentBiometric(
        studentId: event.studentId,
        biometricType: event.biometricType,
        templateData: event.templateData,
      );
    } catch (_) {}
  }

  Future<void> _onSaveStudentAttendanceData(
    SaveStudentAttendanceData event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(studentLoading: true, error: null));
    try {
      await repository.saveStudentAttendance(
        className: event.className,
        date: event.date,
        attendanceList: state.students,
        shiftId: event.shiftId,
        shiftName: event.shiftName,
      );

      final notified = <String>[];
      for (final s in state.students) {
        if (s.status == 'Absent' || s.status == 'Late') {
          notified.add(s.fullName);
        }
      }

      emit(
        state.copyWith(
          studentLoading: false,
          studentSaved: true,
          notifiedParents: notified,
        ),
      );
    } catch (e) {
      emit(state.copyWith(studentLoading: false, error: e.toString()));
    }
  }

  // ── Staff handlers ──────────────────────────────────────────────
  Future<void> _onLoadStaffAttendance(
    LoadStaffAttendance event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(staffLoading: true, error: null));
    try {
      final list = await repository.getStaffAttendance(date: event.date);
      emit(state.copyWith(staffLoading: false, staff: list));
    } catch (e) {
      emit(state.copyWith(staffLoading: false, error: e.toString()));
    }
  }

  void _onUpdateStaffStatus(
    UpdateStaffStatus event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StaffAttendance>.from(state.staff);
    final idx = updated.indexWhere((s) => s.id == event.staffId);
    if (idx != -1) {
      updated[idx].status = event.status;
      if (event.status == 'Absent') {
        updated[idx].checkInTime = '';
        updated[idx].checkOutTime = '';
      }
      emit(state.copyWith(staff: updated));
    }
  }

  void _onUpdateStaffRemarks(
    UpdateStaffRemarks event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StaffAttendance>.from(state.staff);
    final idx = updated.indexWhere((s) => s.id == event.staffId);
    if (idx != -1) {
      updated[idx].remarks = event.remarks;
      emit(state.copyWith(staff: updated));
    }
  }

  void _onUpdateStaffVerification(
    UpdateStaffVerification event,
    Emitter<AttendanceState> emit,
  ) {
    final updated = List<StaffAttendance>.from(state.staff);
    final idx = updated.indexWhere((s) => s.id == event.staffId);
    if (idx != -1) {
      if (updated[idx].checkInTime.isNotEmpty) {
        updated[idx].checkOutTime = event.time;
      } else {
        updated[idx].verificationMethod = event.method;
        updated[idx].checkInTime = event.time;
        updated[idx].status = 'Present';
      }
      emit(state.copyWith(staff: updated));
    }
  }

  Future<void> _onSaveStaffAttendanceData(
    SaveStaffAttendanceData event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(staffLoading: true, error: null));
    try {
      await repository.saveStaffAttendance(
        date: event.date,
        attendanceList: state.staff,
      );
      emit(state.copyWith(staffLoading: false, staffSaved: true));
    } catch (e) {
      emit(state.copyWith(staffLoading: false, error: e.toString()));
    }
  }

  // ── Scan handler ────────────────────────────────────────────────
  Future<void> _onScanAttendance(
    ScanAttendance event,
    Emitter<AttendanceState> emit,
  ) async {
    final code = event.scannedCode.trim();
    if (code.isEmpty) return;

    try {
      final result = await repository.scanAttendance(code);
      final name = result['name'] ?? '';
      final type = result['type'] ?? '';
      final date = result['date'] ?? '';
      final time = result['time'] ?? '';
      final scanType = result['scanType'] ?? 'IN';
      final attendanceStatus = result['attendanceStatus'] ?? 'Present';

      final msg = '✅ $type "$name" $scanType at $time on $date ($attendanceStatus)';

      if (type == 'Student') {
        final updated = List<StudentAttendance>.from(state.students);
        String actualCode = code;
        if (code.startsWith('STU:')) {
          actualCode = code.substring(4);
        }
        final idx = updated.indexWhere(
          (s) =>
              s.grNo == actualCode ||
              s.registrationNumber == actualCode ||
              s.fullName.toLowerCase() == actualCode.toLowerCase(),
        );
        if (idx != -1) {
          if (scanType == 'OUT') {
            updated[idx].checkOutTime = time;
            updated[idx].status = attendanceStatus;
            if (updated[idx].checkInTime.isEmpty) {
              updated[idx].checkInTime = time;
            }
          } else {
            updated[idx].status = attendanceStatus;
            updated[idx].checkInTime = time;
          }
        }
        emit(state.copyWith(students: updated, scanResult: msg));
      } else {
        final updated = List<StaffAttendance>.from(state.staff);
        String actualCode = code;
        if (code.startsWith('STF:')) {
          actualCode = code.substring(4);
        }
        final idx = updated.indexWhere(
          (s) =>
              s.staffNo == actualCode ||
              s.fullName.toLowerCase() == actualCode.toLowerCase(),
        );
        if (idx != -1) {
          if (scanType == 'OUT') {
            updated[idx].checkOutTime = time;
            updated[idx].status = attendanceStatus;
            if (updated[idx].checkInTime.isEmpty) {
              updated[idx].checkInTime = time;
            }
          } else {
            updated[idx].status = attendanceStatus;
            updated[idx].checkInTime = time;
            updated[idx].verificationMethod = 'Mobile';
          }
        }
        emit(state.copyWith(staff: updated, scanResult: msg));
      }
    } catch (e) {
      String errMsg = 'No student or staff member found for code: "$code"';
      if (!e.toString().contains('404')) {
        errMsg = 'Scan failed: ${e.toString()}';
      }
      emit(state.copyWith(scanResult: '❌ $errMsg'));
    }
  }
}
